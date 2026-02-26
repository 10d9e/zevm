const std = @import("std");
const primitives = @import("primitives");
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const gas_costs = @import("../gas_costs.zig");
const host_module = @import("../host.zig");

// ---------------------------------------------------------------------------
// Memory expansion helper (shared pattern from other opcode files)
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
// Opcodes that read from interpreter.input (no Host required)
// ---------------------------------------------------------------------------

/// ADDRESS (0x30): Push the address of the currently executing contract.
/// Stack: [] -> [address]   Gas: 2 (G_BASE, dispatch)
pub fn opAddress(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(host_module.addressToU256(ctx.interpreter.input.target));
}

/// CALLER (0x33): Push the caller address (msg.sender).
/// Stack: [] -> [caller]   Gas: 2 (G_BASE, dispatch)
pub fn opCaller(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(host_module.addressToU256(ctx.interpreter.input.caller));
}

/// CALLVALUE (0x34): Push the value sent with this call (msg.value).
/// Stack: [] -> [value]   Gas: 2 (G_BASE, dispatch)
pub fn opCallvalue(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(ctx.interpreter.input.value);
}

/// CALLDATASIZE (0x36): Push the size of the call data.
/// Stack: [] -> [size]   Gas: 2 (G_BASE, dispatch)
pub fn opCalldatasize(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(@intCast(ctx.interpreter.input.data.len));
}

/// CALLDATALOAD (0x35): Load 32 bytes from calldata at offset.
/// Stack: [offset] -> [data]   Gas: 3 (G_VERYLOW, dispatch)
pub fn opCalldataload(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const offset = stack.peekUnsafe(0);
    const data = ctx.interpreter.input.data;

    var word: [32]u8 = [_]u8{0} ** 32;
    if (offset <= std.math.maxInt(usize)) {
        const off: usize = @intCast(offset);
        if (off < data.len) {
            const available = data.len - off;
            const to_copy = @min(available, 32);
            @memcpy(word[0..to_copy], data[off .. off + to_copy]);
        }
    }

    const U = primitives.U256;
    const value: U = (@as(U, std.mem.readInt(u64, word[0..8], .big)) << 192) |
        (@as(U, std.mem.readInt(u64, word[8..16], .big)) << 128) |
        (@as(U, std.mem.readInt(u64, word[16..24], .big)) << 64) |
        @as(U, std.mem.readInt(u64, word[24..32], .big));

    stack.setTopUnsafe().* = value;
}

/// CALLDATACOPY (0x37): Copy call data to memory.
/// Stack: [memOff, dataOff, size] -> []   Gas: 3 + copy_words*3 + mem_expansion
pub fn opCalldatacopy(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) { ctx.interpreter.halt(.stack_underflow); return; }

    const mem_off = stack.peekUnsafe(0);
    const data_off = stack.peekUnsafe(1);
    const size = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    if (size == 0) return;

    if (mem_off > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }

    const mem_off_usize: usize = @intCast(mem_off);
    const size_usize: usize = @intCast(size);
    const new_size = mem_off_usize + size_usize;

    // Dynamic: copy cost
    const num_words = (size_usize + 31) / 32;
    const copy_cost: u64 = gas_costs.G_COPY * @as(u64, @intCast(num_words));
    if (!ctx.interpreter.gas.spend(copy_cost)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Dynamic: memory expansion
    if (!expandMemory(ctx, new_size)) { ctx.interpreter.halt(.out_of_gas); return; }

    const dest = ctx.interpreter.memory.buffer.items[mem_off_usize .. mem_off_usize + size_usize];
    const data = ctx.interpreter.input.data;
    if (data_off > std.math.maxInt(usize)) {
        @memset(dest, 0);
    } else {
        const data_off_usize: usize = @intCast(data_off);
        if (data_off_usize >= data.len) {
            @memset(dest, 0);
        } else {
            const available = data.len - data_off_usize;
            const to_copy = @min(available, size_usize);
            @memcpy(dest[0..to_copy], data[data_off_usize .. data_off_usize + to_copy]);
            if (to_copy < size_usize) @memset(dest[to_copy..], 0);
        }
    }
}

