const std = @import("std");
const primitives = @import("primitives");
const Interpreter = @import("../interpreter.zig").Interpreter;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const Gas = @import("../gas.zig").Gas;
const keccak_ops = @import("keccak.zig");

const opKeccak256 = keccak_ops.opKeccak256;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;

// --- KECCAK256 tests ---

test "KECCAK256: empty input" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0)); // length 0
    interp.stack.pushUnsafe(@as(U, 0)); // offset 0
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expect(interp.bytecode.continue_execution);
    // Keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
    const expected: U = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    try expectEqual(expected, interp.stack.popUnsafe());
}

test "KECCAK256: single byte" {
    var interp = Interpreter.defaultExt();
    // Pre-fill memory with 0x00 at offset 0
    try interp.memory.buffer.resize(std.heap.c_allocator, 32);
    interp.memory.buffer.items[0] = 0x00;
    interp.stack.pushUnsafe(@as(U, 1)); // length 1
    interp.stack.pushUnsafe(@as(U, 0)); // offset 0
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expect(interp.bytecode.continue_execution);
    // Keccak256(0x00) = 0xbc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a
    const expected: U = 0xbc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a;
    try expectEqual(expected, interp.stack.popUnsafe());
}

test "KECCAK256: hello" {
    var interp = Interpreter.defaultExt();
    try interp.memory.buffer.resize(std.heap.c_allocator, 32);
    const hello = "hello";
    @memcpy(interp.memory.buffer.items[0..hello.len], hello);
    interp.stack.pushUnsafe(@as(U, 5)); // length 5
    interp.stack.pushUnsafe(@as(U, 0)); // offset 0
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    // Keccak256("hello") = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
    const expected: U = 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8;
    try expectEqual(expected, interp.stack.popUnsafe());
}

test "KECCAK256: dynamic word gas (64 bytes = 2 words = 12 gas)" {
    // Handler charges G_KECCAK256WORD * num_words = 6 * 2 = 12
    // Static G_KECCAK256 = 30 is charged by dispatch, not here
    var interp = Interpreter.defaultExt();
    interp.gas = Gas.new(1000);
    try interp.memory.buffer.resize(std.heap.c_allocator, 64);
    var i: usize = 0;
    while (i < 64) : (i += 1) interp.memory.buffer.items[i] = @as(u8, @intCast(i));
    interp.stack.pushUnsafe(@as(U, 64)); // length 64
    interp.stack.pushUnsafe(@as(U, 0)); // offset 0
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(u64, 988), interp.gas.remaining); // 1000 - 12
}

test "KECCAK256: dynamic word gas (100 bytes = ceil(100/32)=4 words = 24 gas)" {
    var interp = Interpreter.defaultExt();
    interp.gas = Gas.new(1000);
    try interp.memory.buffer.resize(std.heap.c_allocator, 100);
    interp.stack.pushUnsafe(@as(U, 100));
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(u64, 976), interp.gas.remaining); // 1000 - 24
}

test "KECCAK256: auto-expands memory" {
    // keccak256 should expand memory itself, unlike old implementation
    var interp = Interpreter.defaultExt();
    // Memory is empty, but we hash 32 bytes at offset 0
    interp.stack.pushUnsafe(@as(U, 32)); // length 32
    interp.stack.pushUnsafe(@as(U, 0)); // offset 0
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expect(interp.bytecode.continue_execution);
    // Memory should have been expanded to at least 32 bytes
    try expect(interp.memory.size() >= 32);
}

test "KECCAK256: out of gas on word cost" {
    // Give less than 1 word cost (6 gas) for a 32-byte hash
    var interp = Interpreter.defaultExt();
    interp.gas = Gas.new(3); // less than G_KECCAK256WORD = 6
    try interp.memory.buffer.resize(std.heap.c_allocator, 32);
    interp.stack.pushUnsafe(@as(U, 32)); // 1 word
    interp.stack.pushUnsafe(@as(U, 0));
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.out_of_gas, interp.result);
}

test "KECCAK256: stack underflow" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 0)); // only 1 value, need 2
    var ctx = InstructionContext{ .interpreter = &interp };
    opKeccak256(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

test "KECCAK256: deterministic" {
    // Two separate interpreters hashing the same data should produce the same result
    var interp1 = Interpreter.defaultExt();
    try interp1.memory.buffer.resize(std.heap.c_allocator, 10);
    const data = "test";
    @memcpy(interp1.memory.buffer.items[0..data.len], data);
    interp1.stack.pushUnsafe(@as(U, 4));
    interp1.stack.pushUnsafe(@as(U, 0));
    var ctx1 = InstructionContext{ .interpreter = &interp1 };
    opKeccak256(&ctx1);
    const hash1 = interp1.stack.popUnsafe();

    var interp2 = Interpreter.defaultExt();
    try interp2.memory.buffer.resize(std.heap.c_allocator, 10);
    @memcpy(interp2.memory.buffer.items[0..data.len], data);
    interp2.stack.pushUnsafe(@as(U, 4));
    interp2.stack.pushUnsafe(@as(U, 0));
    var ctx2 = InstructionContext{ .interpreter = &interp2 };
    opKeccak256(&ctx2);
    const hash2 = interp2.stack.popUnsafe();

    try expectEqual(hash1, hash2);
}
