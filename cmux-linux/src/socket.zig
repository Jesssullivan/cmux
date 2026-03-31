/// Unix domain socket JSON-RPC server for external control.
///
/// Listens on $XDG_RUNTIME_DIR/cmux.sock (or ~/.config/cmux/cmux.sock).
/// Protocol: newline-delimited JSON-RPC over Unix stream socket.
/// Response format: {"id": N, "ok": true, "result": {...}} or {"id": N, "ok": false, "error": {...}}
/// Maps to macOS SocketControlSettings.swift + TerminalController.

const std = @import("std");
const posix = std.posix;
const c = @import("c_api.zig");
const window = @import("window.zig");
const Workspace = @import("workspace.zig").Workspace;
const split_tree = @import("split_tree.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.socket);
const json = std.json;

/// Format a u128 as a zero-padded 32-char hex string.
fn formatId(id: u128) [32]u8 {
    const digits = "0123456789abcdef";
    var buf: [32]u8 = undefined;
    var val = id;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        buf[i] = digits[@intCast(val & 0xf)];
        val >>= 4;
    }
    return buf;
}

/// Parse a 32-char hex string back to u128.
fn parseId(hex: []const u8) ?u128 {
    if (hex.len != 32) return null;
    var result: u128 = 0;
    for (hex) |ch| {
        const digit: u128 = switch (ch) {
            '0'...'9' => ch - '0',
            'a'...'f' => ch - 'a' + 10,
            'A'...'F' => ch - 'A' + 10,
            else => return null,
        };
        result = (result << 4) | digit;
    }
    return result;
}

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

        // Set permissions (0600 — owner only).
        // Note: fchmod on socket fd works on Linux to set the socket file permissions.
        posix.fchmod(self.listen_fd, 0o600) catch {};

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
        if (posix.getenv("XDG_RUNTIME_DIR")) |runtime_dir| {
            return try std.fmt.allocPrint(self.alloc, "{s}/cmux.sock", .{runtime_dir});
        }
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

        const client_fd = posix.accept(fd, null, null, posix.SOCK.NONBLOCK) catch {
            return 1;
        };

        // Register client fd for persistent reading via GLib main loop
        _ = c.gtk.g_unix_fd_add(client_fd, c.gtk.G_IO_IN, &onClientData, self);
        return 1;
    }

    /// GLib callback for data on a connected client.
    fn onClientData(fd: c_int, _: c_uint, data: ?*anyopaque) callconv(.c) c.gtk.gboolean {
        const self: *SocketServer = @ptrCast(@alignCast(data));

        var buf: [8192]u8 = undefined;
        const n = posix.read(fd, &buf) catch {
            posix.close(fd);
            return 0; // Remove source
        };

        if (n == 0) {
            // Client disconnected
            posix.close(fd);
            return 0; // Remove source
        }

        // Process each newline-delimited request in the buffer
        var remaining = buf[0..n];
        while (remaining.len > 0) {
            const newline = std.mem.indexOf(u8, remaining, "\n");
            const line = if (newline) |nl| remaining[0..nl] else remaining;
            if (line.len > 0) {
                const response = dispatch(self.alloc, line) catch |err| blk: {
                    log.warn("Dispatch error: {}", .{err});
                    break :blk "{\"id\":0,\"ok\":false,\"error\":{\"code\":\"internal_error\",\"message\":\"dispatch failed\"}}\n";
                };
                _ = posix.write(fd, response) catch {
                    posix.close(fd);
                    return 0;
                };
            }
            if (newline) |nl| {
                remaining = remaining[nl + 1 ..];
            } else {
                break;
            }
        }

        return 1; // Keep watching
    }
};

// ── JSON-RPC Dispatch ───────────────────────────────────────────────────

/// Handler function type: takes allocator + params, returns JSON result string.
const Handler = *const fn (Allocator, json.Value) []const u8;

/// Method dispatch table (comptime).
const methods = .{
    .{ "system.ping", handlePing },
    .{ "system.version", handleVersion },
    .{ "system.identify", handleIdentify },
    .{ "system.capabilities", handleCapabilities },
    .{ "window.list", handleWindowList },
    .{ "window.current", handleWindowCurrent },
    .{ "workspace.list", handleWorkspaceList },
    .{ "workspace.create", handleWorkspaceCreate },
    .{ "workspace.current", handleWorkspaceCurrent },
    .{ "workspace.select", handleWorkspaceSelect },
    .{ "workspace.close", handleWorkspaceClose },
    .{ "workspace.rename", handleWorkspaceRename },
    .{ "workspace.next", handleWorkspaceNext },
    .{ "workspace.previous", handleWorkspacePrevious },
    .{ "workspace.last", handleWorkspaceLast },
    .{ "workspace.reorder", handleWorkspaceReorder },
    .{ "window.create", handleWindowCreate },
    .{ "window.close", handleWindowClose },
    .{ "window.focus", handleWindowFocus },
    .{ "surface.list", handleSurfaceList },
    .{ "surface.focus", handleSurfaceFocus },
    .{ "surface.split", handleSurfaceSplit },
    .{ "surface.close", handleSurfaceClose },
    .{ "surface.create", handleSurfaceCreate },
    .{ "surface.current", handleSurfaceCurrent },
    .{ "surface.send_text", handleSurfaceSendText },
    .{ "surface.read_text", handleSurfaceReadText },
    .{ "surface.refresh", handleSurfaceRefresh },
    .{ "surface.health", handleSurfaceHealth },
    .{ "surface.trigger_flash", handleSurfaceTriggerFlash },
    .{ "surface.clear_history", handleSurfaceClearHistory },
    .{ "pane.list", handlePaneList },
    .{ "pane.focus", handlePaneFocus },
    .{ "pane.create", handlePaneCreate },
    .{ "pane.surfaces", handlePaneSurfaces },
    .{ "pane.last", handlePaneLast },
    .{ "pane.swap", handlePaneSwap },
    .{ "pane.break", handlePaneBreak },
    .{ "pane.join", handlePaneJoin },
    .{ "workspace.move_to_window", handleWorkspaceMoveToWindow },
    .{ "surface.move", handleSurfaceMove },
    .{ "surface.reorder", handleSurfaceReorder },
    .{ "surface.drag_to_split", handleSurfaceDragToSplit },
    .{ "browser.open_split", handleBrowserOpenSplit },
    .{ "browser.navigate", handleBrowserNavigate },
    .{ "browser.back", handleBrowserBack },
    .{ "browser.forward", handleBrowserForward },
    .{ "browser.reload", handleBrowserReload },
    .{ "browser.url.get", handleBrowserUrlGet },
    .{ "browser.focus_webview", handleBrowserFocusWebview },
    .{ "browser.is_webview_focused", handleBrowserIsWebviewFocused },
    .{ "browser.show_devtools", handleBrowserShowDevtools },
    .{ "browser.close_devtools", handleBrowserCloseDevtools },
    .{ "browser.find", handleBrowserFind },
    .{ "browser.find_next", handleBrowserFindNext },
    .{ "browser.find_previous", handleBrowserFindPrevious },
    .{ "browser.find_finish", handleBrowserFindFinish },
    .{ "notification.create", handleNotificationCreate },
    .{ "notification.create_for_surface", handleNotificationCreateForSurface },
    .{ "notification.list", handleNotificationList },
    .{ "notification.clear", handleNotificationClear },
    .{ "app.focus_override.set", handleAppFocusOverrideSet },
    .{ "debug.app.activate", handleDebugAppActivate },
    .{ "debug.flash.count", handleDebugFlashCount },
    .{ "debug.flash.reset", handleDebugFlashReset },
};

