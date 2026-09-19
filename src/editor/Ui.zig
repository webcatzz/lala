//! Abstract editor UI.
//!
//! Manages a tree of UI "panes", which may each hold variable content.

const Editor = @import("Editor.zig");
const input = @import("../input.zig");
const math = @import("../math.zig");
const PatternEditor = @import("PatternEditor.zig");
const Renderer = @import("../render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Timeline = @import("Timeline.zig");

/// A flat pool of panes. Indexed with `Pane.Id`.
_panes: []?Pane,

const Ui = @This();

/// Returns a new UI system.
///
/// The system is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Ui {
    const panes = try gpa.alloc(?Pane, 4);
    errdefer gpa.free(panes);

    return .{
        ._panes = panes,
    };
}

/// Frees the UI system.
///
/// The system should not be used after calling this function.
pub fn deinit(self: Ui, gpa: std.mem.Allocator) void {
    gpa.free(self._panes);
}

/// Creates a new pane and returns its ID.
///
/// The pane is owned by the caller and should be freed by calling `deinitPane`.
pub fn initPane(self: *Ui, content: anytype, gpa: std.mem.Allocator) !Pane.Id {
    const impl = struct {
        fn initPane(ui: *Ui, pane_: Pane, gpa_: std.mem.Allocator) !Pane.Id {
            const id = blk: {
                for (ui._panes, 0..) |maybe_pane, i|
                    if (maybe_pane == null)
                        break :blk Pane.Id{ ._raw = @intCast(i) };

                const id = Pane.Id{ ._raw = @intCast(ui._panes.len) };
                ui._panes = try gpa_.realloc(ui._panes, std.ArrayList([]?Pane).growCapacity(ui._panes.len + 1));
                break :blk id;
            };

            ui._panes[id._raw] = pane_;
            return id;
        }
    };

    return impl.initPane(self, .wrap(content), gpa);
}

/// Frees the pane with the given ID.
///
/// Assumes the pane was initialized by calling `initPane`.
///
/// The pane should not be used after calling this function.
pub fn deinitPane(self: *Ui, id: Pane.Id) void {
    self._panes[id._raw] = null;
}

/// Returns a pointer to the pane with the given ID.
///
/// Avoid storing the pointer; the UI system may move its resources at any time.
///
/// Assumes the pane was initialized by calling `initPane`.
pub fn pane(self: *Ui, id: Pane.Id) *Pane {
    return &self._panes[id._raw].?;
}

