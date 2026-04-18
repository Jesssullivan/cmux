/// Terminal surface: embeds a libghostty surface in a GtkGLArea widget.
///
/// Handles OpenGL rendering, input forwarding, and resize events.
/// Reference: ghostty/src/apprt/gtk/Surface.zig
const std = @import("std");
const c = @import("c_api.zig");

/// State for a single terminal surface.
pub const Surface = struct {
    /// The libghostty surface handle.
    ghostty_surface: c.ghostty_surface_t = null,
    /// The GtkGLArea widget.
    gl_area: ?*c.GtkGLArea = null,
    /// The parent ghostty app.
    ghostty_app: c.ghostty_app_t = null,

    /// Create a new terminal surface embedded in a GtkGLArea.
    pub fn create(app: c.ghostty_app_t) !*c.GtkWidget {
        const gl_area: *c.GtkGLArea = @ptrCast(c.gtk.gtk_gl_area_new() orelse
            return error.WidgetCreationFailed);

        // Set OpenGL requirements
        c.gtk.gtk_gl_area_set_required_version(gl_area, 3, 3);
        c.gtk.gtk_gl_area_set_has_depth_buffer(gl_area, 0);
        c.gtk.gtk_gl_area_set_has_stencil_buffer(gl_area, 0);
        c.gtk.gtk_gl_area_set_auto_render(gl_area, 0);

        // Make it focusable for keyboard input
        c.gtk.gtk_widget_set_focusable(@ptrCast(@alignCast(gl_area)), 1);
        c.gtk.gtk_widget_set_can_focus(@ptrCast(@alignCast(gl_area)), 1);

        // Set expand to fill available space
        c.gtk.gtk_widget_set_hexpand(@ptrCast(@alignCast(gl_area)), 1);
        c.gtk.gtk_widget_set_vexpand(@ptrCast(@alignCast(gl_area)), 1);

        // Allocate surface state
        const alloc = std.heap.c_allocator;
        const surface = try alloc.create(Surface);
        surface.* = .{
            .ghostty_app = app,
            .gl_area = gl_area,
        };

        // Store surface pointer as widget data
        c.gtk.g_object_set_data(@ptrCast(@alignCast(gl_area)), "cmux-surface", surface);

        // Connect signals
        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(gl_area)),
            "realize",
            @ptrCast(&onRealize),
            surface,
            null,
            0,
        );

        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(gl_area)),
            "render",
            @ptrCast(&onRender),
            surface,
            null,
            0,
        );

        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(gl_area)),
            "resize",
            @ptrCast(&onResize),
            surface,
            null,
            0,
        );

        // --- Input event controllers ---

        const widget: *c.GtkWidget = @ptrCast(@alignCast(gl_area));

        // Keyboard: key-pressed / key-released
        const key_ctrl = c.gtk.gtk_event_controller_key_new();
        c.gtk.gtk_widget_add_controller(widget, key_ctrl);
        _ = c.gtk.g_signal_connect_data(key_ctrl, "key-pressed", @ptrCast(&onKeyPressed), surface, null, 0);
        _ = c.gtk.g_signal_connect_data(key_ctrl, "key-released", @ptrCast(&onKeyReleased), surface, null, 0);

        // Mouse motion
        const motion_ctrl = c.gtk.gtk_event_controller_motion_new();
        c.gtk.gtk_widget_add_controller(widget, motion_ctrl);
        _ = c.gtk.g_signal_connect_data(motion_ctrl, "motion", @ptrCast(&onMouseMotion), surface, null, 0);

        // Mouse buttons (click)
        const click_gesture = c.gtk.gtk_gesture_click_new();
        c.gtk.gtk_gesture_single_set_button(@ptrCast(click_gesture), 0); // all buttons
        c.gtk.gtk_widget_add_controller(widget, @ptrCast(click_gesture));
        _ = c.gtk.g_signal_connect_data(@ptrCast(click_gesture), "pressed", @ptrCast(&onMousePressed), surface, null, 0);
        _ = c.gtk.g_signal_connect_data(@ptrCast(click_gesture), "released", @ptrCast(&onMouseReleased), surface, null, 0);

        // Scroll
        const scroll_ctrl = c.gtk.gtk_event_controller_scroll_new(
            c.gtk.GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES | c.gtk.GTK_EVENT_CONTROLLER_SCROLL_DISCRETE,
        );
        c.gtk.gtk_widget_add_controller(widget, scroll_ctrl);
        _ = c.gtk.g_signal_connect_data(scroll_ctrl, "scroll", @ptrCast(&onScroll), surface, null, 0);

        // Focus in/out
        const focus_ctrl = c.gtk.gtk_event_controller_focus_new();
        c.gtk.gtk_widget_add_controller(widget, focus_ctrl);
        _ = c.gtk.g_signal_connect_data(focus_ctrl, "enter", @ptrCast(&onFocusEnter), surface, null, 0);
        _ = c.gtk.g_signal_connect_data(focus_ctrl, "leave", @ptrCast(&onFocusLeave), surface, null, 0);

        return @ptrCast(@alignCast(gl_area));
    }

    /// Called when the GtkGLArea is realized (OpenGL context available).
    fn onRealize(_: *c.GtkGLArea, surface: *Surface) callconv(.c) void {
        const gl_area = surface.gl_area orelse return;
        c.gtk.gtk_gl_area_make_current(gl_area);

        // Get content scale from the GDK surface
        const native = c.gtk.gtk_native_get_surface(
            @ptrCast(c.gtk.gtk_widget_get_native(@ptrCast(@alignCast(gl_area)))),
        );
        const scale: f64 = if (native != null)
            @floatFromInt(c.gtk.gdk_surface_get_scale_factor(native))
        else
            1.0;

        // Create the ghostty surface with linux platform config
        var surface_config = c.ghostty.ghostty_surface_config_new();
        surface_config.platform_tag = c.ghostty.GHOSTTY_PLATFORM_LINUX;
        surface_config.platform = .{ .linux = .{
            .surface = @ptrCast(@alignCast(gl_area)),
        } };
        surface_config.scale_factor = scale;

        // Pass the GtkWidget pointer as surface userdata so the
        // close_surface_cb can identify which panel to remove.
        surface_config.userdata = @ptrCast(@alignCast(gl_area));

        surface.ghostty_surface = c.ghostty.ghostty_surface_new(
            surface.ghostty_app,
            &surface_config,
        );

        if (surface.ghostty_surface == null) {
            std.log.err("Failed to create ghostty surface", .{});
        }
    }

    /// Called on each OpenGL render frame.
    fn onRender(_: *c.GtkGLArea, _: ?*anyopaque, surface: *Surface) callconv(.c) c.gtk.gboolean {
        if (surface.ghostty_surface) |s| {
            c.ghostty.ghostty_surface_draw(s);
        }
        return c.gtk.G_SOURCE_REMOVE; // We handle rendering
    }

    /// Called when the GtkGLArea is resized.
    fn onResize(_: *c.GtkGLArea, width: c_int, height: c_int, surface: *Surface) callconv(.c) void {
        if (surface.ghostty_surface) |s| {
            c.ghostty.ghostty_surface_set_size(
                s,
                @intCast(width),
                @intCast(height),
            );
        }
    }

    // ── Keyboard input ──────────────────────────────────────────────

    /// GtkEventControllerKey "key-pressed" signal.
    fn onKeyPressed(
        _: ?*anyopaque,
        keyval: c_uint,
        keycode: c_uint,
        state: c_uint,
        surface: *Surface,
    ) callconv(.c) c.gtk.gboolean {
        return @intFromBool(surface.handleKey(c.ghostty.GHOSTTY_ACTION_PRESS, keyval, keycode, state));
    }

    /// GtkEventControllerKey "key-released" signal.
    fn onKeyReleased(
        _: ?*anyopaque,
        keyval: c_uint,
        keycode: c_uint,
        state: c_uint,
        surface: *Surface,
    ) callconv(.c) void {
        _ = surface.handleKey(c.ghostty.GHOSTTY_ACTION_RELEASE, keyval, keycode, state);
    }

    /// Common keyboard handler: translate GDK key event → ghostty_input_key_s.
    fn handleKey(surface: *Surface, action: c_int, keyval: c_uint, keycode: c_uint, state: c_uint) bool {
        const s = surface.ghostty_surface orelse return false;

        // Convert GDK modifier state to ghostty mods
        const mods = gtkModsToGhostty(state);

        // Build key input struct. The keycode from GTK4 is the hardware
        // scancode (evdev code), which ghostty uses directly. The text
        // is derived from the GDK keyval for printable characters.
        var text_buf: [8]u8 = undefined;
        var text_ptr: [*c]const u8 = null;
        var text_len: usize = 0;

        // Only send text for press/repeat, not release
        if (action != c.ghostty.GHOSTTY_ACTION_RELEASE) {
            const uc = c.gtk.gdk_keyval_to_unicode(keyval);
            if (uc > 0 and uc != 0xFFFF) {
                text_len = std.unicode.utf8Encode(@intCast(uc), &text_buf) catch 0;
                if (text_len > 0) {
                    text_buf[text_len] = 0; // null-terminate
                    text_ptr = &text_buf;
                }
            }
        }

        // Get the unshifted codepoint (keyval without shift modifier)
        const unshifted_codepoint = c.gtk.gdk_keyval_to_unicode(
            c.gtk.gdk_keyval_to_lower(keyval),
        );

        const key_event = c.ghostty.ghostty_input_key_s{
            .action = @intCast(action),
            .mods = mods,
            .consumed_mods = c.ghostty.GHOSTTY_MODS_NONE,
            .keycode = keycode,
            .text = text_ptr,
            .unshifted_codepoint = unshifted_codepoint,
            .composing = false,
        };

        return c.ghostty.ghostty_surface_key(s, key_event);
    }

    // ── Mouse input ─────────────────────────────────────────────────

    /// GtkGestureClick "pressed" signal.
    fn onMousePressed(
        gesture: ?*anyopaque,
        _: c_int, // n_press
        x: f64,
        y: f64,
        surface: *Surface,
    ) callconv(.c) void {
        const s = surface.ghostty_surface orelse return;

        // Grab focus on click
        if (surface.gl_area) |gl| {
            _ = c.gtk.gtk_widget_grab_focus(@ptrCast(@alignCast(gl)));
        }

        const button = gtkButtonToGhostty(c.gtk.gtk_gesture_single_get_current_button(@ptrCast(gesture)));
        const event = c.gtk.gtk_event_controller_get_current_event(@ptrCast(gesture));
        const mods = gtkModsToGhostty(if (event != null) c.gtk.gdk_event_get_modifier_state(event) else 0);

        // Send position first, then button press
        c.ghostty.ghostty_surface_mouse_pos(s, x, y, mods);
        _ = c.ghostty.ghostty_surface_mouse_button(s, c.ghostty.GHOSTTY_MOUSE_PRESS, button, mods);
    }

    /// GtkGestureClick "released" signal.
    fn onMouseReleased(
        gesture: ?*anyopaque,
        _: c_int, // n_press
        x: f64,
        y: f64,
        surface: *Surface,
    ) callconv(.c) void {
        const s = surface.ghostty_surface orelse return;
        const button = gtkButtonToGhostty(c.gtk.gtk_gesture_single_get_current_button(@ptrCast(gesture)));
        const event = c.gtk.gtk_event_controller_get_current_event(@ptrCast(gesture));
        const mods = gtkModsToGhostty(if (event != null) c.gtk.gdk_event_get_modifier_state(event) else 0);

        c.ghostty.ghostty_surface_mouse_pos(s, x, y, mods);
        _ = c.ghostty.ghostty_surface_mouse_button(s, c.ghostty.GHOSTTY_MOUSE_RELEASE, button, mods);
    }

    /// GtkEventControllerMotion "motion" signal.
    fn onMouseMotion(
        controller: ?*anyopaque,
        x: f64,
        y: f64,
        surface: *Surface,
    ) callconv(.c) void {
        const s = surface.ghostty_surface orelse return;
        const event = c.gtk.gtk_event_controller_get_current_event(@ptrCast(controller));
        const mods = gtkModsToGhostty(if (event != null) c.gtk.gdk_event_get_modifier_state(event) else 0);
        c.ghostty.ghostty_surface_mouse_pos(s, x, y, mods);
    }

    /// GtkEventControllerScroll "scroll" signal.
    fn onScroll(
        controller: ?*anyopaque,
        dx: f64,
        dy: f64,
        surface: *Surface,
    ) callconv(.c) c.gtk.gboolean {
        const s = surface.ghostty_surface orelse return 0;
        const event = c.gtk.gtk_event_controller_get_current_event(@ptrCast(controller));
        const mods_raw = if (event != null) c.gtk.gdk_event_get_modifier_state(event) else @as(c_uint, 0);

        // ghostty_input_scroll_mods_t is a packed int: lower bits are mods
        const scroll_mods: c.ghostty.ghostty_input_scroll_mods_t = @intCast(gtkModsToGhostty(mods_raw));
        c.ghostty.ghostty_surface_mouse_scroll(s, dx, dy, scroll_mods);
        return 1; // handled
    }

    // ── Focus ───────────────────────────────────────────────────────

    /// GtkEventControllerFocus "enter" signal.
    fn onFocusEnter(_: ?*anyopaque, surface: *Surface) callconv(.c) void {
        if (surface.ghostty_surface) |s| {
            c.ghostty.ghostty_surface_set_focus(s, true);
        }
    }

    /// GtkEventControllerFocus "leave" signal.
    fn onFocusLeave(_: ?*anyopaque, surface: *Surface) callconv(.c) void {
        if (surface.ghostty_surface) |s| {
            c.ghostty.ghostty_surface_set_focus(s, false);
        }
    }
};