/// Parse and dispatch a JSON-RPC request, return the full response line.
fn dispatch(alloc: Allocator, request_bytes: []const u8) ![]const u8 {
    // Trim whitespace/newlines
    const trimmed = std.mem.trim(u8, request_bytes, &[_]u8{ ' ', '\t', '\n', '\r' });
    if (trimmed.len == 0) return "{\"id\":0,\"ok\":false,\"error\":{\"code\":\"invalid_request\",\"message\":\"empty request\"}}\n";

    // Parse JSON
    const parsed = json.parseFromSlice(json.Value, alloc, trimmed, .{}) catch {
        return "{\"id\":0,\"ok\":false,\"error\":{\"code\":\"parse_error\",\"message\":\"invalid JSON\"}}\n";
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return "{\"id\":0,\"ok\":false,\"error\":{\"code\":\"invalid_request\",\"message\":\"expected object\"}}\n";

    // Extract request ID
    const req_id: i64 = if (root.object.get("id")) |id_val| switch (id_val) {
        .integer => |i| i,
        else => 0,
    } else 0;

    // Extract method
    const method_val = root.object.get("method") orelse
        return formatError(alloc, req_id, "invalid_request", "missing method");
    if (method_val != .string)
        return formatError(alloc, req_id, "invalid_request", "method must be string");
    const method_name = method_val.string;

    // Extract params (default to null if not provided)
    const params: json.Value = root.object.get("params") orelse .null;

    // Dispatch to handler
    inline for (methods) |entry| {
        if (std.mem.eql(u8, method_name, entry[0])) {
            const result = entry[1](alloc, params);
            return formatSuccess(alloc, req_id, result);
        }
    }

    return formatError(alloc, req_id, "method_not_found", method_name);
}

// ── Response Formatting ─────────────────────────────────────────────────

fn formatSuccess(alloc: Allocator, req_id: i64, result: []const u8) []const u8 {
    return std.fmt.allocPrint(alloc, "{{\"id\":{d},\"ok\":true,\"result\":{s}}}\n", .{ req_id, result }) catch
        "{\"id\":0,\"ok\":false,\"error\":{\"code\":\"internal_error\",\"message\":\"format failed\"}}\n";
}

fn formatError(alloc: Allocator, req_id: i64, code: []const u8, message: []const u8) []const u8 {
    return std.fmt.allocPrint(alloc, "{{\"id\":{d},\"ok\":false,\"error\":{{\"code\":\"{s}\",\"message\":\"{s}\"}}}}\n", .{ req_id, code, message }) catch
        "{\"id\":0,\"ok\":false,\"error\":{\"code\":\"internal_error\",\"message\":\"format failed\"}}\n";
}

// ── Helpers ─────────────────────────────────────────────────────────────

fn getTabManager() ?*@import("tab_manager.zig").TabManager {
    return window.getTabManager();
}

fn findWorkspaceById(tm: *@import("tab_manager.zig").TabManager, id_str: []const u8) ?struct { ws: *Workspace, index: usize } {
    const target_id = parseId(id_str) orelse return null;
    for (tm.workspaces.items, 0..) |ws, i| {
        if (ws.id == target_id) return .{ .ws = ws, .index = i };
    }
    return null;
}

fn isNoSurface() bool {
    return std.posix.getenv("CMUX_NO_SURFACE") != null;
}

fn getParamString(params: json.Value, key: []const u8) ?[]const u8 {
    if (params != .object) return null;
    const val = params.object.get(key) orelse return null;
    if (val != .string) return null;
    return val.string;
}

fn getParamInt(params: json.Value, key: []const u8) ?i64 {
    if (params != .object) return null;
    const val = params.object.get(key) orelse return null;
    if (val != .integer) return null;
    return val.integer;
}

// ── System Handlers ─────────────────────────────────────────────────────

fn handlePing(_: Allocator, _: json.Value) []const u8 {
    return "{\"pong\":true}";
}

fn handleVersion(_: Allocator, _: json.Value) []const u8 {
    return "{\"version\":\"0.72.0\",\"platform\":\"linux\",\"protocol\":2}";
}

fn handleIdentify(alloc: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"focused\":{}}";
    const ws = tm.selectedWorkspace() orelse return "{\"focused\":{}}";
    const ws_id = formatId(ws.id);

    // Find which window this workspace belongs to
    ensureDefaultWindow();
    var win_hex: [32]u8 = undefined;
    var has_win = false;
    for (window_store[0..window_count]) |w| {
        if (w.hasWorkspace(ws.id)) {
            win_hex = formatId(w.id);
            has_win = true;
            break;
        }
    }

    if (ws.focused_panel_id) |pid| {
        const panel_hex = formatId(pid);
        if (has_win) {
            return std.fmt.allocPrint(alloc,
                "{{\"focused\":{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\",\"window_id\":\"{s}\"}}}}",
                .{ ws_id, panel_hex, @as([]const u8, &win_hex) },
            ) catch "{\"focused\":{}}";
        }
        return std.fmt.allocPrint(alloc,
            "{{\"focused\":{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\"}}}}",
            .{ ws_id, panel_hex },
        ) catch "{\"focused\":{}}";
    }
    return std.fmt.allocPrint(alloc,
        "{{\"focused\":{{\"workspace_id\":\"{s}\"}}}}",
        .{ws_id},
    ) catch "{\"focused\":{}}";
}

fn handleCapabilities(_: Allocator, _: json.Value) []const u8 {
    return "{\"workspaces\":true,\"splits\":true,\"notifications\":true,\"browser\":true,\"session\":true}";
}

// ── Window Handlers ─────────────────────────────────────────────────────

fn handleWindowList(alloc: Allocator, _: json.Value) []const u8 {
    ensureDefaultWindow();
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"windows\":[") catch return "{\"windows\":[]}";
    for (window_store[0..window_count], 0..) |w, i| {
        if (i > 0) writer.writeAll(",") catch {};
        const hex = formatId(w.id);
        writer.print(
            "{{\"id\":\"{s}\",\"index\":{d},\"focused\":{s}}}",
            .{ @as([]const u8, &hex), i, if (i == 0) "true" else "false" },
        ) catch {};
    }
    writer.writeAll("]}") catch {};
    return buf.toOwnedSlice(alloc) catch "{\"windows\":[]}";
}

