/// Tab manager: ordered workspace list mapped to AdwTabView pages.
///
/// Manages the lifecycle of workspaces (create, close, reorder, select)
/// and keeps AdwTabView in sync. Maps to macOS TabManager.swift.

const std = @import("std");
const c = @import("c_api.zig");
const Workspace = @import("workspace.zig").Workspace;
const split_tree = @import("split_tree.zig");

const Allocator = std.mem.Allocator;

/// Generate a random 128-bit ID (UUID-like).
fn generateId() u128 {
    var buf: [16]u8 = undefined;
    std.crypto.random.bytes(&buf);
    return std.mem.readInt(u128, &buf, .little);
}

pub const TabManager = struct {
    alloc: Allocator,
    workspaces: std.ArrayList(*Workspace),
    selected_index: ?usize = null,
    tab_view: ?*c.gtk.AdwTabView = null,
    ghostty_app: c.ghostty_app_t = null,

    pub fn init(alloc: Allocator) TabManager {
        return .{
            .alloc = alloc,
            .workspaces = .empty,
        };
    }

    pub fn deinit(self: *TabManager) void {
        for (self.workspaces.items) |ws| {
            ws.deinit();
            self.alloc.destroy(ws);
        }
        self.workspaces.deinit(self.alloc);
    }

    /// Set the AdwTabView and ghostty app for creating surfaces.
    pub fn setTabView(self: *TabManager, tab_view: *c.gtk.AdwTabView, app: c.ghostty_app_t) void {
        self.tab_view = tab_view;
        self.ghostty_app = app;
    }

    /// Create a new workspace with a single terminal panel.
    /// If CMUX_NO_SURFACE is set, creates an empty workspace (no terminal surface).
    pub fn createWorkspace(self: *TabManager) !*Workspace {
        const ws = try self.alloc.create(Workspace);
        ws.* = Workspace.init(self.alloc);
        ws.id = generateId();

        // CMUX_NO_SURFACE: skip terminal surface to avoid GL renderer crash in CI
        const no_surface = std.posix.getenv("CMUX_NO_SURFACE") != null;
        if (!no_surface) {
            // Create initial terminal panel
            const panel = try ws.createTerminalPanel(self.ghostty_app);
            ws.root_node = try split_tree.createLeaf(self.alloc, panel.id, panel.widget);
            ws.content_widget = split_tree.buildWidget(ws.root_node.?);
        } else {
            // Test mode: create a mock panel so workspace has a surface for socket tests
            const panel = try ws.createMockPanel(.terminal);
            ws.root_node = try split_tree.createLeaf(ws.alloc, panel.id, panel.widget);
            ws.content_widget = split_tree.buildWidget(ws.root_node.?);
        }

        // Add to workspace list
        try self.workspaces.append(self.alloc, ws);
        const idx = self.workspaces.items.len - 1;

        // Add tab page in AdwTabView (skip in test mode — GTK calls must be on main thread)
        const no_surface = std.posix.getenv("CMUX_NO_SURFACE") != null;
        if (!no_surface) {
            if (self.tab_view) |tv| {
                if (ws.content_widget) |widget| {
                    const page = c.gtk.adw_tab_view_append(tv, widget);
                    if (page) |p| {
                        c.gtk.adw_tab_page_set_title(p, ws.displayTitle().ptr);
                    }
                }
            }
        }

        self.selected_index = idx;
        return ws;
    }

    /// Close a workspace by index.
    pub fn closeWorkspace(self: *TabManager, index: usize) void {
        if (index >= self.workspaces.items.len) return;

        const ws = self.workspaces.orderedRemove(index);

        // Remove from AdwTabView (skip in test mode — GTK calls must be on main thread)
        const no_surface = std.posix.getenv("CMUX_NO_SURFACE") != null;
        if (!no_surface) {
            if (self.tab_view) |tv| {
                if (ws.content_widget) |widget| {
                    const page = c.gtk.adw_tab_view_get_page(tv, widget);
                    if (page) |p| {
                        c.gtk.adw_tab_view_close_page(tv, p);
                    }
                }
            }
        }

        ws.deinit();
        self.alloc.destroy(ws);

        // Adjust selected index
        if (self.workspaces.items.len == 0) {
            self.selected_index = null;
        } else if (self.selected_index) |sel| {
            if (sel >= self.workspaces.items.len) {
                self.selected_index = self.workspaces.items.len - 1;
            }
        }
    }

    /// Select a workspace by index.
    pub fn selectWorkspace(self: *TabManager, index: usize) void {
        if (index >= self.workspaces.items.len) return;
        self.selected_index = index;

        // Skip GTK calls in test mode — not thread-safe from socket handler
        const no_surface = std.posix.getenv("CMUX_NO_SURFACE") != null;
        if (!no_surface) {
            if (self.tab_view) |tv| {
                const ws = self.workspaces.items[index];
                if (ws.content_widget) |widget| {
                    const page = c.gtk.adw_tab_view_get_page(tv, widget);
                    if (page) |p| {
                        c.gtk.adw_tab_view_set_selected_page(tv, p);
                    }
                }
            }
        }
    }

    /// Get the currently selected workspace.
    pub fn selectedWorkspace(self: *const TabManager) ?*Workspace {
        const idx = self.selected_index orelse return null;
        if (idx >= self.workspaces.items.len) return null;
        return self.workspaces.items[idx];
    }

    /// Number of workspaces.
    pub fn count(self: *const TabManager) usize {
        return self.workspaces.items.len;
    }

    /// Update tab title for a workspace.
    pub fn updateTabTitle(self: *TabManager, ws: *Workspace) void {
        if (self.tab_view == null) return;
        if (std.posix.getenv("CMUX_NO_SURFACE") != null) return;
        const tv = self.tab_view.?;
        if (ws.content_widget) |widget| {
            const page = c.gtk.adw_tab_view_get_page(tv, widget);
            if (page) |p| {
                c.gtk.adw_tab_page_set_title(p, ws.displayTitle().ptr);
            }
        }
    }
};
