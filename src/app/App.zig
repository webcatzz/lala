const Ctx = @import("ctx/Ctx.zig");
const input = @import("input.zig");
const Renderer = @import("render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");

const App = @This();

/// App state.
ctx: *Ctx,
/// The window used to display the app.
_window: *sdl.SDL_Window,
/// The renderer used to display the app.
_renderer: Renderer,
/// The audio device used to play back audio.
_audio_device: sdl.SDL_AudioDeviceID,
/// The audio stream used to play back audio.
_audio_stream: *sdl.SDL_AudioStream,

/// The scale applied when rendering.
pub const render_scale = 3;

/// Returns the app.
///
/// The app is owned by the caller and should be freed by calling `deinit`.
fn init(gpa: std.mem.Allocator, io: std.Io) !App {
    const window = sdl.SDL_CreateWindow("lala", 800, 600, sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY) orelse
        return error.Sdl;
    errdefer sdl.SDL_DestroyWindow(window);

    var renderer: Renderer = try .init(gpa);
    errdefer renderer.deinit();

    try renderer.claimWindow(window);
    errdefer renderer.releaseWindow(window);

    const audio_device = sdl.SDL_OpenAudioDevice(sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, null);
    if (audio_device == 0)
        return error.Sdl;
    errdefer sdl.SDL_CloseAudioDevice(audio_device);

    const audio_stream = sdl.SDL_CreateAudioStream(&.{
        .format = sdl.SDL_AUDIO_F32,
        .channels = 1,
        .freq = 44100,
    }, null) orelse
        return error.Sdl;
    errdefer sdl.SDL_DestroyAudioStream(audio_stream);

    if (!sdl.SDL_BindAudioStream(audio_device, audio_stream))
        return error.Sdl;

    const ctx = try gpa.create(Ctx);
    errdefer gpa.destroy(ctx);

    ctx.* = try .init(gpa, io);
    errdefer ctx.deinit();

    if (!sdl.SDL_SetAudioStreamGetCallback(audio_stream, @ptrCast(&synth), ctx))
        return error.Sdl;

    return .{
        .ctx = ctx,
        ._window = window,
        ._renderer = renderer,
        ._audio_device = audio_device,
        ._audio_stream = audio_stream,
    };
}

/// Frees the app.
///
/// The app should not be used after calling this function.
fn deinit(self: *App) void {
    _ = sdl.SDL_SetAudioStreamGetCallback(self._audio_stream, null, null);

    var ctx = self.ctx.*;
    ctx.gpa.destroy(self.ctx);
    ctx.deinit();

    sdl.SDL_DestroyAudioStream(self._audio_stream);
    sdl.SDL_CloseAudioDevice(self._audio_device);

    self._renderer.releaseWindow(self._window);
    self._renderer.deinit();
    sdl.SDL_DestroyWindow(self._window);

    self.* = undefined;
}

/// Updates app state.
fn iter(self: *App) !void {
    if (self.ctx.should_redraw) {
        self.ctx.should_redraw = false;
        self._renderer.clear();

        var w: c_int = undefined;
        var h: c_int = undefined;
        if (!sdl.SDL_GetWindowSizeInPixels(self._window, &w, &h))
            return error.Sdl;

        const scale = sdl.SDL_GetWindowDisplayScale(self._window);
        if (scale == 0)
            return error.Sdl;

        self._renderer.switchScale(
            1 / @as(f32, @floatFromInt(w)) * scale * render_scale,
            1 / @as(f32, @floatFromInt(h)) * scale * render_scale,
        );

        try self.ctx.redraw(&self._renderer);

        try self._renderer.render(self._window);
    }
}

/// Updates app state in response to user input.
fn respond(self: *App, event: input.Event) !void {
    return self.ctx.respond(event);
}

/// Synthesizes additional audio into the given stream.
///
/// Called by SDL when additional audio data is needed by the stream.
fn synth(ctx: *Ctx, stream: *sdl.SDL_AudioStream, additional_bytes: c_int, _: c_int) callconv(.c) void {
    if (!ctx.is_playing) return;

    const output_buf = ctx.synth_output_buf[0..@intCast(@divFloor(additional_bytes, @sizeOf(f32)))];
    @memset(output_buf, 0);
    const output_len = ctx.synth.run(ctx.track_edit.track, output_buf) catch return;

    _ = sdl.SDL_PutAudioStreamData(stream, output_buf.ptr, @as(c_int, @intCast(output_len)) * @sizeOf(f32));
}

/// Runs the app.
///
/// Initializes the app by calling `init`, then repeatedly calls `iter` and
/// `respond` as necessary.
///
/// Blocks until the user requests to quit.
pub fn run(gpa: std.mem.Allocator, io: std.Io) !void {
    defer sdl.SDL_Quit();
    _ = sdl.SDL_SetAppMetadataProperty(sdl.SDL_PROP_APP_METADATA_NAME_STRING, "chipr");
    _ = sdl.SDL_SetAppMetadataProperty(sdl.SDL_PROP_APP_METADATA_CREATOR_STRING, "lamb chapel");
    _ = sdl.SDL_SetAppMetadataProperty(sdl.SDL_PROP_APP_METADATA_URL_STRING, "https://lambchapel.neocities.org");
    if (!sdl.SDL_Init(sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_VIDEO))
        return error.Sdl;

    var app = try init(gpa, io);
    defer app.deinit();

    main: while (true) {
        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event)) {
            switch (sdl_event.type) {
                sdl.SDL_EVENT_QUIT => break :main,

                sdl.SDL_EVENT_KEY_DOWN, sdl.SDL_EVENT_KEY_UP => try app.respond(.{
                    .button = .{
                        .button = input.Button.fromKeyCode(@intCast(sdl_event.key.scancode)) orelse continue,
                        .is_pressed = sdl_event.key.down,
                    },
                }),
                sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => try app.respond(.{
                    .button = .{
                        .button = input.Button.fromMouseCode(sdl_event.button.button) orelse continue,
                        .is_pressed = sdl_event.button.down,
                    },
                }),

                sdl.SDL_EVENT_MOUSE_MOTION => {
                    try app.respond(.{
                        .cursor = .{
                            .pos = .{
                                .x = sdl_event.motion.x / render_scale,
                                .y = sdl_event.motion.y / render_scale,
                            },
                        },
                    });
                },

                sdl.SDL_EVENT_MOUSE_WHEEL => try app.respond(.{
                    .scroll = .{
                        .amount = .{
                            .x = sdl_event.wheel.x,
                            .y = sdl_event.wheel.y,
                        },
                    },
                }),

                else => continue,
            }
        }

        try app.iter();
    }
}
