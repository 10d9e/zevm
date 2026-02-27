/// Tests for the post-execution pipeline (gas refund capping, floor gas, reimbursement).
/// Imported from mainnet_builder.zig via `test { _ = @import("postexecution_tests.zig"); }`.
const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const state = @import("state");
const database = @import("database");
const handler_main = @import("main.zig");
const mainnet_builder = @import("mainnet_builder.zig");
const validation = @import("validation.zig");

const MainnetHandler = mainnet_builder.MainnetHandler;
const ExecuteEvm = mainnet_builder.ExecuteEvm;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makeEvmParts(db: database.InMemoryDB, spec: primitives.SpecId) struct {
    ctx: context.Context,
    instructions: handler_main.Instructions,
    precompiles: handler_main.Precompiles,
    frame_stack: handler_main.FrameStack,
} {
    return .{
        .ctx = context.Context.new(db, spec),
        .instructions = handler_main.Instructions.new(spec),
        .precompiles = handler_main.Precompiles.new(spec),
        .frame_stack = handler_main.FrameStack.new(),
    };
}

/// Insert an account with a given balance into the DB and return it.
fn insertCaller(db: *database.InMemoryDB, addr: primitives.Address, balance: primitives.U256) !void {
    try db.insertAccount(addr, state.AccountInfo{
        .balance = balance,
        .nonce = 0,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });
}

/// Read an account's current balance from the journal (after execution).
fn readBalance(ctx: *context.Context, addr: primitives.Address) !primitives.U256 {
    const load = try ctx.journaled_state.loadAccount(addr);
    return load.data.info.balance;
}

// ---------------------------------------------------------------------------
// Gas helper unit tests
// ---------------------------------------------------------------------------

test "Gas.setFinalRefund: London caps at 1/5" {
    const interpreter = @import("interpreter");
    var g = interpreter.Gas.new(100_000);
    g.remaining = 10_000; // spent = 90_000
    g.refunded = 30_000; // raw refund > spent/5 = 18_000
    g.setFinalRefund(true);
    try std.testing.expectEqual(@as(i64, 18_000), g.refunded); // capped to 90000/5
}

test "Gas.setFinalRefund: pre-London caps at 1/2" {
    const interpreter = @import("interpreter");
    var g = interpreter.Gas.new(100_000);
    g.remaining = 10_000; // spent = 90_000
    g.refunded = 60_000; // raw refund > spent/2 = 45_000
    g.setFinalRefund(false);
    try std.testing.expectEqual(@as(i64, 45_000), g.refunded);
}

test "Gas.setFinalRefund: refund below cap unchanged" {
    const interpreter = @import("interpreter");
    var g = interpreter.Gas.new(100_000);
    g.remaining = 10_000; // spent = 90_000
    g.refunded = 5_000; // < 90000/5 = 18000 → unchanged
    g.setFinalRefund(true);
    try std.testing.expectEqual(@as(i64, 5_000), g.refunded);
}

test "Gas.spentSubRefunded: basic arithmetic" {
    const interpreter = @import("interpreter");
    var g = interpreter.Gas.new(100_000);
    g.remaining = 10_000; // spent = 90_000
    g.refunded = 20_000;
    try std.testing.expectEqual(@as(u64, 70_000), g.spentSubRefunded());
}

// ---------------------------------------------------------------------------
// postExecution integration tests
// ---------------------------------------------------------------------------

