const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const interpreter = @import("interpreter");
const main = @import("main.zig");

/// Execution utilities
pub const Execution = struct {
    /// Execute call frame
    pub fn executeCall(
        evm: *main.Evm,
        caller: primitives.Address,
        target: primitives.Address,
        value: primitives.U256,
        input: []const u8,
        gas_limit: u64,
        is_static: bool,
    ) !main.FrameResult {
        // Create frame data
        const frame_data = main.FrameData.new(
            caller,
            target,
            value,
            input,
            gas_limit,
            is_static,
            .call,
        );

        // Create frame
        var frame = try evm.createFrame(frame_data);

        // Execute frame
        return evm.executeFrame(&frame);
    }

    /// Execute create frame
    pub fn executeCreate(
        evm: *main.Evm,
        caller: primitives.Address,
        value: primitives.U256,
        init_code: []const u8,
        gas_limit: u64,
    ) !main.FrameResult {
        // Create frame data
        const frame_data = main.FrameData.new(
            caller,
            [_]u8{0} ** 20, // No target for create
            value,
            init_code,
            gas_limit,
            false,
            .create,
        );

        // Create frame
        var frame = try evm.createFrame(frame_data);

        // Execute frame
        return evm.executeFrame(&frame);
    }

    /// Execute delegate call frame
    pub fn executeDelegateCall(
        evm: *main.Evm,
        caller: primitives.Address,
        target: primitives.Address,
        input: []const u8,
        gas_limit: u64,
        is_static: bool,
    ) !main.FrameResult {
        // Create frame data
        const frame_data = main.FrameData.new(
            caller,
            target,
            @as(primitives.U256, 0), // No value for delegate call
            input,
            gas_limit,
            is_static,
            .delegate_call,
        );

        // Create frame
        var frame = try evm.createFrame(frame_data);

        // Execute frame
        return evm.executeFrame(&frame);
    }

    /// Execute static call frame
    pub fn executeStaticCall(
        evm: *main.Evm,
        caller: primitives.Address,
        target: primitives.Address,
        input: []const u8,
        gas_limit: u64,
    ) !main.FrameResult {
        return executeCall(evm, caller, target, @as(primitives.U256, 0), input, gas_limit, true);
    }

    /// Execute call code frame
    pub fn executeCallCode(
        evm: *main.Evm,
        caller: primitives.Address,
        target: primitives.Address,
        value: primitives.U256,
        input: []const u8,
        gas_limit: u64,
    ) !main.FrameResult {
        // Create frame data
        const frame_data = main.FrameData.new(
            caller,
            target,
            value,
            input,
            gas_limit,
            false,
            .call_code,
        );

        // Create frame
        var frame = try evm.createFrame(frame_data);

        // Execute frame
        return evm.executeFrame(&frame);
    }
};

/// Execution loop
pub const ExecutionLoop = struct {
    /// Run execution loop
    pub fn run(
        evm: *main.Evm,
        initial_frame_data: main.FrameData,
    ) !main.FrameResult {
        // Create initial frame
        var frame = try evm.createFrame(initial_frame_data);

        // Execute frame
        const result = try evm.executeFrame(&frame);

        // Handle nested calls if any
        // In a real implementation, this would handle:
        // - Nested calls
        // - Contract creation
        // - Precompiled contracts
        // - System calls

        return result;
    }

    /// Handle frame result
    pub fn handleFrameResult(
        evm: *main.Evm,
        result: *main.FrameResult,
    ) !void {
        _ = evm;
        _ = result;

        // Handle frame result:
        // - Process return data
        // - Handle nested calls
        // - Update gas costs
        // - Handle errors
    }
};

/// Gas calculation utilities
pub const GasCalculation = struct {
    /// Calculate initial gas cost
    pub fn calculateInitialGas(tx: *context.TxEnv) u64 {
        var gas: u64 = 0;

        // Base gas cost
        gas += 21000;

        // Data gas cost
        if (tx.data) |data| {
            gas += data.items.len * 16; // 16 gas per byte for non-zero bytes
            // In a real implementation, would also count zero bytes at 4 gas each
        }

        // Access list gas cost (EIP-2929)
        if (tx.access_list.items) |access_list| {
            gas += access_list.items.len * 2400; // 2400 gas per access list entry
        }

        return gas;
    }

    /// Calculate gas refund
    pub fn calculateRefund(_: *main.FrameResult) u64 {
        const refund: u64 = 0;

        // Storage refund (EIP-3529)
        // In a real implementation, would calculate based on storage changes

        // Suicide refund (deprecated)
        // In a real implementation, would check for account deletions

        return refund;
    }

    /// Validate gas floor (EIP-7623)
    pub fn validateGasFloor(
        _: u64,
        gas_used: u64,
        floor_gas: u64,
    ) bool {
        return gas_used >= floor_gas;
    }
};

/// State management utilities
pub const StateManagement = struct {
    /// Load accounts
    pub fn loadAccounts(evm: *main.Evm) !void {
        _ = evm;

        // Load accounts:
        // - Caller account
        // - Target account
        // - Beneficiary account
        // - Access list accounts
    }

    /// Warm accounts
    pub fn warmAccounts(evm: *main.Evm) !void {
        _ = evm;

        // Warm accounts:
        // - Add to warm address set
        // - Reduce gas costs for subsequent access
    }

    /// Deduct gas costs
    pub fn deductGasCosts(evm: *main.Evm, gas_cost: u64) !void {
        _ = evm;
        _ = gas_cost;

        // Deduct gas costs:
        // - Check sufficient balance
        // - Deduct from caller account
        // - Handle gas price
    }

    /// Reimburse caller
    pub fn reimburseCaller(evm: *main.Evm, unused_gas: u64) !void {
        _ = evm;
        _ = unused_gas;

        // Reimburse caller:
        // - Calculate unused gas
        // - Add back to caller account
        // - Handle gas price
    }

    /// Reward beneficiary
    pub fn rewardBeneficiary(evm: *main.Evm, gas_used: u64) !void {
        _ = evm;
        _ = gas_used;

        // Reward beneficiary:
        // - Calculate transaction fees
        // - Add to beneficiary account
        // - Handle base fee burning
    }
};

// Placeholder for testing
pub const testing = struct {
    pub fn testExecution() !void {
        std.log.info("Testing execution module...", .{});

        // Test gas calculation
        var tx = context.TxEnv.default();
        defer tx.deinit();

        const initial_gas = GasCalculation.calculateInitialGas(&tx);
        std.debug.assert(initial_gas >= 21000); // At least base gas

        // Test execution result
        var result = main.FrameResult.new(main.ExecutionResult.new(.Success, 1000), 500);
        defer result.deinit();

        const refund = GasCalculation.calculateRefund(&result);
        std.debug.assert(refund >= 0);

        const valid_floor = GasCalculation.validateGasFloor(10000, 5000, 1000);
        std.debug.assert(valid_floor == true);

        std.log.info("Execution module test passed!", .{});
    }
};
