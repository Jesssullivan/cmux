/// libghostty runtime callbacks.
///
/// These functions are called by libghostty when it needs the host
/// application to perform actions (clipboard, new tabs, close, etc.).
const std = @import("std");
const c = @import("c_api.zig");
const window = @import("window.zig");
const main_mod = @import("main.zig");
const split_tree = @import("split_tree.zig");

const log = std.log.scoped(.app);

/// Action callback: libghostty requests the host perform an action.
/// Returns true if handled, false to let libghostty handle it.
pub fn onAction(
    _: c.ghostty_app_t,
    target: c.ghostty.ghostty_target_s,
    action: c.ghostty.ghostty_action_s,
) callconv(.c) bool {
    return switch (action.tag) {
        c.ghostty.GHOSTTY_ACTION_SET_TITLE => handleSetTitle(target, action.action.set_title),
        c.ghostty.GHOSTTY_ACTION_PWD => handlePwd(target, action.action.pwd),
        c.ghostty.GHOSTTY_ACTION_NEW_TAB => handleNewTab(),
        c.ghostty.GHOSTTY_ACTION_NEW_WINDOW => handleNewTab(),
        c.ghostty.GHOSTTY_ACTION_GOTO_TAB => handleGotoTab(action.action.goto_tab),
        c.ghostty.GHOSTTY_ACTION_CLOSE_TAB => handleCloseTab(),
        c.ghostty.GHOSTTY_ACTION_DESKTOP_NOTIFICATION => handleDesktopNotification(action.action.desktop_notification),
        c.ghostty.GHOSTTY_ACTION_OPEN_URL => handleOpenUrl(action.action.open_url),
        c.ghostty.GHOSTTY_ACTION_TOGGLE_FULLSCREEN => handleToggleFullscreen(),
        c.ghostty.GHOSTTY_ACTION_RING_BELL => handleBell(target),
        c.ghostty.GHOSTTY_ACTION_RENDER => handleRender(target),
        c.ghostty.GHOSTTY_ACTION_MOUSE_SHAPE => handleMouseShape(target, action.action.mouse_shape),
        c.ghostty.GHOSTTY_ACTION_MOUSE_VISIBILITY => handleMouseVisibility(target, action.action.mouse_visibility),
        c.ghostty.GHOSTTY_ACTION_CLOSE_WINDOW => handleCloseWindow(),
        c.ghostty.GHOSTTY_ACTION_CLOSE_ALL_WINDOWS => handleCloseAllWindows(),
        c.ghostty.GHOSTTY_ACTION_QUIT => handleQuit(),
        c.ghostty.GHOSTTY_ACTION_TOGGLE_MAXIMIZE => handleToggleMaximize(),
        c.ghostty.GHOSTTY_ACTION_SET_TAB_TITLE => handleSetTitle(target, action.action.set_tab_title),
        c.ghostty.GHOSTTY_ACTION_SHOW_CHILD_EXITED => handleChildExited(target, action.action.child_exited),
        c.ghostty.GHOSTTY_ACTION_RENDERER_HEALTH => handleRendererHealth(action.action.renderer_health),
        c.ghostty.GHOSTTY_ACTION_COLOR_CHANGE => handleColorChange(action.action.color_change),
        c.ghostty.GHOSTTY_ACTION_RELOAD_CONFIG => handleReloadConfig(action.action.reload_config),
        c.ghostty.GHOSTTY_ACTION_CONFIG_CHANGE => handleConfigChange(action.action.config_change),
        c.ghostty.GHOSTTY_ACTION_NEW_SPLIT => handleNewSplit(action.action.new_split),
        c.ghostty.GHOSTTY_ACTION_GOTO_SPLIT => handleGotoSplit(action.action.goto_split),
        c.ghostty.GHOSTTY_ACTION_RESIZE_SPLIT => handleResizeSplit(action.action.resize_split),
        c.ghostty.GHOSTTY_ACTION_EQUALIZE_SPLITS => handleEqualizeSplits(),
        c.ghostty.GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM => handleToggleSplitZoom(),
        else => false,
    };
}

