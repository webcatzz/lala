//! App context.

const ActionBus = @import("ActionBus.zig");
const App = @import("../App.zig");
const Config = @import("Config.zig");
const input_sys = @import("../input.zig");
const PianoRoll = @import("../panes/PianoRoll.zig");
const Renderer = @import("../render/Renderer.zig");
const std = @import("std");
const Synth = @import("../../synth/Synth.zig");
const Timeline = @import("../panes/Timeline.zig");
const Track = @import("../../synth/Track.zig");
const TrackEdit = @import("TrackEdit.zig");
const Ui = @import("../Ui.zig");

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
/// User configuration.
cfg: Config,

/// The UI system.
ui: Ui,
root: *Ui.Split,
root_id: Ui.Id,
piano_roll: *PianoRoll,
piano_roll_id: Ui.Id,
timeline: *Timeline,
timeline_id: Ui.Id,
/// If `true`, UI should redraw.
should_redraw: bool = true,

/// A general-purpose allocator.
gpa: std.mem.Allocator,
/// An IO interface.
io: std.Io,

/// Returns a new context.
///
/// The context is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator, io: std.Io) !Ctx {
    var track_edit: TrackEdit = .{};
    errdefer track_edit.deinit(gpa);

    const pattern_index: u8 = @intCast(try track_edit.insertPattern(gpa));
    try track_edit.insertChannel(gpa, .{}, 0);
    _ = try track_edit.insertSection(gpa, 0, .{
        .interval = .{ .first_tick = 0, .last_tick = 192 },
        .pattern_index = pattern_index,
    });

    var synth: Synth = try .init(gpa);
    errdefer synth.deinit(gpa);

    const synth_output_buf = try gpa.alloc(f32, 4096);
    errdefer gpa.free(synth_output_buf);

    const action_bus: ActionBus = try .init(gpa);
    errdefer action_bus.deinit(gpa);

    var ui: Ui = try .init(gpa);
    errdefer ui.deinit(gpa);

    const piano_roll = try gpa.create(PianoRoll);
    errdefer gpa.destroy(piano_roll);
    piano_roll.* = .{ .pattern_index = 0 };
    const piano_roll_id = try ui.insert(gpa, undefined, .construct(PianoRoll, piano_roll));

    const timeline = try gpa.create(Timeline);
    errdefer gpa.destroy(timeline);
    timeline.* = .{};
    const timeline_id = try ui.insert(gpa, undefined, .construct(Timeline, timeline));

    const root = try gpa.create(Ui.Split);
    errdefer gpa.destroy(root);
    const root_id = try ui.insert(gpa, .{
        .w = App.width,
        .h = App.height,
    }, .construct(Ui.Split, root));

    root.* = .{
        .children = .{ piano_roll_id, timeline_id },
        .axis = .y,
        .split = 0.67,
    };
    ui.layOut(root_id);

    return .{
        .track_edit = track_edit,
        .synth = synth,
        .synth_output_buf = synth_output_buf,
        .action_bus = action_bus,
        .cfg = .{},
        .ui = ui,
        .root = root,
        .root_id = root_id,
        .piano_roll = piano_roll,
        .piano_roll_id = piano_roll_id,
        .timeline = timeline,
        .timeline_id = timeline_id,
        .gpa = gpa,
        .io = io,
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

    self.ui.deinit(self.gpa);
    self.gpa.destroy(self.root);
    self.gpa.destroy(self.piano_roll);
    self.gpa.destroy(self.timeline);

    self.* = undefined;
}

/// Updates the context in response to an event.
pub fn respond(self: *Ctx, comptime event_type: input_sys.Type, event: input_sys.Event(event_type)) !void {
    self.input.record(event_type, event);

    if (self.input.was_action_just_pressed(.editor_toggle_playback))
        self.is_playing = !self.is_playing
    else
        try self.ui.respond(self.root_id, self, event_type, event);
}

/// Redraws the context.
pub fn redraw(self: Ctx, renderer: *Renderer) !void {
    try self.ui.draw(self.root_id, renderer, self);
}

/// Requests that the context be redrawn at a later time.
pub fn queueRedraw(self: *Ctx) void {
    self.should_redraw = true;
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
