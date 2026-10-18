const App = @import("app/App.zig");
const input = @import("app/input.zig");
const sokol = @import("sokol");
const std = @import("std");

pub fn main(init: std.process.Init) void {
    gpa = init.gpa;
    io = init.io;
    sokol.app.run(.{
        .width = 800,
        .height = 600,
        .init_cb = sokol_init,
        .frame_cb = sokol_frame,
        .cleanup_cb = sokol_cleanup,
        .event_cb = sokol_event,
    });
}

var app: App = undefined;
var gpa: std.mem.Allocator = undefined;
var io: std.Io = undefined;

fn sokol_init() callconv(.c) void {
    sokol.gfx.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    app = App.init(gpa, io) catch return quitErr();
}

fn sokol_frame() callconv(.c) void {
    app.iter() catch quitErr();
}

fn sokol_cleanup() callconv(.c) void {
    app.deinit();

    sokol.gfx.shutdown();
}

fn sokol_event(event: [*c]const sokol.app.Event) callconv(.c) void {
    (switch (event.*.type) {
        .KEY_DOWN => app.respond(.button, .{
            .button = buttonFromSokolKeycode(event.*.key_code) orelse return,
            .is_pressed = true,
        }),
        .KEY_UP => app.respond(.button, .{
            .button = buttonFromSokolKeycode(event.*.key_code) orelse return,
            .is_pressed = false,
        }),
        .MOUSE_DOWN => app.respond(.button, .{
            .button = buttonFromSokolMouseButton(event.*.mouse_button) orelse return,
            .is_pressed = true,
        }),
        .MOUSE_UP => app.respond(.button, .{
            .button = buttonFromSokolMouseButton(event.*.mouse_button) orelse return,
            .is_pressed = true,
        }),
        .MOUSE_MOVE => app.respond(.cursor, .{
            .pos = .{
                .x = event.*.mouse_x,
                .y = event.*.mouse_y,
            },
        }),
        .MOUSE_SCROLL => app.respond(.scroll, .{
            .amount = .{
                .x = event.*.scroll_x,
                .y = event.*.scroll_y,
            },
        }),
        else => {},
    }) catch quitErr();
}

fn buttonFromSokolKeycode(keycode: sokol.app.Keycode) ?input.Button {
    return switch (keycode) {
        .SPACE => .key_space,
        .APOSTROPHE => .key_apostrophe,
        .COMMA => .key_comma,
        .MINUS => .key_minus,
        .PERIOD => .key_period,
        .SLASH => .key_slash,
        ._0 => .key_0,
        ._1 => .key_1,
        ._2 => .key_2,
        ._3 => .key_3,
        ._4 => .key_4,
        ._5 => .key_5,
        ._6 => .key_6,
        ._7 => .key_7,
        ._8 => .key_8,
        ._9 => .key_9,
        .SEMICOLON => .key_semicolon,
        .EQUAL => .key_equals,
        .A => .key_a,
        .B => .key_b,
        .C => .key_c,
        .D => .key_d,
        .E => .key_e,
        .F => .key_f,
        .G => .key_g,
        .H => .key_h,
        .I => .key_i,
        .J => .key_j,
        .K => .key_k,
        .L => .key_l,
        .M => .key_m,
        .N => .key_n,
        .O => .key_o,
        .P => .key_p,
        .Q => .key_q,
        .R => .key_r,
        .S => .key_s,
        .T => .key_t,
        .U => .key_u,
        .V => .key_v,
        .W => .key_w,
        .X => .key_x,
        .Y => .key_y,
        .Z => .key_z,
        .LEFT_BRACKET => .key_lbracket,
        .BACKSLASH => .key_backslash,
        .RIGHT_BRACKET => .key_rbracket,
        .GRAVE_ACCENT => .key_grave,
        .ESCAPE => .key_escape,
        .ENTER => .key_return,
        .TAB => .key_tab,
        .BACKSPACE => .key_delete,
        .RIGHT => .key_right,
        .LEFT => .key_left,
        .DOWN => .key_down,
        .UP => .key_up,
        .LEFT_SHIFT => .key_lshift,
        .LEFT_CONTROL => .key_lctrl,
        .LEFT_ALT => .key_lalt,
        .LEFT_SUPER => .key_lgui,
        .RIGHT_SHIFT => .key_rshift,
        .RIGHT_CONTROL => .key_rctrl,
        .RIGHT_ALT => .key_ralt,
        .RIGHT_SUPER => .key_rgui,
        else => null,
    };
}

fn buttonFromSokolMouseButton(mouse_button: sokol.app.Mousebutton) ?input.Button {
    return switch (mouse_button) {
        .LEFT => .mouse_left,
        .RIGHT => .mouse_right,
        .MIDDLE => .mouse_middle,
        .INVALID => null,
    };
}

fn quitErr() void {
    if (@errorReturnTrace()) |trace|
        std.debug.dumpErrorReturnTrace(trace);
    sokol.app.requestQuit();
}

// Test imports

test {
    _ = @import("app/ctx/TrackEdit.zig");
}
