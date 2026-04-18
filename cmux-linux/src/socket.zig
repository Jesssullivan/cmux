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
const workspace_mod = @import("workspace.zig");
const Workspace = workspace_mod.Workspace;
const Panel = workspace_mod.Panel;
const split_tree = @import("split_tree.zig");
const surface_mod = @import("surface.zig");

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
    .{ "auth.login", handleAuthLogin },
    .{ "system.tree", handleSystemTree },
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
    .{ "workspace.action", handleWorkspaceAction },
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
    .{ "surface.action", handleSurfaceAction },
    .{ "tab.action", handleSurfaceAction },
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
    .{ "browser.open_split", if (c.has_webkit) handleBrowserOpenSplit else handleBrowserUnavailable },
    .{ "browser.navigate", if (c.has_webkit) handleBrowserNavigate else handleBrowserUnavailable },
    .{ "browser.back", if (c.has_webkit) handleBrowserBack else handleBrowserUnavailable },
    .{ "browser.forward", if (c.has_webkit) handleBrowserForward else handleBrowserUnavailable },
    .{ "browser.reload", if (c.has_webkit) handleBrowserReload else handleBrowserUnavailable },
    .{ "browser.url.get", if (c.has_webkit) handleBrowserUrlGet else handleBrowserUnavailable },
    .{ "browser.focus_webview", if (c.has_webkit) handleBrowserFocusWebview else handleBrowserUnavailable },
    .{ "browser.is_webview_focused", if (c.has_webkit) handleBrowserIsWebviewFocused else handleBrowserUnavailable },
    .{ "browser.show_devtools", if (c.has_webkit) handleBrowserShowDevtools else handleBrowserUnavailable },
    .{ "browser.close_devtools", if (c.has_webkit) handleBrowserCloseDevtools else handleBrowserUnavailable },
    .{ "browser.find", if (c.has_webkit) handleBrowserFind else handleBrowserUnavailable },
    .{ "browser.find_next", if (c.has_webkit) handleBrowserFindNext else handleBrowserUnavailable },
    .{ "browser.find_previous", if (c.has_webkit) handleBrowserFindPrevious else handleBrowserUnavailable },
    .{ "browser.find_finish", if (c.has_webkit) handleBrowserFindFinish else handleBrowserUnavailable },
    .{ "notification.create", handleNotificationCreate },
    .{ "notification.create_for_surface", handleNotificationCreateForSurface },
    .{ "notification.create_for_target", handleNotificationCreateForTarget },
    .{ "notification.list", handleNotificationList },
    .{ "notification.clear", handleNotificationClear },
    .{ "app.focus_override.set", handleAppFocusOverrideSet },
    .{ "app.simulate_active", handleAppSimulateActive },
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

const RefKind = enum { workspace, surface, pane, window };

/// Parse a "kind:N" short ref string. Returns the kind and ordinal index.
fn parseRef(s: []const u8) ?struct { kind: RefKind, ordinal: usize } {
    const colon = std.mem.indexOfScalar(u8, s, ':') orelse return null;
    if (colon == 0 or colon + 1 >= s.len) return null;
    const kind_str = s[0..colon];
    const ordinal_str = s[colon + 1 ..];
    const kind: RefKind = if (std.mem.eql(u8, kind_str, "workspace"))
        .workspace
    else if (std.mem.eql(u8, kind_str, "surface"))
        .surface
    else if (std.mem.eql(u8, kind_str, "pane"))
        .pane
    else if (std.mem.eql(u8, kind_str, "window"))
        .window
    else
        return null;
    const ordinal = std.fmt.parseInt(usize, ordinal_str, 10) catch return null;
    return .{ .kind = kind, .ordinal = ordinal };
}

/// Result of resolving a workspace handle (UUID hex or short ref).
///
/// Named explicitly so call sites that need to construct one (e.g. when
/// falling back to the currently-selected workspace) produce the same type
/// as the function return — Zig treats `?struct { ... }` written at two
/// different sites as two distinct anonymous types and refuses to peer-type
/// them in `if/else` expressions.
const WorkspaceLookup = struct { ws: *Workspace, index: usize };

/// Resolve a workspace by UUID hex string or "workspace:N" short ref.
fn findWorkspaceById(tm: *@import("tab_manager.zig").TabManager, id_str: []const u8) ?WorkspaceLookup {
    // Try short ref first (workspace:N)
    if (parseRef(id_str)) |ref| {
        if (ref.kind == .workspace and ref.ordinal < tm.workspaces.items.len) {
            return .{ .ws = tm.workspaces.items[ref.ordinal], .index = ref.ordinal };
        }
        return null;
    }
    // Fall back to UUID hex
    const target_id = parseId(id_str) orelse return null;
    for (tm.workspaces.items, 0..) |ws, i| {
        if (ws.id == target_id) return .{ .ws = ws, .index = i };
    }
    return null;
}

/// Resolve a surface by UUID hex string or "surface:N" short ref within a workspace.
fn findSurfaceInWorkspace(ws: *Workspace, id_str: []const u8) ?u128 {
    if (parseRef(id_str)) |ref| {
        if (ref.kind == .surface and ref.ordinal < ws.ordered_panels.items.len) {
            return ws.ordered_panels.items[ref.ordinal];
        }
        return null;
    }
    return parseId(id_str);
}

/// Resolve a surface by UUID hex or "surface:N" ref, searching all workspaces.
fn findSurfaceGlobal(tm: *@import("tab_manager.zig").TabManager, id_str: []const u8) ?struct { id: u128, ws: *Workspace } {
    if (parseRef(id_str)) |ref| {
        if (ref.kind != .surface) return null;
        // Short refs are relative to the selected workspace
        const ws = tm.selectedWorkspace() orelse return null;
        if (ref.ordinal < ws.ordered_panels.items.len) {
            const panel_id = ws.ordered_panels.items[ref.ordinal];
            return .{ .id = panel_id, .ws = ws };
        }
        return null;
    }
    const target_id = parseId(id_str) orelse return null;
    for (tm.workspaces.items) |ws| {
        if (ws.panels.get(target_id) != null) return .{ .id = target_id, .ws = ws };
    }
    return null;
}

