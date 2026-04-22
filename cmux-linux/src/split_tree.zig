/// Split tree: binary tree model for pane layout.
///
/// Each node is either a Leaf (terminal surface in a GtkGLArea) or a
/// Split (GtkPaned containing two child nodes with an orientation and
/// divider ratio). Maps to macOS Bonsplit's SplitNode model.

const std = @import("std");
const c = @import("c_api.zig");

const Allocator = std.mem.Allocator;

pub const Orientation = enum {
    horizontal,
    vertical,

    pub fn toGtk(self: Orientation) c_uint {
        return switch (self) {
            .horizontal => c.gtk.GTK_ORIENTATION_HORIZONTAL,
            .vertical => c.gtk.GTK_ORIENTATION_VERTICAL,
        };
    }
};

pub const Node = union(enum) {
    leaf: Leaf,
    split: Split,
};

pub const Leaf = struct {
    /// Panel ID that this leaf displays.
    panel_id: u128,
    /// The GTK widget (GtkGLArea for terminal surfaces).
    widget: ?*c.GtkWidget = null,
};

pub const Split = struct {
    orientation: Orientation,
    /// Divider position as a fraction (0.0-1.0), clamped to [0.1, 0.9].
    ratio: f64 = 0.5,
    first: *Node,
    second: *Node,
    /// The GtkPaned widget created for this split.
    paned: ?*c.GtkWidget = null,
};

/// Create a new leaf node.
pub fn createLeaf(alloc: Allocator, panel_id: u128, widget: ?*c.GtkWidget) !*Node {
    const node = try alloc.create(Node);
    node.* = .{ .leaf = .{ .panel_id = panel_id, .widget = widget } };
    return node;
}

/// Split a leaf node into two panes.
/// The existing leaf becomes the first child; a new leaf is created as second.
pub fn splitPane(
    alloc: Allocator,
    target: *Node,
    orientation: Orientation,
    new_panel_id: u128,
    new_widget: ?*c.GtkWidget,
) !*Node {
    // Save the original leaf content
    const original = target.*;

    // Create two child nodes
    const first = try alloc.create(Node);
    first.* = original;

    const second = try createLeaf(alloc, new_panel_id, new_widget);

    // Replace target with a split
    target.* = .{ .split = .{
        .orientation = orientation,
        .ratio = 0.5,
        .first = first,
        .second = second,
    } };

    return target;
}

/// Close a leaf by panel ID. Returns the sibling that gets promoted,
/// or null if the leaf wasn't found.
pub fn closePane(alloc: Allocator, root: *Node, panel_id: u128) ?*Node {
    return closePaneInner(alloc, root, null, panel_id);
}

fn closePaneInner(alloc: Allocator, node: *Node, _: ?*Node, panel_id: u128) ?*Node {
    switch (node.*) {
        .leaf => |leaf| {
            if (leaf.panel_id == panel_id) {
                // This is the target leaf. The parent split should promote the sibling.
                // The caller (parent traversal) handles this.
                return node;
            }
            return null;
        },
        .split => |*split| {
            // Check first child
            if (split.first.* == .leaf and split.first.leaf.panel_id == panel_id) {
                // Promote second child to replace this split
                const promoted = split.second.*;
                alloc.destroy(split.first);
                alloc.destroy(split.second);
                node.* = promoted;
                return node;
            }

            // Check second child
            if (split.second.* == .leaf and split.second.leaf.panel_id == panel_id) {
                // Promote first child to replace this split
                const promoted = split.first.*;
                alloc.destroy(split.first);
                alloc.destroy(split.second);
                node.* = promoted;
                return node;
            }

            // Recurse into children
            if (closePaneInner(alloc, split.first, node, panel_id)) |r| return r;
            if (closePaneInner(alloc, split.second, node, panel_id)) |r| return r;

            return null;
        },
    }
}

/// Build the GTK widget tree from the split tree.
/// Returns the root widget for embedding in a container.
pub fn buildWidget(node: *Node) ?*c.GtkWidget {
    switch (node.*) {
        .leaf => |leaf| return leaf.widget,
        .split => |*split| {
            const first_widget = buildWidget(split.first) orelse return null;
            const second_widget = buildWidget(split.second) orelse return null;

            const paned: *c.GtkWidget = c.gtk.gtk_paned_new(
                split.orientation.toGtk(),
            ) orelse return null;

            c.gtk.gtk_paned_set_start_child(@ptrCast(@alignCast(paned)), first_widget);
            c.gtk.gtk_paned_set_end_child(@ptrCast(@alignCast(paned)), second_widget);
            c.gtk.gtk_paned_set_resize_start_child(@ptrCast(@alignCast(paned)), 1);
            c.gtk.gtk_paned_set_resize_end_child(@ptrCast(@alignCast(paned)), 1);

            // Set divider position (as fraction of allocated size)
            // Position will be updated after allocation via size-allocate signal
            split.paned = paned;

            // Expand to fill
            c.gtk.gtk_widget_set_hexpand(paned, 1);
            c.gtk.gtk_widget_set_vexpand(paned, 1);

            return paned;
        },
    }
}

