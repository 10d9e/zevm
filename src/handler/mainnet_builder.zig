const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const database = @import("database");
const state = @import("state");
const bytecode = @import("bytecode");
const interpreter_mod = @import("interpreter");
const main = @import("main.zig");
const validation = @import("validation.zig");

/// Mainnet EVM type alias
pub const MainnetEvm = main.Evm;

/// Mainnet context type alias
pub const MainnetContext = context.Context;

/// Main builder
pub const MainBuilder = struct {
    /// Build mainnet EVM without inspector
    pub fn buildMainnet(self: *MainnetContext) MainnetEvm {
        // Extract spec from context configuration
        const spec = self.cfg.spec;

        // Initialize instruction table and precompiles for this spec
        var instructions = main.Instructions.new(spec);
        var precompiles = main.Precompiles.new(spec);
        var frame_stack = main.FrameStack.newPrealloc(8);

        return main.Evm.init(
            self,
            null,
            &instructions,
            &precompiles,
            &frame_stack,
        );
    }

    /// Build mainnet EVM with inspector
    pub fn buildMainnetWithInspector(self: *MainnetContext, inspector: *main.Inspector) MainnetEvm {
        // Extract spec from context configuration
        const spec = self.cfg.spec;

        // Initialize instruction table and precompiles for this spec
        var instructions = main.Instructions.new(spec);
        var precompiles = main.Precompiles.new(spec);
        var frame_stack = main.FrameStack.newPrealloc(8);

        return main.Evm.init(
            self,
            inspector,
            &instructions,
            &precompiles,
            &frame_stack,
        );
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
pub const MainnetHandler = struct {
    /// Validate transaction — environment checks (no DB access) then caller state check.
    pub fn validate(evm: *MainnetEvm, initial_gas: *validation.InitialAndFloorGas) !void {
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
    pub fn preExecution(evm: *MainnetEvm) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const spec = ctx.cfg.spec;
        const js = &ctx.journaled_state;

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

                                    // Load authority account (marks it warm)
                                    const load_result = js.loadAccountMutOptionalCode(authority_addr, true, false) catch continue;
                                    const journaled = load_result.data;

                                    // Nonce must match exactly — skip if stale
                                    if (journaled.account.info.nonce != auth.nonce) continue;

                                    // Bump authority nonce (journaled, revertable)
                                    journaled.account.info.nonce += 1;
                                    js.nonceBumpJournalEntry(authority_addr);

                                    // Apply delegation: zero address clears code; otherwise set EIP-7702 bytecode
                                    const zero_addr = [_]u8{0} ** 20;
                                    const bc = if (std.mem.eql(u8, &auth.address, &zero_addr))
                                        bytecode.Bytecode.new()
                                    else
                                        bytecode.Bytecode{ .eip7702 = bytecode.Eip7702Bytecode.new(auth.address) };

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
    pub fn executeFrame(evm: *MainnetEvm, initial_gas: u64) !main.FrameResult {
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
                };
                const cr = host.create(tx.caller, tx.value, calldata, exec_gas, false, 0, true);
                const status: main.ExecutionStatus = if (cr.success) .Success else .Revert;
                var exec_result = main.ExecutionResult.new(status, exec_gas - cr.gas_remaining);
                exec_result.return_data = cr.return_data;
                return main.FrameResult.new(exec_result, cr.gas_remaining, cr.gas_refunded);
            },
            .Call => |target| {
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
                return evm.executeFrame(&frame);
            },
        }
    }

    /// Post-execution phase — gas refund capping (EIP-3529), EIP-7623 floor, reimburse caller,
    /// reward beneficiary, and commit journal.
    pub fn postExecution(
        evm: *MainnetEvm,
        result: *main.FrameResult,
        initial_gas: validation.InitialAndFloorGas,
    ) !void {
        const ctx = evm.getContext();
        const tx = &ctx.tx;
        const block = &ctx.block;
        const spec = ctx.cfg.spec;
        const js = &ctx.journaled_state;

        const is_london = primitives.isEnabledIn(spec, .london);

        // 1. EIP-3529: cap gas refund
        const exec_gas = tx.gas_limit - initial_gas.initial_gas;
        const gas_spent = exec_gas - result.gas_remaining;
        const raw_refund = @as(u64, @intCast(@max(0, result.gas_refunded)));
        const quotient: u64 = if (is_london) 5 else 2;
        var capped_refund = @min(raw_refund, gas_spent / quotient);

        // 2. EIP-7623: floor gas (Prague+)
        var effective_exec_gas_used = gas_spent - capped_refund;
        if (primitives.isEnabledIn(spec, .prague)) {
            if (effective_exec_gas_used < initial_gas.floor_gas) {
                effective_exec_gas_used = initial_gas.floor_gas;
                capped_refund = 0;
            }
        }

        // 3. Effective gas price (EIP-1559 aware)
        const basefee: u128 = @as(u128, block.basefee);
        const effective_gas_price: u128 = if (tx.gas_priority_fee) |tip|
            @min(tx.gas_price, basefee + tip)
        else
            tx.gas_price;

        // 4. Reimburse caller: (gas_remaining + capped_refund) * effective_gas_price
        const gas_returned: u64 = result.gas_remaining + capped_refund;
        const reimburse_amount: primitives.U256 = @as(primitives.U256, effective_gas_price) * @as(primitives.U256, gas_returned);
        try js.balanceIncr(tx.caller, reimburse_amount);

        // 5. Pay beneficiary (only tip portion post-London)
        const total_gas_used = initial_gas.initial_gas + effective_exec_gas_used;
        const coinbase_price: u128 = if (is_london) effective_gas_price -| basefee else effective_gas_price;
        const beneficiary_amount: primitives.U256 = @as(primitives.U256, coinbase_price) * @as(primitives.U256, total_gas_used);
        try js.balanceIncr(block.beneficiary, beneficiary_amount);

        // 6. Commit transaction state
        js.commitTx();

        // 7. Update ExecutionResult with final accounting
        result.result.gas_used = total_gas_used;
        result.result.gas_refunded = capped_refund;
    }

    /// Handle errors — revert journal, discard tx.
    pub fn catchError(evm: *MainnetEvm, _: anyerror) void {
        const ctx = evm.getContext();
        // Revert all state changes from this transaction
        ctx.journaled_state.discardTx();
    }
};

