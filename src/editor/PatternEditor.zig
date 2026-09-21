const ActionBus = @import("ActionBus.zig");
const Editor = @import("Editor.zig");
const input = @import("../input.zig");
const math = @import("../math.zig");
const pitch = @import("../pitch.zig");
const Renderer = @import("../render/Renderer.zig");
const sdl = @import("sdl");
const std = @import("std");
const Timeline = @import("Timeline.zig");
const Track = @import("../Track.zig");

/// The rectangle occupied by the editor.
rect: math.Rect(f32) = .zero,
/// The amount scrolled, relative to the initial position.
scroll_amount: math.Vec2(f32) = .zero,

tick_snap: u16 = 48,
active_note_index: ?u8 = null,

const PatternEditor = @This();

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
pub fn respond(self: *PatternEditor, editor: *Editor, event: input.Event, state: input.State) !void {
    if (event == .scroll) {
        self.scroll_amount = .from_simd(@min(
            @max(
                self.scroll_amount.to_simd() + event.scroll.amount.to_simd() * @Vector(2, f32){ 6, 6 },
                @as(@Vector(2, f32), @splat(0)),
            ),
            @Vector(2, f32){ tick_width * std.math.maxInt(u16), @as(f32, pitch_height) * std.math.maxInt(u8) },
        ));
        try editor.redraw();
    } else if (editor.timeline().selection) |selection| {
        if (event == .cursor) {
            if (state.is_button_pressed(.mouse_left)) {
                if (self.active_note_index) |active_note_index| {
                    const section = editor.track.channels[selection.channel_index].sections[selection.section_index];
                    const note = &editor.track.patterns[section.pattern_index].notes[active_note_index];
                    note.interval.last_tick = (@max(note.interval.first_tick, self.tickFromX(event.cursor.pos.x)) / self.tick_snap + 1) * self.tick_snap;
                    try editor.redraw();
                }
            }
        } else if (state.was_action_just_pressed(.pattern_editor_place_note) and state.cursor_pos.x > self.rect.x + piano_key_width) {
            const cursor_tick = self.tickFromX(state.cursor_pos.x);
            const cursor_pitch = self.pitchFromY(state.cursor_pos.y);
            const section = editor.track.channels[selection.channel_index].sections[selection.section_index];

            var notes_during_tick = editor.track.patterns[section.pattern_index]
                .notesDuringTick(cursor_tick);

            while (notes_during_tick.next()) |note|
                if (note.pitch == cursor_pitch) {
                    _ = try editor.do(.{ .remove_note = .{
                        .pattern_index = section.pattern_index,
                        .note_index = notes_during_tick.index - 1,
                    } });
                    try editor.redraw();
                    self.active_note_index = null;
                    return;
                };

            const note_tick = cursor_tick / self.tick_snap * self.tick_snap;

            self.active_note_index = (try editor.do(.{ .insert_note = .{
                .pattern_index = section.pattern_index,
                .note = .{
                    .interval = .{ .first_tick = note_tick, .last_tick = note_tick + self.tick_snap },
                    .pitch = cursor_pitch,
                },
            } })).remove_note.note_index;

            try editor.redraw();
        }
    }
}

/// Draws the pattern editor.
pub fn draw(self: PatternEditor, editor: *Editor) !void {
    const renderer = &editor.renderer;
    const selection = editor.timeline().selection orelse return;
    const section = editor.track.channels[selection.channel_index].sections[selection.section_index];
    const pattern = editor.track.patterns[section.pattern_index];

    const pitch_at_top = self.pitchAtTop();
    // const tick_at_left = self.tickAtLeft();

    // Draws piano keys + lines

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

        try renderer.drawSpriteStretch(.line, .{
            .x = self.rect.x + piano_key_width,
            .y = key_y,
            .w = self.rect.w - piano_key_width,
            .h = pitch_height,
        });
    }

    // Draws notes

    for (pattern.notes) |note| {
        // TODO filter out-of-viewport notes
        try renderer.drawSprite9Patch(.note, .{
            .x = self.xFromTick(note.interval.first_tick),
            .y = self.yFromPitch(note.pitch),
            .w = @as(f32, @floatFromInt(note.interval.duration())) * tick_width,
            .h = pitch_height,
        });
    }
}

fn pitchAtTop(self: PatternEditor) u8 {
    return @as(u8, @trunc(self.scroll_amount.y / pitch_height));
}

fn pitchFromY(self: PatternEditor, y: f32) u8 {
    return self.pitchAtTop() -| @as(u8, @trunc((y - self.rect.y) / pitch_height));
}

fn yFromPitch(self: PatternEditor, p: u8) f32 {
    return (@as(f32, @floatFromInt(self.pitchAtTop())) - @as(f32, @floatFromInt(p))) * pitch_height + self.rect.y;
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
