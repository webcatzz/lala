const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const steps: [2][]const []const u8 = .{
        &.{
            "shadercross",
            "res/shaders/shader.hlsl",
            "-t",
            "vertex",
            "-e",
            "VertMain",
            "-o",
            "res/shaders/vert.msl",
        },
        &.{
            "shadercross",
            "res/shaders/shader.hlsl",
            "-t",
            "fragment",
            "-e",
            "FragMain",
            "-o",
            "res/shaders/frag.msl",
        },
    };

    for (steps) |args| {
        const result = try std.process.run(init.gpa, init.io, .{
            .argv = args,
        });
        init.gpa.free(result.stdout);
        init.gpa.free(result.stderr);
    }
}
