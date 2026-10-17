const std = @import("std");

/// A memory pool backed by a buffer and a singly-linked list.
pub fn BufPool(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The backing buffer.
        buf: []Slot,
        /// A singly-linked list of unused slots in the buffer.
        free_list: std.SinglyLinkedList,

        /// An empty memory pool with a zero-sized buffer.
        pub const empty: Self = .{
            .buf = &.{},
            .free_list = .{},
        };

        /// The value of a single slot in the backing buffer.
        ///
        /// The slot may either contain a value of type `T` or a node in the
        /// free list.
        const Slot = union { value: T, node: std.SinglyLinkedList.Node };

        /// Returns a new pool with the given capacity.
        ///
        /// The pool is owned by the caller and should be freed by calling
        /// `deinit`.
        pub fn initCapacity(gpa: std.mem.Allocator, cap: usize) !Self {
            const buf = try gpa.alloc(Slot, cap);
            errdefer gpa.free(buf);

            return .{
                .buf = buf,
                .free_list = populateBuf(buf),
            };
        }

        /// Destroys the pool and frees the backing buffer.
        ///
        /// The pool should not be used after calling this function.
        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.buf);
            self.* = undefined;
        }

        /// Returns the index of an unused item in the pool.
        ///
        /// If the pool is full, attempts to reallocate the backing buffer,
        /// potentially invalidating any item pointers.
        pub fn create(self: *Self, gpa: std.mem.Allocator) !usize {
            if (self.free_list.first == null) {
                const old_cap = self.buf.len;
                self.buf = try gpa.realloc(self.buf, std.ArrayList(Slot).growCapacity(self.buf.len + 1));
                self.free_list = populateBuf(self.buf[old_cap..]);
            }
            return self.createBounded();
        }

        /// Returns the index of an unused item in the pool.
        ///
        /// If the pool is full, returns `error.OutOfMemory`.
        pub fn createBounded(self: *Self) !usize {
            const slot: *Slot = @ptrCast(@alignCast(self.free_list.popFirst() orelse
                return error.OutOfMemory));
            slot.* = .{ .value = undefined };
            return (slot - self.buf.ptr) / @sizeOf(Slot);
        }

        /// Destroys the item with the given index.
        pub fn destroy(self: *Self, index: usize) void {
            const slot = &self.buf[index];
            slot.* = .{ .node = .{} };
            self.free_list.prepend(&slot.node);
        }

        /// Ensures the pool can hold at least `cap` items.
        ///
        /// Reallocates the backing buffer if necessary, potentially
        /// invalidating any item pointers.
        pub fn ensureTotalCapacity(self: *Self, gpa: std.mem.Allocator, cap: usize) !void {
            if (cap <= self.buf.len) return;
            const old_cap = self.buf.len;
            self.buf = try gpa.realloc(self.buf, cap);

            const head = populateBuf(self.buf[old_cap..cap]).first orelse return;
            if (self.free_list.first) |first| {
                var tail = first;
                while (tail.next) |next| tail = next;
                tail.next = head;
            } else self.free_list.first = head;
        }

        /// Ensures the pool can hold at least `cap` additional items.
        ///
        /// Reallocates the backing buffer if necessary, potentially
        /// invalidating any item pointers.
        ///
        /// Note that because unused slots are tracked with a singly linked
        /// list, this function takes `O(n)` time to compute the number of
        /// unused slots.
        pub fn ensureUnusedCapacity(self: *Self, gpa: std.mem.Allocator, cap: usize) !void {
            try self.ensureTotalCapacity(gpa, self.buf.len - self.free_list.len() + cap);
        }

        /// Clears the pool, invalidating any item IDs or pointers.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.free_list = populateBuf(self.buf);
        }

        /// Returns `true` if there are no unused slots in the pool.
        pub fn isFull(self: Self) bool {
            return self.free_list.first == null;
        }

        pub fn items(self: *Self) []T {
            if (@sizeOf(T) < @sizeOf(Slot) and @alignOf(T) != @alignOf(Slot))
                @compileError("`BufPool(T).items` may only be called if `T` has the same size as and a compatible alignment with `BufPool(T).Slot`");
            return @as([*]T, @ptrCast(self.buf.ptr))[0..self.buf.len];
        }

        /// Returns a pointer to the item with the given index.
        fn itemPtr(self: *Self, index: usize) *T {
            return &self.buf[@intFromEnum(index)].value;
        }

        /// Populates `buf` with empty slots.
        fn populateBuf(buf: []Slot) std.SinglyLinkedList {
            var dummy: std.SinglyLinkedList.Node = .{};
            var prev_node: *std.SinglyLinkedList.Node = &dummy;
            for (buf) |*slot| {
                slot.* = .{ .node = .{} };
                prev_node.next = &slot.node;
                prev_node = &slot.node;
            }

            return .{ .first = dummy.next };
        }

        test "basic" {
            var pool: BufPool(T) = .empty;
            defer pool.deinit(std.testing.allocator);

            try std.testing.expect(pool.isFull());

            const item = try pool.create(std.testing.allocator);
            defer pool.destroy(item);

            try std.testing.expect(!pool.isFull());
        }

        test ensureTotalCapacity {
            var pool: BufPool(T) = .empty;
            defer pool.deinit(std.testing.allocator);

            try std.testing.expect(pool.isFull());

            try pool.ensureTotalCapacity(std.testing.allocator, 8);

            try std.testing.expectEqual(8, pool.free_list.len());

            pool.clearRetainingCapacity();

            try std.testing.expect(!pool.isFull());
        }

        test populateBuf {
            const buf = try std.testing.allocator.alloc(Slot, 8);
            defer std.testing.allocator.free(buf);

            const list = populateBuf(buf);

            try std.testing.expectEqual(buf.len, list.len());
        }
    };
}
