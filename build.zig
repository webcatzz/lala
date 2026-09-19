const builtin = @import("builtin");
const std = @import("std");
const Io = std.Io;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl = b.addTranslateC(.{
        .root_source_file = .{ .cwd_relative = "/opt/homebrew/opt/sdl3/include/SDL3/SDL.h" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sdl.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/sdl3/include/" });

    const zlib = b.addTranslateC(.{
        .root_source_file = .{ .cwd_relative = "/opt/homebrew/opt/zlib/include/zlib.h" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sdl.addIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/zlib/include/" });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sdl", .module = sdl.createModule() },
            .{ .name = "zlib", .module = zlib.createModule() },
        },
    });
    mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/sdl3/lib/" });
    mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/zlib/lib/" });
    mod.linkSystemLibrary("SDL3", .{});
    mod.linkSystemLibrary("z", .{});

    const exe = b.addExecutable(.{ .name = "chipr", .root_module = mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // run_cmd.step.dependOn(build_res(b));
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = mod })).step);

    // Docs

    const doc_step = b.step("doc", "Generate documentation");
    doc_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc",
    }).step);

    // Sprites

    const spr_cmd = b.addRunArtifact(b.addExecutable(.{
        .name = "build_sprites",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build_sprites.zig"),
            .target = target,
            .optimize = optimize,
        }),
    }));

    const spr_step = b.step("sprites", "Reload sprite data into file");
    spr_step.dependOn(&spr_cmd.step);
}

// /// Returns a step to build project resources.
// pub fn build_res(b: *std.Build) *std.Build.Step {
//     const res_install = b.addInstallDirectory(.{
//         .source_dir = b.path("res"),
//         .install_dir = .bin,
//         .install_subdir = "res",
//         .exclude_extensions = &.{ ".DS_Store", ".hlsl" },
//     });

//     const shader_ext = switch (b.standardTargetOptions(.{}).result.os.tag) {
//         .macos => "msl",
//         .linux => "spv",
//     };

//     const transpile_vert_shader_cmd = b.addSystemCommand(&.{
//         "shadercross",
//         "res/shader.hlsl",
//         "-t",
//         "vertex",
//         "-e",
//         "VertMain",
//         "-o",
//         b.pathJoin(&.{ b.getInstallPath(.bin, "res"), "shader." ++ shader_ext }),
//     });
//     transpile_vert_shader_cmd.step.dependOn(&res_install.step);

//     const transpile_frag_shader_cmd = b.addSystemCommand(&.{
//         "shadercross",
//         "res/shader.hlsl",
//         "-t",
//         "fragment",
//         "-e",
//         "FragMain",
//         "-o",
//         b.pathJoin(&.{ b.getInstallPath(.bin, "res"), "shader." ++ shader_ext }),
//     });
//     transpile_frag_shader_cmd.step.dependOn(&res_install.step);

//     const res_step = b.step("res", "Install resources");
//     res_step.dependOn(&res_install.step);
//     res_step.dependOn(&transpile_vert_shader_cmd.step);
//     res_step.dependOn(&transpile_frag_shader_cmd.step);
//     return res_step;
// }
