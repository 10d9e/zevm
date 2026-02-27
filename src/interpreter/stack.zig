const std = @import("std");
const primitives = @import("primitives");

/// EVM interpreter stack limit.
pub const STACK_LIMIT: usize = 1024;

/// EVM stack with STACK_LIMIT capacity of words.
/// Uses a fixed-size array with no heap allocation.
pub const Stack = struct {
    /// The underlying data of the stack.
    data: [STACK_LIMIT]primitives.U256 = undefined,
    /// Current number of items on the stack.
    length: usize = 0,

    /// Create a new stack
    pub fn new() Stack {
        return Stack{};
    }

    /// Get the length of the stack
    pub fn len(self: *const Stack) usize {
        return self.length;
    }

    /// Get the data slice
    pub fn getData(self: *const Stack) []const primitives.U256 {
        return self.data[0..self.length];
    }

    /// Clear the stack
    pub fn clear(self: *Stack) void {
        self.length = 0;
    }

    // --- Validation helpers ---

    /// Check if the stack has at least n items
    pub fn hasItems(self: *const Stack, n: usize) bool {
        return self.length >= n;
    }

    /// Check if the stack has space for n more items
    pub fn hasSpace(self: *const Stack, n: usize) bool {
        return self.length + n <= STACK_LIMIT;
    }

    // --- Safe methods (with bounds checks) ---

    /// Push a value onto the stack
    pub fn push(self: *Stack, value: primitives.U256) !void {
        if (self.length >= STACK_LIMIT) {
            return error.StackOverflow;
        }
        self.data[self.length] = value;
        self.length += 1;
    }

    /// Pop a value from the stack
    pub fn pop(self: *Stack) ?primitives.U256 {
        if (self.length == 0) {
            return null;
        }
        self.length -= 1;
        return self.data[self.length];
    }

    /// Peek at the top value without removing it
    pub fn peek(self: *const Stack) ?primitives.U256 {
        if (self.length == 0) {
            return null;
        }
        return self.data[self.length - 1];
    }

    /// Peek at a value at a specific depth
    pub fn peekAt(self: *const Stack, depth: usize) ?primitives.U256 {
        if (depth >= self.length) {
            return null;
        }
        return self.data[self.length - 1 - depth];
    }

    /// Pop multiple values from the stack
    pub fn popN(self: *Stack, comptime N: usize) ?[N]primitives.U256 {
        if (self.length < N) {
            return null;
        }

        var result: [N]primitives.U256 = undefined;
        for (0..N) |i| {
            result[i] = self.data[self.length - N + i];
        }

        self.length -= N;
        return result;
    }

    /// Exchange two values on the stack
    pub fn exchange(self: *Stack, n: usize, m: usize) bool {
        if (n >= self.length or m >= self.length) {
            return false;
        }

        const temp = self.data[self.length - 1 - n];
        self.data[self.length - 1 - n] = self.data[self.length - 1 - m];
        self.data[self.length - 1 - m] = temp;

        return true;
    }

    /// Duplicate a value on the stack
    pub fn dup(self: *Stack, n: usize) !void {
        if (n == 0 or n > self.length) {
            return error.InvalidDupIndex;
        }

        if (self.length >= STACK_LIMIT) {
            return error.StackOverflow;
        }

        const value = self.data[self.length - n];
        self.data[self.length] = value;
        self.length += 1;
    }

    /// Push a slice of bytes as a U256
    pub fn pushSlice(self: *Stack, slice: []const u8) !void {
        if (slice.len > 32) {
            return error.InvalidSliceLength;
        }

        var bytes: [32]u8 = [_]u8{0} ** 32;
        @memcpy(bytes[32 - slice.len ..], slice);

        try self.push(@bitCast(bytes));
    }

    /// Set a value at a specific position
    pub fn set(self: *Stack, index: usize, value: primitives.U256) bool {
        if (index >= self.length) {
            return false;
        }

        self.data[self.length - 1 - index] = value;
        return true;
    }

    /// Get a value at a specific position
    pub fn get(self: *const Stack, index: usize) ?primitives.U256 {
        if (index >= self.length) {
            return null;
        }

        return self.data[self.length - 1 - index];
    }

    // --- Unsafe methods (caller must validate first) ---

    /// Push a value without bounds checking
    pub fn pushUnsafe(self: *Stack, value: primitives.U256) void {
        self.data[self.length] = value;
        self.length += 1;
    }

    /// Pop a value without bounds checking
    pub fn popUnsafe(self: *Stack) primitives.U256 {
        self.length -= 1;
        return self.data[self.length];
    }

    /// Peek at a value at a specific depth without bounds checking
    pub fn peekUnsafe(self: *const Stack, depth: usize) primitives.U256 {
        return self.data[self.length - 1 - depth];
    }

    /// Get a mutable pointer to the top value without bounds checking
    pub fn setTopUnsafe(self: *Stack) *primitives.U256 {
        return &self.data[self.length - 1];
    }

    /// Duplicate a value without bounds checking
    pub fn dupUnsafe(self: *Stack, n: usize) void {
        const value = self.data[self.length - n];
        self.data[self.length] = value;
        self.length += 1;
    }

    /// Swap top with nth element without bounds checking
    pub fn swapUnsafe(self: *Stack, n: usize) void {
        const top_idx = self.length - 1;
        const swap_idx = self.length - 1 - n;
        const temp = self.data[top_idx];
        self.data[top_idx] = self.data[swap_idx];
        self.data[swap_idx] = temp;
    }

    /// Shrink the stack by n elements without bounds checking
    pub fn shrinkUnsafe(self: *Stack, n: usize) void {
        self.length -= n;
    }

    /// Format the stack for debugging
    pub fn format(self: *const Stack, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("[");
        for (self.data[0..self.length], 0..) |item, i| {
            if (i > 0) {
                try writer.writeAll(", ");
            }
            try std.fmt.format(writer, "{}", .{item});
        }
        try writer.writeAll("]");
    }
};

