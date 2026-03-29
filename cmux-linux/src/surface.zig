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
};