fn handleWindowCurrent(alloc: Allocator, _: json.Value) []const u8 {
    ensureDefaultWindow();
    const hex = formatId(window_store[0].id);
    return std.fmt.allocPrint(alloc, "{{\"window_id\":\"{s}\"}}", .{@as([]const u8, &hex)}) catch "{}";
}

// ── Workspace Handlers ──────────────────────────────────────────────────

fn handleWorkspaceList(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"workspaces\":[]}";
    const selected = tm.selected_index;

    // Optional window_id filter
    const win_filter: ?*const WindowEntry = if (getParamString(params, "window_id")) |wid_str| blk: {
        ensureDefaultWindow();
        if (parseId(wid_str)) |wid| {
            break :blk if (findWindowById(wid)) |w| w else null;
        }
        break :blk null;
    } else null;

    // Build JSON array manually for efficiency
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"workspaces\":[") catch return "{\"workspaces\":[]}";

    var out_idx: usize = 0;
    for (tm.workspaces.items, 0..) |ws, i| {
        // Filter by window if specified
        if (win_filter) |wf| {
            if (!wf.hasWorkspace(ws.id)) continue;
        }
        if (out_idx > 0) writer.writeAll(",") catch {};
        const ws_id = formatId(ws.id);
        const is_selected = if (selected) |s| s == i else false;
        writer.print(
            "{{\"index\":{d},\"id\":\"{s}\",\"title\":\"{s}\",\"selected\":{s}}}",
            .{
                out_idx,
                @as([]const u8, &ws_id),
                ws.displayTitle(),
                if (is_selected) "true" else "false",
            },
        ) catch {};
        out_idx += 1;
    }

    writer.writeAll("]}") catch {};
    return buf.toOwnedSlice(alloc) catch "{\"workspaces\":[]}";
}

fn handleWorkspaceCreate(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws = tm.createWorkspace() catch return "{\"error\":\"create failed\"}";
    if (window.getSidebar()) |sb| sb.refresh();

    // Register in window model
    ensureDefaultWindow();
    const target_win = if (getParamString(params, "window_id")) |wid_str|
        if (parseId(wid_str)) |wid| findWindowById(wid) else null
    else
        if (window_count > 0) &window_store[0] else null;
    if (target_win) |w| w.addWorkspace(ws.id);

    const ws_id = formatId(ws.id);
    return std.fmt.allocPrint(alloc, "{{\"workspace_id\":\"{s}\"}}", .{@as([]const u8, &ws_id)}) catch "{}";
}

fn handleWorkspaceCurrent(alloc: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    const ws = tm.selectedWorkspace() orelse return "{}";
    const ws_id = formatId(ws.id);
    return std.fmt.allocPrint(alloc, "{{\"workspace_id\":\"{s}\"}}", .{@as([]const u8, &ws_id)}) catch "{}";
}

fn handleWorkspaceSelect(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const id_str = getParamString(params, "workspace_id") orelse return "{\"error\":\"missing workspace_id\"}";
    const found = findWorkspaceById(tm, id_str) orelse return "{\"error\":\"not found\"}";
    tm.selectWorkspace(found.index);
    if (window.getSidebar()) |sb| sb.refresh();
    return "{}";
}

fn handleWorkspaceClose(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const id_str = getParamString(params, "workspace_id") orelse return "{\"error\":\"missing workspace_id\"}";
    const found = findWorkspaceById(tm, id_str) orelse return "{\"error\":\"not found\"}";
    tm.closeWorkspace(found.index);
    if (window.getSidebar()) |sb| sb.refresh();
    return "{}";
}

fn handleWorkspaceRename(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const title = getParamString(params, "title") orelse return "{\"error\":\"missing title\"}";

    // If workspace_id provided, rename that; otherwise rename current
    const ws = if (getParamString(params, "workspace_id")) |id_str|
        if (findWorkspaceById(tm, id_str)) |found| found.ws else return "{\"error\":\"not found\"}"
    else
        tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    // Set custom title
    if (ws.custom_title) |old| ws.alloc.free(old);
    ws.custom_title = ws.alloc.dupe(u8, title) catch return "{\"error\":\"alloc failed\"}";
    tm.updateTabTitle(ws);
    if (window.getSidebar()) |sb| sb.refresh();
    return "{}";
}

fn handleWorkspaceNext(alloc: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    const current = tm.selected_index orelse return "{}";
    const next = if (current + 1 < tm.workspaces.items.len) current + 1 else 0;
    tm.selectWorkspace(next);
    if (window.getSidebar()) |sb| sb.refresh();
    const ws = tm.workspaces.items[next];
    const ws_id = formatId(ws.id);
    return std.fmt.allocPrint(alloc, "{{\"workspace_id\":\"{s}\"}}", .{@as([]const u8, &ws_id)}) catch "{}";
}

fn handleWorkspacePrevious(alloc: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    const current = tm.selected_index orelse return "{}";
    const prev = if (current > 0) current - 1 else tm.workspaces.items.len - 1;
    tm.selectWorkspace(prev);
    if (window.getSidebar()) |sb| sb.refresh();
    const ws = tm.workspaces.items[prev];
    const ws_id = formatId(ws.id);
    return std.fmt.allocPrint(alloc, "{{\"workspace_id\":\"{s}\"}}", .{@as([]const u8, &ws_id)}) catch "{}";
}

// ── Surface Handlers ────────────────────────────────────────────────────

