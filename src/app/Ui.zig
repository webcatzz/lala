//! A UI system.
//!
//! Each UI element in the system has two components: a rectangle which it
//! occupies and its behavioral logic. Each element is uniquely identified by an
//! `Id`.

const Ctx = @import("ctx/Ctx.zig");
const input = @import("input.zig");
const math = @import("util/math.zig");
const Renderer = @import("render/Renderer.zig");
const std = @import("std");

const Ui = @This();

/// Rectangle components for each element.
rects: [*]math.Rect(f32),
/// Logic components for each element.
///
/// Unused slots are populated with nodes of the free list.
logic: [*]LogicSlot,
/// The total number of elements the system can hold.
cap: usize,
/// A singly-linked list tracking unused IDs in the system, stored in unused
/// slots in `logic`.
free_list: std.SinglyLinkedList,
/// A mapping from positions to UI elements.
map: Map,

/// An ID for an element.
///
/// One sentinel ID is reserved for invalid IDs.
pub const Id = struct {
    _index: BackingInt,

    /// The integer type used to represent IDs.
    const BackingInt = u16;
    /// The invalid ID.
    const invalid: Id = .{ ._index = std.math.maxInt(BackingInt) };
};

/// A slot storing either a logic interface or a node of the free list.
const LogicSlot = union { logic: Logic, node: std.SinglyLinkedList.Node };

/// An interface defining the behavior of an element.
pub const Logic = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        draw: *const fn (*const anyopaque, *Renderer, Ctx, math.Rect(f32)) Renderer.DrawError!void,
        lay_out: *const fn (*anyopaque, *Ui, math.Rect(f32)) void,
        respond_button: *const fn (*anyopaque, *Ctx, Id, input.Event(.button)) error{OutOfMemory}!void,
        respond_cursor: *const fn (*anyopaque, *Ctx, Id, input.Event(.cursor)) error{OutOfMemory}!void,
        respond_scroll: *const fn (*anyopaque, *Ctx, Id, input.Event(.scroll)) error{OutOfMemory}!void,
    };

    /// A no-op logic interface.
    pub const noop: Logic = .construct(void, undefined);

    /// Constructs a logic interface for the given type.
    ///
    /// The interface will hook into the given methods, if present:
    ///
    /// ```
    /// T.draw(*const T, *Renderer, Ctx, Id)
    /// T.layOut(*T, *Ui, Id)
    /// T.respond(*T, *Ctx, Id, comptime input.Type, input.Event)
    /// ```
    pub fn construct(comptime T: type, ptr: *T) Logic {
        const impl = struct {
            fn draw(p: *const anyopaque, renderer: *Renderer, ctx: Ctx, rect: math.Rect(f32)) !void {
                if (@hasDecl(T, "draw"))
                    try @as(*const T, @ptrCast(@alignCast(p))).draw(renderer, ctx, rect);
            }

            fn layOut(p: *anyopaque, ui: *Ui, rect: math.Rect(f32)) void {
                if (@hasDecl(T, "layOut"))
                    @as(*T, @ptrCast(@alignCast(p))).layOut(ui, rect);
            }

            fn respondButton(p: *anyopaque, ctx: *Ctx, id: Id, event: input.Event(.button)) !void {
                if (@hasDecl(T, "respond"))
                    try @as(*T, @ptrCast(@alignCast(p))).respond(ctx, id, .button, event);
            }

            fn respondCursor(p: *anyopaque, ctx: *Ctx, id: Id, event: input.Event(.cursor)) !void {
                if (@hasDecl(T, "respond"))
                    try @as(*T, @ptrCast(@alignCast(p))).respond(ctx, id, .cursor, event);
            }

            fn respondScroll(p: *anyopaque, ctx: *Ctx, id: Id, event: input.Event(.scroll)) !void {
                if (@hasDecl(T, "respond"))
                    try @as(*T, @ptrCast(@alignCast(p))).respond(ctx, id, .scroll, event);
            }

            const vtable: VTable = .{
                .draw = @This().draw,
                .lay_out = @This().layOut,
                .respond_button = respondButton,
                .respond_cursor = respondCursor,
                .respond_scroll = respondScroll,
            };
        };

        return .{ .ptr = ptr, .vtable = &impl.vtable };
    }

    /// Updates the element in response to the given event.
    pub fn respond(self: Logic, ctx: *Ctx, id: Id, comptime event_type: input.Type, event: input.Event(event_type)) !void {
        try (switch (event_type) {
            .button => self.vtable.respond_button,
            .cursor => self.vtable.respond_cursor,
            .scroll => self.vtable.respond_scroll,
        })(self.ptr, ctx, id, event);
    }

    /// Lays out the element and its children in the given rectangle.
    pub fn layOut(self: Logic, ui: *Ui, rect: math.Rect(f32)) void {
        self.vtable.lay_out(self.ptr, ui, rect);
    }

    /// Draws the element and its children in the given rectangle.
    pub fn draw(self: Logic, renderer: *Renderer, ctx: Ctx, rect: math.Rect(f32)) !void {
        try self.vtable.draw(self.ptr, renderer, ctx, rect);
    }
};