// --- Tests ---

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const U = primitives.U256;

test "push and pop" {
    var stack = Stack.new();
    try expectEqual(@as(usize, 0), stack.len());

    try stack.push(@as(U, 1));
    try expectEqual(@as(usize, 1), stack.len());

    const value = stack.pop() orelse return error.StackEmpty;
    try expectEqual(@as(U, 1), value);
}

test "push overflow" {
    var stack = Stack.new();
    for (0..STACK_LIMIT) |i| {
        try stack.push(@as(U, @intCast(i)));
    }
    try expectEqual(@as(usize, STACK_LIMIT), stack.len());
    try std.testing.expectError(error.StackOverflow, stack.push(@as(U, 9999)));
}

test "pop underflow" {
    var stack = Stack.new();
    try expectEqual(@as(?U, null), stack.pop());
}

test "peek" {
    var stack = Stack.new();
    try stack.push(@as(U, 42));
    try expectEqual(@as(U, 42), stack.peek().?);
    try expectEqual(@as(usize, 1), stack.len());
}

test "peek empty" {
    var stack = Stack.new();
    try expectEqual(@as(?U, null), stack.peek());
}

test "peekAt" {
    var stack = Stack.new();
    try stack.push(@as(U, 10));
    try stack.push(@as(U, 20));
    try stack.push(@as(U, 30));
    try expectEqual(@as(U, 30), stack.peekAt(0).?);
    try expectEqual(@as(U, 20), stack.peekAt(1).?);
    try expectEqual(@as(U, 10), stack.peekAt(2).?);
}

test "peekAt out of bounds" {
    var stack = Stack.new();
    try stack.push(@as(U, 1));
    try expectEqual(@as(?U, null), stack.peekAt(1));
    try expectEqual(@as(?U, null), stack.peekAt(100));
}

test "popN" {
    var stack = Stack.new();
    try stack.push(@as(U, 10));
    try stack.push(@as(U, 20));
    try stack.push(@as(U, 30));
    const popped = stack.popN(2) orelse return error.UnexpectedNull;
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 20), popped[0]);
    try expectEqual(@as(U, 30), popped[1]);
}

