//! Common math types.

const sdl = @import("sdl");
const std = @import("std");

/// An area defined by the offsets of its sides.
pub fn Margins(comptime T: type) type {
    return struct {
        left: T,
        right: T,
        top: T,
        bottom: T,
    };
}

/// An inclusive range spanning two points.
pub fn Span(comptime T: type) type {
    return struct {
        first_point: T,
        last_point: T,

        /// Returns the length of the span, in points.
        pub fn length(self: Span(T)) T {
            return self.last_point - self.first_point;
        }

        /// Returns `true` if the span includes the given point.
        pub fn includes(self: Span(T), point: T) bool {
            return self.first_point <= point and self.last_point >= point;
        }

        /// Returns `true` if the given spans overlap.
        pub fn overlaps(self: Span(T), other: Span(T)) bool {
            return self.last_point >= other.first_point and other.last_point >= self.first_point;
        }

        /// Returns the intersection of the given spans.
        pub fn intersect(self: Span(T), other: Span(T)) Span(T) {
            return .{
                .first_point = @max(self.first_point, other.first_point),
                .last_point = @min(self.last_point, other.last_point),
            };
        }

        /// Returns the union of the given spans.
        pub fn join(self: Span(T), other: Span(T)) Span(T) {
            return .{
                .first_point = @min(self.first_point, other.first_point),
                .last_point = @max(self.last_point, other.last_point),
            };
        }
    };
}

/// A two-dimensional vector.
pub fn Vec2(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,

        /// The SIMD vector representation of this vector type.
        pub const Simd = @Vector(2, T);

        /// A vector with all components set to `0`.
        pub const zero = Vec2(T){ .x = 0, .y = 0 };
        /// A vector with all components set to `1`.
        pub const one = Vec2(T){ .x = 1, .y = 1 };

        /// Returns a vector with all components set to `v`.
        pub fn splat(v: T) Vec2(T) {
            return .{ .x = v, .y = v };
        }

        /// Returns the vector's value along the given axis.
        pub fn get(self: Vec2(T), axis: Axis) T {
            return switch (axis) {
                .x => self.x,
                .y => self.y,
            };
        }

        // /// Returns the vector but with the given value along the given axis.
        // pub fn with(self: Vec2(T), axis: Axis, v: T) Vec2(T) {
        //     switch (axis) {
        //         .x => self.x = v,
        //         .y => self.y = v,
        //     }
        // }

        /// Returns the vector but with the given component's sign flipped.
        pub fn withNeg(self: Vec2(T), axis: Axis) Vec2(T) {
            return switch (axis) {
                .x => .{ .x = -self.x, .y = self.y },
                .y => .{ .x = self.x, .y = -self.y },
            };
        }

        pub fn swap(self: Vec2(T)) Vec2(T) {
            return .{ .x = self.y, .y = self.x };
        }

        /// Converts the vector to its SIMD vector representation.
        pub fn to_simd(self: Vec2(T)) Simd {
            return .{ self.x, self.y };
        }

        /// Converts the SIMD vector to its `Vec2` representation.
        pub fn from_simd(simd: Simd) Vec2(T) {
            return .{ .x = simd[0], .y = simd[1] };
        }

        /// Adds the given vectors and returns the result.
        pub fn add(self: Vec2(T), other: Vec2(T)) Vec2(T) {
            return from_simd(self.to_simd() + other.to_simd());
        }

        /// Subtracts the given vectors and returns the result.
        pub fn sub(self: Vec2(T), other: Vec2(T)) Vec2(T) {
            return from_simd(self.to_simd() - other.to_simd());
        }

        /// Multiplies the given vector and returns the result.
        ///
        /// The multiplier may be a vector `Vec2(T)` or a scalar `T`.
        pub fn mul(self: Vec2(T), multiplier: anytype) Vec2(T) {
            return from_simd(self.to_simd() * switch (@TypeOf(multiplier)) {
                Vec2(T) => multiplier.to_simd(),
                T, comptime_float, comptime_int => @as(Simd, @splat(multiplier)),
                else => @compileError("`Vec2(" ++ @typeName(T) ++ ").mul` should only be called with a multiplier of type `Vec2(" ++ @typeName(T) ++ ")` or `" ++ @typeName(T) ++ "`, not `" ++ @typeName(@TypeOf(multiplier)) ++ "`"),
            });
        }

        /// Divides the given vector and returns the result.
        ///
        /// The multiplier may be a vector `Vec2(T)` or a scalar `T`.
        pub fn div(self: Vec2(T), divisor: anytype) Vec2(T) {
            return from_simd(self.to_simd() / switch (@TypeOf(divisor)) {
                Vec2(T) => divisor.to_simd(),
                T, comptime_float, comptime_int => @as(Simd, @splat(divisor)),
                else => @compileError("`Vec2(" ++ @typeName(T) ++ ").div` should only be called with a divisor of type `Vec2(" ++ @typeName(T) ++ ")` or `" ++ @typeName(T) ++ "`, not `" ++ @typeName(@TypeOf(divisor)) ++ "`"),
            });
        }

        /// Returns the vector with its components' signs flipped.
        pub fn neg(self: Vec2(T)) Vec2(T) {
            return .{ .x = -self.x, .y = -self.y };
        }

        /// Returns the magnitude (i.e. length) of the vector, squared.
        pub fn magsq(self: Vec2(T)) T {
            return self.x * self.x + self.y * self.y;
        }

        /// Returns the magnitude (i.e. length) of the vector.
        pub fn mag(self: Vec2(T)) T {
            return @sqrt(self.magsq());
        }

        /// Scales the vector to unit length.
        ///
        /// Returns an error if the vector is of zero magnitude.
        pub fn normalize(self: Vec2(T)) !Vec2(T) {
            const m = self.mag();
            return if (m == 0) error.DivisionByZero else self.div(m);
        }

        /// Rotates the vector by the given angle, in radians.
        pub fn rotate(self: Vec2(T), rad: f32) Vec2(T) {
            return .{
                .x = self.x * @cos(rad) - self.y * @sin(rad),
                .y = self.x * @sin(rad) + self.y * @cos(rad),
            };
        }
    };
}

