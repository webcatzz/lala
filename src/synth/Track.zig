//! Track data.

const chip = @import("chip.zig");
const std = @import("std");

/// The tempo of the track, in ticks-per-second.
tempo: u16 = 450,
/// The channels in the track.
channels: []Channel,
/// The patterns in the track.
patterns: []Pattern,

const Track = @This();

pub const Channel = struct {
    /// The instrument used to play notes in the channel.
    instrument: Instrument = .{},
    /// The spans of patterns in the channel.
    sections: []Section,

    /// The unsigned integer type used to represent ticks within channels.
    pub const Tick = u64;

    /// Returns the section during the given tick, if any.
    pub fn pick_section(self: Channel, tick: Tick) ?Section {
        for (self.sections) |section|
            if (section.interval.includes(tick))
                return section;
        return null;
    }
};

pub const Section = struct {
    interval: Interval(Channel.Tick),
    pattern_index: u8,
};

/// A collection of notes.
///
/// Patterns have no inherent duration or position in the track; they are
/// referenced by channel sections which do.
pub const Pattern = struct {
    /// The notes in the pattern.
    ///
    /// Assumed to be sorted by their first tick.
    notes: []Note,

    /// The unsigned integer type used to represent ticks within patterns.
    pub const Tick = u16;

    /// Returns the index the given note should be inserted into a pattenr note list.
    pub fn findNoteIndex(note: Note, notes: []Note) usize {
        for (notes, 0..) |other_note, i|
            if (other_note.interval.first_tick > note.interval.first_tick)
                return i;
        return notes.len;
    }

    /// Returns an iterator over the notes during the given tick.
    ///
    /// The pattern notes should not be modified while the iterator is being used.
    pub fn notesDuringTick(self: Pattern, tick: Tick) struct {
        notes: []const Note,
        tick: u16,
        index: u8 = 0,

        pub fn next(iter: *@This()) ?Note {
            while (iter.index < iter.notes.len) {
                const note = iter.notes[iter.index];
                iter.index += 1;
                if (note.interval.includes(iter.tick))
                    return note;
            }
            return null;
        }
    } {
        return .{ .notes = self.notes, .tick = tick };
    }
};