/// CODESIZE (0x38): Push the size of the currently executing code.
/// Stack: [] -> [size]   Gas: 2 (G_BASE, dispatch)
pub fn opCodesize(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    const code_len = ctx.interpreter.bytecode.bytecode.bytecode().len;
    stack.pushUnsafe(@intCast(code_len));
}

/// CODECOPY (0x39): Copy code to memory.
/// Stack: [memOff, codeOff, size] -> []   Gas: 3 + copy_words*3 + mem_expansion
pub fn opCodecopy(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) { ctx.interpreter.halt(.stack_underflow); return; }

    const mem_off = stack.peekUnsafe(0);
    const code_off = stack.peekUnsafe(1);
    const size = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    if (size == 0) return;

    if (mem_off > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }

    const mem_off_usize: usize = @intCast(mem_off);
    const size_usize: usize = @intCast(size);
    const new_size = mem_off_usize + size_usize;

    // Dynamic: copy cost
    const num_words = (size_usize + 31) / 32;
    const copy_cost: u64 = gas_costs.G_COPY * @as(u64, @intCast(num_words));
    if (!ctx.interpreter.gas.spend(copy_cost)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Dynamic: memory expansion
    if (!expandMemory(ctx, new_size)) { ctx.interpreter.halt(.out_of_gas); return; }

    const dest = ctx.interpreter.memory.buffer.items[mem_off_usize .. mem_off_usize + size_usize];
    const code = ctx.interpreter.bytecode.bytecode.bytecode();

    if (code_off > std.math.maxInt(usize)) {
        @memset(dest, 0);
    } else {
        const code_off_usize: usize = @intCast(code_off);
        if (code_off_usize >= code.len) {
            @memset(dest, 0);
        } else {
            const available = code.len - code_off_usize;
            const to_copy = @min(available, size_usize);
            @memcpy(dest[0..to_copy], code[code_off_usize .. code_off_usize + to_copy]);
            if (to_copy < size_usize) @memset(dest[to_copy..], 0);
        }
    }
}

/// RETURNDATASIZE (0x3D): Push the size of the last sub-call's return data.
/// Stack: [] -> [size]   Gas: 2 (G_BASE, dispatch)
pub fn opReturndatasize(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(@intCast(ctx.interpreter.return_data.data.len));
}

/// RETURNDATACOPY (0x3E): Copy return data from last sub-call to memory.
/// Stack: [memOff, srcOff, size] -> []   Gas: 3 + copy_words*3 + mem_expansion
pub fn opReturndatacopy(ctx: *InstructionContext) void {
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(3)) { ctx.interpreter.halt(.stack_underflow); return; }

    const mem_off = stack.peekUnsafe(0);
    const src_off = stack.peekUnsafe(1);
    const size = stack.peekUnsafe(2);
    stack.shrinkUnsafe(3);

    if (size == 0) return;

    if (mem_off > std.math.maxInt(usize) or src_off > std.math.maxInt(usize) or size > std.math.maxInt(usize)) {
        ctx.interpreter.halt(.memory_limit_oog); return;
    }

    const mem_off_usize: usize = @intCast(mem_off);
    const src_off_usize: usize = @intCast(src_off);
    const size_usize: usize = @intCast(size);

    // Bounds check: src_off + size must be within return data
    const return_data = ctx.interpreter.return_data.data;
    if (src_off_usize > return_data.len or size_usize > return_data.len - src_off_usize) {
        ctx.interpreter.halt(.invalid_returndata); return;
    }

    const new_size = mem_off_usize + size_usize;

    // Dynamic: copy cost
    const num_words = (size_usize + 31) / 32;
    const copy_cost: u64 = gas_costs.G_COPY * @as(u64, @intCast(num_words));
    if (!ctx.interpreter.gas.spend(copy_cost)) { ctx.interpreter.halt(.out_of_gas); return; }

    // Dynamic: memory expansion
    if (!expandMemory(ctx, new_size)) { ctx.interpreter.halt(.out_of_gas); return; }

    @memcpy(
        ctx.interpreter.memory.buffer.items[mem_off_usize .. mem_off_usize + size_usize],
        return_data[src_off_usize .. src_off_usize + size_usize],
    );
}

