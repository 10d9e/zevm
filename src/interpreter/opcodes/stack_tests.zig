const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const Interpreter = @import("../interpreter.zig").Interpreter;
const ExtBytecode = @import("../interpreter.zig").ExtBytecode;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const stack_ops = @import("stack.zig");

const opPop = stack_ops.opPop;
const opPush0 = stack_ops.opPush0;
const makePushFn = stack_ops.makePushFn;
const makeDupFn = stack_ops.makeDupFn;
const makeSwapFn = stack_ops.makeSwapFn;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;

// --- POP tests ---

test "POP: remove top item" {
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 42));
    interp.stack.pushUnsafe(@as(U, 100));
    var ctx = InstructionContext{ .interpreter = &interp };
    opPop(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 1), interp.stack.len());
    try expectEqual(@as(U, 42), interp.stack.peekUnsafe(0));
}

test "POP: stack underflow" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opPop(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- PUSH0 tests ---

test "PUSH0: pushes zero" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush0(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 1), interp.stack.len());
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "PUSH0: stack overflow" {
    var interp = Interpreter.defaultExt();
    var i: usize = 0;
    while (i < 1024) : (i += 1) interp.stack.pushUnsafe(@as(U, i));
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush0(&ctx);
    try expectEqual(.stack_overflow, interp.result);
}

// --- makePushFn tests (PUSH1..PUSH4 spot checks) ---

test "PUSH1: read 1 byte immediate" {
    const opPush1 = makePushFn(1);
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    // Bytecode: PUSH1 0x42 (but step() already consumed the PUSH1 byte; pc points to 0x42)
    const code = [_]u8{ 0x60, 0x42 }; // PUSH1 0x42
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.bytecode.pc = 1; // simulates step() having advanced past opcode byte
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush1(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 0x42), interp.stack.popUnsafe());
    try expectEqual(@as(usize, 2), interp.bytecode.pc); // advanced by 1
}

test "PUSH2: read 2 byte immediate" {
    const opPush2 = makePushFn(2);
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x61, 0xAB, 0xCD }; // PUSH2 0xABCD
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.bytecode.pc = 1;
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush2(&ctx);
    try expectEqual(@as(U, 0xABCD), interp.stack.popUnsafe());
    try expectEqual(@as(usize, 3), interp.bytecode.pc);
}

test "PUSH4: 4-byte immediate big-endian" {
    const opPush4 = makePushFn(4);
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x63, 0xDE, 0xAD, 0xBE, 0xEF };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.bytecode.pc = 1;
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush4(&ctx);
    try expectEqual(@as(U, 0xDEADBEEF), interp.stack.popUnsafe());
}

test "PUSH1: near end of code (zero padding)" {
    const opPush1 = makePushFn(1);
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    // Only the PUSH1 opcode, no data byte
    const code = [_]u8{0x60};
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.bytecode.pc = 1; // past end
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush1(&ctx);
    // Should push 0 (zero-padded)
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "PUSH1: stack overflow" {
    const opPush1 = makePushFn(1);
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x60, 0x01 };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.bytecode.pc = 1;
    var i: usize = 0;
    while (i < 1024) : (i += 1) interp.stack.pushUnsafe(@as(U, i));
    var ctx = InstructionContext{ .interpreter = &interp };
    opPush1(&ctx);
    try expectEqual(.stack_overflow, interp.result);
}

// --- makeDupFn tests ---

test "DUP1: duplicate top item" {
    const opDup1 = makeDupFn(1);
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 100));
    interp.stack.pushUnsafe(@as(U, 200));
    var ctx = InstructionContext{ .interpreter = &interp };
    opDup1(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 3), interp.stack.len());
    try expectEqual(@as(U, 200), interp.stack.peekUnsafe(0));
    try expectEqual(@as(U, 200), interp.stack.peekUnsafe(1));
    try expectEqual(@as(U, 100), interp.stack.peekUnsafe(2));
}

test "DUP2: duplicate second item" {
    const opDup2 = makeDupFn(2);
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10));
    interp.stack.pushUnsafe(@as(U, 20));
    var ctx = InstructionContext{ .interpreter = &interp };
    opDup2(&ctx);
    try expectEqual(@as(U, 10), interp.stack.peekUnsafe(0));
    try expectEqual(@as(U, 20), interp.stack.peekUnsafe(1));
    try expectEqual(@as(U, 10), interp.stack.peekUnsafe(2));
}

test "DUP1: stack underflow" {
    const opDup1 = makeDupFn(1);
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opDup1(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

test "DUP1: stack overflow" {
    const opDup1 = makeDupFn(1);
    var interp = Interpreter.defaultExt();
    var i: usize = 0;
    while (i < 1024) : (i += 1) interp.stack.pushUnsafe(@as(U, i));
    var ctx = InstructionContext{ .interpreter = &interp };
    opDup1(&ctx);
    try expectEqual(.stack_overflow, interp.result);
}

// --- makeSwapFn tests ---

test "SWAP1: swap top two items" {
    const opSwap1 = makeSwapFn(1);
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10));
    interp.stack.pushUnsafe(@as(U, 20));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSwap1(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 10), interp.stack.peekUnsafe(0));
    try expectEqual(@as(U, 20), interp.stack.peekUnsafe(1));
}

test "SWAP2: swap top with third item" {
    const opSwap2 = makeSwapFn(2);
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 10));
    interp.stack.pushUnsafe(@as(U, 20));
    interp.stack.pushUnsafe(@as(U, 30));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSwap2(&ctx);
    try expectEqual(@as(U, 10), interp.stack.peekUnsafe(0)); // was at depth 2, now top
    try expectEqual(@as(U, 20), interp.stack.peekUnsafe(1));
    try expectEqual(@as(U, 30), interp.stack.peekUnsafe(2)); // was top, now at depth 2
}

test "SWAP1: stack underflow (need 2, have 1)" {
    const opSwap1 = makeSwapFn(1);
    var interp = Interpreter.defaultExt();
    interp.stack.pushUnsafe(@as(U, 1));
    var ctx = InstructionContext{ .interpreter = &interp };
    opSwap1(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}
