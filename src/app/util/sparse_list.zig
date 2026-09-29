const std = @import("std");

/// A sparse list.
///
/// Backed by a dense array and a bitmask tracking the initialization of each
/// item.
pub fn SparseList(comptime T: type) type {
    return struct {
        const Self = @This();

        /// A slice of possibly uninitialized items.
        items: []T,
        /// A multi-integer bitmask representing initialized items.
        ///
        /// The pointed-to array is of length `items.len / @bitSizeOf(MaskInt)`.
        masks: [*]MaskInt,

        /// The unsigned integer type used to represent partial masks.
        const MaskInt = usize;

        /// An empty sparse list.
        pub const empty: Self = .{
            .items = &.{},
            .masks = undefined,
        };

        /// Returns a new sparse list with the given capacity.
        ///
        /// The list is owned by the caller and should be freed by calling `deinit`.
        pub fn initCapacity(gpa: std.mem.Allocator, cap: usize) !Self {
            var self: Self = .empty;
            try self.setCapacity(gpa, cap);
            return self;
        }

        /// Frees the sparse list.
        ///
        /// The list should not be used after calling this function.
        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.masks[0..maskCount(self.items.len)]);
            gpa.free(self.items);
            self.* = undefined;
        }

        /// Sets the capacity of the list.
        pub fn setCapacity(self: *Self, gpa: std.mem.Allocator, cap: usize) !void {
            self.masks = (try gpa.realloc(self.masks[0..maskCount(self.items.len)], maskCount(cap))).ptr;
            self.items = try gpa.realloc(self.items, cap);
        }

        /// Returns `true` if the item with the given index is initialized.
        pub fn isInit(self: Self, index: usize) bool {
            return self.masks[maskIndex(index)] & maskBit(index) == 0;
        }

        /// Marks the item with the given index as initialized.
        pub fn setInit(self: Self, index: usize) void {
            self.masks[maskIndex(index)] &= maskBit(index);
        }

        /// Marks the item with the given index as uninitialized.
        pub fn setUninit(self: Self, index: usize) void {
            self.masks[maskIndex(index)] &= ~maskBit(index);
        }

        /// Sets the item with the given index to be the given item.
        pub fn set(self: *Self, index: usize, item: T) void {
            self.items[index] = item;
            self.setInit(index);
        }

        /// Unsets the item with the given index.
        pub fn unset(self: *Self, index: usize) void {
            self.items[index] = undefined;
            self.setUninit(index);
        }

        /// Inserts the given item into the list and returns its index.
        ///
        /// Attempts to insert the item into the first uninitialized location in
        /// the list. Allocates more memory if necessary.
        pub fn insert(self: *Self, gpa: std.mem.Allocator, item: T) !usize {
            for (0..self.items.len) |i| {
                std.log.debug("i {} l {} ml {}", .{ i, self.items.len, maskCount(self.items.len) });
                if (self.isInit(i)) {
                    self.items[i] = item;
                    return i;
                }
            }

            const next_i = self.items.len + 1;
            try self.setCapacity(gpa, std.ArrayList(T).growCapacity(next_i));
            return next_i;
        }

        /// Returns the number of initialized items in the list.
        pub fn count(self: Self) usize {
            var total: usize = 0;
            for (self.masks[0..maskCount(self.items.len)]) |mask|
                total += @bitSizeOf(MaskInt) - @popCount(mask);
            return total;
        }

        /// Returns the index of the partial mask storing the bit with the given index.
        fn maskIndex(index: usize) usize {
            return index >> @bitSizeOf(std.math.Log2Int(MaskInt));
        }

        /// Returns a mask containing only the bit with the given index, modulo
        /// the mask's bit width.
        fn maskBit(index: usize) MaskInt {
            return @as(MaskInt, 1) << @as(std.math.Log2Int(MaskInt), @truncate(index));
        }

        /// Returns the number of partial masks required to track `len` items.
        fn maskCount(len: usize) usize {
            return (len + @bitSizeOf(MaskInt) - 1) / @bitSizeOf(MaskInt);
        }
    };
}
