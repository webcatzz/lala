const Editor = @import("Editor.zig");
const input = @import("../input.zig");
const math = @import("../math.zig");
const Renderer = @import("../render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Track = @import("../Track.zig");

/// The rectangle occupied by the timeline.
rect: math.Rect(f32) = .zero,
scroll_amount: math.Vec2(f32) = .zero,

selection: ?Selection = null,
is_composing: bool = false,

const Timeline = @This();

const tick_snap = 48;
const tick_width = 1;
const channel_header_width = 160;
const channel_header_background_color = math.Color(f32).fromValue(0.125);
const channel_height = 120;

pub const Selection = struct {
    channel_index: usize,
    section_index: usize,
};

pub fn respond(self: *Timeline, editor: *Editor, event: input.Event, state: input.State) !void {
    if (event == .scroll) {
        self.scroll_amount = self.scroll_amount.add(event.scroll.amount);
        try editor.redraw();
    } else if (event == .cursor and self.is_composing) {
        const selection = self.selection orelse return;
        const section = &editor.track.channels[selection.channel_index].sections[selection.section_index];

        section.interval.last_tick = @max(
            section.interval.first_tick + tick_snap,
            self.tickFromX(state.cursor_pos.x) / tick_snap * tick_snap,
        );
        try editor.redraw();
    } else {
        if (state.was_action_just_pressed(.timeline_place_section)) {
            const channel_index = self.channelIndexAtTop();
            const tick = self.tickFromX(state.cursor_pos.x);

            self.selection = .{
                .channel_index = channel_index,
                .section_index = (try editor.do(.{ .insert_section = .{
                    .channel_index = channel_index,
                    .section = .{
                        .interval = .at(tick),
                        .pattern_index = 0,
                    },
                } })).remove_section.section_index,
            };
            self.is_composing = true;
        } else if (state.was_action_just_released(.timeline_place_section))
            self.is_composing = false;
    }
}

pub fn draw(self: Timeline, editor: *Editor) !void {
    _ = self;
    _ = editor;
    // const renderer = &editor.renderer;

    // const channel_at_top = self.channelIndexAtTop();

    // for (editor.track.channels, channel_at_top..) |channel, channel_index| {
    //     const channel_y = self.yFromChannelIndex(@truncate(channel_index));

    //     if (channel_y < self.rect.y - channel_height) continue;
    //     if (channel_y > self.rect.y + self.rect.h) break;

    //     try renderer.drawSpriteStretch(.blank, .{
    //         .x = self.rect.x,
    //         .y = channel_y,
    //         .w = channel_header_width,
    //         .h = channel_height,
    //     });

    //     for (channel.sections) |section| {
    //         try renderer.drawSprite9Patch(.note, .{
    //             .x = self.rect.x + self.scroll_amount.x + @as(f32, @floatFromInt(section.interval.first_tick)) * tick_width,
    //             .y = channel_y,
    //             .w = @as(f32, @floatFromInt(section.interval.duration())) * tick_width,
    //             .h = channel_height,
    //         }, 1, 1, 1, 1);
    //     }
    // }
}

fn tickAtLeft(self: Timeline) Track.Channel.Tick {
    return @trunc(self.scroll_amount.x / tick_width);
}

fn tickFromX(self: Timeline, x: f32) Track.Channel.Tick {
    return self.tickAtLeft() + @as(Track.Channel.Tick, @trunc(@max(0, x - self.rect.x - channel_header_width) / tick_width));
}

fn xFromTick(self: Timeline, tick: u16) f32 {
    return (@as(f32, @floatFromInt(tick)) - @as(f32, @floatFromInt(self.tickAtLeft()))) * tick_width + self.rect.x + channel_header_width;
}

fn channelIndexAtTop(self: Timeline) u8 {
    return @trunc(self.scroll_amount.y / channel_height);
}

fn channelIndexFromY(self: Timeline, y: f32) u8 {
    return self.channelAtTop() + @as(u8, @trunc((y - self.rect.y) / channel_height));
}

fn yFromChannelIndex(self: Timeline, index: u8) f32 {
    return (@as(f32, @floatFromInt(index)) - @as(f32, @floatFromInt(self.channelIndexAtTop()))) * channel_height + self.rect.y;
}
