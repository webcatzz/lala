const Ctx = @import("../ctx/Ctx.zig");
const input = @import("../input.zig");
const math = @import("../util/math.zig");
const pitch = @import("../../synth/pitch.zig");
const Renderer = @import("../render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Timeline = @import("Timeline.zig");
const Track = @import("../../synth/Track.zig");
const Ui = @import("../Ui.zig");

const PianoRoll = @This();

/// The rectangle occupied by the piano roll.
rect: math.Rect(f32) = .zero,
/// The amount scrolled, relative to the initial position.
scroll_amount: math.Vec2(f32) = .zero,

/// The index of the pattern being edited.
pattern_index: ?u8,
/// The current selection.
selection: union(enum) {
    /// An empty selection.
    empty,
    /// A note, represented by the note's index.
    note: u8,
    /// The start of a note, represented by the note's index.
    note_start: u8,
    /// The end of a note, represented by the note's index.
    note_end: u8,
    /// An interval.
    interval: Track.Interval(u16),
} = .empty,

/// The width used to represent a single tick.
tick_width: f32 = 0.33,
/// The tick snapping applied when editing notes.
tick_snap: u16 = 48,

/// The height of a pitch.
const pitch_height = Renderer.Spritesheet.Sprite.piano_key_white.info().rect.h;
/// The width of piano keys.
const piano_key_width = Renderer.Spritesheet.Sprite.piano_key_white.info().rect.w;
/// The color of white piano keys.
const piano_key_white: math.Color(f32) = .white;
/// The color of black piano keys.
const piano_key_black: math.Color(f32) = .black;
/// The color of the border around piano keys.
const piano_key_border_color: math.Color(f32) = .fromValue(0.75);

/// Updates the piano roll in response to user input.
pub fn respond(self: *PianoRoll, ctx: *Ctx, event: input.Event) !void {
    switch (event) {
        .button => if (self.pattern_index) |pattern_index| {
            if (ctx.input.was_action_just_pressed(.piano_roll_place_note)) {
                const tick_offset: Track.Pattern.Tick = @trunc(self.scroll_amount.x / self.tick_width);
                const pitch_offset: u8 = @trunc(self.scroll_amount.y / pitch_height);
                const cursor_tick = tick_offset + tickFromX(ctx.input.cursor_pos.x, self.rect.x + Ui.frame.border.left + piano_key_width, self.tick_width);
                const cursor_pitch = pitch_offset -| pitchFromY(ctx.input.cursor_pos.y, self.rect.y + Ui.frame.border.top);

                var notes_during_tick = ctx.track_edit.track.patterns[pattern_index]
                    .notesDuringTick(cursor_tick);

                while (notes_during_tick.next()) |note|
                    if (note.pitch == cursor_pitch) {
                        _ = try ctx.do(.{ .remove_note = .{
                            .pattern_index = pattern_index,
                            .note_index = notes_during_tick.index - 1,
                        } });
                        ctx.queueRedraw();
                        self.selection = .empty;
                        return;
                    };

                const note_tick = cursor_tick / self.tick_snap * self.tick_snap;

                self.selection = .{
                    .note_end = (try ctx.do(.{ .insert_note = .{
                        .pattern_index = pattern_index,
                        .note = .{
                            .interval = .{ .first_tick = note_tick, .last_tick = note_tick + self.tick_snap },
                            .pitch = cursor_pitch,
                        },
                    } })).remove_note.note_index,
                };

                ctx.queueRedraw();
            } else if (ctx.input.was_action_just_released(.piano_roll_place_note))
                self.selection = .empty;
        },
        .cursor => |cursor_event| if (self.pattern_index) |pattern_index| {
            if (cursor_event.pos.x < self.rect.x + Ui.frame.border.left + piano_key_width) {
                // Piano keyboard
                // TODO
            } else {
                // Note editor
                if (ctx.input.is_action_active(.piano_roll_place_note))
                    switch (self.selection) {
                        .note_end => |i| {
                            const note = &ctx.track_edit.track.patterns[pattern_index].notes[i];
                            const tick_offset: Track.Pattern.Tick = @trunc(self.scroll_amount.x / self.tick_width);
                            note.interval.last_tick = (@max(note.interval.first_tick, tick_offset + tickFromX(cursor_event.pos.x, self.rect.x + Ui.frame.border.left + piano_key_width, self.tick_width)) / self.tick_snap + 1) * self.tick_snap;
                            ctx.queueRedraw();
                        },
                        else => {},
                    };
            }
        },
        .scroll => |scroll_event| {
            self.scroll_amount = .{
                .x = @max(minXScroll(), @min(maxXScroll(self.tick_width), self.scroll_amount.x + scroll_event.amount.x * 6)),
                .y = @max(minYScroll(self.rect.h), @min(maxYScroll(), self.scroll_amount.y + scroll_event.amount.y * 6)),
            };
            ctx.queueRedraw();
        },
    }
}

pub fn layOut(self: *PianoRoll, r: math.Rect(f32)) void {
    self.rect = r;
    self.scroll_amount = .{
        .x = @max(minXScroll(), @min(maxXScroll(self.tick_width), self.scroll_amount.x)),
        .y = @max(minYScroll(self.rect.h), @min(maxYScroll(), self.scroll_amount.y)),
    };
}

/// Draws the piano roll.
pub fn draw(self: PianoRoll, renderer: *Renderer, ctx: Ctx) !void {
    const tick_offset: Track.Pattern.Tick = @trunc(self.scroll_amount.x / self.tick_width);
    const pitch_offset: u8 = @trunc(self.scroll_amount.y / pitch_height);

    try Ui.frame.draw(renderer, self.rect);

    const border = Ui.frame.border;
    const inner_rect = self.rect.grow(.{
        .left = -@as(f32, border.left),
        .right = -@as(f32, border.right),
        .top = -@as(f32, border.top),
        .bottom = -@as(f32, border.bottom),
    });

    try drawPianoKeys(
        renderer,
        pitch_offset,
        inner_rect.x,
        inner_rect.y,
        inner_rect.h,
    );

    const pattern = ctx.track_edit.track.patterns[self.pattern_index orelse return];
    try drawNotes(
        renderer,
        pattern,
        tick_offset,
        self.tick_width,
        pitch_offset,
        .{
            .x = inner_rect.x + piano_key_width,
            .y = inner_rect.y,
            .w = inner_rect.w - piano_key_width - Ui.scrollbar.width,
            .h = inner_rect.h,
        },
    );

    const y_scroll = 1 - (self.scroll_amount.y - minYScroll(self.rect.h)) / (maxYScroll() - minYScroll(self.rect.h));
    try Ui.scrollbar.drawVertical(renderer, y_scroll, .{
        .x = inner_rect.endX() - Ui.scrollbar.width,
        .y = inner_rect.y,
        .w = Ui.scrollbar.width,
        .h = inner_rect.h,
    });
}

/// Draws piano keys in the given area.
fn drawPianoKeys(
    renderer: *Renderer,
    pitch_offset: u8,
    x: f32,
    y: f32,
    h: f32,
) !void {
    const visible_key_count: usize = @trunc(h / pitch_height);

    for (0..visible_key_count) |key_index| {
        const key_pitch = pitch_offset -| @as(u8, @truncate(key_index));
        const key_y = y + yFromPitch(key_pitch, pitch_offset);

        try renderer.drawSprite(switch (pitch.color(key_pitch)) {
            .white => .piano_key_white,
            .black => .piano_key_black,
        }, .{ .x = x, .y = key_y });

        try renderer.switchColor(.black);
        if (pitch.class(key_pitch) == .c)
            if (pitch.name(key_pitch)) |pitch_name|
                try renderer.print(pitch_name, .{ .x = x, .y = key_y });
        try renderer.switchColor(.white);
    }
}

fn drawNotes(
    renderer: *Renderer,
    pattern: Track.Pattern,
    tick_offset: Track.Pattern.Tick,
    tick_width: f32,
    pitch_offset: u8,
    rect: math.Rect(f32),
) !void {
    // TODO causes a segfault outside the current scope for some reason?
    // try renderer.drawSpriteRepeat(.line, .{
    //     .x = self.rect.x + piano_key_width,
    //     .y = self.rect.y,
    //     .w = self.rect.w - piano_key_width,
    //     .h = self.rect.h,
    // });

    // TODO filter out-of-viewport notes
    for (pattern.notes) |note|
        try renderer.drawSprite9Patch(.note, .{
            .x = rect.x + xFromTick(note.interval.first_tick, tick_offset, tick_width),
            .y = rect.y + yFromPitch(note.pitch, pitch_offset),
            .w = @as(f32, @floatFromInt(note.interval.duration())) * tick_width,
            .h = pitch_height - 1,
        });
}

fn pitchFromY(
    y: f32,
    y_offset: f32,
) u8 {
    return @as(u8, @trunc((y - y_offset) / pitch_height));
}

fn yFromPitch(
    p: u8,
    pitch_offset: u8,
) f32 {
    return (@as(f32, @floatFromInt(pitch_offset)) - @as(f32, @floatFromInt(p))) * pitch_height;
}

fn tickAtLeft(
    x_offset: f32,
    tick_width: f32,
) Track.Pattern.Tick {
    return @as(Track.Pattern.Tick, @trunc(x_offset / tick_width));
}

fn tickFromX(
    x: f32,
    x_offset: f32,
    tick_width: f32,
) Track.Pattern.Tick {
    return @as(Track.Pattern.Tick, @trunc(@max(0, (x - x_offset) / tick_width)));
}

fn xFromTick(
    tick: Track.Pattern.Tick,
    tick_offset: Track.Pattern.Tick,
    tick_width: f32,
) f32 {
    return (@as(f32, @floatFromInt(tick)) - @as(f32, @floatFromInt(tick_offset))) * tick_width;
}

fn minXScroll() f32 {
    return 0;
}

fn maxXScroll(tick_width: f32) f32 {
    return tick_width * std.math.maxInt(u16);
}

fn minYScroll(h: f32) f32 {
    return h - pitch_height;
}

fn maxYScroll() f32 {
    return @as(f32, pitch_height) * std.math.maxInt(u8);
}
