//! Wraps a track and allows editing its structure.

const std = @import("std");
const Track = @import("../../synth/Track.zig");
const TrackBuffers = @import("TrackBuffers.zig");

const TrackEdit = @This();

/// A track backed by `buffers`.
track: Track,
/// Buffers of track components.
buffers: TrackBuffers,

/// Returns a new track edit.
///
/// The edit is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !TrackEdit {
    const buffers: TrackBuffers = try .init(gpa);
    errdefer buffers.deinit(gpa);

    return .{
        .buffers = buffers,
        .track = buffers.wrap(),
    };
}

/// Frees the track edit.
///
/// The edit should not be used after calling this function.
pub fn deinit(self: *TrackEdit, gpa: std.mem.Allocator) void {
    self.buffers.deinit(gpa);
    self.* = undefined;
}

/// Returns a copy of the track edit.
///
/// The copy is owned by the caller and should be freed by calling `deinit`.
pub fn clone(self: TrackEdit, gpa: std.mem.Allocator) !TrackEdit {
    _ = self;
    _ = gpa;
    @panic("TODO");
}

/// Inserts the given channel into the track, with the given index.
///
/// Allocates memory if necessary.
pub fn insertChannel(self: *TrackEdit, gpa: std.mem.Allocator, channel: Track.Channel, index: usize) !u8 {
    if (self.track.channels.len >= self.buffers.channel_buf.len)
        try self.buffers.reserveChannels(gpa, 1, 16);
    self.track.channels.ptr = self.buffers.channel_buf.ptr;

    self.insertChannelAssumeCapacity(channel, index);
}

/// Inserts the given channel into the track, with the given index.
///
/// Assumes the buffers have enough space to hold the channel.
pub fn insertChannelAssumeCapacity(self: *TrackEdit, channel: Track.Channel, index: usize) void {
    sliceInsert(Track.Channel, self.track.channels, channel, index);
}

/// Removes the channel with the given index.
///
/// Returns the removed channel.
pub fn removeChannel(self: *TrackEdit, index: usize) Track.Channel {
    return sliceRemove(Track.Channel, self.track.channels, index);
}

/// Inserts the given section into the channel with the given index.
///
/// Returns the index of the section.
///
/// Allocates memory if necessary.
pub fn insertSection(self: *TrackEdit, gpa: std.mem.Allocator, channel_index: usize, section: Track.Section) !usize {
    if (self.track.channels[channel_index].sections.len >= self.buffers.section_bufs[channel_index].len)
        try self.buffers.reserveSections(gpa, channel_index, 16);

    return self.insertSectionAssumeCapacity(channel_index, section);
}

/// Inserts the given section into the channel with the given index.
///
/// Returns the index of the section.
///
/// Assumes the buffers have enough space to hold the section.
pub fn insertSectionAssumeCapacity(self: *TrackEdit, channel_index: usize, section: Track.Section) usize {
    const i = blk: for (self.track.channels[channel_index].sections, 0..) |track_section, i|
        if (track_section.interval.first_tick >= section.interval.first_tick)
            break :blk i;

    sliceInsert(Track.Section, self.track.channels[channel_index].sections, section, i);
    return i;
}

/// Removes the section with the given indices.
///
/// Returns the removed section.
pub fn removeSection(self: *TrackEdit, channel_index: usize, section_index: usize) Track.Section {
    return sliceRemove(Track.Section, self.track.channels[channel_index].sections, section_index);
}

/// Inserts the given note into the pattern with the given index.
///
/// Returns the index of the note.
///
/// Allocates memory if necessary.
pub fn insertNote(self: *TrackEdit, gpa: std.mem.Allocator, pattern_index: usize, note: Track.Note) !usize {
    if (self.track.patterns[pattern_index].sections.len >= self.buffers.pattern_buf[pattern_index].len)
        try self.buffers.reserveNotes(gpa, pattern_index, 16);

    return self.insertNoteAssumeCapacity(pattern_index, note);
}

/// Inserts the given note into the pattern with the given index.
///
/// Returns the index of the note.
///
/// Assumes the buffers have enough space to hold the note.
pub fn insertNoteAssumeCapacity(self: *TrackEdit, pattern_index: usize, note: Track.Note) usize {
    const i = blk: for (self.track.patterns[pattern_index].notes, 0..) |track_note, i|
        if (track_note.interval.first_tick >= note.interval.first_tick)
            break :blk i;

    sliceInsert(Track.Section, self.track.patterns[pattern_index].sections, note, i);
    return i;
}

/// Removes the note with the given indices.
///
/// Returns the removed note.
pub fn removeNote(self: *TrackEdit, pattern_index: usize, note_index: usize) Track.Note {
    return sliceRemove(Track.Note, self.track.patterns[pattern_index].notes, note_index);
}

/// Arranges used patterns contiguously in memory.
pub fn compactPatterns(self: *TrackEdit) void {
    _ = self;
    @panic("TODO compactPatterns");
}

// Slice mutation helpers

/// Inserts the given element into the slice, with the given index.
///
/// Assumes the memory backing the slice is of size at least `slice.len + 1`.
fn sliceInsert(comptime T: type, slice: []T, value: T, index: usize) void {
    slice.len += 1;
    @memmove(slice[index + 1 ..], slice[index .. slice.len - 1]);
    slice[index] = value;
}

/// Removes the element with the given index from the slice.
///
/// Returns the removed element.
fn sliceRemove(comptime T: type, slice: []T, index: usize) T {
    const value = slice[index];
    @memmove(slice[index .. slice.len - 1], slice[index + 1 ..]);
    slice.len -= 1;
    return value;
}