pub fn init(gpa: std.mem.Allocator) !Ui {
    return .{
        .rects = undefined,
        .logic = undefined,
        .cap = 0,
        .free_list = .{ .first = null },
        .map = try .init(gpa),
    };
}

/// Frees the UI system.
///
/// The system should not be used after calling this function. Calling this
/// function will clean up any inserted items.
pub fn deinit(self: *Ui, gpa: std.mem.Allocator) void {
    gpa.free(self.rects[0..self.cap]);
    gpa.free(self.logic[0..self.cap]);
    self.map.deinit(gpa);
    self.* = undefined;
}

fn setCapacity(self: *Ui, gpa: std.mem.Allocator, new_cap: usize) !void {
    const old_cap = self.cap;
    self.rects = (try gpa.realloc(self.rects[0..self.cap], new_cap)).ptr;
    self.logic = (try gpa.realloc(self.logic[0..self.cap], new_cap)).ptr;
    self.cap = new_cap;

    const new_nodes = sewBuf(self.logic[old_cap..new_cap]);
    if (self.free_list.first) |head| {
        var tail = head;
        while (tail.next) |next| tail = next;
        tail.next = new_nodes.first;
    } else self.free_list = new_nodes;
}

/// Populates `buf` with a singly-linked list and returns the list.
fn sewBuf(buf: []LogicSlot) std.SinglyLinkedList {
    var head: std.SinglyLinkedList.Node = .{ .next = null };
    var prev_node = &head;
    for (buf) |*slot| {
        slot.* = .{ .node = .{ .next = null } };
        prev_node.next = &slot.node;
        prev_node = &slot.node;
    }

    return .{ .first = head.next };
}

/// Inserts a new element with the given rectangle and logic into the system and
/// returns its ID.
///
/// Reallocates memory if necessary.
pub fn insert(self: *Ui, gpa: std.mem.Allocator, rect: math.Rect(f32), logic: Logic) !Id {
    if (self.free_list.first == null)
        try self.setCapacity(gpa, @max(self.cap, 4) * 2);

    const i = @as(*LogicSlot, @fieldParentPtr("node", self.free_list.popFirst() orelse unreachable)) - self.logic;
    self.rects[i] = rect;
    self.logic[i] = .{ .logic = logic };
    return .{ ._index = @intCast(i) };
}

/// Removes the element with the given ID from the system.
///
/// The ID should not be used after calling this function.
pub fn remove(self: *Ui, id: Id) void {
    self.rects[id._index] = .{ .node = .{ .next = null } };
    self.logic[id._index] = undefined;
    self.free_list.prepend(&self.rects[id._index].node);
}

/// Returns the rectangle occupied by the element with the given ID.
pub fn getRect(self: Ui, id: Id) math.Rect(f32) {
    return self.rects[id._index];
}

/// Sets the rectangle occupied by the element with the given ID.
pub fn setRect(self: Ui, id: Id, rect: math.Rect(f32)) void {
    self.rects[id._index] = rect;
}

