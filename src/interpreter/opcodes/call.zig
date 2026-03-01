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
    const linear = std.math.mul(u64, n, gas_costs.G_MEMORY) catch return std.math.maxInt(u64);
    const quadratic = (std.math.mul(u64, n, n) catch return std.math.maxInt(u64)) / 512;
    return std.math.add(u64, linear, quadratic) catch std.math.maxInt(u64);
}

fn expandMemory(ctx: *InstructionContext, new_size: usize) bool {
    if (new_size == 0) return true;
    const current = ctx.interpreter.memory.size();
    if (new_size <= current) return true;
    const current_words = (current + 31) / 32;
    const new_words = (std.math.add(usize, new_size, 31) catch return false) / 32;
    if (new_words > current_words) {
        const cost = memoryCostWords(new_words) - memoryCostWords(current_words);
        if (!ctx.interpreter.gas.spend(cost)) return false;
    }
    const aligned_size = new_words * 32;
    const old_size = ctx.interpreter.memory.size();
    ctx.interpreter.memory.buffer.resize(std.heap.c_allocator, aligned_size) catch return false;
    @memset(ctx.interpreter.memory.buffer.items[old_size..aligned_size], 0);
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

    // Static call constraint per EIP-214: CALL with non-zero value is forbidden in
    // static context and causes an exception (halt). CALLCODE is NOT in the EIP-214
    // forbidden list because it does not transfer ETH to an external account.
    if (comptime (has_value and scheme == .call)) {
        if (is_static and value > 0) {
            ctx.interpreter.halt(.invalid_static); return;
        }
    }

    const target_addr = host_module.u256ToAddress(addr_val);

    // Sizes must always fit in usize (otherwise the memory requirement is impossible).
    // Offsets only need to fit when the corresponding size is non-zero; a giant offset
    // with size=0 is valid (no memory is touched).
    if (args_size > std.math.maxInt(usize) or ret_size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }
    const args_size_u: usize = @intCast(args_size);
    const ret_size_u: usize = @intCast(ret_size);
    if ((args_size_u > 0 and args_off > std.math.maxInt(usize)) or
        (ret_size_u > 0 and ret_off > std.math.maxInt(usize)))
    {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }
    const args_off_u: usize = if (args_size_u > 0) @intCast(args_off) else 0;
    const ret_off_u: usize = if (ret_size_u > 0) @intCast(ret_off) else 0;

    // Memory expansion for args region
    if (args_size_u > 0) {
        const args_end = std.math.add(usize, args_off_u, args_size_u) catch {
            ctx.interpreter.halt(.memory_limit_oog); return;
        };
        if (!expandMemory(ctx, args_end)) { ctx.interpreter.halt(.out_of_gas); return; }
    }
    // Memory expansion for return region
    if (ret_size_u > 0) {
        const ret_end = std.math.add(usize, ret_off_u, ret_size_u) catch {
            ctx.interpreter.halt(.memory_limit_oog); return;
        };
        if (!expandMemory(ctx, ret_end)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // Determine warm/cold access for target address (code source)
    const acct_info = h.accountInfo(target_addr);
    const is_cold = if (acct_info) |info| info.is_cold else true;
    const transfers_value = has_value and value > 0;
    // G_NEWACCOUNT applies to the ETH *recipient*, not the code source.
    // For CALLCODE/DELEGATECALL, ETH goes to self (always exists). Otherwise ETH goes to target_addr.
    const account_exists = switch (scheme) {
        .callcode, .delegatecall => true, // self always exists
        else => if (acct_info) |info| !info.is_empty else false,
    };

    // EIP-7702: pre-compute delegation gas as part of the CALL upfront cost (before the 63/64
    // rule). Per EIP-7702, loading the delegation target incurs a warm/cold access cost that is
    // part of the CALL instruction overhead. Including it in base_cost ensures the 63/64 rule
    // correctly limits forwarded gas (charging it after the sub-call gives the callee too much gas).
    var delegation_gas: u64 = 0;
    if (h.codeInfo(target_addr)) |code_info| {
        if (code_info.bytecode.isEip7702()) {
            const del_addr = code_info.bytecode.eip7702.address;
            if (h.accountInfo(del_addr)) |del_info| {
                delegation_gas = if (del_info.is_cold) gas_costs.COLD_ACCOUNT_ACCESS else gas_costs.WARM_ACCOUNT_ACCESS;
            }
        }
    }

    // Base call cost (warm/cold + value transfer + new account + EIP-7702 delegation target access)
    const base_cost = gas_costs.getCallGasCost(spec, is_cold, transfers_value, account_exists) + delegation_gas;

    // Apply 63/64 rule to determine forwarded gas (EIP-150).
    const remaining = ctx.interpreter.gas.remaining;
    if (remaining < base_cost) { ctx.interpreter.halt(.out_of_gas); return; }

    const after_base = remaining - base_cost;
    const max_forwarded = after_base - after_base / 64;

    const forwarded: u64 = @min(
        if (gas_val > std.math.maxInt(u64)) max_forwarded else @as(u64, @intCast(gas_val)),
        max_forwarded,
    );

    // The stipend (2300 gas) is gifted to the callee on value-bearing CALL.
    // It is NOT deducted from the caller's gas — the caller only pays `forwarded`.
    const stipend: u64 = if (transfers_value) gas_costs.CALL_STIPEND else 0;
    // Gas limit seen by the sub-interpreter = forwarded amount + free stipend.
    const sub_gas_limit: u64 = forwarded +| stipend;

    // Deduct base cost then the forwarded amount from this frame's gas.
    if (!ctx.interpreter.gas.spend(base_cost)) { ctx.interpreter.halt(.out_of_gas); return; }
    if (!ctx.interpreter.gas.spend(forwarded)) { ctx.interpreter.halt(.out_of_gas); return; }

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
        .gas_limit = sub_gas_limit,
        .scheme = scheme,
        .is_static = call_is_static,
    };

    const result = h.call(inputs);

    // Return unused gas from sub-call and propagate any refunds it accumulated.
    ctx.interpreter.gas.remaining +|= result.gas_remaining;
    ctx.interpreter.gas.refunded += result.gas_refunded;

    // Copy return data to memory (use direction-safe copy: return data may alias
    // execution memory, e.g. when the identity precompile echoes calldata).
    const actual_ret_size = @min(result.return_data.len, ret_size_u);
    if (actual_ret_size > 0) {
        const dst = ctx.interpreter.memory.buffer.items[ret_off_u .. ret_off_u + actual_ret_size];
        const src = result.return_data[0..actual_ret_size];
        if (@intFromPtr(dst.ptr) <= @intFromPtr(src.ptr)) {
            std.mem.copyForwards(u8, dst, src);
        } else {
            std.mem.copyBackwards(u8, dst, src);
        }
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
        const create_end = std.math.add(usize, off_u, size_u) catch {
            ctx.interpreter.halt(.memory_limit_oog); return;
        };
        if (!expandMemory(ctx, create_end)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // EIP-3860 (Shanghai+): oversized initcode causes exceptional halt in calling frame (not push-0).
    // Per EIP-3860 spec: "If len(initcode) > MAX_INITCODE_SIZE, raise out-of-gas exception."
    // This aborts the current frame, so the enclosing CALL sees a failure (returns 0).
    if (primitives.isEnabledIn(spec, .shanghai)) {
        if (size_u > 49152) { // MAX_INITCODE_SIZE = 2 * 24576
            ctx.interpreter.halt(.out_of_gas); return;
        }
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

    // Adjust parent gas: forwarded was already spent; add back what sub-call didn't use.
    ctx.interpreter.gas.remaining = ctx.interpreter.gas.remaining -| forwarded;
    ctx.interpreter.gas.remaining +|= result.gas_remaining;
    ctx.interpreter.gas.refunded += result.gas_refunded;
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
        const create2_end = std.math.add(usize, off_u, size_u) catch {
            ctx.interpreter.halt(.memory_limit_oog); return;
        };
        if (!expandMemory(ctx, create2_end)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // EIP-3860 (Shanghai+): oversized initcode causes exceptional halt in calling frame (not push-0).
    // Per EIP-3860 spec: "If len(initcode) > MAX_INITCODE_SIZE, raise out-of-gas exception."
    if (primitives.isEnabledIn(spec, .shanghai)) {
        if (size_u > 49152) { // MAX_INITCODE_SIZE = 2 * 24576
            ctx.interpreter.halt(.out_of_gas); return;
        }
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
    ctx.interpreter.gas.refunded += result.gas_refunded;
    ctx.interpreter.return_data.data = @constCast(result.return_data);

    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(if (result.success) host_module.addressToU256(result.address) else 0);
}

test {
    _ = @import("create_tests.zig");
}
