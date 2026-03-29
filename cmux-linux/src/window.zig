/// Window management: AdwApplicationWindow with tabbed workspaces + sidebar.
///
/// Sprint 1: single terminal surface per window.
/// Sprint 2: AdwTabView for multiple tabs + sidebar workspace list.

const std = @import("std");
const c = @import("c_api.zig");
const TabManager = @import("tab_manager.zig").TabManager;
const Sidebar = @import("sidebar.zig").Sidebar;

/// Global state for the main window (single window for now).
var tab_manager: TabManager = undefined;
var sidebar: Sidebar = undefined;
var tab_manager_initialized: bool = false;

/// Create the main application window with tabbed workspaces and sidebar.
pub fn createWindow(gtk_app: *c.GtkApplication, ghostty_app: c.ghostty_app_t) void {
    const alloc = std.heap.c_allocator;

    // Create AdwApplicationWindow
    const win: *c.gtk.AdwApplicationWindow = @ptrCast(c.gtk.adw_application_window_new(
        @ptrCast(@alignCast(gtk_app)),
    ) orelse {
        std.log.err("Failed to create application window", .{});
        return;
    });

    c.gtk.gtk_window_set_default_size(@ptrCast(@alignCast(win)), 1200, 720);
    c.gtk.gtk_window_set_title(@ptrCast(@alignCast(win)), "cmux");

    // Initialize tab manager
    tab_manager = TabManager.init(alloc);
    tab_manager_initialized = true;

    // Content layout: vertical box with header bar + tab content
    const content_box: *c.GtkWidget = c.gtk.gtk_box_new(
        c.gtk.GTK_ORIENTATION_VERTICAL,
        0,
    ) orelse {
        std.log.err("Failed to create content box", .{});
        return;
    };

    // Header bar with tab bar
    const header: *c.gtk.AdwHeaderBar = @ptrCast(c.gtk.adw_header_bar_new() orelse {
        std.log.err("Failed to create header bar", .{});
        return;
    });

    // Tab view (holds workspace content pages)
    const tab_view: *c.gtk.AdwTabView = @ptrCast(c.gtk.adw_tab_view_new() orelse {
        std.log.err("Failed to create tab view", .{});
        return;
    });

    // Tab bar (shows tabs in the header)
    const tab_bar: *c.gtk.AdwTabBar = @ptrCast(c.gtk.adw_tab_bar_new() orelse {
        std.log.err("Failed to create tab bar", .{});
        return;
    });
    c.gtk.adw_tab_bar_set_view(tab_bar, tab_view);
    const tab_bar_widget: *c.GtkWidget = @ptrCast(@alignCast(tab_bar));
    c.gtk.adw_header_bar_set_title_widget(header, tab_bar_widget);

    // Wire tab manager to the tab view
    tab_manager.setTabView(tab_view, ghostty_app);

    // Build sidebar
    sidebar = Sidebar.create(&tab_manager);

    // Assemble layout: header + tab view content
    c.gtk.gtk_box_append(@ptrCast(@alignCast(content_box)), @ptrCast(@alignCast(header)));
    c.gtk.gtk_box_append(@ptrCast(@alignCast(content_box)), @ptrCast(@alignCast(tab_view)));
    c.gtk.gtk_widget_set_vexpand(@ptrCast(@alignCast(tab_view)), 1);

    // Set window content
    c.gtk.adw_application_window_set_content(win, content_box);

    // Create the first workspace (initial terminal tab)
    _ = tab_manager.createWorkspace() catch |err| {
        std.log.err("Failed to create initial workspace: {}", .{err});
    };

    // Refresh sidebar to show the initial workspace
    sidebar.refresh();

    // Show the window
    c.gtk.gtk_window_present(@ptrCast(@alignCast(win)));
}

/// Get the global tab manager (for use by action callbacks).
pub fn getTabManager() ?*TabManager {
    if (!tab_manager_initialized) return null;
    return &tab_manager;
}

/// Get the global sidebar (for refreshing after state changes).
pub fn getSidebar() ?*Sidebar {
    if (!tab_manager_initialized) return null;
    return &sidebar;
}
