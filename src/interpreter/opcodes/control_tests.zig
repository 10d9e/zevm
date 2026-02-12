const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const Bytecode = bytecode_mod.Bytecode;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const control = @import("control.zig");

const opStop = control.opStop;
const opJump = control.opJump;
const opJumpi = control.opJumpi;
const opJumpdest = control.opJumpdest;
const opPc = control.opPc;
const opGas = control.opGas;

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;
const U = primitives.U256;

// --- STOP tests ---

test "STOP: halts execution" {
    var gas = Gas.new(100);
    const result = opStop(&gas);
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(u64, 99), gas.getRemaining());
}

test "STOP: out of gas" {
    var gas = Gas.new(0);
    const result = opStop(&gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- JUMPDEST tests ---

test "JUMPDEST: valid jump destination" {
    var gas = Gas.new(100);
    const result = opJumpdest(&gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(u64, 99), gas.getRemaining());
}

test "JUMPDEST: out of gas" {
    var gas = Gas.new(0);
    const result = opJumpdest(&gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- PC tests ---

test "PC: push program counter" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const pc: usize = 42;
    const result = opPc(&stack, &gas, pc);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.from(42)));
    try expectEqual(@as(u64, 98), gas.getRemaining());
}

test "PC: zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const pc: usize = 0;
    const result = opPc(&stack, &gas, pc);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "PC: large value" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const pc: usize = 12345;
    const result = opPc(&stack, &gas, pc);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.from(12345)));
}

test "PC: stack overflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    // Fill stack to max capacity
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        stack.pushUnsafe(U.from(i));
    }
    const result = opPc(&stack, &gas, 0);
    try expectEqual(InstructionResult.stack_overflow, result);
}

// --- GAS tests ---

test "GAS: push remaining gas" {
    var stack = Stack.new();
    var gas = Gas.new(1000);
    const result = opGas(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    // After spending GAS_BASE (2), remaining should be 998
    try expect(stack.popUnsafe().eql(U.from(998)));
    try expectEqual(@as(u64, 998), gas.getRemaining());
}

test "GAS: zero gas remaining" {
    var stack = Stack.new();
    var gas = Gas.new(2); // Exactly enough for GAS opcode
    const result = opGas(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expect(stack.popUnsafe().eql(U.ZERO));
}

test "GAS: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(1); // Not enough gas
    const result = opGas(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- JUMP tests ---

test "JUMP: valid jump to JUMPDEST" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    // Create bytecode: JUMPDEST at position 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B }; // 0x5B = JUMPDEST
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.from(5)); // Jump to position 5
    const result = opJump(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 5), pc);
    try expectEqual(@as(u64, 92), gas.getRemaining());
}

test "JUMP: invalid destination (no JUMPDEST)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    // Create bytecode without JUMPDEST at position 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.from(5));
    const result = opJump(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.invalid_jump, result);
}

test "JUMP: out of bounds" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{ 0x00, 0x00 };
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.from(100)); // Beyond bytecode length
    const result = opJump(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.invalid_jump, result);
}

test "JUMP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{0x5B};
    const bytecode = Bytecode.new_raw(&code);

    const result = opJump(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.stack_underflow, result);
}

// --- JUMPI tests ---

test "JUMPI: conditional jump (condition true)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    // Create bytecode: JUMPDEST at position 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.ONE); // Condition (non-zero = true)
    stack.pushUnsafe(U.from(5)); // Destination
    const result = opJumpi(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 5), pc); // Should jump
}

test "JUMPI: conditional jump (condition false)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 10;

    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.ZERO); // Condition (zero = false)
    stack.pushUnsafe(U.from(5)); // Destination
    const result = opJumpi(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 10), pc); // Should NOT jump
}

test "JUMPI: condition true but invalid destination" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    // No JUMPDEST at position 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.ONE); // Condition true
    stack.pushUnsafe(U.from(5)); // Invalid destination
    const result = opJumpi(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.invalid_jump, result);
}

test "JUMPI: MAX value is true condition" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.MAX); // MAX is non-zero = true
    stack.pushUnsafe(U.from(5));
    const result = opJumpi(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 5), pc); // Should jump
}

test "JUMPI: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{0x5B};
    const bytecode = Bytecode.new_raw(&code);

    stack.pushUnsafe(U.ONE); // Only 1 value, need 2
    const result = opJumpi(&stack, &gas, bytecode, &pc);
    try expectEqual(InstructionResult.stack_underflow, result);
}
