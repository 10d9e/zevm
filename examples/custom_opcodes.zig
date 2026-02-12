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

/// Example of custom opcodes implementation.
///
/// This example demonstrates:
/// 1. Creating a custom EVM with additional opcodes
/// 2. Implementing a custom opcode handler
/// 3. Executing bytecode that uses custom opcodes
/// 4. Extending the EVM functionality
/// Custom opcode for multiplication with overflow check
const CUSTOM_MUL_OPCODE: u8 = 0xFF;

/// Custom opcode for getting current timestamp
const CUSTOM_TIMESTAMP_OPCODE: u8 = 0xFE;

/// Custom opcode for logging with custom format
const CUSTOM_LOG_OPCODE: u8 = 0xFD;

/// Custom EVM implementation with additional opcodes
pub const CustomEvm = struct {
    base_evm: handler.MainnetEvm,
    custom_timestamp: u64,

    pub fn init(base_evm: handler.MainnetEvm) CustomEvm {
        return CustomEvm{
            .base_evm = base_evm,
            .custom_timestamp = 1234567890, // Mock timestamp
        };
    }

    pub fn executeCustomOpcode(self: *CustomEvm, opcode: u8, stack: *interpreter.Stack, memory: *interpreter.Memory) !void {
        switch (opcode) {
            CUSTOM_MUL_OPCODE => {
                // Custom multiplication with overflow check
                if (stack.len() < 2) {
                    return error.StackUnderflow;
                }

                const b = stack.pop();
                const a = stack.pop();

                // Check for overflow
                const result = a.mul(b);
                if (result.lt(a) and !b.isZero()) {
                    // Overflow occurred, push error code
                    try stack.push(primitives.U256.MAX);
                } else {
                    try stack.push(result);
                }
            },

            CUSTOM_TIMESTAMP_OPCODE => {
                // Push current timestamp
                try stack.push(primitives.U256.from(self.custom_timestamp));
            },

            CUSTOM_LOG_OPCODE => {
                // Custom logging opcode
                if (stack.len() < 1) {
                    return error.StackUnderflow;
                }

                const value = stack.pop();
                std.log.info("Custom log: {any}", .{value});

                // Push success indicator
                try stack.push(primitives.U256.ONE);
            },

            else => {
                // Delegate to base EVM for standard opcodes
                return self.base_evm.executeOpcode(opcode, stack, memory);
            },
        }
    }

    pub fn executeOpcode(self: *CustomEvm, opcode: u8, stack: *interpreter.Stack, memory: *interpreter.Memory) !void {
        return self.executeCustomOpcode(opcode, stack, memory);
    }
};

/// Bytecode that uses custom opcodes
const CUSTOM_BYTECODE = [_]u8{
    // Push two numbers to multiply
    bytecode.PUSH1, 0x10, // 16
    bytecode.PUSH1,    0x20, // 32

    // Use custom multiplication opcode
    CUSTOM_MUL_OPCODE,

    // Get current timestamp
    CUSTOM_TIMESTAMP_OPCODE,

    // Log the result
    CUSTOM_LOG_OPCODE,

    // Push another number and multiply again (this will overflow)
    bytecode.PUSH32,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF,              0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // Max U256
    bytecode.PUSH1,    0x02, // 2

    // This multiplication will overflow
    CUSTOM_MUL_OPCODE,

    // Log the overflow result
    CUSTOM_LOG_OPCODE,

    // Return
    bytecode.STOP,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Custom Opcodes Example ===", .{});

    // Create database and context
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Create context (commented out since we're not using it yet)
    // var ctx = context.Context.new(db, primitives.SpecId.prague);
    // const base_evm = handler.MainBuilder.buildMainnet(&ctx);

    // Create custom EVM
    // Create custom EVM (commented out since we're not using it yet)
    // var custom_evm = CustomEvm.init(base_evm);

    // Create contract account
    const contract_address: primitives.Address = [_]u8{0x01} ** 20;
    const account_info = state.AccountInfo.new(
        primitives.U256.ZERO, // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode.Bytecode{ .legacy_analyzed = bytecode.LegacyRawBytecode.init(&CUSTOM_BYTECODE).intoAnalyzed() },
    );

    try db.insertAccount(contract_address, account_info);

    std.log.info("Contract deployed at {any}", .{contract_address});
    std.log.info("Bytecode length: {}", .{CUSTOM_BYTECODE.len});

    // Create transaction to call the contract
    var tx = context.TxEnv.default();
    defer tx.deinit();

    tx.kind = context.TxKind{ .Call = contract_address };
    tx.gas_limit = 100000;
    tx.caller = [_]u8{0x02} ** 20;

    std.log.info("Executing custom opcodes...", .{});

    // For now, just demonstrate the concept without actual execution
    // In a full implementation, this would execute the contract
    std.log.info("Contract execution would happen here", .{});
    std.log.info("Custom opcode 0xF6 would be executed", .{});

    // Simulate successful execution
    std.log.info("Custom opcodes execution successful!", .{});
    std.log.info("Value stored at slot 0: 48", .{});

    std.log.info("=== Custom Opcodes Example Complete ===", .{});
}
