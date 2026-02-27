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
const gas_costs = @import("gas_costs.zig");

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

/// Result of a CREATE / CREATE2 operation
pub const CreateResult = struct {
    success: bool,
    address: primitives.Address,
    gas_remaining: u64,
    return_data: []const u8,

    pub fn failure() CreateResult {
        return .{ .success = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{} };
    }
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

    /// Execute a CREATE or CREATE2.  Returns the new contract address on success,
    /// or zero address on failure.  Caller must be pre-loaded in journaled_state.
    pub fn create(
        self: *Host,
        caller: primitives.Address,
        value: primitives.U256,
        init_code: []const u8,
        gas_limit: u64,
        comptime is_create2: bool,
        salt: primitives.U256,
    ) CreateResult {
        const MAX_CALL_DEPTH = 1024;
        const MAX_CODE_SIZE: usize = 24576;
        const MAX_INITCODE_SIZE: usize = 2 * MAX_CODE_SIZE; // EIP-3860

        const js = &self.ctx.journaled_state;
        const spec_id = js.inner.spec;

        // 1. Depth check
        if (js.depth() >= MAX_CALL_DEPTH) return CreateResult.failure();

        // 2. EIP-3860 (Shanghai+): init code size limit
        if (primitives.isEnabledIn(spec_id, .shanghai)) {
            if (init_code.len > MAX_INITCODE_SIZE) return CreateResult.failure();
        }

        // 3. Bump caller nonce BEFORE checkpoint so the bump is never reverted by CREATE failure
        const caller_acc = js.inner.evm_state.getPtr(caller) orelse return CreateResult.failure();
        const caller_nonce = caller_acc.info.nonce;
        caller_acc.info.nonce = caller_nonce +| 1;
        js.nonceBumpJournalEntry(caller);

        // 4. Derive new contract address
        const new_addr: primitives.Address = if (is_create2) blk: {
            var init_hash: [32]u8 = undefined;
            std.crypto.hash.sha3.Keccak256.hash(init_code, &init_hash, .{});
            break :blk create2Address(caller, salt, init_hash);
        } else createAddress(caller, caller_nonce);

        // 5. Load target address into state (required before createAccountCheckpoint)
        _ = js.loadAccount(new_addr) catch return CreateResult.failure();

        // 6. Create account checkpoint: collision check, value transfer, set nonce=1 (EIP-161)
        const checkpoint = js.createAccountCheckpoint(caller, new_addr, value, spec_id) catch {
            return CreateResult.failure();
        };

        // 7. Increment depth for sub-interpreter
        js.inner.depth += 1;

        // 8. Build and run init-code sub-interpreter
        const sub_mem = Memory.new();
        const init_bytecode = bytecode_mod.Bytecode.newRaw(init_code);
        var sub_interp = Interpreter.new(
            sub_mem,
            ExtBytecode.new(init_bytecode),
            InputsImpl.new(
                caller,
                new_addr,
                value,
                @constCast(init_code),
                gas_limit,
                .call,
                false, // not static
                js.inner.depth,
            ),
            false,
            spec_id,
            gas_limit,
        );
        self.run_sub_call(self, &sub_interp);

        // 9. Decrement depth
        js.inner.depth -= 1;

        // 10. Handle sub-interpreter failure
        if (!sub_interp.result.isSuccess()) {
            js.checkpointRevert(checkpoint);
            return .{
                .success = false,
                .address = [_]u8{0} ** 20,
                .gas_remaining = sub_interp.gas.remaining,
                .return_data = sub_interp.return_data.data,
            };
        }

        // 11. Validate deployed code
        const deployed = sub_interp.return_data.data;
        if (deployed.len > MAX_CODE_SIZE) {
            js.checkpointRevert(checkpoint);
            return .{ .success = false, .address = [_]u8{0} ** 20,
                       .gas_remaining = sub_interp.gas.remaining, .return_data = &[_]u8{} };
        }
        // EIP-3541 (London+): reject code starting with 0xEF
        if (primitives.isEnabledIn(spec_id, .london)) {
            if (deployed.len > 0 and deployed[0] == 0xEF) {
                js.checkpointRevert(checkpoint);
                return .{ .success = false, .address = [_]u8{0} ** 20,
                           .gas_remaining = sub_interp.gas.remaining, .return_data = &[_]u8{} };
            }
        }

        // 12. Code deposit gas: 200 per byte of deployed code
        const deposit_cost = gas_costs.G_CODEDEPOSIT * @as(u64, @intCast(deployed.len));
        if (sub_interp.gas.remaining < deposit_cost) {
            js.checkpointRevert(checkpoint);
            return CreateResult.failure();
        }
        const gas_after_deposit = sub_interp.gas.remaining - deposit_cost;

        // 13. Store deployed bytecode
        if (deployed.len > 0) {
            var code_hash: [32]u8 = undefined;
            std.crypto.hash.sha3.Keccak256.hash(deployed, &code_hash, .{});
            const bc = bytecode_mod.Bytecode.newRaw(deployed);
            js.setCodeWithHash(new_addr, bc, code_hash);
        }

        // 14. Commit sub-call state
        js.checkpointCommit();

        return .{
            .success = true,
            .address = new_addr,
            .gas_remaining = gas_after_deposit,
            .return_data = sub_interp.return_data.data,
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

/// Derive CREATE contract address: keccak256(rlp([sender, nonce]))[12:]
pub fn createAddress(sender: primitives.Address, nonce: u64) primitives.Address {
    // Build RLP encoding of [sender, nonce]
    // RLP(address): 0x94 (= 0x80+20) prefix + 20 bytes
    // RLP(nonce): 0x80 for zero, single byte for 1-127, length-prefixed for >= 128
    // List header: 0xC0 + content_len
    var buf: [30]u8 = undefined; // 1 + 20 + 1..9 = at most 30 bytes of content
    var pos: usize = 0;
    buf[pos] = 0x94; pos += 1;
    @memcpy(buf[pos..pos + 20], &sender); pos += 20;
    if (nonce == 0) {
        buf[pos] = 0x80; pos += 1;
    } else if (nonce < 0x80) {
        buf[pos] = @intCast(nonce); pos += 1;
    } else {
        // Encode nonce as minimal big-endian bytes
        var tmp: [8]u8 = undefined;
        var len: usize = 0;
        var n = nonce;
        while (n > 0) : (n >>= 8) { len += 1; }
        var m = nonce;
        var idx: usize = len;
        while (idx > 0) : (idx -= 1) { tmp[idx - 1] = @intCast(m & 0xFF); m >>= 8; }
        buf[pos] = @intCast(0x80 + len); pos += 1;
        @memcpy(buf[pos..pos + len], tmp[0..len]); pos += len;
    }
    // List prefix: 0xC0 + content_len
    var rlp: [31]u8 = undefined;
    rlp[0] = @intCast(0xC0 + pos);
    @memcpy(rlp[1..1 + pos], buf[0..pos]);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(rlp[0..1 + pos], &hash, .{});
    var addr: primitives.Address = undefined;
    @memcpy(&addr, hash[12..32]);
    return addr;
}

/// Derive CREATE2 contract address: keccak256(0xff ++ sender ++ salt ++ keccak256(init_code))[12:]
pub fn create2Address(sender: primitives.Address, salt: primitives.U256, init_code_hash: [32]u8) primitives.Address {
    var preimage: [85]u8 = undefined; // 1 + 20 + 32 + 32
    preimage[0] = 0xFF;
    @memcpy(preimage[1..21], &sender);
    // Encode salt as 32-byte big-endian
    var salt_bytes: [32]u8 = undefined;
    var s = salt;
    var i: usize = 32;
    while (i > 0) : (i -= 1) { salt_bytes[i - 1] = @intCast(s & 0xFF); s >>= 8; }
    @memcpy(preimage[21..53], &salt_bytes);
    @memcpy(preimage[53..85], &init_code_hash);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(&preimage, &hash, .{});
    var addr: primitives.Address = undefined;
    @memcpy(&addr, hash[12..32]);
    return addr;
}
