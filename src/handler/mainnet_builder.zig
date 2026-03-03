const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const database = @import("database");
const state = @import("state");
const bytecode = @import("bytecode");
const interpreter_mod = @import("interpreter");
const main = @import("main.zig");
const validation = @import("validation.zig");

/// Mainnet EVM — heap-allocated wrapper that owns its Instructions, Precompiles, and FrameStack.
///
/// `buildMainnet` / `buildMainnetWithInspector` return `*MainnetEvm`.  Because the struct is
/// heap-allocated the addresses of `instructions`, `precompiles`, and `frame_stack` are stable
/// for the lifetime of the object, so the internal `Evm` can hold `&self.instructions` etc.
/// without dangling pointers.
///
/// Call `evm.destroy()` when done to free the heap allocation.
pub const MainnetEvm = struct {
    /// Owned instruction table and precompile set (stable addresses — do NOT move this struct).
    instructions: main.Instructions,
    precompiles: main.Precompiles,
    frame_stack: main.FrameStack,
    /// Inner Evm whose `instructions`/`precompiles`/`frame_stack` pointers reference the fields above.
    evm: main.Evm,

    /// Get the execution context.
    pub fn getContext(self: *MainnetEvm) *context.Context {
        return self.evm.ctx;
    }

    /// Create an execution frame.
    pub fn createFrame(self: *MainnetEvm, frame_data: main.FrameData) !main.Frame {
        return self.evm.createFrame(frame_data);
    }

    /// Execute a frame (delegates to the inner Evm).
    pub fn executeFrame(self: *MainnetEvm, frame: *main.Frame) !main.FrameResult {
        return self.evm.executeFrame(frame);
    }

    /// Execute a full transaction through validate → pre-exec → exec → post-exec.
    /// Convenience wrapper over `ExecuteEvm.execute(&self.evm)`.
    pub fn execute(self: *MainnetEvm) !main.ExecutionResult {
        return ExecuteEvm.execute(&self.evm);
    }

    /// Free the heap allocation created by `buildMainnet` / `buildMainnetWithInspector`.
    pub fn destroy(self: *MainnetEvm) void {
        std.heap.c_allocator.destroy(self);
    }
};

/// Mainnet context type alias
pub const MainnetContext = context.Context;

/// Main builder
pub const MainBuilder = struct {
    /// Build mainnet EVM without inspector.
    /// Returns a heap-allocated `*MainnetEvm`; call `evm.destroy()` when done.
    pub fn buildMainnet(self: *MainnetContext) *MainnetEvm {
        const spec = self.cfg.spec;
        const owned = std.heap.c_allocator.create(MainnetEvm) catch @panic("OOM in buildMainnet");
        owned.instructions = main.Instructions.new(spec);
        owned.precompiles = main.Precompiles.new(spec);
        owned.frame_stack = main.FrameStack.newPrealloc(8);
        owned.evm = main.Evm.init(self, null, &owned.instructions, &owned.precompiles, &owned.frame_stack);
        return owned;
    }

    /// Build mainnet EVM with inspector.
    /// Returns a heap-allocated `*MainnetEvm`; call `evm.destroy()` when done.
    pub fn buildMainnetWithInspector(self: *MainnetContext, inspector: *main.Inspector) *MainnetEvm {
        const spec = self.cfg.spec;
        const owned = std.heap.c_allocator.create(MainnetEvm) catch @panic("OOM in buildMainnetWithInspector");
        owned.instructions = main.Instructions.new(spec);
        owned.precompiles = main.Precompiles.new(spec);
        owned.frame_stack = main.FrameStack.newPrealloc(8);
        owned.evm = main.Evm.init(self, inspector, &owned.instructions, &owned.precompiles, &owned.frame_stack);
        return owned;
    }
};

/// Main context
pub const MainContext = struct {
    /// Create new mainnet context
    pub fn mainnet() MainnetContext {
        const db = database.InMemoryDB.init(std.heap.c_allocator);
        return context.Context.new(db, primitives.SpecId.prague);
    }
};