/// Update the panel/workspace title from terminal escape sequences.
fn handleSetTitle(target: c.ghostty.ghostty_target_s, title: c.ghostty.ghostty_action_set_title_s) bool {
    const tm = window.getTabManager() orelse return false;
    const title_str = if (title.title) |t| std.mem.span(t) else return false;

    // Find the surface from target and update its workspace title.
    const surface_ud = getSurfaceUserdata(target) orelse return false;
    const widget: *c.GtkWidget = @ptrCast(@alignCast(surface_ud));

    for (tm.workspaces.items) |ws| {
        var it = ws.panels.valueIterator();
        while (it.next()) |panel_ptr| {
            const panel = panel_ptr.*;
            if (panel.widget) |pw| {
                if (pw == widget) {
                    // Set panel title
                    panel.title = ws.alloc.dupe(u8, title_str) catch null;
                    // If no custom workspace title, propagate to workspace
                    if (ws.custom_title == null) {
                        ws.setTitle(title_str);
                        tm.updateTabTitle(ws);
                    }
                    return true;
                }
            }
        }
    }
    return false;
}

/// Update the workspace's current directory from shell integration.
fn handlePwd(target: c.ghostty.ghostty_target_s, pwd: c.ghostty.ghostty_action_pwd_s) bool {
    const tm = window.getTabManager() orelse return false;
    const pwd_str = if (pwd.pwd) |p| std.mem.span(p) else return false;

    const surface_ud = getSurfaceUserdata(target) orelse return false;
    const widget: *c.GtkWidget = @ptrCast(@alignCast(surface_ud));

    for (tm.workspaces.items) |ws| {
        var it = ws.panels.valueIterator();
        while (it.next()) |panel_ptr| {
            const panel = panel_ptr.*;
            if (panel.widget) |pw| {
                if (pw == widget) {
                    panel.directory = ws.alloc.dupe(u8, pwd_str) catch null;
                    ws.current_directory = ws.alloc.dupe(u8, pwd_str) catch null;
                    return true;
                }
            }
        }
    }
    return false;
}

/// Create a new workspace (tab).
fn handleNewTab() bool {
    const tm = window.getTabManager() orelse return false;
    _ = tm.createWorkspace() catch |err| {
        log.err("Failed to create workspace: {}", .{err});
        return false;
    };
    if (window.getSidebar()) |sb| sb.refresh();
    return true;
}

/// Navigate between tabs (previous, next, last, or direct index).
fn handleGotoTab(goto: c.ghostty.ghostty_action_goto_tab_e) bool {
    const tm = window.getTabManager() orelse return false;
    const count = tm.count();
    if (count == 0) return false;
    const current = tm.selected_index orelse 0;

    const target_idx: usize = switch (goto) {
        c.ghostty.GHOSTTY_GOTO_TAB_PREVIOUS => if (current > 0) current - 1 else count - 1,
        c.ghostty.GHOSTTY_GOTO_TAB_NEXT => if (current + 1 < count) current + 1 else 0,
        c.ghostty.GHOSTTY_GOTO_TAB_LAST => count - 1,
        // Positive values are 1-based tab indices from ghostty.
        // The C enum is translated as c_int; cast to isize directly.
        else => blk: {
            const raw: isize = @intCast(goto);
            if (raw < 1) break :blk current;
            const idx: usize = @intCast(raw - 1);
            break :blk if (idx < count) idx else count - 1;
        },
    };

    tm.selectWorkspace(target_idx);
    if (window.getSidebar()) |sb| sb.refresh();
    return true;
}

/// Close the current workspace (tab).
fn handleCloseTab() bool {
    const tm = window.getTabManager() orelse return false;
    const idx = tm.selected_index orelse return false;
    // Don't close the last workspace — keep at least one
    if (tm.count() <= 1) return false;
    tm.closeWorkspace(idx);
    if (window.getSidebar()) |sb| sb.refresh();
    return true;
}

