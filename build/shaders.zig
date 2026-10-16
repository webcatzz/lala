const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const steps: [6][]const []const u8 = .{
        &.{ "shadercross", "res/shaders/shader.hlsl", "-t", "vertex", "-e", "VertMain", "-o", "res/shaders/vert.spv" },
        &.{ "shadercross", "res/shaders/shader.hlsl", "-t", "fragment", "-e", "FragMain", "-o", "res/shaders/frag.spv" },
        &.{ "shadercross", "res/shaders/shader.hlsl", "-t", "vertex", "-e", "VertMain", "-o", "res/shaders/vert.msl" },
        &.{ "shadercross", "res/shaders/shader.hlsl", "-t", "fragment", "-e", "FragMain", "-o", "res/shaders/frag.msl" },
        &.{ "shadercross", "res/shaders/shader.hlsl", "-t", "vertex", "-e", "VertMain", "-o", "res/shaders/vert.dxil" },
        &.{ "shadercross", "res/shaders/shader.hlsl", "-t", "fragment", "-e", "FragMain", "-o", "res/shaders/frag.dxil" },
    };

    for (steps) |args| {
        const result = try std.process.run(init.gpa, init.io, .{
            .argv = args,
        });
        init.gpa.free(result.stdout);
        init.gpa.free(result.stderr);
    }
}
