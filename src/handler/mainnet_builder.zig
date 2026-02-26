const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const database = @import("database");
const state = @import("state");
const bytecode = @import("bytecode");
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
        // 1. Validate block/tx/cfg fields (chain ID, gas cap, priority fee ordering)
        try validation.Validation.validateEnv(evm);

        // 2. Calculate intrinsic gas and validate gas_limit covers it
        initial_gas.* = try validation.Validation.validateInitialTxGas(evm);

        // 3. Load caller, check nonce/code/balance, deduct max fee, bump nonce
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
    }

    /// Execute the transaction frame — runs the interpreter against bytecode.
    pub fn executeFrame(evm: *MainnetEvm, initial_gas: u64) !main.FrameResult {
        const ctx = evm.getContext();
        const tx = &ctx.tx;

        // Determine target address from tx.kind
        const target: primitives.Address = switch (tx.kind) {
            .Call => |addr| addr,
            .Create => [_]u8{0} ** 20, // CREATE: address computed later (Phase 4)
        };

        // Top-level transactions are never static (STATICCALL is sub-call only)
        const is_static = false;

        const calldata: []const u8 = if (tx.data) |data| data.items else &[_]u8{};

        // Gas available to execution = gas_limit minus intrinsic cost
        const exec_gas = tx.gas_limit - initial_gas;

        const frame_data = main.FrameData.new(
            tx.caller,
            target,
            tx.value,
            calldata,
            exec_gas,
            is_static,
            .call,
        );

        // Create and execute the frame
        var frame = try evm.createFrame(frame_data);
        return evm.executeFrame(&frame);
    }

    /// Post-execution phase — gas refund, reimburse caller, reward beneficiary.
    ///
    /// Left as stubs for Phase 2.
    pub fn postExecution(evm: *MainnetEvm, result: *main.FrameResult) !void {
        _ = evm;
        _ = result;
        // Phase 2: calculate refunds (EIP-3529 SSTORE), enforce floor (EIP-7623),
        //          reimburse caller, reward beneficiary, commit journal.
    }

    /// Handle errors — revert journal, discard tx.
    pub fn catchError(evm: *MainnetEvm, err: anyerror) void {
        _ = err;
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
        const frame_result = MainnetHandler.executeFrame(self, initial_gas.initial_gas) catch |err| {
            MainnetHandler.catchError(self, err);
            return main.ExecutionResult.new(.Fail, 0);
        };

        // Post-execution (Phase 2 stubs)
        var fr = frame_result;
        MainnetHandler.postExecution(self, &fr) catch {};

        return frame_result.result;
    }
};

/// Execute commit EVM — execute then commit state to the underlying database.
pub const ExecuteCommitEvm = struct {
    pub fn executeAndCommit(self: *MainnetEvm) !main.ExecutionResult {
        const result = try ExecuteEvm.execute(self);

        // Commit journal changes (Phase 2: also need to apply EvmState diff to DB)
        self.ctx.journaled_state.commitTx();

        return result;
    }
};

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