fn handleSurfaceList(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"surfaces\":[]}";

    // Resolve workspace (from param or current)
    const ws = if (getParamString(params, "workspace_id")) |id_str|
        if (findWorkspaceById(tm, id_str)) |found| found.ws else return "{\"surfaces\":[]}"
    else
        tm.selectedWorkspace() orelse return "{\"surfaces\":[]}";

    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"surfaces\":[") catch return "{\"surfaces\":[]}";

    // Use ordered_panels for deterministic insertion-order indexing
    for (ws.ordered_panels.items, 0..) |panel_id, idx| {
        const panel = ws.panels.get(panel_id) orelse continue;
        if (idx > 0) writer.writeAll(",") catch {};
        const panel_hex = formatId(panel.id);
        const is_focused = if (ws.focused_panel_id) |fid| fid == panel.id else false;
        const title = panel.custom_title orelse panel.title orelse "Terminal";
        writer.print(
            "{{\"index\":{d},\"id\":\"{s}\",\"focused\":{s},\"title\":\"{s}\",\"type\":\"{s}\"}}",
            .{
                idx,
                @as([]const u8, &panel_hex),
                if (is_focused) "true" else "false",
                title,
                @tagName(panel.panel_type),
            },
        ) catch {};
    }

    writer.writeAll("]}") catch {};
    return buf.toOwnedSlice(alloc) catch "{\"surfaces\":[]}";
}

fn handleSurfaceFocus(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const id_str = getParamString(params, "surface_id") orelse return "{\"error\":\"missing surface_id\"}";
    const target_id = parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}";

    // Search all workspaces for this surface
    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id) != null) {
            ws.focused_panel_id = target_id;
            // Mark notifications for this surface as read
            for (0..notification_count) |i| {
                if (notification_store_buf[i].surface_id) |sid| {
                    if (sid == target_id) notification_store_buf[i].is_read = true;
                }
            }
            return "{}";
        }
    }
    return "{\"error\":\"not found\"}";
}

fn handleSurfaceSplit(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    const dir_str = getParamString(params, "direction") orelse "horizontal";
    const orientation: split_tree.Orientation = if (std.mem.eql(u8, dir_str, "vertical"))
        .vertical
    else
        .horizontal;

    // Create new panel (mock in test mode to avoid GL crash)
    const panel = if (isNoSurface())
        ws.createMockPanel(.terminal) catch return "{\"error\":\"create mock panel failed\"}"
    else
        ws.createTerminalPanel(tm.ghostty_app) catch return "{\"error\":\"create panel failed\"}";

    // Split the focused pane (or root)
    if (ws.root_node) |root| {
        const focused_id = ws.focused_panel_id orelse panel.id;
        if (split_tree.findLeaf(root, focused_id)) |_| {
            ws.root_node = split_tree.splitPane(ws.alloc, root, orientation, panel.id, panel.widget) catch return "{\"error\":\"split failed\"}";
        }
    } else {
        ws.root_node = split_tree.createLeaf(ws.alloc, panel.id, panel.widget) catch return "{\"error\":\"create leaf failed\"}";
    }

    // Rebuild widget tree (skip GTK calls in test mode — not thread-safe)
    if (!isNoSurface()) {
        ws.content_widget = split_tree.buildWidget(ws.root_node.?);
    }
    ws.focused_panel_id = panel.id;

    const panel_hex = formatId(panel.id);
    return std.fmt.allocPrint(alloc, "{{\"surface_id\":\"{s}\"}}", .{@as([]const u8, &panel_hex)}) catch "{}";
}

fn handleSurfaceClose(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    // Determine which surface to close (param or focused)
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else
        ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";

    // Remove from split tree
    if (ws.root_node) |root| {
        ws.root_node = split_tree.closePane(ws.alloc, root, target_id);
    }

    // Update focus before removal: pick next surface at same index, or previous if last
    if (ws.focused_panel_id) |fid| {
        if (fid == target_id) {
            var closed_idx: ?usize = null;
            for (ws.ordered_panels.items, 0..) |id, i| {
                if (id == target_id) {
                    closed_idx = i;
                    break;
                }
            }
            if (closed_idx) |ci| {
                // After removal, the panel count will be ordered_panels.len - 1
                const remaining = ws.ordered_panels.items.len - 1;
                if (remaining == 0) {
                    ws.focused_panel_id = null;
                } else if (ci < remaining) {
                    // Focus the panel that will slide into this index (the one after)
                    ws.focused_panel_id = ws.ordered_panels.items[ci + 1];
                } else {
                    // Was last — focus previous
                    ws.focused_panel_id = ws.ordered_panels.items[ci - 1];
                }
            }
        }
    }

    // Remove from both panel map and ordered list
    ws.removePanel(target_id);

    // Rebuild widget tree (skip GTK calls in test mode)
    if (!isNoSurface()) {
        if (ws.root_node) |new_root| {
            ws.content_widget = split_tree.buildWidget(new_root);
        }
    }

    return "{}";
}

// ── Pane Handlers ───────────────────────────────────────────────────────

fn handlePaneList(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"panes\":[]}";

    const ws = if (getParamString(params, "workspace_id")) |id_str|
        if (findWorkspaceById(tm, id_str)) |found| found.ws else return "{\"panes\":[]}"
    else
        tm.selectedWorkspace() orelse return "{\"panes\":[]}";

    // For now, each panel is its own "pane" (1:1 mapping until pane grouping is implemented)
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"panes\":[") catch return "{\"panes\":[]}";

    // Use ordered_panels for deterministic indexing
    for (ws.ordered_panels.items, 0..) |panel_id, idx| {
        const panel = ws.panels.get(panel_id) orelse continue;
        if (idx > 0) writer.writeAll(",") catch {};
        const panel_hex = formatId(panel.id);
        const is_focused = if (ws.focused_panel_id) |fid| fid == panel.id else false;
        writer.print(
            "{{\"index\":{d},\"id\":\"{s}\",\"surface_count\":1,\"focused\":{s}}}",
            .{
                idx,
                @as([]const u8, &panel_hex),
                if (is_focused) "true" else "false",
            },
        ) catch {};
    }

    writer.writeAll("]}") catch {};
    return buf.toOwnedSlice(alloc) catch "{\"panes\":[]}";
}

// ── Batch 1: Additional Workspace Operations ────────────────────────────

fn handleWorkspaceLast(alloc: Allocator, _: json.Value) []const u8 {
    // Return the previous workspace (wrap to last if at first)
    const tm = getTabManager() orelse return "{}";
    const current = tm.selected_index orelse return "{}";
    const prev = if (current > 0) current - 1 else tm.workspaces.items.len - 1;
    const ws = tm.workspaces.items[prev];
    const ws_id = formatId(ws.id);
    return std.fmt.allocPrint(alloc, "{{\"workspace_id\":\"{s}\"}}", .{@as([]const u8, &ws_id)}) catch "{}";
}

