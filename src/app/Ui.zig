//! Abstract editor UI.
//!
//! Manages a tree of "panes", which may each hold variable content.

const App = @import("App.zig");
const builtin = @import("builtin");
const Ctx = @import("ctx/Ctx.zig");
const input = @import("input.zig");
const math = @import("util/math.zig");
const PianoRoll = @import("panes/PianoRoll.zig");
const Renderer = @import("render/Renderer.zig");
const sdl = @import("sdl");
const sparse_list = @import("util/sparse_list.zig");
const std = @import("std");
const Timeline = @import("panes/Timeline.zig");

const Ui = @This();

/// The panes in the system. Indexed with `Pane.Id`.
panes: sparse_list.SparseList(Pane),

/// A node in the UI tree.
pub const Pane = union(enum) {
    piano_roll: PianoRoll,
    timeline: Timeline,
    split: Split,

    /// A unique identifier for a pane.
    pub const Id = struct { _index: u8 };

    /// Returns the rectangle occupied by the pane.
    pub fn rect(self: Pane) math.Rect(f32) {
        return switch (self) {
            .piano_roll => |piano_roll| piano_roll.rect,
            .timeline => |timeline| timeline.rect,
            .split => |split| split.rect,
        };
    }

    /// Updates the pane in response to an event.
    pub fn respond(self: *Pane, ctx: *Ctx, event: input.Event) error{OutOfMemory}!void {
        return switch (self.*) {
            .piano_roll => |*piano_roll| piano_roll.respond(ctx, event),
            .timeline => |*timeline| timeline.respond(ctx, event),
            .split => |*split| split.respond(ctx, event),
        };
    }

    /// Lays out the pane and its contents within the given rectangle.
    pub fn layOut(self: *Pane, ui: *Ui, r: math.Rect(f32)) void {
        switch (self.*) {
            .piano_roll => |*piano_roll| piano_roll.rect = r,
            .timeline => |*timeline| timeline.rect = r,
            .split => |*split| split.layOut(ui, r),
        }
    }

    /// Draws the pane.
    pub fn draw(self: Pane, renderer: *Renderer, ctx: Ctx) error{OutOfMemory}!void {
        try switch (self) {
            .piano_roll => |piano_roll| piano_roll.draw(renderer, ctx),
            .timeline => |timeline| timeline.draw(renderer, ctx),
            .split => |split| split.draw(renderer, ctx),
        };
    }

    /// A pane which holds two other panes, arranged along the given axis.
    pub const Split = struct {
        /// The rectangle occupied by the pane.
        rect: math.Rect(f32) = .zero,
        /// The two child panes.
        pane_ids: [2]Pane.Id,
        /// The axis along which child panes are arranged.
        axis: math.Axis,
        /// The fraction of space occupied by the first pane, in the range \[0, 1].
        split: f32,
        /// The index of the pane with mouse focus, if any.
        active_pane_index: ?u1 = null,

        /// Routes the given event to one of the two child panes.
        fn respond(self: *Split, ctx: *Ctx, event: input.Event) !void {
            if (self.active_pane_index) |active_pane_index| {
                // Routes events to the active pane, if one exists
                try ctx.ui.pane(self.pane_ids[active_pane_index])
                    .respond(ctx, event);
                if (event == .button and !event.button.is_pressed)
                    self.active_pane_index = null;
            } else if (event == .button and event.button.is_pressed) {
                // Sets the active pane when a button press event is received
                const active_pane_index = self.paneIndexAt(ctx.input.cursor_pos);
                self.active_pane_index = active_pane_index;
                try ctx.ui.pane(self.pane_ids[active_pane_index])
                    .respond(ctx, event);
            } else {
                // Otherwise, routes events to the pane under the cursor
                try ctx.ui.pane(self.pane_ids[self.paneIndexAt(ctx.input.cursor_pos)])
                    .respond(ctx, event);
            }
        }

        /// Lays out the pane and its contents within the given rectangle.
        fn layOut(self: *Split, ui: *Ui, r: math.Rect(f32)) void {
            self.rect = r;

            switch (self.axis) {
                .x => {
                    const split = self.split * self.rect.w;
                    ui.pane(self.pane_ids[0]).layOut(ui, .{
                        .y = self.rect.x,
                        .x = self.rect.y,
                        .h = split,
                        .w = self.rect.h,
                    });
                    ui.pane(self.pane_ids[1]).layOut(ui, .{
                        .y = self.rect.x + split,
                        .x = self.rect.y,
                        .h = self.rect.w - split,
                        .w = self.rect.h,
                    });
                },
                .y => {
                    const split = self.split * self.rect.h;
                    ui.pane(self.pane_ids[0]).layOut(ui, .{
                        .x = self.rect.x,
                        .y = self.rect.y,
                        .w = self.rect.w,
                        .h = split,
                    });
                    ui.pane(self.pane_ids[1]).layOut(ui, .{
                        .x = self.rect.x,
                        .y = self.rect.y + split,
                        .w = self.rect.w,
                        .h = self.rect.h - split,
                    });
                },
            }
        }

        /// Draws the two child panes.
        fn draw(self: Split, renderer: *Renderer, ctx: Ctx) !void {
            inline for (self.pane_ids) |id|
                try ctx.ui.paneConst(id).draw(renderer, ctx);
        }

        /// Sets the fraction of space occupied by the first pane.
        fn setSplit(self: *Split, ui: *Ui, split: f32) void {
            self.split = @min(0, @max(self.rect.sizeAlong(self.axis), split));
            self.layOut(ui, self.rect);
        }

        /// Returns the index of the pane at the given coordinates.
        fn paneIndexAt(self: Split, pos: math.Vec2(f32)) u1 {
            return switch (self.axis) {
                .x => @intFromBool(pos.x > self.rect.x + self.split * self.rect.w),
                .y => @intFromBool(pos.y > self.rect.y + self.split * self.rect.h),
            };
        }
    };
};

