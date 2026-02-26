const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const context_mod = @import("context");
const Interpreter = @import("interpreter.zig").Interpreter;
const InputsImpl = @import("interpreter.zig").InputsImpl;
const ExtBytecode = @import("interpreter.zig").ExtBytecode;
const Memory = @import("memory.zig").Memory;
const InstructionResult = @import("instruction_result.zig").InstructionResult;
const CallScheme = @import("interpreter_action.zig").CallScheme;

/// Result of a sub-call dispatched via Host.call()
pub const CallResult = struct {
    success: bool,
    return_data: []const u8,
    gas_used: u64,
    gas_remaining: u64,

    pub fn failure(gas_limit: u64) CallResult {
        return .{ .success = false, .return_data = &[_]u8{}, .gas_used = gas_limit, .gas_remaining = 0 };
    }
};

/// Inputs for a sub-call
pub const CallInputs = struct {
    /// Sender of the call (msg.sender in callee)
    caller: primitives.Address,
    /// Execution context address (storage/balance ownership)
    target: primitives.Address,
    /// Contract whose code is executed
    callee: primitives.Address,
    /// Value transferred
    value: primitives.U256,
    /// Call data
    data: []const u8,
    /// Gas limit for the sub-call
    gas_limit: u64,
    /// Call scheme
    scheme: CallScheme,
    /// Whether this is a static (read-only) call
    is_static: bool,
};

/// Result of a selfdestruct operation
pub const SelfDestructLoadResult = struct {
    had_value: bool,
    target_exists: bool,
    previously_destroyed: bool,
    is_cold: bool,
};

