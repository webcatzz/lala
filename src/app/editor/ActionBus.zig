//! Handles doing and undoing actions.

const std = @import("std");
const Editor = @import("Editor.zig");
const Track = @import("../../synth/Track.zig");

/// A stack of recent actions.
undo_stack: Stack,
/// A stack of recently undone actions.
redo_stack: Stack,

const ActionBus = @This();

/// A discrete action.
pub const Action = union(enum) {
    /// Sets the current track.
    load_track: struct { track: Track },

    /// Inserts a channel into the current track.
    insert_channel: struct { channel_index: u8, channel: Track.Channel },
    /// Removes a channel from the current track.
    remove_channel: struct { channel_index: u8 },

    /// Inserts a section into a channel.
    insert_section: struct { channel_index: u8, section: Track.Section },
    /// Removes a section from a channel.
    remove_section: struct { channel_index: u8, section_index: u8 },

    /// Inserts a note into a pattern.
    insert_note: struct { pattern_index: u8, note: Track.Note },
    /// Removes a note from a pattern.
    remove_note: struct { pattern_index: u8, note_index: u8 },
    /// Sets the interval occupied by a note.
    set_note_interval: struct { pattern_index: u8, note_index: u8, interval: Track.Interval(Track.Pattern.Tick) },
    /// Sets the pitch of a note.
    set_note_pitch: struct { pattern_index: u8, note_index: u8, pitch: Track.Note.Pitch },
    /// Sets the volume of a note.
    set_note_volume: struct { pattern_index: u8, note_index: u8, volume: u4 },

    /// Performs the action in the editor.
    ///
    /// Returns the opposite action which, if performed, will undo the effects
    /// of this call.
    pub fn do(self: Action, editor: *Editor) !Action {
        switch (self) {
            .load_track => |args| {
                const old_track = loadTrack(editor, args.track);
                return .{ .load_track = .{ .track = old_track } };
            },

            .insert_channel => |args| {
                const channel_index = try insertChannel(editor, args.channel_index, args.channel);
                return .{ .remove_channel = .{ .channel_index = channel_index } };
            },
            .remove_channel => |args| {
                const channel = removeChannel(editor, args.channel_index);
                return .{ .insert_channel = .{ .channel_index = args.channel_index, .channel = channel } };
            },

            .insert_section => |args| {
                const section_index = try insertSection(editor, args.channel_index, args.section);
                return .{ .remove_section = .{ .channel_index = args.channel_index, .section_index = section_index } };
            },
            .remove_section => |args| {
                const section = try removeSection(editor, args.channel_index, args.section_index);
                return .{ .insert_section = .{ .channel_index = args.channel_index, .section = section } };
            },

            .insert_note => |args| {
                const note_index = try insertNote(editor, args.pattern_index, args.note);
                return .{ .remove_note = .{ .pattern_index = args.pattern_index, .note_index = note_index } };
            },
            .remove_note => |args| {
                const note = removeNote(editor, args.pattern_index, args.note_index);
                return .{ .insert_note = .{ .pattern_index = args.pattern_index, .note = note } };
            },
            .set_note_interval => |args| {
                const interval = setNoteInterval(editor, args.pattern_index, args.note_index, args.interval);
                return .{ .set_note_interval = .{ .pattern_index = args.pattern_index, .note_index = args.note_index, .interval = interval } };
            },
            .set_note_pitch => |args| {
                const pitch = setNotePitch(editor, args.pattern_index, args.note_index, args.pitch);
                return .{ .set_note_pitch = .{ .pattern_index = args.pattern_index, .note_index = args.note_index, .pitch = pitch } };
            },
            .set_note_volume => |args| {
                const volume = setNoteVolme(editor, args.pattern_index, args.note_index, args.volume);
                return .{ .set_note_volume = .{ .pattern_index = args.pattern_index, .note_index = args.note_index, .volume = volume } };
            },
        }
    }

    /// Loads a track into the editor.
    ///
    /// Returns the previously loaded track.
    pub fn loadTrack(editor: *Editor, track: Track) Track {
        const old_track = editor.track;
        editor.track = track;
        return old_track;
    }

    /// Inserts a new channel into the editor's track.
    ///
    /// Returns the index of the channel.
    pub fn insertChannel(editor: *Editor, channel_index: u8, channel: Track.Channel) !u8 {
        const channels = &editor.track.channels;
        const channel_buf = &editor.track_buffers.channel_buf;

        if (channels.len >= channel_buf.len)
            try editor.track_buffers.reserveChannels(editor.gpa, 1, 16);
        channels.ptr = channel_buf.ptr;

        @memmove(channel_buf.*[channel_index + 1 .. channels.len + 1], channel_buf.*[channel_index..channels.len]);
        channels.len += 1;
        channels.*[editor.track.channels.len - 1] = channel;
        return @intCast(channels.len - 1);
    }

    /// Removes the channel with the given index from the editor's track.
    ///
    /// Returns the channel.
    pub fn removeChannel(editor: *Editor, channel_index: u8) Track.Channel {
        const old_channel = editor.track.channels[editor.track.channels.len - 1];
        editor.track.channels.len -= 1;
        @memmove(editor.track.channels[channel_index..], editor.track.channels[channel_index + 1 ..]);
        return old_channel;
    }

    /// Inserts a section into the channel with the given index.
    ///
    /// Returns the index of the section.
    pub fn insertSection(editor: *Editor, channel_index: u8, section: Track.Section) !u8 {
        const sections = &editor.track.channels[channel_index].sections;
        const section_buf = &editor.track_buffers.section_bufs[channel_index];

        if (sections.len >= section_buf.len)
            try editor.track_buffers.reserveSections(editor.gpa, channel_index, 1);
        sections.ptr = section_buf.ptr;

        const index = sections.len;
        sections.len += 1;
        sections.*[index] = section;
        return @intCast(index);
    }

    /// Removes a section from the channel with the given index.
    ///
    /// Returns the section.
    pub fn removeSection(editor: *Editor, channel_index: u8, section_index: u8) !Track.Section {
        const sections = &editor.track.channels[channel_index].sections;
        @memmove(sections.*[section_index .. sections.len - 1], sections.*[section_index + 1 ..]);
        sections.len -= 1;
        return sections.ptr[sections.len];
    }

    /// Inserts a note into a pattern.
    ///
    /// Returns the index of the note.
    pub fn insertNote(editor: *Editor, pattern_index: u8, note: Track.Note) !u8 {
        const notes = &editor.track.patterns[pattern_index].notes;
        const note_buf = editor.track_buffers.note_bufs[pattern_index];

        if (notes.len >= note_buf.len) {
            try editor.track_buffers.reserveNotes(editor.gpa, pattern_index, 1);
            notes.ptr = note_buf.ptr;
        }

        const note_index = Track.Pattern.findNoteIndex(note, notes.*);

        notes.len += 1;
        @memmove(notes.*[note_index + 1 ..], notes.*[note_index .. notes.len - 1]);
        notes.*[note_index] = note;

        return @intCast(note_index);
    }

    /// Removes a note from a pattern.
    ///
    /// Returns the note.
    pub fn removeNote(editor: *Editor, pattern_index: u8, note_index: u8) Track.Note {
        const notes = &editor.track.patterns[pattern_index].notes;
        @memmove(notes.*[note_index .. notes.len - 1], notes.*[note_index + 1 ..]);
        notes.len -= 1;
        return notes.ptr[notes.len];
    }

    /// Sets the interval occupied by a note.
    ///
    /// Returns the old interval occupied by the note.
    pub fn setNoteInterval(editor: *Editor, pattern_index: u8, note_index: u8, interval: Track.Interval(Track.Pattern.Tick)) Track.Interval(Track.Pattern.Tick) {
        const note = &editor.track.patterns[pattern_index].notes[note_index];
        const old_interval = note.interval;
        note.interval = interval;
        return old_interval;
    }

    /// Sets the pitch of a note.
    ///
    /// Returns the old pitch of the note.
    pub fn setNotePitch(editor: *Editor, pattern_index: u8, note_index: u8, pitch: Track.Note.Pitch) Track.Note.Pitch {
        const note = &editor.track.patterns[pattern_index].notes[note_index];
        const old_pitch = note.pitch;
        note.pitch = pitch;
        return old_pitch;
    }

    /// Sets the pitch of a note.
    ///
    /// Returns the old pitch of the note.
    pub fn setNoteVolme(editor: *Editor, pattern_index: u8, note_index: u8, volume: u4) u4 {
        const note = &editor.track.patterns[pattern_index].notes[note_index];
        const old_volume = note.volume;
        note.volume = volume;
        return old_volume;
    }
};

