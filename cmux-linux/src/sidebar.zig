/// Sidebar: workspace list in a GTK container compatible with older libadwaita.
///
/// Shows all workspaces with color dots, titles, and directory info.
/// Click to select, right-click for context menu.
/// Maps to macOS ContentView.swift sidebar.
const std = @import("std");
const c = @import("c_api.zig");
const TabManager = @import("tab_manager.zig").TabManager;
const Workspace = @import("workspace.zig").Workspace;

pub const Sidebar = struct {
    root_widget: ?*c.GtkWidget = null,
    list_box: ?*c.gtk.GtkListBox = null,
    tab_manager: ?*TabManager = null,

    /// Initialize the sidebar in place so signal userdata points at stable storage.
    pub fn init(self: *Sidebar, tab_manager: *TabManager) void {
        self.* = .{
            .root_widget = null,
            .list_box = null,
            .tab_manager = tab_manager,
        };

        self.root_widget = createSidebarContent(self);
    }

    fn createSidebarContent(self: *Sidebar) *c.GtkWidget {
        const box = c.gtk.gtk_box_new(c.gtk.GTK_ORIENTATION_VERTICAL, 0) orelse
            return @ptrCast(c.gtk.gtk_label_new("Error"));

        // Header
        const header: *c.GtkWidget = @ptrCast(c.gtk.adw_header_bar_new() orelse
            return @ptrCast(@alignCast(box)));
        c.gtk.gtk_box_append(@ptrCast(@alignCast(box)), header);

        // Workspace list
        self.list_box = @ptrCast(c.gtk.gtk_list_box_new() orelse return @ptrCast(@alignCast(box)));
        c.gtk.gtk_list_box_set_selection_mode(self.list_box.?, c.gtk.GTK_SELECTION_SINGLE);

        // Style the list box
        const lb_widget: *c.GtkWidget = @ptrCast(@alignCast(self.list_box.?));
        c.gtk.gtk_widget_add_css_class(lb_widget, "navigation-sidebar");

        // Scrolled window for the list
        const scrolled = c.gtk.gtk_scrolled_window_new() orelse return @ptrCast(@alignCast(box));
        c.gtk.gtk_scrolled_window_set_child(@ptrCast(@alignCast(scrolled)), @ptrCast(@alignCast(self.list_box.?)));
        c.gtk.gtk_widget_set_vexpand(@ptrCast(@alignCast(scrolled)), 1);
        c.gtk.gtk_box_append(@ptrCast(@alignCast(box)), @ptrCast(@alignCast(scrolled)));

        // Connect selection signal
        _ = c.gtk.g_signal_connect_data(
            @ptrCast(@alignCast(self.list_box.?)),
            "row-selected",
            @ptrCast(&onRowSelected),
            self,
            null,
            0,
        );

        return @ptrCast(@alignCast(box));
    }

    /// Rebuild sidebar rows from the tab manager's workspace list.
    pub fn refresh(self: *Sidebar) void {
        // Skip GTK widget operations in test mode (not thread-safe from socket handler)
        if (std.posix.getenv("CMUX_NO_SURFACE") != null) return;
        const list_box = self.list_box orelse return;
        const tm = self.tab_manager orelse return;

        // Remove all existing rows
        while (c.gtk.gtk_list_box_get_row_at_index(list_box, 0)) |row| {
            c.gtk.gtk_list_box_remove(list_box, @ptrCast(@alignCast(row)));
        }

        // Add rows for each workspace
        for (tm.workspaces.items, 0..) |ws, i| {
            const row = createWorkspaceRow(ws);
            c.gtk.gtk_list_box_append(list_box, row);

            // Select current workspace
            if (tm.selected_index) |sel| {
                if (sel == i) {
                    const gtk_row = c.gtk.gtk_list_box_get_row_at_index(list_box, @intCast(i));
                    c.gtk.gtk_list_box_select_row(list_box, gtk_row);
                }
            }
        }
    }

    fn createWorkspaceRow(ws: *Workspace) *c.GtkWidget {
        const box = c.gtk.gtk_box_new(c.gtk.GTK_ORIENTATION_HORIZONTAL, 8) orelse
            return @ptrCast(c.gtk.gtk_label_new("?"));

        // Color indicator (small circle)
        const color_label = c.gtk.gtk_label_new("\xE2\x97\x8F") orelse return @ptrCast(@alignCast(box)); // "●"
        if (ws.custom_color) |_| {
            // TODO: apply CSS color from ws.custom_color
        }
        c.gtk.gtk_box_append(@ptrCast(@alignCast(box)), @ptrCast(@alignCast(color_label)));

        // Title + directory in a vertical box
        const vbox = c.gtk.gtk_box_new(c.gtk.GTK_ORIENTATION_VERTICAL, 2) orelse return @ptrCast(@alignCast(box));

        const title_label = c.gtk.gtk_label_new(ws.displayTitle().ptr);
        c.gtk.gtk_label_set_xalign(@ptrCast(@alignCast(title_label)), 0);
        c.gtk.gtk_widget_add_css_class(@ptrCast(@alignCast(title_label)), "heading");
        c.gtk.gtk_box_append(@ptrCast(@alignCast(vbox)), @ptrCast(@alignCast(title_label)));

        if (ws.current_directory) |dir| {
            const dir_label = c.gtk.gtk_label_new(dir.ptr);
            c.gtk.gtk_label_set_xalign(@ptrCast(@alignCast(dir_label)), 0);
            c.gtk.gtk_widget_add_css_class(@ptrCast(@alignCast(dir_label)), "dim-label");
            c.gtk.gtk_label_set_ellipsize(@ptrCast(@alignCast(dir_label)), c.gtk.PANGO_ELLIPSIZE_START);
            c.gtk.gtk_box_append(@ptrCast(@alignCast(vbox)), @ptrCast(@alignCast(dir_label)));
        }

        c.gtk.gtk_widget_set_hexpand(@ptrCast(@alignCast(vbox)), 1);
        c.gtk.gtk_box_append(@ptrCast(@alignCast(box)), @ptrCast(@alignCast(vbox)));

        // Margin/padding
        c.gtk.gtk_widget_set_margin_top(@ptrCast(@alignCast(box)), 6);
        c.gtk.gtk_widget_set_margin_bottom(@ptrCast(@alignCast(box)), 6);
        c.gtk.gtk_widget_set_margin_start(@ptrCast(@alignCast(box)), 8);
        c.gtk.gtk_widget_set_margin_end(@ptrCast(@alignCast(box)), 8);

        return @ptrCast(@alignCast(box));
    }

    /// Get the root widget for embedding in the window.
    pub fn widget(self: *const Sidebar) ?*c.GtkWidget {
        return self.root_widget;
    }

    fn onRowSelected(
        list_box: *c.gtk.GtkListBox,
        row: ?*c.gtk.GtkListBoxRow,
        self: *Sidebar,
    ) callconv(.c) void {
        _ = list_box;
        const tm = self.tab_manager orelse return;
        if (row) |r| {
            const index: usize = @intCast(c.gtk.gtk_list_box_row_get_index(r));
            tm.selectWorkspace(index);
        }
    }
};
