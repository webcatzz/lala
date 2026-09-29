//! App context.

const ActionBus = @import("ActionBus.zig");
const input_sys = @import("../sys/input.zig");
const std = @import("std");
const Synth = @import("../../synth/Synth.zig");
const Track = @import("../../synth/Track.zig");
const TrackEdit = @import("TrackEdit.zig");
const Ui = @import("../sys/Ui.zig");

const Ctx = @This();

/// The track currently being edited.
track_edit: TrackEdit,

/// A synth used to play back the track.
synth: Synth,
/// An audio buffer used by the synth.
synth_output_buf: []f32,
/// If `true`, the context should play back audio.
is_playing: bool = false,

/// A log of past and future user actions.
action_bus: ActionBus,
/// The current input state.
input: input_sys.State = .default,
/// The UI system.
ui: Ui,

/// A general-purpose allocator.
gpa: std.mem.Allocator,

/// Returns a new context.
///
/// The context is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Ctx {
    var track_edit: TrackEdit = try .init(gpa);
    errdefer track_edit.deinit(gpa);

    var synth: Synth = try .init(gpa);
    errdefer synth.deinit(gpa);

    const synth_output_buf = try gpa.alloc(f32, 4096);
    errdefer gpa.free(synth_output_buf);

    const action_bus: ActionBus = try .init(gpa);
    errdefer action_bus.deinit(gpa);

    var ui: Ui = try .init(gpa);
    errdefer ui.deinit();

    ui.setNodeSize(ui.root_node, 400, 300);
    ui._nodes.items[ui.root_node._index].paint_mode = .fromSprite(.blank);

    return .{
        .track_edit = track_edit,
        .synth = synth,
        .synth_output_buf = synth_output_buf,
        .action_bus = action_bus,
        .ui = ui,
        .gpa = gpa,
    };
}

/// Frees the context.
///
/// The context should not be used after calling this function.
pub fn deinit(self: *Ctx) void {
    self.track_edit.deinit(self.gpa);

    self.synth.deinit(self.gpa);
    self.gpa.free(self.synth_output_buf);

    self.action_bus.deinit(self.gpa);
    self.ui.deinit();

    self.* = undefined;
}

/// Updates the context in response to an event.
pub fn respond(self: *Ctx, event: input_sys.Event) void {
    self.input.record(event);
}

/// Shorthand for `self.action_bus.do(self, action)`.
///
/// See `ActionBus.do` for documentation.
pub fn do(self: *Ctx, action: ActionBus.Action) !ActionBus.Action {
    return self.action_bus.do(self, action);
}

/// Shorthand for `self.action_bus.undo(self)`.
///
/// See `ActionBus.undo` for documentation.
pub fn undo(self: *Ctx) !?void {
    return self.action_bus.undo(self);
}

/// Shorthand for `self.action_bus.redo(self)`.
///
/// See `ActionBus.redo` for documentation.
pub fn redo(self: *Ctx) !?void {
    return self.action_bus.redo(self);
}