/// A FIFO stack of actions.
///
/// Actions may be pushed onto and popped off the stack. The stack has a maximum
/// capacity; if its capacity is exceeded, it will discard the oldest action in
/// the stack to make space for new actions.
pub const Stack = struct {
    /// The underlying buffer in which actions are stored.
    ///
    /// Actions in the buffer may be uninitialized. Only the first `len` actions
    /// are assumed to be initialized.
    buf: []Action,
    /// The number of actions in the stack.
    len: usize = 0,

    /// Allocates the stack with the given capacity.
    ///
    /// The stack is owned by the caller and should be freed by calling `deinit`.
    pub fn init(gpa: std.mem.Allocator, cap: usize) !Stack {
        return .{
            .buf = try gpa.alloc(Action, cap),
        };
    }

    /// Deallocates the stack.
    ///
    /// The stack should not be used after calling this function.
    pub fn deinit(self: Stack, gpa: std.mem.Allocator) void {
        gpa.free(self.buf);
    }

    /// Adds an action on top of the stack.
    ///
    /// If there is no space in the stack, the oldest action in the stack will
    /// be discarded.
    pub fn pushRaw(self: *Stack, action: Action) void {
        if (self.len < self.buf.len) {
            self.buf[self.len] = action;
            self.len += 1;
        } else {
            @memmove(self.buf[0 .. self.buf.len - 1], self.buf[1..self.buf.len]);
            self.buf[self.buf.len - 1] = action;
        }
    }

    /// Adds an action on top of the stack.
    ///
    /// The action will be composed with previous actions to save space. If even
    /// after composition there is no space in the stack, the oldest action in the
    /// stack will be discarded.
    pub fn push(self: *Stack, action: Action) void {
        switch (action) {
            .set_note_interval => |args| {
                if (self.peek()) |last_action| if (last_action.* == .set_note_interval) {
                    last_action.set_note_interval.interval = args.interval;
                    return;
                };
            },
            else => {},
        }
        self.pushRaw(action);
    }

    /// Removes and returns the action on top of the stack, if any.
    pub fn pop(self: *Stack) ?Action {
        if (self.len == 0)
            return null;
        self.len -= 1;
        return self.buf[self.len];
    }

    /// Replaces the action on top of the stack with the given action.
    pub fn replace(self: *Stack, action: Action) void {
        self.buf[self.len - 1] = action;
    }

    /// Returns a pointer to the action on top of the stack, if any.
    ///
    /// The pointer will be invalidated if an action is pushed or popped.
    pub fn peek(self: *Stack) ?*Action {
        return if (self.len == 0) null else &self.buf[self.len - 1];
    }
};