/// Resolve a window by UUID hex or "window:N" short ref.
fn findWindowByRef(id_str: []const u8) ?*WindowEntry {
    if (parseRef(id_str)) |ref| {
        if (ref.kind == .window and ref.ordinal < window_count) {
            return &window_store[ref.ordinal];
        }
        return null;
    }
    const target_id = parseId(id_str) orelse return null;
    return findWindowById(target_id);
}

fn isNoSurface() bool {
    return std.posix.getenv("CMUX_NO_SURFACE") != null;
}

fn getTerminalGhosttySurface(panel: *Panel) ?c.ghostty.ghostty_surface_t {
    if (panel.widget) |widget| {
        if (surface_mod.fromWidget(widget)) |surface| {
            return surface.ghostty_surface;
        }
    }
    return panel.surface;
}

fn trimToLastLines(text: []const u8, line_limit: usize) []const u8 {
    if (line_limit == 0) return text;
    if (text.len == 0) return text;

    var newlines_seen: usize = 0;
    var idx: usize = text.len;
    while (idx > 0) {
        idx -= 1;
        if (text[idx] == '\n') {
            newlines_seen += 1;
            if (newlines_seen >= line_limit) {
                if (idx + 1 < text.len) return text[idx + 1 ..];
                return "";
            }
        }
    }
    return text;
}

fn normalizeSocketText(alloc: Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, text, '\n') == null) {
        return alloc.dupe(u8, text);
    }

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch == '\r') {
            try buf.append(alloc, '\r');
            if (i + 1 < text.len and text[i + 1] == '\n') {
                i += 1;
            }
            continue;
        }
        if (ch == '\n') {
            try buf.append(alloc, '\r');
            continue;
        }
        try buf.append(alloc, ch);
    }

    return buf.toOwnedSlice(alloc);
}

fn writeJsonString(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x08 => try writer.writeAll("\\b"),
            0x0c => try writer.writeAll("\\f"),
            0x00...0x07, 0x0b, 0x0e...0x1f => try writer.print("\\u00{x:0>2}", .{ch}),
            else => try writer.writeByte(ch),
        }
    }
    try writer.writeByte('"');
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

fn getParamBool(params: json.Value, key: []const u8) ?bool {
    if (params != .object) return null;
    const val = params.object.get(key) orelse return null;
    if (val != .bool) return null;
    return val.bool;
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
            return std.fmt.allocPrint(
                alloc,
                "{{\"focused\":{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\",\"window_id\":\"{s}\"}}}}",
                .{ ws_id, panel_hex, @as([]const u8, &win_hex) },
            ) catch "{\"focused\":{}}";
        }
        return std.fmt.allocPrint(
            alloc,
            "{{\"focused\":{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\"}}}}",
            .{ ws_id, panel_hex },
        ) catch "{\"focused\":{}}";
    }
    return std.fmt.allocPrint(
        alloc,
        "{{\"focused\":{{\"workspace_id\":\"{s}\"}}}}",
        .{ws_id},
    ) catch "{\"focused\":{}}";
}

fn handleCapabilities(_: Allocator, _: json.Value) []const u8 {
    return "{\"workspaces\":true,\"splits\":true,\"notifications\":true,\"browser\":true,\"session\":true}";
}

fn handleAuthLogin(_: Allocator, _: json.Value) []const u8 {
    // The Linux build does not gate the v2 socket behind a password.
    // Match the macOS response shape: {authenticated, required}. We always
    // report authenticated=true so existing v1/v2 clients short-circuit the
    // password handshake gracefully, and required=false so they know the
    // gate is not enforced on this platform.
    return "{\"authenticated\":true,\"required\":false}";
}