/// Returns a new UI system.
///
/// The system is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Ui {
    const panes: sparse_list.SparseList(Pane) = try .initCapacity(gpa, 8);
    errdefer panes.deinit(gpa);

    return .{
        .panes = panes,
    };
}

/// Frees the UI system.
///
/// In `Debug` or `ReleaseSafe` mode, logs an error for each pane left
/// initialized.
///
/// The system should not be used after calling this function.
pub fn deinit(self: *Ui, gpa: std.mem.Allocator) void {
    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe)
        for (0..self.panes.items.len) |i|
            if (self.panes.isInit(i))
                std.log.scoped(.ui).err("pane #{} leaked", .{i});

    self.panes.deinit(gpa);
    self.* = undefined;
}

/// Creates a new pane and returns its ID.
///
/// The pane is owned by the caller and should be freed by calling `deinitPane`.
/// Note that `deinitPane` does not deinitialize the pane contents, which need to
/// be deinitialized separately.
pub fn initPane(self: *Ui, gpa: std.mem.Allocator, p: Pane) !Pane.Id {
    return .{ ._index = @intCast(try self.panes.insert(gpa, p)) };
}

/// Frees the pane with the given ID.
///
/// Note that this function does not deinitialize the pane's contents, which
/// should be deinitialized separately.
///
/// Assumes the ID is valid. The ID is invalidated after calling this function
/// and should not be used again.
pub fn deinitPane(self: *Ui, id: Pane.Id) void {
    self.panes.unset(id._index);
}

/// Returns a pointer to the pane with the given ID.
///
/// Avoid storing the pointer; the UI system may move its resources at any time.
///
/// Assumes the ID is valid.
pub fn pane(self: *Ui, id: Pane.Id) *Pane {
    return &self.panes.items[id._index];
}

/// Returns a constant pointer to the pane with the given ID.
///
/// Avoid storing the pointer; the UI system may move its resources at any time.
///
/// Assumes the ID is valid.
pub fn paneConst(self: *const Ui, id: Pane.Id) *const Pane {
    return &self.panes.items[id._index];
}

// Common UI elements

pub const frame = struct {
    /// The widths of the borders of the frame.
    pub const border = Renderer.Spritesheet.Sprite.frame.info().border;

    /// Draws the frame
    pub fn draw(renderer: *Renderer, rect: math.Rect(f32)) !void {
        try renderer.drawSprite9Patch(.frame, rect);
    }
};

pub const scrollbar = struct {
    /// Draws a vertical scrollbar.
    pub fn drawVertical(renderer: *Renderer, value: f32, rect: math.Rect(f32)) !void {
        const button_h = Renderer.Spritesheet.Sprite.scroll_down.info().rect.h;

        try renderer.drawSprite(.scroll_up, .{ .x = rect.x, .y = rect.y });
        try renderer.drawSprite(.scroll_down, .{ .x = rect.x, .y = rect.y + rect.h - button_h });

        const track_y = rect.y + button_h;
        const track_h = rect.h - button_h * 2;
        const thumb_h = 64;
        const thumb_y = track_y - thumb_h * value;

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
            .y = thumb_y + thumb_h / 2 - Renderer.Spritesheet.Sprite.scroll_thumb_marks.info().rect.h,
        });
    }
};

// pub const Scrollbar = struct {
//     pub fn respond(renderer: *Renderer, rect: math.Rect(f32)) void {}

//     pub fn draw(renderer: *Renderer, axis: math.Axis, value: f32, rect: math.Rect(f32)) void {
//         switch (axis) {
//             .x => {
//                 const thumb_len = 32;
//                 const thumb_off = (rect.h - thumb_len) * value;

//                 renderer.drawSprite9Patch(.scroll_thumb, pos: Vec2(f32))
//             },
//             .y => {},
//         }
//     }
// };
