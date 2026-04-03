/// cmux-linux: GTK4 terminal multiplexer linking to libghostty.
///
/// Entry point: creates a GtkApplication with libadwaita, initializes
/// libghostty, and runs the main event loop.

const std = @import("std");
const posix = std.posix;
const c = @import("c_api.zig");
const app_mod = @import("app.zig");
const window = @import("window.zig");
const SocketServer = @import("socket.zig").SocketServer;
const notifications = @import("notifications.zig");
const logind = @import("logind.zig");

const log = std.log.scoped(.main);

/// Global libghostty app instance (set after ghostty_app_new).
var ghostty_app: c.ghostty_app_t = null;

/// Global socket server (started before window creation).
var socket_server: SocketServer = SocketServer.init(std.heap.c_allocator);

/// GTK application activate callback.
fn onActivate(gtk_app: *c.GtkApplication) callconv(.c) void {
    // Start socket server FIRST — so it's available even if surface creation crashes
    socket_server.start() catch |err| {
        log.warn("Socket server failed to start: {}", .{err});
    };

    // Start logind session monitoring (pause terminals on screen lock)
    logind.watchSession(&onSessionStateChange);

    // Create the main window (tab manager, sidebar, workspaces)
    window.createWindow(gtk_app, ghostty_app);

    // In test mode, hold the app to prevent auto-quit (placeholder widget may not keep it alive)
    if (posix.getenv("CMUX_NO_SURFACE") != null) {
        c.gtk.g_application_hold(@ptrCast(gtk_app));
    }
}

/// Handle logind session state changes (lock/unlock).
fn onSessionStateChange(state: logind.SessionState) void {
    switch (state) {
        .locked => {
            log.info("Session locked — pausing terminal activity", .{});
            // TODO: pause ghostty rendering when ghostty_app_pause API is available
        },
        .active => {
            log.info("Session unlocked — resuming terminal activity", .{});
            // TODO: resume ghostty rendering when ghostty_app_resume API is available
        },
    }
}

/// Send a desktop notification via GNotification.
/// Called from socket commands and OSC 9/99 terminal sequences.
pub fn sendNotification(id: []const u8, title: []const u8, body: ?[]const u8) void {
    const app = c.gtk.g_application_get_default() orelse {
        log.warn("No GApplication for notification", .{});
        return;
    };
    notifications.send(app, id, .{
        .title = title,
        .body = body,
    });
}

/// Withdraw a previously sent notification.
pub fn withdrawNotification(id: []const u8) void {
    const app = c.gtk.g_application_get_default() orelse return;
    notifications.withdraw(app, id);
}

/// Wakeup callback: called by libghostty when it needs a tick.
/// Schedules an idle handler on the GLib main loop.
fn onWakeup(_: ?*anyopaque) callconv(.c) void {
    _ = c.gtk.g_idle_add(&tickCallback, null);
}

/// Idle callback: ticks libghostty.
fn tickCallback(_: ?*anyopaque) callconv(.c) c.gtk.gboolean {
    if (ghostty_app) |app| {
        c.ghostty.ghostty_app_tick(app);
    }
    return c.gtk.G_SOURCE_REMOVE;
}

pub fn main() !void {
    // Initialize libghostty
    _ = c.ghostty.ghostty_init(0, null);

    // Create ghostty config
    const config = c.ghostty.ghostty_config_new();
    c.ghostty.ghostty_config_load_default_files(config);
    c.ghostty.ghostty_config_finalize(config);

    // Create ghostty app with our runtime callbacks
    const runtime_config = c.ghostty.ghostty_runtime_config_s{
        .userdata = null,
        .supports_selection_clipboard = false,
        .wakeup_cb = &onWakeup,
        .action_cb = &app_mod.onAction,
        .read_clipboard_cb = &app_mod.onReadClipboard,
        .confirm_read_clipboard_cb = &app_mod.onConfirmReadClipboard,
        .write_clipboard_cb = &app_mod.onWriteClipboard,
        .close_surface_cb = &app_mod.onCloseSurface,
    };

    ghostty_app = c.ghostty.ghostty_app_new(&runtime_config, config);
    if (ghostty_app == null) {
        std.log.err("Failed to create ghostty app", .{});
        return error.GhosttyInitFailed;
    }
    defer c.ghostty.ghostty_app_free(ghostty_app);

    // Create GTK application
    const gtk_app: *c.GtkApplication = @ptrCast(c.gtk.adw_application_new(
        "com.cmuxterm.cmux",
        c.gtk.G_APPLICATION_DEFAULT_FLAGS,
    ) orelse {
        std.log.err("Failed to create GTK application", .{});
        return error.GtkInitFailed;
    });
    defer c.gtk.g_object_unref(gtk_app);

    // Connect activate signal
    _ = c.gtk.g_signal_connect_data(
        @ptrCast(gtk_app),
        "activate",
        @ptrCast(&onActivate),
        null,
        null,
        0,
    );

    // Run the application
    const status = c.gtk.g_application_run(
        @ptrCast(gtk_app),
        0,
        null,
    );

    // Clean up
    logind.unwatchSession();
    socket_server.stop();

    if (status != 0) {
        log.warn("Application exited with status {}", .{status});
    }
}