test "popN underflow" {
    var stack = Stack.new();
    try stack.push(@as(U, 1));
    try stack.push(@as(U, 2));
    try stack.push(@as(U, 3));
    try expect(stack.popN(5) == null);
    try expectEqual(@as(usize, 3), stack.len());
}

test "exchange" {
    var stack = Stack.new();
    try stack.push(@as(U, 10));
    try stack.push(@as(U, 20));
    try stack.push(@as(U, 30));
    try expect(stack.exchange(0, 2));
    try expectEqual(@as(U, 10), stack.peekAt(0).?);
    try expectEqual(@as(U, 30), stack.peekAt(2).?);
    try expectEqual(@as(U, 20), stack.peekAt(1).?);
}

test "exchange out of bounds" {
    var stack = Stack.new();
    try stack.push(@as(U, 1));
    try expect(!stack.exchange(0, 1));
    try expect(!stack.exchange(5, 0));
}

test "dup" {
    var stack = Stack.new();
    try stack.push(@as(U, 100));
    try stack.push(@as(U, 200));
    try stack.dup(1);
    try expectEqual(@as(usize, 3), stack.len());
    try expectEqual(@as(U, 200), stack.peekAt(0).?);
    try expectEqual(@as(U, 200), stack.peekAt(1).?);
    try expectEqual(@as(U, 100), stack.peekAt(2).?);
}

test "dup invalid index" {
    var stack = Stack.new();
    try stack.push(@as(U, 1));
    try std.testing.expectError(error.InvalidDupIndex, stack.dup(0));
    try std.testing.expectError(error.InvalidDupIndex, stack.dup(2));
}

test "set and get" {
    var stack = Stack.new();
    try stack.push(@as(U, 10));
    try stack.push(@as(U, 20));
    try stack.push(@as(U, 30));
    try expectEqual(@as(U, 30), stack.get(0).?);
    try expectEqual(@as(U, 20), stack.get(1).?);
    try expectEqual(@as(U, 10), stack.get(2).?);
    try expect(stack.set(0, @as(U, 99)));
    try expectEqual(@as(U, 99), stack.get(0).?);
    try expectEqual(@as(U, 20), stack.get(1).?);
}

test "set and get out of bounds" {
    var stack = Stack.new();
    try stack.push(@as(U, 1));
    try expectEqual(@as(?U, null), stack.get(1));
    try expectEqual(@as(?U, null), stack.get(100));
    try expect(!stack.set(1, @as(U, 0)));
}

test "pushSlice" {
    var stack = Stack.new();
    const slice = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try stack.pushSlice(&slice);
    try expectEqual(@as(usize, 1), stack.len());
    const val = stack.pop().?;
    const bytes: [32]u8 = @bitCast(val);
    for (bytes[0..28]) |b| {
        try expectEqual(@as(u8, 0), b);
    }
    try expectEqual(@as(u8, 0xDE), bytes[28]);
    try expectEqual(@as(u8, 0xAD), bytes[29]);
    try expectEqual(@as(u8, 0xBE), bytes[30]);
    try expectEqual(@as(u8, 0xEF), bytes[31]);
}

test "pushSlice too long" {
    var stack = Stack.new();
    var buf: [33]u8 = undefined;
    @memset(&buf, 0xFF);
    try std.testing.expectError(error.InvalidSliceLength, stack.pushSlice(&buf));
}

test "clear" {
    var stack = Stack.new();
    try stack.push(@as(U, 1));
    try stack.push(@as(U, 2));
    try stack.push(@as(U, 3));
    try expectEqual(@as(usize, 3), stack.len());
    stack.clear();
    try expectEqual(@as(usize, 0), stack.len());
}

test "getData" {
    var stack = Stack.new();
    try stack.push(@as(U, 10));
    try stack.push(@as(U, 20));
    try stack.push(@as(U, 30));
    const data = stack.getData();
    try expectEqual(@as(usize, 3), data.len);
    try expectEqual(@as(U, 10), data[0]);
    try expectEqual(@as(U, 20), data[1]);
    try expectEqual(@as(U, 30), data[2]);
}