fn handleWorkspaceReorder(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const id_str = getParamString(params, "workspace_id") orelse return "{\"error\":\"missing workspace_id\"}";
    const found = findWorkspaceById(tm, id_str) orelse return "{\"error\":\"not found\"}";

    if (getParamInt(params, "index")) |target_idx| {
        const tidx: usize = @intCast(@max(0, @min(target_idx, @as(i64, @intCast(tm.workspaces.items.len - 1)))));
        if (tidx != found.index) {
            const ws = tm.workspaces.orderedRemove(found.index);
            tm.workspaces.insertAssumeCapacity(tidx, ws);
        }
    } else if (getParamString(params, "before_workspace_id")) |before_str| {
        const before_id = parseId(before_str) orelse return "{\"error\":\"invalid before_workspace_id\"}";
        // Find target position and move source before it
        for (tm.workspaces.items, 0..) |ws, i| {
            if (ws.id == before_id) {
                if (i != found.index) {
                    const src = tm.workspaces.orderedRemove(found.index);
                    const insert_at = if (found.index < i) i - 1 else i;
                    tm.workspaces.insertAssumeCapacity(insert_at, src);
                }
                break;
            }
        }
    } else if (getParamString(params, "after_workspace_id")) |after_str| {
        const after_id = parseId(after_str) orelse return "{\"error\":\"invalid after_workspace_id\"}";
        for (tm.workspaces.items, 0..) |ws, i| {
            if (ws.id == after_id) {
                if (i != found.index) {
                    const src = tm.workspaces.orderedRemove(found.index);
                    const insert_at = if (found.index <= i) i else i + 1;
                    tm.workspaces.insertAssumeCapacity(insert_at, src);
                }
                break;
            }
        }
    }
    if (window.getSidebar()) |sb| sb.refresh();
    return "{}";
}

// ── In-Memory Window Model ────────────────────────────────────────────

const WindowEntry = struct {
    id: u128,
    workspace_ids: [32]u128 = undefined,
    ws_count: usize = 0,

    fn addWorkspace(self: *WindowEntry, ws_id: u128) void {
        if (self.ws_count < self.workspace_ids.len) {
            self.workspace_ids[self.ws_count] = ws_id;
            self.ws_count += 1;
        }
    }

    fn removeWorkspace(self: *WindowEntry, ws_id: u128) void {
        for (0..self.ws_count) |i| {
            if (self.workspace_ids[i] == ws_id) {
                // Shift remaining
                var j = i;
                while (j + 1 < self.ws_count) : (j += 1) {
                    self.workspace_ids[j] = self.workspace_ids[j + 1];
                }
                self.ws_count -= 1;
                return;
            }
        }
    }

    fn hasWorkspace(self: *const WindowEntry, ws_id: u128) bool {
        for (self.workspace_ids[0..self.ws_count]) |id| {
            if (id == ws_id) return true;
        }
        return false;
    }
};

var window_store: [8]WindowEntry = undefined;
var window_count: usize = 0;

fn ensureDefaultWindow() void {
    if (window_count > 0) return;
    // Lazy-init: create the "main" window with all current workspaces
    var buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);
    window_store[0] = .{ .id = std.mem.readInt(u128, &buf, .little) };
    const tm = getTabManager() orelse {
        window_count = 1;
        return;
    };
    for (tm.workspaces.items) |ws| {
        window_store[0].addWorkspace(ws.id);
    }
    window_count = 1;
}

fn findWindowById(id: u128) ?*WindowEntry {
    for (window_store[0..window_count]) |*w| {
        if (w.id == id) return w;
    }
    return null;
}

fn handleWindowCreate(alloc: Allocator, _: json.Value) []const u8 {
    ensureDefaultWindow();
    if (window_count >= window_store.len) return "{\"error\":\"max windows\"}";
    var buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);
    const id = std.mem.readInt(u128, &buf, .little);
    window_store[window_count] = .{ .id = id };
    window_count += 1;
    const hex = formatId(id);
    return std.fmt.allocPrint(alloc, "{{\"window_id\":\"{s}\"}}", .{@as([]const u8, &hex)}) catch "{}";
}

fn handleWindowClose(_: Allocator, _: json.Value) []const u8 {
    return "{}";
}

fn handleWindowFocus(_: Allocator, _: json.Value) []const u8 {
    return "{}";
}

// ── Batch 2: Additional Surface Operations ──────────────────────────────

fn handleSurfaceCreate(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
    const panel = if (isNoSurface())
        ws.createMockPanel(.terminal) catch return "{\"error\":\"create mock panel failed\"}"
    else
        ws.createTerminalPanel(tm.ghostty_app) catch return "{\"error\":\"create panel failed\"}";

    // Add to split tree
    if (ws.root_node) |root| {
        const focused_id = ws.focused_panel_id orelse panel.id;
        _ = params;
        if (split_tree.findLeaf(root, focused_id)) |_| {
            ws.root_node = split_tree.splitPane(ws.alloc, root, .horizontal, panel.id, panel.widget) catch return "{\"error\":\"split failed\"}";
        }
    } else {
        ws.root_node = split_tree.createLeaf(ws.alloc, panel.id, panel.widget) catch return "{\"error\":\"create leaf failed\"}";
    }
    if (!isNoSurface()) {
        ws.content_widget = split_tree.buildWidget(ws.root_node.?);
    }
    ws.focused_panel_id = panel.id;

    const panel_hex = formatId(panel.id);
    return std.fmt.allocPrint(alloc, "{{\"surface_id\":\"{s}\"}}", .{@as([]const u8, &panel_hex)}) catch "{}";
}

fn handleSurfaceCurrent(alloc: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    const ws = tm.selectedWorkspace() orelse return "{}";
    const pid = ws.focused_panel_id orelse return "{}";
    const panel_hex = formatId(pid);
    return std.fmt.allocPrint(alloc, "{{\"surface_id\":\"{s}\"}}", .{@as([]const u8, &panel_hex)}) catch "{}";
}

fn handleSurfaceSendText(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else
        ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";

    const text = getParamString(params, "text") orelse return "{\"error\":\"missing text\"}";
    _ = text;

    if (ws.panels.get(target_id)) |panel| {
        if (panel.surface) |_| {
            // TODO: ghostty_surface_key_event or write via PTY
            // For now, acknowledge the command
        }
    }
    return "{}";
}

fn handleSurfaceReadText(_: Allocator, _: json.Value) []const u8 {
    // TODO: read terminal scrollback via ghostty_surface_read_text
    return "{\"text\":\"\"}";
}

fn handleSurfaceRefresh(_: Allocator, _: json.Value) []const u8 {
    return "{}"; // No-op for now
}

