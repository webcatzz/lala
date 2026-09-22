const Editor = @import("app/editor/Editor.zig");
const loop = @import("app/core/loop.zig");
const sdl = @import("sdl");
const std = @import("std");

pub const usageStr =
    \\Usage:
    \\    edit [path]        Opens the editor, with a track file loaded if given.
    \\    play <path>        Plays the track in the given file.
;

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();

    _ = args.skip();

    (blk: {
        if (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "edit"))
                break :blk loop.run(Editor, init)
            else if (std.mem.eql(u8, arg, "play"))
                break :blk error.Todo;

            std.log.err("Unknown command\n{s}", .{usageStr});
            break :blk error.UnknownCommand;
        } else {
            std.log.err("Provide command\n{s}", .{usageStr});
            break :blk error.MissingCommand;
        }
    }) catch |err| {
        if (err == error.Sdl)
            std.log.scoped(.sdl).err("{s}", .{sdl.SDL_GetError()});
        return err;
    };
}