/// Forward a desktop notification from the terminal (OSC 9/99).
fn handleDesktopNotification(notif: c.ghostty.ghostty_action_desktop_notification_s) bool {
    const title = if (notif.title) |t| std.mem.span(t) else return false;
    const body: ?[]const u8 = if (notif.body) |b| std.mem.span(b) else null;
    main_mod.sendNotification("ghostty-terminal", title, body);
    return true;
}

/// Open a URL via the desktop's default handler.
fn handleOpenUrl(url_action: c.ghostty.ghostty_action_open_url_s) bool {
    const url_ptr = url_action.url orelse return false;
    const url = url_ptr[0..url_action.len];
    if (url.len == 0) return false;

    // Use GLib's URI launcher (null-terminate the URL)
    const alloc = std.heap.c_allocator;
    const url_z = alloc.dupeZ(u8, url) catch return false;
    defer alloc.free(url_z);

    _ = c.gtk.g_app_info_launch_default_for_uri(url_z.ptr, null, null);
    return true;
}

/// Toggle fullscreen on the main window.
fn handleToggleFullscreen() bool {
    const gtk_app = c.gtk.g_application_get_default() orelse return false;
    const win = c.gtk.gtk_application_get_active_window(@ptrCast(@alignCast(gtk_app))) orelse return false;
    const is_fullscreen = c.gtk.gtk_window_is_fullscreen(win);
    if (is_fullscreen != 0) {
        c.gtk.gtk_window_unfullscreen(win);
    } else {
        c.gtk.gtk_window_fullscreen(win);
    }
    return true;
}

/// Visual/audible bell from the terminal.
fn handleBell(target: c.ghostty.ghostty_target_s) bool {
    // Increment the flash counter on the panel for visual bell
    const tm = window.getTabManager() orelse return false;
    const surface_ud = getSurfaceUserdata(target) orelse {
        // App-level bell: ring the system bell via GDK
        const gtk_app = c.gtk.g_application_get_default() orelse return false;
        const win = c.gtk.gtk_application_get_active_window(@ptrCast(@alignCast(gtk_app))) orelse return false;
        const gdk_surface = c.gtk.gtk_native_get_surface(@ptrCast(win));
        if (gdk_surface) |s| c.gtk.gdk_surface_beep(s);
        return true;
    };
    const widget: *c.GtkWidget = @ptrCast(@alignCast(surface_ud));

    for (tm.workspaces.items) |ws| {
        var it = ws.panels.valueIterator();
        while (it.next()) |panel_ptr| {
            const panel = panel_ptr.*;
            if (panel.widget) |pw| {
                if (pw == widget) {
                    panel.flash_count +|= 1;
                    return true;
                }
            }
        }
    }
    // Fall back to system bell
    const gtk_app = c.gtk.g_application_get_default() orelse return true;
    const win = c.gtk.gtk_application_get_active_window(@ptrCast(@alignCast(gtk_app))) orelse return true;
    const gdk_surface = c.gtk.gtk_native_get_surface(@ptrCast(win));
    if (gdk_surface) |s| c.gtk.gdk_surface_beep(s);
    return true;
}

/// Queue a re-render of the surface's GL area.
fn handleRender(target: c.ghostty.ghostty_target_s) bool {
    const surface_ud = getSurfaceUserdata(target) orelse return false;
    const widget: *c.GtkWidget = @ptrCast(@alignCast(surface_ud));
    // The widget is a GtkGLArea — queue a redraw
    c.gtk.gtk_gl_area_queue_render(@ptrCast(@alignCast(widget)));
    return true;
}

