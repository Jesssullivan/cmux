/// Unix domain socket JSON-RPC server for external control.
///
/// Listens on $XDG_RUNTIME_DIR/cmux.sock (or ~/.config/cmux/cmux.sock).
/// Protocol: newline-delimited JSON-RPC over Unix stream socket.
/// Maps to macOS SocketControlSettings.swift + TerminalController.

const std = @import("std");
const posix = std.posix;
const c = @import("c_api.zig");
const window = @import("window.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.socket);

pub const SocketServer = struct {
    alloc: Allocator,
    listen_fd: posix.socket_t = -1,
    socket_path: ?[]const u8 = null,
    glib_source_id: c_uint = 0,

    pub fn init(alloc: Allocator) SocketServer {
        return .{ .alloc = alloc };
    }

    /// Start listening on the socket.
    pub fn start(self: *SocketServer) !void {
        const path = try self.resolveSocketPath();
        self.socket_path = path;

        // Remove stale socket file
        std.fs.deleteFileAbsolute(path) catch {};

        // Create Unix domain socket
        self.listen_fd = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, 0);
        errdefer posix.close(self.listen_fd);

        // Bind
        var addr = std.mem.zeroes(posix.sockaddr.un);
        addr.family = posix.AF.UNIX;
        const path_bytes = path[0..@min(path.len, addr.path.len - 1)];
        @memcpy(addr.path[0..path_bytes.len], path_bytes);

        try posix.bind(self.listen_fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un));

        // Set permissions (0600 — owner only)
        std.fs.cwd().chmod(path, 0o600) catch {};

        // Listen
        try posix.listen(self.listen_fd, 8);

        // Integrate with GLib main loop
        self.glib_source_id = c.gtk.g_unix_fd_add(
            self.listen_fd,
            c.gtk.G_IO_IN,
            &onIncoming,
            self,
        );

        log.info("Socket server listening on {s}", .{path});
    }

    /// Stop the socket server.
    pub fn stop(self: *SocketServer) void {
        if (self.glib_source_id != 0) {
            _ = c.gtk.g_source_remove(self.glib_source_id);
            self.glib_source_id = 0;
        }
        if (self.listen_fd >= 0) {
            posix.close(self.listen_fd);
            self.listen_fd = -1;
        }
        if (self.socket_path) |path| {
            std.fs.deleteFileAbsolute(path) catch {};
            self.alloc.free(path);
            self.socket_path = null;
        }
    }

    fn resolveSocketPath(self: *SocketServer) ![]const u8 {
        // Prefer XDG_RUNTIME_DIR
        if (posix.getenv("XDG_RUNTIME_DIR")) |runtime_dir| {
            return try std.fmt.allocPrint(self.alloc, "{s}/cmux.sock", .{runtime_dir});
        }
        // Fall back to ~/.config/cmux/
        if (posix.getenv("HOME")) |home| {
            const dir = try std.fmt.allocPrint(self.alloc, "{s}/.config/cmux", .{home});
            defer self.alloc.free(dir);
            std.fs.makeDirAbsolute(dir) catch {};
            return try std.fmt.allocPrint(self.alloc, "{s}/.config/cmux/cmux.sock", .{home});
        }
        return error.NoSocketPath;
    }

    /// GLib callback for incoming connections.
    fn onIncoming(fd: c_int, _: c_uint, data: ?*anyopaque) callconv(.c) c.gtk.gboolean {
        const self: *SocketServer = @ptrCast(@alignCast(data));
        _ = self;

        // Accept the connection
        const client_fd = posix.accept(fd, null, null, posix.SOCK.NONBLOCK) catch {
            return 1; // Keep watching
        };

        // Read request (simple: read all available, parse JSON-RPC)
        var buf: [4096]u8 = undefined;
        const n = posix.read(client_fd, &buf) catch {
            posix.close(client_fd);
            return 1;
        };

        if (n > 0) {
            const response = handleRequest(buf[0..n]);
            _ = posix.write(client_fd, response) catch {};
        }

        posix.close(client_fd);
        return 1; // Keep watching
    }

    /// Dispatch a JSON-RPC request and return the response.
    fn handleRequest(request: []const u8) []const u8 {
        // Simple JSON-RPC dispatch
        if (std.mem.indexOf(u8, request, "\"ping\"")) |_| {
            return "{\"result\":\"pong\"}\n";
        }
        if (std.mem.indexOf(u8, request, "\"version\"")) |_| {
            return "{\"result\":{\"version\":\"0.1.0\",\"platform\":\"linux\"}}\n";
        }
        if (std.mem.indexOf(u8, request, "\"workspace.list\"")) |_| {
            return handleWorkspaceList();
        }
        if (std.mem.indexOf(u8, request, "\"workspace.create\"")) |_| {
            return handleWorkspaceCreate();
        }
        return "{\"error\":\"unknown method\"}\n";
    }

    fn handleWorkspaceList() []const u8 {
        const tm = window.getTabManager() orelse return "{\"result\":[]}\n";
        _ = tm;
        // TODO: serialize workspace list to JSON
        return "{\"result\":[]}\n";
    }

    fn handleWorkspaceCreate() []const u8 {
        const tm = window.getTabManager() orelse return "{\"error\":\"no tab manager\"}\n";
        _ = tm.createWorkspace() catch return "{\"error\":\"create failed\"}\n";
        if (window.getSidebar()) |sb| sb.refresh();
        return "{\"result\":\"ok\"}\n";
    }
};
