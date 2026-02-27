const std = @import("std");
const zevm = @import("zevm");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("ZEVM - Zig Ethereum Virtual Machine", .{});
    std.log.info("=====================================", .{});

    // Create an in-memory database
    var db = zevm.database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Create a test account
    const test_address: zevm.primitives.Address = [_]u8{0x01} ** 20;
    const account_info = zevm.state.AccountInfo.fromBalance(@as(zevm.primitives.U256, 1000));

    // Insert account into database
    try db.insertAccount(test_address, account_info);
    std.log.info("Created account with balance: {any}", .{account_info.balance});

    // Retrieve account from database
    const retrieved_account = try db.basic(test_address);
    if (retrieved_account) |account| {
        std.log.info("Retrieved account balance: {any}", .{account.balance});
    }

    // Create some bytecode
    const code = zevm.bytecode.Bytecode.new();
    const code_hash = code.hashSlow();
    try db.insertCode(code_hash, code);
    std.log.info("Inserted bytecode with hash: {any}", .{code_hash});

    // Test opcode operations
    const stop_opcode = zevm.bytecode.OpCode.new(0x00) orelse return;
    std.log.info("STOP opcode: {any}", .{stop_opcode});
    std.log.info("STOP inputs: {}, outputs: {}", .{ stop_opcode.inputs(), stop_opcode.outputs() });

    const add_opcode = zevm.bytecode.OpCode.new(0x01) orelse return;
    std.log.info("ADD opcode: {any}", .{add_opcode});
    std.log.info("ADD inputs: {}, outputs: {}", .{ add_opcode.inputs(), add_opcode.outputs() });

    // Test hardfork parsing
    const prague_spec = zevm.primitives.specIdFromString("Prague") catch return;
    std.log.info("Current hardfork: {any}", .{prague_spec});

    // Test account state management
    var account = zevm.state.Account.default();
    account.markTouch();
    account.markCreated();
    std.log.info("Account touched: {}, created: {}", .{ account.isTouched(), account.isCreated() });

    std.log.info("ZEVM demonstration completed successfully!", .{});
}
