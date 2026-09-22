//! Synthesizes audio from track data.

const std = @import("std");
const Track = @import("Track.zig");

/// The synth's current position in the track, in ticks.
tick: Track.Channel.Tick = 0,

/// The number of samples used to represent a duration of one second.
comptime sample_rate: u32 = 44100,
/// The number of sequential samples synthesized since the last resume or seek
/// operation.
samples_synthesized: u64 = 0,
// /// The number of samples left in the current tick.
// samples_left_in_tick: usize,

/// Synthesizers for each channel in the track.
channels: std.ArrayList(Channel),

const Synth = @This();

/// Returns a new synth.
///
/// The synth is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Synth {
    var channels: std.ArrayList(Channel) = try .initCapacity(gpa, 32);
    channels.items.len = channels.capacity;
    @memset(channels.items, .{ .notes = .empty });
    errdefer {
        for (channels.items) |*channel|
            if (channel.notes.capacity != 0)
                channel.notes.deinit(gpa);
        channels.deinit(gpa);
    }

    for (channels.items) |*channel|
        channel.notes = try .initCapacity(gpa, 16);

    return .{
        .channels = channels,
    };
}

/// Frees the synth's resources.
///
/// The synth should not be used after this function is called.
pub fn deinit(self: *Synth, gpa: std.mem.Allocator) void {
    for (self.channels.items) |*channel|
        channel.notes.deinit(gpa);
    self.channels.deinit(gpa);
}

/// Synthesizes audio for the given track into the given output buffer.
///
/// Returns the number of samples generated.
pub fn run(self: *Synth, track: Track, output: []f32) !usize {
    var output_index: u32 = 0;

    self.channels.items.len = @min(track.channels.len, self.channels.capacity);

    while (true) {
        // Grabs slice of output for current tick

        const sample_count = self.sample_rate / track.tempo;
        const next_output_index = output_index + sample_count;
        const output_slice = if (next_output_index < output.len)
            output[output_index..next_output_index]
        else
            break;

        // Synthesizes each channel

        for (self.channels.items, track.channels) |*channel, settings| {
            try channel.update(settings, track.patterns, self.tick);
            channel.synth(self.samples_synthesized, self.sample_rate, output_slice);
        }

        // Advances to next tick

        self.tick += 1;
        output_index = next_output_index;
        self.samples_synthesized += sample_count;
    }

    return output_index;
}

/// Seeks to the given position, in ticks.
pub fn seek(self: *Synth, tick: Track.Channel.Tick) void {
    self.tick = tick;
    self.samples_synthesized = 0;
}

const Channel = struct {
    instrument: Track.Instrument = .{},
    /// Currently active notes.
    notes: std.ArrayList(Note),

    /// Updates the channel for the given playhead position.
    fn update(self: *Channel, settings: Track.Channel, patterns: []const Track.Pattern, tick: Track.Channel.Tick) !void {
        self.instrument = settings.instrument;
        self.notes.clearRetainingCapacity();

        if (settings.pick_section(tick)) |section| {
            var iter = patterns[section.pattern_index]
                .notesDuringTick(@intCast(tick - section.interval.first_tick));
            var i: u8 = 0;
            while (iter.next()) |note_settings| {
                var note: Note = undefined;
                note.update(note_settings);
                try self.notes.appendBounded(note);
                i += 1;
            }
        }
    }

    /// Synthesizes audio for the current tick into the given output buffer.
    fn synth(self: *Channel, sample_offset: usize, sample_rate: u32, output: []f32) void {
        for (self.notes.items) |*note|
            note.synth(self.instrument, sample_offset, sample_rate, output);
    }
};

const Note = struct {
    pitch: Track.Note.Pitch,
    volume: f32 = 1,

    /// Updates the note for the given tick.
    fn update(self: *Note, settings: Track.Note) void {
        self.pitch = settings.pitch;
        self.volume = @as(f32, @floatFromInt(settings.volume)) / 0xf;
    }

    /// Synthesizes audio for the current tick into the given output buffer.
    fn synth(self: *Note, instrument: Track.Instrument, sample_offset: usize, sample_rate: u32, output: []f32) void {
        for (output, 0..) |*sample, i| {
            const phase = @as(f32, @floatFromInt(sample_offset + i)) * self.pitch.freq() / @as(f32, @floatFromInt(sample_rate));
            const phase_fract = phase - @trunc(phase);
            sample.* += instrument.sample(phase_fract) * self.volume;
        }
    }
};
