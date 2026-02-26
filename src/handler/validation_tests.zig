/// Tests for handler/validation.zig
/// Imported from validation.zig via `test { _ = @import("validation_tests.zig"); }`.
const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const state = @import("state");
const database = @import("database");
const validation = @import("validation.zig");
const handler_main = @import("main.zig");

const Validation = validation.Validation;
const ValidationError = validation.ValidationError;
const InitialAndFloorGas = validation.InitialAndFloorGas;

// -------------------------------------------------------------------------
// Intrinsic gas tests
// -------------------------------------------------------------------------

test "intrinsic gas: base CALL = 21000" {
    var tx = context.TxEnv.default();
    defer tx.deinit();
    const gas = Validation.calculateInitialGas(&tx, primitives.SpecId.prague);
    try std.testing.expectEqual(@as(u64, 21000), gas);
}

test "intrinsic gas: CREATE adds 32000" {
    var tx = context.TxEnv.default();
    defer tx.deinit();
    tx.kind = context.TxKind.Create;
    const gas = Validation.calculateInitialGas(&tx, primitives.SpecId.prague);
    try std.testing.expectEqual(@as(u64, 21000 + 32000), gas);
}

test "intrinsic gas: zero byte costs 4, nonzero costs 16" {
    var tx = context.TxEnv.default();
    defer tx.deinit();
    var data = std.ArrayList(u8){};
    try data.append(std.heap.c_allocator, 0x00); // 4 gas
    try data.append(std.heap.c_allocator, 0xFF); // 16 gas
    tx.data = data;
    const gas = Validation.calculateInitialGas(&tx, primitives.SpecId.prague);
    try std.testing.expectEqual(@as(u64, 21000 + 4 + 16), gas);
}


test "floor gas: zero for pre-Prague" {
    var tx = context.TxEnv.default();
    defer tx.deinit();
    const floor = Validation.calculateFloorGas(&tx, primitives.SpecId.cancun);
    try std.testing.expectEqual(@as(u64, 0), floor);
}

test "floor gas: zero for empty calldata on Prague" {
    var tx = context.TxEnv.default();
    defer tx.deinit();
    const floor = Validation.calculateFloorGas(&tx, primitives.SpecId.prague);
    try std.testing.expectEqual(@as(u64, 0), floor);
}

// -------------------------------------------------------------------------
// Caller deduction / nonce tests
// -------------------------------------------------------------------------

fn makeEvm(db: database.InMemoryDB, spec: primitives.SpecId) struct {
    ctx: context.Context,
    instructions: handler_main.Instructions,
    precompiles: handler_main.Precompiles,
    frame_stack: handler_main.FrameStack,
} {
    const ctx = context.Context.new(db, spec);
    return .{
        .ctx = ctx,
        .instructions = handler_main.Instructions.new(spec),
        .precompiles = handler_main.Precompiles.new(spec),
        .frame_stack = handler_main.FrameStack.new(),
    };
}

test "validateAgainstStateAndDeductCaller: deducts gas_fee and bumps nonce" {
    const caller: primitives.Address = [_]u8{0xAA} ** 20;
    const initial_balance: primitives.U256 = 1_000_000_000_000_000_000; // 1 ETH

    var db = database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();
    try db.insertAccount(caller, state.AccountInfo{
        .balance = initial_balance,
        .nonce = 5,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });

    var parts = makeEvm(db, primitives.SpecId.prague);
    var evm = handler_main.Evm.init(&parts.ctx, null, &parts.instructions, &parts.precompiles, &parts.frame_stack);

    parts.ctx.tx.caller = caller;
    parts.ctx.tx.gas_limit = 21000;
    parts.ctx.tx.gas_price = 1_000_000_000; // 1 gwei
    parts.ctx.tx.value = 0;
    parts.ctx.tx.nonce = 5;

    try Validation.validateAgainstStateAndDeductCaller(&evm, 21000);

    // Verify via journal: load the account and check mutations
    const load = try parts.ctx.journaled_state.loadAccount(caller);
    const acct = load.data;
    // Nonce bumped from 5 → 6
    try std.testing.expectEqual(@as(u64, 6), acct.info.nonce);
    // Balance deducted: 1 ETH - 21000*1gwei = 1e18 - 21_000_000_000_000
    const expected = initial_balance - (21000 * 1_000_000_000);
    try std.testing.expectEqual(expected, acct.info.balance);
}

test "validateAgainstStateAndDeductCaller: insufficient balance returns error" {
    const caller: primitives.Address = [_]u8{0xBB} ** 20;

    var db = database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();
    try db.insertAccount(caller, state.AccountInfo{
        .balance = 1000, // not enough for 21000 * 1_gwei
        .nonce = 0,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });

    var parts = makeEvm(db, primitives.SpecId.prague);
    var evm = handler_main.Evm.init(&parts.ctx, null, &parts.instructions, &parts.precompiles, &parts.frame_stack);
    parts.ctx.tx.caller = caller;
    parts.ctx.tx.gas_limit = 21000;
    parts.ctx.tx.gas_price = 1_000_000_000;
    parts.ctx.tx.nonce = 0;

    const result = Validation.validateAgainstStateAndDeductCaller(&evm, 21000);
    try std.testing.expectError(ValidationError.InsufficientBalance, result);
}

test "validateAgainstStateAndDeductCaller: nonce mismatch returns error" {
    const caller: primitives.Address = [_]u8{0xCC} ** 20;

    var db = database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();
    try db.insertAccount(caller, state.AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 3, // account nonce = 3
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });

    var parts = makeEvm(db, primitives.SpecId.prague);
    var evm = handler_main.Evm.init(&parts.ctx, null, &parts.instructions, &parts.precompiles, &parts.frame_stack);
    parts.ctx.tx.caller = caller;
    parts.ctx.tx.gas_limit = 21000;
    parts.ctx.tx.gas_price = 1;
    parts.ctx.tx.nonce = 99; // wrong nonce

    const result = Validation.validateAgainstStateAndDeductCaller(&evm, 21000);
    try std.testing.expectError(ValidationError.NonceMismatch, result);
}

test "validateAgainstStateAndDeductCaller: EIP-3607 rejects account with code" {
    const caller: primitives.Address = [_]u8{0xDD} ** 20;

    var db = database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();
    // Give caller a non-empty code_hash (simulating deployed code)
    const fake_code_hash = [_]u8{0xDE, 0xAD, 0xBE, 0xEF} ++ [_]u8{0} ** 28;
    try db.insertAccount(caller, state.AccountInfo{
        .balance = 1_000_000_000_000_000_000,
        .nonce = 0,
        .code_hash = fake_code_hash,
        .code = null,
    });

    var parts = makeEvm(db, primitives.SpecId.prague);
    var evm = handler_main.Evm.init(&parts.ctx, null, &parts.instructions, &parts.precompiles, &parts.frame_stack);
    parts.ctx.tx.caller = caller;
    parts.ctx.tx.gas_limit = 21000;
    parts.ctx.tx.gas_price = 1;
    parts.ctx.tx.nonce = 0;

    const result = Validation.validateAgainstStateAndDeductCaller(&evm, 21000);
    try std.testing.expectError(ValidationError.SenderHasCode, result);
}