// ── Shared helpers ──────────────────────────────────────────────────

/// Translate GDK modifier state bitmask to ghostty modifier bitmask.
fn gtkModsToGhostty(state: c_uint) c.ghostty.ghostty_input_mods_e {
    var mods: c_int = c.ghostty.GHOSTTY_MODS_NONE;
    if (state & c.gtk.GDK_SHIFT_MASK != 0) mods |= c.ghostty.GHOSTTY_MODS_SHIFT;
    if (state & c.gtk.GDK_CONTROL_MASK != 0) mods |= c.ghostty.GHOSTTY_MODS_CTRL;
    if (state & c.gtk.GDK_ALT_MASK != 0) mods |= c.ghostty.GHOSTTY_MODS_ALT;
    if (state & c.gtk.GDK_SUPER_MASK != 0) mods |= c.ghostty.GHOSTTY_MODS_SUPER;
    if (state & c.gtk.GDK_LOCK_MASK != 0) mods |= c.ghostty.GHOSTTY_MODS_CAPS;
    return @intCast(mods);
}

/// Translate GDK button number (1=left, 2=middle, 3=right) to ghostty button.
fn gtkButtonToGhostty(button: c_uint) c.ghostty.ghostty_input_mouse_button_e {
    return switch (button) {
        1 => c.ghostty.GHOSTTY_MOUSE_LEFT,
        2 => c.ghostty.GHOSTTY_MOUSE_MIDDLE,
        3 => c.ghostty.GHOSTTY_MOUSE_RIGHT,
        4 => c.ghostty.GHOSTTY_MOUSE_FOUR,
        5 => c.ghostty.GHOSTTY_MOUSE_FIVE,
        6 => c.ghostty.GHOSTTY_MOUSE_SIX,
        7 => c.ghostty.GHOSTTY_MOUSE_SEVEN,
        8 => c.ghostty.GHOSTTY_MOUSE_EIGHT,
        else => c.ghostty.GHOSTTY_MOUSE_UNKNOWN,
    };
}

/// Get the Surface wrapper from a GtkWidget (if it's a terminal panel).
pub fn fromWidget(widget: *c.GtkWidget) ?*Surface {
    const data = c.gtk.g_object_get_data(@ptrCast(@alignCast(widget)), "cmux-surface");
    if (data) |d| return @ptrCast(@alignCast(d));
    return null;
}
