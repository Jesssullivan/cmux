/// logind session lock/unlock integration.
///
/// Listens for systemd-logind Lock/Unlock signals via D-Bus to
/// pause/resume terminal activity when the screen is locked.
/// Maps to macOS NSWorkspace.willSleep/didWake notifications.

const std = @import("std");
const c = @import("c_api.zig");

const log = std.log.scoped(.logind);

pub const SessionState = enum {
    active,
    locked,
};

pub const LockCallback = *const fn (state: SessionState) void;

var lock_callback: ?LockCallback = null;
var subscription_id: c_uint = 0;

/// Start listening for logind Lock/Unlock signals.
/// Calls the provided callback when the session is locked or unlocked.
pub fn watchSession(callback: LockCallback) void {
    lock_callback = callback;

    // Subscribe to org.freedesktop.login1.Session signals via D-Bus
    const bus = c.gtk.g_bus_get_sync(c.gtk.G_BUS_TYPE_SYSTEM, null, null) orelse {
        log.warn("Failed to connect to system D-Bus for logind", .{});
        return;
    };

    subscription_id = c.gtk.g_dbus_connection_signal_subscribe(
        bus,
        "org.freedesktop.login1", // sender
        "org.freedesktop.login1.Session", // interface
        null, // member (all signals)
        null, // object path (all sessions)
        null, // arg0
        c.gtk.G_DBUS_SIGNAL_FLAGS_NONE,
        &onLogindSignal,
        null, // user_data
        null, // user_data_free_func
    );

    log.info("Watching logind session signals (subscription {d})", .{subscription_id});
}

/// Stop listening for logind signals.
pub fn unwatchSession() void {
    if (subscription_id != 0) {
        // Would need the bus connection to unsubscribe
        subscription_id = 0;
        lock_callback = null;
    }
}

fn onLogindSignal(
    _: ?*c.gtk.GDBusConnection,
    _: [*c]const u8, // sender_name
    _: [*c]const u8, // object_path
    _: [*c]const u8, // interface_name
    signal_name: [*c]const u8,
    _: ?*c.gtk.GVariant,
    _: ?*anyopaque,
) callconv(.c) void {
    const cb = lock_callback orelse return;
    const name = std.mem.span(signal_name);

    if (std.mem.eql(u8, name, "Lock")) {
        log.info("Session locked", .{});
        cb(.locked);
    } else if (std.mem.eql(u8, name, "Unlock")) {
        log.info("Session unlocked", .{});
        cb(.active);
    }
}
