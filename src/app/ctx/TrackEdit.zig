//! Wraps a track and allows editing its structure.
//!
//! The same memory allocator should be used all throughout the track edit's
//! lifetime, and if any method requiring a memory allocator is called, the track
//! edit should be freed by calling `deinit`.

const sparse_list = @import("../util/sparse_list.zig");
const std = @import("std");
const Track = @import("../../synth/Track.zig");

const TrackEdit = @This();

/// A track backed by `buffers`.
track: Track = .{},

/// Channel buffers.
_channel_buf: []Track.Channel = &.{},
/// Section buffers for each channel.
///
/// Of the same length as `channel_buf`.
_section_bufs: [][]Track.Section = &.{},
/// Pattern buffers.
_patterns: sparse_list.SparseList(Track.Pattern) = .empty,
/// Note buffers for each pattern.
///
/// Of the same length as `pattern_buf`.
_note_bufs: [][]Track.Note = &.{},

/// Options for inserting a channel.
pub const ChannelOptions = struct {
    instrument: Track.Instrument = .{},
};

/// Frees the track edit.
///
/// The edit should not be used after calling this function.
pub fn deinit(self: *TrackEdit, gpa: std.mem.Allocator) void {
    for (self._section_bufs) |section_buf|
        gpa.free(section_buf);
    gpa.free(self._section_bufs);
    gpa.free(self._channel_buf);
    for (self._note_bufs) |note_buf|
        gpa.free(note_buf);
    gpa.free(self._note_bufs);
    self._patterns.deinit(gpa);
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
pub fn insertChannel(self: *TrackEdit, gpa: std.mem.Allocator, options: ChannelOptions, index: usize) !void {
    if (self.track.channels.len >= self._channel_buf.len) {
        const old_cap = self._channel_buf.len;
        const new_cap = growCapacity(Track.Channel, self._channel_buf.len + 1);

        self._channel_buf = try gpa.realloc(self._channel_buf, new_cap);
        @memset(self._channel_buf[old_cap..new_cap], undefined);
        self.track.channels.ptr = self._channel_buf.ptr;

        self._section_bufs = try gpa.realloc(self._section_bufs, new_cap);
        @memset(self._section_bufs[old_cap..new_cap], &.{});
    }

    self.insertChannelAssumeCapacity(options, index);
}

/// Inserts the given channel into the track, with the given index.
///
/// Assumes the buffers have enough space to hold the channel.
pub fn insertChannelAssumeCapacity(self: *TrackEdit, options: ChannelOptions, index: usize) void {
    sliceInsert(Track.Channel, &self.track.channels, .{
        .instrument = options.instrument,
        .sections = self._section_bufs[index][0..0],
    }, index);
}

/// Removes the channel with the given index.
///
/// Returns the removed channel.
pub fn removeChannel(self: *TrackEdit, index: usize) Track.Channel {
    return sliceRemove(Track.Channel, &self.track.channels, index);
}

/// Inserts the given section into the channel with the given index.
///
/// Returns the index of the section.
///
/// Allocates memory if necessary.
pub fn insertSection(self: *TrackEdit, gpa: std.mem.Allocator, channel_index: usize, section: Track.Section) !usize {
    if (self.track.channels[channel_index].sections.len >= self._section_bufs[channel_index].len) {
        const old_cap = self._section_bufs[channel_index].len;
        const new_cap = growCapacity(Track.Section, self._section_bufs[channel_index].len + 1);

        self._section_bufs[channel_index] = try gpa.realloc(self._section_bufs[channel_index], new_cap);
        @memset(self._section_bufs[channel_index][old_cap..new_cap], undefined);
        self.track.channels[channel_index].sections.ptr = self._section_bufs[channel_index].ptr;
    }

    return self.insertSectionAssumeCapacity(channel_index, section);
}

/// Inserts the given section into the channel with the given index.
///
/// Returns the index of the section.
///
/// Assumes the buffers have enough space to hold the section.
pub fn insertSectionAssumeCapacity(self: *TrackEdit, channel_index: usize, section: Track.Section) usize {
    const i: usize = blk: {
        for (self.track.channels[channel_index].sections, 0..) |track_section, i|
            if (track_section.interval.first_tick >= section.interval.first_tick)
                break :blk i;
        break :blk self.track.channels[channel_index].sections.len;
    };

    sliceInsert(Track.Section, &self.track.channels[channel_index].sections, section, i);
    return i;
}

/// Removes the section with the given indices.
///
/// Returns the removed section.
pub fn removeSection(self: *TrackEdit, channel_index: usize, section_index: usize) Track.Section {
    return sliceRemove(Track.Section, &self.track.channels[channel_index].sections, section_index);
}

/// Inserts a pattern into the track and returns its index.
///
/// Allocates memory if necessary.
pub fn insertPattern(self: *TrackEdit, gpa: std.mem.Allocator) !usize {
    const i = if (self._patterns.firstUninit()) |i| i else blk: {
        const old_cap = self._patterns.items.len;
        const i = old_cap + 1;
        const new_cap = growCapacity(Track.Pattern, i);

        try self._patterns.setCapacity(gpa, new_cap);
        self.track.patterns = self._patterns.items;

        self._note_bufs = try gpa.realloc(self._note_bufs, new_cap);
        @memset(self._note_bufs[old_cap..new_cap], &.{});

        break :blk i;
    };

    self._patterns.set(i, .{
        .notes = self._note_bufs[i][0..0],
    });
    return i;
}

/// Inserts the given note into the pattern with the given index.
///
/// Returns the index of the note.
///
/// Allocates memory if necessary.
pub fn insertNote(self: *TrackEdit, gpa: std.mem.Allocator, pattern_index: usize, note: Track.Note) !usize {
    if (self.track.patterns[pattern_index].notes.len >= self._note_bufs[pattern_index].len) {
        const old_cap = self._note_bufs[pattern_index].len;
        const new_cap = growCapacity(Track.Note, self._note_bufs[pattern_index].len + 1);

        self._note_bufs[pattern_index] = try gpa.realloc(self._note_bufs[pattern_index], new_cap);
        @memset(self._note_bufs[pattern_index][old_cap..new_cap], undefined);
        self.track.patterns[pattern_index].notes.ptr = self._note_bufs[pattern_index].ptr;
    }

    return self.insertNoteAssumeCapacity(pattern_index, note);
}

/// Inserts the given note into the pattern with the given index.
///
/// Returns the index of the note.
///
/// Assumes the buffers have enough space to hold the note.
pub fn insertNoteAssumeCapacity(self: *TrackEdit, pattern_index: usize, note: Track.Note) usize {
    const i = blk: {
        for (self.track.patterns[pattern_index].notes, 0..) |track_note, i|
            if (track_note.interval.first_tick >= note.interval.first_tick)
                break :blk i;
        break :blk self.track.patterns[pattern_index].notes.len;
    };

    sliceInsert(Track.Note, &self.track.patterns[pattern_index].notes, note, i);
    return i;
}

/// Removes the note with the given indices.
///
/// Returns the removed note.
pub fn removeNote(self: *TrackEdit, pattern_index: usize, note_index: usize) Track.Note {
    return sliceRemove(Track.Note, &self.track.patterns[pattern_index].notes, note_index);
}

/// Arranges used patterns contiguously in memory.
pub fn compactPatterns(self: *TrackEdit) void {
    _ = self;
    @panic("TODO compactPatterns");
}

/// Returns a capacity larger than `min` that grows super-linearly.
fn growCapacity(comptime T: type, min: usize) usize {
    return std.ArrayList(T).growCapacity(min);
}

/// Inserts the given element into the slice, with the given index.
///
/// Assumes the memory backing the slice is of size at least `slice.len + 1`.
fn sliceInsert(comptime T: type, slice: *[]T, value: T, index: usize) void {
    slice.len += 1;
    @memmove(slice.*[index + 1 ..], slice.*[index .. slice.len - 1]);
    slice.*[index] = value;
}

/// Removes the element with the given index from the slice.
///
/// Returns the removed element.
fn sliceRemove(comptime T: type, slice: *[]T, index: usize) T {
    const value = slice.*[index];
    @memmove(slice.*[index .. slice.len - 1], slice.*[index + 1 ..]);
    slice.len -= 1;
    return value;
}

test insertChannel {
    var track_edit: TrackEdit = .{};
    defer track_edit.deinit(std.testing.allocator);

    try track_edit.insertChannel(std.testing.allocator, .{}, 0);
}

test insertSection {
    var track_edit: TrackEdit = .{};
    defer track_edit.deinit(std.testing.allocator);

    try track_edit.insertChannel(std.testing.allocator, .{}, 0);
    _ = try track_edit.insertSection(std.testing.allocator, 0, undefined);
}

test insertPattern {
    var track_edit: TrackEdit = .{};
    defer track_edit.deinit(std.testing.allocator);

    _ = try track_edit.insertPattern(std.testing.allocator);
}

test insertNote {
    var track_edit: TrackEdit = .{};
    defer track_edit.deinit(std.testing.allocator);

    const pattern_index = try track_edit.insertPattern(std.testing.allocator);
    _ = try track_edit.insertNote(std.testing.allocator, pattern_index, undefined);
}

test deinit {
    var track_edit: TrackEdit = .{};
    defer track_edit.deinit(std.testing.allocator);

    const pattern_index = try track_edit.insertPattern(std.testing.allocator);
    _ = try track_edit.insertNote(std.testing.allocator, pattern_index, undefined);

    try track_edit.insertChannel(std.testing.allocator, .{}, 0);
    _ = try track_edit.insertSection(std.testing.allocator, 0, undefined);
}
