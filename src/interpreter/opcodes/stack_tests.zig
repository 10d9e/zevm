const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const stack_ops = @import("stack.zig");

const opPop = stack_ops.opPop;
const opPush0 = stack_ops.opPush0;
const opPushN = stack_ops.opPushN;
const opDupN = stack_ops.opDupN;
const opSwapN = stack_ops.opSwapN;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;

// --- POP tests ---

test "POP: remove top item" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    stack.pushUnsafe(U.from(100));
    const result = opPop(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expect(stack.peekUnsafe(0).eql(U.from(42)));
    try expectEqual(@as(u64, 98), gas.getRemaining());
}

test "POP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opPop(&stack, &gas);
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "POP: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(1); // Not enough gas
    stack.pushUnsafe(U.ONE);
    const result = opPop(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- PUSH0 tests ---

test "PUSH0: push zero onto stack" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opPush0(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 1), stack.len());
    try expect(stack.popUnsafe().eql(U.ZERO));
    try expectEqual(@as(u64, 98), gas.getRemaining());
}

test "PUSH0: stack overflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    // Fill stack to max capacity (1024)
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        stack.pushUnsafe(U.from(i));
    }
    const result = opPush0(&stack, &gas);
    try expectEqual(InstructionResult.stack_overflow, result);
}

// --- PUSH1-PUSH32 tests ---

test "PUSH1: push 1 byte" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;
    const bytecode = [_]u8{ 0x60, 0x42 }; // PUSH1 0x42
    const result = opPushN(&stack, &gas, &bytecode, &pc, 1);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.from(0x42)));
    try expectEqual(@as(usize, 1), pc); // PC advanced by 1
}

test "PUSH2: push 2 bytes" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;
    const bytecode = [_]u8{ 0x61, 0x12, 0x34 }; // PUSH2 0x1234
    const result = opPushN(&stack, &gas, &bytecode, &pc, 2);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.from(0x1234)));
    try expectEqual(@as(usize, 2), pc);
}

test "PUSH4: push 4 bytes" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;
    const bytecode = [_]u8{ 0x63, 0xDE, 0xAD, 0xBE, 0xEF }; // PUSH4 0xDEADBEEF
    const result = opPushN(&stack, &gas, &bytecode, &pc, 4);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.from(0xDEADBEEF)));
    try expectEqual(@as(usize, 4), pc);
}

test "PUSH32: push 32 bytes" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;
    var bytecode: [33]u8 = undefined;
    bytecode[0] = 0x7F; // PUSH32 opcode
    var i: usize = 1;
    while (i <= 32) : (i += 1) {
        bytecode[i] = @as(u8, @intCast(i));
    }
    const result = opPushN(&stack, &gas, &bytecode, &pc, 32);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 32), pc);
}

test "PUSH: not enough bytecode" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;
    const bytecode = [_]u8{ 0x61, 0x12 }; // PUSH2 but only 1 byte available
    const result = opPushN(&stack, &gas, &bytecode, &pc, 2);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.from(0x12))); // Should push partial data
}

// --- DUP tests ---

test "DUP1: duplicate top item" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(42));
    const result = opDupN(&stack, &gas, 1);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 2), stack.len());
    try expect(stack.peekUnsafe(0).eql(U.from(42)));
    try expect(stack.peekUnsafe(1).eql(U.from(42)));
}

test "DUP2: duplicate second item" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(20));
    const result = opDupN(&stack, &gas, 2);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 3), stack.len());
    try expect(stack.peekUnsafe(0).eql(U.from(10))); // Duplicated
    try expect(stack.peekUnsafe(1).eql(U.from(20)));
    try expect(stack.peekUnsafe(2).eql(U.from(10)));
}

test "DUP16: duplicate 16th item" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var i: u8 = 0;
    while (i < 16) : (i += 1) {
        stack.pushUnsafe(U.from(i));
    }
    const result = opDupN(&stack, &gas, 16);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 17), stack.len());
    try expect(stack.peekUnsafe(0).eql(U.ZERO)); // Duplicated 16th item
}

test "DUP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.ONE);
    const result = opDupN(&stack, &gas, 2); // Need 2 items, only have 1
    try expectEqual(InstructionResult.stack_underflow, result);
}

test "DUP: stack overflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    // Fill stack to max capacity
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        stack.pushUnsafe(U.from(i));
    }
    const result = opDupN(&stack, &gas, 1);
    try expectEqual(InstructionResult.stack_overflow, result);
}

// --- SWAP tests ---

test "SWAP1: swap top two items" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(20));
    const result = opSwapN(&stack, &gas, 1);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.peekUnsafe(0).eql(U.from(10)));
    try expect(stack.peekUnsafe(1).eql(U.from(20)));
}

test "SWAP2: swap top with 3rd item" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.from(10));
    stack.pushUnsafe(U.from(20));
    stack.pushUnsafe(U.from(30));
    const result = opSwapN(&stack, &gas, 2);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.peekUnsafe(0).eql(U.from(10))); // Was 3rd
    try expect(stack.peekUnsafe(1).eql(U.from(20))); // Unchanged
    try expect(stack.peekUnsafe(2).eql(U.from(30))); // Was top
}

test "SWAP16: swap top with 17th item" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var i: u8 = 0;
    while (i < 17) : (i += 1) {
        stack.pushUnsafe(U.from(i));
    }
    const result = opSwapN(&stack, &gas, 16);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.peekUnsafe(0).eql(U.ZERO)); // Was 17th
    try expect(stack.peekUnsafe(16).eql(U.from(16))); // Was top
}

test "SWAP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    stack.pushUnsafe(U.ONE);
    const result = opSwapN(&stack, &gas, 1); // Need 2 items, only have 1
    try expectEqual(InstructionResult.stack_underflow, result);
}