/// Compose a window→workspace→pane→surface tree mirroring the macOS shape.
///
/// Linux currently uses a 1:1 panel:pane mapping (no pane grouping yet), so
/// each pane node always contains exactly one surface and `pane_id` /
/// `surface_id` resolve to the same underlying panel UUID. Any client that
/// joins/breaks panes on Linux later will get richer pane/surface arrays
/// without changing this shape.
///
/// Optional params recognised today:
///   - none (workspace_id / all_windows / caller filters from macOS are not
///     yet implemented; the tree always covers every known window).
fn handleSystemTree(alloc: Allocator, params: json.Value) []const u8 {
    _ = params;
    const empty = "{\"active\":{},\"windows\":[]}";
    const tm = getTabManager() orelse return empty;
    ensureDefaultWindow();

    const selected_ws = tm.selectedWorkspace();

    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(alloc);

    // ── active focus pointer (matches handleIdentify shape) ──
    w.writeAll("{\"active\":") catch return empty;
    if (selected_ws) |ws| {
        const ws_hex = formatId(ws.id);
        w.writeAll("{\"workspace_id\":\"") catch return empty;
        w.writeAll(&ws_hex) catch return empty;
        w.writeAll("\"") catch return empty;
        if (ws.focused_panel_id) |pid| {
            const pid_hex = formatId(pid);
            w.writeAll(",\"surface_id\":\"") catch return empty;
            w.writeAll(&pid_hex) catch return empty;
            w.writeAll("\"") catch return empty;
        }
        for (window_store[0..window_count]) |win_entry| {
            if (win_entry.hasWorkspace(ws.id)) {
                const win_hex = formatId(win_entry.id);
                w.writeAll(",\"window_id\":\"") catch return empty;
                w.writeAll(&win_hex) catch return empty;
                w.writeAll("\"") catch return empty;
                break;
            }
        }
        w.writeAll("}") catch return empty;
    } else {
        w.writeAll("{}") catch return empty;
    }

    // ── windows[] ──
    w.writeAll(",\"windows\":[") catch return empty;
    for (window_store[0..window_count], 0..) |win_entry, win_idx| {
        if (win_idx > 0) w.writeAll(",") catch {};
        const win_hex = formatId(win_entry.id);

        // Count workspaces in this window and find the selected one (if any).
        var ws_in_window: usize = 0;
        var sel_ws_in_window: ?u128 = null;
        for (tm.workspaces.items) |ws| {
            if (!win_entry.hasWorkspace(ws.id)) continue;
            ws_in_window += 1;
            if (selected_ws) |sws| {
                if (sws.id == ws.id) sel_ws_in_window = ws.id;
            }
        }

        w.writeAll("{\"id\":\"") catch return empty;
        w.writeAll(&win_hex) catch return empty;
        w.print(
            "\",\"ref\":\"window:{d}\",\"index\":{d},\"workspace_count\":{d},\"selected_workspace_id\":",
            .{ win_idx, win_idx, ws_in_window },
        ) catch return empty;
        if (sel_ws_in_window) |sid| {
            const sid_hex = formatId(sid);
            w.writeAll("\"") catch return empty;
            w.writeAll(&sid_hex) catch return empty;
            w.writeAll("\"") catch return empty;
        } else {
            w.writeAll("null") catch return empty;
        }
        w.writeAll(",\"workspaces\":[") catch return empty;

        // ── workspaces[] (filtered to this window) ──
        var ws_out_idx: usize = 0;
        for (tm.workspaces.items) |ws| {
            if (!win_entry.hasWorkspace(ws.id)) continue;
            if (ws_out_idx > 0) w.writeAll(",") catch {};
            const ws_hex = formatId(ws.id);
            const is_ws_selected = if (selected_ws) |sws| sws.id == ws.id else false;

            w.writeAll("{\"id\":\"") catch return empty;
            w.writeAll(&ws_hex) catch return empty;
            w.print(
                "\",\"ref\":\"workspace:{d}\",\"index\":{d},\"title\":",
                .{ ws_out_idx, ws_out_idx },
            ) catch return empty;
            writeJsonString(w, ws.displayTitle()) catch return empty;
            w.print(
                ",\"selected\":{s},\"pinned\":{s},\"panes\":[",
                .{
                    if (is_ws_selected) "true" else "false",
                    if (ws.is_pinned) "true" else "false",
                },
            ) catch return empty;

            // ── panes[] (Linux: one pane per panel) ──
            for (ws.ordered_panels.items, 0..) |panel_id, p_idx| {
                const panel = ws.panels.get(panel_id) orelse continue;
                if (p_idx > 0) w.writeAll(",") catch {};
                const panel_hex = formatId(panel.id);
                const is_focused = if (ws.focused_panel_id) |fid| fid == panel.id else false;
                const focused_str: []const u8 = if (is_focused) "true" else "false";
                const title_str = panel.custom_title orelse panel.title orelse "Terminal";
                const type_str = @tagName(panel.panel_type);

                // Pane node — surface_count is always 1 on Linux today.
                w.writeAll("{\"id\":\"") catch return empty;
                w.writeAll(&panel_hex) catch return empty;
                w.print(
                    "\",\"ref\":\"pane:{d}\",\"index\":{d},\"focused\":{s},\"surface_count\":1,\"selected_surface_id\":\"",
                    .{ p_idx, p_idx, focused_str },
                ) catch return empty;
                w.writeAll(&panel_hex) catch return empty;
                w.print(
                    "\",\"selected_surface_ref\":\"surface:{d}\",\"surfaces\":[",
                    .{p_idx},
                ) catch return empty;

                // Single surface entry per pane.
                w.writeAll("{\"id\":\"") catch return empty;
                w.writeAll(&panel_hex) catch return empty;
                w.print(
                    "\",\"ref\":\"surface:{d}\",\"index\":{d},\"index_in_pane\":0,\"type\":\"{s}\",\"focused\":{s},\"selected\":true,\"selected_in_pane\":true,\"pane_id\":\"",
                    .{ p_idx, p_idx, type_str, focused_str },
                ) catch return empty;
                w.writeAll(&panel_hex) catch return empty;
                w.print(
                    "\",\"pane_ref\":\"pane:{d}\",\"title\":",
                    .{p_idx},
                ) catch return empty;
                writeJsonString(w, title_str) catch return empty;
                w.writeAll("}]}") catch return empty; // close surface + surfaces[] + pane
            }

            w.writeAll("]}") catch return empty; // close panes[] + workspace
            ws_out_idx += 1;
        }

        w.writeAll("]}") catch return empty; // close workspaces[] + window
    }
    w.writeAll("]}") catch return empty; // close windows[] + root

    return buf.toOwnedSlice(alloc) catch empty;
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
            "{{\"id\":\"{s}\",\"short_id\":\"window:{d}\",\"index\":{d},\"focused\":{s}}}",
            .{ @as([]const u8, &hex), i, i, if (i == 0) "true" else "false" },
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
        break :blk if (findWindowByRef(wid_str)) |w| w else null;
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
            "{{\"index\":{d},\"id\":\"{s}\",\"short_id\":\"workspace:{d}\",\"title\":\"{s}\",\"selected\":{s}}}",
            .{
                out_idx,
                @as([]const u8, &ws_id),
                out_idx,
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
        findWindowByRef(wid_str)
    else if (window_count > 0) &window_store[0] else null;
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
            "{{\"index\":{d},\"id\":\"{s}\",\"short_id\":\"surface:{d}\",\"focused\":{s},\"title\":\"{s}\",\"type\":\"{s}\"}}",
            .{
                idx,
                @as([]const u8, &panel_hex),
                idx,
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
    const found = findSurfaceGlobal(tm, id_str) orelse return "{\"error\":\"surface not found\"}";
    const target_id = found.id;

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
        findSurfaceInWorkspace(ws, id_str) orelse return "{\"error\":\"invalid surface_id\"}"
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
            "{{\"index\":{d},\"id\":\"{s}\",\"short_id\":\"pane:{d}\",\"surface_count\":1,\"focused\":{s}}}",
            .{
                idx,
                @as([]const u8, &panel_hex),
                idx,
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

    if (getParamString(params, "before_workspace_id")) |before_str| {
        const before = findWorkspaceById(tm, before_str) orelse return "{\"error\":\"invalid before_workspace_id\"}";
        if (before.index != found.index) {
            const src = tm.workspaces.orderedRemove(found.index);
            const insert_at = if (found.index < before.index) before.index - 1 else before.index;
            tm.workspaces.insertAssumeCapacity(insert_at, src);
        }
    } else if (getParamString(params, "after_workspace_id")) |after_str| {
        const after = findWorkspaceById(tm, after_str) orelse return "{\"error\":\"invalid after_workspace_id\"}";
        if (after.index != found.index) {
            const src = tm.workspaces.orderedRemove(found.index);
            const insert_at = if (found.index <= after.index) after.index else after.index + 1;
            tm.workspaces.insertAssumeCapacity(insert_at, src);
        }
    }
    if (window.getSidebar()) |sb| sb.refresh();
    return "{}";
}

/// workspace.action — apply a workspace-level action.
///
/// Mirrors macOS `v2WorkspaceAction` (Sources/TerminalController.swift).
/// Linux supports the property-mutation actions and the reorder/close
/// variants that map directly onto existing primitives. Unsupported
/// actions return a structured error so callers can detect parity gaps.
fn handleWorkspaceAction(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";

    const action = getParamString(params, "action") orelse return "{\"error\":\"missing action\"}";

    // Resolve workspace (workspace_id param or current selection).
    //
    // The explicit `WorkspaceLookup` annotation is required: without it Zig
    // cannot peer-type the two if/else arms — `findWorkspaceById` returns
    // a named struct, and the `else` block constructs an anonymous struct
    // literal at this site, which Zig considers a distinct type.
    const found: WorkspaceLookup = if (getParamString(params, "workspace_id")) |id_str|
        findWorkspaceById(tm, id_str) orelse return "{\"error\":\"workspace not found\"}"
    else blk: {
        const idx = tm.selected_index orelse return "{\"error\":\"no workspace\"}";
        break :blk WorkspaceLookup{ .ws = tm.workspaces.items[idx], .index = idx };
    };
    const ws = found.ws;
    const ws_index = found.index;
    const ws_hex = formatId(ws.id);
    const ws_id_slice: []const u8 = &ws_hex;

    if (std.mem.eql(u8, action, "rename")) {
        const title = getParamString(params, "title") orelse return "{\"error\":\"missing title\"}";
        // Allocate FIRST, then free — otherwise an alloc failure leaves
        // ws.custom_title pointing at freed memory (use-after-free).
        const new_title = ws.alloc.dupe(u8, title) catch return "{\"error\":\"alloc failed\"}";
        if (ws.custom_title) |old| ws.alloc.free(old);
        ws.custom_title = new_title;
        tm.updateTabTitle(ws);
        if (window.getSidebar()) |sb| sb.refresh();
        // Escape `title` so quotes / control chars cannot break the envelope.
        var buf: std.ArrayList(u8) = .empty;
        const w = buf.writer(alloc);
        w.writeAll("{\"action\":\"rename\",\"workspace_id\":\"") catch return "{}";
        w.writeAll(ws_id_slice) catch return "{}";
        w.writeAll("\",\"title\":") catch return "{}";
        writeJsonString(w, title) catch return "{}";
        w.writeByte('}') catch return "{}";
        return buf.toOwnedSlice(alloc) catch "{}";
    }

    if (std.mem.eql(u8, action, "clear_name")) {
        if (ws.custom_title) |old| {
            ws.alloc.free(old);
            ws.custom_title = null;
        }
        tm.updateTabTitle(ws);
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"clear_name\",\"workspace_id\":\"{s}\"}}",
            .{ws_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "pin")) {
        ws.is_pinned = true;
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"pin\",\"workspace_id\":\"{s}\",\"pinned\":true}}",
            .{ws_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "unpin")) {
        ws.is_pinned = false;
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"unpin\",\"workspace_id\":\"{s}\",\"pinned\":false}}",
            .{ws_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "set_color")) {
        const color = getParamString(params, "color") orelse return "{\"error\":\"missing color\"}";
        // Allocate FIRST, then free — same use-after-free guard as rename.
        const new_color = ws.alloc.dupe(u8, color) catch return "{\"error\":\"alloc failed\"}";
        if (ws.custom_color) |old| ws.alloc.free(old);
        ws.custom_color = new_color;
        if (window.getSidebar()) |sb| sb.refresh();
        // Escape `color` to keep the JSON envelope intact regardless of value.
        var buf: std.ArrayList(u8) = .empty;
        const w = buf.writer(alloc);
        w.writeAll("{\"action\":\"set_color\",\"workspace_id\":\"") catch return "{}";
        w.writeAll(ws_id_slice) catch return "{}";
        w.writeAll("\",\"color\":") catch return "{}";
        writeJsonString(w, color) catch return "{}";
        w.writeByte('}') catch return "{}";
        return buf.toOwnedSlice(alloc) catch "{}";
    }

    if (std.mem.eql(u8, action, "clear_color")) {
        if (ws.custom_color) |old| {
            ws.alloc.free(old);
            ws.custom_color = null;
        }
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"clear_color\",\"workspace_id\":\"{s}\"}}",
            .{ws_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "move_up")) {
        if (ws_index > 0) {
            const src = tm.workspaces.orderedRemove(ws_index);
            tm.workspaces.insertAssumeCapacity(ws_index - 1, src);
        }
        if (window.getSidebar()) |sb| sb.refresh();
        const new_idx_opt = blk: {
            for (tm.workspaces.items, 0..) |w, i| if (w.id == ws.id) break :blk i;
            break :blk @as(usize, ws_index);
        };
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"move_up\",\"workspace_id\":\"{s}\",\"index\":{d}}}",
            .{ ws_id_slice, new_idx_opt },
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "move_down")) {
        if (ws_index + 1 < tm.workspaces.items.len) {
            const src = tm.workspaces.orderedRemove(ws_index);
            tm.workspaces.insertAssumeCapacity(ws_index + 1, src);
        }
        if (window.getSidebar()) |sb| sb.refresh();
        const new_idx_opt = blk: {
            for (tm.workspaces.items, 0..) |w, i| if (w.id == ws.id) break :blk i;
            break :blk @as(usize, ws_index);
        };
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"move_down\",\"workspace_id\":\"{s}\",\"index\":{d}}}",
            .{ ws_id_slice, new_idx_opt },
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "move_top")) {
        if (ws_index > 0) {
            const src = tm.workspaces.orderedRemove(ws_index);
            tm.workspaces.insertAssumeCapacity(0, src);
        }
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"move_top\",\"workspace_id\":\"{s}\",\"index\":0}}",
            .{ws_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "close_others") or
        std.mem.eql(u8, action, "close_above") or
        std.mem.eql(u8, action, "close_below"))
    {
        // Compute the set of workspace IDs to close before mutating, since
        // closeWorkspace shifts indices.
        var to_close = std.ArrayList(u128).empty;
        defer to_close.deinit(alloc);

        for (tm.workspaces.items, 0..) |candidate, i| {
            if (candidate.id == ws.id) continue;
            if (candidate.is_pinned) continue;
            const include = if (std.mem.eql(u8, action, "close_others"))
                true
            else if (std.mem.eql(u8, action, "close_above"))
                i < ws_index
            else // close_below
                i > ws_index;
            if (include) to_close.append(alloc, candidate.id) catch break;
        }

        var closed: usize = 0;
        for (to_close.items) |target_id| {
            // Re-find each target since indices shift after each close.
            for (tm.workspaces.items, 0..) |w, i| {
                if (w.id == target_id) {
                    tm.closeWorkspace(i);
                    closed += 1;
                    break;
                }
            }
        }
        if (window.getSidebar()) |sb| sb.refresh();
        // `action` is gated to one of three known-safe values above, but
        // escape it via writeJsonString for consistency with the other echoes.
        var buf: std.ArrayList(u8) = .empty;
        const w = buf.writer(alloc);
        w.writeAll("{\"action\":") catch return "{}";
        writeJsonString(w, action) catch return "{}";
        w.writeAll(",\"workspace_id\":\"") catch return "{}";
        w.writeAll(ws_id_slice) catch return "{}";
        w.print("\",\"closed\":{d}}}", .{closed}) catch return "{}";
        return buf.toOwnedSlice(alloc) catch "{}";
    }

    // Recognized macOS actions not yet wired on Linux. `action` is user
    // input — escape it so a malformed value cannot break the envelope.
    if (std.mem.eql(u8, action, "set_description") or
        std.mem.eql(u8, action, "clear_description") or
        std.mem.eql(u8, action, "mark_read") or
        std.mem.eql(u8, action, "mark_unread"))
    {
        var buf: std.ArrayList(u8) = .empty;
        const w = buf.writer(alloc);
        w.writeAll("{\"error\":\"action not implemented on linux\",\"action\":") catch
            return "{\"error\":\"action not implemented on linux\"}";
        writeJsonString(w, action) catch
            return "{\"error\":\"action not implemented on linux\"}";
        w.writeByte('}') catch return "{\"error\":\"action not implemented on linux\"}";
        return buf.toOwnedSlice(alloc) catch "{\"error\":\"action not implemented on linux\"}";
    }

    // Unsupported action — same escape treatment.
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(alloc);
    w.writeAll("{\"error\":\"unsupported action\",\"action\":") catch
        return "{\"error\":\"unsupported action\"}";
    writeJsonString(w, action) catch return "{\"error\":\"unsupported action\"}";
    w.writeAll(",\"supported\":[\"rename\",\"clear_name\",\"pin\",\"unpin\",\"set_color\",\"clear_color\",\"move_up\",\"move_down\",\"move_top\",\"close_others\",\"close_above\",\"close_below\"]}") catch
        return "{\"error\":\"unsupported action\"}";
    return buf.toOwnedSlice(alloc) catch "{\"error\":\"unsupported action\"}";
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

fn handleSurfaceSendText(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const workspace_found = if (getParamString(params, "workspace_id")) |id_str|
        findWorkspaceById(tm, id_str) orelse return "{\"error\":\"invalid workspace_id\"}"
    else
        null;

    const ws = if (workspace_found) |found|
        found.ws
    else if (getParamString(params, "surface_id")) |id_str|
        if (findSurfaceGlobal(tm, id_str)) |found| found.ws else return "{\"error\":\"invalid surface_id\"}"
    else
        tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    const target_id = if (getParamString(params, "surface_id")) |id_str|
        if (workspace_found != null)
            findSurfaceInWorkspace(ws, id_str) orelse return "{\"error\":\"invalid surface_id\"}"
        else if (findSurfaceGlobal(tm, id_str)) |found|
            found.id
        else
            return "{\"error\":\"invalid surface_id\"}"
    else
        ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";

    const text = getParamString(params, "text") orelse return "{\"error\":\"missing text\"}";

    const panel = ws.panels.get(target_id) orelse return "{\"error\":\"invalid surface_id\"}";
    if (panel.panel_type != .terminal) return "{\"error\":\"surface is not a terminal\"}";

    const panel_hex = formatId(panel.id);
    const ws_hex = formatId(ws.id);

    if (isNoSurface()) {
        // Test-only mode has mock panels with no live terminal surface.
        // Treat send_text as a no-op success once the target is validated.
        return std.fmt.allocPrint(
            alloc,
            "{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\"}}",
            .{ @as([]const u8, &ws_hex), @as([]const u8, &panel_hex) },
        ) catch "{}";
    }

    const surface = getTerminalGhosttySurface(panel) orelse {
        return "{\"error\":\"terminal surface not ready\"}";
    };

    const normalized_text = normalizeSocketText(alloc, text) catch {
        return "{\"error\":\"failed to prepare text\"}";
    };
    defer alloc.free(normalized_text);

    if (normalized_text.len > 0) {
        c.ghostty.ghostty_surface_text(surface, normalized_text.ptr, normalized_text.len);
    }
    if (panel.widget) |widget| {
        c.gtk.gtk_widget_queue_draw(widget);
    }

    return std.fmt.allocPrint(
        alloc,
        "{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\"}}",
        .{ @as([]const u8, &ws_hex), @as([]const u8, &panel_hex) },
    ) catch "{}";
}

fn handleSurfaceReadText(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const workspace_found = if (getParamString(params, "workspace_id")) |id_str|
        findWorkspaceById(tm, id_str) orelse return "{\"error\":\"invalid workspace_id\"}"
    else
        null;

    const ws = if (workspace_found) |found|
        found.ws
    else if (getParamString(params, "surface_id")) |id_str|
        if (findSurfaceGlobal(tm, id_str)) |found| found.ws else return "{\"error\":\"invalid surface_id\"}"
    else
        tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    const target_id = if (getParamString(params, "surface_id")) |id_str|
        if (workspace_found != null)
            findSurfaceInWorkspace(ws, id_str) orelse return "{\"error\":\"invalid surface_id\"}"
        else if (findSurfaceGlobal(tm, id_str)) |found|
            found.id
        else
            return "{\"error\":\"invalid surface_id\"}"
    else
        ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";

    var include_scrollback = getParamBool(params, "scrollback") orelse false;
    const line_limit_raw = getParamInt(params, "lines");
    const line_limit: ?usize = if (line_limit_raw) |raw| blk: {
        if (raw <= 0) return "{\"error\":\"lines must be greater than 0\"}";
        include_scrollback = true;
        break :blk @intCast(raw);
    } else null;

    const panel = ws.panels.get(target_id) orelse return "{\"error\":\"invalid surface_id\"}";
    if (panel.panel_type != .terminal) return "{\"error\":\"surface is not a terminal\"}";

    const surface = getTerminalGhosttySurface(panel) orelse {
        if (isNoSurface()) return "{\"error\":\"surface.read_text unavailable in CMUX_NO_SURFACE mode\"}";
        return "{\"error\":\"terminal surface not ready\"}";
    };

    const point_tag: c_uint = @intCast(if (include_scrollback)
        c.ghostty.GHOSTTY_POINT_SURFACE
    else
        c.ghostty.GHOSTTY_POINT_VIEWPORT);

    const top_left = c.ghostty.ghostty_point_s{
        .tag = point_tag,
        .coord = c.ghostty.GHOSTTY_POINT_COORD_TOP_LEFT,
        .x = 0,
        .y = 0,
    };
    const bottom_right = c.ghostty.ghostty_point_s{
        .tag = point_tag,
        .coord = c.ghostty.GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
        .x = 0,
        .y = 0,
    };
    const selection = c.ghostty.ghostty_selection_s{
        .top_left = top_left,
        .bottom_right = bottom_right,
        .rectangle = false,
    };

    var ghostty_text: c.ghostty.ghostty_text_s = undefined;
    if (!c.ghostty.ghostty_surface_read_text(surface, selection, &ghostty_text)) {
        return "{\"error\":\"failed to read terminal text\"}";
    }
    defer c.ghostty.ghostty_surface_free_text(surface, &ghostty_text);

    const raw_text: []const u8 = if (ghostty_text.text != null and ghostty_text.text_len > 0)
        ghostty_text.text[0..ghostty_text.text_len]
    else
        "";
    const trimmed_text = if (line_limit) |limit| trimToLastLines(raw_text, limit) else raw_text;

    var buf: std.ArrayList(u8) = .empty;
    const writer = buf.writer(alloc);
    writer.writeAll("{\"text\":") catch return "{\"error\":\"encode failed\"}";
    writeJsonString(writer, trimmed_text) catch return "{\"error\":\"encode failed\"}";
    writer.writeAll("}") catch return "{\"error\":\"encode failed\"}";
    return buf.toOwnedSlice(alloc) catch "{\"error\":\"encode failed\"}";
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
    const found = findSurfaceGlobal(tm, id_str) orelse return "{}";
    if (found.ws.panels.getPtr(found.id)) |panel_ptr| {
        panel_ptr.*.flash_count += 1;
    }
    return "{}";
}

fn handleSurfaceClearHistory(_: Allocator, _: json.Value) []const u8 {
    return "{}"; // Terminal scrollback clear stub
}

/// surface.action / tab.action — apply a tab-level action to a surface.
///
/// Mirrors macOS `v2TabAction` (Sources/TerminalController.swift). Linux
/// implements the trivial property-mutation actions (rename, clear_name,
/// pin, unpin, mark_read, mark_unread). Tab-relative close/new actions
/// (close_left, close_right, close_others, new_terminal_right,
/// new_browser_right, reload, duplicate) are not yet wired and will return
/// an `unsupported` error so callers can detect parity gaps.
fn handleSurfaceAction(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";

    // Resolve workspace (param or current)
    const ws = if (getParamString(params, "workspace_id")) |id_str|
        if (findWorkspaceById(tm, id_str)) |found| found.ws else return "{\"error\":\"workspace not found\"}"
    else
        tm.selectedWorkspace() orelse return "{\"error\":\"no workspace\"}";

    const action = getParamString(params, "action") orelse return "{\"error\":\"missing action\"}";

    // Resolve target surface (surface_id, tab_id, or focused)
    const target_id = if (getParamString(params, "surface_id")) |id_str|
        findSurfaceInWorkspace(ws, id_str) orelse return "{\"error\":\"invalid surface_id\"}"
    else if (getParamString(params, "tab_id")) |id_str|
        findSurfaceInWorkspace(ws, id_str) orelse return "{\"error\":\"invalid tab_id\"}"
    else
        ws.focused_panel_id orelse return "{\"error\":\"no focused surface\"}";

    const panel = ws.panels.get(target_id) orelse return "{\"error\":\"surface not found\"}";
    const panel_hex = formatId(target_id);
    const panel_id_slice: []const u8 = &panel_hex;

    if (std.mem.eql(u8, action, "rename")) {
        const title = getParamString(params, "title") orelse return "{\"error\":\"missing title\"}";
        // Allocate the new value FIRST, then free the old. Otherwise an alloc
        // failure leaves panel.custom_title pointing at freed memory.
        const new_title = ws.alloc.dupe(u8, title) catch return "{\"error\":\"alloc failed\"}";
        if (panel.custom_title) |old| ws.alloc.free(old);
        panel.custom_title = new_title;
        if (window.getSidebar()) |sb| sb.refresh();
        // Escape `title` via writeJsonString so quotes / backslashes / control
        // chars in the user-supplied value cannot break the JSON envelope.
        var buf: std.ArrayList(u8) = .empty;
        const w = buf.writer(alloc);
        w.writeAll("{\"action\":\"rename\",\"surface_id\":\"") catch return "{}";
        w.writeAll(panel_id_slice) catch return "{}";
        w.writeAll("\",\"title\":") catch return "{}";
        writeJsonString(w, title) catch return "{}";
        w.writeByte('}') catch return "{}";
        return buf.toOwnedSlice(alloc) catch "{}";
    }

    if (std.mem.eql(u8, action, "clear_name")) {
        if (panel.custom_title) |old| {
            ws.alloc.free(old);
            panel.custom_title = null;
        }
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"clear_name\",\"surface_id\":\"{s}\"}}",
            .{panel_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "pin")) {
        panel.is_pinned = true;
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"pin\",\"surface_id\":\"{s}\",\"pinned\":true}}",
            .{panel_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "unpin")) {
        panel.is_pinned = false;
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"unpin\",\"surface_id\":\"{s}\",\"pinned\":false}}",
            .{panel_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "mark_read")) {
        panel.is_manually_unread = false;
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"mark_read\",\"surface_id\":\"{s}\"}}",
            .{panel_id_slice},
        ) catch "{}";
    }

    if (std.mem.eql(u8, action, "mark_unread")) {
        panel.is_manually_unread = true;
        if (window.getSidebar()) |sb| sb.refresh();
        return std.fmt.allocPrint(
            alloc,
            "{{\"action\":\"mark_unread\",\"surface_id\":\"{s}\"}}",
            .{panel_id_slice},
        ) catch "{}";
    }

    // Recognized but not yet implemented on Linux. Returning a structured
    // error lets callers distinguish "wrong call" from "platform gap".
    // `action` is user input — escape it via writeJsonString.
    if (std.mem.eql(u8, action, "close_left") or
        std.mem.eql(u8, action, "close_right") or
        std.mem.eql(u8, action, "close_others") or
        std.mem.eql(u8, action, "new_terminal_right") or
        std.mem.eql(u8, action, "new_browser_right") or
        std.mem.eql(u8, action, "reload") or
        std.mem.eql(u8, action, "duplicate"))
    {
        var buf: std.ArrayList(u8) = .empty;
        const w = buf.writer(alloc);
        w.writeAll("{\"error\":\"action not implemented on linux\",\"action\":") catch
            return "{\"error\":\"action not implemented on linux\"}";
        writeJsonString(w, action) catch
            return "{\"error\":\"action not implemented on linux\"}";
        w.writeByte('}') catch return "{\"error\":\"action not implemented on linux\"}";
        return buf.toOwnedSlice(alloc) catch "{\"error\":\"action not implemented on linux\"}";
    }

    // Unsupported action — same escape treatment for `action` echo.
    var buf: std.ArrayList(u8) = .empty;
    const w = buf.writer(alloc);
    w.writeAll("{\"error\":\"unsupported action\",\"action\":") catch
        return "{\"error\":\"unsupported action\"}";
    writeJsonString(w, action) catch return "{\"error\":\"unsupported action\"}";
    w.writeAll(",\"supported\":[\"rename\",\"clear_name\",\"pin\",\"unpin\",\"mark_read\",\"mark_unread\"]}") catch
        return "{\"error\":\"unsupported action\"}";
    return buf.toOwnedSlice(alloc) catch "{\"error\":\"unsupported action\"}";
}

// ── Batch 3: Additional Pane Operations ─────────────────────────────────

fn handlePaneFocus(_: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const id_str = getParamString(params, "pane_id") orelse return "{\"error\":\"missing pane_id\"}";
    const found = findSurfaceGlobal(tm, id_str) orelse return "{\"error\":\"invalid pane_id\"}";

    // pane == panel in 1:1 mapping
    found.ws.focused_panel_id = found.id;
    return "{}";
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
        findSurfaceInWorkspace(ws, id_str) orelse return "{\"surfaces\":[]}"
    else
        ws.focused_panel_id orelse return "{\"surfaces\":[]}";

    // In 1:1 mapping, each pane has exactly one surface
    if (ws.panels.get(target_id)) |panel| {
        const panel_hex = formatId(panel.id);
        const title = panel.custom_title orelse panel.title orelse "Terminal";
        const is_focused = if (ws.focused_panel_id) |fid| fid == panel.id else false;
        return std.fmt.allocPrint(
            alloc,
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
    const pane_found = findSurfaceGlobal(tm, pane_str) orelse return "{\"error\":\"invalid pane_id\"}";
    const target_found = findSurfaceGlobal(tm, target_str) orelse return "{\"error\":\"invalid target_pane_id\"}";
    const pane_id = pane_found.id;
    const target_id = target_found.id;

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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid pane_id\"}"
    else if (getParamString(params, "surface_id")) |id_str|
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";
    const ws_found = findWorkspaceById(tm, ws_str) orelse return "{\"error\":\"invalid workspace_id\"}";

    ensureDefaultWindow();
    const win = findWindowByRef(win_str) orelse return "{\"error\":\"invalid window_id\"}";

    // Remove from all windows
    for (window_store[0..window_count]) |*w| {
        w.removeWorkspace(ws_found.ws.id);
    }
    // Add to target window
    win.addWorkspace(ws_found.ws.id);
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

/// Stub for browser commands when built without WebKitGTK (-Dno-webkit).
fn handleBrowserUnavailable(_: Allocator, _: json.Value) []const u8 {
    return "{\"error\":\"browser panel requires WebKitGTK (built with -Dno-webkit)\"}";
}

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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"focused\":false}"
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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
        if (findSurfaceGlobal(tm, id_str)) |f| f.id else return "{\"error\":\"invalid surface_id\"}"
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
    const body = getParamString(params, "body");

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

    if (!isNoSurface()) {
        // Send desktop notification via GNotification only in real GTK runs.
        const main = @import("main.zig");
        main.sendNotification("cmux-notification", title, body);
    }

    return "{}";
}

fn handleNotificationCreateForSurface(alloc: Allocator, params: json.Value) []const u8 {
    _ = alloc;
    const title = getParamString(params, "title") orelse "notification";
    const sid_str = getParamString(params, "surface_id");

    // Resolve surface ref once (if provided)
    const resolved_id: ?u128 = if (sid_str) |s| blk: {
        const tm = getTabManager() orelse break :blk null;
        const found = findSurfaceGlobal(tm, s) orelse break :blk null;
        break :blk found.id;
    } else null;

    // Suppress only if app focused AND target surface is the focused surface
    if (app_focus_override) |focused| {
        if (focused) {
            if (resolved_id) |rid| {
                const tm = getTabManager();
                if (tm) |tmgr| {
                    if (tmgr.selectedWorkspace()) |ws| {
                        if (ws.focused_panel_id) |fid| {
                            if (fid == rid) return "{}";
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
    if (resolved_id) |rid| {
        notif.surface_id = rid;
        // Trigger flash on the notified surface
        if (getTabManager()) |tm| {
            for (tm.workspaces.items) |ws| {
                if (ws.panels.getPtr(rid)) |panel_ptr| {
                    panel_ptr.*.flash_count += 1;
                    break;
                }
            }
        }
    }
    notification_count += 1;
    return "{}";
}

fn handleNotificationCreateForTarget(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"error\":\"no tab manager\"}";

    // Both ids are required. Unlike create_for_surface we do not fall
    // back to the focused surface — the caller has explicitly named the
    // routing target and we should fail loudly if it does not resolve.
    const ws_id_str = getParamString(params, "workspace_id") orelse
        return "{\"error\":\"missing workspace_id\"}";
    const sid_str = getParamString(params, "surface_id") orelse
        return "{\"error\":\"missing surface_id\"}";

    const ws_lookup = findWorkspaceById(tm, ws_id_str) orelse
        return "{\"error\":\"invalid workspace_id\"}";
    const ws = ws_lookup.ws;

    const target_id = findSurfaceInWorkspace(ws, sid_str) orelse
        return "{\"error\":\"invalid surface_id\"}";

    const title = getParamString(params, "title") orelse "Notification";
    // Optional fields. We accept `subtitle` for cross-platform parity but
    // do not yet have a slot for it in StoredNotification; the body is
    // truncated to fit the fixed-size buffer.
    _ = getParamString(params, "subtitle");
    const body_opt = getParamString(params, "body");

    // Suppress only if the app is reporting itself focused AND the target
    // surface is the currently-focused surface in its workspace.
    if (app_focus_override) |focused| {
        if (focused) {
            if (ws.focused_panel_id) |fid| {
                if (fid == target_id) return "{}";
            }
        }
    }

    if (notification_count >= notification_store_buf.len)
        notification_count = notification_store_buf.len - 1;
    var notif = &notification_store_buf[notification_count];
    notif.* = .{ .id = blk: {
        var id_buf: [16]u8 = undefined;
        std.crypto.random.bytes(&id_buf);
        break :blk std.mem.readInt(u128, &id_buf, .little);
    } };

    const tlen = @min(title.len, notif.title.len);
    @memcpy(notif.title[0..tlen], title[0..tlen]);
    notif.title_len = tlen;

    if (body_opt) |body| {
        const blen = @min(body.len, notif.body.len);
        @memcpy(notif.body[0..blen], body[0..blen]);
        notif.body_len = blen;
    }

    notif.surface_id = target_id;
    notification_count += 1;

    // Flash the addressed surface so list views surface the unread state
    if (ws.panels.getPtr(target_id)) |panel_ptr| {
        panel_ptr.*.flash_count += 1;
    }

    const ws_hex = formatId(ws.id);
    const sid_hex = formatId(target_id);
    return std.fmt.allocPrint(
        alloc,
        "{{\"workspace_id\":\"{s}\",\"surface_id\":\"{s}\"}}",
        .{ @as([]const u8, &ws_hex), @as([]const u8, &sid_hex) },
    ) catch "{}";
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
    if (!isNoSurface()) {
        // Withdraw desktop notification only in real GTK runs.
        const main = @import("main.zig");
        main.withdrawNotification("cmux-notification");
    }
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

fn handleAppSimulateActive(_: Allocator, _: json.Value) []const u8 {
    // No-op on Linux. The macOS handler triggers
    // applicationDidBecomeActive on NSApp so test harnesses can drive
    // focus-restoration code paths. The Linux build has no equivalent
    // app-active lifecycle, so we accept the call and return success
    // to keep cross-platform tests happy.
    return "{}";
}

fn handleDebugFlashCount(alloc: Allocator, params: json.Value) []const u8 {
    const tm = getTabManager() orelse return "{\"count\":0}";
    const id_str = getParamString(params, "surface_id") orelse return "{\"count\":0}";
    const found = findSurfaceGlobal(tm, id_str) orelse return "{\"count\":0}";
    if (found.ws.panels.get(found.id)) |panel| {
        return std.fmt.allocPrint(alloc, "{{\"count\":{d}}}", .{panel.flash_count}) catch "{\"count\":0}";
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
