const std = @import("std");
const primitives = @import("primitives");
const Interpreter = @import("../interpreter.zig").Interpreter;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const Gas = @import("../gas.zig").Gas;
const memory_ops = @import("memory.zig");

const opMload = memory_ops.opMload;
const opMstore = memory_ops.opMstore;
const opMstore8 = memory_ops.opMstore8;
const opMsize = memory_ops.opMsize;
const opMcopy = memory_ops.opMcopy;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;

// --- MLOAD tests ---

test "MLOAD: load from offset 0" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    try interp.memory.buffer.resize(std.heap.c_allocator, 64);
    @memset(interp.memory.buffer.items[0..32], 0x42);
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMload(&ctx);
    try expect(interp.bytecode.continue_execution);
    // Load 32 bytes of 0x42 as big-endian U256
    var expected: U = 0;
    var i: u8 = 0;
    while (i < 32) : (i += 1) expected = (expected << 8) | 0x42;
    try expectEqual(expected, interp.stack.popUnsafe());
}

test "MLOAD: auto-expands memory" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 32)); // load from offset 32
    var ctx = InstructionContext{ .interpreter = &interp };
    opMload(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 64), interp.memory.size());
}

test "MLOAD: memory expansion charges gas" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.gas = Gas.new(1000);
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMload(&ctx);
    // Memory expansion from 0 to 32 bytes (1 word): cost = 1*3 + 1/512 = 3
    try expectEqual(@as(u64, 997), interp.gas.remaining);
}

test "MLOAD: stack underflow" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    var ctx = InstructionContext{ .interpreter = &interp };
    opMload(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

test "MLOAD: out of gas on memory expansion" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.gas = Gas.new(0); // zero gas, expansion costs at least 3
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMload(&ctx);
    try expectEqual(.out_of_gas, interp.result);
}

// --- MSTORE tests ---

test "MSTORE: store 32 bytes" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 0x123456789ABCDEF)); // value
    interp.stack.pushUnsafe(@as(U, 0)); // offset
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 32), interp.memory.size());
    // Verify big-endian storage
    try expectEqual(@as(u8, 0x01), interp.memory.buffer.items[24]);
    try expectEqual(@as(u8, 0xEF), interp.memory.buffer.items[31]);
}

test "MSTORE: expand memory to cover offset + 32" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 42)); // value
    interp.stack.pushUnsafe(@as(U, 64)); // offset 64
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore(&ctx);
    try expectEqual(@as(usize, 96), interp.memory.size());
}

test "MSTORE: overwrite existing data" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    // First store
    interp.stack.pushUnsafe(@as(U, 0xFF));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore(&ctx);
    // Second store (overwrite)
    interp.stack.pushUnsafe(@as(U, 0xAA));
    interp.stack.pushUnsafe(@as(U, 0));
    opMstore(&ctx);
    try expectEqual(@as(u8, 0xAA), interp.memory.buffer.items[31]);
}

test "MSTORE: stack underflow" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 0)); // only 1 value, need 2
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- MSTORE8 tests ---

test "MSTORE8: store lowest byte" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 0x12345)); // only 0x45 stored
    interp.stack.pushUnsafe(@as(U, 10)); // offset 10
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore8(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(u8, 0x45), interp.memory.buffer.items[10]);
}

test "MSTORE8: only lowest byte (large value)" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF42));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore8(&ctx);
    try expectEqual(@as(u8, 0x42), interp.memory.buffer.items[0]);
}

test "MSTORE8: auto-expands memory" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 0xFF));
    interp.stack.pushUnsafe(@as(U, 100)); // offset 100
    var ctx = InstructionContext{ .interpreter = &interp };
    opMstore8(&ctx);
    try expectEqual(@as(usize, 128), interp.memory.size()); // EVM memory is 32-byte aligned: ceil(101/32)*32 = 128
}

// --- MSIZE tests ---

test "MSIZE: empty memory = 0" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    var ctx = InstructionContext{ .interpreter = &interp };
    opMsize(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "MSIZE: after expansion" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    try interp.memory.buffer.resize(std.heap.c_allocator, 128);
    var ctx = InstructionContext{ .interpreter = &interp };
    opMsize(&ctx);
    try expectEqual(@as(U, 128), interp.stack.popUnsafe());
}

test "MSIZE: stack overflow" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) interp.stack.pushUnsafe(@as(U, i));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMsize(&ctx);
    try expectEqual(.stack_overflow, interp.result);
}

// --- MCOPY tests ---

test "MCOPY: basic copy" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    try interp.memory.buffer.resize(std.heap.c_allocator, 64);
    @memset(interp.memory.buffer.items[0..32], 0xAB);
    @memset(interp.memory.buffer.items[32..64], 0x00);
    // Copy 32 bytes from offset 0 to offset 32
    interp.stack.pushUnsafe(@as(U, 32)); // length
    interp.stack.pushUnsafe(@as(U, 0)); // src
    interp.stack.pushUnsafe(@as(U, 32)); // dest
    var ctx = InstructionContext{ .interpreter = &interp };
    opMcopy(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(u8, 0xAB), interp.memory.buffer.items[32]);
    try expectEqual(@as(u8, 0xAB), interp.memory.buffer.items[63]);
}

test "MCOPY: overlapping regions (forward)" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    try interp.memory.buffer.resize(std.heap.c_allocator, 64);
    for (interp.memory.buffer.items, 0..) |*b, i| b.* = @as(u8, @intCast(i & 0xFF));
    // Copy 10 bytes from offset 5 to offset 0 (overlapping)
    interp.stack.pushUnsafe(@as(U, 10)); // length
    interp.stack.pushUnsafe(@as(U, 5)); // src
    interp.stack.pushUnsafe(@as(U, 0)); // dest
    var ctx = InstructionContext{ .interpreter = &interp };
    opMcopy(&ctx);
    try expect(interp.bytecode.continue_execution);
    // dest[0] should be original src[5] = 5
    try expectEqual(@as(u8, 5), interp.memory.buffer.items[0]);
}

test "MCOPY: stack underflow" {
    var interp = Interpreter.defaultExt();
    defer interp.memory.deinit();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opMcopy(&ctx); // only 2 items, need 3
    try expectEqual(.stack_underflow, interp.result);
}
