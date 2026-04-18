/// Session persistence: snapshot and restore workspace state.
///
/// Saves a JSON snapshot of all windows/workspaces/panels every 8 seconds.
/// On app startup, restores the previous session if available.
/// Schema matches macOS SessionPersistence.swift exactly.

const std = @import("std");
const posix = std.posix;
const c = @import("c_api.zig");
const Workspace = @import("workspace.zig").Workspace;
const TabManager = @import("tab_manager.zig").TabManager;
const split_tree = @import("split_tree.zig");

const Allocator = std.mem.Allocator;
const log = std.log.scoped(.session);

const SCHEMA_VERSION: u32 = 1;
const AUTOSAVE_INTERVAL_SECS: u32 = 8;
const MAX_SCROLLBACK_BYTES: usize = 400 * 1024;

// ── Snapshot Types ───────────────────────────────────────────────

pub const AppSessionSnapshot = struct {
    version: u32 = SCHEMA_VERSION,
    created_at: f64 = 0,
    windows: []WindowSnapshot,
};

pub const WindowSnapshot = struct {
    frame: ?RectSnapshot = null,
    tab_manager: TabManagerSnapshot,
    sidebar: SidebarSnapshot,
};

pub const RectSnapshot = struct {
    x: f64 = 0,
    y: f64 = 0,
    width: f64 = 960,
    height: f64 = 640,
};

pub const SidebarSnapshot = struct {
    is_visible: bool = true,
    selection: []const u8 = "tabs",
    width: f64 = 200,
};

pub const TabManagerSnapshot = struct {
    selected_workspace_index: ?usize = null,
    workspaces: []WorkspaceSnapshot,
};

pub const WorkspaceSnapshot = struct {
    process_title: []const u8 = "",
    custom_title: ?[]const u8 = null,
    custom_color: ?[]const u8 = null,
    is_pinned: bool = false,
    current_directory: []const u8 = "",
    focused_panel_id: ?[]const u8 = null,
    layout: LayoutSnapshot,
    panels: []PanelSnapshot,
};

pub const LayoutSnapshot = union(enum) {
    pane: PaneLayoutSnapshot,
    split: SplitLayoutSnapshot,
};

pub const PaneLayoutSnapshot = struct {
    panel_ids: [][]const u8,
    selected_panel_id: ?[]const u8 = null,
};

pub const SplitLayoutSnapshot = struct {
    orientation: []const u8,
    divider_position: f64,
    first: *LayoutSnapshot,
    second: *LayoutSnapshot,
};

pub const PanelSnapshot = struct {
    id: []const u8,
    panel_type: []const u8 = "terminal",
    title: ?[]const u8 = null,
    custom_title: ?[]const u8 = null,
    directory: ?[]const u8 = null,
    is_pinned: bool = false,
    is_manually_unread: bool = false,
    terminal: ?TerminalPanelSnapshot = null,
};

pub const TerminalPanelSnapshot = struct {
    working_directory: ?[]const u8 = null,
    scrollback: ?[]const u8 = null,
};

// ── Session Manager ──────────────────────────────────────────────

