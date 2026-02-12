const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Memory = @import("../memory.zig").Memory;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const keccak_ops = @import("keccak.zig");

const opKeccak256 = keccak_ops.opKeccak256;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;

// --- KECCAK256 tests ---

test "KECCAK256: empty input" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(U.ZERO); // Length 0
    stack.pushUnsafe(U.ZERO); // Offset 0
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
    const expected = U.fromNative(0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470);
    const hash = stack.popUnsafe();
    try expect(hash.eql(expected));
}

test "KECCAK256: single byte" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Store 0x00 at offset 0
    try memory.buffer.resize(std.heap.c_allocator, 32);
    memory.buffer.items[0] = 0x00;

    stack.pushUnsafe(U.ONE); // Length 1
    stack.pushUnsafe(U.ZERO); // Offset 0
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Keccak256(0x00) = 0xbc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a
    const expected = U.fromNative(0xbc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a);
    const hash = stack.popUnsafe();
    try expect(hash.eql(expected));
}

test "KECCAK256: multiple bytes" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Store "hello" in memory
    try memory.buffer.resize(std.heap.c_allocator, 32);
    const hello = "hello";
    @memcpy(memory.buffer.items[0..hello.len], hello);

    stack.pushUnsafe(U.from(5)); // Length 5
    stack.pushUnsafe(U.ZERO); // Offset 0
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Keccak256("hello") = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
    const expected = U.fromNative(0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8);
    const hash = stack.popUnsafe();
    try expect(hash.eql(expected));
}

test "KECCAK256: 32 bytes (one word)" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Fill 32 bytes with 0xFF
    try memory.buffer.resize(std.heap.c_allocator, 32);
    @memset(memory.buffer.items[0..32], 0xFF);

    stack.pushUnsafe(U.from(32)); // Length 32
    stack.pushUnsafe(U.ZERO); // Offset 0
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Should produce some hash (exact value not critical, just verify it runs)
    const hash = stack.popUnsafe();
    try expect(!hash.isZero());
}

test "KECCAK256: 64 bytes (two words)" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Fill 64 bytes
    try memory.buffer.resize(std.heap.c_allocator, 64);
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        memory.buffer.items[i] = @as(u8, @intCast(i));
    }

    stack.pushUnsafe(U.from(64)); // Length 64
    stack.pushUnsafe(U.ZERO); // Offset 0

    const initial_gas = gas.getRemaining();
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    // Verify gas cost: 30 + 6*2 = 42
    const gas_used = initial_gas - gas.getRemaining();
    try expectEqual(@as(u64, 42), gas_used);
}

test "KECCAK256: offset in middle of memory" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Pre-fill memory
    try memory.buffer.resize(std.heap.c_allocator, 64);
    @memset(memory.buffer.items[0..32], 0xAA);
    @memset(memory.buffer.items[32..64], 0xBB);

    // Hash the second half
    stack.pushUnsafe(U.from(32)); // Length 32
    stack.pushUnsafe(U.from(32)); // Offset 32
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    const hash = stack.popUnsafe();
    try expect(!hash.isZero());
}

test "KECCAK256: gas cost calculation" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    try memory.buffer.resize(std.heap.c_allocator, 100);

    // 100 bytes = ceil(100/32) = 4 words
    // Gas cost = 30 + 6*4 = 54
    stack.pushUnsafe(U.from(100)); // Length
    stack.pushUnsafe(U.ZERO); // Offset

    const initial_gas = gas.getRemaining();
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    const gas_used = initial_gas - gas.getRemaining();
    try expectEqual(@as(u64, 54), gas_used);
}

test "KECCAK256: partial word" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    try memory.buffer.resize(std.heap.c_allocator, 10);

    // 10 bytes = ceil(10/32) = 1 word
    // Gas cost = 30 + 6*1 = 36
    stack.pushUnsafe(U.from(10)); // Length
    stack.pushUnsafe(U.ZERO); // Offset

    const initial_gas = gas.getRemaining();
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.continue_, result);

    const gas_used = initial_gas - gas.getRemaining();
    try expectEqual(@as(u64, 36), gas_used);
}

// --- Error conditions ---

test "KECCAK256: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(U.ZERO); // Only 1 value, need 2
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "KECCAK256: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(20); // Not enough gas (need 30 + 6*words)
    var memory = Memory.new();
    defer memory.deinit();

    stack.pushUnsafe(U.ZERO);
    stack.pushUnsafe(U.ZERO);
    const result = opKeccak256(&stack, &gas, &memory);
    try expectEqual(InstructionResult.out_of_gas, result);
}

test "KECCAK256: memory limit exceeded" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    var memory = Memory.new();
    defer memory.deinit();

    // Try to hash beyond memory size
    stack.pushUnsafe(U.from(100)); // Length 100
    stack.pushUnsafe(U.ZERO); // Offset 0
    const result = opKeccak256(&stack, &gas, &memory);
    // Should fail because memory isn't expanded yet
    try expectEqual(InstructionResult.memory_limit_oog, result);
}

test "KECCAK256: deterministic" {
    var stack1 = Stack.new();
    var gas1 = Gas.new(1000);
    var memory1 = Memory.new();
    defer memory1.deinit();

    // First hash
    try memory1.buffer.resize(std.heap.c_allocator, 10);
    const data = "test";
    @memcpy(memory1.buffer.items[0..data.len], data);
    stack1.pushUnsafe(U.from(4));
    stack1.pushUnsafe(U.ZERO);
    _ = opKeccak256(&stack1, &gas1, &memory1);
    const hash1 = stack1.popUnsafe();

    // Second hash (same data)
    var stack2 = Stack.new();
    var gas2 = Gas.new(1000);
    var memory2 = Memory.new();
    defer memory2.deinit();

    try memory2.buffer.resize(std.heap.c_allocator, 10);
    @memcpy(memory2.buffer.items[0..data.len], data);
    stack2.pushUnsafe(U.from(4));
    stack2.pushUnsafe(U.ZERO);
    _ = opKeccak256(&stack2, &gas2, &memory2);
    const hash2 = stack2.popUnsafe();

    // Should be identical
    try expectEqual(hash1, hash2);
}