/// Set the mouse cursor shape on the terminal surface widget.
fn handleMouseShape(target: c.ghostty.ghostty_target_s, shape: c.ghostty.ghostty_action_mouse_shape_e) bool {
    const surface_ud = getSurfaceUserdata(target) orelse return false;
    const widget: *c.GtkWidget = @ptrCast(@alignCast(surface_ud));

    const cursor_name: [*c]const u8 = switch (shape) {
        c.ghostty.GHOSTTY_MOUSE_SHAPE_DEFAULT => "default",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_TEXT => "text",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_POINTER => "pointer",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_CROSSHAIR => "crosshair",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_MOVE => "move",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED => "not-allowed",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_GRAB => "grab",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_GRABBING => "grabbing",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_COL_RESIZE => "col-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_ROW_RESIZE => "row-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_N_RESIZE => "n-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_E_RESIZE => "e-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_S_RESIZE => "s-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_W_RESIZE => "w-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_NE_RESIZE => "ne-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_NW_RESIZE => "nw-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_SE_RESIZE => "se-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_SW_RESIZE => "sw-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_EW_RESIZE => "ew-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_NS_RESIZE => "ns-resize",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_WAIT => "wait",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_PROGRESS => "progress",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_HELP => "help",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU => "context-menu",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_CELL => "cell",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_ALL_SCROLL => "all-scroll",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_ZOOM_IN => "zoom-in",
        c.ghostty.GHOSTTY_MOUSE_SHAPE_ZOOM_OUT => "zoom-out",
        else => "default",
    };

    const cursor = c.gtk.gdk_cursor_new_from_name(cursor_name, null);
    c.gtk.gtk_widget_set_cursor(widget, cursor);
    if (cursor) |cur| c.gtk.g_object_unref(cur);
    return true;
}

/// Set mouse cursor visibility on the terminal surface widget.
fn handleMouseVisibility(target: c.ghostty.ghostty_target_s, vis: c.ghostty.ghostty_action_mouse_visibility_e) bool {
    const surface_ud = getSurfaceUserdata(target) orelse return false;
    const widget: *c.GtkWidget = @ptrCast(@alignCast(surface_ud));

    if (vis == c.ghostty.GHOSTTY_MOUSE_HIDDEN) {
        // Use "none" cursor to hide
        const cursor = c.gtk.gdk_cursor_new_from_name("none", null);
        c.gtk.gtk_widget_set_cursor(widget, cursor);
        if (cursor) |cur| c.gtk.g_object_unref(cur);
    } else {
        // Restore default cursor
        c.gtk.gtk_widget_set_cursor(widget, null);
    }
    return true;
}

/// Close the active window.
fn handleCloseWindow() bool {
    const gtk_app = c.gtk.g_application_get_default() orelse return false;
    const win = c.gtk.gtk_application_get_active_window(@ptrCast(@alignCast(gtk_app))) orelse return false;
    c.gtk.gtk_window_close(win);
    return true;
}

/// Close all windows and quit.
fn handleCloseAllWindows() bool {
    const gtk_app = c.gtk.g_application_get_default() orelse return false;
    c.gtk.g_application_quit(gtk_app);
    return true;
}

/// Quit the application.
fn handleQuit() bool {
    const gtk_app = c.gtk.g_application_get_default() orelse return false;
    c.gtk.g_application_quit(gtk_app);
    return true;
}

/// Toggle maximize on the active window.
fn handleToggleMaximize() bool {
    const gtk_app = c.gtk.g_application_get_default() orelse return false;
    const win = c.gtk.gtk_application_get_active_window(@ptrCast(@alignCast(gtk_app))) orelse return false;
    if (c.gtk.gtk_window_is_maximized(win) != 0) {
        c.gtk.gtk_window_unmaximize(win);
    } else {
        c.gtk.gtk_window_maximize(win);
    }
    return true;
}

/// Handle terminal child process exit.
fn handleChildExited(target: c.ghostty.ghostty_target_s, exited: c.ghostty.ghostty_surface_message_childexited_s) bool {
    _ = exited; // exit_code and runtime available but not used yet
    // Treat child exit the same as close_surface: remove the panel.
    const surface_ud = getSurfaceUserdata(target) orelse return false;
    onCloseSurface(surface_ud, true);
    return true;
}

