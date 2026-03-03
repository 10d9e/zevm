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
const precompile_mod = @import("precompile");

/// Result of a sub-call dispatched via Host.call()
pub const CallResult = struct {
    success: bool,
    return_data: []const u8,
    gas_used: u64,
    gas_remaining: u64,
    /// Refund counter accumulated inside the sub-call (SSTORE clears, etc.).
    /// Must be added to the parent frame's gas.refunded on return.
    gas_refunded: i64,
    /// EIP-7702: gas charged for loading the delegation target (if any).
    /// Must be deducted from the parent frame's remaining gas after the call.
    delegation_gas: u64,

    /// Sub-call failed after execution (all gas consumed).
    pub fn failure(gas_limit: u64) CallResult {
        return .{ .success = false, .return_data = &[_]u8{}, .gas_used = gas_limit, .gas_remaining = 0, .gas_refunded = 0, .delegation_gas = 0 };
    }

    /// Sub-call failed BEFORE execution (depth limit, value-transfer failure).
    /// Per EVM spec: when no sub-code runs, all forwarded gas is returned to caller.
    pub fn preExecFailure(gas_limit: u64) CallResult {
        return .{ .success = false, .return_data = &[_]u8{}, .gas_used = 0, .gas_remaining = gas_limit, .gas_refunded = 0, .delegation_gas = 0 };
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
    /// True when the init-code explicitly executed REVERT (gas is returned, revert reason in
    /// return_data). False for any other failure (OOG, bad opcode, pre-execution guard, etc.).
    is_revert: bool,
    address: primitives.Address,
    gas_remaining: u64,
    return_data: []const u8,
    /// Refund counter accumulated inside the init-code sub-interpreter.
    gas_refunded: i64,

    /// Pre-execution failure: no sub-interpreter ran, return all forwarded gas.
    pub fn preExecFailure(gas_limit: u64) CreateResult {
        return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = gas_limit, .return_data = &[_]u8{}, .gas_refunded = 0 };
    }

    /// Post-execution failure: sub-interpreter ran and consumed gas.
    pub fn failure() CreateResult {
        return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20, .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0 };
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
    /// Precompile set for the current spec. Null disables precompile dispatch (benchmarks/unit tests).
    precompiles: ?*const precompile_mod.Precompiles = null,
    /// Instruction dispatch table for the current spec. Stored here so sub-calls can reuse
    /// the same table pointer instead of allocating a fresh 4 KB table on the native stack.
    instruction_table: ?*const @import("interpreter.zig").InstructionTable = null,

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
    /// Per EIP-7702: EXTCODESIZE/EXTCODECOPY/EXTCODEHASH operate on the delegation POINTER bytes
    /// (23-byte 0xef0100||addr), NOT the delegation target's code. Return as-is.
    pub fn codeInfo(self: *Host, addr: primitives.Address) ?struct { bytecode: bytecode_mod.Bytecode, code_hash: primitives.Hash, is_cold: bool } {
        const load = self.ctx.journaled_state.loadAccountWithCode(addr) catch return null;
        const acc = load.data;
        const code = if (acc.info.code) |c| c else bytecode_mod.Bytecode.new();
        const code_hash = acc.info.code_hash;
        return .{
            .bytecode = code,
            .code_hash = code_hash,
            .is_cold = load.is_cold,
        };
    }

    /// Load account for external code hash. Returns null on database error.
    /// Per EIP-7702: EXTCODEHASH returns keccak256 of the delegation pointer bytes (not the target).
    /// code_hash is already stored as keccak256(delegation_pointer) when the account is loaded.
    pub fn extCodeHash(self: *Host, addr: primitives.Address) ?struct { hash: primitives.Hash, is_cold: bool, is_empty: bool } {
        const load = self.ctx.journaled_state.loadAccountWithCode(addr) catch return null;
        const acct = load.data;
        const hash = acct.info.code_hash;
        // An account is "non-existing" (returns 0) only if it was loaded as not-existing
        // from the DB AND has never been touched during this transaction.
        // Accounts that were touched (e.g., by EIP-7702 setCode clearing delegation to 0x0)
        // are considered existing and return KECCAK_EMPTY (not 0) even with empty code.
        const is_empty = acct.isLoadedAsNotExistingNotTouched();
        return .{
            .hash = hash,
            .is_cold = load.is_cold,
            .is_empty = is_empty,
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

        // 1. Depth check: no sub-code ran → return all gas to caller.
        if (self.ctx.journaled_state.depth() >= MAX_CALL_DEPTH) {
            return CallResult.preExecFailure(inputs.gas_limit);
        }

        // 1b. Precompile dispatch: if the callee is a precompile, run it instead of the interpreter.
        // Value transfer still occurs (ETH accumulates at the precompile address).
        if (self.precompiles) |pcs| {
            if (pcs.get(inputs.callee)) |pc| {
                const checkpoint = self.ctx.journaled_state.getCheckpoint();
                // Value transfer (target == callee for normal CALL).
                // Per EVM spec: if value transfer fails (insufficient balance), no code ran,
                // so all forwarded gas is returned to caller (preExecFailure, not failure).
                // DELEGATECALL inherits msg.value but does NOT transfer ETH.
                if (inputs.value > 0 and inputs.scheme != .delegatecall) {
                    const xfer_err = self.ctx.journaled_state.transfer(inputs.caller, inputs.target, inputs.value) catch {
                        self.ctx.journaled_state.checkpointRevert(checkpoint);
                        return CallResult.preExecFailure(inputs.gas_limit);
                    };
                    if (xfer_err != null) {
                        self.ctx.journaled_state.checkpointRevert(checkpoint);
                        return CallResult.preExecFailure(inputs.gas_limit);
                    }
                }
                const pc_result = pc.execute(inputs.data, inputs.gas_limit);
                switch (pc_result) {
                    .success => |out| {
                        if (out.reverted) {
                            self.ctx.journaled_state.checkpointRevert(checkpoint);
                            return .{ .success = false, .return_data = out.bytes,
                                       .gas_used = inputs.gas_limit, .gas_remaining = 0, .gas_refunded = 0, .delegation_gas = 0 };
                        }
                        self.ctx.journaled_state.checkpointCommit();
                        return .{ .success = true, .return_data = out.bytes,
                                   .gas_used = out.gas_used,
                                   .gas_remaining = inputs.gas_limit - out.gas_used, .gas_refunded = 0, .delegation_gas = 0 };
                    },
                    .err => {
                        self.ctx.journaled_state.checkpointRevert(checkpoint);
                        return CallResult.failure(inputs.gas_limit);
                    },
                }
            }
        }

        // 2. Load callee account and code
        const callee_load = self.ctx.journaled_state.loadAccountWithCode(inputs.callee) catch {
            return CallResult.failure(inputs.gas_limit);
        };
        const callee_acc = callee_load.data;
        var code = if (callee_acc.info.code) |c| c else bytecode_mod.Bytecode.new();

        // EIP-7702: if callee has delegation code, follow it to get the code to execute.
        // The call context (ADDRESS, storage) still refers to the authority (callee),
        // but the bytecode executed comes from the delegation target. No recursive following.
        // Per EIP-7702: loading the delegation target incurs warm/cold access cost,
        // charged to the parent frame (returned as delegation_gas in CallResult).
        var delegation_gas: u64 = 0;
        if (code.isEip7702()) {
            const delegation_addr = code.eip7702.address;
            if (self.ctx.journaled_state.loadAccountWithCode(delegation_addr)) |del_load| {
                delegation_gas = if (del_load.is_cold)
                    gas_costs.COLD_ACCOUNT_ACCESS
                else
                    gas_costs.WARM_ACCOUNT_ACCESS;
                code = if (del_load.data.info.code) |del_code|
                    del_code // per EIP-7702: execute target's code as-is (no recursion; 0xef → INVALID)
                else
                    bytecode_mod.Bytecode.new();
            } else |_| {
                code = bytecode_mod.Bytecode.new();
            }
        }

        // 3. Checkpoint before state changes
        const checkpoint = self.ctx.journaled_state.getCheckpoint();

        // 4. Value transfer (if any).
        // DELEGATECALL inherits msg.value (CALLVALUE opcode) from parent but does NOT
        // transfer ETH. Only CALL and CALLCODE actually move ETH.
        // Transfer failure means no sub-code ran → return all gas to caller.
        if (inputs.value > 0 and inputs.scheme != .delegatecall) {
            const transfer_err = self.ctx.journaled_state.transfer(inputs.caller, inputs.target, inputs.value) catch {
                self.ctx.journaled_state.checkpointRevert(checkpoint);
                return CallResult.preExecFailure(inputs.gas_limit);
            };
            if (transfer_err != null) {
                self.ctx.journaled_state.checkpointRevert(checkpoint);
                return CallResult.preExecFailure(inputs.gas_limit);
            }
        }

        // 5. Build and run sub-interpreter.
        // Heap-allocate to avoid native stack overflow on deep recursive EVM calls.
        // The embedded Stack (32 KB) would exhaust the native stack at ~200 levels otherwise.
        // Note: sub_interp is not freed here because return_data.data slices into
        // sub_interp.memory.buffer.items which must remain valid for the caller.
        // Depth is already incremented by getCheckpoint() above; no manual adjustment needed.
        const spec_id = self.ctx.journaled_state.inner.spec;
        const sub_mem = Memory.new();
        const sub_interp = std.heap.c_allocator.create(Interpreter) catch {
            self.ctx.journaled_state.checkpointRevert(checkpoint);
            return CallResult.preExecFailure(inputs.gas_limit);
        };
        sub_interp.* = Interpreter.new(
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

        self.run_sub_call(self, sub_interp);

        // 6. Commit or revert state changes
        const result = sub_interp.result;
        if (result.isSuccess()) {
            self.ctx.journaled_state.checkpointCommit();
        } else {
            self.ctx.journaled_state.checkpointRevert(checkpoint);
        }

        // EVM gas return rules:
        //   - Success (stop/return/selfdestruct): return unused gas to caller
        //   - REVERT: return unused gas to caller
        //   - Any error (stack underflow/overflow, bad opcode, bad jump, etc.):
        //     all remaining gas is consumed; return 0
        const gas_remaining: u64 = if (result.isSuccess() or result == .revert) sub_interp.gas.remaining else 0;
        const gas_used = if (inputs.gas_limit > gas_remaining) inputs.gas_limit - gas_remaining else 0;
        // Propagate sub-call refund counter (SSTORE clears, etc.) to caller frame.
        const gas_refunded: i64 = if (result.isSuccess()) sub_interp.gas.refunded else 0;

        return CallResult{
            .success = result.isSuccess(),
            // EVM semantics: return data is only populated on SUCCESS or REVERT.
            // Any other failure (OOG, stack overflow, bad opcode, etc.) returns empty data.
            .return_data = if (result.isSuccess() or result == .revert) sub_interp.return_data.data else &[_]u8{},
            .gas_used = gas_used,
            .gas_remaining = gas_remaining,
            .gas_refunded = gas_refunded,
            .delegation_gas = 0, // delegation_gas is now charged upfront in callImpl (before 63/64)
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
        /// When true, the caller nonce has already been incremented by tx validation.
        /// The nonce bump is skipped here but the pre-bump nonce is still used for address derivation.
        comptime skip_nonce_bump: bool,
    ) CreateResult {
        const MAX_CALL_DEPTH = 1024;
        const MAX_CODE_SIZE: usize = 24576;
        const MAX_INITCODE_SIZE: usize = 2 * MAX_CODE_SIZE; // EIP-3860

        const js = &self.ctx.journaled_state;
        const spec_id = js.inner.spec;

        // 1. Depth check
        if (js.depth() >= MAX_CALL_DEPTH) return CreateResult.preExecFailure(gas_limit);

        // 2. EIP-3860 (Shanghai+): init code size limit
        if (primitives.isEnabledIn(spec_id, .shanghai)) {
            if (init_code.len > MAX_INITCODE_SIZE) return CreateResult.preExecFailure(gas_limit);
        }

        // 2.5. Early balance check: if value > 0, verify caller has sufficient balance BEFORE
        //      bumping the nonce. Per go-ethereum and the Yellow Paper, nonce is NOT incremented
        //      when CREATE fails due to insufficient balance (unlike EIP-161/code collision which
        //      happens after the nonce bump and does not revert it).
        if (value > 0) {
            const acct = js.inner.evm_state.getPtr(caller) orelse return CreateResult.preExecFailure(gas_limit);
            if (acct.info.balance < value) return CreateResult.preExecFailure(gas_limit);
        }

        // 3. Manage caller nonce BEFORE checkpoint (nonce bump is never reverted by CREATE failure).
        //    skip_nonce_bump=true means tx validation already bumped the nonce from N to N+1;
        //    we still need N for address derivation.
        const caller_acc = js.inner.evm_state.getPtr(caller) orelse return CreateResult.preExecFailure(gas_limit);
        const caller_nonce: u64 = if (skip_nonce_bump)
            // Already bumped: current nonce is N+1, use N for address derivation
            caller_acc.info.nonce -| 1
        else blk: {
            // Normal opcode path: read N, bump to N+1, record journal entry
            const n = caller_acc.info.nonce;
            // EIP-2681: nonce must not overflow u64
            if (n == std.math.maxInt(u64)) return CreateResult.preExecFailure(gas_limit);
            caller_acc.info.nonce = n + 1;
            js.nonceBumpJournalEntry(caller);
            break :blk n;
        };

        // 4. Derive new contract address
        const new_addr: primitives.Address = if (is_create2) blk: {
            var init_hash: [32]u8 = undefined;
            std.crypto.hash.sha3.Keccak256.hash(init_code, &init_hash, .{});
            break :blk create2Address(caller, salt, init_hash);
        } else createAddress(caller, caller_nonce);

        // 5. Load target address into state (required before createAccountCheckpoint)
        _ = js.loadAccount(new_addr) catch return CreateResult.preExecFailure(gas_limit);

        // EIP-7610: CREATE fails if target address has non-empty storage in the DB.
        // Per EIP-7610, storage collision consumes ALL forwarded gas (like OOG), not a preExecFailure
        // that returns gas. Return gas_remaining=0 so the 63/64 rule keeps only 1/64 for the caller.
        // Check loaded storage in evm_state (from prior SLOAD/SSTORE) and in DB (pre-inserted).
        if (js.inner.evm_state.get(new_addr)) |acct| {
            var slot_it = acct.storage.valueIterator();
            while (slot_it.next()) |slot| {
                if (slot.presentValue() != 0) return CreateResult.preExecFailure(0);
            }
        }
        {
            var db_it = js.database.storage_map.iterator();
            while (db_it.next()) |entry| {
                if (std.mem.eql(u8, &entry.key_ptr.@"0", &new_addr) and entry.value_ptr.* != 0)
                    return CreateResult.preExecFailure(0);
            }
        }

        // 6. Create account checkpoint: collision check, value transfer, set nonce=1 (EIP-161)
        // EIP-7610: nonce/code collision consumes all forwarded gas (like OOG), same as storage collision.
        const checkpoint = js.createAccountCheckpoint(caller, new_addr, value, spec_id) catch {
            return CreateResult.preExecFailure(0);
        };

        // 7. Build and run init-code sub-interpreter (heap-allocated; see call() comment above).
        // Depth is already incremented by createAccountCheckpoint() → getCheckpoint() above.
        const sub_mem = Memory.new();
        const init_bytecode = bytecode_mod.Bytecode.newRaw(init_code);
        const sub_interp = std.heap.c_allocator.create(Interpreter) catch {
            js.checkpointRevert(checkpoint);
            return CreateResult.preExecFailure(gas_limit);
        };
        // Per EVM Yellow Paper: I_d (input data) is empty for CREATE/CREATE2 sub-executions.
        // The initcode is the CODE being executed; calldata is empty. Initcode reads its own
        // bytes via CODECOPY (not CALLDATALOAD). Passing init_code as calldata would cause
        // CALLDATALOAD to return non-zero values, inflating gas costs (SSTORE_SET vs no-op).
        sub_interp.* = Interpreter.new(
            sub_mem,
            ExtBytecode.new(init_bytecode),
            InputsImpl.new(
                caller,
                new_addr,
                value,
                @constCast(&[_]u8{}), // Empty calldata for CREATE sub-context
                gas_limit,
                .call,
                false, // not static
                js.inner.depth,
            ),
            false,
            spec_id,
            gas_limit,
        );
        self.run_sub_call(self, sub_interp);

        // 8. Handle sub-interpreter failure
        if (!sub_interp.result.isSuccess()) {
            js.checkpointRevert(checkpoint);
            // EVM gas return rules for CREATE:
            //   - REVERT: return unused gas to caller
            //   - Any error (invalid opcode, stack underflow, OOG, etc.): all gas consumed, return 0
            const gas_rem = if (sub_interp.result == .revert) sub_interp.gas.remaining else @as(u64, 0);
            return .{
                .success = false,
                .is_revert = (sub_interp.result == .revert),
                .address = [_]u8{0} ** 20,
                .gas_remaining = gas_rem,
                // EVM semantics: CREATE propagates return data only on REVERT (not on OOG/error).
                .return_data = if (sub_interp.result == .revert) sub_interp.return_data.data else &[_]u8{},
                .gas_refunded = 0,
            };
        }

        // 11. Validate deployed code
        const deployed = sub_interp.return_data.data;
        if (deployed.len > MAX_CODE_SIZE) {
            // EIP-170: code too large → all remaining gas consumed (treated as error, not revert)
            js.checkpointRevert(checkpoint);
            return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20,
                       .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0 };
        }
        // EIP-3541 (London+): reject code starting with 0xEF (all gas consumed)
        if (primitives.isEnabledIn(spec_id, .london)) {
            if (deployed.len > 0 and deployed[0] == 0xEF) {
                js.checkpointRevert(checkpoint);
                return .{ .success = false, .is_revert = false, .address = [_]u8{0} ** 20,
                           .gas_remaining = 0, .return_data = &[_]u8{}, .gas_refunded = 0 };
            }
        }

        // 12. Code deposit gas: 200 per byte of deployed code
        const deposit_cost = gas_costs.G_CODEDEPOSIT * @as(u64, @intCast(deployed.len));
        if (sub_interp.gas.remaining < deposit_cost) {
            if (primitives.isEnabledIn(spec_id, .homestead)) {
                // Homestead+ (EIP-2): deposit OOG is a full failure — all gas consumed, state reverted.
                js.checkpointRevert(checkpoint);
                return CreateResult.failure();
            } else {
                // Frontier: code deposit OOG silently deploys an EMPTY contract (EIP-2 removed this).
                // The state is committed (new account with empty code), and remaining gas is returned.
                // This is the "leaving an empty contract" behavior that EIP-2 eliminated.
                js.checkpointCommit();
                return .{ .success = true, .is_revert = false, .address = new_addr,
                           .gas_remaining = sub_interp.gas.remaining, .return_data = &[_]u8{},
                           .gas_refunded = sub_interp.gas.refunded };
            }
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

        // EIP-211: After a successful CREATE, RETURNDATASIZE is zero.
        return .{
            .success = true,
            .is_revert = false,
            .address = new_addr,
            .gas_remaining = gas_after_deposit,
            .return_data = &[_]u8{},
            .gas_refunded = sub_interp.gas.refunded,
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
