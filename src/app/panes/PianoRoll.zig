const Ctx = @import("../ctx/Ctx.zig");
const input = @import("../input.zig");
const math = @import("../util/math.zig");
const pitch = @import("../../synth/pitch.zig");
const Renderer = @import("../render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Timeline = @import("Timeline.zig");
const Track = @import("../../synth/Track.zig");

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

tick_snap: u16 = 48,

/// The width of a tick.
const tick_width = 0.33;
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
        .scroll => |scroll_event| {
            self.scroll_amount = self.scroll_amount.add(scroll_event.amount.mul(6))
                .min(.{ .x = tick_width * std.math.maxInt(u16), .y = @as(f32, pitch_height) * std.math.maxInt(u8) })
                .max(.splat(0));
            ctx.queueRedraw();
        },
        .cursor => |cursor_event| if (self.pattern_index) |pattern_index| {
            if (ctx.input.is_action_active(.piano_roll_place_note))
                switch (self.selection) {
                    .note_end => |i| {
                        const note = &ctx.track_edit.track.patterns[pattern_index].notes[i];
                        note.interval.last_tick = (@max(note.interval.first_tick, self.tickFromX(cursor_event.pos.x)) / self.tick_snap + 1) * self.tick_snap;
                        ctx.queueRedraw();
                    },
                    else => {},
                };
        },
        .button => if (self.pattern_index) |pattern_index| {
            if (ctx.input.was_action_just_pressed(.piano_roll_place_note)) {
                const cursor_tick = self.tickFromX(ctx.input.cursor_pos.x);
                const cursor_pitch = self.pitchFromY(ctx.input.cursor_pos.y);

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
    }
}

/// Draws the piano roll.
pub fn draw(self: PianoRoll, renderer: *Renderer, ctx: Ctx) !void {
    const pitch_at_top = self.pitchAtTop();
    // const tick_at_left = self.tickAtLeft();

    // Draws piano keys

    const visible_key_count: usize = @trunc(self.rect.h / pitch_height);

    for (0..visible_key_count) |key_index| {
        const key_pitch = pitch_at_top -| @as(u8, @truncate(key_index));
        const key_y = self.yFromPitch(key_pitch);

        try renderer.drawSprite(switch (pitch.color(key_pitch)) {
            .white => .piano_key_white,
            .black => .piano_key_black,
        }, .{ .x = self.rect.x, .y = key_y });

        if (pitch.class(key_pitch) == .c)
            if (pitch.name(key_pitch)) |pitch_name|
                try renderer.print(pitch_name, .{ .x = self.rect.x, .y = key_y }, .black);
    }

    // Draws lines

    // TODO causes a segfault outside the current scope for some reason?
    // try renderer.drawSpriteRepeat(.line, .{
    //     .x = self.rect.x + piano_key_width,
    //     .y = self.rect.y,
    //     .w = self.rect.w - piano_key_width,
    //     .h = self.rect.h,
    // });

    // Draws notes

    const pattern = ctx.track_edit.track.patterns[self.pattern_index orelse return];

    for (pattern.notes) |note| {
        // TODO filter out-of-viewport notes
        try renderer.drawSprite9Patch(.note, .{
            .x = self.xFromTick(note.interval.first_tick),
            .y = self.yFromPitch(note.pitch),
            .w = @as(f32, @floatFromInt(note.interval.duration())) * tick_width,
            .h = pitch_height - 1,
        });
    }
}

fn pitchAtTop(self: PianoRoll) u8 {
    return @as(u8, @trunc(self.scroll_amount.y / pitch_height));
}

fn pitchFromY(self: PianoRoll, y: f32) u8 {
    return self.pitchAtTop() -| @as(u8, @trunc((y - self.rect.y) / pitch_height));
}

fn yFromPitch(self: PianoRoll, p: u8) f32 {
    return (@as(f32, @floatFromInt(self.pitchAtTop())) - @as(f32, @floatFromInt(p))) * pitch_height + self.rect.y;
}

fn tickAtLeft(self: PianoRoll) Track.Pattern.Tick {
    return @as(Track.Pattern.Tick, @trunc(self.scroll_amount.x / tick_width));
}

fn tickFromX(self: PianoRoll, x: f32) Track.Pattern.Tick {
    return self.tickAtLeft() + @as(Track.Pattern.Tick, @trunc(@max(0, (x - self.rect.x - piano_key_width) / tick_width)));
}

fn xFromTick(self: PianoRoll, tick: u16) f32 {
    return (@as(f32, @floatFromInt(tick)) - @as(f32, @floatFromInt(self.tickAtLeft()))) * tick_width + self.rect.x + piano_key_width;
}
