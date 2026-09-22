const std = @import("std");

pub const SpriteInfo = struct {
    name: []const u8,
    x: u8,
    y: u8,
    w: u8,
    h: u8,
    border_left: u8,
    border_right: u8,
    border_top: u8,
    border_bottom: u8,
};

/// Builds sprite data.
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var file_buf: [64]u8 = undefined;

    var sprite_info: std.ArrayList(SpriteInfo) = try .initCapacity(gpa, 8);
    defer {
        for (sprite_info.items) |item|
            gpa.free(item.name);
        sprite_info.deinit(gpa);
    }

    // Reads Aseprite file

    const input_file = try std.Io.Dir.cwd().openFile(io, "res/spritesheet.aseprite", .{});
    defer input_file.close(io);

    var input_file_reader = input_file.reader(io, &file_buf);
    const reader = &input_file_reader.interface;

    var buf: [32]u8 = undefined;

    // Reads header

    try reader.discardAll(6);
    try reader.readSliceAll(buf[0..2]);
    const frame_count = std.mem.readInt(u16, buf[0..2], .little);
    try reader.discardAll(120);

    // Reads frames

    for (0..frame_count) |_| {
        try reader.readSliceAll(buf[0..16]);
        const chunk_count = switch (std.mem.readInt(u32, buf[12..16], .little)) {
            0 => std.mem.readInt(u16, buf[6..8], .little),
            else => |count| count,
        };

        // Reads frame chunks

        for (0..chunk_count) |_| {
            try reader.readSliceAll(buf[0..6]);
            switch (std.mem.readInt(u16, buf[4..6], .little)) {
                // Slice chunk
                0x2022 => {
                    try reader.readSliceAll(buf[0..14]);
                    const slice_key_count = std.mem.readInt(u32, buf[0..4], .little);
                    const slice_key_flags = std.mem.readInt(u32, buf[4..8], .little);
                    const slice_key_name = try gpa.alloc(u8, std.mem.readInt(u16, buf[12..14], .little));
                    errdefer gpa.free(slice_key_name);
                    try reader.readSliceAll(slice_key_name);

                    for (0..slice_key_count) |_| {
                        try reader.discardAll(4);
                        try reader.readSliceAll(buf[0..16]);
                        const slice_x: u8 = @intCast(std.mem.readInt(i32, buf[0..4], .little));
                        const slice_y: u8 = @intCast(std.mem.readInt(i32, buf[4..8], .little));
                        const slice_w: u8 = @intCast(std.mem.readInt(u32, buf[8..12], .little));
                        const slice_h: u8 = @intCast(std.mem.readInt(u32, buf[12..16], .little));

                        var slice_center_x: u8 = 0;
                        var slice_center_y: u8 = 0;
                        var slice_center_w: u8 = slice_w;
                        var slice_center_h: u8 = slice_h;
                        if (slice_key_flags & 0b1 != 0) {
                            try reader.readSliceAll(buf[0..16]);
                            slice_center_x = @intCast(std.mem.readInt(i32, buf[0..4], .little));
                            slice_center_y = @intCast(std.mem.readInt(i32, buf[4..8], .little));
                            slice_center_w = @intCast(std.mem.readInt(u32, buf[8..12], .little));
                            slice_center_h = @intCast(std.mem.readInt(u32, buf[12..16], .little));
                        }

                        if (slice_key_flags & 0b10 != 0)
                            try reader.discardAll(8);

                        try sprite_info.append(gpa, .{
                            .name = slice_key_name,
                            .x = slice_x,
                            .y = slice_y,
                            .w = slice_w,
                            .h = slice_h,
                            .border_left = slice_center_x,
                            .border_right = slice_w - (slice_center_x + slice_center_w),
                            .border_top = slice_center_y,
                            .border_bottom = slice_h - (slice_center_y + slice_center_h),
                        });
                    }
                },
                // Other chunks
                else => {
                    const chunk_size = std.mem.readInt(u32, buf[0..4], .little);
                    try reader.discardAll(chunk_size - 6);
                },
            }
        }
    }

    // Sorts info

    const sort = struct {
        fn is_lt(_: void, a: SpriteInfo, b: SpriteInfo) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    };

    std.sort.block(SpriteInfo, sprite_info.items, {}, sort.is_lt);

    // Opens output file

    const output_file = try std.Io.Dir.cwd().createFile(io, "src/render/sprites.zon", .{});
    defer output_file.close(io);

    var output_file_writer = output_file.writer(io, &file_buf);
    const writer = &output_file_writer.interface;

    // Writes zon

    try writer.writeAll(".{\n");

    for (sprite_info.items) |item|
        try writer.print(
            \\    .{s} = .{{
            \\        .rect = .{{ .x = {}, .y = {}, .w = {}, .h = {} }},
            \\        .border = .{{ .left = {}, .right = {}, .top = {}, .bottom = {} }},
            \\    }},
            \\
        , .{ item.name, item.x, item.y, item.w, item.h, item.border_left, item.border_right, item.border_top, item.border_bottom });

    try writer.writeAll("}\n");
    try writer.flush();

    std.log.info("Wrote sprites", .{});
}
