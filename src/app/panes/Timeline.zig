const Ctx = @import("../ctx/Ctx.zig");
const input = @import("../input.zig");
const math = @import("../util/math.zig");
const Renderer = @import("../render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Track = @import("../../synth/Track.zig");

const Timeline = @This();

/// The rectangle occupied by the timeline.
rect: math.Rect(f32) = .zero,
/// The amount scrolled, relative to the initial position.
scroll_amount: math.Vec2(f32) = .zero,

/// The current selection in the timeline.
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
    interval: Track.Interval(u64),

    const SectionCoords = struct { channel_index: u8, section_index: u8 };
} = .empty,

const tick_snap = 48;
const channel_header_width = 48;
const channel_header_background_color = math.Color(f32).fromValue(0.125);
const channel_height = 32;

pub fn respond(self: *Timeline, ctx: *Ctx, event: input.Event) !void {
    switch (event) {
        .scroll => |scroll_event| {
            self.scroll_amount = self.scroll_amount.add(scroll_event.amount);
            ctx.queueRedraw();
        },
        .cursor => switch (self.selection) {
            .section_start, .section_end => |selection| {
                const section = &ctx.track_edit.track.channels[selection.channel_index].sections[selection.section_index];
                const tick_offset: u64 = @trunc(self.scroll_amount.x / ctx.config.timeline_tick_width);

                section.interval.last_tick = @max(
                    section.interval.first_tick + tick_snap,
                    (tick_offset + tickFromX(ctx.input.cursor_pos.x, self.rect.x, ctx.config.timeline_tick_width)) / tick_snap * tick_snap,
                );

                ctx.queueRedraw();
            },
            else => {},
        },
        .button => {
            if (ctx.input.was_action_just_pressed(.timeline_place_section)) {
                const tick_offset: Track.Channel.Tick = @trunc(self.scroll_amount.x / ctx.config.timeline_tick_width);
                const channel_offset: u8 = @trunc(self.scroll_amount.y / channel_height);
                const cursor_tick = tick_offset + tickFromX(ctx.input.cursor_pos.x, self.rect.x, ctx.config.timeline_tick_width);
                const cursor_channel_index = channel_offset + channelIndexFromY(ctx.input.cursor_pos.y, self.rect.y);

                self.selection = .{
                    .section_start = .{
                        .channel_index = cursor_channel_index,
                        .section_index = (try ctx.do(.{ .insert_section = .{
                            .channel_index = cursor_channel_index,
                            .section = .{ .interval = .at(cursor_tick), .pattern_index = 0 },
                        } })).remove_section.section_index,
                    },
                };
            } else if (ctx.input.was_action_just_released(.timeline_place_section))
                self.selection = .empty;
        },
    }

    // if (event == .scroll) {
    //     self.scroll_amount = self.scroll_amount.add(event.scroll.amount);
    //     try editor.redraw();
    // } else if (event == .cursor and self.is_composing) {} else {
    //     if (state.was_action_just_pressed(.timeline_place_section)) {
    //         const channel_index = self.channelIndexAtTop();
    //         const tick = self.tickFromX(state.cursor_pos.x);

    //         self.selection = .{
    //             .channel_index = channel_index,
    //             .section_index = (try editor.do(.{ .insert_section = .{
    //                 .channel_index = channel_index,
    //                 .section = .{
    //                     .interval = .at(tick),
    //                     .pattern_index = 0,
    //                 },
    //             } })).remove_section.section_index,
    //         };
    //         self.is_composing = true;
    //     } else if (state.was_action_just_released(.timeline_place_section))
    //         self.is_composing = false;
    // }
}

/// Draws the timeline.
pub fn draw(self: Timeline, renderer: *Renderer, ctx: Ctx) !void {
    const tick_at_left: Track.Channel.Tick = @trunc(self.scroll_amount.x / ctx.config.timeline_tick_width);
    const channel_at_top: u8 = @trunc(self.scroll_amount.y / channel_height);

    for (ctx.track_edit.track.channels, channel_at_top..) |channel, channel_index| {
        const y = yFromChannelIndex(@truncate(channel_index), channel_at_top);
        if (y < self.rect.y - channel_height) continue;
        if (y > self.rect.y + self.rect.h) break;

        try drawChannel(
            renderer,
            channel,
            ctx.track_edit.track.patterns,
            tick_at_left,
            ctx.config.timeline_tick_width,
            .{ .x = self.rect.x, .y = y, .w = self.rect.w, .h = channel_height },
        );
    }
}