pub fn Rect(comptime T: type) type {
    return struct {
        /// The *x* position of the top-left corner of the rectangle.
        x: T = 0,
        /// The *y* position of the top-left corner of the rectangle.
        y: T = 0,
        /// The width of the rectangle.
        w: T,
        /// The height of the rectangle.
        h: T,

        /// The corners of a rectangle.
        pub const Corners = struct {
            /// The top left corner.
            tl: Vec2(f32),
            /// The top right corner.
            tr: Vec2(f32),
            /// The bottom left corner.
            bl: Vec2(f32),
            /// The bottom right corner.
            br: Vec2(f32),
        };

        /// A zero-sized rectangle starting from the origin.
        pub const zero = Rect(T){ .w = 0, .h = 0 };
        /// A one-by-one rectangle starting from the origin.
        pub const unit = Rect(T){ .w = 1, .h = 1 };

        /// Returns a `Vec2` of the top-left corner of the rectangle.
        pub fn pos(self: Rect(T)) Vec2(T) {
            return .{ .x = self.x, .y = self.y };
        }

        /// Returns a `Vec2` of the size of the rectangle.
        pub fn size(self: Rect(T)) Vec2(T) {
            return .{ .x = self.w, .y = self.h };
        }

        /// Returns the *x* coordinate of the rectangle's right side.
        pub fn endX(self: Rect(T)) T {
            return self.x + self.w;
        }

        /// Returns the *y* coordinate of the rectangle's bottom side.
        pub fn endY(self: Rect(T)) T {
            return self.y + self.h;
        }

        /// Returns the rectangle but with the given *x* position.
        pub fn withX(self: Rect(T), x: T) Rect(T) {
            var rect = self;
            rect.x = x;
            return rect;
        }

        /// Returns the rectangle but with the given *y* position.
        pub fn withY(self: Rect(T), y: T) Rect(T) {
            var rect = self;
            rect.y = y;
            return rect;
        }

        /// Returns the rectangle but with the given width.
        pub fn withW(self: Rect(T), w: T) Rect(T) {
            var rect = self;
            rect.w = w;
            return rect;
        }

        /// Returns the rectangle but with the given height.
        pub fn withH(self: Rect(T), h: T) Rect(T) {
            var rect = self;
            rect.h = h;
            return rect;
        }

        /// Returns the rectangle but with the given position.
        pub fn withPos(self: Rect(T), p: Vec2(T)) Rect(T) {
            var rect = self;
            rect.x = p.x;
            rect.y = p.y;
            return rect;
        }

        /// Returns the rectangle but with the given size.
        pub fn withSize(self: Rect(T), s: Vec2(T)) Rect(T) {
            var rect = self;
            rect.w = s.x;
            rect.h = s.y;
            return rect;
        }

        /// Expands the rectangle on all sides by the given amount.
        pub fn grow(self: Rect(T), amount: T) Rect(T) {
            const new_pos = @Vector(2, T){ self.x, self.y } - @as(@Vector(2, T), @splat(amount));
            const new_size = @Vector(2, T){ self.w, self.h } + @as(@Vector(2, T), @splat(amount * 2));
            return .{ .x = new_pos[0], .y = new_pos[1], .w = new_size[0], .h = new_size[1] };
        }

        /// Splits the rectangle in two at the given position.
        pub fn split(self: Rect(T), axis: Axis, offset: T) .{ Rect(T), Rect(T) } {
            return .{ .{
                .pos = self.pos,
                .size = self.size.with(axis, offset),
            }, .{
                .pos = self.pos.with(axis, self.pos.get(axis) + offset),
                .size = self.size.with(axis, self.size.get(axis) - offset),
            } };
        }

        /// Returns the four corners of the rectangle.
        pub fn corners(self: Rect(T)) Corners {
            const end_x = self.endX();
            const end_y = self.endY();
            return .{
                .tl = .{ .x = self.x, .y = self.y },
                .tr = .{ .x = end_x, .y = self.y },
                .bl = .{ .x = self.x, .y = end_y },
                .br = .{ .x = end_x, .y = end_y },
            };
        }

        /// Converts the rectangle to an SDL integer rectangle.
        pub fn sdlRect(self: Rect(T)) sdl.SDL_Rect {
            return .{
                .x = self.x,
                .y = self.y,
                .w = self.w,
                .h = self.h,
            };
        }

        /// Converts the rectangle to an SDL floating-point rectangle.
        pub fn sdlFRect(self: Rect(T)) sdl.SDL_FRect {
            return .{
                .x = self.x,
                .y = self.y,
                .w = self.w,
                .h = self.h,
            };
        }
    };
}

