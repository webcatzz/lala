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
    pitch: u8,
    /// The volume multiplier applied to the note.
    volume: u4 = 0xf,
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