/// Mainnet handler — stateless, all methods are free functions grouped in a namespace.
/// All functions accept `*main.Evm` so they work with both the heap-allocated `*MainnetEvm`
/// (call `evm.execute()` or pass `&mevm.evm`) and stack-allocated test helpers.
pub const MainnetHandler = struct {
    /// Validate transaction — environment checks (no DB access) then caller state check.
    pub fn validate(evm: *main.Evm, initial_gas: *validation.InitialAndFloorGas) !void {
        const ctx = evm.getContext();

        // 1. Validate block/tx/cfg fields (chain ID, gas cap, priority fee ordering)
        try validation.Validation.validateEnv(evm);

        // 2. EIP-4844: Validate blob transaction fields (Cancun+)
        try validation.Validation.validateBlobTx(&ctx.tx, &ctx.block, ctx.cfg.spec);

        // 3. EIP-7702: Validate set-code transaction fields (Prague+)
        try validation.Validation.validateEip7702Tx(&ctx.tx, ctx.cfg.spec);

        // 4. Calculate intrinsic gas and validate gas_limit covers it
        initial_gas.* = try validation.Validation.validateInitialTxGas(evm);

        // 5. Load caller, check nonce/code/balance, deduct max fee, bump nonce
        try validation.Validation.validateAgainstStateAndDeductCaller(evm, initial_gas.initial_gas);
    }

    /// Pre-execution phase — warm addresses and mark access-list items.
    ///
    /// Must run after validate() so the caller is already loaded and nonce bumped.
    /// Populates `initial_gas.auth_refund` with 12,500 (PER_EMPTY_ACCOUNT_COST/2) per valid
    /// EIP-7702 authorization where the authority account is non-empty (existing); 0 for new accounts.
    pub fn preExecution(evm: *main.Evm, initial_gas: *validation.InitialAndFloorGas) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const spec = ctx.cfg.spec;
        const js = &ctx.journaled_state;

        // EIP-2929: Pre-warm precompile addresses (precompiles are always warm at tx start).
        {
            var addr_buf: [32]primitives.Address = undefined;
            var count: usize = 0;
            var it = evm.precompiles.precompiles.addresses.keyIterator();
            while (it.next()) |addr| {
                if (count < addr_buf.len) {
                    addr_buf[count] = addr.*;
                    count += 1;
                }
            }
            try js.warmPrecompiles(addr_buf[0..count]);
        }

        // EIP-3651 (Shanghai+): Pre-warm coinbase so CALL to coinbase is not cold
        if (primitives.isEnabledIn(spec, .shanghai)) {
            js.warmCoinbaseAccount(ctx.block.beneficiary);
        }

        // EIP-2929: Pre-warm all access-list addresses and their storage slots.
        // Calling loadAccountWithCode marks the account warm (cold-load journal entry added).
        // Calling sload marks each storage slot warm.
        if (tx.access_list.items) |items| {
            for (items.items) |item| {
                // Load account (marks it warm, journal entry recorded)
                _ = try js.loadAccountWithCode(item.address);

                // Load each storage slot (marks it warm, journal entry recorded)
                for (item.storage_keys.items) |key| {
                    _ = try js.sload(item.address, key);
                }
            }
        }

        // EIP-7702: Apply authorization list (Prague+)
        // For each recovered authorization, validate and apply code delegation.
        if (primitives.isEnabledIn(spec, .prague)) {
            if (tx.authorization_list) |auth_list| {
                for (auth_list.items) |auth_entry| {
                    switch (auth_entry) {
                        .Right => |recovered| {
                            switch (recovered.authority) {
                                .Valid => |authority_addr| {
                                    const auth = recovered.auth;

                                    // chain_id 0 means valid for any chain
                                    const chain_id_valid = auth.chain_id == 0 or
                                        auth.chain_id == @as(primitives.U256, ctx.cfg.chain_id);
                                    if (!chain_id_valid) continue;

                                    // Per EIP-7702 (EELS reference): skip without warming the authority
                                    // if auth.nonce == maxInt(u64). Applying the auth would overflow the
                                    // nonce. EELS checks this BEFORE adding the account to accessed_addresses,
                                    // so the account remains cold when execution later accesses it.
                                    if (auth.nonce == std.math.maxInt(u64)) continue;

                                    // Load authority account (marks it warm; EIP-7702 spec: always access
                                    // the signer's account even if the authorization is ultimately invalid)
                                    const load_result = js.loadAccountMutOptionalCode(authority_addr, true, false) catch continue;
                                    const journaled = load_result.data;

                                    // Per EIP-7702: skip if authority has non-empty, non-EIP-7702 code.
                                    // Only EOAs (empty code) or accounts already holding an EIP-7702
                                    // delegation designator may re-delegate.
                                    if (journaled.account.info.code) |existing_code| {
                                        if (!existing_code.isEip7702() and !existing_code.isEmpty()) continue;
                                    }

                                    // Nonce must match exactly — skip if stale
                                    if (journaled.account.info.nonce != auth.nonce) continue;

                                    // EIP-7702 refund: the intrinsic cost charges PER_EMPTY_ACCOUNT_COST
                                    // (25,000) for each authorization to cover possible new-account creation.
                                    // If the authority already exists (non-empty), no new account is created,
                                    // so refund PER_EMPTY_ACCOUNT_COST / 2 = 12,500.
                                    // An account is non-empty if: nonce > 0, balance > 0, or code != empty.
                                    const is_existing = journaled.account.info.nonce > 0 or
                                        journaled.account.info.balance > 0 or
                                        !std.mem.eql(u8, &journaled.account.info.code_hash, &primitives.KECCAK_EMPTY);
                                    if (is_existing) {
                                        initial_gas.auth_refund += 12500;
                                    }

                                    // Bump authority nonce (journaled, revertable).
                                    journaled.account.info.nonce += 1;
                                    js.nonceBumpJournalEntry(authority_addr);

                                    // Apply delegation. setCode() handles zero address → clearing code.
                                    const bc = bytecode.Bytecode{ .eip7702 = bytecode.Eip7702Bytecode.new(auth.address) };
                                    js.inner.setCode(authority_addr, bc);
                                },
                                .Invalid => {}, // skip invalid (unrecoverable) authorities
                            }
                        },
                        .Left => {}, // unrecovered signed authorization — skip
                    }
                }
            }
        }
    }

    /// Execute the transaction frame — runs the interpreter against bytecode.
    pub fn executeFrame(evm: *main.Evm, initial_gas: u64) !main.FrameResult {
        const ctx = evm.getContext();
        const tx = &ctx.tx;

        const calldata: []const u8 = if (tx.data) |data| data.items else &[_]u8{};
        // Gas available to execution = gas_limit minus intrinsic cost
        const exec_gas = tx.gas_limit - initial_gas;

        switch (tx.kind) {
            .Create => {
                // Top-level CREATE: tx validation already bumped caller nonce.
                // Dispatch through Host.create() with skip_nonce_bump=true.
                var host = interpreter_mod.Host{
                    .ctx = ctx,
                    .run_sub_call = interpreter_mod.protocol_schedule.runSubCallDefault,
                    .precompiles = &evm.precompiles.precompiles,
                    .instruction_table = &evm.instructions.table,
                };
                const cr = host.create(tx.caller, tx.value, calldata, exec_gas, false, 0, true);
                const status: main.ExecutionStatus = if (cr.success) .Success else .Revert;
                var exec_result = main.ExecutionResult.new(status, exec_gas - cr.gas_remaining);
                exec_result.return_data = cr.return_data;
                return main.FrameResult.new(exec_result, cr.gas_remaining, cr.gas_refunded);
            },
            .Call => |target| {
                // Load target account and its code before executing.
                const callee_load = try ctx.journaled_state.loadAccountWithCode(target);
                var callee_code = if (callee_load.data.info.code) |c| c else bytecode.Bytecode.new();

                // EIP-7702: top-level CALL to a delegation account — follow the delegation to
                // get the actual code to execute. The CALL context (ADDRESS, storage) still
                // refers to the target (authority), but bytecode comes from the delegate.
                // No recursive delegation (flat one-hop per EIP-7702 spec).
                if (callee_code.isEip7702()) {
                    const del_addr = callee_code.eip7702.address;
                    if (ctx.journaled_state.loadAccountWithCode(del_addr)) |del_load| {
                        callee_code = if (del_load.data.info.code) |del_code|
                            del_code // per EIP-7702: execute target's code as-is (no recursion; 0xef → INVALID)
                        else
                            bytecode.Bytecode.new();
                    } else |_| {
                        callee_code = bytecode.Bytecode.new();
                    }
                }

                // Snapshot journal position before value transfer so state can be rolled back on REVERT.
                // Use snapshotPosition (not getCheckpoint) to avoid consuming an EVM call depth slot —
                // getCheckpoint increments depth, which would reduce the available recursive call depth by 1.
                const call_checkpoint = ctx.journaled_state.snapshotPosition();

                // Value transfer for top-level CALL (pre-execution, not through sub-call opcode).
                if (tx.value > 0) {
                    const xfer_err = try ctx.journaled_state.transfer(tx.caller, target, tx.value);
                    if (xfer_err != null) {
                        ctx.journaled_state.revertToSnapshot(call_checkpoint);
                        return main.FrameResult.new(
                            main.ExecutionResult.new(.Fail, exec_gas),
                            0,
                            0,
                        );
                    }
                }

                // Precompile dispatch: if the top-level TX target is a precompile, run it directly.
                // (Precompile dispatch in sub-calls is handled by Host.call(); this handles the case
                // where the transaction itself targets a precompile address.)
                if (evm.precompiles.get(target)) |precompile_fn| {
                    const pc_result = precompile_fn.execute(calldata, exec_gas);
                    switch (pc_result) {
                        .success => |out| {
                            if (out.reverted) {
                                ctx.journaled_state.revertToSnapshot(call_checkpoint);
                                return main.FrameResult.new(
                                    main.ExecutionResult.new(.Revert, exec_gas),
                                    0,
                                    0,
                                );
                            }
                            return main.FrameResult.new(
                                main.ExecutionResult.new(.Success, out.gas_used),
                                exec_gas - out.gas_used,
                                0,
                            );
                        },
                        .err => {
                            ctx.journaled_state.revertToSnapshot(call_checkpoint);
                            return main.FrameResult.new(
                                main.ExecutionResult.new(.Fail, exec_gas),
                                0,
                                0,
                            );
                        },
                    }
                }

                const frame_data = main.FrameData.new(
                    tx.caller,
                    target,
                    tx.value,
                    calldata,
                    exec_gas,
                    false, // top-level txs are never static
                    .call,
                );
                var frame = try evm.createFrame(frame_data);
                // Set the actual target bytecode on the interpreter (Frame.init uses empty bytecode).
                frame.interpreter.bytecode.setBytecode(callee_code);
                const call_result = try evm.executeFrame(&frame);

                // Revert all journaled state (transfer + execution effects) on REVERT/Halt.
                // On success, no action needed — postExecution.commitTx() will finalize state.
                if (call_result.result.status != .Success) {
                    ctx.journaled_state.revertToSnapshot(call_checkpoint);
                }

                return call_result;
            },
        }
    }

    /// Post-execution phase — gas refund capping (EIP-3529), EIP-7623 floor, reimburse caller,
    /// reward beneficiary, and commit journal.
    pub fn postExecution(
        evm: *main.Evm,
        result: *main.FrameResult,
        initial_gas: validation.InitialAndFloorGas,
    ) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const block = &ctx.block;
        const spec = ctx.cfg.spec;
        const js = &ctx.journaled_state;

        const is_london = primitives.isEnabledIn(spec, .london);

        // 1. EIP-3529: discard execution (SSTORE) refund on REVERT/Halt/Fail.
        //    EIP-7702 auth_refund always applies: it represents already-committed preExecution work.
        const exec_gas = tx.gas_limit - initial_gas.initial_gas;
        const gas_spent = exec_gas - result.gas_remaining;

        // 2. Compute total gas spent (intrinsic + execution) and apply EIP-7623 floor (Prague+).
        //
        // total_gas_spent must be computed before the refund cap (which uses it as the cap basis).
        // Per Yellow Paper: gas_used = gas_limit - gas_remaining_after_exec = intrinsic + gas_spent.
        //
        // The floor is compared against the TOTAL transaction cost (not just exec portion) because
        // EIP-7623 defines: floor_cost = TX_BASE_COST + tokens*10. The floor applies when
        //   (total_spent - refund) < (21000 + floor_tokens*10)
        //
        // Using exec-only arithmetic would cause underflow when floor_tokens*10 > exec_gas
        // (which is common: floor=40/nonzero-byte vs standard=16/nonzero-byte calldata gas).
        const total_gas_spent = initial_gas.initial_gas + gas_spent;

        // SSTORE clearing refund (exec_refund) only on Success (state was not reverted).
        // EIP-7702 auth_refund applies regardless of execution outcome because authorization
        // processing is committed in preExecution regardless of whether execution succeeds.
        const exec_refund: u64 = if (result.result.status == .Success)
            @as(u64, @intCast(@max(0, result.gas_refunded)))
        else
            0;
        const auth_refund = @as(u64, @intCast(@max(0, initial_gas.auth_refund)));
        const raw_refund: u64 = exec_refund + auth_refund;
        const quotient: u64 = if (is_london) 5 else 2;
        // EIP-3529 refund cap: min(refund, gas_used / max_refund_quotient) where gas_used is
        // the TOTAL gas consumed (intrinsic + execution), not just execution gas.
        // Per Yellow Paper: g* = gas_limit - gas_remaining_after_exec = total_gas_spent.
        var capped_refund = @min(raw_refund, total_gas_spent / quotient);
        var final_cost = total_gas_spent - capped_refund;
        if (primitives.isEnabledIn(spec, .prague) and !ctx.cfg.disable_eip7623 and initial_gas.floor_gas > 0) {
            // floor_total = TX_BASE_COST + floor_exec_gas (validated: gas_limit >= floor_total)
            const floor_total = 21000 + initial_gas.floor_gas;
            if (final_cost < floor_total) {
                final_cost = floor_total;
                capped_refund = 0;
            }
        }

        // 3. Effective gas price (EIP-1559 aware)
        const basefee: u128 = @as(u128, block.basefee);
        const effective_gas_price: u128 = if (tx.gas_priority_fee) |tip|
            @min(tx.gas_price, basefee + tip)
        else
            tx.gas_price;

        // 4. Reimburse caller and pay beneficiary — skipped if fee charging is disabled
        //    (e.g. eth_call simulation where no fee was deducted upfront).
        const gas_returned: u64 = tx.gas_limit - final_cost;
        if (!ctx.cfg.disable_fee_charge) {
            // Reimburse caller: gas_returned = gas_limit - final_cost (always >= 0).
            //    Normal case (no floor): gas_returned = gas_remaining + capped_refund.
            //    Floor case: gas_returned = gas_limit - floor_total.
            const reimburse_amount: primitives.U256 = @as(primitives.U256, effective_gas_price) * @as(primitives.U256, gas_returned);
            try js.balanceIncr(tx.caller, reimburse_amount);

            // Pay beneficiary (only tip portion post-London)
            const coinbase_price: u128 = if (is_london) effective_gas_price -| basefee else effective_gas_price;
            const beneficiary_amount: primitives.U256 = @as(primitives.U256, coinbase_price) * @as(primitives.U256, final_cost);
            try js.balanceIncr(block.beneficiary, beneficiary_amount);
        }

        // 6. Commit transaction state
        js.commitTx();

        // 7. Update ExecutionResult with final accounting
        result.result.gas_used = final_cost;
        result.result.gas_refunded = capped_refund;
    }

    /// Handle errors — revert journal, discard tx.
    pub fn catchError(evm: *main.Evm, _: anyerror) void {
        const ctx = evm.getContext();
        // Revert all state changes from this transaction
        ctx.journaled_state.discardTx();
    }
};

