//! Manages tasks required for the application to run, such as rendering and
//! audio playback.

const Ctx = @import("ctx/Ctx.zig");
const input = @import("sys/input.zig");
const Renderer = @import("sys/render/Renderer.zig");
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
fn init(gpa: std.mem.Allocator, _: std.Io) !App {
    const window = sdl.SDL_CreateWindow("lala", 800, 600, sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY | sdl.SDL_WINDOW_RESIZABLE) orelse
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

    ctx.* = try .init(gpa);
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
    if (self.ctx.ui.should_repaint) {
        self.ctx.ui.should_repaint = false;
        try self.ctx.ui.repaint(&self._renderer, self._window);
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
                        .button = switch (sdl_event.key.scancode) {
                            sdl.SDL_SCANCODE_A => .key_a,
                            sdl.SDL_SCANCODE_B => .key_b,
                            sdl.SDL_SCANCODE_C => .key_c,
                            sdl.SDL_SCANCODE_D => .key_d,
                            sdl.SDL_SCANCODE_E => .key_e,
                            sdl.SDL_SCANCODE_F => .key_f,
                            sdl.SDL_SCANCODE_G => .key_g,
                            sdl.SDL_SCANCODE_H => .key_h,
                            sdl.SDL_SCANCODE_I => .key_i,
                            sdl.SDL_SCANCODE_J => .key_j,
                            sdl.SDL_SCANCODE_K => .key_k,
                            sdl.SDL_SCANCODE_L => .key_l,
                            sdl.SDL_SCANCODE_M => .key_m,
                            sdl.SDL_SCANCODE_N => .key_n,
                            sdl.SDL_SCANCODE_O => .key_o,
                            sdl.SDL_SCANCODE_P => .key_p,
                            sdl.SDL_SCANCODE_Q => .key_q,
                            sdl.SDL_SCANCODE_R => .key_r,
                            sdl.SDL_SCANCODE_S => .key_s,
                            sdl.SDL_SCANCODE_T => .key_t,
                            sdl.SDL_SCANCODE_U => .key_u,
                            sdl.SDL_SCANCODE_V => .key_v,
                            sdl.SDL_SCANCODE_W => .key_w,
                            sdl.SDL_SCANCODE_X => .key_x,
                            sdl.SDL_SCANCODE_Y => .key_y,
                            sdl.SDL_SCANCODE_Z => .key_z,
                            sdl.SDL_SCANCODE_1 => .key_1,
                            sdl.SDL_SCANCODE_2 => .key_2,
                            sdl.SDL_SCANCODE_3 => .key_3,
                            sdl.SDL_SCANCODE_4 => .key_4,
                            sdl.SDL_SCANCODE_5 => .key_5,
                            sdl.SDL_SCANCODE_6 => .key_6,
                            sdl.SDL_SCANCODE_7 => .key_7,
                            sdl.SDL_SCANCODE_8 => .key_8,
                            sdl.SDL_SCANCODE_9 => .key_9,
                            sdl.SDL_SCANCODE_0 => .key_0,
                            sdl.SDL_SCANCODE_SPACE => .key_space,
                            sdl.SDL_SCANCODE_RETURN => .key_return,
                            sdl.SDL_SCANCODE_LSHIFT => .key_lshift,
                            sdl.SDL_SCANCODE_RSHIFT => .key_rshift,
                            sdl.SDL_SCANCODE_LCTRL => .key_lctrl,
                            sdl.SDL_SCANCODE_RCTRL => .key_rctrl,
                            sdl.SDL_SCANCODE_LGUI => .key_lsuper,
                            sdl.SDL_SCANCODE_RGUI => .key_rsuper,
                            else => continue,
                        },
                        .is_pressed = sdl_event.key.down,
                    },
                }),
                sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => try app.respond(.{
                    .button = .{
                        .button = switch (sdl_event.button.button) {
                            1 => .mouse_left,
                            2 => .mouse_right,
                            3 => .mouse_middle,
                            else => continue,
                        },
                        .is_pressed = sdl_event.button.down,
                    },
                }),

                sdl.SDL_EVENT_MOUSE_MOTION => try app.respond(.{
                    .cursor = .{
                        .pos = .{
                            .x = sdl_event.motion.x / render_scale,
                            .y = sdl_event.motion.y / render_scale,
                        },
                    },
                }),

                sdl.SDL_EVENT_MOUSE_WHEEL => try app.respond(.{
                    .scroll = .{
                        .amount = .{
                            .x = sdl_event.wheel.x,
                            .y = sdl_event.wheel.y,
                        },
                        // .amount = (math.Vec2(f32){
                        //     .x = sdl_event.wheel.x,
                        //     .y = sdl_event.wheel.y,
                        // }).mul(if (sdl_event.wheel.direction == sdl.SDL_MOUSEWHEEL_FLIPPED) @as(f32, -1) else @as(f32, 1)),
                    },
                }),

                sdl.SDL_EVENT_WINDOW_RESIZED => app.ctx.ui.setNodeSize(
                    app.ctx.ui.root_node,
                    @as(f32, @floatFromInt(sdl_event.window.data1)) / render_scale,
                    @as(f32, @floatFromInt(sdl_event.window.data2)) / render_scale,
                ),

                else => continue,
            }
        }

        try app.iter();
    }
}
