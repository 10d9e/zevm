const std = @import("std");
const primitives = @import("primitives");
const Stack = @import("../stack.zig").Stack;
const Gas = @import("../gas.zig").Gas;
const InstructionResult = @import("../instruction_result.zig").InstructionResult;
const gas_costs = @import("../gas_costs.zig");

/// POP opcode (0x50): Remove top item from stack
/// Stack: [a] -> []   Gas: 2 (BASE)
pub inline fn opPop(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasItems(1)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_BASE)) return .out_of_gas;
    stack.shrinkUnsafe(1);
    return .continue_;
}

/// PUSH0 opcode (0x5F): Push 0 onto stack (Shanghai+)
/// Stack: [] -> [0]   Gas: 2 (BASE)
pub inline fn opPush0(stack: *Stack, gas: *Gas) InstructionResult {
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(gas_costs.G_BASE)) return .out_of_gas;
    stack.pushUnsafe(0);
    return .continue_;
}

/// Generic PUSH operation for PUSH1-PUSH32
/// Reads N bytes from bytecode and pushes as U256
pub inline fn opPushN(stack: *Stack, gas: *Gas, code: []const u8, pc: *usize, n: u8) InstructionResult {
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;

    const start = pc.* + 1;
    const available = if (start < code.len) code.len - start else 0;
    const to_read: usize = @min(@as(usize, n), available);

    // Zero-padded 32-byte big-endian buffer; n bytes go right-aligned
    var buf: [32]u8 = .{0} ** 32;
    if (to_read > 0) {
        @memcpy(buf[32 - to_read ..], code[start .. start + to_read]);
    }

    // Read four big-endian u64 limbs and assemble U256
    // (4 native-width loads + bswaps, then 3 constant shifts + ORs)
    const U = primitives.U256;
    const value: U = (@as(U, std.mem.readInt(u64, buf[0..8], .big)) << 192) |
        (@as(U, std.mem.readInt(u64, buf[8..16], .big)) << 128) |
        (@as(U, std.mem.readInt(u64, buf[16..24], .big)) << 64) |
        @as(U, std.mem.readInt(u64, buf[24..32], .big));

    stack.pushUnsafe(value);
    pc.* += n;
    return .continue_;
}

/// DUP1-DUP16 operations: Duplicate nth stack item
/// Stack: [..., nth] -> [..., nth, nth]   Gas: 3 (VERYLOW)
pub inline fn opDupN(stack: *Stack, gas: *Gas, n: u8) InstructionResult {
    if (!stack.hasItems(n)) return .stack_underflow;
    if (!stack.hasSpace(1)) return .stack_overflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;
    stack.dupUnsafe(n);
    return .continue_;
}

/// SWAP1-SWAP16 operations: Swap top with nth item
/// Stack: [a, ..., nth] -> [nth, ..., a]   Gas: 3 (VERYLOW)
pub inline fn opSwapN(stack: *Stack, gas: *Gas, n: u8) InstructionResult {
    const items_needed = n + 1;
    if (!stack.hasItems(items_needed)) return .stack_underflow;
    if (!gas.spend(gas_costs.G_VERYLOW)) return .out_of_gas;
    stack.swapUnsafe(n);
    return .continue_;
}

test {
    _ = @import("stack_tests.zig");
}
