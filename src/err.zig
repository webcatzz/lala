//! Error logging.

const sdl = @import("sdl");
const std = @import("std");

/// Error information for the latest error.
pub var info: ?union(enum) {
    /// An error occurred on SDL's side.
    sdl,

    unsupported_spritesheet_png_bit_depth: u8,
    unsupported_spritesheet_png_color_type: u8,
    unsupported_spritesheet_png_compression_method: u8,
    unsupported_spritesheet_png_filter_method: u8,
    unsupported_spritesheet_png_interlace_method: u8,

    /// Logs the error with `std.log.err`.
    pub fn log(self: @This()) []const u8 {
        switch (self) {
            .sdl => std.log.err("SDL: {s}", .{sdl.SDL_GetError()}),

            .unsupported_spritesheet_png_bit_depth => |i| std.log.err("Spritesheet PNG bit depth should be 8, is {}", .{i}),
            .unsupported_spritesheet_png_color_type => |i| std.log.err("Spritesheet PNG color type should be 2, is {}", .{i}),
            .unsupported_spritesheet_png_compression_method => |i| std.log.err("Spritesheet PNG compression method should be 0, is {}", .{i}),
            .unsupported_spritesheet_png_filter_method => |i| std.log.err("Spritesheet PNG filter method should be 0, is {}", .{i}),
            .unsupported_spritesheet_png_interlace_method => |i| std.log.err("Spritesheet PNG interlace method should be 0, is {}", .{i}),
        }
    }
} = null;