/// Log renderer health changes.
fn handleRendererHealth(health: c.ghostty.ghostty_action_renderer_health_e) bool {
    if (health == c.ghostty.GHOSTTY_RENDERER_HEALTH_UNHEALTHY) {
        log.warn("Renderer reported unhealthy state", .{});
    }
    return true;
}

/// Handle terminal color changes (OSC 4/10/11).
fn handleColorChange(change: c.ghostty.ghostty_action_color_change_s) bool {
    _ = change; // Color kind + RGB values — will wire to theme engine later
    return true;
}

/// Reload the ghostty configuration.
fn handleReloadConfig(reload: c.ghostty.ghostty_action_reload_config_s) bool {
    _ = reload; // .soft field available for future partial reload support
    // Re-read config from disk and apply
    if (main_mod.ghostty_app) |app| {
        const new_config = c.ghostty.ghostty_config_new();
        c.ghostty.ghostty_config_load_default_files(new_config);
        c.ghostty.ghostty_config_finalize(new_config);
        c.ghostty.ghostty_app_update_config(app, new_config);
        log.info("Configuration reloaded", .{});
    }
    return true;
}

/// Handle config changes pushed from libghostty.
fn handleConfigChange(change: c.ghostty.ghostty_action_config_change_s) bool {
    _ = change; // Config key/value — will wire to settings UI later
    return true;
}

// ── Split management ───────────────────────────────────────────────

/// Create a new split pane in the focused workspace.
fn handleNewSplit(direction: c.ghostty.ghostty_action_split_direction_e) bool {
    const tm = window.getTabManager() orelse return false;
    const ws = tm.selectedWorkspace() orelse return false;
    const root = ws.root_node orelse return false;
    const focused_id = ws.focused_panel_id orelse return false;

    // Determine orientation from ghostty direction
    const orientation: split_tree.Orientation = switch (direction) {
        c.ghostty.GHOSTTY_SPLIT_DIRECTION_RIGHT,
        c.ghostty.GHOSTTY_SPLIT_DIRECTION_LEFT,
        => .horizontal,
        c.ghostty.GHOSTTY_SPLIT_DIRECTION_DOWN,
        c.ghostty.GHOSTTY_SPLIT_DIRECTION_UP,
        => .vertical,
        else => .horizontal,
    };

    // Find the target node BEFORE creating the panel to avoid orphans on failure
    const target = findNodeByPanel(root, focused_id) orelse return false;

    // Create a new terminal panel
    const panel = ws.createTerminalPanel(tm.ghostty_app) catch return false;

    // Split the target node; clean up on failure to avoid orphaned panel
    _ = split_tree.splitPane(
        ws.alloc,
        target,
        orientation,
        panel.id,
        panel.widget,
    ) catch {
        ws.removePanel(panel.id);
        ws.focused_panel_id = focused_id;
        return false;
    };

    // Rebuild the GTK widget tree
    rebuildWorkspaceWidget(tm, ws);
    return true;
}

/// Navigate to an adjacent split pane.
fn handleGotoSplit(goto: c.ghostty.ghostty_action_goto_split_e) bool {
    const tm = window.getTabManager() orelse return false;
    const ws = tm.selectedWorkspace() orelse return false;
    const root = ws.root_node orelse return false;
    const focused_id = ws.focused_panel_id orelse return false;

    const direction: split_tree.TraversalDirection = switch (goto) {
        c.ghostty.GHOSTTY_GOTO_SPLIT_NEXT,
        c.ghostty.GHOSTTY_GOTO_SPLIT_RIGHT,
        c.ghostty.GHOSTTY_GOTO_SPLIT_DOWN,
        => .next,
        c.ghostty.GHOSTTY_GOTO_SPLIT_PREVIOUS,
        c.ghostty.GHOSTTY_GOTO_SPLIT_LEFT,
        c.ghostty.GHOSTTY_GOTO_SPLIT_UP,
        => .previous,
        else => .next,
    };

    const target_leaf = split_tree.adjacentLeaf(root, focused_id, direction, ws.alloc) orelse return false;
    ws.focused_panel_id = target_leaf.panel_id;

    // Focus the target widget
    if (target_leaf.widget) |w| {
        _ = c.gtk.gtk_widget_grab_focus(w);
    }
    return true;
}