// ---------------------------------------------------------------------------
// Opcodes that require the Host (block/tx environment)
// ---------------------------------------------------------------------------

/// ORIGIN (0x32): Push the origin address of the transaction (tx.origin).
/// Stack: [] -> [origin]   Gas: 2 (G_BASE, dispatch)
pub fn opOrigin(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(host_module.addressToU256(h.origin()));
}

/// GASPRICE (0x3A): Push the effective gas price of this transaction.
/// Stack: [] -> [gasPrice]   Gas: 2 (G_BASE, dispatch)
pub fn opGasprice(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(h.gasPrice());
}

/// COINBASE (0x41): Push the block's beneficiary address.
/// Stack: [] -> [coinbase]   Gas: 2 (G_BASE, dispatch)
pub fn opCoinbase(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(host_module.addressToU256(h.coinbase()));
}

/// TIMESTAMP (0x42): Push the block timestamp.
/// Stack: [] -> [timestamp]   Gas: 2 (G_BASE, dispatch)
pub fn opTimestamp(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(h.timestamp());
}

/// NUMBER (0x43): Push the current block number.
/// Stack: [] -> [number]   Gas: 2 (G_BASE, dispatch)
pub fn opNumber(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(h.blockNumber());
}

/// DIFFICULTY (0x44): Push block difficulty (or PREVRANDAO after Paris).
/// Stack: [] -> [difficulty]   Gas: 2 (G_BASE, dispatch)
pub fn opDifficulty(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }

    // After Paris (EIP-4399): use prevrandao if available
    const spec = ctx.interpreter.runtime_flags.spec_id;
    if (primitives.isEnabledIn(spec, .merge)) {
        if (h.prevrandao()) |pr| {
            stack.pushUnsafe(host_module.hashToU256(pr));
            return;
        }
    }
    stack.pushUnsafe(h.difficulty());
}

/// GASLIMIT (0x45): Push the block gas limit.
/// Stack: [] -> [gasLimit]   Gas: 2 (G_BASE, dispatch)
pub fn opGaslimit(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(@as(primitives.U256, h.blockGasLimit()));
}

/// CHAINID (0x46): Push the chain ID (EIP-1344, Istanbul+).
/// Stack: [] -> [chainId]   Gas: 2 (G_BASE, dispatch)
pub fn opChainid(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(@as(primitives.U256, h.chainId()));
}

/// BASEFEE (0x48): Push the base fee per gas (EIP-3198, London+).
/// Stack: [] -> [basefee]   Gas: 2 (G_BASE, dispatch)
pub fn opBasefee(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(@as(primitives.U256, h.basefee()));
}

/// BLOBHASH (0x49): Push a blob versioned hash (EIP-4844, Cancun+).
/// Stack: [index] -> [blobHash]   Gas: 3 (G_VERYLOW, dispatch)
pub fn opBlobhash(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasItems(1)) { ctx.interpreter.halt(.stack_underflow); return; }

    const index = stack.peekUnsafe(0);
    if (index > std.math.maxInt(usize)) {
        stack.setTopUnsafe().* = 0;
        return;
    }
    const idx: usize = @intCast(index);
    const val = h.blobHash(idx) orelse 0;
    stack.setTopUnsafe().* = val;
}

/// BLOBBASEFEE (0x4A): Push the blob base fee (EIP-7516, Cancun+).
/// Stack: [] -> [blobBasefee]   Gas: 2 (G_BASE, dispatch)
pub fn opBlobbasefee(ctx: *InstructionContext) void {
    const h = ctx.host orelse { ctx.interpreter.halt(.invalid_opcode); return; };
    const stack = &ctx.interpreter.stack;
    if (!stack.hasSpace(1)) { ctx.interpreter.halt(.stack_overflow); return; }
    stack.pushUnsafe(@as(primitives.U256, h.blobBasefee()));
}
