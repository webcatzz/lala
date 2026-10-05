const App = @import("app/App.zig");
const sdl = @import("sdl");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    App.run(init.gpa, init.io) catch |err| {
        if (err == error.Sdl)
            std.log.scoped(.sdl).err("{s}", .{sdl.SDL_GetError()});
        return err;
    };
}

// Test imports

test {
    _ = @import("app/ctx/TrackEdit.zig");
}
