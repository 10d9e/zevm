const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");
const host_module = @import("../host.zig");
const CallScheme = @import("../interpreter_action.zig").CallScheme;

// ---------------------------------------------------------------------------
// Memory expansion helper
// ---------------------------------------------------------------------------

fn memoryCostWords(num_words: usize) u64 {
    const n: u64 = @intCast(num_words);
    return n * gas_costs.G_MEMORY + (n * n) / 512;
}

fn expandMemory(ctx: *InstructionContext, new_size: usize) bool {
    if (new_size == 0) return true;
    const current = ctx.interpreter.memory.size();
    if (new_size <= current) return true;
    const current_words = (current + 31) / 32;
    const new_words = (new_size + 31) / 32;
    if (new_words > current_words) {
        const cost = memoryCostWords(new_words) - memoryCostWords(current_words);
        if (!ctx.interpreter.gas.spend(cost)) return false;
    }
    ctx.interpreter.memory.buffer.resize(std.heap.c_allocator, new_size) catch return false;
    return true;
}

// ---------------------------------------------------------------------------
// Common call dispatch helper
// ---------------------------------------------------------------------------

/// Shared logic for CALL, CALLCODE, DELEGATECALL, STATICCALL.
///
/// Stack layout (from top):
///   CALL/CALLCODE (7 items): gas, addr, value, argsOff, argsSize, retOff, retSize
///   DELEGATECALL/STATICCALL (6 items): gas, addr, argsOff, argsSize, retOff, retSize
fn callImpl(
    ctx: *InstructionContext,
    comptime has_value: bool,
    comptime scheme: CallScheme,
) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;

    const stack_items: usize = if (has_value) 7 else 6;
    if (!stack.hasItems(stack_items)) { ctx.interpreter.halt(.stack_underflow); return; }

    // Pop stack items
    const gas_val = stack.peekUnsafe(0);
    const addr_val = stack.peekUnsafe(1);
    const value: primitives.U256 = if (has_value) stack.peekUnsafe(2) else 0;
    const args_off = if (has_value) stack.peekUnsafe(3) else stack.peekUnsafe(2);
    const args_size = if (has_value) stack.peekUnsafe(4) else stack.peekUnsafe(3);
    const ret_off = if (has_value) stack.peekUnsafe(5) else stack.peekUnsafe(4);
    const ret_size = if (has_value) stack.peekUnsafe(6) else stack.peekUnsafe(5);
    stack.shrinkUnsafe(stack_items);

    const spec = ctx.interpreter.runtime_flags.spec_id;
    const is_static = ctx.interpreter.runtime_flags.is_static;

    // Static call constraint: no value transfer in static context
    if (comptime has_value) {
        if (is_static and value > 0) {
            ctx.interpreter.halt(.invalid_static); return;
        }
    }

    const target_addr = host_module.u256ToAddress(addr_val);

    // Memory bounds validation
    if (args_off > std.math.maxInt(usize) or args_size > std.math.maxInt(usize) or
        ret_off > std.math.maxInt(usize) or ret_size > std.math.maxInt(usize))
    {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }

    const args_off_u: usize = @intCast(args_off);
    const args_size_u: usize = @intCast(args_size);
    const ret_off_u: usize = @intCast(ret_off);
    const ret_size_u: usize = @intCast(ret_size);

    // Memory expansion for args region
    if (args_size_u > 0) {
        if (!expandMemory(ctx, args_off_u + args_size_u)) { ctx.interpreter.halt(.out_of_gas); return; }
    }
    // Memory expansion for return region
    if (ret_size_u > 0) {
        if (!expandMemory(ctx, ret_off_u + ret_size_u)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // Determine warm/cold access for target address
    const acct_info = h.accountInfo(target_addr);
    const is_cold = if (acct_info) |info| info.is_cold else true;
    const account_exists = if (acct_info) |info| !info.is_empty else false;
    const transfers_value = has_value and value > 0;

    // Base call cost (warm/cold + value transfer + new account)
    const base_cost = gas_costs.getCallGasCost(spec, is_cold, transfers_value, account_exists);

    // Apply 63/64 rule to determine forwarded gas
    const remaining = ctx.interpreter.gas.remaining;
    if (remaining < base_cost) { ctx.interpreter.halt(.out_of_gas); return; }

    const after_base = remaining - base_cost;
    const max_forwarded = after_base - after_base / 64; // EIP-150: 63/64 rule

    var forwarded: u64 = if (gas_val > std.math.maxInt(u64)) max_forwarded else @intCast(gas_val);
    forwarded = @min(forwarded, max_forwarded);

    // Value transfer stipend: add 2300 to forwarded gas if transferring value
    const stipend: u64 = if (transfers_value) 2300 else 0;
    forwarded +|= stipend;

    // Spend the base cost
    if (!ctx.interpreter.gas.spend(base_cost)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Build call inputs. For DELEGATECALL, caller and value come from parent frame.
    // For CALLCODE, target (storage context) stays as current contract.
    const call_caller = switch (scheme) {
        .delegatecall => ctx.interpreter.input.caller,
        else => ctx.interpreter.input.target,
    };
    const call_target = switch (scheme) {
        .callcode, .delegatecall => ctx.interpreter.input.target,
        else => target_addr,
    };
    const call_value = switch (scheme) {
        .delegatecall => ctx.interpreter.input.value,
        else => value,
    };
    const call_is_static = is_static or (scheme == .staticcall);

    // Gather call data from memory
    const call_data: []const u8 = if (args_size_u > 0)
        ctx.interpreter.memory.buffer.items[args_off_u .. args_off_u + args_size_u]
    else
        &[_]u8{};

    const inputs = host_module.CallInputs{
        .caller = call_caller,
        .target = call_target,
        .callee = target_addr,
        .value = call_value,
        .data = call_data,
        .gas_limit = forwarded,
        .scheme = scheme,
        .is_static = call_is_static,
    };

    const result = h.call(inputs);

    // Return unused gas from sub-call
    if (!ctx.interpreter.gas.spend(0)) {} // no-op, just for clarity
    ctx.interpreter.gas.remaining +|= result.gas_remaining;

    // Copy return data to memory
    const actual_ret_size = @min(result.return_data.len, ret_size_u);
    if (actual_ret_size > 0) {
        @memcpy(
            ctx.interpreter.memory.buffer.items[ret_off_u .. ret_off_u + actual_ret_size],
            result.return_data[0..actual_ret_size],
        );
    }

    // Update interpreter's return data buffer from sub-call
    ctx.interpreter.return_data.data = @constCast(result.return_data);

    // Push success flag: 1 for success, 0 for failure
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(if (result.success) 1 else 0);
}

// ---------------------------------------------------------------------------
// Public opcode handlers
// ---------------------------------------------------------------------------

/// CALL (0xF1): Call a contract.
/// Stack: [gas, addr, value, argsOff, argsSize, retOff, retSize] -> [success]
pub fn opCall(ctx: *InstructionContext) void {
    callImpl(ctx, true, .call);
}

/// CALLCODE (0xF2): Call with current contract's storage context.
/// Stack: [gas, addr, value, argsOff, argsSize, retOff, retSize] -> [success]
pub fn opCallcode(ctx: *InstructionContext) void {
    callImpl(ctx, true, .callcode);
}

/// DELEGATECALL (0xF4): Call with current contract's storage, sender, and value.
/// Stack: [gas, addr, argsOff, argsSize, retOff, retSize] -> [success]
pub fn opDelegatecall(ctx: *InstructionContext) void {
    callImpl(ctx, false, .delegatecall);
}

/// STATICCALL (0xFA): Read-only call (no state modifications allowed).
/// Stack: [gas, addr, argsOff, argsSize, retOff, retSize] -> [success]
pub fn opStaticcall(ctx: *InstructionContext) void {
    callImpl(ctx, false, .staticcall);
}

/// CREATE (0xF0): Create a new contract.
/// Stack: [value, offset, size] -> [addr]
pub fn opCreate(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    if (ctx.interpreter.runtime_flags.is_static) { ctx.interpreter.halt(.invalid_static); return; }
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) { ctx.interpreter.halt(.stack_underflow); return; }

    const value  = stack.peekUnsafe(0);
    const offset = stack.peekUnsafe(1);
    const size   = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    const spec = ctx.interpreter.runtime_flags.spec_id;

    // Base cost
    if (!ctx.interpreter.gas.spend(gas_costs.G_CREATE)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Validate and resolve memory region
    const size_u: usize = if (size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    } else @intCast(size);
    const off_u: usize = if (size_u == 0) 0 else if (offset > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    } else @intCast(offset);

    if (size_u > 0) {
        if (!expandMemory(ctx, off_u + size_u)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // EIP-3860 (Shanghai+): initcode word gas
    if (primitives.isEnabledIn(spec, .shanghai)) {
        const word_cost: u64 = 2 * @as(u64, @intCast((size_u + 31) / 32));
        if (!ctx.interpreter.gas.spend(word_cost)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // 63/64 rule: forward at most 63/64 of remaining gas
    const remaining = ctx.interpreter.gas.remaining;
    const forwarded = remaining - remaining / 64;

    const init_code: []const u8 = if (size_u > 0)
        ctx.interpreter.memory.buffer.items[off_u .. off_u + size_u]
    else &[_]u8{};

    const caller = ctx.interpreter.input.target;
    const result = h.create(caller, value, init_code, forwarded, false, 0, false);

    // Gas not used by sub-call is returned to caller
    ctx.interpreter.gas.remaining = ctx.interpreter.gas.remaining -| forwarded;
    ctx.interpreter.gas.remaining +|= result.gas_remaining;
    ctx.interpreter.return_data.data = @constCast(result.return_data);

    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(if (result.success) host_module.addressToU256(result.address) else 0);
}

/// CREATE2 (0xF5): Create a new contract with deterministic address.
/// Stack: [value, offset, size, salt] -> [addr]
pub fn opCreate2(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    if (ctx.interpreter.runtime_flags.is_static) { ctx.interpreter.halt(.invalid_static); return; }
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(4)) { ctx.interpreter.halt(.stack_underflow); return; }

    const value  = stack.peekUnsafe(0);
    const offset = stack.peekUnsafe(1);
    const size   = stack.peekUnsafe(2);
    const salt   = stack.peekUnsafe(3);
    stack.shrinkUnsafe(4);

    const spec = ctx.interpreter.runtime_flags.spec_id;

    if (!ctx.interpreter.gas.spend(gas_costs.G_CREATE)) { ctx.interpreter.halt(.out_of_gas); return; }

    const size_u: usize = if (size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    } else @intCast(size);
    const off_u: usize = if (size_u == 0) 0 else if (offset > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    } else @intCast(offset);

    if (size_u > 0) {
        if (!expandMemory(ctx, off_u + size_u)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // CREATE2 keccak word cost (charged for the init_code hash)
    {
        const word_cost: u64 = gas_costs.G_KECCAK256WORD * @as(u64, @intCast((size_u + 31) / 32));
        if (!ctx.interpreter.gas.spend(word_cost)) { ctx.interpreter.halt(.out_of_gas); return; }
    }
    // EIP-3860 (Shanghai+): additional initcode word gas
    if (primitives.isEnabledIn(spec, .shanghai)) {
        const word_cost: u64 = 2 * @as(u64, @intCast((size_u + 31) / 32));
        if (!ctx.interpreter.gas.spend(word_cost)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    const remaining = ctx.interpreter.gas.remaining;
    const forwarded = remaining - remaining / 64;

    const init_code: []const u8 = if (size_u > 0)
        ctx.interpreter.memory.buffer.items[off_u .. off_u + size_u]
    else &[_]u8{};

    const caller = ctx.interpreter.input.target;
    const result = h.create(caller, value, init_code, forwarded, true, salt, false);

    ctx.interpreter.gas.remaining = ctx.interpreter.gas.remaining -| forwarded;
    ctx.interpreter.gas.remaining +|= result.gas_remaining;
    ctx.interpreter.return_data.data = @constCast(result.return_data);

    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(if (result.success) host_module.addressToU256(result.address) else 0);
}

test {
    _ = @import("create_tests.zig");
}