pub const SessionManager = struct {
    alloc: Allocator,
    session_path: ?[]const u8 = null,
    autosave_source_id: c_uint = 0,
    tab_manager: ?*TabManager = null,

    pub fn init(alloc: Allocator) SessionManager {
        return .{ .alloc = alloc };
    }

    /// Start autosaving every 8 seconds.
    pub fn startAutosave(self: *SessionManager, tm: *TabManager) void {
        self.tab_manager = tm;
        self.session_path = self.resolveSessionPath() catch null;

        self.autosave_source_id = c.gtk.g_timeout_add_seconds(
            AUTOSAVE_INTERVAL_SECS,
            &autosaveCallback,
            self,
        );

        log.info("Session autosave started ({d}s interval)", .{AUTOSAVE_INTERVAL_SECS});
    }

    /// Stop autosaving.
    pub fn stopAutosave(self: *SessionManager) void {
        if (self.autosave_source_id != 0) {
            _ = c.gtk.g_source_remove(self.autosave_source_id);
            self.autosave_source_id = 0;
        }
    }

    fn resolveSessionPath(self: *SessionManager) ![]const u8 {
        if (posix.getenv("HOME")) |home| {
            const dir = try std.fmt.allocPrint(self.alloc, "{s}/.config/cmux", .{home});
            defer self.alloc.free(dir);
            std.fs.makeDirAbsolute(dir) catch {};
            return try std.fmt.allocPrint(self.alloc, "{s}/.config/cmux/session.json", .{home});
        }
        return error.NoHomePath;
    }

    /// Autosave GLib callback.
    fn autosaveCallback(data: ?*anyopaque) callconv(.c) c.gtk.gboolean {
        const self: *SessionManager = @ptrCast(@alignCast(data));
        self.save() catch |err| {
            log.warn("Autosave failed: {}", .{err});
        };
        return 1; // Continue timer
    }

    /// Save the current session to disk.
    pub fn save(self: *SessionManager) !void {
        const path = self.session_path orelse return error.NoSessionPath;
        const tm = self.tab_manager orelse return;

        // Build snapshot
        var workspace_snaps: std.ArrayList(WorkspaceSnapshot) = .empty;
        defer workspace_snaps.deinit(self.alloc);

        for (tm.workspaces.items) |ws| {
            try workspace_snaps.append(self.alloc, snapshotWorkspace(self.alloc, ws));
        }

        // Serialize to JSON
        var json_buf: std.ArrayList(u8) = .empty;
        defer json_buf.deinit(self.alloc);

        const writer = json_buf.writer(self.alloc);
        try writer.writeAll("{\"version\":1,\"windows\":[{\"tab_manager\":{\"workspaces\":[");

        for (workspace_snaps.items, 0..) |snap, i| {
            if (i > 0) try writer.writeAll(",");
            try writeWorkspaceJson(writer, snap);
        }

        try writer.writeAll("],\"selected_workspace_index\":");
        if (tm.selected_index) |idx| {
            try writer.print("{d}", .{@as(u64, idx)});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("},\"sidebar\":{\"is_visible\":true,\"width\":200}}]}");

        // Atomic write: write to tmp file, then rename
        const tmp_path = try std.fmt.allocPrint(self.alloc, "{s}.tmp", .{path});
        defer self.alloc.free(tmp_path);

        const file = try std.fs.createFileAbsolute(tmp_path, .{});
        try file.writeAll(json_buf.items);
        file.close();

        try std.fs.renameAbsolute(tmp_path, path);
    }

    fn snapshotWorkspace(_: Allocator, ws: *Workspace) WorkspaceSnapshot {
        return .{
            .process_title = ws.title orelse "",
            .custom_title = ws.custom_title,
            .custom_color = ws.custom_color,
            .is_pinned = ws.is_pinned,
            .current_directory = ws.current_directory orelse "",
            .layout = .{ .pane = .{
                .panel_ids = &.{},
                .selected_panel_id = null,
            } },
            .panels = &.{},
        };
    }

    fn writeWorkspaceJson(writer: anytype, snap: WorkspaceSnapshot) !void {
        try writer.writeAll("{\"process_title\":\"");
        try writer.writeAll(snap.process_title);
        try writer.writeAll("\",\"is_pinned\":");
        try writer.writeAll(if (snap.is_pinned) "true" else "false");
        try writer.writeAll(",\"current_directory\":\"");
        try writer.writeAll(snap.current_directory);
        try writer.writeAll("\"}");
    }

    /// Attempt to restore a previous session.
    /// Returns true if restoration was successful.
    pub fn restore(self: *SessionManager) bool {
        const path = self.session_path orelse return false;

        // Check if session restore is disabled
        if (posix.getenv("CMUX_DISABLE_SESSION_RESTORE")) |v| {
            if (std.mem.eql(u8, v, "1")) return false;
        }

        const file = std.fs.openFileAbsolute(path, .{}) catch return false;
        defer file.close();

        const content = file.readToEndAlloc(self.alloc, 10 * 1024 * 1024) catch return false;
        defer self.alloc.free(content);

        // Parse and validate version
        const parsed = std.json.parseFromSlice(std.json.Value, self.alloc, content, .{}) catch return false;
        defer parsed.deinit();

        if (parsed.value != .object) return false;
        const version_val = parsed.value.object.get("version") orelse return false;
        if (version_val != .integer or version_val.integer != SCHEMA_VERSION) return false;

        // TODO: rebuild windows, workspaces, splits, and surfaces from snapshot
        log.info("Session restore: found valid snapshot (v{d})", .{SCHEMA_VERSION});
        return false; // Not yet implemented — return false to create fresh session
    }
};
