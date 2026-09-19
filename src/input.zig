const math = @import("math.zig");
const std = @import("std");

/// Describes input performed by the user.
pub const Event = union(enum) {
    /// A button is pressed or released.
    button: struct { button: Button, is_pressed: bool },
    /// The cursor is moved.
    cursor: struct { pos: math.Vec2(f32) },
    /// A wheel is scrolled.
    scroll: struct { amount: math.Vec2(f32) },
};

/// A button the user might press.
pub const Button = enum {
    /// The 'A' key.
    key_a,
    /// The 'B' key.
    key_b,
    /// The 'C' key.
    key_c,
    /// The 'D' key.
    key_d,
    /// The 'E' key.
    key_e,
    /// The 'F' key.
    key_f,
    /// The 'G' key.
    key_g,
    /// The 'H' key.
    key_h,
    /// The 'I' key.
    key_i,
    /// The 'J' key.
    key_j,
    /// The 'K' key.
    key_k,
    /// The 'L' key.
    key_l,
    /// The 'M' key.
    key_m,
    /// The 'N' key.
    key_n,
    /// The 'O' key.
    key_o,
    /// The 'P' key.
    key_p,
    /// The 'Q' key.
    key_q,
    /// The 'R' key.
    key_r,
    /// The 'S' key.
    key_s,
    /// The 'T' key.
    key_t,
    /// The 'U' key.
    key_u,
    /// The 'V' key.
    key_v,
    /// The 'W' key.
    key_w,
    /// The 'X' key.
    key_x,
    /// The 'Y' key.
    key_y,
    /// The 'Z' key.
    key_z,
    /// The '`' key.
    key_backtick,
    /// The '1' key.
    key_1,
    /// The '2' key.
    key_2,
    /// The '3' key.
    key_3,
    /// The '4' key.
    key_4,
    /// The '5' key.
    key_5,
    /// The '6' key.
    key_6,
    /// The '7' key.
    key_7,
    /// The '8' key.
    key_8,
    /// The '9' key.
    key_9,
    /// The '0' key.
    key_0,
    /// The `-` key.
    key_minus,
    /// The `+` key.
    key_plus,
    /// The left arrow key.
    key_left,
    /// The right arrow key.
    key_right,
    /// The up arrow key.
    key_up,
    /// The down arrow key.
    key_down,
    /// The space key.
    key_space,
    /// The return key.
    key_return,
    /// The escape key.
    key_escape,
    /// The tab key.
    key_tab,
    /// The left shift key.
    key_lshift,
    /// The right shift key.
    key_rshift,
    /// The left control key.
    key_lctrl,
    /// The right control key.
    key_rctrl,
    /// The left command key on MacOS.
    key_lsuper,
    /// The right command key on MacOS.
    key_rsuper,

    /// The left mouse button.
    mouse_left,
    /// The right mouse button.
    mouse_right,
    /// The middle mouse button.
    mouse_middle,
};

/// A bitmask of buttons commonly used as modifiers.
pub const ModButtons = packed struct {
    shift: Req = .ignore,
    ctrl: Req = .ignore,
    super: Req = .ignore,

    /// A requirement for the state of modifier buttons.
    const Req = enum(u2) { ignore, either, only_left, only_right };
};

/// An input action the user might perform.
pub const Action = enum {
    /// A UI widget should be accepted.
    ui_accept,
    /// A UI widget should be cancelled.
    ui_cancel,
    /// A UI widget should navigate left.
    ui_left,
    /// A UI widget should navigate right.
    ui_right,
    /// A UI widget should navigate up.
    ui_up,
    /// A UI widget should navigate down.
    ui_down,
    /// A UI widget should navigate to the previous element.
    ui_prev,
    /// A UI widget should navigate to the next element.
    ui_next,

    /// An editor action should be undone.
    editor_undo,
    /// An editor action should be redone.
    editor_redo,
    /// Editor playback should be played or paused.
    editor_toggle_playback,

    /// A note should be placed in the pattern editor.
    pattern_editor_place_note,

    /// A section should be placed in the timeline.
    timeline_place_section,
};

