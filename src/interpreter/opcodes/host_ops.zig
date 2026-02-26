const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");
const host_module = @import("../host.zig");

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
// Account balance / code opcodes
// ---------------------------------------------------------------------------

/// BALANCE (0x31): Push the ETH balance of an address.
/// Stack: [addr] -> [balance]
/// Gas: pre-Berlin 400 static; Berlin+ dynamic warm/cold
pub fn opBalance(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const addr_val = stack.peekUnsafe(0);
    const addr = host_module.u256ToAddress(addr_val);

    const info = h.accountInfo(addr) orelse {
        ctx.interpreter.halt(.invalid_opcode); return;
    };

    // Post-Berlin: charge dynamic warm/cold cost (static_gas is 0)
    if (primitives.isEnabledIn(ctx.interpreter.runtime_flags.spec_id, .berlin)) {
        const dyn_gas: u64 = if (info.is_cold) gas_costs.COLD_ACCOUNT_ACCESS else gas_costs.WARM_ACCOUNT_ACCESS;
        if (!ctx.interpreter.gas.spend(dyn_gas)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    stack.setTopUnsafe().* = info.balance;
}

/// SELFBALANCE (0x47): Push the balance of the currently executing contract.
/// Stack: [] -> [balance]   Gas: 5 (G_LOW, dispatch, Istanbul+)
pub fn opSelfbalance(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }

    const self_addr = ctx.interpreter.input.target;
    const info = h.accountInfo(self_addr) orelse {
        stack.pushUnsafe(0);
        return;
    };
    stack.pushUnsafe(info.balance);
}

/// EXTCODESIZE (0x3B): Push the size of an external account's code.
/// Stack: [addr] -> [size]
/// Gas: pre-Berlin 700 static; Berlin+ dynamic warm/cold
pub fn opExtcodesize(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const addr_val = stack.peekUnsafe(0);
    const addr = host_module.u256ToAddress(addr_val);

    const info = h.codeInfo(addr) orelse {
        stack.setTopUnsafe().* = 0;
        return;
    };

    // Post-Berlin: charge dynamic warm/cold cost (static_gas is 0)
    if (primitives.isEnabledIn(ctx.interpreter.runtime_flags.spec_id, .berlin)) {
        const dyn_gas: u64 = if (info.is_cold) gas_costs.COLD_ACCOUNT_ACCESS else gas_costs.WARM_ACCOUNT_ACCESS;
        if (!ctx.interpreter.gas.spend(dyn_gas)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // Use originalBytes().len: the analyzed bytecode may include a STOP-padding byte
    // that is NOT part of the on-chain code, so EXTCODESIZE must return the original length.
    stack.setTopUnsafe().* = @intCast(info.bytecode.originalBytes().len);
}

/// EXTCODECOPY (0x3C): Copy external account code to memory.
/// Stack: [addr, memOff, codeOff, size] -> []
/// Gas: pre-Berlin 700 static + copy; Berlin+ dynamic warm/cold + copy
pub fn opExtcodecopy(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(4)) { ctx.interpreter.halt(.stack_underflow); return; }

    const addr_val = stack.peekUnsafe(0);
    const mem_off = stack.peekUnsafe(1);
    const code_off = stack.peekUnsafe(2);
    const size = stack.peekUnsafe(3);
    stack.shrinkUnsafe(4);

    const addr = host_module.u256ToAddress(addr_val);
    const info = h.codeInfo(addr) orelse {
        // Address doesn't exist; still need to expand memory and pay copy cost
        if (size == 0) return;
        if (mem_off > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
            ctx.interpreter.halt(.memory_limit_oog); return;
        }
        const mem_off_u: usize = @intCast(mem_off);
        const size_u: usize = @intCast(size);
        const num_words = (size_u + 31) / 32;
        if (!ctx.interpreter.gas.spend(gas_costs.G_COPY * @as(u64, @intCast(num_words)))) {
            ctx.interpreter.halt(.out_of_gas); return;
        }
        if (!expandMemory(ctx, mem_off_u + size_u)) { ctx.interpreter.halt(.out_of_gas); return; }
        @memset(ctx.interpreter.memory.buffer.items[mem_off_u .. mem_off_u + size_u], 0);
        return;
    };

    // Post-Berlin: dynamic warm/cold access cost
    if (primitives.isEnabledIn(ctx.interpreter.runtime_flags.spec_id, .berlin)) {
        const dyn_gas: u64 = if (info.is_cold) gas_costs.COLD_ACCOUNT_ACCESS else gas_costs.WARM_ACCOUNT_ACCESS;
        if (!ctx.interpreter.gas.spend(dyn_gas)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    if (size == 0) return;

    if (mem_off > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }

    const mem_off_u: usize = @intCast(mem_off);
    const size_u: usize = @intCast(size);
    const new_size = mem_off_u + size_u;

    // Dynamic: copy cost
    const num_words = (size_u + 31) / 32;
    if (!ctx.interpreter.gas.spend(gas_costs.G_COPY * @as(u64, @intCast(num_words)))) {
        ctx.interpreter.halt(.out_of_gas); return;
    }

    if (!expandMemory(ctx, new_size)) { ctx.interpreter.halt(.out_of_gas); return; }

    const code = info.bytecode.bytecode();
    const dest = ctx.interpreter.memory.buffer.items[mem_off_u .. mem_off_u + size_u];

    if (code_off > std.math.maxInt(usize)) {
        @memset(dest, 0);
    } else {
        const code_off_u: usize = @intCast(code_off);
        if (code_off_u >= code.len) {
            @memset(dest, 0);
        } else {
            const available = code.len - code_off_u;
            const to_copy = @min(available, size_u);
            @memcpy(dest[0..to_copy], code[code_off_u .. code_off_u + to_copy]);
            if (to_copy < size_u) @memset(dest[to_copy..], 0);
        }
    }
}

/// EXTCODEHASH (0x3F): Push the keccak256 hash of an external account's code.
/// Stack: [addr] -> [hash]
/// Gas: Istanbul: 700 static; Berlin+ dynamic warm/cold
pub fn opExtcodehash(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const addr_val = stack.peekUnsafe(0);
    const addr = host_module.u256ToAddress(addr_val);

    const info = h.extCodeHash(addr) orelse {
        stack.setTopUnsafe().* = 0;
        return;
    };

    // Post-Berlin: dynamic warm/cold cost (static_gas is 0)
    if (primitives.isEnabledIn(ctx.interpreter.runtime_flags.spec_id, .berlin)) {
        const dyn_gas: u64 = if (info.is_cold) gas_costs.COLD_ACCOUNT_ACCESS else gas_costs.WARM_ACCOUNT_ACCESS;
        if (!ctx.interpreter.gas.spend(dyn_gas)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    // Empty account → push 0
    if (info.is_empty) {
        stack.setTopUnsafe().* = 0;
    } else {
        stack.setTopUnsafe().* = host_module.hashToU256(info.hash);
    }
}

/// BLOCKHASH (0x40): Push the hash of one of the 256 most recent blocks.
/// Stack: [blockNumber] -> [hash]   Gas: 20 (G_BLOCKHASH, dispatch)
pub fn opBlockhash(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const number = stack.peekUnsafe(0);
    if (number > std.math.maxInt(u64)) {
        stack.setTopUnsafe().* = 0;
        return;
    }
    const num_u64: u64 = @intCast(number);
    const hash_opt = h.blockHash(num_u64);
    stack.setTopUnsafe().* = if (hash_opt) |hash| host_module.hashToU256(hash) else 0;
}

// ---------------------------------------------------------------------------
// Storage opcodes
// ---------------------------------------------------------------------------

/// SLOAD (0x54): Load a word from storage.
/// Stack: [key] -> [value]
/// Gas: dynamic based on cold/warm and spec
pub fn opSload(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const key = stack.peekUnsafe(0);
    const self_addr = ctx.interpreter.input.target;
    const spec = ctx.interpreter.runtime_flags.spec_id;

    const result = h.sload(self_addr, key) orelse {
        ctx.interpreter.halt(.invalid_opcode); return;
    };

    // Dynamic gas for Berlin+ (static_gas is 0 for Berlin+)
    if (primitives.isEnabledIn(spec, .berlin)) {
        const dyn_gas: u64 = if (result.is_cold) gas_costs.COLD_SLOAD else gas_costs.WARM_SLOAD;
        if (!ctx.interpreter.gas.spend(dyn_gas)) { ctx.interpreter.halt(.out_of_gas); return; }
    }

    stack.setTopUnsafe().* = result.value;
}

/// SSTORE (0x55): Save a word to storage.
/// Stack: [key, value] -> []
/// Gas: complex EIP-2200/EIP-2929 calculation
pub fn opSstore(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };

    // Static call check
    if (ctx.interpreter.runtime_flags.is_static) {
        ctx.interpreter.halt(.invalid_static); return;
    }

    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) { ctx.interpreter.halt(.stack_underflow); return; }

    const key = stack.peekUnsafe(0);
    const new_value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    const self_addr = ctx.interpreter.input.target;
    const spec = ctx.interpreter.runtime_flags.spec_id;

    const result = h.sstore(self_addr, key, new_value) orelse {
        ctx.interpreter.halt(.invalid_opcode); return;
    };

    // Compute gas cost using EIP-2200/EIP-2929 rules
    const sstore_gas = gas_costs.getSstoreCost(spec, result.original, result.current, result.new, result.is_cold);

    if (!ctx.interpreter.gas.spend(sstore_gas.gas_cost)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Apply gas refund (can be positive or negative)
    if (sstore_gas.gas_refund > 0) {
        ctx.interpreter.gas.recordRefund(@intCast(sstore_gas.gas_refund));
    } else if (sstore_gas.gas_refund < 0) {
        const abs_refund: u64 = @intCast(-sstore_gas.gas_refund);
        ctx.interpreter.gas.refunded -= @as(i64, @intCast(abs_refund));
    }
}

/// TLOAD (0x5C): Load a word from transient storage (EIP-1153, Cancun+).
/// Stack: [key] -> [value]   Gas: 100 (WARM_SLOAD, dispatch)
pub fn opTload(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const key = stack.peekUnsafe(0);
    const self_addr = ctx.interpreter.input.target;
    stack.setTopUnsafe().* = h.tload(self_addr, key);
}

/// TSTORE (0x5D): Save a word to transient storage (EIP-1153, Cancun+).
/// Stack: [key, value] -> []   Gas: 100 (WARM_SLOAD, dispatch)
pub fn opTstore(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };

    // Static call check
    if (ctx.interpreter.runtime_flags.is_static) {
        ctx.interpreter.halt(.invalid_static); return;
    }

    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(2)) { ctx.interpreter.halt(.stack_underflow); return; }

    const key = stack.peekUnsafe(0);
    const value = stack.peekUnsafe(1);
    stack.shrinkUnsafe(2);

    const self_addr = ctx.interpreter.input.target;
    h.tstore(self_addr, key, value);
}

// ---------------------------------------------------------------------------
// LOG opcodes (comptime-generated for LOG0..LOG4)
// ---------------------------------------------------------------------------

/// Generate a LOG opcode handler for n topics (0..4).
/// Stack: [offset, size, topic0, ..., topicN-1] -> []
/// Gas: G_LOG + G_LOGDATA*size + G_LOGTOPIC*n + memory_expansion
pub fn makeLogFn(comptime n: u8) *const fn (ctx: *InstructionContext) void {
    const impl = struct {
        fn logN(ctx: *InstructionContext) void {
            const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };

            // Static call check
            if (ctx.interpreter.runtime_flags.is_static) {
                ctx.interpreter.halt(.invalid_static); return;
            }

            const stack = &ctx.interpreter.stack;
            const required = 2 + @as(usize, n);
            if (!stack.hasItems(required)) { ctx.interpreter.halt(.stack_underflow); return; }

            const offset = stack.peekUnsafe(0);
            const size = stack.peekUnsafe(1);

            if (offset > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
                ctx.interpreter.halt(.memory_limit_oog); return;
            }

            const offset_u: usize = @intCast(offset);
            const size_u: usize = @intCast(size);

            // Dynamic: data cost + topic cost
            const data_cost: u64 = gas_costs.G_LOGDATA * @as(u64, @intCast(size_u));
            const topic_cost: u64 = gas_costs.G_LOGTOPIC * @as(u64, n);
            if (!ctx.interpreter.gas.spend(data_cost + topic_cost)) {
                ctx.interpreter.halt(.out_of_gas); return;
            }

            // Dynamic: memory expansion
            if (size_u > 0) {
                if (!expandMemory(ctx, offset_u + size_u)) { ctx.interpreter.halt(.out_of_gas); return; }
            }

            // Collect topics into a heap-allocated slice so the pointer remains
            // valid after this function returns (stack-local arrays would dangle).
            const topics: []primitives.Hash = if (comptime n == 0)
                &[_]primitives.Hash{}
            else blk: {
                const t = std.heap.page_allocator.alloc(primitives.Hash, n) catch {
                    ctx.interpreter.halt(.out_of_gas); return;
                };
                inline for (0..n) |i| {
                    const topic_val = stack.peekUnsafe(2 + i);
                    t[i] = host_module.u256ToHash(topic_val);
                }
                break :blk t;
            };

            stack.shrinkUnsafe(2 + n);

            // Get log data from memory
            const log_data: []const u8 = if (size_u > 0)
                ctx.interpreter.memory.buffer.items[offset_u .. offset_u + size_u]
            else
                &[_]u8{};

            // Emit the log
            const log_entry = primitives.Log{
                .address = ctx.interpreter.input.target,
                .topics = topics,
                .data = log_data,
            };
            h.emitLog(log_entry);
        }
    };
    return impl.logN;
}

pub const opLog0 = makeLogFn(0);
pub const opLog1 = makeLogFn(1);
pub const opLog2 = makeLogFn(2);
pub const opLog3 = makeLogFn(3);
pub const opLog4 = makeLogFn(4);

// ---------------------------------------------------------------------------
// SELFDESTRUCT
// ---------------------------------------------------------------------------

/// SELFDESTRUCT (0xFF): Destroy current contract, send ETH to target.
/// Stack: [target] -> []
/// Gas: G_SELFDESTRUCT (5000, static) + dynamic warm/cold + had_value+new_account
pub fn opSelfdestruct(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };

    // Static call check
    if (ctx.interpreter.runtime_flags.is_static) {
        ctx.interpreter.halt(.invalid_static); return;
    }

    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const target_val = stack.popUnsafe();
    const target = host_module.u256ToAddress(target_val);
    const self_addr = ctx.interpreter.input.target;
    const spec = ctx.interpreter.runtime_flags.spec_id;

    const result = h.selfdestruct(self_addr, target) orelse {
        ctx.interpreter.halt(.invalid_opcode); return;
    };

    // Dynamic gas costs
    var dyn_gas: u64 = 0;

    // Berlin+: cold account access cost for target
    if (primitives.isEnabledIn(spec, .berlin) and result.is_cold) {
        dyn_gas += gas_costs.COLD_ACCOUNT_ACCESS;
    }

    // Had value + target account is new/empty → pay new account creation cost
    if (result.had_value and !result.target_exists) {
        dyn_gas += 25000;
    }

    if (!ctx.interpreter.gas.spend(dyn_gas)) { ctx.interpreter.halt(.out_of_gas); return; }

    ctx.interpreter.halt(.selfdestruct);
}
