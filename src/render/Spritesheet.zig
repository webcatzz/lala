//! A spritesheet containing all possible sprites the editor might need.
//!
//! Its footprint is small enough that we can load it up front and use it all
//! throughout the lifetime of the program, rather than loading and unloading
//! smaller sprites and requiring additional GPU binding state changes.
//!
//! Individual sprites are identified by their `Sprite` variant, which provides
//! functions for accessing their spritesheet coordinates.

const err = @import("../err.zig");
const math = @import("../math.zig");
const Renderer = @import("Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const zlib = @import("zlib");

/// The SDL GPU texture used to store the spritesheet.
_gpu_texture: *sdl.SDL_GPUTexture,

const Spritesheet = @This();

/// The width of the spritesheet, in pixels.
pub const width = 256;
/// The height of the spritesheet, in pixels.
pub const height = 256;
/// The total area of the spritesheet, in pixels.
pub const area = width * height;

/// A sprite in the spritesheet.
pub const Sprite = enum(u8) {
    /// A blank white sprite.
    blank,

    note,
    line,
    line_hover,
    piano_key_white,
    piano_key_black,
    section,

    // Characters in the "pebble font". Characters in base ASCII are represented
    // with their value in base ASCII plus the value of `pebble_base`. Other
    // characters' values are unspecified.

    /// The '!' character in the "pebble" font.
    pebble_exclamation_mark = pebble_base + 1,
    /// The '"' character in the "pebble" font.
    pebble_quote = pebble_base + 2,
    /// The '#' character in the "pebble" font.
    pebble_hash = pebble_base + 3,
    /// The '$' character in the "pebble" font.
    pebble_dollar = pebble_base + 4,
    /// The '%' character in the "pebble" font.
    pebble_percent = pebble_base + 5,
    /// The '&' character in the "pebble" font.
    pebble_ampersand = pebble_base + 6,
    /// The ''' character in the "pebble" font.
    pebble_apostrophe = pebble_base + 7,
    /// The '(' character in the "pebble" font.
    pebble_lparen = pebble_base + 8,
    /// The ')' character in the "pebble" font.
    pebble_rparen = pebble_base + 9,
    /// The '*' character in the "pebble" font.
    pebble_star = pebble_base + 10,
    /// The '+' character in the "pebble" font.
    pebble_plus = pebble_base + 11,
    /// The ',' character in the "pebble" font.
    pebble_comma = pebble_base + 12,
    /// The '-' character in the "pebble" font.
    pebble_hyphen = pebble_base + 13,
    /// The '.' character in the "pebble" font.
    pebble_period = pebble_base + 14,
    /// The '/' character in the "pebble" font.
    pebble_slash = pebble_base + 15,
    /// The '0' character in the "pebble" font.
    pebble_0 = pebble_base + 16,
    /// The '1' character in the "pebble" font.
    pebble_1 = pebble_base + 17,
    /// The '2' character in the "pebble" font.
    pebble_2 = pebble_base + 18,
    /// The '3' character in the "pebble" font.
    pebble_3 = pebble_base + 19,
    /// The '4' character in the "pebble" font.
    pebble_4 = pebble_base + 20,
    /// The '5' character in the "pebble" font.
    pebble_5 = pebble_base + 21,
    /// The '6' character in the "pebble" font.
    pebble_6 = pebble_base + 22,
    /// The '7' character in the "pebble" font.
    pebble_7 = pebble_base + 23,
    /// The '8' character in the "pebble" font.
    pebble_8 = pebble_base + 24,
    /// The '9' character in the "pebble" font.
    pebble_9 = pebble_base + 25,
    /// The ':' character in the "pebble" font.
    pebble_colon = pebble_base + 26,
    /// The ';' character in the "pebble" font.
    pebble_semicolon = pebble_base + 27,
    /// The '<' character in the "pebble" font.
    pebble_lt = pebble_base + 28,
    /// The '=' character in the "pebble" font.
    pebble_eq = pebble_base + 29,
    /// The '>' character in the "pebble" font.
    pebble_gt = pebble_base + 30,
    /// The '?' character in the "pebble" font.
    pebble_question_mark = pebble_base + 31,
    /// The '@' character in the "pebble" font.
    pebble_at = pebble_base + 32,
    /// The 'a' character in the "pebble" font.
    pebble_a = pebble_base + 33,
    /// The 'b' character in the "pebble" font.
    pebble_b = pebble_base + 34,
    /// The 'c' character in the "pebble" font.
    pebble_c = pebble_base + 35,
    /// The 'd' character in the "pebble" font.
    pebble_d = pebble_base + 36,
    /// The 'e' character in the "pebble" font.
    pebble_e = pebble_base + 37,
    /// The 'f' character in the "pebble" font.
    pebble_f = pebble_base + 38,
    /// The 'g' character in the "pebble" font.
    pebble_g = pebble_base + 39,
    /// The 'h' character in the "pebble" font.
    pebble_h = pebble_base + 40,
    /// The 'i' character in the "pebble" font.
    pebble_i = pebble_base + 41,
    /// The 'j' character in the "pebble" font.
    pebble_j = pebble_base + 42,
    /// The 'k' character in the "pebble" font.
    pebble_k = pebble_base + 43,
    /// The 'l' character in the "pebble" font.
    pebble_l = pebble_base + 44,
    /// The 'm' character in the "pebble" font.
    pebble_m = pebble_base + 45,
    /// The 'n' character in the "pebble" font.
    pebble_n = pebble_base + 46,
    /// The 'o' character in the "pebble" font.
    pebble_o = pebble_base + 47,
    /// The 'p' character in the "pebble" font.
    pebble_p = pebble_base + 48,
    /// The 'q' character in the "pebble" font.
    pebble_q = pebble_base + 49,
    /// The 'r' character in the "pebble" font.
    pebble_r = pebble_base + 50,
    /// The 's' character in the "pebble" font.
    pebble_s = pebble_base + 51,
    /// The 't' character in the "pebble" font.
    pebble_t = pebble_base + 52,
    /// The 'u' character in the "pebble" font.
    pebble_u = pebble_base + 53,
    /// The 'v' character in the "pebble" font.
    pebble_v = pebble_base + 54,
    /// The 'w' character in the "pebble" font.
    pebble_w = pebble_base + 55,
    /// The 'x' character in the "pebble" font.
    pebble_x = pebble_base + 56,
    /// The 'y' character in the "pebble" font.
    pebble_y = pebble_base + 57,
    /// The 'z' character in the "pebble" font.
    pebble_z = pebble_base + 58,
    /// The '[' character in the "pebble" font.
    pebble_lbracket = pebble_base + 59,
    /// The '\' character in the "pebble" font.
    pebble_backslash = pebble_base + 60,
    /// The ']' character in the "pebble" font.
    pebble_rbracket = pebble_base + 61,
    /// The '^' character in the "pebble" font.
    pebble_caret = pebble_base + 62,
    /// The '_' character in the "pebble" font.
    pebble_underscore = pebble_base + 63,
    /// The '`' character in the "pebble" font.
    pebble_backtick = pebble_base + 64,
    /// The '{' character in the "pebble" font.
    pebble_lbrace = pebble_base + 91,
    /// The '|' character in the "pebble" font.
    pebble_pipe = pebble_base + 92,
    /// The '}' character in the "pebble" font.
    pebble_rbrace = pebble_base + 93,
    /// The '~' character in the "pebble" font.
    pebble_tilde = pebble_base + 94,

    /// Sprite information.
    pub const Info = struct {
        /// The region occupied by the sprite, in pixels.
        rect: math.Rect(u8),

        /// Returns the rectangle occupied by the given sprite, in pixels.
        pub fn pixel_rect(self: Info) math.Rect(u8) {
            return self.rect;
        }

        /// Returns the region occupied by the given sprite, in pixels.
        pub fn pixel_region(self: Info) math.Rect(u8) {
            return .{
                .left = self.x,
                .top = self.y,
                .right = self.x + self.w,
                .bottom = self.y + self.h,
            };
        }
    };

    /// Information for each sprite.
    pub const info: std.EnumArray(Sprite, Info) = .init(@import("sprites.zon"));

    /// The starting value from which printable base ASCII "pebble" characters
    /// (codes 32 through 127) are enumerated.
    const pebble_base = 64;
    const pebble_rect_x = 160;
    const pebble_rect_y = 0;

    /// Returns the rectangle occupied by the sprite.
    pub fn rect(self: Sprite) math.Rect(u8) {
        return info.get(self);
    }

    /// Returns the sprite corresponding to the given character in the "pebble"
    /// font, if any.
    pub fn pebble(char: u8) ?Sprite {
        return @enumFromInt(pebble_base + switch (char) {
            '!'...'`', '{'...'~' => char - 32,
            'a'...'z' => char - 64,
            else => return null,
        });
    }
};

/// Returns the spritesheet.
///
/// The spritesheet is owned by the caller and should be freed by calling
/// `deinit`.
pub fn init(io: std.Io, gpa: std.mem.Allocator, gpu_device: *sdl.SDL_GPUDevice) !Spritesheet {
    const pixel_byte_size = 4;
    const scanline_byte_size = width * pixel_byte_size + 1;

    // Reads PNG

    const file = try std.Io.Dir.cwd().openFile(io, "res/spritesheet.png", .{});
    defer file.close(io);

    var file_buf: [32]u8 = undefined;
    var file_reader = file.reader(io, &file_buf);
    const reader = &file_reader.interface;

    var buf: [32]u8 = undefined;

    // Verifies PNG signature

    try reader.readSliceAll(buf[0..8]);
    if (std.mem.readInt(u64, buf[0..8], .big) != 0x89504e470d0a1a0a)
        return error.InvalidPng;

    // Reads PNG IHDR chunk

    try reader.readSliceAll(buf[0..25]);
    if (std.mem.readInt(u32, buf[0..4], .big) != 13 or
        std.mem.readInt(u32, buf[4..8], .big) != std.mem.readInt(u32, "IHDR", .big)) return error.InvalidPng;

    if (std.mem.readInt(u32, buf[8..12], .big) != width) {
        std.log.err("Spritesheet PNG width should be {}, is {}", .{ width, std.mem.readInt(u32, buf[8..12], .big) });
        return error.UnexpectedPngSize;
    }
    if (std.mem.readInt(u32, buf[12..16], .big) != height) {
        std.log.err("Spritesheet PNG height should be {}, is {}", .{ height, std.mem.readInt(u32, buf[12..16], .big) });
        return error.UnexpectedPngSize;
    }
    if (buf[16] != 8) {
        std.log.err("Spritesheet PNG bit depth should be 8, is {}", .{buf[16]});
        return error.UnsupportedPngBitDepth;
    }
    if (buf[17] != 6) {
        std.log.err("Spritesheet color type should be 6, is {}", .{buf[17]});
        return error.UnsupportedPngColorType;
    }
    if (buf[18] != 0) {
        std.log.err("Spritesheet compression method should be 0, is {}", .{buf[18]});
        return error.UnsupportedPngCompressionMethod;
    }
    if (buf[19] != 0) {
        std.log.err("Spritesheet filter method should be 0, is {}", .{buf[19]});
        return error.UnsupportedPngFilterMethod;
    }
    if (buf[20] != 0) {
        std.log.err("Spritesheet interlace method should be 0, is {}", .{buf[20]});
        return error.UnsupportedPngInterlaceMethod;
    }

    // Reads following PNG chunks

    var compressed_data = try gpa.alloc(u8, 0);
    defer gpa.free(compressed_data);

    while (true) {
        try reader.readSliceAll(buf[0..8]);
        const chunk_len = std.mem.readInt(u32, buf[0..4], .big);
        const chunk_type = std.mem.readInt(u32, buf[4..8], .big);

        switch (chunk_type) {
            std.mem.readInt(u32, "IEND", .big) => break,
            std.mem.readInt(u32, "IDAT", .big) => {
                const old_len = compressed_data.len;
                compressed_data = try gpa.realloc(compressed_data, old_len + chunk_len);
                try reader.readSliceAll(compressed_data[old_len..]);
            },
            else => if (std.ascii.isUpper(buf[4])) {
                std.log.err("Unknown critical PNG chunk: {s}", .{buf[4..8]});
                return error.UnknownCriticalPngChunk;
            } else try reader.discardAll(chunk_len),
        }

        try reader.discardAll(4); // Discards CRC
    }

    // Decompresses image data

    const decompressed_data = try gpa.alloc(u8, scanline_byte_size * height);
    defer gpa.free(decompressed_data);

    var decompressed_data_len: zlib.uLongf = @intCast(decompressed_data.len);

    switch (zlib.uncompress(
        decompressed_data.ptr,
        &decompressed_data_len,
        compressed_data.ptr,
        compressed_data.len,
    )) {
        zlib.Z_OK => {},
        else => |zlib_return_code| {
            std.log.scoped(.zlib).err("returned code {}", .{zlib_return_code});
            return error.Zlib;
        },
    }

    // Reverses per-scanline filters

    for (0..height) |y| {
        const i = y * scanline_byte_size + 1;

        switch (decompressed_data[i - 1]) {
            0 => {},
            // Sub
            1 => for (pixel_byte_size..scanline_byte_size - 1) |x| {
                decompressed_data[i + x] +%=
                    decompressed_data[i + x - pixel_byte_size];
            },
            // Up
            2 => if (y > 0) for (0..scanline_byte_size - 1) |x| {
                decompressed_data[i + x] +%=
                    decompressed_data[i + x - scanline_byte_size];
            },
            // Average
            3 => for (0..scanline_byte_size - 1) |x| {
                decompressed_data[i + x] +%=
                    ((if (x == 0) 0 else decompressed_data[i + x - pixel_byte_size]) +
                        (if (y == 0) 0 else decompressed_data[i + x - scanline_byte_size])) / 2;
            },
            // Paeth
            4 => for (0..scanline_byte_size - 1) |x| {
                decompressed_data[i + x] +%= paethPredictor(
                    if (x == 0) 0 else decompressed_data[i + x - pixel_byte_size],
                    if (y == 0) 0 else decompressed_data[i + x - scanline_byte_size],
                    if (x == 0 or y == 0) 0 else decompressed_data[i + x - scanline_byte_size - pixel_byte_size],
                );
            },

            else => |filter_type| {
                std.log.err("Unsupported PNG scanline filter type: {}", .{filter_type});
                return error.UnsupportedPngScanlineFilterType;
            },
        }
    }

    // Creates GPU texture

    const texture = sdl.SDL_CreateGPUTexture(gpu_device, &.{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = width,
        .height = height,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    }) orelse
        return error.Sdl;
    errdefer sdl.SDL_ReleaseGPUTexture(gpu_device, texture);

    const Pixel = extern struct { r: f32, g: f32, b: f32, a: f32 };

    // Creates transfer buffer

    const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(gpu_device, &.{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = area * @sizeOf(Pixel),
    }) orelse
        return error.Sdl;
    defer sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, transfer_buffer);

    // Maps image data into transfer buffer

    const transfer_ptr: *[area]Pixel = @ptrCast(@alignCast(
        sdl.SDL_MapGPUTransferBuffer(gpu_device, transfer_buffer, false) orelse
            return error.Sdl,
    ));

    for (transfer_ptr, 0..) |*pixel, i|
        pixel.* = .{
            .r = @as(f32, @floatFromInt(decompressed_data[i / width + i * 4 + 1])) / 255,
            .g = @as(f32, @floatFromInt(decompressed_data[i / width + i * 4 + 2])) / 255,
            .b = @as(f32, @floatFromInt(decompressed_data[i / width + i * 4 + 3])) / 255,
            .a = @as(f32, @floatFromInt(decompressed_data[i / width + i * 4 + 4])) / 255,
        };

    sdl.SDL_UnmapGPUTransferBuffer(gpu_device, transfer_buffer);

    // Uploads image data to GPU

    const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device) orelse
        return error.Sdl;
    const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse unreachable;

    sdl.SDL_UploadToGPUTexture(copy_pass, &.{
        .transfer_buffer = transfer_buffer,
        .pixels_per_row = width,
        .rows_per_layer = height,
    }, &.{
        .texture = texture,
        .w = width,
        .h = height,
        .d = 1,
    }, false);

    sdl.SDL_EndGPUCopyPass(copy_pass);
    if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer))
        return error.Sdl;

    // Returns spritesheet

    return .{ ._gpu_texture = texture };
}

/// Frees the spritesheet.
///
/// The spritesheet should not be used after calling this function.
pub fn deinit(self: *Spritesheet, gpu_device: *sdl.SDL_GPUDevice) void {
    sdl.SDL_ReleaseGPUTexture(gpu_device, self._gpu_texture);
    self.* = undefined;
}

/// Based on [the PNG specification].
///
/// [the PNG specification]:
///     https://www.libpng.org/pub/png/spec/1.2/PNG-Filters.html#Filter-type-4-Paeth
fn paethPredictor(a: u8, b: u8, c: u8) u8 {
    // TODO this math looks simplifiable
    const p = @as(i32, a) + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    return if (pa <= pb and pa <= pc)
        a
    else if (pb <= pc)
        b
    else
        c;
}
