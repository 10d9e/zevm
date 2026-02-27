const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const control = @import("control.zig");

const opStop = control.opStop;
const opJump = control.opJump;
const opJumpi = control.opJumpi;
const opJumpdest = control.opJumpdest;
const opPc = control.opPc;
const opGas = control.opGas;

const expectEqual = std.testing.expectEqual;
const U = primitives.U256;

// --- STOP tests ---

test "STOP: halts execution" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opStop(&stack, &gas);
    try expectEqual(InstructionResult.stop, result);
    // opStop doesn't spend gas
    try expectEqual(@as(u64, 100), gas.getRemaining());
}

// --- JUMPDEST tests ---

test "JUMPDEST: valid jump destination" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const result = opJumpdest(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(u64, 99), gas.getRemaining());
}

test "JUMPDEST: out of gas" {
    var stack = Stack.new();
    var gas = Gas.new(0);
    const result = opJumpdest(&stack, &gas);
    try expectEqual(InstructionResult.out_of_gas, result);
}

// --- PC tests ---

test "PC: push program counter" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const pc: usize = 42;
    const result = opPc(&stack, &gas, pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 42), stack.popUnsafe());
    try expectEqual(@as(u64, 98), gas.getRemaining());
}

test "PC: zero" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const pc: usize = 0;
    const result = opPc(&stack, &gas, pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
}

test "PC: large value" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    const pc: usize = 12345;
    const result = opPc(&stack, &gas, pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 12345), stack.popUnsafe());
}

test "PC: stack overflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    // Fill stack to max capacity
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        stack.pushUnsafe(@as(U, i));
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
    try expectEqual(@as(U, 998), stack.popUnsafe());
    try expectEqual(@as(u64, 998), gas.getRemaining());
}

test "GAS: zero gas remaining" {
    var stack = Stack.new();
    var gas = Gas.new(2); // Exactly enough for GAS opcode
    const result = opGas(&stack, &gas);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(U, 0), stack.popUnsafe());
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
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(@as(U, 5)); // Jump to position 5
    const result = opJump(&stack, &gas, &code, jt, &pc);
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
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(@as(U, 5));
    const result = opJump(&stack, &gas, &code, jt, &pc);
    try expectEqual(InstructionResult.invalid_jump, result);
}

test "JUMP: out of bounds" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{ 0x00, 0x00 };
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(@as(U, 100)); // Beyond bytecode length
    const result = opJump(&stack, &gas, &code, jt, &pc);
    try expectEqual(InstructionResult.invalid_jump, result);
}

test "JUMP: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{0x5B};

    const result = opJump(&stack, &gas, &code, null, &pc);
    try expectEqual(InstructionResult.stack_underflow, result);
}

// --- JUMPI tests ---

test "JUMPI: conditional jump (condition true)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    // Create bytecode: JUMPDEST at position 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(@as(U, 1)); // Condition (non-zero = true)
    stack.pushUnsafe(@as(U, 5)); // Destination
    const result = opJumpi(&stack, &gas, &code, jt, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 5), pc); // Should jump
}

test "JUMPI: conditional jump (condition false)" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 10;

    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(@as(U, 0)); // Condition (zero = false)
    stack.pushUnsafe(@as(U, 5)); // Destination
    const result = opJumpi(&stack, &gas, &code, jt, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 10), pc); // Should NOT jump
}

test "JUMPI: condition true but invalid destination" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    // No JUMPDEST at position 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(@as(U, 1)); // Condition true
    stack.pushUnsafe(@as(U, 5)); // Invalid destination
    const result = opJumpi(&stack, &gas, &code, jt, &pc);
    try expectEqual(InstructionResult.invalid_jump, result);
}

test "JUMPI: MAX value is true condition" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    const bc = bytecode_mod.Bytecode.newLegacy(&code);
    const jt = bc.legacyJumpTable();

    stack.pushUnsafe(std.math.maxInt(U)); // MAX is non-zero = true
    stack.pushUnsafe(@as(U, 5));
    const result = opJumpi(&stack, &gas, &code, jt, &pc);
    try expectEqual(InstructionResult.continue_, result);
    try expectEqual(@as(usize, 5), pc); // Should jump
}

test "JUMPI: stack underflow" {
    var stack = Stack.new();
    var gas = Gas.new(100);
    var pc: usize = 0;

    const code = [_]u8{0x5B};

    stack.pushUnsafe(@as(U, 1)); // Only 1 value, need 2
    const result = opJumpi(&stack, &gas, &code, null, &pc);
    try expectEqual(InstructionResult.stack_underflow, result);
}