/// Records input state and maps it to input actions.
pub const State = struct {
    /// The most recently recorded event.
    last_event: Event = .{ .cursor = .{ .pos = .zero } },
    /// The most recently recorded cursor position.
    cursor_pos: math.Vec2(f32) = .zero,
    /// The set of buttons currently recorded as pressed.
    pressed_buttons: std.EnumSet(Button) = .empty,
    /// Button bindings for each input action.
    bindings: std.EnumMap(Action, struct { button: Button, mod_buttons: ModButtons }) = .{},

    /// Input state with default bindings.
    pub const default = init: {
        var state: State = .{};

        state.bind(.ui_accept, .key_return, .{});
        state.bind(.ui_cancel, .key_escape, .{});
        state.bind(.ui_left, .key_left, .{});
        state.bind(.ui_right, .key_right, .{});
        state.bind(.ui_up, .key_up, .{});
        state.bind(.ui_down, .key_down, .{});
        state.bind(.ui_prev, .key_tab, .{ .shift = .either });
        state.bind(.ui_next, .key_tab, .{});

        state.bind(.editor_undo, .key_z, .{ .super = .either });
        state.bind(.editor_redo, .key_z, .{ .super = .either, .shift = .either });
        state.bind(.editor_toggle_playback, .key_space, .{});

        state.bind(.pattern_editor_place_note, .mouse_left, .{});

        state.bind(.timeline_place_section, .mouse_left, .{});

        break :init state;
    };

    /// Records the given input event.
    pub fn record(self: *State, event: Event) void {
        self.last_event = event;
        switch (event) {
            .button => |button_event| if (button_event.is_pressed)
                self.pressed_buttons.insert(button_event.button)
            else
                self.pressed_buttons.remove(button_event.button),
            .cursor => |cursor_event| self.cursor_pos = cursor_event.pos,
            else => {},
        }
    }

    /// Returns `true` if the given button is recorded as pressed.
    pub fn is_button_pressed(self: State, button: Button) bool {
        return self.pressed_buttons.contains(button);
    }

    /// Returns `true` if the most recently recorded event was the given button
    /// being pressed.
    pub fn was_button_just_pressed(self: State, button: Button) bool {
        return self.last_event == .button and self.last_event.button.button == button and self.last_event.button.is_pressed;
    }

    /// Returns `true` if the most recently recorded event was the given button
    /// being released.
    pub fn was_button_just_released(self: State, button: Button) bool {
        return self.last_event == .button and self.last_event.button.button == button and !self.last_event.button.is_pressed;
    }

    /// Returns `true` if the given modifier buttons are recorded as pressed.
    pub fn are_mod_buttons_pressed(self: State, mod_buttons: ModButtons) bool {
        return switch (mod_buttons.shift) {
            .ignore => true,
            .only_left => self.is_button_pressed(.key_lshift),
            .only_right => self.is_button_pressed(.key_rshift),
            .either => self.is_button_pressed(.key_lshift) or self.is_button_pressed(.key_rshift),
        } and switch (mod_buttons.ctrl) {
            .ignore => true,
            .only_left => self.is_button_pressed(.key_lctrl),
            .only_right => self.is_button_pressed(.key_rctrl),
            .either => self.is_button_pressed(.key_lctrl) or self.is_button_pressed(.key_rctrl),
        } and switch (mod_buttons.super) {
            .ignore => true,
            .only_left => self.is_button_pressed(.key_lsuper),
            .only_right => self.is_button_pressed(.key_rsuper),
            .either => self.is_button_pressed(.key_lsuper) or self.is_button_pressed(.key_rsuper),
        };
    }

    /// Returns `true` if the given action is recorded as active.
    pub fn is_action_active(self: State, action: Action) bool {
        const binding = self.bindings.get(action) orelse return false;
        return self.is_button_pressed(binding.button) and self.are_mod_buttons_pressed(binding.mod_buttons);
    }

    /// Returns `true` if the most recently recorded event was the given action
    /// being pressed.
    pub fn was_action_just_pressed(self: State, action: Action) bool {
        const binding = self.bindings.get(action) orelse return false;
        return self.was_button_just_pressed(binding.button) and self.are_mod_buttons_pressed(binding.mod_buttons);
    }

    /// Returns `true` if the most recently recorded event was the given action
    /// being released.
    pub fn was_action_just_released(self: State, action: Action) bool {
        const binding = self.bindings.get(action) orelse return false;
        return self.was_button_just_released(binding.button) and self.are_mod_buttons_pressed(binding.mod_buttons);
    }

    /// Binds the given action to the given buttons.
    pub fn bind(self: *State, action: Action, button: Button, mod_buttons: ModButtons) void {
        self.bindings.put(action, .{ .button = button, .mod_buttons = mod_buttons });
    }
};
