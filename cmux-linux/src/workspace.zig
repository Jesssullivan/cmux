/// Workspace: the core container for a "tab" worth of state.
///
/// Each workspace owns a split tree of terminal/browser panels,
/// plus metadata (title, color, directory, git branch, status).
/// Maps to macOS Sources/Workspace.swift.
const std = @import("std");
const split_tree = @import("split_tree.zig");
const c = @import("c_api.zig");

const Allocator = std.mem.Allocator;

pub const PanelType = enum {
    terminal,
    browser,
    markdown,
};

pub const Panel = struct {
    id: u128,
    panel_type: PanelType,
    title: ?[]const u8 = null,
    custom_title: ?[]const u8 = null,
    directory: ?[]const u8 = null,
    url: ?[]const u8 = null,
    is_pinned: bool = false,
    is_manually_unread: bool = false,
    git_branch: ?[]const u8 = null,
    tty_name: ?[]const u8 = null,
    surface: c.ghostty.ghostty_surface_t = null,
    widget: ?*c.GtkWidget = null,
    flash_count: u32 = 0,
    /// Shell integration progress state (OSC 9;4).
    progress_state: c.ghostty.ghostty_action_progress_report_state_e = c.ghostty.GHOSTTY_PROGRESS_STATE_REMOVE,
    /// Progress percentage (0-100). Null if no progress has been reported yet.
    progress_value: ?u8 = null,
    /// Headless socket-test state used when CMUX_NO_SURFACE is enabled.
    mock_terminal: MockTerminalState = .{},
};

pub const MockTerminalState = struct {
    transcript: std.ArrayListUnmanaged(u8) = .{},
    working_directory: ?[]const u8 = null,
    env_overrides: ?std.process.EnvMap = null,

    pub fn deinit(self: *MockTerminalState, alloc: Allocator) void {
        self.transcript.deinit(alloc);
        if (self.working_directory) |cwd| alloc.free(cwd);
        if (self.env_overrides) |*env| env.deinit();
        self.env_overrides = null;
    }

    pub fn setWorkingDirectory(self: *MockTerminalState, alloc: Allocator, cwd: ?[]const u8) !void {
        if (self.working_directory) |old| {
            alloc.free(old);
            self.working_directory = null;
        }
        if (cwd) |value| {
            self.working_directory = try alloc.dupe(u8, value);
        }
    }

    pub fn clearEnvOverrides(self: *MockTerminalState) void {
        if (self.env_overrides) |*env| env.deinit();
        self.env_overrides = null;
    }

    pub fn putEnvOverride(self: *MockTerminalState, alloc: Allocator, key: []const u8, value: []const u8) !void {
        if (self.env_overrides == null) {
            self.env_overrides = std.process.EnvMap.init(alloc);
        }
        try self.env_overrides.?.put(key, value);
    }

    pub fn appendTranscript(self: *MockTerminalState, alloc: Allocator, text: []const u8) !void {
        if (text.len == 0) return;
        try self.transcript.appendSlice(alloc, text);
    }

    pub fn transcriptText(self: *const MockTerminalState) []const u8 {
        return self.transcript.items;
    }
};

pub const StatusEntry = struct {
    key: []const u8,
    value: []const u8,
    icon: ?[]const u8 = null,
    color: ?[]const u8 = null,
    timestamp: f64 = 0,
};

pub const GitBranch = struct {
    branch: []const u8,
    is_dirty: bool = false,
};

