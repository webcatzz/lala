//! Pitches.
//!
//! These values follow the MIDI standard.

pub const C0 = 12;
pub const CS0 = 13;
pub const D0 = 14;
pub const DS0 = 15;
pub const E0 = 16;
pub const F0 = 17;
pub const FS0 = 18;
pub const G0 = 19;
pub const GS0 = 20;
pub const A0 = 21;
pub const AS0 = 22;
pub const B0 = 23;
pub const C1 = 24;
pub const CS1 = 25;
pub const D1 = 26;
pub const DS1 = 27;
pub const E1 = 28;
pub const F1 = 29;
pub const FS1 = 30;
pub const G1 = 31;
pub const GS1 = 32;
pub const A1 = 33;
pub const AS1 = 34;
pub const B1 = 35;
pub const C2 = 36;
pub const CS2 = 37;
pub const D2 = 38;
pub const DS2 = 39;
pub const E2 = 40;
pub const F2 = 41;
pub const FS2 = 42;
pub const G2 = 43;
pub const GS2 = 44;
pub const A2 = 45;
pub const AS2 = 46;
pub const B2 = 47;
pub const C3 = 48;
pub const CS3 = 49;
pub const D3 = 50;
pub const DS3 = 51;
pub const E3 = 52;
pub const F3 = 53;
pub const FS3 = 54;
pub const G3 = 55;
pub const GS3 = 56;
pub const A3 = 57;
pub const AS3 = 58;
pub const B3 = 59;
pub const C4 = 60;
pub const CS4 = 61;
pub const D4 = 62;
pub const DS4 = 63;
pub const E4 = 64;
pub const F4 = 65;
pub const FS4 = 66;
pub const G4 = 67;
pub const GS4 = 68;
pub const A4 = 69;
pub const AS4 = 70;
pub const B4 = 71;
pub const C5 = 72;
pub const CS5 = 73;
pub const D5 = 74;
pub const DS5 = 75;
pub const E5 = 76;
pub const F5 = 77;
pub const FS5 = 78;
pub const G5 = 79;
pub const GS5 = 80;
pub const A5 = 81;
pub const AS5 = 82;
pub const B5 = 83;
pub const C6 = 84;
pub const CS6 = 85;
pub const D6 = 86;
pub const DS6 = 87;
pub const E6 = 88;
pub const F6 = 89;
pub const FS6 = 90;
pub const G6 = 91;
pub const GS6 = 92;
pub const A6 = 93;
pub const AS6 = 94;
pub const B6 = 95;
pub const C7 = 96;
pub const CS7 = 97;
pub const D7 = 98;
pub const DS7 = 99;
pub const E7 = 100;
pub const F7 = 101;
pub const FS7 = 102;
pub const G7 = 103;
pub const GS7 = 104;
pub const A7 = 105;
pub const AS7 = 106;
pub const B7 = 107;
pub const C8 = 108;
pub const CS8 = 109;
pub const D8 = 110;
pub const DS8 = 111;
pub const E8 = 112;
pub const F8 = 113;
pub const FS8 = 114;
pub const G8 = 115;
pub const GS8 = 116;
pub const A8 = 117;
pub const AS8 = 118;
pub const B8 = 119;
pub const C9 = 120;
pub const CS9 = 121;
pub const D9 = 122;
pub const DS9 = 123;
pub const E9 = 124;
pub const F9 = 125;
pub const FS9 = 126;
pub const G9 = 127;

/// Converts from pitch to frequency.
pub fn freq(pitch: f32) f32 {
    return 440.0 * @exp2((pitch - 69.0) / 12.0);
}

/// Returns the color of the piano key corresponding to the given pitch.
pub fn color(pitch: anytype) enum { white, black } {
    return switch (pitch % 12) {
        1, 3, 6, 8, 10 => .black,
        else => .white,
    };
}

pub fn class(pitch: anytype) enum {
    c,
    c_sharp,
    d,
    d_sharp,
    e,
    f,
    f_sharp,
    g,
    g_sharp,
    a,
    a_sharp,
    b,
} {
    return @enumFromInt(pitch % 12);
}

/// Returns a human-readable name for the given pitch.
pub fn name(pitch: u8) ?[]const u8 {
    return switch (pitch) {
        12 => "C0",
        13 => "C#0",
        14 => "D0",
        15 => "D#0",
        16 => "E0",
        17 => "F0",
        18 => "F#0",
        19 => "G0",
        20 => "G#0",
        21 => "A0",
        22 => "A#0",
        23 => "B0",
        24 => "C1",
        25 => "C#1",
        26 => "D1",
        27 => "D#1",
        28 => "E1",
        29 => "F1",
        30 => "F#1",
        31 => "G1",
        32 => "G#1",
        33 => "A1",
        34 => "A#1",
        35 => "B1",
        36 => "C2",
        37 => "C#2",
        38 => "D2",
        39 => "D#2",
        40 => "E2",
        41 => "F2",
        42 => "F#2",
        43 => "G2",
        44 => "G#2",
        45 => "A2",
        46 => "A#2",
        47 => "B2",
        48 => "C3",
        49 => "C#3",
        50 => "D3",
        51 => "D#3",
        52 => "E3",
        53 => "F3",
        54 => "F#3",
        55 => "G3",
        56 => "G#3",
        57 => "A3",
        58 => "A#3",
        59 => "B3",
        60 => "C4",
        61 => "C#4",
        62 => "D4",
        63 => "D#4",
        64 => "E4",
        65 => "F4",
        66 => "F#4",
        67 => "G4",
        68 => "G#4",
        69 => "A4",
        70 => "A#4",
        71 => "B4",
        72 => "C5",
        73 => "C#5",
        74 => "D5",
        75 => "D#5",
        76 => "E5",
        77 => "F5",
        78 => "F#5",
        79 => "G5",
        80 => "G#5",
        81 => "A5",
        82 => "A#5",
        83 => "B5",
        84 => "C6",
        85 => "C#6",
        86 => "D6",
        87 => "D#6",
        88 => "E6",
        89 => "F6",
        90 => "F#6",
        91 => "G6",
        92 => "G#6",
        93 => "A6",
        94 => "A#6",
        95 => "B6",
        96 => "C7",
        97 => "C#7",
        98 => "D7",
        99 => "D#7",
        100 => "E7",
        101 => "F7",
        102 => "F#7",
        103 => "G7",
        104 => "G#7",
        105 => "A7",
        106 => "A#7",
        107 => "B7",
        108 => "C8",
        109 => "C#8",
        110 => "D8",
        111 => "D#8",
        112 => "E8",
        113 => "F8",
        114 => "F#8",
        115 => "G8",
        116 => "G#8",
        117 => "A8",
        118 => "A#8",
        119 => "B8",
        120 => "C9",
        121 => "C#9",
        122 => "D9",
        123 => "D#9",
        124 => "E9",
        125 => "F9",
        126 => "F#9",
        127 => "G9",
        else => null,
    };
}