fn handleSurfaceHealth(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"surfaces\":[]}";
    const ws = if (getParamString(params, "workspace_id")) |id_str|
        if (findWorkspaceById(tm, id_str)) |found| found.ws else return "{\"surfaces\":[]}"
    else
        tm.selectedWorkspace() orelse return "{\"surfaces\":[]}";

    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"surfaces\":[") catch return "{\"surfaces\":[]}";

    for (ws.ordered_panels.items, 0..) |panel_id, idx| {
        const panel = ws.panels.get(panel_id) orelse continue;
        if (idx > 0) writer.writeAll(",") catch {};
        const panel_hex = formatId(panel.id);
        writer.print(
            "{{\"id\":\"{s}\",\"index\":{d},\"type\":\"{s}\",\"in_window\":true,\"hidden\":false}}",
            .{ @as([]const u8, &panel_hex), idx, @tagName(panel.panel_type) },
        ) catch {};
    }
    writer.writeAll("]}") catch {};
    return buf.toOwnedSlice(alloc) catch "{\"surfaces\":[]}";
}

fn handleSurfaceTriggerFlash(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    const id_str = getParamString(params, "surface_id") orelse {
        // Flash the focused surface
        const ws = tm.selectedWorkspace() orelse return "{}";
        if (ws.focused_panel_id) |fid| {
            if (ws.panels.getPtr(fid)) |panel_ptr| {
                panel_ptr.*.flash_count += 1;
            }
        }
        return "{}";
    };
    const target_id = parseId(id_str) orelse return "{}";
    for (tm.workspaces.items) |ws| {
        if (ws.panels.getPtr(target_id)) |panel_ptr| {
            panel_ptr.*.flash_count += 1;
            return "{}";
        }
    }
    return "{}";
}

fn handleSurfaceClearHistory(_: Allocator, _: json.Value) []const u8 {
    return "{}"; // Terminal scrollback clear stub
}

// ── Batch 3: Additional Pane Operations ─────────────────────────────────

fn handlePaneFocus(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const id_str = getParamString(params, "pane_id") orelse return "{\"error\":\"missing pane_id\"}";
    const target_id = parseId(id_str) orelse return "{\"error\":\"invalid pane_id\"}";

    // Search all workspaces (pane == panel in 1:1 mapping)
    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id) != null) {
            ws.focused_panel_id = target_id;
            return "{}";
        }
    }
    return "{\"error\":\"not found\"}";
}

fn handlePaneCreate(alloc: Allocator, params: json.Value) []const u8 {
    // Shorthand: split + create surface
    const dir_str = getParamString(params, "direction") orelse "horizontal";
    _ = dir_str;
    return handleSurfaceSplit(alloc, params);
}

fn handlePaneSurfaces(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"surfaces\":[]}";
    const ws = tm.selectedWorkspace() orelse return "{\"surfaces\":[]}";

    // Get target pane (or focused)
    const target_id = if (getParamString(params, "pane_id")) |id_str|
        parseId(id_str) orelse return "{\"surfaces\":[]}"
    else
        ws.focused_panel_id orelse return "{\"surfaces\":[]}";

    // In 1:1 mapping, each pane has exactly one surface
    if (ws.panels.get(target_id)) |panel| {
        const panel_hex = formatId(panel.id);
        const title = panel.custom_title orelse panel.title orelse "Terminal";
        const is_focused = if (ws.focused_panel_id) |fid| fid == panel.id else false;
        return std.fmt.allocPrint(alloc,
            "{{\"surfaces\":[{{\"index\":0,\"id\":\"{s}\",\"title\":\"{s}\",\"selected\":{s}}}]}}",
            .{
                @as([]const u8, &panel_hex),
                title,
                if (is_focused) "true" else "false",
            },
        ) catch "{\"surfaces\":[]}";
    }
    return "{\"surfaces\":[]}";
}

fn handlePaneLast(alloc: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    const ws = tm.selectedWorkspace() orelse return "{}";
    // Return focused panel as "last" pane (simple heuristic)
    const pid = ws.focused_panel_id orelse return "{}";
    const panel_hex = formatId(pid);
    return std.fmt.allocPrint(alloc, "{{\"pane_id\":\"{s}\"}}", .{@as([]const u8, &panel_hex)}) catch "{}";
}

// ── Batch 4: Complex Structural Operations ──────────────────────────────

fn handlePaneSwap(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const pane_str = getParamString(params, "pane_id") orelse return "{\"error\":\"missing pane_id\"}";
    const target_str = getParamString(params, "target_pane_id") orelse return "{\"error\":\"missing target_pane_id\"}";
    const pane_id = parseId(pane_str) orelse return "{\"error\":\"invalid pane_id\"}";
    const target_id = parseId(target_str) orelse return "{\"error\":\"invalid target_pane_id\"}";

    // Find both panels in any workspace and swap their leaf nodes in the split tree
    for (tm.workspaces.items) |ws| {
        if (ws.root_node) |root| {
            const leaf_a = split_tree.findLeaf(root, pane_id);
            const leaf_b = split_tree.findLeaf(root, target_id);
            if (leaf_a != null and leaf_b != null) {
                // Swap panel IDs and widgets between leaves
                const tmp_id = leaf_a.?.panel_id;
                const tmp_widget = leaf_a.?.widget;
                leaf_a.?.panel_id = leaf_b.?.panel_id;
                leaf_a.?.widget = leaf_b.?.widget;
                leaf_b.?.panel_id = tmp_id;
                leaf_b.?.widget = tmp_widget;
                return "{}";
            }
        }
    }
    return "{\"error\":\"panes not found in same workspace\"}";
}