/// Count total leaf nodes in the tree.
pub fn leafCount(node: *const Node) usize {
    return switch (node.*) {
        .leaf => 1,
        .split => |split| leafCount(split.first) + leafCount(split.second),
    };
}

/// Find a leaf by panel ID.
pub fn findLeaf(node: *Node, panel_id: u128) ?*Leaf {
    return switch (node.*) {
        .leaf => |*leaf| if (leaf.panel_id == panel_id) leaf else null,
        .split => |split| findLeaf(split.first, panel_id) orelse findLeaf(split.second, panel_id),
    };
}

/// Check whether a subtree contains a given panel.
pub fn containsPanel(node: *const Node, panel_id: u128) bool {
    return switch (node.*) {
        .leaf => |leaf| leaf.panel_id == panel_id,
        .split => |split| containsPanel(split.first, panel_id) or containsPanel(split.second, panel_id),
    };
}

/// Find the innermost split ancestor of `panel_id` whose orientation
/// matches `target_orientation` and where the panel is in the first
/// child (if `in_first` is true) or the second child (if false).
///
/// Returns a mutable pointer to the matching Split, or null if none
/// found. The caller can then adjust `split.ratio` to resize.
pub fn findResizeSplit(
    node: *Node,
    panel_id: u128,
    target_orientation: Orientation,
    in_first: bool,
) ?*Split {
    switch (node.*) {
        .leaf => return null,
        .split => |*split| {
            const in_first_child = containsPanel(split.first, panel_id);
            if (!in_first_child and !containsPanel(split.second, panel_id))
                return null;

            // Recurse into the child that contains the panel first
            // so innermost matches win.
            const child = if (in_first_child) split.first else split.second;
            if (findResizeSplit(child, panel_id, target_orientation, in_first)) |inner|
                return inner;

            // If this split matches, return it.
            if (split.orientation == target_orientation and in_first_child == in_first)
                return split;

            return null;
        },
    }
}

/// Collect all leaf nodes in left-to-right / top-to-bottom order.
pub fn collectLeaves(node: *Node, alloc: Allocator, out: *std.ArrayList(*Leaf)) void {
    switch (node.*) {
        .leaf => |*leaf| out.append(alloc, leaf) catch |err| {
            std.log.warn("collectLeaves: failed to append leaf: {}", .{err});
        },
        .split => |split| {
            collectLeaves(split.first, alloc, out);
            collectLeaves(split.second, alloc, out);
        },
    }
}

/// Direction for adjacent leaf navigation.
pub const TraversalDirection = enum { next, previous };

/// Find the next or previous leaf relative to the one with `panel_id`.
/// `direction`: .next or .previous (wraps around).
pub fn adjacentLeaf(
    root: *Node,
    panel_id: u128,
    direction: TraversalDirection,
    alloc: Allocator,
) ?*Leaf {
    var leaves: std.ArrayList(*Leaf) = .empty;
    defer leaves.deinit(alloc);
    collectLeaves(root, alloc, &leaves);
    if (leaves.items.len <= 1) return null;

    for (leaves.items, 0..) |leaf, i| {
        if (leaf.panel_id == panel_id) {
            return switch (direction) {
                .next => leaves.items[(i + 1) % leaves.items.len],
                .previous => leaves.items[if (i == 0) leaves.items.len - 1 else i - 1],
            };
        }
    }
    return null;
}

/// Set all split ratios to 0.5 (equalize).
pub fn equalize(node: *Node) void {
    switch (node.*) {
        .leaf => {},
        .split => |*split| {
            split.ratio = 0.5;
            equalize(split.first);
            equalize(split.second);
        },
    }
}

/// Apply split ratios to GtkPaned widgets (call after widget allocation).
pub fn applyRatios(node: *Node) void {
    switch (node.*) {
        .leaf => {},
        .split => |*split| {
            if (split.paned) |paned| {
                // Get the allocated size along the split axis
                const size: c_int = switch (split.orientation) {
                    .horizontal => c.gtk.gtk_widget_get_width(paned),
                    .vertical => c.gtk.gtk_widget_get_height(paned),
                };
                if (size > 0) {
                    const pos: c_int = @intFromFloat(@as(f64, @floatFromInt(size)) * split.ratio);
                    c.gtk.gtk_paned_set_position(@ptrCast(@alignCast(paned)), pos);
                }
            }
            applyRatios(split.first);
            applyRatios(split.second);
        },
    }
}

/// Recursively destroy all nodes.
pub fn destroy(alloc: Allocator, node: *Node) void {
    switch (node.*) {
        .leaf => {},
        .split => |split| {
            destroy(alloc, split.first);
            destroy(alloc, split.second);
        },
    }
    alloc.destroy(node);
}
