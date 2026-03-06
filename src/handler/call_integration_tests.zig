/// Gas accounting correctness tests: CALL gas forwarding, refund propagation,
/// SSTORE EIP-2200 stipend protection, and call gas schedule constants.
const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const state = @import("state");
const database = @import("database");
const bytecode_mod = @import("bytecode");
const interpreter_mod = @import("interpreter");
const handler_main = @import("main.zig");
const mainnet_builder = @import("mainnet_builder.zig");

const ExecuteEvm = mainnet_builder.ExecuteEvm;
const gas_costs = interpreter_mod.gas_costs;
const ALLOC = std.heap.c_allocator;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const CALLER: primitives.Address = [_]u8{0xAA} ** 20;
const CALLEE: primitives.Address = [_]u8{0xBB} ** 20;
const COINBASE: primitives.Address = [_]u8{0xCB} ** 20;

fn makeParts(db: database.InMemoryDB, spec: primitives.SpecId) struct {
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

fn insertEoa(db: *database.InMemoryDB, addr: primitives.Address, balance: primitives.U256, nonce: u64) !void {
    try db.insertAccount(addr, state.AccountInfo{
        .balance = balance,
        .nonce = nonce,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });
}

fn insertContract(db: *database.InMemoryDB, addr: primitives.Address, code: []const u8) !void {
    var code_hash: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(code, &code_hash, .{});
    const bc = bytecode_mod.Bytecode.newRaw(code);
    try db.insertAccount(addr, state.AccountInfo{
        .balance = 0,
        .nonce = 1,
        .code_hash = code_hash,
        .code = bc,
    });
}

// ---------------------------------------------------------------------------
// Gas schedule constant tests
// ---------------------------------------------------------------------------

test "call gas schedule: pre-Berlin flat 700 (warm/cold ignored)" {
    const cost_warm = gas_costs.getCallGasCost(.istanbul, false, false, true);
    const cost_cold = gas_costs.getCallGasCost(.istanbul, true, false, true);
    try std.testing.expectEqual(@as(u64, 700), cost_warm);
    try std.testing.expectEqual(@as(u64, 700), cost_cold); // cold flag has no effect pre-Berlin
}

test "call gas schedule: Berlin+ uses access cost only — no 700 double-charge" {
    const cold = gas_costs.getCallGasCost(.berlin, true, false, true);
    const warm = gas_costs.getCallGasCost(.berlin, false, false, true);
    try std.testing.expectEqual(@as(u64, 2600), cold);
    try std.testing.expectEqual(@as(u64, 100), warm);
}

test "call gas schedule: Prague warm + value transfer" {
    // warm (100) + G_CALLVALUE (9000) = 9100
    const cost = gas_costs.getCallGasCost(.prague, false, true, true);
    try std.testing.expectEqual(@as(u64, 9100), cost);
}

test "call gas schedule: Frontier is 40" {
    const cost = gas_costs.getCallGasCost(.frontier, false, false, true);
    try std.testing.expectEqual(@as(u64, 40), cost);
}

// ---------------------------------------------------------------------------
// SSTORE EIP-2200 stipend protection
// ---------------------------------------------------------------------------

test "SSTORE EIP-2200: fails when gas_remaining <= 2300 (Istanbul+)" {
    // Contract: PUSH1 0x42 PUSH1 0x00 SSTORE STOP
    const sstore_code = [_]u8{ 0x60, 0x42, 0x60, 0x00, 0x55, 0x00 };

    var db = database.InMemoryDB.init(ALLOC);
    defer db.deinit();
    try insertEoa(&db, CALLER, 1_000_000_000_000_000_000, 0);
    try insertContract(&db, CALLEE, &sstore_code);

    var parts = makeParts(db, .istanbul);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(CALLEE);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .precompiles = null,
    };

    // Exactly 2300 gas — EIP-2200 guard fires before SSTORE
    const result = host.call(.{
        .caller = CALLER,
        .target = CALLEE,
        .callee = CALLEE,
        .value = 0,
        .data = &[_]u8{},
        .gas_limit = 2300,
        .scheme = .call,
        .is_static = false,
    });
    try std.testing.expect(!result.success);
}

