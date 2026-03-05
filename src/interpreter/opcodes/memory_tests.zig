const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Memory = @import("../memory.zig").Memory;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const memory_ops = @import("memory.zig");

const opMload = memory_ops.opMload;
const opMstore = memory_ops.opMstore;
const opMstore8 = memory_ops.opMstore8;
const opMsize = memory_ops.opMsize;
const opMcopy = memory_ops.opMcopy;

const expectEqual = std.testing.expectEqual;
const U = primitives.U256;

// --- MLOAD tests ---

test "MLOAD: load from memory offset 0" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Pre-fill memory with some data
    try memory.buffer.resize(std.heap.c_allocator, 64);
    @memset(memory.buffer.items[0..32], 0x42);

    stack.pushUnsafe(@as(U, 0)); // Offset 0
    const result = opMload(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Should load 32 bytes of 0x42
    const value = stack.popUnsafe();
    var expected: U = 0;
    var i: u8 = 0;
    while (i < 32) : (i += 1) {
        expected = (expected << 8) | 0x42;
    }
    try expectEqual(expected, value);
}

test "MLOAD: expand memory" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 32)); // Load from offset 32
    const result = opMload(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 64), memory.size()); // Should expand to 64 bytes
}

test "MLOAD: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    const result = opMload(&stack, &gas, &memory);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "MLOAD: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(2); // Not enough gas
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0));
    const result = opMload(&stack, &gas, &memory);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- MSTORE tests ---

test "MSTORE: store 32 bytes" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0x123456789ABCDEF)); // Value
    stack.pushUnsafe(@as(U, 0)); // Offset
    const result = opMstore(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 32), memory.size());

    // Verify the value was stored (big-endian)
    const stored = memory.buffer.items[24..32];
    try expectEqual(@as(u8, 0x01), stored[0]);
    try expectEqual(@as(u8, 0xEF), stored[7]);
}

test "MSTORE: expand memory" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 42));
    stack.pushUnsafe(@as(U, 64)); // Offset 64
    const result = opMstore(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 96), memory.size()); // 64 + 32
}

test "MSTORE: overwrite existing data" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // First store
    stack.pushUnsafe(@as(U, 0xFF));
    stack.pushUnsafe(@as(U, 0));
    _ = opMstore(&stack, &gas, &memory);

    // Second store (overwrite)
    stack.pushUnsafe(@as(U, 0xAA));
    stack.pushUnsafe(@as(U, 0));
    const result = opMstore(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Verify new value
    try expectEqual(@as(u8, 0xAA), memory.buffer.items[31]);
}

test "MSTORE: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0)); // Only 1 value, need 2
    const result = opMstore(&stack, &gas, &memory);
    try expectEqual(InstructionResult.stack_underflow, result);
}

// --- MSTORE8 tests ---

test "MSTORE8: store single byte" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0x12345)); // Value (only lowest byte stored)
    stack.pushUnsafe(@as(U, 10)); // Offset
    const result = opMstore8(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(u8, 0x45), memory.buffer.items[10]);
}

test "MSTORE8: only lowest byte" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF42));
    stack.pushUnsafe(@as(U, 0));
    const result = opMstore8(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(u8, 0x42), memory.buffer.items[0]);
}

test "MSTORE8: expand memory" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0xFF));
    stack.pushUnsafe(@as(U, 100));
    const result = opMstore8(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 101), memory.size());
}

// --- MSIZE tests ---

test "MSIZE: empty memory" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var memory = Memory.new();
    defer memory.deinit();

    const result = opMsize(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "MSIZE: after expansion" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Expand memory
    try memory.buffer.resize(std.heap.c_allocator, 128);

    const result = opMsize(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 128), stack.popUnsafe());
}

test "MSIZE: stack overflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var memory = Memory.new();
    defer memory.deinit();

    // Fill stack
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        stack.pushUnsafe(@as(U, i));
    }

    const result = opMsize(&stack, &gas, &memory);
    try expectEqual(InstructionResult.stack_overflow, result);
}

// --- MCOPY tests ---

test "MCOPY: basic copy" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Pre-fill source memory
    try memory.buffer.resize(std.heap.c_allocator, 64);
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        memory.buffer.items[i] = @as(u8, @intCast(i));
    }

    stack.pushUnsafe(@as(U, 16)); // Length
    stack.pushUnsafe(@as(U, 0)); // Source offset
    stack.pushUnsafe(@as(U, 32)); // Dest offset
    const result = opMcopy(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Verify copy
    i = 0;
    while (i < 16) : (i += 1) {
        try expectEqual(memory.buffer.items[i], memory.buffer.items[32 + i]);
    }
}

test "MCOPY: overlapping regions" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Pre-fill memory
    try memory.buffer.resize(std.heap.c_allocator, 64);
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        memory.buffer.items[i] = @as(u8, @intCast(i + 1));
    }

    // Copy overlapping: src=0, dest=16, len=16
    stack.pushUnsafe(@as(U, 16)); // Length
    stack.pushUnsafe(@as(U, 0)); // Source
    stack.pushUnsafe(@as(U, 16)); // Dest
    const result = opMcopy(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Verify forward copy worked correctly
    i = 0;
    while (i < 16) : (i += 1) {
        try expectEqual(@as(u8, @intCast(i + 1)), memory.buffer.items[16 + i]);
    }
}

test "MCOPY: zero length" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0)); // Length = 0
    stack.pushUnsafe(@as(U, 0)); // Source
    stack.pushUnsafe(@as(U, 0)); // Dest
    const result = opMcopy(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
}

test "MCOPY: expand memory" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 32)); // Length
    stack.pushUnsafe(@as(U, 0)); // Source
    stack.pushUnsafe(@as(U, 64)); // Dest (beyond current size)
    const result = opMcopy(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 96), memory.size()); // 64 + 32
}

test "MCOPY: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(@as(U, 0));
    stack.pushUnsafe(@as(U, 0)); // Only 2 values, need 3
    const result = opMcopy(&stack, &gas, &memory);
    try expectEqual(InstructionResult.stack_underflow, result);
}
