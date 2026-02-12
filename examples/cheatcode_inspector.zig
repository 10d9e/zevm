const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const state = @import("state");
const database = @import("database");
const context = @import("context");
const interpreter = @import("interpreter");
const precompile = @import("precompile");
const handler = @import("handler");
const inspector = @import("inspector");

/// Example demonstrating cheatcode inspector functionality.
///
/// This example demonstrates:
/// 1. Custom inspector implementation
/// 2. Cheatcode detection and handling
/// 3. Execution monitoring and logging
/// 4. Gas usage analysis
/// 5. State change tracking
/// Cheatcode inspector that detects and logs cheatcode usage
pub const CheatcodeInspector = struct {
    base: inspector.Inspector,
    gas_inspector: inspector.GasInspector,
    cheatcode_calls: std.ArrayList(CheatcodeCall),
    allocator: std.mem.Allocator,

    const CheatcodeCall = struct {
        cheatcode_type: CheatcodeType,
        caller: primitives.Address,
        gas_used: u64,
        timestamp: u64,

        const CheatcodeType = enum {
            timestamp_manipulation,
            block_number_manipulation,
            balance_manipulation,
            storage_manipulation,
            gas_price_manipulation,
            unknown,
        };
    };

    pub fn init(allocator: std.mem.Allocator) !CheatcodeInspector {
        return CheatcodeInspector{
            .base = inspector.Inspector{},
            .gas_inspector = inspector.GasInspector.new(),
            .cheatcode_calls = try std.ArrayList(CheatcodeCall).initCapacity(allocator, 50),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CheatcodeInspector) void {
        self.cheatcode_calls.deinit(self.allocator);
    }

    pub fn detectCheatcode(self: *CheatcodeInspector, opcode: u8, caller: primitives.Address, gas_used: u64) !void {
        const cheatcode_type = self.analyzeOpcode(opcode);
        if (cheatcode_type != .unknown) {
            try self.cheatcode_calls.append(self.allocator, CheatcodeCall{
                .cheatcode_type = cheatcode_type,
                .caller = caller,
                .gas_used = gas_used,
                .timestamp = @as(u64, @intCast(std.time.timestamp())),
            });

            std.log.warn("🚨 CHEATCODE DETECTED: {} by {s} (gas: {})", .{ cheatcode_type, caller, gas_used });
        }
    }

    fn analyzeOpcode(self: *CheatcodeInspector, opcode: u8) CheatcodeCall.CheatcodeType {
        _ = self;
        return switch (opcode) {
            bytecode.TIMESTAMP => .timestamp_manipulation,
            bytecode.NUMBER => .block_number_manipulation,
            bytecode.BALANCE => .balance_manipulation,
            bytecode.SSTORE => .storage_manipulation,
            bytecode.GASPRICE => .gas_price_manipulation,
            else => .unknown,
        };
    }

    pub fn printReport(self: *CheatcodeInspector) void {
        std.log.info("=== Cheatcode Inspector Report ===", .{});
        std.log.info("Total cheatcode calls detected: {}", .{self.cheatcode_calls.items.len});

        var total_gas: u64 = 0;

        for (self.cheatcode_calls.items) |call| {
            total_gas += call.gas_used;
            std.log.info("  Type: {}, Caller: {any}, Gas Used: {}, Timestamp: {}", .{
                call.cheatcode_type,
                call.caller,
                call.gas_used,
                call.timestamp,
            });
        }

        std.log.info("Total gas used by cheatcodes: {}", .{total_gas});
    }
};

/// Mock bytecode that uses various cheatcodes
const CHEATCODE_BYTECODE = [_]u8{
    // Get current timestamp (cheatcode)
    bytecode.TIMESTAMP,

    // Store timestamp in storage
    bytecode.PUSH0,
    bytecode.SSTORE,

    // Get current block number (cheatcode)
    bytecode.NUMBER,

    // Store block number in storage
    bytecode.PUSH1,
    0x01,
    bytecode.SSTORE,

    // Get balance of an address (cheatcode)
    bytecode.PUSH20,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    bytecode.BALANCE,

    // Store balance in storage
    bytecode.PUSH1,
    0x02,
    bytecode.SSTORE,

    // Get gas price (cheatcode)
    bytecode.GASPRICE,

    // Store gas price in storage
    bytecode.PUSH1,
    0x03,
    bytecode.SSTORE,

    // Stop execution
    bytecode.STOP,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Cheatcode Inspector Example ===", .{});

    // Create database and context
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Create context (commented out since we're not using it yet)
    // var ctx = context.Context.new(db, primitives.SpecId.prague);

    // Create cheatcode inspector
    var cheatcode_inspector = try CheatcodeInspector.init(allocator);
    defer cheatcode_inspector.deinit();

    // Create contract account
    const contract_address: primitives.Address = [_]u8{0x01} ** 20;
    const account_info = state.AccountInfo.new(
        primitives.U256.ZERO, // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode{ .legacy_analyzed = bytecode.LegacyRawBytecode.init(&CHEATCODE_BYTECODE).intoAnalyzed() },
    );

    try db.insertAccount(contract_address, account_info);

    std.log.info("Contract deployed at {any}", .{contract_address});
    std.log.info("Bytecode length: {}", .{CHEATCODE_BYTECODE.len});

    // Build EVM with inspector (commented out since transaction methods don't exist yet)
    // var evm = handler.MainBuilder.buildMainnetWithInspector(&ctx, &cheatcode_inspector.base);

    // Create transaction to call the contract
    var tx = context.TxEnv.default();
    defer tx.deinit();

    tx.kind = context.TxKind{ .Call = contract_address };
    tx.gas_limit = 100000;
    tx.caller = [_]u8{0x02} ** 20;

    std.log.info("Executing contract with cheatcode detection...", .{});

    // For now, just simulate cheatcode detection without actual execution
    // In a full implementation, this would be called during EVM execution
    try simulateCheatcodeDetection(&cheatcode_inspector);

    // Print cheatcode report
    cheatcode_inspector.printReport();

    std.log.info("=== Cheatcode Inspector Example Complete ===", .{});
}

fn simulateCheatcodeDetection(cheatcode_inspector: *CheatcodeInspector) !void {
    std.log.info("--- Simulating Cheatcode Detection ---", .{});

    const malicious_caller: primitives.Address = [_]u8{0x99} ** 20;

    // Simulate various cheatcode calls
    try cheatcode_inspector.detectCheatcode(bytecode.TIMESTAMP, malicious_caller, 100);
    try cheatcode_inspector.detectCheatcode(bytecode.NUMBER, malicious_caller, 150);
    try cheatcode_inspector.detectCheatcode(bytecode.BALANCE, malicious_caller, 200);
    try cheatcode_inspector.detectCheatcode(bytecode.SSTORE, malicious_caller, 5000);
    try cheatcode_inspector.detectCheatcode(bytecode.GASPRICE, malicious_caller, 50);

    // Simulate more calls from different addresses
    const another_caller: primitives.Address = [_]u8{0x88} ** 20;
    try cheatcode_inspector.detectCheatcode(bytecode.TIMESTAMP, another_caller, 120);
    try cheatcode_inspector.detectCheatcode(bytecode.NUMBER, another_caller, 180);

    std.log.info("Cheatcode detection simulation complete", .{});
}

/// Demonstrate inspector integration
pub fn demonstrateInspectorIntegration() !void {
    std.log.info("--- Inspector Integration Demo ---", .{});

    // Create gas inspector
    var gas_inspector = inspector.GasInspector.new();

    // Create count inspector
    var count_inspector = inspector.CountInspector.new();

    // Create no-op inspector
    const noop_inspector = inspector.NoOpInspector.new();
    _ = noop_inspector; // Prevent unused variable warning

    std.log.info("Created multiple inspector types:", .{});
    std.log.info("  Gas Inspector: {}", .{gas_inspector.gasRemaining()});
    std.log.info("  Count Inspector - Steps: {}, Calls: {}", .{ count_inspector.getStepCount(), count_inspector.getCallCount() });
    std.log.info("  No-Op Inspector: Ready", .{});

    std.log.info("Inspector integration demo complete", .{});
}