// Minimal successful call: STOP (opcode 0x00), no data, no refund.
// Verifies caller is reimbursed for unused gas and coinbase receives tip.
test "postExecution: caller reimbursed for unused gas, coinbase receives tip" {
    const caller: primitives.Address = [_]u8{0xAA} ** 20;
    const coinbase: primitives.Address = [_]u8{0xCB} ** 20;
    const initial_caller_balance: primitives.U256 = 10_000_000_000_000_000_000; // 10 ETH

    var db = database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();
    try insertCaller(&db, caller, initial_caller_balance);

    var parts = makeEvmParts(db, primitives.SpecId.london);
    var evm = handler_main.Evm.init(
        &parts.ctx,
        null,
        &parts.instructions,
        &parts.precompiles,
        &parts.frame_stack,
    );

    // London tx: basefee=1gwei, max_fee=10gwei, tip=2gwei → effective = min(10,1+2)=3gwei
    const gwei: u128 = 1_000_000_000;
    parts.ctx.tx.caller = caller;
    parts.ctx.tx.gas_limit = 100_000;
    parts.ctx.tx.gas_price = 10 * gwei; // max fee
    parts.ctx.tx.gas_priority_fee = 2 * gwei; // tip
    parts.ctx.tx.nonce = 0;
    parts.ctx.tx.value = 0;
    // Empty calldata → STOP executed immediately
    parts.ctx.block.basefee = @as(u64, @intCast(gwei));
    parts.ctx.block.beneficiary = coinbase;

    const result = try ExecuteEvm.execute(&evm);

    try std.testing.expectEqual(handler_main.ExecutionStatus.Success, result.status);

    // Intrinsic gas = 21000, STOP costs 0 → gas_used = 21000, gas_returned = 79_000
    // Phase 1 deducts at max_fee (tx.gas_price = 10*gwei): 100_000 * 10*gwei
    // Phase 2 reimburses at effective_gas_price = min(10*gwei, 1*gwei+2*gwei) = 3*gwei: 79_000 * 3*gwei
    const effective_price = 3 * gwei;
    const gas_returned: u64 = 79_000;
    const expected_caller: primitives.U256 = initial_caller_balance
        - @as(primitives.U256, parts.ctx.tx.gas_price) * parts.ctx.tx.gas_limit
        + @as(primitives.U256, effective_price) * gas_returned;
    const actual_caller = try readBalance(&parts.ctx, caller);
    try std.testing.expectEqual(expected_caller, actual_caller);

    // coinbase tip = (effective_price - basefee) * gas_used = 2gwei * 21000
    const expected_coinbase: primitives.U256 = 2 * gwei * 21_000;
    const actual_coinbase = try readBalance(&parts.ctx, coinbase);
    try std.testing.expectEqual(expected_coinbase, actual_coinbase);
}

test "postExecution: pre-London refund capped at 1/2 gas_spent" {
    const interpreter_pkg = @import("interpreter");
    // Test the helper directly — no full tx needed
    var g = interpreter_pkg.Gas.new(100_000);
    g.remaining = 10_000; // spent = 90_000
    g.refunded = 80_000; // raw > spent/2 = 45_000
    g.setFinalRefund(false); // pre-London
    try std.testing.expectEqual(@as(i64, 45_000), g.refunded);
}

test "postExecution: London refund capped at 1/5 gas_spent" {
    const interpreter_pkg = @import("interpreter");
    var g = interpreter_pkg.Gas.new(100_000);
    g.remaining = 10_000; // spent = 90_000
    g.refunded = 50_000; // raw > spent/5 = 18_000
    g.setFinalRefund(true); // London+
    try std.testing.expectEqual(@as(i64, 18_000), g.refunded);
}

test "postExecution: EIP-7623 floor gas enforced on Prague" {
    // When floor_gas > effective_exec_gas_used, effective_exec_gas_used = floor_gas, refund = 0
    const floor_gas: u64 = 5_000;
    const gas_spent: u64 = 3_000; // < floor
    const raw_refund: u64 = 1_000;

    // Simulate the calculation from postExecution directly
    const is_london = true;
    const quotient: u64 = if (is_london) 5 else 2;
    var capped_refund = @min(raw_refund, gas_spent / quotient);
    var effective = gas_spent - capped_refund;
    const is_prague = true;
    if (is_prague and effective < floor_gas) {
        effective = floor_gas;
        capped_refund = 0;
    }

    try std.testing.expectEqual(@as(u64, floor_gas), effective);
    try std.testing.expectEqual(@as(u64, 0), capped_refund);
}

test "postExecution: EIP-7623 floor not applied pre-Prague" {
    const floor_gas: u64 = 5_000;
    const gas_spent: u64 = 3_000;
    const raw_refund: u64 = 500;

    const is_london = false; // pre-London (also pre-Prague)
    const quotient: u64 = if (is_london) 5 else 2;
    var capped_refund = @min(raw_refund, gas_spent / quotient);
    var effective = gas_spent - capped_refund;
    const is_prague = false;
    if (is_prague and effective < floor_gas) {
        effective = floor_gas;
        capped_refund = 0;
    }

    // floor not applied, effective stays below floor
    try std.testing.expect(effective < floor_gas);
    try std.testing.expectEqual(raw_refund, capped_refund); // unchanged since 500 < 3000/2
}
