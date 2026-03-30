/// cmux-term: headless terminal multiplexer (no GTK4/GUI).
///
/// Runs without a display server — suitable for SSH sessions,
/// containers, and server environments like Rocky 10.
///
/// Build with: zig build -Dheadless=true
/// Binary: cmux-term

const std = @import("std");
const config = @import("config.zig");

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    // Load config
    if (config.loadDefault(alloc)) |cfg| {
        _ = cfg;
        std.log.info("Config loaded ({d} commands)", .{cfg.commands.len});
    } else {
        std.log.info("No config found, using defaults", .{});
    }

    // TODO: Initialize libghostty in headless mode
    // TODO: Start Unix socket server for JSON-RPC control
    // TODO: Create PTY and run default shell
    // TODO: Forward stdin/stdout to the PTY

    const stdout = std.io.getStdOut().writer();
    try stdout.print("cmux-term: headless terminal mode\n", .{});
    try stdout.print("Socket control: $XDG_RUNTIME_DIR/cmux.sock\n", .{});
    try stdout.print("Config: ~/.config/cmux/cmux.json\n", .{});
}