pub const Workspace = struct {
    alloc: Allocator,

    /// Stable identifier for this workspace (UUID-like, for socket API).
    id: u128 = 0,

    /// Split tree root node (owns the pane layout).
    root_node: ?*split_tree.Node = null,

    /// All panels in this workspace, keyed by panel ID.
    panels: std.AutoHashMapUnmanaged(u128, *Panel),

    /// Insertion-ordered panel IDs for deterministic surface indexing.
    ordered_panels: std.ArrayListUnmanaged(u128) = .{},

    /// Display metadata.
    title: ?[]const u8 = null,
    custom_title: ?[]const u8 = null,
    custom_color: ?[]const u8 = null,
    current_directory: ?[]const u8 = null,
    description: ?[]const u8 = null,
    is_pinned: bool = false,
    is_manually_unread: bool = false,

    /// Status.
    git_branch: ?GitBranch = null,
    status_entries: std.ArrayList(StatusEntry),

    /// The GTK widget for this workspace's content (the split tree root widget).
    content_widget: ?*c.GtkWidget = null,

    /// Focused panel ID.
    focused_panel_id: ?u128 = null,

    pub fn init(alloc: Allocator) Workspace {
        return .{
            .alloc = alloc,
            .panels = .{},
            .status_entries = .{},
        };
    }

    pub fn deinit(self: *Workspace) void {
        var it = self.panels.valueIterator();
        while (it.next()) |panel_ptr| {
            const panel = panel_ptr.*;
            if (panel.surface) |s| c.ghostty.ghostty_surface_free(s);
            panel.mock_terminal.deinit(self.alloc);
            self.alloc.destroy(panel);
        }
        self.panels.deinit(self.alloc);
        self.ordered_panels.deinit(self.alloc);
        self.status_entries.deinit(self.alloc);

        if (self.description) |d| self.alloc.free(d);
        if (self.root_node) |node| split_tree.destroy(self.alloc, node);
    }

    /// Create a new terminal panel in this workspace.
    pub fn createTerminalPanel(self: *Workspace, ghostty_app: c.ghostty_app_t) !*Panel {
        const id = generateId();
        const panel = try self.alloc.create(Panel);
        panel.* = .{
            .id = id,
            .panel_type = .terminal,
        };

        // Create the surface widget
        const widget = try @import("surface.zig").Surface.create(ghostty_app);
        panel.widget = widget;

        try self.panels.put(self.alloc, id, panel);
        try self.ordered_panels.append(self.alloc, id);
        self.focused_panel_id = id;
        return panel;
    }

    /// Create a new browser panel in this workspace.
    /// Returns error.WebKitNotAvailable when built without WebKitGTK (-Dno-webkit).
    pub const createBrowserPanel = if (c.has_webkit) createBrowserPanelWebkit else createBrowserPanelStub;

    fn createBrowserPanelStub(_: *Workspace, _: ?[]const u8) !*Panel {
        return error.WebKitNotAvailable;
    }

    fn createBrowserPanelWebkit(self: *Workspace, url: ?[]const u8) !*Panel {
        const id = generateId();
        const panel = try self.alloc.create(Panel);
        panel.* = .{
            .id = id,
            .panel_type = .browser,
            .url = if (url) |u| self.alloc.dupe(u8, u) catch null else null,
        };

        // Create the WebKitGTK browser widget
        const widget = try @import("browser.zig").BrowserView.create(url);
        panel.widget = widget;

        try self.panels.put(self.alloc, id, panel);
        try self.ordered_panels.append(self.alloc, id);
        self.focused_panel_id = id;
        return panel;
    }

    /// Create a mock panel for test mode (no GL surface, no GTK widget).
    /// Used when CMUX_NO_SURFACE is set to avoid GL and GTK thread-safety crashes.
    pub fn createMockPanel(self: *Workspace, panel_type: PanelType) !*Panel {
        const id = generateId();
        const panel = try self.alloc.create(Panel);
        panel.* = .{
            .id = id,
            .panel_type = panel_type,
        };
        try self.panels.put(self.alloc, id, panel);
        try self.ordered_panels.append(self.alloc, id);
        self.focused_panel_id = id;
        return panel;
    }

    /// Remove a panel by ID from both maps.
    pub fn removePanel(self: *Workspace, panel_id: u128) void {
        if (self.panels.get(panel_id)) |panel| {
            if (panel.surface) |s| c.ghostty.ghostty_surface_free(s);
            self.alloc.destroy(panel);
            _ = self.panels.remove(panel_id);
        }
        // Remove from ordered list
        for (self.ordered_panels.items, 0..) |id, i| {
            if (id == panel_id) {
                _ = self.ordered_panels.orderedRemove(i);
                break;
            }
        }
    }

    /// Detach a panel without destroying it — for transferring between workspaces.
    /// Returns the panel pointer if found, null otherwise.
    pub fn detachPanel(self: *Workspace, panel_id: u128) ?*Panel {
        const panel = self.panels.get(panel_id) orelse return null;
        _ = self.panels.remove(panel_id);
        for (self.ordered_panels.items, 0..) |id, i| {
            if (id == panel_id) {
                _ = self.ordered_panels.orderedRemove(i);
                break;
            }
        }
        if (self.focused_panel_id) |fid| {
            if (fid == panel_id) {
                // Focus the next available panel
                self.focused_panel_id = if (self.ordered_panels.items.len > 0)
                    self.ordered_panels.items[0]
                else
                    null;
            }
        }
        return panel;
    }

    /// Attach an existing panel to this workspace (for transfers from another workspace).
    pub fn attachPanel(self: *Workspace, panel: *Panel) !void {
        try self.panels.put(self.alloc, panel.id, panel);
        try self.ordered_panels.append(self.alloc, panel.id);
        self.focused_panel_id = panel.id;
    }

    /// Get the number of panels.
    pub fn panelCount(self: *const Workspace) usize {
        return self.panels.count();
    }

    /// Get the focused panel.
    pub fn focusedPanel(self: *const Workspace) ?*Panel {
        const id = self.focused_panel_id orelse return null;
        return self.panels.get(id);
    }

    /// Set the display title (from terminal process or user override).
    pub fn setTitle(self: *Workspace, title: []const u8) void {
        if (self.title) |old| self.alloc.free(old);
        self.title = self.alloc.dupe(u8, title) catch null;
    }

    /// Get the display title (custom > process > default).
    pub fn displayTitle(self: *const Workspace) []const u8 {
        return self.custom_title orelse self.title orelse "Terminal";
    }
};

/// Generate a random 128-bit ID (UUID-like).
fn generateId() u128 {
    var buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);
    return std.mem.readInt(u128, &buf, .little);
}
