//! A spritesheet containing all possible sprites the editor might need.
//!
//! Its footprint is small enough that we can load it up front and use it all
//! throughout the lifetime of the program, rather than loading and unloading
//! smaller sprites and requiring additional GPU binding state changes.
//!
//! Individual sprites are identified by a unique `Sprite` variant.

const math = @import("../util/math.zig");
const Renderer = @import("Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const zlib = @import("zlib");

const Spritesheet = @This();

/// The SDL GPU texture used to store the spritesheet.
_gpu_texture: *sdl.SDL_GPUTexture,

/// The width of the spritesheet, in pixels.
pub const width = 255;
/// The height of the spritesheet, in pixels.
pub const height = 255;
/// The total area of the spritesheet, in pixels.
pub const area = width * height;

/// A sprite in the spritesheet.
pub const Sprite = enum(u8) {
    /// A blank white sprite.
    blank,

    // Common UI elements

    frame,
    scroll_thumb,
    scroll_thumb_marks,
    scroll_track,
    scroll_up,
    scroll_down,
    scroll_left,
    scroll_right,
    input_number,
    selection_outline,

    // Piano roll

    piano_key_white,
    piano_key_white_held,
    piano_key_black,
    piano_key_black_held,
    note,
    line,

    // Timeline

    section,
    section_drag_indicator,

    // Sheet music symbols

    sheet_note_empty,
    sheet_note_full,
    sheet_note_stem,
    sheet_note_flag,
    sheet_note_flag_chain,
    sheet_line,

    // Characters in the "pebble" font. Base ASCII characters are represented
    // with their ASCII value plus the value of `pebble_base`.

    /// The '!' character in the "pebble" font.
    pebble_exclamation_mark = pebble_base + 1,
    /// The '"' character in the "pebble" font.
    pebble_quote,
    /// The '#' character in the "pebble" font.
    pebble_hash,
    /// The '$' character in the "pebble" font.
    pebble_dollar,
    /// The '%' character in the "pebble" font.
    pebble_percent,
    /// The '&' character in the "pebble" font.
    pebble_ampersand,
    /// The ''' character in the "pebble" font.
    pebble_apostrophe,
    /// The '(' character in the "pebble" font.
    pebble_lparen,
    /// The ')' character in the "pebble" font.
    pebble_rparen,
    /// The '*' character in the "pebble" font.
    pebble_star,
    /// The '+' character in the "pebble" font.
    pebble_plus,
    /// The ',' character in the "pebble" font.
    pebble_comma,
    /// The '-' character in the "pebble" font.
    pebble_hyphen,
    /// The '.' character in the "pebble" font.
    pebble_period,
    /// The '/' character in the "pebble" font.
    pebble_slash,
    /// The '0' character in the "pebble" font.
    pebble_0,
    /// The '1' character in the "pebble" font.
    pebble_1,
    /// The '2' character in the "pebble" font.
    pebble_2,
    /// The '3' character in the "pebble" font.
    pebble_3,
    /// The '4' character in the "pebble" font.
    pebble_4,
    /// The '5' character in the "pebble" font.
    pebble_5,
    /// The '6' character in the "pebble" font.
    pebble_6,
    /// The '7' character in the "pebble" font.
    pebble_7,
    /// The '8' character in the "pebble" font.
    pebble_8,
    /// The '9' character in the "pebble" font.
    pebble_9,
    /// The ':' character in the "pebble" font.
    pebble_colon,
    /// The ';' character in the "pebble" font.
    pebble_semicolon,
    /// The '<' character in the "pebble" font.
    pebble_lt,
    /// The '=' character in the "pebble" font.
    pebble_eq,
    /// The '>' character in the "pebble" font.
    pebble_gt,
    /// The '?' character in the "pebble" font.
    pebble_question_mark,
    /// The '@' character in the "pebble" font.
    pebble_at,
    /// The 'a' character in the "pebble" font.
    pebble_a,
    /// The 'b' character in the "pebble" font.
    pebble_b,
    /// The 'c' character in the "pebble" font.
    pebble_c,
    /// The 'd' character in the "pebble" font.
    pebble_d,
    /// The 'e' character in the "pebble" font.
    pebble_e,
    /// The 'f' character in the "pebble" font.
    pebble_f,
    /// The 'g' character in the "pebble" font.
    pebble_g,
    /// The 'h' character in the "pebble" font.
    pebble_h,
    /// The 'i' character in the "pebble" font.
    pebble_i,
    /// The 'j' character in the "pebble" font.
    pebble_j,
    /// The 'k' character in the "pebble" font.
    pebble_k,
    /// The 'l' character in the "pebble" font.
    pebble_l,
    /// The 'm' character in the "pebble" font.
    pebble_m,
    /// The 'n' character in the "pebble" font.
    pebble_n,
    /// The 'o' character in the "pebble" font.
    pebble_o,
    /// The 'p' character in the "pebble" font.
    pebble_p,
    /// The 'q' character in the "pebble" font.
    pebble_q,
    /// The 'r' character in the "pebble" font.
    pebble_r,
    /// The 's' character in the "pebble" font.
    pebble_s,
    /// The 't' character in the "pebble" font.
    pebble_t,
    /// The 'u' character in the "pebble" font.
    pebble_u,
    /// The 'v' character in the "pebble" font.
    pebble_v,
    /// The 'w' character in the "pebble" font.
    pebble_w,
    /// The 'x' character in the "pebble" font.
    pebble_x,
    /// The 'y' character in the "pebble" font.
    pebble_y,
    /// The 'z' character in the "pebble" font.
    pebble_z,
    /// The '[' character in the "pebble" font.
    pebble_lbracket,
    /// The '\' character in the "pebble" font.
    pebble_backslash,
    /// The ']' character in the "pebble" font.
    pebble_rbracket,
    /// The '^' character in the "pebble" font.
    pebble_caret,
    /// The '_' character in the "pebble" font.
    pebble_underscore,
    /// The '`' character in the "pebble" font.
    pebble_backtick,
    /// The '{' character in the "pebble" font.
    pebble_lbrace = pebble_base + 91,
    /// The '|' character in the "pebble" font.
    pebble_pipe,
    /// The '}' character in the "pebble" font.
    pebble_rbrace,
    /// The '~' character in the "pebble" font.
    pebble_tilde,

    /// Sprite information.
    const Info = struct {
        /// The rectangle occupied by the sprite, in pixels.
        rect: math.Rect(u8),
        /// The widths of the borders of the sprite.
        ///
        /// This is used for nine-patch sprites. For non-nine-patch sprites, the
        /// border values are undefined.
        border: math.Sides(u8),
    };

    /// Information for each sprite.
    const db: std.EnumArray(Sprite, Info) = .init(@import("sprites.zon"));

    /// The starting value from which printable base ASCII "pebble" characters
    /// (codes 32 through 127) are enumerated.
    const pebble_base = 64;

    /// Returns information for the given sprite.
    pub fn info(self: Sprite) Info {
        return db.get(self);
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
    const bytes_per_pixel = 4;
    const bytes_per_scanline = width * bytes_per_pixel + 1;

    // Reads PNG

    // Based on the PNG specification, version 1.2
    // https://www.libpng.org/pub/png/spec/1.2/PNG-Contents.html

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

    const decompressed_data = try gpa.alloc(u8, bytes_per_scanline * height);
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
        const i = y * bytes_per_scanline + 1;

        switch (decompressed_data[i - 1]) {
            0 => {},
            // Sub
            1 => for (bytes_per_pixel..bytes_per_scanline - 1) |x| {
                decompressed_data[i + x] +%=
                    decompressed_data[i + x - bytes_per_pixel];
            },
            // Up
            2 => if (y > 0) for (0..bytes_per_scanline - 1) |x| {
                decompressed_data[i + x] +%=
                    decompressed_data[i + x - bytes_per_scanline];
            },
            // Average
            3 => for (0..bytes_per_scanline - 1) |x| {
                decompressed_data[i + x] +%=
                    ((if (x < bytes_per_pixel) 0 else decompressed_data[i + x - bytes_per_pixel]) +
                        (if (y == 0) 0 else decompressed_data[i + x - bytes_per_scanline])) / 2;
            },
            // Paeth
            4 => for (0..bytes_per_scanline - 1) |x| {
                const a = if (x < bytes_per_pixel) 0 else decompressed_data[i + x - bytes_per_pixel];
                const b = if (y == 0) 0 else decompressed_data[i + x - bytes_per_scanline];
                const c = if (x < bytes_per_pixel or y == 0) 0 else decompressed_data[i + x - bytes_per_scanline - bytes_per_pixel];

                const p = @as(i32, a) + b - c;
                const pa = @abs(p - a);
                const pb = @abs(p - b);
                const pc = @abs(p - c);

                decompressed_data[i + x] +%= if (pa <= pb and pa <= pc) a else if (pb <= pc) b else c;
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
