const Ctx = @import("ctx/Ctx.zig");
const input = @import("input.zig");
const Renderer = @import("render/Renderer.zig");
const sokol = @import("sokol");
const std = @import("std");

const App = @This();

/// App state.
ctx: *Ctx,
/// The renderer used to display the app.
_renderer: Renderer,

/// The scale applied when rendering.
pub const render_scale = 3;

/// Returns the app.
///
/// The app is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator, io: std.Io) !App {
    var renderer: Renderer = try .init(gpa);
    errdefer renderer.deinit();

    const ctx = try gpa.create(Ctx);
    errdefer gpa.destroy(ctx);

    ctx.* = try .init(gpa, io);
    errdefer ctx.deinit();

    return .{
        .ctx = ctx,
        ._renderer = renderer,
    };
}

/// Frees the app.
///
/// The app should not be used after calling this function.
pub fn deinit(self: *App) void {
    var ctx = self.ctx.*;
    ctx.gpa.destroy(self.ctx);
    ctx.deinit();

    self._renderer.deinit();
    self.* = undefined;
}

/// Updates app state.
pub fn iter(self: *App) !void {
    if (self.ctx.should_redraw) {
        self.ctx.should_redraw = false;
        self._renderer.clear();

        const scale = sokol.app.dpiScale();
        try self._renderer.switchScale(
            1 / @as(f32, @floatFromInt(sokol.app.width())) * scale * render_scale,
            1 / @as(f32, @floatFromInt(sokol.app.height())) * scale * render_scale,
        );

        try self.ctx.redraw(&self._renderer);

        try self._renderer.render(self._window);
    }
}

/// Updates app state in response to user input.
pub fn respond(self: *App, comptime event_type: input.Type, event: input.Event(event_type)) !void {
    return self.ctx.respond(event_type, event);
}
