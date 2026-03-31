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

    /// Display metadata.
    title: ?[]const u8 = null,
    custom_title: ?[]const u8 = null,
    custom_color: ?[]const u8 = null,
    current_directory: ?[]const u8 = null,
    is_pinned: bool = false,

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
            self.alloc.destroy(panel);
        }
        self.panels.deinit(self.alloc);
        self.status_entries.deinit(self.alloc);  // ArrayList needs allocator

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
        self.focused_panel_id = id;
        return panel;
    }

    /// Create a new browser panel in this workspace.
    pub fn createBrowserPanel(self: *Workspace, url: ?[]const u8) !*Panel {
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
        self.focused_panel_id = id;
        return panel;
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
