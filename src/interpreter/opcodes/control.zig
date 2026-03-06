const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;

/// STOP opcode (0x00): Halt execution
/// Stack: [] -> []   Gas: 0 (G_ZERO, charged by dispatch)
pub fn opStop(ctx: *InstructionContext) void {
    // Per EVM spec, STOP produces empty output. Clear return_data so:
    // 1. RETURNDATASIZE in the caller is 0 after a STOP-terminating call.
    // 2. For CREATE/CREATE2, deployed code is empty (not stale from a prior sub-call).
    ctx.interpreter.return_data.data = &[_]u8{};
    ctx.interpreter.halt(.stop);
}

/// JUMP opcode (0x56): Unconditional jump
/// Stack: [dest] -> []   Gas: 8 (G_MID, charged by dispatch)
pub fn opJump(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const dest = stack.popUnsafe();
    if (dest > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.invalid_jump);
        return;
    }
    const dest_usize: usize = @intCast(dest);
    if (!ctx.interpreter.bytecode.isValidJump(dest_usize)) {
        ctx.interpreter.halt(.invalid_jump);
        return;
    }
    ctx.interpreter.bytecode.absoluteJump(dest_usize);
}

/// JUMPI opcode (0x57): Conditional jump
/// Stack: [dest, cond] -> []   Gas: 10 (G_HIGH, charged by dispatch)
pub fn opJumpi(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) {
        ctx.interpreter.halt(.stack_underflow);
        return;
    }
    const dest = stack.peekUnsafe(0);
    const cond = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);
    if (cond == 0) return;
    if (dest > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.invalid_jump);
        return;
    }
    const dest_usize: usize = @intCast(dest);
    if (!ctx.interpreter.bytecode.isValidJump(dest_usize)) {
        ctx.interpreter.halt(.invalid_jump);
        return;
    }
    ctx.interpreter.bytecode.absoluteJump(dest_usize);
}

/// JUMPDEST opcode (0x5B): Mark valid jump destination — no-op at runtime
/// Stack: [] -> []   Gas: 1 (G_JUMPDEST, charged by dispatch)
pub fn opJumpdest(ctx: *InstructionContext) void {
    _ = ctx;
}

/// PC opcode (0x58): Push program counter of this instruction
/// Stack: [] -> [pc]   Gas: 2 (G_BASE, charged by dispatch)
/// Note: step() advances PC by 1 before calling handler; pc-1 is the opcode address.
pub fn opPc(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) {
        ctx.interpreter.halt(.stack_overflow);
        return;
    }
    stack.pushUnsafe(@intCast(ctx.interpreter.bytecode.pc - 1));
}

/// GAS opcode (0x5A): Push remaining gas after this instruction's static cost
/// Stack: [] -> [gas]   Gas: 2 (G_BASE, charged by dispatch before handler is called)
pub fn opGas(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) {
        ctx.interpreter.halt(.stack_overflow);
        return;
    }
    stack.pushUnsafe(ctx.interpreter.gas.remaining);
}

test {
    _ = @import("control_tests.zig");
}
