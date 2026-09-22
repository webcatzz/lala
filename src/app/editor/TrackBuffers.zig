//! Manages allocation of track components.
//!
//! Components within buffers may not be initialized.

const std = @import("std");
const Track = @import("../../synth/Track.zig");

/// Channels.
channel_buf: []Track.Channel,
/// Sections for each channel.
///
/// Of the same length as `channel_buf`.
section_bufs: [][]Track.Section,
/// Patterns.
pattern_buf: []Track.Pattern,
/// Notes for each pattern.
///
/// Of the same length as `pattern_buf`.
note_bufs: [][]Track.Note,

const TrackBuffers = @This();

/// Allocates and returns track buffers.
///
/// The returned buffers are owned by the caller and should be freed by calling
/// `deinit`.
pub fn init(gpa: std.mem.Allocator) !TrackBuffers {
    const channel_buf = try gpa.alloc(Track.Channel, 32);
    errdefer gpa.free(channel_buf);

    const section_bufs = try gpa.alloc([]Track.Section, 32);
    @memset(section_bufs, &.{});
    errdefer {
        for (section_bufs) |section_buf|
            if (section_buf.len != 0)
                gpa.free(section_buf);
        gpa.free(section_bufs);
    }

    for (section_bufs) |*section_buf|
        section_buf.* = try gpa.alloc(Track.Section, 32);

    const pattern_buf = try gpa.alloc(Track.Pattern, 32);
    errdefer gpa.free(pattern_buf);

    const note_bufs = try gpa.alloc([]Track.Note, 32);
    @memset(note_bufs, &.{});
    errdefer {
        for (note_bufs) |note_buf|
            if (note_buf.len != 0) {
                gpa.free(note_buf);
            };
        gpa.free(section_bufs);
    }

    for (note_bufs) |*note_buf|
        note_buf.* = try gpa.alloc(Track.Note, 32);

    return .{
        .channel_buf = channel_buf,
        .section_bufs = section_bufs,
        .pattern_buf = pattern_buf,
        .note_bufs = note_bufs,
    };
}

/// Frees the track buffers.
///
/// The track buffers should not be used after calling this function.
pub fn deinit(self: TrackBuffers, gpa: std.mem.Allocator) void {
    for (self.section_bufs) |section_buf|
        gpa.free(section_buf);
    gpa.free(self.section_bufs);
    gpa.free(self.channel_buf);
    for (self.note_bufs) |note_buf|
        gpa.free(note_buf);
    gpa.free(self.note_bufs);
    gpa.free(self.pattern_buf);
}

/// Resizes the buffers to hold at the given number of channels.
pub fn setChannelCount(self: *TrackBuffers, gpa: std.mem.Allocator, count: usize, section_count: usize) !void {
    const old_count = self.channel_buf.len;
    for (self.section_bufs[count..old_count]) |section_buf|
        gpa.free(section_buf);

    self.channel_buf = try gpa.realloc(self.channel_buf, count);

    for (self.section_bufs[old_count..count]) |*section_buf|
        section_buf.* = try gpa.alloc(Track.Section, section_count);
}

/// Resizes the buffers to hold at the given number of sections for the given channel.
pub fn setSectionCount(self: *TrackBuffers, gpa: std.mem.Allocator, chan_i: usize, count: usize) !void {
    self.section_bufs[chan_i] = try gpa.realloc(self.section_bufs[chan_i], count);
}

/// Resizes the buffers to hold at the given number of patterns.
pub fn setPatternCount(self: *TrackBuffers, gpa: std.mem.Allocator, count: usize, note_count: usize) !void {
    const old_count = self.pattern_buf.len;
    for (self.note_bufs[count..old_count]) |note_buf|
        gpa.free(note_buf);

    self.pattern_buf = try gpa.realloc(self.pattern_buf, count);

    for (self.note_bufs[old_count..count]) |*note_buf|
        note_buf.* = try gpa.alloc(Track.Note, note_count);
}

/// Resizes the buffers to hold at the given number of notes for the given pattern.
pub fn setNoteCount(self: *TrackBuffers, gpa: std.mem.Allocator, pat_i: usize, count: usize) !void {
    self.note_bufs[pat_i] = try gpa.realloc(self.note_bufs[pat_i], count);
}

/// Ensures there is enough space for the given number of channels.
///
/// Reallocates if there is not enough space.
pub fn reserveChannels(self: *TrackBuffers, gpa: std.mem.Allocator, count: usize, section_count: usize) !void {
    return self.setChannelCount(gpa, growCapacity(Track.Channel, self.channel_buf.len + count), section_count);
}

/// Ensures there is enough space for the given number of sections in the given channel.
///
/// Reallocates if there is not enough space.
pub fn reserveSections(self: *TrackBuffers, gpa: std.mem.Allocator, chan_i: usize, count: usize) !void {
    return self.setSectionCount(gpa, chan_i, growCapacity(Track.Section, self.section_bufs[chan_i].len + count));
}

/// Ensures there is enough space for the given number of patterns.
///
/// Reallocates if there is not enough space.
pub fn reservePatterns(self: *TrackBuffers, gpa: std.mem.Allocator, count: usize, note_count: usize) !void {
    return self.setPatternCount(gpa, growCapacity(Track.Pattern, self.pattern_buf.len + count), note_count);
}

/// Ensures there is enough space for the given number of notes in the given pattern.
///
/// Reallocates if there is not enough space.
pub fn reserveNotes(self: *TrackBuffers, gpa: std.mem.Allocator, pat_i: usize, count: usize) !void {
    return self.setNoteCount(gpa, pat_i, growCapacity(Track.Note, self.note_bufs[pat_i].len + count));
}

/// Returns a capacity larger than `min` that grows super-linearly.
pub fn growCapacity(comptime T: type, min: usize) usize {
    return std.ArrayList(T).growCapacity(min);
}