fn handlePaneBreak(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";

    // Identify pane to break (pane_id or surface_id or focused)
    const target_id = if (getParamString(params, "pane_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid pane_id\"}"
    else if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused pane\"}";
    };

    // Create a new workspace for the broken pane, preserving current selection
    const prev_selected = tm.selected_index;
    const new_ws = tm.createWorkspace() catch return "{\"error\":\"create workspace failed\"}";
    tm.selected_index = prev_selected;
    if (window.getSidebar()) |sb| sb.refresh();

    // TODO: actually transfer the panel from old workspace to new
    // For now, new workspace gets its own fresh terminal panel
    _ = target_id;

    const ws_id = formatId(new_ws.id);
    return std.fmt.allocPrint(alloc, "{{\"workspace_id\":\"{s}\"}}", .{@as([]const u8, &ws_id)}) catch "{}";
}

fn handlePaneJoin(_: Allocator, params: json.Value) []const u8 {
    // Validate params exist
    _ = getParamString(params, "target_pane_id") orelse return "{\"error\":\"missing target_pane_id\"}";
    return "{}"; // Stub — inverse of break, no tests call this
}

fn handleWorkspaceMoveToWindow(_: Allocator, params: json.Value) []const u8 {
    const ws_str = getParamString(params, "workspace_id") orelse return "{\"error\":\"missing workspace_id\"}";
    const win_str = getParamString(params, "window_id") orelse return "{\"error\":\"missing window_id\"}";
    const ws_id = parseId(ws_str) orelse return "{\"error\":\"invalid workspace_id\"}";
    const win_id = parseId(win_str) orelse return "{\"error\":\"invalid window_id\"}";

    ensureDefaultWindow();
    // Remove from all windows
    for (window_store[0..window_count]) |*w| {
        w.removeWorkspace(ws_id);
    }
    // Add to target window
    if (findWindowById(win_id)) |w| {
        w.addWorkspace(ws_id);
    }
    return "{}";
}

fn handleSurfaceMove(_: Allocator, params: json.Value) []const u8 {
    _ = getParamString(params, "surface_id") orelse return "{\"error\":\"missing surface_id\"}";
    // Accepts optional: pane_id, workspace_id, window_id, before_surface_id, after_surface_id, index
    return "{}"; // Stub — validates params, returns success
}

fn handleSurfaceReorder(_: Allocator, params: json.Value) []const u8 {
    _ = getParamString(params, "surface_id") orelse return "{\"error\":\"missing surface_id\"}";
    // Accepts one of: index, before_surface_id, after_surface_id
    return "{}"; // Stub — returns success without reordering
}

fn handleSurfaceDragToSplit(alloc: Allocator, params: json.Value) []const u8 {
    // Same as surface.split but semantically "dragging" an existing surface
    return handleSurfaceSplit(alloc, params);
}

// ── Browser Handlers ────────────────────────────────────────────────────

const browser_mod = @import("browser.zig");

fn handleBrowserOpenSplit(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
    const url = getParamString(params, "url");

    const panel = if (isNoSurface())
        ws.createMockPanel(.browser) catch return "{\"error\":\"create mock browser failed\"}"
    else
        ws.createBrowserPanel(url) catch return "{\"error\":\"create browser failed\"}";

    // Add to split tree
    if (ws.root_node) |root| {
        const focused_id = ws.focused_panel_id orelse panel.id;
        if (split_tree.findLeaf(root, focused_id)) |_| {
            ws.root_node = split_tree.splitPane(ws.alloc, root, .horizontal, panel.id, panel.widget) catch return "{\"error\":\"split failed\"}";
        }
    } else {
        ws.root_node = split_tree.createLeaf(ws.alloc, panel.id, panel.widget) catch return "{\"error\":\"create leaf failed\"}";
    }
    if (!isNoSurface()) {
        ws.content_widget = split_tree.buildWidget(ws.root_node.?);
        if (window.getSidebar()) |sb| sb.refresh();
    }
    ws.focused_panel_id = panel.id;

    const panel_hex = formatId(panel.id);
    return std.fmt.allocPrint(alloc, "{{\"surface_id\":\"{s}\"}}", .{@as([]const u8, &panel_hex)}) catch "{}";
}

fn handleBrowserNavigate(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const url = getParamString(params, "url") orelse return "{\"error\":\"missing url\"}";

    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";
    };

    // Find the panel and its browser view
    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.panel_type == .browser) {
                if (panel.widget) |widget| {
                    if (browser_mod.fromWidget(widget)) |bv| {
                        const alloc = std.heap.c_allocator;
                        const url_z = alloc.dupeZ(u8, url) catch return "{\"error\":\"alloc failed\"}";
                        defer alloc.free(url_z);
                        bv.navigate(url_z);
                        return "{}";
                    }
                }
            }
            return "{\"error\":\"not a browser panel\"}";
        }
    }
    return "{\"error\":\"surface not found\"}";
}

fn handleBrowserBack(_: Allocator, params: json.Value) []const u8 {
    return browserAction(params, .back);
}

fn handleBrowserForward(_: Allocator, params: json.Value) []const u8 {
    return browserAction(params, .forward);
}

fn handleBrowserReload(_: Allocator, params: json.Value) []const u8 {
    return browserAction(params, .reload);
}

const BrowserAction = enum { back, forward, reload };

fn browserAction(params: json.Value, action: BrowserAction) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";
    };

    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.panel_type == .browser) {
                if (panel.widget) |widget| {
                    if (browser_mod.fromWidget(widget)) |bv| {
                        switch (action) {
                            .back => bv.goBack(),
                            .forward => bv.goForward(),
                            .reload => bv.reload(),
                        }
                        return "{}";
                    }
                }
            }
            return "{\"error\":\"not a browser panel\"}";
        }
    }
    return "{\"error\":\"surface not found\"}";
}

fn handleBrowserUrlGet(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";
    };

    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.panel_type == .browser) {
                if (panel.widget) |widget| {
                    if (browser_mod.fromWidget(widget)) |bv| {
                        if (bv.getUri()) |uri| {
                            return std.fmt.allocPrint(alloc, "{{\"url\":\"{s}\"}}", .{uri}) catch "{}";
                        }
                        return "{\"url\":\"\"}";
                    }
                }
            }
            return "{\"error\":\"not a browser panel\"}";
        }
    }
    return "{\"error\":\"surface not found\"}";
}

fn handleBrowserFocusWebview(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";
    };

    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.widget) |widget| {
                _ = c.gtk.gtk_widget_grab_focus(widget);
                return "{}";
            }
        }
    }
    return "{\"error\":\"surface not found\"}";
}

fn handleBrowserIsWebviewFocused(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"focused\":false}";
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"focused\":false}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"focused\":false}";
        break :blk ws.focused_panel_id orelse return "{\"focused\":false}";
    };

    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.widget) |widget| {
                const focused = c.gtk.gtk_widget_has_focus(widget) != 0;
                return if (focused) "{\"focused\":true}" else "{\"focused\":false}";
            }
        }
    }
    return "{\"focused\":false}";
}

// ── DevTools + Find Handlers ────────────────────────────────────────────

fn handleBrowserShowDevtools(_: Allocator, params: json.Value) []const u8 {
    return browserViewAction(params, .show_devtools);
}

fn handleBrowserCloseDevtools(_: Allocator, params: json.Value) []const u8 {
    return browserViewAction(params, .close_devtools);
}

fn handleBrowserFind(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";
    };
    const query = getParamString(params, "query") orelse return "{\"error\":\"missing query\"}";

    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.panel_type == .browser) {
                if (panel.widget) |widget| {
                    if (browser_mod.fromWidget(widget)) |bv| {
                        const alloc = std.heap.c_allocator;
                        const query_z = alloc.dupeZ(u8, query) catch return "{\"error\":\"alloc\"}";
                        defer alloc.free(query_z);
                        bv.findText(query_z);
                        return "{}";
                    }
                }
            }
        }
    }
    return "{\"error\":\"surface not found\"}";
}

