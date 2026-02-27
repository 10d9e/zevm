const std = @import("std");
const primitives = @import("primitives");

/// EVM memory implementation using a shared buffer
pub const Memory = struct {
    /// The underlying buffer
    buffer: std.ArrayList(u8),
    /// Memory checkpoints for each depth
    checkpoint: usize,
    /// Child checkpoint that we need to free context to
    child_checkpoint: ?usize,
    /// Memory limit
    memory_limit: u64,

    /// Create a new memory instance
    pub fn new() Memory {
        return Memory{
            .buffer = std.ArrayList(u8){ .items = &[_]u8{}, .capacity = 0 },
            .checkpoint = 0,
            .child_checkpoint = null,
            .memory_limit = (1 << 32) - 1, // Default memory limit
        };
    }

    /// Create a new memory instance with a shared buffer
    pub fn newWithBuffer(buffer: std.ArrayList(u8)) Memory {
        return Memory{
            .buffer = buffer,
            .checkpoint = 0,
            .child_checkpoint = null,
            .memory_limit = (1 << 32) - 1,
        };
    }

    /// Deinitialize the memory
    pub fn deinit(self: *Memory) void {
        self.buffer.deinit(std.heap.c_allocator);
    }

    /// Get the current memory size
    pub fn size(self: Memory) usize {
        return self.buffer.items.len;
    }

    /// Get the current memory size in words
    pub fn sizeInWords(self: Memory) usize {
        return (self.buffer.items.len + 31) / 32;
    }

    /// Set data in memory
    pub fn set(self: *Memory, offset: usize, data: []const u8) !void {
        const end_offset = offset + data.len;

        // Check memory limit
        if (end_offset > self.memory_limit) {
            return error.MemoryLimitExceeded;
        }

        // Expand memory if necessary
        if (end_offset > self.buffer.items.len) {
            try self.buffer.resize(std.heap.c_allocator, end_offset);
        }

        // Copy data
        @memcpy(self.buffer.items[offset..end_offset], data);
    }

    /// Set data in memory with source offset
    pub fn setData(self: *Memory, memory_offset: usize, data_offset: usize, len: usize, data: []const u8) !void {
        const end_offset = memory_offset + len;

        // Check memory limit
        if (end_offset > self.memory_limit) {
            return error.MemoryLimitExceeded;
        }

        // Expand memory if necessary
        if (end_offset > self.buffer.items.len) {
            try self.buffer.resize(std.heap.c_allocator, end_offset);
        }

        // Copy data
        @memcpy(self.buffer.items[memory_offset..end_offset], data[data_offset .. data_offset + len]);
    }

    /// Copy data within memory
    pub fn copy(self: *Memory, destination: usize, source: usize, len: usize) !void {
        const end_dest = destination + len;
        const end_src = source + len;

        // Check memory limit
        if (end_dest > self.memory_limit or end_src > self.memory_limit) {
            return error.MemoryLimitExceeded;
        }

        // Expand memory if necessary
        if (end_dest > self.buffer.items.len) {
            try self.buffer.resize(end_dest);
        }

        // Copy data
        @memcpy(self.buffer.items[destination..end_dest], self.buffer.items[source..end_src]);
    }

    /// Get a slice of memory
    pub fn slice(self: Memory, start: usize, end: usize) []const u8 {
        if (end > self.buffer.items.len) {
            return self.buffer.items[start..self.buffer.items.len];
        }
        return self.buffer.items[start..end];
    }

    /// Get a mutable slice of memory
    pub fn sliceMut(self: *Memory, start: usize, end: usize) []u8 {
        if (end > self.buffer.items.len) {
            return self.buffer.items[start..self.buffer.items.len];
        }
        return self.buffer.items[start..end];
    }

    /// Get the local memory offset
    pub fn localMemoryOffset(self: Memory) usize {
        return self.checkpoint;
    }

    /// Set data from global memory
    pub fn setDataFromGlobal(self: *Memory, memory_offset: usize, data_offset: usize, len: usize, data_start: usize, data_end: usize) !void {
        _ = data_end;
        const end_offset = memory_offset + len;

        // Check memory limit
        if (end_offset > self.memory_limit) {
            return error.MemoryLimitExceeded;
        }

        // Expand memory if necessary
        if (end_offset > self.buffer.items.len) {
            try self.buffer.resize(std.heap.c_allocator, end_offset);
        }

        // Copy data from global memory
        const source_start = data_start + data_offset;
        const source_end = source_start + len;

        if (source_end <= self.buffer.items.len) {
            @memcpy(self.buffer.items[memory_offset..end_offset], self.buffer.items[source_start..source_end]);
        }
    }

    /// Load a U256 from memory (big-endian)
    pub fn loadU256(self: Memory, offset: usize) primitives.U256 {
        if (offset + 32 > self.buffer.items.len) {
            // Pad with zeros if beyond memory
            var bytes: [32]u8 = [_]u8{0} ** 32;
            const available = self.buffer.items.len - offset;
            if (available > 0) {
                @memcpy(bytes[0..available], self.buffer.items[offset .. offset + available]);
            }
            return @byteSwap(@as(primitives.U256, @bitCast(bytes)));
        }

        var bytes: [32]u8 = undefined;
        @memcpy(&bytes, self.buffer.items[offset .. offset + 32]);
        return @byteSwap(@as(primitives.U256, @bitCast(bytes)));
    }

    /// Store a U256 to memory (big-endian)
    pub fn storeU256(self: *Memory, offset: usize, value: primitives.U256) !void {
        const bytes: [32]u8 = @bitCast(@byteSwap(value));
        try self.set(offset, &bytes);
    }

    /// Load a U128 from memory
    pub fn loadU128(self: Memory, offset: usize) primitives.U128 {
        if (offset + 16 > self.buffer.items.len) {
            // Pad with zeros if beyond memory
            var bytes: [16]u8 = [_]u8{0} ** 16;
            const available = self.buffer.items.len - offset;
            if (available > 0) {
                @memcpy(bytes[0..available], self.buffer.items[offset .. offset + available]);
            }
            return @bitCast(bytes);
        }

        var bytes: [16]u8 = undefined;
        @memcpy(&bytes, self.buffer.items[offset .. offset + 16]);
        return @bitCast(bytes);
    }

    /// Store a U128 to memory
    pub fn storeU128(self: *Memory, offset: usize, value: primitives.U128) !void {
        const bytes: [16]u8 = @bitCast(value);
        try self.set(offset, &bytes);
    }

    /// Load a U64 from memory
    pub fn loadU64(self: Memory, offset: usize) primitives.U64 {
        if (offset + 8 > self.buffer.items.len) {
            // Pad with zeros if beyond memory
            var bytes: [8]u8 = [_]u8{0} ** 8;
            const available = self.buffer.items.len - offset;
            if (available > 0) {
                @memcpy(bytes[0..available], self.buffer.items[offset .. offset + available]);
            }
            return @bitCast(bytes);
        }

        var bytes: [8]u8 = undefined;
        @memcpy(&bytes, self.buffer.items[offset .. offset + 8]);
        return @bitCast(bytes);
    }

    /// Store a U64 to memory
    pub fn storeU64(self: *Memory, offset: usize, value: primitives.U64) !void {
        const bytes: [8]u8 = @bitCast(value);
        try self.set(offset, &bytes);
    }

    /// Load a U32 from memory
    pub fn loadU32(self: Memory, offset: usize) primitives.U32 {
        if (offset + 4 > self.buffer.items.len) {
            // Pad with zeros if beyond memory
            var bytes: [4]u8 = [_]u8{0} ** 4;
            const available = self.buffer.items.len - offset;
            if (available > 0) {
                @memcpy(bytes[0..available], self.buffer.items[offset .. offset + available]);
            }
            return @bitCast(bytes);
        }

        var bytes: [4]u8 = undefined;
        @memcpy(&bytes, self.buffer.items[offset .. offset + 4]);
        return @bitCast(bytes);
    }

    /// Store a U32 to memory
    pub fn storeU32(self: *Memory, offset: usize, value: primitives.U32) !void {
        const bytes: [4]u8 = @bitCast(value);
        try self.set(offset, &bytes);
    }

    /// Load a U16 from memory
    pub fn loadU16(self: Memory, offset: usize) primitives.U16 {
        if (offset + 2 > self.buffer.items.len) {
            // Pad with zeros if beyond memory
            var bytes: [2]u8 = [_]u8{0} ** 2;
            const available = self.buffer.items.len - offset;
            if (available > 0) {
                @memcpy(bytes[0..available], self.buffer.items[offset .. offset + available]);
            }
            return @bitCast(bytes);
        }

        var bytes: [2]u8 = undefined;
        @memcpy(&bytes, self.buffer.items[offset .. offset + 2]);
        return @bitCast(bytes);
    }

    /// Store a U16 to memory
    pub fn storeU16(self: *Memory, offset: usize, value: primitives.U16) !void {
        const bytes: [2]u8 = @bitCast(value);
        try self.set(offset, &bytes);
    }

    /// Load a U8 from memory
    pub fn loadU8(self: Memory, offset: usize) primitives.U8 {
        if (offset >= self.buffer.items.len) {
            return primitives.U8.zero();
        }

        return primitives.U8.from(self.buffer.items[offset]);
    }

    /// Store a U8 to memory
    pub fn storeU8(self: *Memory, offset: usize, value: primitives.U8) !void {
        const byte = value.to();
        try self.set(offset, &[_]u8{byte});
    }

    /// Calculate memory expansion cost
    pub fn expansionCost(self: Memory, new_size: usize) u64 {
        if (new_size <= self.buffer.items.len) {
            return 0;
        }

        const new_words = (new_size + 31) / 32;
        const current_words = (self.buffer.items.len + 31) / 32;

        if (new_words <= current_words) {
            return 0;
        }

        const cost = (new_words * new_words) / 512 + (3 * new_words);
        const current_cost = (current_words * current_words) / 512 + (3 * current_words);

        return cost - current_cost;
    }

    /// Resize memory to a new size
    pub fn resize(self: *Memory, new_size: usize) !void {
        if (new_size > self.memory_limit) {
            return error.MemoryLimitExceeded;
        }

        try self.buffer.resize(new_size);
    }

    /// Clear memory
    pub fn clear(self: *Memory) void {
        self.buffer.clearRetainingCapacity();
        self.checkpoint = 0;
        self.child_checkpoint = null;
    }

    /// Set memory limit
    pub fn setMemoryLimit(self: *Memory, limit: u64) void {
        self.memory_limit = limit;
    }

    /// Get memory limit
    pub fn getMemoryLimit(self: Memory) u64 {
        return self.memory_limit;
    }
};