pub const Note = struct {
    /// The interval in which the note is played.
    interval: Interval(Pattern.Tick),
    /// The MIDI pitch of the note.
    pitch: Pitch,
    /// The volume multiplier applied to the note.
    volume: u4 = 0xf,

    /// An unsigned integer representing a pitch.
    ///
    /// Values follow the MIDI standard.
    pub const Pitch = enum(u8) {
        c0 = 12,
        c0_sharp = 13,
        d0 = 14,
        d0_sharp = 15,
        e0 = 16,
        f0 = 17,
        f0_sharp = 18,
        g0 = 19,
        g0_sharp = 20,
        a0 = 21,
        a0_sharp = 22,
        b0 = 23,
        c1 = 24,
        c1_sharp = 25,
        d1 = 26,
        d1_sharp = 27,
        e1 = 28,
        f1 = 29,
        f1_sharp = 30,
        g1 = 31,
        g1_sharp = 32,
        a1 = 33,
        a1_sharp = 34,
        b1 = 35,
        c2 = 36,
        c2_sharp = 37,
        d2 = 38,
        d2_sharp = 39,
        e2 = 40,
        f2 = 41,
        f2_sharp = 42,
        g2 = 43,
        g2_sharp = 44,
        a2 = 45,
        a2_sharp = 46,
        b2 = 47,
        c3 = 48,
        c3_sharp = 49,
        d3 = 50,
        d3_sharp = 51,
        e3 = 52,
        f3 = 53,
        f3_sharp = 54,
        g3 = 55,
        g3_sharp = 56,
        a3 = 57,
        a3_sharp = 58,
        b3 = 59,
        c4 = 60,
        c4_sharp = 61,
        d4 = 62,
        d4_sharp = 63,
        e4 = 64,
        f4 = 65,
        f4_sharp = 66,
        g4 = 67,
        g4_sharp = 68,
        a4 = 69,
        a4_sharp = 70,
        b4 = 71,
        c5 = 72,
        c5_sharp = 73,
        d5 = 74,
        d5_sharp = 75,
        e5 = 76,
        f5 = 77,
        f5_sharp = 78,
        g5 = 79,
        g5_sharp = 80,
        a5 = 81,
        a5_sharp = 82,
        b5 = 83,
        c6 = 84,
        c6_sharp = 85,
        d6 = 86,
        d6_sharp = 87,
        e6 = 88,
        f6 = 89,
        f6_sharp = 90,
        g6 = 91,
        g6_sharp = 92,
        a6 = 93,
        a6_sharp = 94,
        b6 = 95,
        c7 = 96,
        c7_sharp = 97,
        d7 = 98,
        d7_sharp = 99,
        e7 = 100,
        f7 = 101,
        f7_sharp = 102,
        g7 = 103,
        g7_sharp = 104,
        a7 = 105,
        a7_sharp = 106,
        b7 = 107,
        c8 = 108,
        c8_sharp = 109,
        d8 = 110,
        d8_sharp = 111,
        e8 = 112,
        f8 = 113,
        f8_sharp = 114,
        g8 = 115,
        g8_sharp = 116,
        a8 = 117,
        a8_sharp = 118,
        b8 = 119,
        c9 = 120,
        c9_sharp = 121,
        d9 = 122,
        d9_sharp = 123,
        e9 = 124,
        f9 = 125,
        f9_sharp = 126,
        g9 = 127,
        _,

        /// Converts from pitch to frequency.
        pub fn freq(pitch: Pitch) f32 {
            return 440.0 * @exp2((@as(f32, @floatFromInt(@intFromEnum(pitch))) - 69.0) / 12.0);
        }

        /// Returns the octave the pitch belongs to.
        pub fn octave(pitch: Pitch) u8 {
            return @intFromEnum(pitch) / 12;
        }

        /// Returns the pitch class the pitch belongs to.
        pub fn class(pitch: Pitch) enum { c, c_sharp, d, d_sharp, e, f, f_sharp, g, g_sharp, a, a_sharp, b } {
            return @enumFromInt(@intFromEnum(pitch) % 12);
        }

        /// Returns the color of the piano key corresponding to the given pitch.
        pub fn color(pitch: Pitch) enum { white, black } {
            return switch (@intFromEnum(pitch) % 12) {
                1, 3, 6, 8, 10 => .black,
                else => .white,
            };
        }

        /// Returns a human-readable name for the given pitch.
        pub fn name(pitch: Pitch) ?[]const u8 {
            return switch (pitch) {
                .c0 => "C0",
                .c0_sharp => "C#0",
                .d0 => "D0",
                .d0_sharp => "D#0",
                .e0 => "E0",
                .f0 => "F0",
                .f0_sharp => "F#0",
                .g0 => "G0",
                .g0_sharp => "G#0",
                .a0 => "A0",
                .a0_sharp => "A#0",
                .b0 => "B0",
                .c1 => "C1",
                .c1_sharp => "C#1",
                .d1 => "D1",
                .d1_sharp => "D#1",
                .e1 => "E1",
                .f1 => "F1",
                .f1_sharp => "F#1",
                .g1 => "G1",
                .g1_sharp => "G#1",
                .a1 => "A1",
                .a1_sharp => "A#1",
                .b1 => "B1",
                .c2 => "C2",
                .c2_sharp => "C#2",
                .d2 => "D2",
                .d2_sharp => "D#2",
                .e2 => "E2",
                .f2 => "F2",
                .f2_sharp => "F#2",
                .g2 => "G2",
                .g2_sharp => "G#2",
                .a2 => "A2",
                .a2_sharp => "A#2",
                .b2 => "B2",
                .c3 => "C3",
                .c3_sharp => "C#3",
                .d3 => "D3",
                .d3_sharp => "D#3",
                .e3 => "E3",
                .f3 => "F3",
                .f3_sharp => "F#3",
                .g3 => "G3",
                .g3_sharp => "G#3",
                .a3 => "A3",
                .a3_sharp => "A#3",
                .b3 => "B3",
                .c4 => "C4",
                .c4_sharp => "C#4",
                .d4 => "D4",
                .d4_sharp => "D#4",
                .e4 => "E4",
                .f4 => "F4",
                .f4_sharp => "F#4",
                .g4 => "G4",
                .g4_sharp => "G#4",
                .a4 => "A4",
                .a4_sharp => "A#4",
                .b4 => "B4",
                .c5 => "C5",
                .c5_sharp => "C#5",
                .d5 => "D5",
                .d5_sharp => "D#5",
                .e5 => "E5",
                .f5 => "F5",
                .f5_sharp => "F#5",
                .g5 => "G5",
                .g5_sharp => "G#5",
                .a5 => "A5",
                .a5_sharp => "A#5",
                .b5 => "B5",
                .c6 => "C6",
                .c6_sharp => "C#6",
                .d6 => "D6",
                .d6_sharp => "D#6",
                .e6 => "E6",
                .f6 => "F6",
                .f6_sharp => "F#6",
                .g6 => "G6",
                .g6_sharp => "G#6",
                .a6 => "A6",
                .a6_sharp => "A#6",
                .b6 => "B6",
                .c7 => "C7",
                .c7_sharp => "C#7",
                .d7 => "D7",
                .d7_sharp => "D#7",
                .e7 => "E7",
                .f7 => "F7",
                .f7_sharp => "F#7",
                .g7 => "G7",
                .g7_sharp => "G#7",
                .a7 => "A7",
                .a7_sharp => "A#7",
                .b7 => "B7",
                .c8 => "C8",
                .c8_sharp => "C#8",
                .d8 => "D8",
                .d8_sharp => "D#8",
                .e8 => "E8",
                .f8 => "F8",
                .f8_sharp => "F#8",
                .g8 => "G8",
                .g8_sharp => "G#8",
                .a8 => "A8",
                .a8_sharp => "A#8",
                .b8 => "B8",
                .c9 => "C9",
                .c9_sharp => "C#9",
                .d9 => "D9",
                .d9_sharp => "D#9",
                .e9 => "E9",
                .f9 => "F9",
                .f9_sharp => "F#9",
                .g9 => "G9",
                else => null,
            };
        }
    };
};

