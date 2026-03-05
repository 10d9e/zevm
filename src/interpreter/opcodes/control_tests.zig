const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const Interpreter = @import("../interpreter.zig").Interpreter;
const ExtBytecode = @import("../interpreter.zig").ExtBytecode;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
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

test "STOP: halts execution with .stop" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opStop(&ctx);
    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.stop, interp.result);
}

// --- JUMPDEST tests ---

test "JUMPDEST: no-op, does not halt" {
    var interp = Interpreter.defaultExt();
    var ctx = InstructionContext{ .interpreter = &interp };
    opJumpdest(&ctx);
    try expect(interp.bytecode.continue_execution);
}

// --- PC tests ---

test "PC: push program counter" {
    var interp = Interpreter.defaultExt();
    interp.bytecode.pc = 43; // simulate step() having advanced PC past opcode
    var ctx = InstructionContext{ .interpreter = &interp };
    opPc(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 42), interp.stack.popUnsafe()); // pc - 1
}

test "PC: zero" {
    var interp = Interpreter.defaultExt();
    interp.bytecode.pc = 1; // step() advances before calling handler
    var ctx = InstructionContext{ .interpreter = &interp };
    opPc(&ctx);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "PC: stack overflow" {
    var interp = Interpreter.defaultExt();
    interp.bytecode.pc = 1;
    var i: usize = 0;
    while (i < 1024) : (i += 1) interp.stack.pushUnsafe(@as(U, i));
    var ctx = InstructionContext{ .interpreter = &interp };
    opPc(&ctx);
    try expectEqual(.stack_overflow, interp.result);
}

// --- GAS tests ---

test "GAS: push remaining gas" {
    var interp = Interpreter.defaultExt();
    const Gas = @import("../gas.zig").Gas;
    interp.gas = Gas.new(1000);
    var ctx = InstructionContext{ .interpreter = &interp };
    opGas(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 1000), interp.stack.popUnsafe());
}

test "GAS: stack overflow" {
    var interp = Interpreter.defaultExt();
    var i: usize = 0;
    while (i < 1024) : (i += 1) interp.stack.pushUnsafe(@as(U, i));
    var ctx = InstructionContext{ .interpreter = &interp };
    opGas(&ctx);
    try expectEqual(.stack_overflow, interp.result);
}

// --- JUMP tests ---

test "JUMP: valid jump to JUMPDEST" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    // Bytecode: 5 NOP bytes then JUMPDEST at index 5
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B }; // 0x5B = JUMPDEST
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(@as(U, 5));
    var ctx = InstructionContext{ .interpreter = &interp };
    opJump(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 5), interp.bytecode.pc);
}

test "JUMP: invalid destination (no JUMPDEST)" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(@as(U, 5));
    var ctx = InstructionContext{ .interpreter = &interp };
    opJump(&ctx);
    try expectEqual(.invalid_jump, interp.result);
}

test "JUMP: out of bounds destination" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x00, 0x00 };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(@as(U, 100));
    var ctx = InstructionContext{ .interpreter = &interp };
    opJump(&ctx);
    try expectEqual(.invalid_jump, interp.result);
}

test "JUMP: stack underflow" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{0x5B};
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    var ctx = InstructionContext{ .interpreter = &interp };
    opJump(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}

// --- JUMPI tests ---

test "JUMPI: condition true => jump" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(@as(U, 1)); // condition (non-zero = true)
    interp.stack.pushUnsafe(@as(U, 5)); // destination
    var ctx = InstructionContext{ .interpreter = &interp };
    opJumpi(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 5), interp.bytecode.pc);
}

test "JUMPI: condition false => no jump" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.bytecode.pc = 10; // pretend we're at position 10
    interp.stack.pushUnsafe(@as(U, 0)); // condition = false
    interp.stack.pushUnsafe(@as(U, 5)); // destination (not taken)
    var ctx = InstructionContext{ .interpreter = &interp };
    opJumpi(&ctx);
    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 10), interp.bytecode.pc); // PC unchanged
}

test "JUMPI: condition true but invalid destination" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }; // no JUMPDEST
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(@as(U, 1));
    interp.stack.pushUnsafe(@as(U, 5));
    var ctx = InstructionContext{ .interpreter = &interp };
    opJumpi(&ctx);
    try expectEqual(.invalid_jump, interp.result);
}

test "JUMPI: MAX condition is true" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x5B };
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(std.math.maxInt(U));
    interp.stack.pushUnsafe(@as(U, 5));
    var ctx = InstructionContext{ .interpreter = &interp };
    opJumpi(&ctx);
    try expectEqual(@as(usize, 5), interp.bytecode.pc);
}

test "JUMPI: stack underflow" {
    var interp = Interpreter.defaultExt();
    defer interp.deinit();
    const code = [_]u8{0x5B};
    interp.bytecode = ExtBytecode.newOwned(bytecode_mod.Bytecode.newLegacy(&code));
    interp.stack.pushUnsafe(@as(U, 1)); // only 1 value, need 2
    var ctx = InstructionContext{ .interpreter = &interp };
    opJumpi(&ctx);
    try expectEqual(.stack_underflow, interp.result);
}