test "SSTORE EIP-2200: succeeds with sufficient gas" {
    const sstore_code = [_]u8{ 0x60, 0x42, 0x60, 0x00, 0x55, 0x00 };

    var db = database.InMemoryDB.init(ALLOC);
    defer db.deinit();
    try insertEoa(&db, CALLER, 1_000_000_000_000_000_000, 0);
    try insertContract(&db, CALLEE, &sstore_code);

    var parts = makeParts(db, .istanbul);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(CALLEE);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .precompiles = null,
    };

    // 50,000 gas — plenty for SSTORE set (20000 + SLOAD overhead)
    const result = host.call(.{
        .caller = CALLER,
        .target = CALLEE,
        .callee = CALLEE,
        .value = 0,
        .data = &[_]u8{},
        .gas_limit = 50_000,
        .scheme = .call,
        .is_static = false,
    });
    try std.testing.expect(result.success);
}

// ---------------------------------------------------------------------------
// Gas refund propagation
// ---------------------------------------------------------------------------

test "gas refund propagation: SSTORE clear in sub-call surfaces in CallResult" {
    // Contract B clears storage slot 0 (non-zero → zero) → earns SSTORE_CLEARS refund.
    // PUSH1 0x00 PUSH1 0x00 SSTORE STOP = 0x60 0x00 0x60 0x00 0x55 0x00
    const clear_code = [_]u8{ 0x60, 0x00, 0x60, 0x00, 0x55, 0x00 };

    var db = database.InMemoryDB.init(ALLOC);
    defer db.deinit();
    try insertEoa(&db, CALLER, 1_000_000_000_000_000_000, 0);
    try insertContract(&db, CALLEE, &clear_code);

    var parts = makeParts(db, .berlin);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(CALLEE);

    // Pre-warm and set slot 0 to non-zero so clearing it earns a refund
    _ = try parts.ctx.journaled_state.sstore(CALLEE, 0, 1);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .precompiles = null,
    };

    const result = host.call(.{
        .caller = CALLER,
        .target = CALLEE,
        .callee = CALLEE,
        .value = 0,
        .data = &[_]u8{},
        .gas_limit = 100_000,
        .scheme = .call,
        .is_static = false,
    });

    try std.testing.expect(result.success);
    // SSTORE_CLEARS_SCHEDULE = 15000 (Berlin, pre-London refund)
    try std.testing.expect(result.gas_refunded > 0);
}

// ---------------------------------------------------------------------------
// Full transaction: plain ETH transfer
// ---------------------------------------------------------------------------

test "full tx: plain ETH transfer to EOA succeeds and uses exactly 21000 gas" {
    const gwei: u128 = 1_000_000_000;
    const initial_balance: primitives.U256 = 100 * gwei * 21_000;

    var db = database.InMemoryDB.init(ALLOC);
    defer db.deinit();
    try insertEoa(&db, CALLER, initial_balance, 0);
    try insertEoa(&db, CALLEE, 0, 0);

    var parts = makeParts(db, .prague);
    var evm = handler_main.Evm.init(
        &parts.ctx,
        null,
        &parts.instructions,
        &parts.precompiles,
        &parts.frame_stack,
    );

    parts.ctx.tx.caller = CALLER;
    parts.ctx.tx.gas_limit = 21_000;
    parts.ctx.tx.gas_price = gwei;
    parts.ctx.tx.gas_priority_fee = null;
    parts.ctx.tx.nonce = 0;
    parts.ctx.tx.value = gwei; // 1 gwei transfer
    parts.ctx.tx.kind = .{ .Call = CALLEE };
    parts.ctx.block.basefee = @as(u64, @intCast(gwei));
    parts.ctx.block.beneficiary = COINBASE;

    const result = try ExecuteEvm.execute(&evm);

    try std.testing.expectEqual(handler_main.ExecutionStatus.Success, result.status);
    // Plain transfer to EOA: gas_used = 21000 (intrinsic only, no exec gas)
    try std.testing.expectEqual(@as(u64, 21_000), result.gas_used);
}