/// Resize the focused split pane.
fn handleResizeSplit(resize: c.ghostty.ghostty_action_resize_split_s) bool {
    const tm = window.getTabManager() orelse return false;
    const ws = tm.selectedWorkspace() orelse return false;
    const root = ws.root_node orelse return false;
    const focused_id = ws.focused_panel_id orelse return false;

    // Map ghostty resize direction to split_tree orientation and side
    const orientation: split_tree.Orientation = switch (resize.direction) {
        c.ghostty.GHOSTTY_RESIZE_SPLIT_LEFT,
        c.ghostty.GHOSTTY_RESIZE_SPLIT_RIGHT,
        => .horizontal,
        c.ghostty.GHOSTTY_RESIZE_SPLIT_UP,
        c.ghostty.GHOSTTY_RESIZE_SPLIT_DOWN,
        => .vertical,
        else => return false,
    };

    // Growing right/down means the panel is in the first child,
    // growing left/up means it's in the second child.
    const in_first = switch (resize.direction) {
        c.ghostty.GHOSTTY_RESIZE_SPLIT_RIGHT,
        c.ghostty.GHOSTTY_RESIZE_SPLIT_DOWN,
        => true,
        else => false,
    };

    const split = split_tree.findResizeSplit(root, focused_id, orientation, in_first) orelse return false;

    // Adjust ratio by the amount (ghostty sends pixels, we convert to fraction)
    const delta: f64 = @as(f64, @floatFromInt(resize.amount)) / 1000.0;
    const new_ratio = if (in_first) split.ratio + delta else split.ratio - delta;
    split.ratio = std.math.clamp(new_ratio, 0.1, 0.9);

    // Apply the new ratio to the GtkPaned widget
    split_tree.applyRatios(root);
    return true;
}

/// Equalize all split ratios in the focused workspace.
fn handleEqualizeSplits() bool {
    const tm = window.getTabManager() orelse return false;
    const ws = tm.selectedWorkspace() orelse return false;
    const root = ws.root_node orelse return false;

    split_tree.equalize(root);
    split_tree.applyRatios(root);
    return true;
}

/// Toggle split zoom (maximize focused pane / restore).
/// Currently a no-op placeholder — needs show/hide logic for sibling panes.
fn handleToggleSplitZoom() bool {
    // TODO: implement zoom by hiding sibling panes and restoring them
    log.info("toggle_split_zoom: not yet implemented", .{});
    return false;
}

/// Find the Node (leaf or split) containing a panel by its ID.
fn findNodeByPanel(node: *split_tree.Node, panel_id: u128) ?*split_tree.Node {
    switch (node.*) {
        .leaf => |leaf| {
            if (leaf.panel_id == panel_id) return node;
            return null;
        },
        .split => |split| {
            if (findNodeByPanel(split.first, panel_id)) |n| return n;
            if (findNodeByPanel(split.second, panel_id)) |n| return n;
            return null;
        },
    }
}