pub const Pane = struct {
    /// The content displayed inside the pane.
    content: union(enum) {
        pattern_editor: PatternEditor,
        timeline: Timeline,
        v_split: Split(.x),
        h_split: Split(.y),
    },

    /// A unique identifier for a pane.
    pub const Id = struct { _raw: u8 };

    fn wrap(content: anytype) Pane {
        return .{
            .content = switch (@TypeOf(content)) {
                PatternEditor => .{ .pattern_editor = content },
                Timeline => .{ .timeline = content },
                Split(.x) => .{ .v_split = content },
                Split(.y) => .{ .h_split = content },
                else => @compileError("`Pane` cannot hold content of type `" ++ @typeName(@TypeOf(content)) ++ "`"),
            },
        };
    }

    /// Returns a pointer to the rectangle occupied by the pane.
    pub fn rect(self: *Pane) *math.Rect(f32) {
        return switch (self.content) {
            .pattern_editor => |*pattern_editor| &pattern_editor.rect,
            .timeline => |*timeline| &timeline.rect,
            .v_split => |*split| &split.rect,
            .h_split => |*split| &split.rect,
        };
    }

    /// Passes an event to the contents of the pane.
    pub fn respond(self: *Pane, editor: *Editor, event: input.Event, state: input.State) anyerror!void {
        return switch (self.content) {
            .pattern_editor => |*pattern_editor| try pattern_editor.respond(editor, event, state),
            .timeline => |*timeline| try timeline.respond(editor, event, state),
            .v_split => |*split| try split.respond(editor, event, state),
            .h_split => |*split| try split.respond(editor, event, state),
        };
    }

    /// Lays out the pane and its contents within the given rectangle.
    pub fn layOut(self: *Pane, editor: *Editor, r: math.Rect(f32)) void {
        switch (self.content) {
            .v_split => |*split| split.layOut(editor, r),
            .h_split => |*split| split.layOut(editor, r),
            else => {},
        }
    }

    /// Draws the pane.
    pub fn draw(self: Pane, editor: *Editor) error{OutOfMemory}!void {
        return switch (self.content) {
            .pattern_editor => |*pattern_editor| try pattern_editor.draw(editor),
            .timeline => |*timeline| try timeline.draw(editor),
            .v_split => |split| try split.draw(editor),
            .h_split => |split| try split.draw(editor),
        };
    }

    /// A pane which holds two other panes, arranged along the given axis.
    pub fn Split(comptime axis: math.Axis) type {
        return struct {
            /// The rectangle occupied by the pane.
            rect: math.Rect(f32) = .zero,
            /// The two child panes.
            pane_ids: [2]Pane.Id,
            /// The fraction of space occupied by the first pane, in the range \[0, 1].
            split: f32,
            /// The index of the pane with mouse focus, if any.
            active_pane_index: ?u1 = null,

            const fields = switch (axis) {
                .x => .{ .pos_main = "x", .pos_aux = "y", .size_main = "w", .size_aux = "h" },
                .y => .{ .pos_main = "y", .pos_aux = "x", .size_main = "h", .size_aux = "w" },
            };

            /// Passes the given event to one of the two child panes.
            pub fn respond(self: *Split(axis), editor: *Editor, event: input.Event, state: input.State) !void {
                if (self.active_pane_index) |active_pane_index| {
                    // Routes events to the active pane, if one exists
                    try editor.ui.pane(self.pane_ids[active_pane_index])
                        .respond(editor, event, state);
                    if (event == .button and !event.button.is_pressed)
                        self.active_pane_index = null;
                } else if (event == .button and event.button.is_pressed) {
                    // Sets the active pane when a button press event is received
                    const active_pane_index = self.paneIndexAt(state.cursor_pos);
                    self.active_pane_index = active_pane_index;
                    try editor.ui.pane(self.pane_ids[active_pane_index])
                        .respond(editor, event, state);
                } else {
                    // Otherwise, routes events to the pane under the cursor
                    try editor.ui.pane(self.pane_ids[self.paneIndexAt(state.cursor_pos)])
                        .respond(editor, event, state);
                }
            }

            /// Lays out the pane and its contents within the given rectangle.
            pub fn layOut(self: *Split(axis), editor: *Editor, r: math.Rect(f32)) void {
                self.rect = r;
                const split = self.split * @field(self.rect, fields.size_main);

                const panes = .{ editor.ui.pane(self.pane_ids[0]), editor.ui.pane(self.pane_ids[1]) };
                const pane_rects = .{ panes[0].rect(), panes[1].rect() };

                inline for (pane_rects) |pane_rect| {
                    @field(pane_rect, fields.pos_aux) = @field(r, fields.pos_aux);
                    @field(pane_rect, fields.size_aux) = @field(r, fields.size_aux);
                }

                @field(pane_rects[0], fields.pos_main) = @field(r, fields.pos_main);
                @field(pane_rects[0], fields.size_main) = @field(r, fields.pos_main) + split;
                @field(pane_rects[1], fields.pos_main) = @field(r, fields.pos_main) + split;
                @field(pane_rects[1], fields.size_main) = @field(r, fields.size_main) - split;
            }

            /// Draws the two child panes.
            pub fn draw(self: Split(axis), editor: *Editor) !void {
                inline for (self.pane_ids) |id|
                    try editor.ui.pane(id).draw(editor);
            }

            /// Sets the fraction of space occupied by the first pane.
            pub fn setSplit(self: *Split(axis), ui: *Ui, split: f32) void {
                self.split = @min(0, @max(@field(self.rect, fields.size_field), split));
                self.layOut(ui, self.rect);
            }

            /// Returns the index of the pane at the given coordinates.
            fn paneIndexAt(self: Split(axis), pos: math.Vec2(f32)) u1 {
                return @intFromBool(@field(pos, fields.pos_main) > @field(self.rect, fields.pos_main) + self.split * @field(self.rect, fields.size_main));
            }
        };
    }
};
