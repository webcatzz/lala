const Ctx = @import("../ctx/Ctx.zig");
const input = @import("../input.zig");
const math = @import("../util/math.zig");
const Renderer = @import("../render/Renderer.zig");
const Track = @import("../../synth/Track.zig");
const Ui = @import("../Ui.zig");

const Timeline = @This();

/// The amount scrolled, relative to the initial position.
scroll_amount: math.Vec2(f32) = .zero,

/// The current selection.
selection: union(enum) {
    /// An empty selection.
    empty,
    /// A section, represented by the section's coordinates.
    section: SectionCoords,
    /// The start of a section, represented by the section's coordinates.
    section_start: SectionCoords,
    /// The end of a section, represented by the section's coordinates.
    section_end: SectionCoords,
    /// An interval.
    interval: Track.Interval(u16),

    const SectionCoords = struct { channel_index: u8, section_index: u8 };
} = .empty,

/// The width used to represent a single tick.
tick_width: f32 = 0.33,
/// The tick snapping applied when editing sections.
tick_snap: u16 = 48,

/// The height of a channel.
const channel_height = 32;
/// The width of a channel control panel.
const channel_panel_width = 32;

/// Updates the timeline in response to an event.
pub fn respond(self: *Timeline, ctx: *Ctx, id: Ui.Id, comptime event_type: input.Type, event: input.Event(event_type)) !void {
    _ = self;
    _ = ctx;
    _ = id;
    _ = event;
}

/// Draws the timeline.
pub fn draw(self: Timeline, renderer: *Renderer, ctx: Ctx, rect: math.Rect(f32)) Renderer.DrawError!void {
    try Ui.frame.draw(renderer, rect, "timeline");

    const inner_rect = rect.grow(.{
        .left = -@as(f32, Ui.frame.border.left),
        .right = -@as(f32, Ui.frame.border.right),
        .top = -@as(f32, Ui.frame.border.top),
        .bottom = -@as(f32, Ui.frame.border.bottom),
    });

    const min_channel_index: u8 = @trunc(self.scroll_amount.y / channel_height);
    const max_channel_index: u8 = @min(min_channel_index + @as(u8, @trunc(inner_rect.h / channel_height)), @as(u8, @intCast(ctx.track_edit.track.channels.len)));
    for (min_channel_index..max_channel_index) |channel_index| {
        const channel_y: f32 = @as(u8, @truncate(channel_index)) * channel_height;

        try drawPanel(
            renderer,
            .{ .x = inner_rect.x, .y = inner_rect.y + channel_y },
        );
        try drawSections(
            renderer,
            .{
                .x = inner_rect.x + channel_panel_width,
                .y = inner_rect.y + channel_y,
                .w = inner_rect.w - channel_panel_width,
                .h = channel_height,
            },
            ctx.track_edit.track.channels[channel_index].sections,
            ctx.track_edit.track.patterns,
            self.tick_width,
        );
    }
}

fn drawPanel(
    renderer: *Renderer,
    pos: math.Vec2(f32),
) !void {
    try Ui.flipswitch.draw(renderer, pos, false, .icon_volume_off, .icon_volume_on);
    try Ui.flipswitch.draw(renderer, .{ .x = pos.x + Ui.flipswitch.width + 1, .y = pos.y }, false, .icon_volume_off, .icon_volume_on);
}

fn drawSections(
    renderer: *Renderer,
    rect: math.Rect(f32),
    sections: []const Track.Section,
    patterns: []const Track.Pattern,
    tick_width: f32,
) !void {
    for (sections) |section|
        try drawSection(
            renderer,
            .{
                .x = rect.x + @as(f32, @floatFromInt(section.interval.first_tick)) * tick_width,
                .y = rect.y,
                .w = @as(f32, @floatFromInt(section.interval.duration())) * tick_width,
                .h = rect.h,
            },
            patterns[section.pattern_index],
            @intCast(section.interval.duration()),
        );
}

fn drawSection(
    renderer: *Renderer,
    rect: math.Rect(f32),
    pattern: Track.Pattern,
    last_tick: Track.Pattern.Tick,
) !void {
    try renderer.drawSprite9Patch(.section, rect);

    if (pattern.notes.len == 0) return;

    const border = Renderer.Spritesheet.Sprite.section.info().border;
    const inner_rect: math.Rect(f32) = .{
        .x = rect.x + border.left,
        .y = rect.y + border.top,
        .w = rect.w - border.left - border.right,
        .h = rect.h - border.top - border.bottom,
    };

    var min_pitch = pattern.notes[0].pitch;
    var max_pitch = min_pitch;
    for (pattern.notes[1..]) |note| {
        min_pitch = @min(min_pitch, note.pitch);
        max_pitch = @max(max_pitch, note.pitch);
    }

    const tick_width = inner_rect.w / last_tick;
    const pitch_height = inner_rect.h / (max_pitch - min_pitch + 1);
    for (pattern.notes) |note|
        if (note.interval.first_tick <= last_tick)
            try renderer.drawSpriteStretch(.blank, .{
                .x = inner_rect.x + note.interval.first_tick * tick_width,
                .y = inner_rect.y + (max_pitch - note.pitch) * pitch_height,
                .w = @min(note.interval.duration(), last_tick - note.interval.first_tick) * tick_width,
                .h = pitch_height,
            });
}

fn channelIndexFromY(y: f32) u8 {
    return @trunc(y / channel_height);
}

fn yFromChannelIndex(channel_index: u8) f32 {
    return channel_index * channel_height;
}

fn tickFromX(x: f32, tick_width: f32) Track.Channel.Tick {
    return @trunc(x / tick_width);
}

fn xFromTick(tick: Track.Channel.Tick, tick_width: f32) f32 {
    return @as(f32, @floatFromInt(tick)) * tick_width;
}