/// An RGBA color with components of the given type.
pub fn Color(comptime T: type) type {
    return struct {
        r: T,
        g: T,
        b: T,
        a: T = range.max,

        /// The type of a component.
        pub const Component = T;
        /// The range of values a component may have.
        pub const range = if (T == u8)
            .{ .min = 0, .max = 255 }
        else if (@typeInfo(T) == .float)
            .{ .min = 0, .max = 1 }
        else
            @compileError("`Color` components may only be be `u8` or a floating-point type");

        /// A color with all components set to their minimum value.
        pub const zero = Color(T){ .r = range.min, .g = range.min, .b = range.min, .a = range.min };
        /// Absolute black.
        pub const black = Color(T){ .r = range.min, .g = range.min, .b = range.min };
        /// Absolute white.
        pub const white = Color(T){ .r = range.max, .g = range.max, .b = range.max };
        /// Absolute red.
        pub const red = Color(T){ .r = range.max, .g = range.min, .b = range.min };
        /// Absolute green.
        pub const green = Color(T){ .r = range.min, .g = range.max, .b = range.min };
        /// Absolute blue.
        pub const blue = Color(T){ .r = range.min, .g = range.min, .b = range.max };
        /// Absolute cyan.
        pub const cyan = Color(T){ .r = range.min, .g = range.max, .b = range.max };
        /// Absolute magenta.
        pub const magenta = Color(T){ .r = range.max, .g = range.min, .b = range.max };
        /// Absolute yellow.
        pub const yellow = Color(T){ .r = range.max, .g = range.max, .b = range.min };

        /// Constructs a `Color` from a hexcode of the form `0xRRGGBB`.
        pub fn fromHexRgb(value: comptime_int) Color(T) {
            const r = value & 0xff;
            const g = (value << 8) & 0xff;
            const b = (value << 16) & 0xff;
            return if (T == u8)
                .{ .r = r, .g = g, .b = b }
            else if (@typeInfo(T) == .float)
                .{ .r = @as(T, @floatFromInt(r)) / 255, .g = @as(T, @floatFromInt(g)) / 255, .b = @as(T, @floatFromInt(b)) / 255 };
        }

        /// Returns an opaque color with the given value.
        pub fn fromValue(value: T) Color(T) {
            return .{ .r = value, .g = value, .b = value };
        }

        /// Returns the color but with the given `r` value.
        pub fn withR(self: Color(T), r: T) Color(T) {
            self.r = r;
            return self;
        }

        /// Returns the color but with the given `g` value.
        pub fn withG(self: Color(T), g: T) Color(T) {
            self.g = g;
            return self;
        }

        /// Returns the color but with the given `b` value.
        pub fn withB(self: Color(T), b: T) Color(T) {
            self.b = b;
            return self;
        }

        /// Returns the color but with the given `a` value.
        pub fn withA(self: Color(T), a: T) Color(T) {
            var color = self;
            color.a = a;
            return color;
        }

        /// Converts the color to an SDL integer color.
        pub fn sdlColor(self: Color(T)) sdl.SDL_Color {
            return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
        }

        /// Converts the color to an SDL floating-point color.
        pub fn sdlFColor(self: Color(T)) sdl.SDL_FColor {
            return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
        }
    };
}

pub const Axis = enum { x, y };

/// Remaps a value from one range to another, based on the given minimums and
/// conversion multiplier.
pub fn rebase(
    val: anytype,
    src_min: @TypeOf(val),
    dst_min: @TypeOf(val),
    mult: @TypeOf(val),
) @TypeOf(val) {
    return dst_min + (val - src_min) * mult;
}
