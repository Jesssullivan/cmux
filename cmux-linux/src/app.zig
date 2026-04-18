/// libghostty runtime callbacks.
///
/// These functions are called by libghostty when it needs the host
/// application to perform actions (clipboard, new tabs, close, etc.).
const std = @import("std");
const c = @import("c_api.zig");
const window = @import("window.zig");

/// Action callback: libghostty requests the host perform an action.
/// Returns true if handled, false to let libghostty handle it.
pub fn onAction(
    _: c.ghostty_app_t,
    _: c.ghostty.ghostty_target_s,
    _: c.ghostty.ghostty_action_s,
) callconv(.c) bool {
    // TODO: dispatch actions (new_tab, close_tab, set_title, etc.)
    return false;
}

/// Read clipboard callback: libghostty wants clipboard contents.
/// Returns false when clipboard data is not available.
pub fn onReadClipboard(
    _: ?*anyopaque,
    _: c.ghostty.ghostty_clipboard_e,
    _: ?*anyopaque,
) callconv(.c) bool {
    return false;
}

/// Confirm read clipboard callback.
pub fn onConfirmReadClipboard(
    _: ?*anyopaque,
    _: [*c]const u8,
    _: ?*anyopaque,
    _: c.ghostty.ghostty_clipboard_request_e,
) callconv(.c) void {}

/// Write clipboard callback: libghostty wants to set clipboard contents.
pub fn onWriteClipboard(
    _: ?*anyopaque,
    _: c_uint,
    _: [*c]const c.ghostty.ghostty_clipboard_content_s,
    _: usize,
    _: bool,
) callconv(.c) void {}

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