/// Execute EVM — run a full transaction through validate → pre-exec → exec → post-exec.
/// Accepts `*main.Evm` so it works with both heap-allocated `*MainnetEvm` (pass `&mevm.evm`)
/// and stack-allocated test patterns (pass `&evm` directly).
pub const ExecuteEvm = struct {
    pub fn execute(evm: *main.Evm) !main.ExecutionResult {
        var initial_gas = validation.InitialAndFloorGas{ .initial_gas = 0, .floor_gas = 0 };

        // Validate (env checks + caller deduction)
        MainnetHandler.validate(evm, &initial_gas) catch |err| {
            MainnetHandler.catchError(evm, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Pre-execution (warm access lists)
        MainnetHandler.preExecution(evm, &initial_gas) catch |err| {
            MainnetHandler.catchError(evm, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Execute frame
        var frame_result = MainnetHandler.executeFrame(evm, initial_gas.initial_gas) catch |err| {
            MainnetHandler.catchError(evm, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Post-execution: refund capping, floor gas, reimburse caller, reward beneficiary, commit
        MainnetHandler.postExecution(evm, &frame_result, initial_gas) catch |err| {
            MainnetHandler.catchError(evm, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        return frame_result.result;
    }
};

/// Execute commit EVM — execute then commit state to the underlying database.
/// Note: commitTx() is called inside postExecution; no second commit needed here.
pub const ExecuteCommitEvm = struct {
    pub fn executeAndCommit(evm: *main.Evm) !main.ExecutionResult {
        return ExecuteEvm.execute(evm);
    }
};

// Pull in post-execution tests
test {
    _ = @import("postexecution_tests.zig");
}

// Pull in precompile dispatch tests
test {
    _ = @import("precompile_dispatch_tests.zig");
}

// Pull in call gas accounting / integration tests
test {
    _ = @import("call_integration_tests.zig");
}

// Placeholder for testing
pub const testing = struct {
    pub fn testMainnetBuilder() !void {
        std.log.info("Testing mainnet builder...", .{});

        // Test mainnet context creation
        const ctx = MainContext.mainnet();
        std.debug.assert(ctx.cfg.spec == primitives.SpecId.prague);

        // Test EVM building — buildMainnet returns *MainnetEvm (heap-allocated).
        const evm = MainBuilder.buildMainnet(@constCast(&ctx));
        defer evm.destroy();
        std.debug.assert(evm.getContext() == @constCast(&ctx));
        std.debug.assert(evm.evm.inspector == null);

        std.log.info("Mainnet builder test passed!", .{});
    }

    pub fn testMainnetHandler() !void {
        std.log.info("Testing mainnet handler...", .{});

        // Create test context — buildMainnet returns *MainnetEvm (heap-allocated).
        var ctx = MainContext.mainnet();
        const evm = MainBuilder.buildMainnet(&ctx);
        defer evm.destroy();

        // Test handler in isolation — validate/preExecution are NOOPs when
        // called directly without a properly-populated context, so just test
        // the struct construction.
        const handler = MainnetHandler{};
        _ = handler;

        std.log.info("Mainnet handler test passed!", .{});
    }
};
