//! A UI system.

const builtin = @import("builtin");
const Renderer = @import("render/Renderer.zig");
const sdl = @import("sdl");
const sparse_list = @import("../util/sparse_list.zig");
const std = @import("std");

const Ui = @This();

/// The nodes in the UI tree.
_nodes: sparse_list.SparseList(Node),
/// The ID of the root node in the UI tree.
///
/// This node should not be deinitialized by the user.
root_node: Id,
/// The allocator used by the system.
_gpa: std.mem.Allocator,

/// If `true`, the UI should be repainted.
should_repaint: bool = true,

/// A unique ID for a UI node.
pub const Id = struct { _index: u15 };

/// A node in the UI tree.
const Node = struct {
    /// The box occupied by the node.
    box: Box = .zero,
    /// The ID of the node's parent, if any.
    parent: ?Id = null,
    /// The IDs of the node's children.
    children: std.ArrayList(Id) = .empty,
    /// The method used to lay out the node's children.
    layout: Layout = .none,
    /// The method used to paint the node.
    paint_mode: PaintMode = .fromSprite(.blank),
};

/// A layout box.
const Box = struct {
    /// The *x*-coordinate of the box, in pixels.
    x: f32,
    /// The *y*-coordinate of the box, in pixels.
    y: f32,
    /// The width of the box, in pixels.
    w: f32,
    /// The height of the box, in pixels.
    h: f32,

    /// A box of zero size.
    const zero: Box = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
};

/// The method used to lay out a set of UI nodes.
const Layout = enum {
    /// Children are not laid out.
    none,
    /// Children are stretched to the full area of the parent.
    stretch,
    /// Children are arranged horizontally and stretched vertically.
    row_stretch,
    /// Children are arranged horizontally and centered vertically.
    row_center,
    /// Children are arranged vertically and stretched horizontally.
    col_stretch,
    /// Children are arranged vertically and centered horizontally.
    col_center,
};

const PaintMode = enum(@typeInfo(Renderer.Spritesheet.Sprite).@"enum".tag_type) {
    custom = std.math.maxInt(@typeInfo(Renderer.Spritesheet.Sprite).@"enum".tag_type),
    _,

    /// Returns the paint mode corresponding to the given sprite.
    pub fn fromSprite(sprite: Renderer.Spritesheet.Sprite) PaintMode {
        return @enumFromInt(@intFromEnum(sprite));
    }

    /// Returns the sprite corresponding to the given paint mode.
    fn toSprite(self: PaintMode) Renderer.Spritesheet.Sprite {
        return @enumFromInt(@intFromEnum(self));
    }
};

pub const Widget = struct {
    /// A type-erased pointer to widget data.
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        lay_out: fn (*anyopaque) void,
        paint: fn (*const anyopaque) void,
    };
};

/// Returns a new UI system.
///
/// The system is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Ui {
    var nodes: sparse_list.SparseList(Node) = try .initCapacity(gpa, 0);
    errdefer nodes.deinit(gpa);

    const root_node: Id = .{ ._index = @intCast(try nodes.insert(gpa, .{ .parent = undefined })) };

    return .{
        ._nodes = nodes,
        .root_node = root_node,
        ._gpa = gpa,
    };
}

/// Frees the UI system.
///
/// All nodes should have been freed before calling this function. In `Debug`
/// and `ReleaseSafe` mode, this function will log any nodes that have been
/// leaked.
///
/// The system should not be used after calling this function.
pub fn deinit(self: *Ui) void {
    self.deinitNode(self.root_node);

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)
        for (0..self._nodes.items.len) |i|
            if (self._nodes.isInit(i))
                std.log.scoped(.ui).err("node with ID {} was not freed", .{i});

    self._nodes.deinit(self._gpa);
    self.* = undefined;
}

// Nodes

