const Ctx = @import("../ctx/Ctx.zig");
const input = @import("../input.zig");
const math = @import("../util/math.zig");
const Renderer = @import("../render/Renderer.zig");

const Timeline = @This();

/// The rectangle occupied by the timeline.
rect: math.Rect(f32) = .zero,

/// Updates the timeline in response to an event.
pub fn respond(_: *Timeline, _: *Ctx, _: input.Event) !void {
    // TODO
}

/// Draws the timeline.
pub fn draw(self: Timeline, renderer: *Renderer, _: Ctx) !void {
    // TODO
    try renderer.switchColor(.blue);
    try renderer.drawSprite9Patch(.debug_border, self.rect);
    try renderer.print("timeline", self.rect.pos().add(.splat(1)));
    try renderer.switchColor(.white);
}