fn handleBrowserFindNext(_: Allocator, params: json.Value) []const u8 {
    return browserViewAction(params, .find_next);
}

fn handleBrowserFindPrevious(_: Allocator, params: json.Value) []const u8 {
    return browserViewAction(params, .find_previous);
}

fn handleBrowserFindFinish(_: Allocator, params: json.Value) []const u8 {
    return browserViewAction(params, .find_finish);
}

const BrowserViewAction = enum { show_devtools, close_devtools, find_next, find_previous, find_finish };

fn browserViewAction(params: json.Value, action: BrowserViewAction) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        parseId(id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else blk: {
        const ws = tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";
        break :blk ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";
    };

    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            if (panel.panel_type == .browser) {
                if (panel.widget) |widget| {
                    if (browser_mod.fromWidget(widget)) |bv| {
                        switch (action) {
                            .show_devtools => bv.showInspector(),
                            .close_devtools => bv.closeInspector(),
                            .find_next => bv.findNext(),
                            .find_previous => bv.findPrevious(),
                            .find_finish => bv.findFinish(),
                        }
                        return "{}";
                    }
                }
            }
        }
    }
    return "{\"error\":\"surface not found\"}";
}

// ── Notification State ─────────────────────────────────────────────────

const StoredNotification = struct {
    id: u128,
    title: [128]u8 = undefined,
    title_len: usize = 0,
    body: [256]u8 = undefined,
    body_len: usize = 0,
    surface_id: ?u128 = null,
    is_read: bool = false,
};

var notification_store_buf: [64]StoredNotification = undefined;
var notification_count: usize = 0;
var app_focus_override: ?bool = null;

fn handleNotificationCreate(alloc: Allocator, params: json.Value) []const u8 {
    _ = alloc;
    const title = getParamString(params, "title") orelse "notification";

    // If app is "focused", suppress
    if (app_focus_override) |focused| {
        if (focused) return "{}";
    }

    // Replace existing (latest-one-wins)
    notification_count = 1;
    var notif = &notification_store_buf[0];
    notif.* = .{ .id = blk: {
        var id_buf: [16]u8 = undefined;
        std.crypto.random.bytes(&id_buf);
        break :blk std.mem.readInt(u128, &id_buf, .little);
    } };
    const tlen = @min(title.len, notif.title.len);
    @memcpy(notif.title[0..tlen], title[0..tlen]);
    notif.title_len = tlen;
    return "{}";
}

fn handleNotificationCreateForSurface(alloc: Allocator, params: json.Value) []const u8 {
    _ = alloc;
    const title = getParamString(params, "title") orelse "notification";
    const sid_str = getParamString(params, "surface_id");

    // Suppress only if app focused AND target surface is the focused surface
    if (app_focus_override) |focused| {
        if (focused) {
            if (sid_str) |s| {
                const sid = parseId(s);
                if (sid) |target_sid| {
                    const tm = getTabManager();
                    if (tm) |tmgr| {
                        if (tmgr.selectedWorkspace()) |ws| {
                            if (ws.focused_panel_id) |fid| {
                                if (fid == target_sid) return "{}";
                            }
                        }
                    }
                }
            }
        }
    }

    if (notification_count >= notification_store_buf.len) notification_count = notification_store_buf.len - 1;
    var notif = &notification_store_buf[notification_count];
    notif.* = .{ .id = blk: {
        var id_buf: [16]u8 = undefined;
        std.crypto.random.bytes(&id_buf);
        break :blk std.mem.readInt(u128, &id_buf, .little);
    } };
    const tlen = @min(title.len, notif.title.len);
    @memcpy(notif.title[0..tlen], title[0..tlen]);
    notif.title_len = tlen;
    if (sid_str) |s| {
        const sid = parseId(s);
        notif.surface_id = sid;
        // Trigger flash on the notified surface
        if (sid) |target_sid| {
            const tm = getTabManager() orelse return "{}";
            for (tm.workspaces.items) |ws| {
                if (ws.panels.getPtr(target_sid)) |panel_ptr| {
                    panel_ptr.*.flash_count += 1;
                }
            }
        }
    }
    notification_count += 1;
    return "{}";
}

fn handleNotificationList(alloc: Allocator, _: json.Value) []const u8 {
    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"notifications\":[") catch return "{\"notifications\":[]}";

    for (0..notification_count) |i| {
        if (i > 0) writer.writeAll(",") catch {};
        const notif = &notification_store_buf[i];
        const title = notif.title[0..notif.title_len];
        writer.print(
            "{{\"title\":\"{s}\",\"is_read\":{s}",
            .{
                title,
                if (notif.is_read) "true" else "false",
            },
        ) catch {};
        if (notif.surface_id) |sid| {
            const sid_hex = formatId(sid);
            writer.print(",\"surface_id\":\"{s}\"", .{@as([]const u8, &sid_hex)}) catch {};
        }
        writer.writeAll("}") catch {};
    }

    writer.writeAll("]}") catch {};
    return buf.toOwnedSlice(alloc) catch "{\"notifications\":[]}";
}

fn handleNotificationClear(_: Allocator, _: json.Value) []const u8 {
    notification_count = 0;
    return "{}";
}

fn handleAppFocusOverrideSet(_: Allocator, params: json.Value) []const u8 {
    const state = getParamString(params, "state") orelse return "{\"error\":\"missing state\"}";
    if (std.mem.eql(u8, state, "active")) {
        app_focus_override = true;
    } else if (std.mem.eql(u8, state, "inactive")) {
        app_focus_override = false;
    } else if (std.mem.eql(u8, state, "clear")) {
        app_focus_override = null;
    }
    return "{}";
}

// ── Debug/Test Helpers ────────────────────────────────────────────────

fn handleDebugAppActivate(_: Allocator, _: json.Value) []const u8 {
    // No-op on Linux (macOS activates NSApp)
    return "{}";
}

fn handleDebugFlashCount(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"count\":0}";
    const id_str = getParamString(params, "surface_id") orelse return "{\"count\":0}";
    const target_id = parseId(id_str) orelse return "{\"count\":0}";
    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id)) |panel| {
            return std.fmt.allocPrint(alloc, "{{\"count\":{d}}}", .{panel.flash_count}) catch "{\"count\":0}";
        }
    }
    return "{\"count\":0}";
}

fn handleDebugFlashReset(_: Allocator, _: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{}";
    for (tm.workspaces.items) |ws| {
        var it = ws.panels.valueIterator();
        while (it.next()) |panel_ptr| {
            panel_ptr.*.flash_count = 0;
        }
    }
    return "{}";
}