/// Draws a channel.
fn drawChannel(
    renderer: *Renderer,
    channel: Track.Channel,
    patterns: []Track.Pattern,
    tick_offset: Track.Channel.Tick,
    tick_width: f32,
    rect: math.Rect(f32),
) !void {
    try renderer.drawSpriteStretch(.blank, .{
        .x = rect.x,
        .y = rect.y,
        .w = channel_header_width,
        .h = rect.h,
    });

    for (channel.sections) |section| {
        try drawSection(renderer, patterns[section.pattern_index], @intCast(section.interval.duration()), .{
            .x = rect.x + xFromTick(section.interval.first_tick, tick_offset, tick_width),
            .y = rect.y,
            .w = @as(f32, @floatFromInt(section.interval.duration())) * tick_width,
            .h = rect.h,
        });
    }
}

/// Draws a section.
fn drawSection(
    renderer: *Renderer,
    pattern: Track.Pattern,
    last_tick: u16,
    rect: math.Rect(f32),
) !void {
    // Draws section frame

    try renderer.drawSprite9Patch(.section, rect);
    try renderer.drawSprite(.section_drag_indicator, .{ .x = rect.x + rect.w / 2, .y = rect.y + 1 });

    // Finds pitch range of section

    if (pattern.notes.len == 0) return;

    var min_pitch = pattern.notes[0].pitch;
    var max_pitch = min_pitch;
    for (pattern.notes[1..]) |note| {
        min_pitch = @min(min_pitch, note.pitch);
        max_pitch = @max(max_pitch, note.pitch);
    }

    // Calculates note dimensions based on pitch range & last tick

    const inner_rect = rect.grow(comptime blk: {
        const border = Renderer.Spritesheet.Sprite.section.info().border;
        break :blk .{
            .left = -@as(f32, border.left) - 1,
            .right = -@as(f32, border.right) - 1,
            .top = -@as(f32, border.top) - 1,
            .bottom = -@as(f32, border.bottom) - 1,
        };
    });

    const section_tick_width = inner_rect.w / last_tick;
    const section_pitch_height = inner_rect.h / (max_pitch - min_pitch + 1);

    // Draws notes

    try renderer.switchColor(.fromHexRgb(0xe6482e));
    for (pattern.notes) |note| {
        if (note.interval.first_tick > last_tick) break;
        const x = note.interval.first_tick * section_tick_width;
        try renderer.drawSpriteStretch(.blank, .{
            .x = inner_rect.x + x,
            .y = inner_rect.y + (max_pitch - note.pitch) * section_pitch_height,
            .w = @min(note.interval.duration() * section_tick_width, inner_rect.w - x),
            .h = section_pitch_height,
        });
    }
    try renderer.switchColor(.white);
}

/// Returns the tick at the given *x*-position.
fn tickFromX(
    x: f32,
    x_offset: f32,
    tick_width: f32,
) Track.Channel.Tick {
    return @as(Track.Channel.Tick, @trunc(@max(0, x - x_offset - channel_header_width) / tick_width));
}

/// Returns the *x*-position of the given tick.
fn xFromTick(
    tick: Track.Channel.Tick,
    tick_offset: Track.Channel.Tick,
    tick_width: f32,
) f32 {
    return (@as(f32, @floatFromInt(tick)) - @as(f32, @floatFromInt(tick_offset))) * tick_width + channel_header_width;
}

/// Returns the index of the channel at the given *y*-position.
fn channelIndexFromY(
    y: f32,
    y_offset: f32,
) u8 {
    return @as(u8, @trunc((y - y_offset) / channel_height));
}

/// Returns the *y*-position of the channel with the given index.
fn yFromChannelIndex(
    index: u8,
    channel_offset: u8,
) f32 {
    return (@as(f32, @floatFromInt(index)) - @as(f32, @floatFromInt(channel_offset))) * channel_height;
}
