const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const bytecode_mod = @import("bytecode");
const gas_costs = @import("../gas_costs.zig");

/// STOP opcode (0x00): Halt execution
/// Stack: [] -> []   Gas: 0
pub inline fn opStop(stack: *Stack, gas: *Gas) InstructionResult {
    _ = stack;
    _ = gas;
    return .stop;
}

/// JUMP opcode (0x56): Unconditional jump
/// Stack: [dest] -> []   Gas: 8 (MID)
/// Jumps to destination if it's a valid JUMPDEST
pub inline fn opJump(stack: *Stack, gas: *Gas, code: []const u8, jump_table: ?*const bytecode_mod.JumpTable, pc: *usize) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_MID)) return .out_of_gas;

    const dest = stack.popUnsafe();
    const dest_u64 = std.math.cast(u64, dest) orelse return .invalid_jump;
    const dest_usize: usize = @intCast(dest_u64);

    if (dest_usize >= code.len) return .invalid_jump;

    if (jump_table) |jt| {
        if (!jt.isValid(dest_usize)) return .invalid_jump;
    } else {
        if (code[dest_usize] != bytecode_mod.JUMPDEST) return .invalid_jump;
    }

    pc.* = dest_usize;
    return .continue_;
}

/// JUMPI opcode (0x57): Conditional jump
/// Stack: [dest, cond] -> []   Gas: 10 (HIGH)
/// Jumps to destination if condition is non-zero and dest is valid JUMPDEST
pub inline fn opJumpi(stack: *Stack, gas: *Gas, code: []const u8, jump_table: ?*const bytecode_mod.JumpTable, pc: *usize) InstructionResult {
    if (!stack.hasItems(2)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_HIGH)) return .out_of_gas;

    const dest = stack.peekUnsafe(0);
    const cond = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    if (cond == 0) {
        return .continue_;
    }

    const dest_u64 = std.math.cast(u64, dest) orelse return .invalid_jump;
    const dest_usize: usize = @intCast(dest_u64);

    if (dest_usize >= code.len) return .invalid_jump;

    if (jump_table) |jt| {
        if (!jt.isValid(dest_usize)) return .invalid_jump;
    } else {
        if (code[dest_usize] != bytecode_mod.JUMPDEST) return .invalid_jump;
    }

    pc.* = dest_usize;
    return .continue_;
}

/// JUMPDEST opcode (0x5B): Mark valid jump destination
/// Stack: [] -> []   Gas: 1 (JUMPDEST)
pub inline fn opJumpdest(stack: *Stack, gas: *Gas) InstructionResult {
    _ = stack;
    if (!gas.spend(gas_costs.G_JUMPDEST)) return .out_of_gas;
    return .continue_;
}

/// PC opcode (0x58): Get program counter
/// Stack: [] -> [pc]   Gas: 2 (BASE)
pub inline fn opPc(stack: *Stack, gas: *Gas, pc: usize) InstructionResult {
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(gas_costs.G_BASE)) return .out_of_gas;
    stack.pushUnsafe(pc);
    return .continue_;
}

/// GAS opcode (0x5A): Get remaining gas
/// Stack: [] -> [gas]   Gas: 2 (BASE)
pub inline fn opGas(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(gas_costs.G_BASE)) return .out_of_gas;
    stack.pushUnsafe(gas.remaining);
    return .continue_;
}

test {
    _ = @import("control_tests.zig");
}