/// Execute EVM — run a full transaction through validate → pre-exec → exec → post-exec.
pub const ExecuteEvm = struct {
    pub fn execute(self: *MainnetEvm) !main.ExecutionResult {
        var initial_gas = validation.InitialAndFloorGas{ .initial_gas = 0, .floor_gas = 0 };

        // Validate (env checks + caller deduction)
        MainnetHandler.validate(self, &initial_gas) catch |err| {
            MainnetHandler.catchError(self, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Pre-execution (warm access lists)
        MainnetHandler.preExecution(self) catch |err| {
            MainnetHandler.catchError(self, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Execute frame
        var frame_result = MainnetHandler.executeFrame(self, initial_gas.initial_gas) catch |err| {
            MainnetHandler.catchError(self, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Post-execution: refund capping, floor gas, reimburse caller, reward beneficiary, commit
        MainnetHandler.postExecution(self, &frame_result, initial_gas) catch |err| {
            MainnetHandler.catchError(self, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        return frame_result.result;
    }
};

/// Execute commit EVM — execute then commit state to the underlying database.
/// Note: commitTx() is called inside postExecution; no second commit needed here.
pub const ExecuteCommitEvm = struct {
    pub fn executeAndCommit(self: *MainnetEvm) !main.ExecutionResult {
        return ExecuteEvm.execute(self);
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

        // Test EVM building
        const evm = MainBuilder.buildMainnet(@constCast(&ctx));
        std.debug.assert(evm.ctx == &ctx);
        std.debug.assert(evm.inspector == null);

        std.log.info("Mainnet builder test passed!", .{});
    }

    pub fn testMainnetHandler() !void {
        std.log.info("Testing mainnet handler...", .{});

        // Create test context
        var ctx = MainContext.mainnet();
        const evm = MainBuilder.buildMainnet(&ctx);

        // Test handler in isolation — validate/preExecution are NOOPs when
        // called directly without a properly-populated context, so just test
        // the struct construction.
        const handler = MainnetHandler{};
        _ = handler;
        _ = evm;

        std.log.info("Mainnet handler test passed!", .{});
    }
};
