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

    const exe = b.addExecutable(.{
        .name = "chipr",
        .root_module = mod,
    });
    b.installArtifact(exe);

    // `run`

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    run_step.dependOn(&run_cmd.step);

    // `test`

    const test_step = b.step("test", "Run tests");

    const mod_tests = b.addTest(.{ .root_module = mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const run_exe_tests = b.addRunArtifact(exe_tests);

    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // `doc`

    const doc_step = b.step("doc", "Generate documentation");

    const doc_dir = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc",
    });

    doc_step.dependOn(&doc_dir.step);

    // `shaders`

    const shader_step = b.step("shaders", "Transpile shaders");

    const shader_mod = b.createModule(.{
        .root_source_file = b.path("build/shaders.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shader_exe = b.addExecutable(.{
        .name = "build_shaders",
        .root_module = shader_mod,
    });

    const shader_cmd = b.addRunArtifact(shader_exe);

    shader_step.dependOn(&shader_cmd.step);

    // `sprites`

    const spr_step = b.step("sprites", "Reload sprite data into file");

    const spr_mod = b.createModule(.{
        .root_source_file = b.path("build/sprites.zig"),
        .target = target,
        .optimize = optimize,
    });

    const spr_exe = b.addExecutable(.{
        .name = "build_sprites",
        .root_module = spr_mod,
    });

    const spr_cmd = b.addRunArtifact(spr_exe);

    spr_step.dependOn(&spr_cmd.step);
}
