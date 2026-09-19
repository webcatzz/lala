const math = @import("../math.zig");
const Renderer = @import("Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Texture = @import("Texture.zig");

/// The height of a character in the font.
line_height: f32,
/// Information for each character in the font.
char_info: std.AutoHashMap(u8, struct { x: f32, y: f32, w: f32 }),
/// The underlying SDL GPU texture.
gpu_texture: *sdl.SDL_GPUTexture,

const Font = @This();

/// Returns a font with the given texture and character index.
///
/// The font depends on the given texture, which should not be freed until after
/// this font is freed.
pub fn init(gpa: std.mem.Allocator, texture: Texture, line_height: f32, chars: []const []const u8) !Font {
    _ = gpa;
    _ = texture;
    _ = line_height;
    _ = chars;
    @panic("TODO");
    // var char_info: @FieldType(Font, "char_info") = .init(gpa);
    // errdefer char_info.deinit();

    // try char_info.ensureTotalCapacity(chars.len);

    // for (chars, 0..) |row, x|
    //     for (row, 0..) |char, y|
    //         char_info.putAssumeCapacity(char, .{
    //             .x = @floatFromInt(x),
    //             .y = @floatFromInt(y),
    //             .w = @floatFromInt(line_height),
    //         });

    // return .{
    //     .char_rects = char_info,
    //     ._gpu_texture = texture._gpu_texture,
    // };
}

/// Destroys the font.
///
/// The font should not be used after calling this function.
pub fn deinit(self: Font) void {
    self.char_rects.deinit();
    sdl.SDL_ReleaseGPUTexture(self._gpu_texture);
}

/// Draws a string with the font.
pub fn draw(self: Font, renderer: *Renderer, text: []const u8, pos: math.Vec2(f32), color: math.Color(f32)) !void {
    try renderer.command_queue.push(.{ .switch_texture = self._gpu_texture });

    var x: u8 = pos.x;

    for (text) |char| {
        const info = self.char_info.get(char) orelse continue;

        try renderer.fillUvRect(.{
            .x = x,
            .y = pos.y,
            .w = info.w,
            .h = self.line_height,
        }, .{
            .x = info.x / self.size.x,
            .y = info.y / self.size.y,
            .w = (info.x + info.w) / self.size.x,
            .h = (info.y + self.line_height) / self.size.y,
        }, color);

        x += info.w;
    }
}