/// The Host bridges opcode handlers to the EVM execution context.
/// It provides access to block/tx environment and account state via
/// the journaled state.
///
/// `run_sub_call` is a function pointer set by protocol_schedule.zig
/// to break the circular dependency (host → protocol_schedule → instruction_context → host).
pub const Host = struct {
    ctx: *context_mod.Context,
    /// Callback to run a sub-interpreter. Set by protocol_schedule before execution.
    run_sub_call: *const fn (host: *Host, sub_interp: *Interpreter) void,

    // -----------------------------------------------------------------------
    // Block / transaction environment (no state access required)
    // -----------------------------------------------------------------------

    pub fn origin(self: *Host) primitives.Address {
        return self.ctx.tx.caller;
    }

    pub fn gasPrice(self: *Host) primitives.U256 {
        const max_fee = self.ctx.tx.gas_price;
        if (self.ctx.tx.gas_priority_fee) |priority_fee| {
            const base_fee: u128 = @intCast(self.ctx.block.basefee);
            const effective = @min(max_fee, base_fee + priority_fee);
            return @as(primitives.U256, effective);
        }
        return @as(primitives.U256, max_fee);
    }

    pub fn coinbase(self: *Host) primitives.Address {
        return self.ctx.block.beneficiary;
    }

    pub fn blockNumber(self: *Host) primitives.U256 {
        return self.ctx.block.number;
    }

    pub fn timestamp(self: *Host) primitives.U256 {
        return self.ctx.block.timestamp;
    }

    pub fn blockGasLimit(self: *Host) u64 {
        return self.ctx.block.gas_limit;
    }

    pub fn difficulty(self: *Host) primitives.U256 {
        return self.ctx.block.difficulty;
    }

    pub fn prevrandao(self: *Host) ?primitives.Hash {
        return self.ctx.block.prevrandao;
    }

    pub fn chainId(self: *Host) u64 {
        return self.ctx.cfg.chain_id;
    }

    pub fn basefee(self: *Host) u64 {
        return self.ctx.block.basefee;
    }

    pub fn blobBasefee(self: *Host) u64 {
        if (self.ctx.block.blob_excess_gas_and_price) |b| return b.blob_gasprice;
        return 0;
    }

    pub fn blobHash(self: *Host, index: usize) ?primitives.U256 {
        const blob_hashes = self.ctx.tx.blob_hashes orelse return null;
        if (index >= blob_hashes.items.len) return null;
        return hashToU256(blob_hashes.items[index]);
    }

    pub fn blockHash(self: *Host, number: u64) ?primitives.Hash {
        return self.ctx.blockHash(number);
    }

    // -----------------------------------------------------------------------
    // Account state access (via journaled_state)
    // -----------------------------------------------------------------------

    /// Load account info. Returns null on database error.
    /// is_cold indicates whether this was a cold access (for gas charging).
    pub fn accountInfo(self: *Host, addr: primitives.Address) ?struct { balance: primitives.U256, is_cold: bool, is_empty: bool } {
        const load = self.ctx.journaled_state.loadAccountInfoSkipColdLoad(addr, false, false) catch return null;
        return .{
            .balance = load.info.balance,
            .is_cold = load.is_cold,
            .is_empty = load.is_empty,
        };
    }

    /// Load account with code. Returns null on database error.
    pub fn codeInfo(self: *Host, addr: primitives.Address) ?struct { bytecode: bytecode_mod.Bytecode, code_hash: primitives.Hash, is_cold: bool } {
        const load = self.ctx.journaled_state.loadAccountWithCode(addr) catch return null;
        const acc = load.data;
        const code = if (acc.info.code) |c| c else bytecode_mod.Bytecode.new();
        return .{
            .bytecode = code,
            .code_hash = acc.info.code_hash,
            .is_cold = load.is_cold,
        };
    }

    /// Load account for external code hash. Returns null on database error.
    pub fn extCodeHash(self: *Host, addr: primitives.Address) ?struct { hash: primitives.Hash, is_cold: bool, is_empty: bool } {
        const load = self.ctx.journaled_state.loadAccountInfoSkipColdLoad(addr, false, false) catch return null;
        return .{
            .hash = load.info.code_hash,
            .is_cold = load.is_cold,
            .is_empty = load.is_empty,
        };
    }

    pub fn sload(self: *Host, addr: primitives.Address, key: primitives.U256) ?struct { value: primitives.U256, is_cold: bool } {
        const load = self.ctx.journaled_state.sload(addr, key) catch return null;
        return .{ .value = load.data, .is_cold = load.is_cold };
    }

    pub fn sstore(self: *Host, addr: primitives.Address, key: primitives.U256, val: primitives.U256) ?struct { original: primitives.U256, current: primitives.U256, new: primitives.U256, is_cold: bool } {
        const result = self.ctx.journaled_state.sstore(addr, key, val) catch return null;
        return .{
            .original = result.data.original_value,
            .current = result.data.present_value,
            .new = result.data.new_value,
            .is_cold = result.is_cold,
        };
    }

    pub fn tload(self: *Host, addr: primitives.Address, key: primitives.U256) primitives.U256 {
        return self.ctx.journaled_state.tload(addr, key);
    }

    pub fn tstore(self: *Host, addr: primitives.Address, key: primitives.U256, val: primitives.U256) void {
        self.ctx.journaled_state.tstore(addr, key, val);
    }

    pub fn emitLog(self: *Host, log_entry: primitives.Log) void {
        self.ctx.journaled_state.log(log_entry);
    }

    pub fn selfdestruct(self: *Host, addr: primitives.Address, target: primitives.Address) ?SelfDestructLoadResult {
        const result = self.ctx.journaled_state.selfdestruct(addr, target) catch return null;
        return .{
            .had_value = result.data.had_value,
            .target_exists = result.data.target_exists,
            .previously_destroyed = result.data.previously_destroyed,
            .is_cold = result.is_cold,
        };
    }

    // -----------------------------------------------------------------------
    // Sub-call dispatch
    // -----------------------------------------------------------------------

    pub fn call(self: *Host, inputs: CallInputs) CallResult {
        const MAX_CALL_DEPTH = 1024;

        // 1. Depth check
        if (self.ctx.journaled_state.depth() >= MAX_CALL_DEPTH) {
            return CallResult.failure(inputs.gas_limit);
        }

        // 2. Load callee account and code
        const callee_load = self.ctx.journaled_state.loadAccountWithCode(inputs.callee) catch {
            return CallResult.failure(inputs.gas_limit);
        };
        const callee_acc = callee_load.data;
        const code = if (callee_acc.info.code) |c| c else bytecode_mod.Bytecode.new();

        // 3. Checkpoint before state changes
        const checkpoint = self.ctx.journaled_state.getCheckpoint();

        // 4. Value transfer (if any)
        if (inputs.value > 0) {
            const transfer_err = self.ctx.journaled_state.transfer(inputs.caller, inputs.target, inputs.value) catch {
                self.ctx.journaled_state.checkpointRevert(checkpoint);
                return CallResult.failure(inputs.gas_limit);
            };
            if (transfer_err != null) {
                self.ctx.journaled_state.checkpointRevert(checkpoint);
                return CallResult.failure(inputs.gas_limit);
            }
        }

        // 5. Increment depth
        self.ctx.journaled_state.inner.depth += 1;

        // 6. Build and run sub-interpreter
        const spec_id = self.ctx.journaled_state.inner.spec;
        const sub_mem = Memory.new();
        var sub_interp = Interpreter.new(
            sub_mem,
            ExtBytecode.new(code),
            InputsImpl.new(
                inputs.caller,
                inputs.target,
                inputs.value,
                @constCast(inputs.data),
                inputs.gas_limit,
                inputs.scheme,
                inputs.is_static,
                self.ctx.journaled_state.inner.depth,
            ),
            inputs.is_static,
            spec_id,
            inputs.gas_limit,
        );

        self.run_sub_call(self, &sub_interp);

        // 7. Decrement depth
        self.ctx.journaled_state.inner.depth -= 1;

        // 8. Commit or revert state changes
        const result = sub_interp.result;
        if (result.isSuccess()) {
            self.ctx.journaled_state.checkpointCommit();
        } else {
            self.ctx.journaled_state.checkpointRevert(checkpoint);
        }

        const gas_remaining = sub_interp.gas.remaining;
        const gas_used = if (inputs.gas_limit > gas_remaining) inputs.gas_limit - gas_remaining else 0;

        return CallResult{
            .success = result.isSuccess(),
            .return_data = sub_interp.return_data.data,
            .gas_used = gas_used,
            .gas_remaining = gas_remaining,
        };
    }
};

// ---------------------------------------------------------------------------
// Conversion helpers (exported for use by opcode handlers)
// ---------------------------------------------------------------------------

/// Convert an Address (20 bytes big-endian) to U256
pub fn addressToU256(addr: primitives.Address) primitives.U256 {
    var result: primitives.U256 = 0;
    for (addr) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}

/// Convert U256 to Address (take low 20 bytes)
pub fn u256ToAddress(val: primitives.U256) primitives.Address {
    var addr: primitives.Address = [_]u8{0} ** 20;
    var v = val;
    var i: usize = 20;
    while (i > 0) {
        i -= 1;
        addr[i] = @intCast(v & 0xFF);
        v >>= 8;
    }
    return addr;
}

/// Convert a 32-byte Hash to U256 (big-endian)
pub fn hashToU256(h: primitives.Hash) primitives.U256 {
    var result: primitives.U256 = 0;
    for (h) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}

/// Convert U256 to a 32-byte Hash (big-endian)
pub fn u256ToHash(val: primitives.U256) primitives.Hash {
    var h: primitives.Hash = [_]u8{0} ** 32;
    var v = val;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        h[i] = @intCast(v & 0xFF);
        v >>= 8;
    }
    return h;
}
