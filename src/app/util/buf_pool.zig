const std = @import("std");

/// A memory pool backed by a buffer.
pub fn BufPool(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The backing buffer.
        buf: []T,
        /// A singly-linked list of unused slots in the buffer.
        free_list: std.SinglyLinkedList,

        /// An empty memory pool with a zero-sized buffer.
        pub const empty: Self = .{
            .buf = &.{},
            .free_list = .{},
        };

        /// Returns a new pool with the given capacity.
        ///
        /// The pool is owned by the caller and should be freed by calling
        /// `deinit`.
        pub fn initCapacity(gpa: std.mem.Allocator, cap: usize) !Self {
            const buf = try gpa.alloc(T, cap);
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
                self.buf = try gpa.realloc(self.buf, std.ArrayList(T).growCapacity(self.buf.len + 1));
                self.free_list = populateBuf(self.buf[old_cap..]);
            }
            return self.createBounded();
        }

        /// Returns the index of an unused item in the pool.
        ///
        /// If the pool is full, returns `error.OutOfMemory`.
        pub fn createBounded(self: *Self) !usize {
            const ptr: *T = @ptrCast(@alignCast(self.free_list.popFirst() orelse
                return error.OutOfMemory));
            ptr.* = undefined;
            return self.itemIndex(ptr);
        }

        /// Destroys the item with the given index.
        pub fn destroy(self: *Self, index: usize) void {
            const ptr = &self.buf[index];
            ptr.* = undefined;
            self.free_list.prepend(@ptrCast(@alignCast(ptr)));
        }

        /// Ensures the pool can hold at least `cap` items.
        ///
        /// Reallocates the backing buffer if necessary, potentially
        /// invalidating any item pointers.
        pub fn ensureTotalCapacity(self: *Self, gpa: std.mem.Allocator, cap: usize) !void {
            if (cap <= self.buf.len) return;
            const old_cap = self.buf.len;
            self.buf = try gpa.realloc(self.buf, cap);
            if (populateBuf(self.buf[old_cap..cap]).first) |node|
                self.free_list.prepend(node);
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
            populateBuf(self.buf);
        }

        /// Returns `true` if there are no unused slots in the pool.
        pub fn isFull(self: Self) bool {
            return self.free_list.first == null;
        }

        /// Returns a pointer to the item with the given index.
        pub fn itemPtr(self: *Self, index: usize) *T {
            return &self.buf[@intFromEnum(index)];
        }

        /// Returns a constant pointer to the item with the given index.
        pub fn itemPtrConst(self: Self, index: usize) *const T {
            return &self.buf[@intFromEnum(index)];
        }

        /// Returns the index of the item pointed to by `ptr`.
        ///
        /// Assumes `ptr` is within the backing buffer.
        pub fn itemIndex(self: *Self, ptr: *T) usize {
            return (ptr - self.buf.ptr) / @sizeOf(T);
        }

        /// Populates `buf` with a singly-linked list.
        fn populateBuf(buf: []T) std.SinglyLinkedList {
            var dummy: std.SinglyLinkedList.Node = .{};
            var prev_node: *std.SinglyLinkedList.Node = &dummy;
            for (buf) |*item| {
                const node: *std.SinglyLinkedList.Node = @ptrCast(@alignCast(item));
                node.* = .{};
                prev_node.next = node;
                prev_node = node;
            }

            return .{ .first = dummy.next };
        }
    };
}
