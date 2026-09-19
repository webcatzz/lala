//! Chip tone synthesis.

const std = @import("std");

/// Samples a pulse wave with the given duty cycle at the given phase.
///
/// - `phase` should be a value in \[0.0, 1.0).
/// - `duty` should be a value in \[0.0, 1.0) representing the ratio of the
///   pulse duration to the total period, e.g. `0.25` for a 1/4 pulse or `0.5`
///   for a square wave.
pub fn pulse(phase: f32, duty: f32) f32 {
    return @floatFromInt(@intFromBool(phase <= duty));
}

/// Samples a triangle wave at the given phase.
///
/// - `phase` should be a value in \[0.0, 1.0).
pub fn triangle(phase: f32) f32 {
    return @abs(phase - @floor(phase + 0.5)) * 2.0;
}

/// Samples a sine wave at the given phase.
///
/// - `phase` should be a value in \[0.0, 1.0).
pub fn sine(phase: f32) f32 {
    return @sin(phase * std.math.tau);
}