/// Allocates and returns a log with preset capacity.
///
/// The log is owned by the caller and should be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !ActionBus {
    const undo_stack = try Stack.init(gpa, 32);
    errdefer undo_stack.deinit(gpa);

    const redo_stack = try Stack.init(gpa, 32);
    errdefer redo_stack.deinit(gpa);

    return .{
        .undo_stack = undo_stack,
        .redo_stack = redo_stack,
    };
}

/// Deallocates the log.
///
/// The log should not be used after calling this function.
pub fn deinit(self: ActionBus, gpa: std.mem.Allocator) void {
    self.undo_stack.deinit(gpa);
    self.redo_stack.deinit(gpa);
}

/// Performs the given action and records it in the undo stack.
///
/// Returns the opposite action which, if performed, will undo the effects of
/// performing the given action. This action is intended to be used only as
/// information; it is likely incorrect to pass it back through the action bus
/// which handles undoing actions on its own.
pub fn do(self: *ActionBus, editor: *Editor, action: Action) !Action {
    const opposite_action = try action.do(editor);
    self.undo_stack.push(opposite_action);
    return opposite_action;
}

/// Undoes the most recent action.
///
/// Returns `null` if the undo stack is empty.
pub fn undo(self: *ActionBus, editor: *Editor) !?void {
    const action = self.undo_stack.pop() orelse
        return null;
    const opposite_action = try action.do(editor);
    self.redo_stack.push(opposite_action);
}

/// Redoes the most recently undone action.
///
/// Returns `null` if the redo stack is empty.
pub fn redo(self: *ActionBus, editor: *Editor) !?void {
    const action = self.redo_stack.pop() orelse
        return null;
    const opposite_action = try action.do(editor);
    self.undo_stack.push(opposite_action);
}
