/// GNotification integration for cmux-linux.
///
/// Sends desktop notifications via GApplication's GNotification API.
/// Triggered by terminal OSC 9/99 notification sequences.
/// Maps to macOS TerminalNotificationStore.swift.

const std = @import("std");
const c = @import("c_api.zig");

const log = std.log.scoped(.notifications);

pub const Notification = struct {
    title: []const u8,
    body: ?[]const u8 = null,
    priority: Priority = .normal,
};

pub const Priority = enum {
    low,
    normal,
    high,
    urgent,

    pub fn toGLib(self: Priority) c_uint {
        return switch (self) {
            .low => c.gtk.G_NOTIFICATION_PRIORITY_LOW,
            .normal => c.gtk.G_NOTIFICATION_PRIORITY_NORMAL,
            .high => c.gtk.G_NOTIFICATION_PRIORITY_HIGH,
            .urgent => c.gtk.G_NOTIFICATION_PRIORITY_URGENT,
        };
    }
};

/// Send a desktop notification via GApplication.
/// Requires a running GtkApplication with a valid app ID and
/// an installed .desktop file.
pub fn send(app: *c.gtk.GApplication, id: []const u8, notif: Notification) void {
    const g_notif = c.gtk.g_notification_new(notif.title.ptr) orelse {
        log.warn("Failed to create GNotification", .{});
        return;
    };
    defer c.gtk.g_object_unref(g_notif);

    if (notif.body) |body| {
        c.gtk.g_notification_set_body(g_notif, body.ptr);
    }

    c.gtk.g_notification_set_priority(g_notif, notif.priority.toGLib());

    c.gtk.g_application_send_notification(app, id.ptr, g_notif);

    log.debug("Notification sent: {s}", .{notif.title});
}

/// Withdraw (dismiss) a previously sent notification by ID.
pub fn withdraw(app: *c.gtk.GApplication, id: []const u8) void {
    c.gtk.g_application_withdraw_notification(app, id.ptr);
}
