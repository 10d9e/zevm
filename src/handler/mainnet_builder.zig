const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const database = @import("database");
const state = @import("state");
const bytecode = @import("bytecode");
const main = @import("main.zig");

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

/// Mainnet handler implementation
pub const MainnetHandler = struct {
    /// Execute transaction
    pub fn execute(self: *MainnetHandler, evm: *MainnetEvm) !main.ExecutionResult {
        _ = self;

        // Get transaction from context
        const tx = evm.getContext().tx;

        // Create frame data
        const frame_data = main.FrameData.new(
            tx.caller,
            tx.target,
            tx.value,
            tx.data,
            tx.gas_limit,
            tx.is_static,
            .call,
        );

        // Create and execute frame
        var frame = evm.createFrame(frame_data);
        const result = try evm.executeFrame(&frame);

        return result.result;
    }

    /// Validate transaction
    pub fn validate(self: *MainnetHandler, evm: *MainnetEvm) !void {
        _ = self;
        _ = evm;

        // Basic validation - in a real implementation, this would check:
        // - Transaction format
        // - Gas limits
        // - Account balances
        // - Nonce values
        // - Signature validity
    }

    /// Pre-execution phase
    pub fn preExecution(self: *MainnetHandler, evm: *MainnetEvm) !void {
        _ = self;
        _ = evm;

        // Pre-execution tasks:
        // - Load accounts
        // - Warm up addresses
        // - Deduct gas costs
        // - Apply EIP-7702 authorizations
    }

    /// Post-execution phase
    pub fn postExecution(self: *MainnetHandler, evm: *MainnetEvm, result: *main.FrameResult) !void {
        _ = self;
        _ = evm;
        _ = result;

        // Post-execution tasks:
        // - Calculate gas refunds
        // - Validate gas floor
        // - Reimburse caller
        // - Reward beneficiary
        // - Finalize state
    }

    /// Handle errors
    pub fn catchError(self: *MainnetHandler, evm: *MainnetEvm, err: anyerror) !void {
        _ = self;
        _ = evm;
        _ = err;

        // Error handling:
        // - Clean up intermediate state
        // - Revert changes
        // - Log errors
    }
};

/// Execute EVM
pub const ExecuteEvm = struct {
    /// Execute transaction
    pub fn execute(self: *MainnetEvm) !main.ExecutionResult {
        var handler = MainnetHandler{};

        // Validate
        try handler.validate(self);

        // Pre-execution
        try handler.preExecution(self);

        // Execute
        const result = try handler.execute(self);

        // Post-execution
        var frame_result = main.FrameResult.new(result, 0);
        defer frame_result.deinit();
        try handler.postExecution(self, &frame_result);

        return result;
    }
};

/// Execute commit EVM
pub const ExecuteCommitEvm = struct {
    /// Execute and commit transaction
    pub fn executeAndCommit(self: *MainnetEvm) !main.ExecutionResult {
        const result = try ExecuteEvm.execute(self);

        // Commit changes to database
        // In a real implementation, this would:
        // - Apply state changes
        // - Update account balances
        // - Store logs
        // - Update nonces

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
        var evm = MainBuilder.buildMainnet(&ctx);

        // Test handler
        var handler = MainnetHandler{};

        // Test validation
        try handler.validate(&evm);

        // Test pre-execution
        try handler.preExecution(&evm);

        // Test post-execution
        var frame_result = main.FrameResult.new(main.ExecutionResult.new(.Success, 1000), 500);
        defer frame_result.deinit();
        try handler.postExecution(&evm, &frame_result);

        std.log.info("Mainnet handler test passed!", .{});
    }
};
