const Editor = @import("editor/Editor.zig");
const input = @import("input.zig");
const math = @import("math.zig");
const sdl = @import("sdl");
const std = @import("std");

pub const usageStr =
    \\Usage:
    \\    edit [path]        Opens the editor, with a track file loaded if given.
    \\    play <path>        Plays the track in the given file.
;

/// The scale applied when rendering.
pub const render_scale = 3;

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();

    _ = args.skip();

    (blk: {
        if (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "edit"))
                break :blk loop(Editor, init)
            else if (std.mem.eql(u8, arg, "play"))
                break :blk error.Todo;

            std.log.err("Unknown command\n{s}", .{usageStr});
            break :blk error.UnknownCommand;
        } else {
            std.log.err("Provide command\n{s}", .{usageStr});
            break :blk error.MissingCommand;
        }
    }) catch |err| {
        if (err == error.Sdl)
            std.log.scoped(.sdl).err("{s}", .{sdl.SDL_GetError()});
        return err;
    };
}

/// Runs the main loop.
pub fn loop(comptime T: type, init: std.process.Init) !void {
    defer sdl.SDL_Quit();
    if (!sdl.SDL_Init(sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_VIDEO))
        return error.Sdl;

    _ = sdl.SDL_SetAppMetadataProperty(sdl.SDL_PROP_APP_METADATA_NAME_STRING, "chipr");
    _ = sdl.SDL_SetAppMetadataProperty(sdl.SDL_PROP_APP_METADATA_CREATOR_STRING, "lamb chapel");
    _ = sdl.SDL_SetAppMetadataProperty(sdl.SDL_PROP_APP_METADATA_URL_STRING, "https://lambchapel.neocities.org");

    var inner = try T.init(init.gpa, init.io);
    defer inner.deinit();

    var input_state = input.State.default;

    main: while (true) {
        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event)) {
            const event: input.Event = switch (sdl_event.type) {
                sdl.SDL_EVENT_QUIT => break :main,

                sdl.SDL_EVENT_KEY_DOWN, sdl.SDL_EVENT_KEY_UP => .{
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
                },
                sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => .{
                    .button = .{
                        .button = switch (sdl_event.button.button) {
                            1 => .mouse_left,
                            2 => .mouse_right,
                            3 => .mouse_middle,
                            else => continue,
                        },
                        .is_pressed = sdl_event.button.down,
                    },
                },

                sdl.SDL_EVENT_MOUSE_MOTION => .{
                    .cursor = .{
                        .pos = .{
                            .x = sdl_event.motion.x / render_scale,
                            .y = sdl_event.motion.y / render_scale,
                        },
                    },
                },

                sdl.SDL_EVENT_MOUSE_WHEEL => .{
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
                },

                else => continue,
            };

            input_state.record(event);
            try inner.respond(event, input_state);
        }

        try inner.iter();
    }
}
