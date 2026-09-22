const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const pitch = @import("../../synth/pitch.zig");
const Renderer = @import("../core/render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Synth = @import("../../synth/Synth.zig");
const Track = @import("../../synth/Track.zig");

const ActionBus = @import("ActionBus.zig");
const PatternEditor = @import("PatternEditor.zig");
const TrackBuffers = @import("TrackBuffers.zig");
const Timeline = @import("Timeline.zig");
const Ui = @import("Ui.zig");

action_bus: ActionBus,

/// The track being edited.
track: Track,
/// Buffers of track components.
///
/// This is the allocation used to store track components created by the editor.
track_buffers: TrackBuffers,

/// The synth used to play the edited track.
_synth: Synth,
/// The audio buffer used by the synth.
_synth_output_buf: []f32,
/// If `true`, the editor should play back audio.
is_playing: bool = false,

/// The UI system.
ui: Ui,
/// The ID of the root UI pane.
_root_pid: Ui.Pane.Id,
/// The ID of the pattern editor UI pane.
_pattern_editor_pid: Ui.Pane.Id,
/// The ID of the timeline UI pane.
_timeline_pid: Ui.Pane.Id,

/// The allocator provided by the editor.
gpa: std.mem.Allocator,
/// The IO interface provided by the editor.
io: std.Io,
/// The window used to display the editor.
_window: *sdl.SDL_Window,
/// The renderer used to display the editor.
renderer: Renderer,
/// The audio device used to play back audio.
_audio_device: sdl.SDL_AudioDeviceID,
/// The audio stream used to play back audio.
_audio_stream: *sdl.SDL_AudioStream,

// font: Font,

const Editor = @This();

/// The rendering scale applied to the editor.
const render_scale = @import("../core/loop.zig").render_scale;

/// Returns a new editor.
///
/// The editor is owned by the caller and should be freed by calling `deinit`.
///
/// The SDL audio and video subsystems should be initialized before calling this
/// function and remain initialized until after the editor is freed.
pub fn init(gpa: std.mem.Allocator, io: std.Io) !Editor {
    const window = sdl.SDL_CreateWindow("lala", 800, 600, sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY | sdl.SDL_WINDOW_RESIZABLE) orelse
        return error.Sdl;
    errdefer sdl.SDL_DestroyWindow(window);

    var renderer = try Renderer.init(gpa);
    errdefer renderer.deinit();

    try renderer.claimWindow(window);
    errdefer renderer.releaseWindow(window);

    var synth = try Synth.init(gpa);
    errdefer synth.deinit(gpa);

    const synth_output_buf = try gpa.alloc(f32, 4096);
    errdefer gpa.free(synth_output_buf);

    const audio_device = switch (sdl.SDL_OpenAudioDevice(sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, null)) {
        0 => return error.Sdl,
        else => |id| id,
    };
    errdefer sdl.SDL_CloseAudioDevice(audio_device);

    const audio_stream = sdl.SDL_CreateAudioStream(&.{
        .format = sdl.SDL_AUDIO_F32,
        .channels = 1,
        .freq = synth.sample_rate,
    }, null) orelse
        return error.Sdl;
    errdefer sdl.SDL_DestroyAudioStream(audio_stream);

    if (!sdl.SDL_BindAudioStream(audio_device, audio_stream))
        return error.Sdl;

    const track_buffers = try TrackBuffers.init(gpa);
    errdefer track_buffers.deinit(gpa);

    var ui = try Ui.init(gpa);
    errdefer ui.deinit(gpa);

    const pattern_editor_pid = try ui.initPane(PatternEditor{}, gpa);
    errdefer ui.deinitPane(pattern_editor_pid);

    const timeline_pid = try ui.initPane(Timeline{}, gpa);
    errdefer ui.deinitPane(timeline_pid);

    const root_pid = try ui.initPane(Ui.Pane.Split(.y){
        .pane_ids = .{ pattern_editor_pid, timeline_pid },
        .split = 0.67,
    }, gpa);
    errdefer ui.deinitPane(root_pid);

    const action_bus = try ActionBus.init(gpa);
    errdefer action_bus.deinit(gpa);

    var editor = Editor{
        .action_bus = action_bus,

        .ui = ui,
        ._root_pid = root_pid,
        ._pattern_editor_pid = pattern_editor_pid,
        ._timeline_pid = timeline_pid,

        .track = .{
            .channels = track_buffers.channel_buf[0..0],
            .patterns = track_buffers.pattern_buf,
        },
        .track_buffers = track_buffers,

        ._synth = synth,
        ._synth_output_buf = synth_output_buf,

        .gpa = gpa,
        .io = io,
        ._window = window,
        .renderer = renderer,
        ._audio_device = audio_device,
        ._audio_stream = audio_stream,

        // .font = font,
    };

    const chan_i = try ActionBus.Action.insertChannel(&editor, 0, .{
        .sections = undefined,
    });
    _ = try ActionBus.Action.insertSection(&editor, 0, .{
        .interval = .{ .first_tick = 0, .last_tick = 384 },
        .pattern_index = 0,
    });
    editor.track.patterns[0] = .{ .notes = editor.track_buffers.note_bufs[0][0..0] };
    editor.track.channels[chan_i].sections.ptr = editor.track_buffers.section_bufs[chan_i].ptr;

    editor.timeline().selection = .{ .channel_index = 0, .section_index = 0 };

    editor.layOut();
    try editor.redraw();

    return editor;
}

/// Frees the editor.
///
/// The editor should not be used after this function is called.
pub fn deinit(self: *Editor) void {
    self.action_bus.deinit(self.gpa);

    self.track_buffers.deinit(self.gpa);

    self._synth.deinit(self.gpa);
    self.gpa.free(self._synth_output_buf);

    self.ui.deinit(self.gpa);

    sdl.SDL_DestroyAudioStream(self._audio_stream);
    sdl.SDL_CloseAudioDevice(self._audio_device);
    self.renderer.releaseWindow(self._window);
    self.renderer.deinit();
    sdl.SDL_DestroyWindow(self._window);
}

// Actions

/// Shorthand for `self.action_bus.do(self, action)`.
///
/// See `ActionBus.do` for documentation.
pub fn do(self: *Editor, action: ActionBus.Action) !ActionBus.Action {
    return self.action_bus.do(self, action);
}

/// Shorthand for `self.action_bus.undo(self)`.
///
/// See `ActionBus.undo` for documentation.
pub fn undo(self: *Editor) !?void {
    return self.action_bus.undo(self);
}

/// Shorthand for `self.action_bus.redo(self)`.
///
/// See `ActionBus.redo` for documentation.
pub fn redo(self: *Editor) !?void {
    return self.action_bus.redo(self);
}

/// Updates the editor in response to the given event.
pub fn respond(self: *Editor, event: input.Event, state: input.State) !void {
    if (state.was_action_just_pressed(.editor_undo)) {
        _ = try self.undo();
        try self.redraw();
    } else if (state.was_action_just_pressed(.editor_redo)) {
        _ = try self.redo();
        try self.redraw();
    } else if (state.was_action_just_pressed(.editor_toggle_playback)) {
        self.is_playing = !self.is_playing;
        self._synth.seek(0);
    } else {
        try self.rootPane().respond(self, event, state);
    }
}

/// Updates the iterator.
pub fn iter(self: *Editor) !void {
    if (self.is_playing) {
        const sample_deficit = self._synth_output_buf.len -| @as(usize, @intCast(sdl.SDL_GetAudioStreamQueued(self._audio_stream))) / @sizeOf(f32);
        const output_buf = self._synth_output_buf[0..sample_deficit];
        @memset(output_buf, 0);
        const output_len = try self._synth.run(self.track, output_buf);

        if (!sdl.SDL_PutAudioStreamData(self._audio_stream, output_buf.ptr, @as(c_int, @intCast(output_len)) * @sizeOf(f32)))
            return error.Sdl;
    }
}

/// Lays out the editor UI.
pub fn layOut(self: *Editor) void {
    var w: c_int = 0;
    var h: c_int = 0;
    if (!sdl.SDL_GetWindowSize(self._window, &w, &h))
        std.log.err("SDL: {s}", .{sdl.SDL_GetError()});

    self.rootPane().layOut(self, .{
        .w = @as(f32, @floatFromInt(w)) / render_scale,
        .h = @as(f32, @floatFromInt(h)) / render_scale,
    });
}

/// Draws the editor UI.
pub fn redraw(self: *Editor) !void {
    const root_pane_rect = self.rootPane().rect().*;
    self.renderer.scale = .{
        .x = 1 / root_pane_rect.w,
        .y = 1 / root_pane_rect.h,
    };

    self.renderer.clear();

    try self.rootPane().draw(self);

    try self.renderer.render(self._window);
}

// UI components

/// Returns the root UI pane of the editor.
pub fn rootPane(self: *Editor) *Ui.Pane {
    return self.ui.pane(self._root_pid);
}

/// Returns the pattern editor displayed in the editor.
pub fn patternEditor(self: *Editor) *PatternEditor {
    return &self.ui.pane(self._pattern_editor_pid).content.pattern_editor;
}

/// Returns the timeline displayed in the editor.
pub fn timeline(self: *Editor) *Timeline {
    return &self.ui.pane(self._timeline_pid).content.timeline;
}

// Colors

pub fn patternColor(pattern_index: usize) math.Color(f32) {
    return ([_]math.Color(f32){
        .red,
        .blue,
        .green,
    })[pattern_index % 16];
}