/// Rebuild the workspace's GTK widget tree after a split tree mutation.
fn rebuildWorkspaceWidget(tm: *@import("tab_manager.zig").TabManager, ws: *@import("workspace.zig").Workspace) void {
    const root = ws.root_node orelse return;
    const old_widget = ws.content_widget;

    // Build new widget tree
    const new_widget = split_tree.buildWidget(root) orelse return;
    ws.content_widget = new_widget;

    // Replace in AdwTabView
    if (tm.tab_view) |tv| {
        if (old_widget) |ow| {
            const page = c.gtk.adw_tab_view_get_page(tv, ow);
            if (page) |p| {
                // Remove old page and add new one at the same position
                const idx = c.gtk.adw_tab_view_get_page_position(tv, p);
                c.gtk.adw_tab_view_close_page(tv, p);
                const new_page = c.gtk.adw_tab_view_insert(tv, new_widget, idx);
                if (new_page) |np| {
                    c.gtk.adw_tab_page_set_title(np, ws.displayTitle().ptr);
                    c.gtk.adw_tab_view_set_selected_page(tv, np);
                }
            }
        }
    }

    // Apply split ratios after widget is allocated.
    // Use an idle callback so GTK has time to allocate sizes.
    // Carry workspace ID (not raw pointer) to avoid use-after-free
    // if the workspace is closed before the idle fires.
    const alloc = std.heap.c_allocator;
    const ctx = alloc.create(ApplyRatiosCtx) catch return;
    ctx.* = .{ .ws_id = ws.id };
    _ = c.gtk.g_idle_add(&applyRatiosIdle, ctx);
}

/// Context for deferred ratio application.
const ApplyRatiosCtx = struct { ws_id: u128 };

/// GLib idle callback to apply split ratios after allocation.
/// Returns G_SOURCE_REMOVE so it only fires once.
fn applyRatiosIdle(data: ?*anyopaque) callconv(.c) c.gtk.gboolean {
    const alloc = std.heap.c_allocator;
    const ctx: *ApplyRatiosCtx = @ptrCast(@alignCast(data orelse return c.gtk.G_SOURCE_REMOVE));
    defer alloc.destroy(ctx);
    const tm = window.getTabManager() orelse return c.gtk.G_SOURCE_REMOVE;
    for (tm.workspaces.items) |ws| {
        if (ws.id == ctx.ws_id) {
            if (ws.root_node) |r| split_tree.applyRatios(r);
            break;
        }
    }
    return c.gtk.G_SOURCE_REMOVE;
}

/// Extract the surface userdata pointer from a ghostty target.
fn getSurfaceUserdata(target: c.ghostty.ghostty_target_s) ?*anyopaque {
    if (target.tag != c.ghostty.GHOSTTY_TARGET_SURFACE) return null;
    const surface = target.target.surface orelse return null;
    return c.ghostty.ghostty_surface_userdata(surface);
}

/// Context passed through the async clipboard read callback.
const ClipboardReadContext = struct {
    surface: c.ghostty_surface_t,
    completion_context: ?*anyopaque,
};

/// Read clipboard callback: libghostty wants clipboard contents (paste).
/// The userdata is the surface's userdata (GtkWidget* of the GtkGLArea).
/// Starts an async clipboard read and completes via GLib callback.
pub fn onReadClipboard(
    userdata: ?*anyopaque,
    clipboard_type: c.ghostty.ghostty_clipboard_e,
    context: ?*anyopaque,
) callconv(.c) bool {
    const widget: *c.GtkWidget = @ptrCast(@alignCast(userdata orelse return false));
    const surface_data = @import("surface.zig").fromWidget(widget) orelse return false;
    const ghostty_surface = surface_data.ghostty_surface orelse return false;

    // Get the appropriate GDK clipboard
    const display = c.gtk.gtk_widget_get_display(widget) orelse return false;
    const clipboard = switch (clipboard_type) {
        c.ghostty.GHOSTTY_CLIPBOARD_SELECTION => c.gtk.gdk_display_get_primary_clipboard(display),
        else => c.gtk.gdk_display_get_clipboard(display),
    };
    if (clipboard == null) return false;

    // Allocate context for the async callback
    const alloc = std.heap.c_allocator;
    const ctx = alloc.create(ClipboardReadContext) catch return false;
    ctx.* = .{
        .surface = ghostty_surface,
        .completion_context = context,
    };

    c.gtk.gdk_clipboard_read_text_async(clipboard, null, &onClipboardReadComplete, ctx);
    return true;
}

