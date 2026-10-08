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
/// The ID of the root pane.
root_pane: Ui.Pane.Id,
/// The ID of the piano roll pane.
piano_roll: Ui.Pane.Id,
/// The ID of the timeline pane.
timeline: Ui.Pane.Id,
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

    const piano_roll = try ui.initPane(gpa, .{ .piano_roll = .{
        .pattern_index = pattern_index,
    } });
    errdefer ui.deinitPane(piano_roll);

    const timeline = try ui.initPane(gpa, .{ .timeline = .{} });
    errdefer ui.deinitPane(timeline);

    const root_pane = try ui.initPane(gpa, .{ .split = .{
        .pane_ids = .{ piano_roll, timeline },
        .axis = .y,
        .split = 0.67,
    } });
    errdefer ui.deinitPane(root_pane);

    ui.pane(root_pane).layOut(&ui, .{ .w = 800 / App.render_scale, .h = 600 / App.render_scale });

    return .{
        .track_edit = track_edit,
        .synth = synth,
        .synth_output_buf = synth_output_buf,
        .action_bus = action_bus,
        .cfg = .{},
        .ui = ui,
        .root_pane = root_pane,
        .piano_roll = piano_roll,
        .timeline = timeline,
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

    self.ui.deinitPane(self.piano_roll);
    self.ui.deinitPane(self.timeline);
    self.ui.deinitPane(self.root_pane);
    self.ui.deinit(self.gpa);

    self.* = undefined;
}

/// Updates the context in response to an event.
pub fn respond(self: *Ctx, event: input_sys.Event) !void {
    self.input.record(event);

    if (self.input.was_action_just_pressed(.editor_toggle_playback))
        self.is_playing = !self.is_playing
    else
        try self.ui.pane(self.root_pane).respond(self, event);
}

/// Redraws the context.
pub fn redraw(self: Ctx, renderer: *Renderer) !void {
    try self.ui.paneConst(self.root_pane).draw(renderer, self);
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