pub const Instrument = struct {
    base: Base = .{ .chip_pulse = 0.5 },

    pub const Base = union(enum) {
        /// A pulse chip with a variable duty cycle.
        chip_pulse: f32,
        /// A triangle chip.
        chip_triangle,
        /// A sine chip.
        chip_sine,

        /// Samples audio at the given phase.
        pub fn sample(self: Base, phase: f32) f32 {
            return switch (self) {
                .chip_pulse => |duty| chip.pulse(phase, duty),
                .chip_triangle => chip.triangle(phase),
                .chip_sine => chip.sine(phase),
            };
        }
    };

    /// Samples audio at the given phase.
    pub fn sample(self: Instrument, phase: f32) f32 {
        return self.base.sample(phase);
    }
};

/// A interval spanning start and end ticks, with the given tick type.
pub fn Interval(comptime T: type) type {
    return struct {
        /// The first tick included in the interval.
        first_tick: T,
        /// The last tick included in the interval.
        last_tick: T,

        /// Returns an interval including only the given tick.
        pub fn at(tick: T) Interval(T) {
            return .{ .first_tick = tick, .last_tick = tick };
        }

        /// Returns the duration of the interval, in ticks.
        pub fn duration(self: Interval(T)) T {
            return self.last_tick - self.first_tick;
        }

        /// Returns `true` if the interval includes the given tick.
        pub fn includes(self: Interval(T), tick: T) bool {
            return self.first_tick <= tick and self.last_tick >= tick;
        }

        /// Returns `true` if the given intervals overlap.
        pub fn overlaps(self: Interval(T), other: Interval(T)) bool {
            return self.last_tick >= other.first_tick and other.last_tick >= self.first_tick;
        }
    };
}

// Decoding and encoding

/// Single-byte markers used to identify parts of encoded track data.
const Tag = enum(u8) {
    /// Marks the end of track data.
    end,
    /// Followed by a `u16` describing the format of the track data.
    format,
    /// Followed by a `u32` describing the tempo of the track. See
    /// `Track.tempo`.
    tempo,
    data,

    _,
};

/// Encodes the track into bytes.
pub fn encode(track: Track, io: std.Io.Writer) !void {
    _ = track;
    _ = io;
    // const bpm_buf = undefined;

    // try io.writeAll(&@bitCast(.{
    //     @intFromEnum(Tag.bpm),
    // }));
}

/// Decodes a track from bytes.
pub fn decode(io: std.Io.Reader, alloc: std.mem.Allocator) !Track {
    var track = .{};

    _ = alloc;

    while (true) {
        switch (try io.takeEnumNonexhaustive(Tag, .little)) {
            .bpm => {
                var buf: [@sizeOf(f32)]u8 = undefined;
                try io.readSliceAll(&buf);
                track.bpm = std.mem.readInt(f32, buf, .little);
            },
            .end => return track,
        }
    }

    return error.MissingEndTag;
}