/// GAsyncReadyCallback: clipboard text is available.
fn onClipboardReadComplete(
    source: ?*c.gtk.GObject,
    result: ?*c.gtk.GAsyncResult,
    user_data: ?*anyopaque,
) callconv(.c) void {
    const alloc = std.heap.c_allocator;
    const ctx: *ClipboardReadContext = @ptrCast(@alignCast(user_data orelse return));
    defer alloc.destroy(ctx);

    const clipboard: ?*c.gtk.GdkClipboard = @ptrCast(@alignCast(source));
    if (clipboard == null) return;

    const text = c.gtk.gdk_clipboard_read_text_finish(clipboard, result, null);

    c.ghostty.ghostty_surface_complete_clipboard_request(
        ctx.surface,
        text,
        ctx.completion_context,
        true,
    );

    if (text) |t| c.gtk.g_free(t);
}

/// Confirm read clipboard callback: auto-confirm for now.
/// A proper implementation would show a confirmation dialog.
pub fn onConfirmReadClipboard(
    userdata: ?*anyopaque,
    data: [*c]const u8,
    context: ?*anyopaque,
    _: c.ghostty.ghostty_clipboard_request_e,
) callconv(.c) void {
    // Auto-confirm: complete the clipboard request immediately.
    const widget: *c.GtkWidget = @ptrCast(@alignCast(userdata orelse return));
    const surface_data = @import("surface.zig").fromWidget(widget) orelse return;
    const ghostty_surface = surface_data.ghostty_surface orelse return;

    c.ghostty.ghostty_surface_complete_clipboard_request(
        ghostty_surface,
        data,
        context,
        true,
    );
}

/// Write clipboard callback: libghostty wants to set clipboard contents (copy).
pub fn onWriteClipboard(
    userdata: ?*anyopaque,
    clipboard_type: c_uint,
    contents: [*c]const c.ghostty.ghostty_clipboard_content_s,
    count: usize,
    _: bool,
) callconv(.c) void {
    if (count == 0) return;
    const widget: *c.GtkWidget = @ptrCast(@alignCast(userdata orelse return));

    const display = c.gtk.gtk_widget_get_display(widget) orelse return;
    // C enum is translated as c_uint; compare directly against constants.
    const clipboard = if (clipboard_type == c.ghostty.GHOSTTY_CLIPBOARD_SELECTION)
        c.gtk.gdk_display_get_primary_clipboard(display)
    else
        c.gtk.gdk_display_get_clipboard(display);
    if (clipboard == null) return;

    // Use the first text/plain content
    const content = contents[0];
    if (content.data) |data| {
        c.gtk.gdk_clipboard_set_text(clipboard, data);
    }
}

/// Close surface callback: terminal process exited or user requested close.
/// The userdata is the GtkWidget pointer set during surface creation.
/// Walk the tab manager to find the owning panel and remove it.
/// If a workspace becomes empty after removal, close it.
pub fn onCloseSurface(
    userdata: ?*anyopaque,
    _: bool,
) callconv(.c) void {
    const widget: *c.GtkWidget = @ptrCast(@alignCast(userdata orelse return));
    const tm = window.getTabManager() orelse return;

    // Find which workspace/panel owns this widget.
    // Capture the panel ID first, then remove outside the iterator
    // to avoid iterator invalidation.
    var found_panel_id: ?u128 = null;
    var found_ws_idx: usize = 0;
    outer: for (tm.workspaces.items, 0..) |ws, ws_idx| {
        var it = ws.panels.valueIterator();
        while (it.next()) |panel_ptr| {
            const panel = panel_ptr.*;
            if (panel.widget) |pw| {
                if (pw == widget) {
                    found_panel_id = panel.id;
                    found_ws_idx = ws_idx;
                    break :outer;
                }
            }
        }
    }

    const panel_id = found_panel_id orelse return;
    const ws = tm.workspaces.items[found_ws_idx];
    ws.removePanel(panel_id);

    // If the workspace is now empty, close it (unless it's the last one).
    if (ws.panelCount() == 0 and tm.workspaces.items.len > 1) {
        tm.closeWorkspace(found_ws_idx);
    }
}