/// Returns the logic interface of the element with the given ID.
pub fn getLogic(self: Ui, id: Id) Logic {
    return self.logic[id._index].logic;
}

/// Updates the element in response to the given event.
pub fn respond(self: *Ui, id: Id, ctx: *Ctx, comptime event_type: input.Type, event: input.Event(event_type)) !void {
    try self.getLogic(id).respond(ctx, id, event_type, event);
}

/// Lays out the element with the given ID.
pub fn layOut(self: *Ui, id: Id) void {
    self.getLogic(id).layOut(self, self.getRect(id));
}

/// Draws the element with the given ID.
pub fn draw(self: Ui, id: Id, renderer: *Renderer, ctx: Ctx) !void {
    try self.getLogic(id).draw(renderer, ctx, self.getRect(id));
}

test "basic" {
    var ui: Ui = try .init(std.testing.allocator);
    defer ui.deinit(std.testing.allocator);

    const item_1 = try ui.insert(std.testing.allocator, .zero, .noop);
    const item_2 = try ui.insert(std.testing.allocator, .zero, .noop);

    ui.remove(item_1);
    ui.remove(item_2);
}

// Map

const Map = struct {
    pixel_colors: []Id,
    width: u16,

    fn init(gpa: std.mem.Allocator) !Map {
        const App = @import("App.zig");

        return .{
            .pixel_colors = try gpa.alloc(Id, App.width * App.height),
            .width = App.width,
        };
    }

    fn deinit(self: *Map, gpa: std.mem.Allocator) void {
        gpa.free(self.pixel_colors);
        self.* = undefined;
    }

    fn record(self: *Map, id: Id, rect: math.Rect(f32)) void {
        const rect_x1: u16 = @intFromFloat(rect.x);
        const rect_y1: u16 = @intFromFloat(rect.y);
        const rect_x2: u16 = @intFromFloat(rect.endX());
        const rect_y2: u16 = @intFromFloat(rect.endY());
        for (rect_y1..rect_y2) |y|
            @memset(self.pixel_colors[rect_x1 + y * self.width .. rect_x2 + y * self.width], id);
    }
};

// Common UI elements

pub const Split = struct {
    /// The two child panes.
    children: [2]Id,
    /// The axis along which child panes are arranged.
    axis: math.Axis,
    /// The fraction of space occupied by the first pane, in the range \[0, 1].
    split: f32,
    /// The index of the pane with mouse focus, if any.
    active_child_index: ?u1 = null,

    pub fn respond(self: *Split, ctx: *Ctx, id: Id, comptime event_type: input.Type, event: input.Event(event_type)) !void {
        const child_id = if (self.active_child_index) |active_child_index| blk: {
            // Routes events to the active pane, if one exists
            const child_index = active_child_index;
            if (event_type == .button and !event.is_pressed)
                self.active_child_index = null;
            break :blk self.children[child_index];
        } else if (event_type == .button and event.is_pressed) blk: {
            // Sets the active pane when a button press event is received
            const active_child_index = pickChild(ctx.ui.getRect(id), self.axis, self.split, ctx.input.cursor_pos);
            self.active_child_index = active_child_index;
            break :blk self.children[active_child_index];
        } else blk: {
            // Otherwise, routes events to the pane under the cursor
            break :blk self.children[pickChild(ctx.ui.getRect(id), self.axis, self.split, ctx.input.cursor_pos)];
        };

        try ctx.ui.respond(child_id, ctx, event_type, event);
    }

    pub fn layOut(self: *Split, ui: *Ui, rect: math.Rect(f32)) void {
        switch (self.axis) {
            .x => {
                const split = self.split * rect.w;
                ui.setRect(self.children[0], .{
                    .x = rect.x,
                    .y = rect.y,
                    .h = split,
                    .w = rect.h,
                });
                ui.setRect(self.children[1], .{
                    .x = rect.x + split,
                    .y = rect.y,
                    .h = rect.w - split,
                    .w = rect.h,
                });
            },
            .y => {
                const split = self.split * rect.h;
                ui.setRect(self.children[0], .{
                    .x = rect.x,
                    .y = rect.y,
                    .w = rect.w,
                    .h = split,
                });
                ui.setRect(self.children[1], .{
                    .x = rect.x,
                    .y = rect.y + split,
                    .w = rect.w,
                    .h = rect.h - split,
                });
            },
        }

        inline for (self.children) |child_id|
            ui.layOut(child_id);
    }

    pub fn draw(self: Split, renderer: *Renderer, ctx: Ctx, _: math.Rect(f32)) !void {
        inline for (self.children) |child_id|
            try ctx.ui.draw(child_id, renderer, ctx);
    }

    fn pickChild(
        rect: math.Rect(f32),
        axis: math.Axis,
        split: f32,
        pos: math.Vec2(f32),
    ) u1 {
        return switch (axis) {
            .x => @intFromBool(pos.x > rect.x + split * rect.w),
            .y => @intFromBool(pos.y > rect.y + split * rect.h),
        };
    }
};

