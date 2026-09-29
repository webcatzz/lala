const ActionBus = @import("ActionBus.zig");
const Ctx = @import("../ctx/Ctx.zig");
const Editor = @import("Editor.zig");
const input = @import("../core/input.zig");
const math = @import("../core/math.zig");
const Renderer = @import("../core/render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Timeline = @import("Timeline.zig");
const Track = @import("../../synth/Track.zig");

const PatternEditor = @This();

/// The amount scrolled, relative to the initial position.
scroll_amount: math.Vec2(f32) = .zero,
/// The current selection.
selection: union(enum) {
    /// An empty selection.
    empty,
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
const pitch_height = Renderer.Spritesheet.Sprite.info.get(.piano_key_white).rect.h;
/// The width of piano keys.
const piano_key_width = Renderer.Spritesheet.Sprite.info.get(.piano_key_white).rect.w;
/// The color of white piano keys.
const piano_key_white: math.Color(f32) = .white;
/// The color of black piano keys.
const piano_key_black: math.Color(f32) = .black;
/// The color of the border around piano keys.
const piano_key_border_color: math.Color(f32) = .fromValue(0.75);

/// Updates the pattern editor in response to user input.
pub fn respond(self: *PatternEditor, ctx: *Ctx, event: input.Event, section_coords: ?Timeline.SectionCoords) !void {
    switch (event) {
        .scroll => |scroll_event| {
            self.scroll_amount = self.scroll_amount.add(scroll_event.amount.mul(6))
                .min(.{ .x = tick_width * std.math.maxInt(u16), .y = @as(f32, pitch_height) * std.math.maxInt(u8) })
                .max(.splat(0));
            try ctx.queueRedraw();
        },
        .cursor => |cursor_event| if (section_coords) |coords| {
            if (ctx.input.is_action_active(.pattern_editor_place_note))
                switch (self.selection) {
                    .note_end => |i| {
                        const section = ctx.track.channels[coords.channel_index].sections[coords.section_index];
                        const note = &ctx.track.patterns[section.pattern_index].notes[i];
                        note.interval.last_tick = (@max(note.interval.first_tick, self.tickFromX(cursor_event.pos.x)) / self.tick_snap + 1) * self.tick_snap;
                        ctx.queueRedraw();
                    },
                    else => {},
                };
        },
        .button => if (section_coords) |coords| {
            if (ctx.input.was_action_just_pressed(.pattern_editor_place_note)) {
                const section = ctx.track.channels[coords.channel_index].sections[coords.section_index];
                const cursor_tick = self.tickFromX(ctx.input.cursor_pos.x);
                const cursor_pitch = self.pitchFromY(ctx.input.cursor_pos.y);

                var notes_during_tick = ctx.track.patterns[section.pattern_index]
                    .notesDuringTick(cursor_tick);

                while (notes_during_tick.next()) |note|
                    if (note.pitch == cursor_pitch) {
                        _ = try ctx.do(.{ .remove_note = .{
                            .pattern_index = section.pattern_index,
                            .note_index = notes_during_tick.index - 1,
                        } });
                        ctx.queueRedraw();
                        self.selection = .empty;
                        return;
                    };

                const note_tick = cursor_tick / self.tick_snap * self.tick_snap;

                self.selection = .{
                    .note_end = (try ctx.do(.{ .insert_note = .{
                        .pattern_index = section.pattern_index,
                        .note = .{
                            .interval = .{ .first_tick = note_tick, .last_tick = note_tick + self.tick_snap },
                            .pitch = cursor_pitch,
                        },
                    } })).remove_note.note_index,
                };

                ctx.queueRedraw();
            } else if (ctx.input.was_action_just_released(.pattern_editor_place_note))
                self.selection = .empty;
        },
    }
}

/// Draws the pattern editor.
pub fn draw(self: PatternEditor, renderer: *Renderer, ctx: *const Ctx, section_coords: ?Timeline.SectionCoords) !void {
    const pitch_at_top = self.pitchAtTop();
    // const tick_at_left = self.tickAtLeft();

    // Draws piano keys + lines

    const visible_key_count: usize = @trunc(self.rect.h / pitch_height);

    for (0..visible_key_count) |key_index| {
        const key_pitch: Track.Note.Pitch = @enumFromInt(pitch_at_top -| @as(u8, @truncate(key_index)));
        const key_y = self.yFromPitch(key_pitch);

        try renderer.drawSprite(switch (key_pitch.color()) {
            .white => .piano_key_white,
            .black => .piano_key_black,
        }, .{ .x = self.rect.x, .y = key_y });

        if (key_pitch.class() == .c)
            if (key_pitch.name()) |pitch_name|
                try renderer.print(pitch_name, .{ .x = self.rect.x, .y = key_y }, .black);

        try renderer.drawSpriteStretch(.line, .{
            .x = self.rect.x + piano_key_width,
            .y = key_y,
            .w = self.rect.w - piano_key_width,
            .h = pitch_height,
        });
    }

    // Draws section end line

    const coords = section_coords orelse return;
    const section = ctx.track.channels[coords.channel_index].sections[coords.section_index];
    const pattern = ctx.track.patterns[section.pattern_index];

    try renderer.switchColor(.fromHexRgb(0x302c2e));
    try renderer.drawSpriteStretch(.blank, .{
        .x = self.xFromTick(@intCast(section.interval.duration())),
        .y = self.rect.y,
        .w = 1,
        .h = self.rect.h,
    });
    try renderer.switchColor(.white);

    // Draws notes

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

fn pitchAtTop(self: PatternEditor) u8 {
    return @as(u8, @trunc(self.scroll_amount.y / pitch_height));
}

fn pitchFromY(self: PatternEditor, y: f32) Track.Note.Pitch {
    return @enumFromInt(self.pitchAtTop() -| @as(u8, @trunc((y - self.rect.y) / pitch_height)));
}

fn yFromPitch(self: PatternEditor, p: Track.Note.Pitch) f32 {
    return (@as(f32, @floatFromInt(self.pitchAtTop())) - @as(f32, @floatFromInt(@intFromEnum(p)))) * pitch_height + self.rect.y;
}

fn tickAtLeft(self: PatternEditor) Track.Pattern.Tick {
    return @as(Track.Pattern.Tick, @trunc(self.scroll_amount.x / tick_width));
}

fn tickFromX(self: PatternEditor, x: f32) Track.Pattern.Tick {
    return self.tickAtLeft() + @as(Track.Pattern.Tick, @trunc(@max(0, (x - self.rect.x - piano_key_width) / tick_width)));
}

fn xFromTick(self: PatternEditor, tick: u16) f32 {
    return (@as(f32, @floatFromInt(tick)) - @as(f32, @floatFromInt(self.tickAtLeft()))) * tick_width + self.rect.x + piano_key_width;
}