test "hasItems" {
    var stack = Stack.new();
    try expect(stack.hasItems(0));
    try expect(!stack.hasItems(1));
    try stack.push(@as(U, 1));
    try expect(stack.hasItems(1));
    try expect(!stack.hasItems(2));
}

test "hasSpace" {
    var stack = Stack.new();
    try expect(stack.hasSpace(STACK_LIMIT));
    try expect(!stack.hasSpace(STACK_LIMIT + 1));
    try stack.push(@as(U, 1));
    try expect(stack.hasSpace(STACK_LIMIT - 1));
    try expect(!stack.hasSpace(STACK_LIMIT));
}

test "pushUnsafe and popUnsafe LIFO" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 20));
    stack.pushUnsafe(@as(U, 30));
    try expectEqual(@as(usize, 3), stack.len());
    try expectEqual(@as(U, 30), stack.popUnsafe());
    try expectEqual(@as(U, 20), stack.popUnsafe());
    try expectEqual(@as(U, 10), stack.popUnsafe());
    try expectEqual(@as(usize, 0), stack.len());
}

test "peekUnsafe" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 100));
    stack.pushUnsafe(@as(U, 200));
    stack.pushUnsafe(@as(U, 300));
    try expectEqual(@as(U, 300), stack.peekUnsafe(0));
    try expectEqual(@as(U, 200), stack.peekUnsafe(1));
    try expectEqual(@as(U, 100), stack.peekUnsafe(2));
}

test "setTopUnsafe" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 42));
    const ptr = stack.setTopUnsafe();
    try expectEqual(@as(U, 42), ptr.*);
    ptr.* = @as(U, 99);
    try expectEqual(@as(U, 99), stack.popUnsafe());
}

test "dupUnsafe" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 100));
    stack.pushUnsafe(@as(U, 200));
    stack.dupUnsafe(1);
    try expectEqual(@as(usize, 3), stack.len());
    try expectEqual(@as(U, 200), stack.peekUnsafe(0));
    try expectEqual(@as(U, 200), stack.peekUnsafe(1));
    try expectEqual(@as(U, 100), stack.peekUnsafe(2));
}

test "swapUnsafe" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 20));
    stack.pushUnsafe(@as(U, 30));
    stack.swapUnsafe(2);
    try expectEqual(@as(U, 10), stack.peekUnsafe(0));
    try expectEqual(@as(U, 20), stack.peekUnsafe(1));
    try expectEqual(@as(U, 30), stack.peekUnsafe(2));
}

test "shrinkUnsafe" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 20));
    stack.pushUnsafe(@as(U, 30));
    try expectEqual(@as(usize, 3), stack.len());
    stack.shrinkUnsafe(2);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 10), stack.peekUnsafe(0));
}

test "ADD pattern: peek-peek-shrink-overwrite" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 5));
    stack.pushUnsafe(@as(U, 3));
    const a = stack.peekUnsafe(0);
    const b = stack.peekUnsafe(1);
    stack.shrinkUnsafe(1);
    stack.setTopUnsafe().* = a +% b;
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 8), stack.popUnsafe());
}

test "ADDMOD pattern: peek-peek-peek-shrink-overwrite" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 10));
    stack.pushUnsafe(@as(U, 7));
    stack.pushUnsafe(@as(U, 3));
    const n = stack.peekUnsafe(0); // 3
    const b = stack.peekUnsafe(1); // 7
    const a = stack.peekUnsafe(2); // 10
    stack.shrinkUnsafe(2);
    // ADDMOD: (a + b) % N = (10 + 7) % 3 = 2
    stack.setTopUnsafe().* = if (n != @as(U, 0)) (a +% b) % n else @as(U, 0);
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(@as(U, 2), stack.popUnsafe());
}

test "NOT pattern: setTopUnsafe in-place" {
    var stack = Stack.new();
    stack.pushUnsafe(@as(U, 0));
    const ptr = stack.setTopUnsafe();
    ptr.* = ~ptr.*;
    try expectEqual(@as(usize, 1), stack.len());
    try expectEqual(std.math.maxInt(U), stack.popUnsafe());
}