pub const frame = struct {
    /// The widths of the borders of the frame.
    pub const border = Renderer.Spritesheet.Sprite.frame.info().border;

    /// Draws the frame
    pub fn draw(renderer: *Renderer, rect: math.Rect(f32), title: []const u8) !void {
        try renderer.drawSprite9Patch(.frame, rect);
        try renderer.switchColor(.fromHexRgb(0x302c2e));
        try renderer.print(title, .{ .x = rect.x + border.left, .y = rect.y + 2 });
        try renderer.switchColor(.white);
    }
};

pub const scrollbar = struct {
    /// The width of the scrollbar.
    pub const width = Renderer.Spritesheet.Sprite.scroll_track.info().rect.w;

    /// Draws a vertical scrollbar.
    pub fn drawVertical(renderer: *Renderer, value: f32, rect: math.Rect(f32)) !void {
        const button_h = Renderer.Spritesheet.Sprite.scroll_down.info().rect.h;

        try renderer.drawSprite(.scroll_up, .{ .x = rect.x, .y = rect.y });
        try renderer.drawSprite(.scroll_down, .{ .x = rect.x, .y = rect.y + rect.h - button_h });

        const track_y = rect.y + button_h;
        const track_h = rect.h - button_h * 2;
        const thumb_h = 16;
        const thumb_y = track_y + track_h * value - thumb_h * value;

        try renderer.drawSpriteRepeat(.scroll_track, .{
            .x = rect.x,
            .y = track_y,
            .w = rect.w,
            .h = track_h,
        });
        try renderer.drawSprite9Patch(.scroll_thumb, .{
            .x = rect.x,
            .y = thumb_y,
            .w = rect.w,
            .h = thumb_h,
        });
        try renderer.drawSprite(.scroll_thumb_marks, .{
            .x = rect.x,
            .y = thumb_y + (thumb_h - Renderer.Spritesheet.Sprite.scroll_thumb_marks.info().rect.h) / 2,
        });
    }
};

pub const flipswitch = struct {
    pub const width = Renderer.Spritesheet.Sprite.flipswitch_off.info().rect.w;
    pub const height = Renderer.Spritesheet.Sprite.flipswitch_off.info().rect.h;

    pub fn draw(
        renderer: *Renderer,
        pos: math.Vec2(f32),
        on: bool,
        icon_off: Renderer.Spritesheet.Sprite,
        icon_on: Renderer.Spritesheet.Sprite,
    ) !void {
        var sprite: Renderer.Spritesheet.Sprite = .flipswitch_off;
        var icon_y_offset: f32 = 0;
        if (on) {
            sprite = .flipswitch_on;
            icon_y_offset = 2;
        }

        try renderer.drawSprite(sprite, pos);
        try renderer.drawSprite(icon_off, .{ .x = pos.x + 1, .y = pos.y + 1 + icon_y_offset });
        try renderer.drawSprite(icon_on, .{ .x = pos.x + 1, .y = pos.y + 10 + icon_y_offset });
    }
};
