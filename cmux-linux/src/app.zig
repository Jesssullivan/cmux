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
pub fn onReadClipboard(
    _: ?*anyopaque,
    _: c_uint,
    _: ?*anyopaque,
) callconv(.c) void {}

/// Confirm read clipboard callback.
pub fn onConfirmReadClipboard(
    _: ?*anyopaque,
    _: [*c]const u8,
    _: ?*anyopaque,
    _: c_uint,
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
pub fn onCloseSurface(
    _: ?*anyopaque,
    _: bool,
) callconv(.c) void {}