/// Creates a UI node and returns its ID.
///
/// The node is owned by the caller and should be freed by calling
/// `deinitNode`.
pub fn initNode(self: *Ui) !Id {
    const i = try self._nodes.insert(self._gpa, .{});
    return .{ ._index = @intCast(i) };
}

/// Frees the node with the given ID.
///
/// The ID is invalidated after calling this function and should not be used
/// again.
///
/// Assumes the ID is valid.
pub fn deinitNode(self: *Ui, id: Id) void {
    self._nodes.unset(id._index);
}

/// Reassigns the node with the given ID to be a child of the given parent
/// node.
///
/// Each node may only have one parent. If the node was already a child of
/// another parent, it will be removed from that parent's children.
///
/// Assumes both IDs are valid.
pub fn setNodeParent(self: *Ui, id: Id, parent: ?Id) !void {
    if (self._nodes.items[id._index].parent) |prev_parent| {
        const prev_parent_children = &self._nodes.items[prev_parent._index].children;
        for (prev_parent_children.items, 0..) |child, i|
            if (child._index == id._index) {
                _ = prev_parent_children.orderedRemove(i);
                break;
            };
    }

    if (parent) |new_parent| {
        try self._nodes.items[new_parent._index].children.append(self._gpa, id);
        self._nodes.items[id._index].parent = new_parent;
    }

    self.queueRepaint();
}

/// Sets the size of the node with the given ID.
///
/// Assumes the ID is valid.
pub fn setNodeSize(self: *Ui, id: Id, w: f32, h: f32) void {
    const node = &self._nodes.items[id._index];
    node.box.w = w;
    node.box.h = h;

    self.queueRepaint();
}

// Systems

pub fn layOut(self: *Ui, box: Box) void {
    self.layOutNode(self.root_node, box);
}

fn layOutNode(self: *Ui, id: Id, box: Box) void {
    const node = &self._nodes.items[id._index];
    node.box = box;

    switch (node.layout) {
        .none => {},
        .stretch => for (node.children) |child_id|
            self.layOutNode(child_id, box),
        .row_stretch => {
            for (node.children) |child_id| {
                self.layOutNode(child_id, .{ .w = 0, .h = box.h });
            }
        },
    }
}

/// Requests that UI be repainted at a later time.
pub fn queueRepaint(self: *Ui) void {
    self.should_repaint = true;
}

/// Repaints UI.
pub fn repaint(self: *Ui, renderer: *Renderer, window: *sdl.SDL_Window) !void {
    renderer.clear();

    const root_node_box = self._nodes.items[self.root_node._index].box;
    renderer.switchScale(.{ .x = 1 / root_node_box.w, .y = 1 / root_node_box.h });

    // try self.paintNode(renderer, self.root_node);
    try renderer.drawSpriteStretch(.note, .{ .w = 8, .h = 8 });
    try renderer.render(window);
}

fn paintNode(self: *Ui, renderer: *Renderer, id: Id) !void {
    const node = &self._nodes.items[id._index];

    try renderer.drawSpriteStretch(.blank, .{ .x = node.box.x, .y = node.box.y, .w = node.box.w, .h = node.box.h });

    // switch (node.paint_mode) {
    //     .custom => {},
    //     _ => |paint_mode| try renderer.drawSprite(paint_mode.toSprite(), .zero),
    // }

    for (node.children.items) |child|
        try self.paintNode(renderer, child);
}

pub fn print(self: Ui, writer: *std.Io.Writer) !void {
    try self.print_node(self.root_node, writer, 0);
}

fn print_node(self: Ui, id: Id, writer: *std.Io.Writer, level: usize) !void {
    const node = self._nodes.items[id._index];

    for (0..level) |_| writer.writeByte(' ');
    writer.print("- ID {}", .{id._index});

    for (node.children.items) |child|
        try self.print_node(child, writer, level + 1);
}

test "UI init-deinit" {
    const gpa = std.testing.allocator;
    var ui = try init(gpa);
    ui.deinit();
}
