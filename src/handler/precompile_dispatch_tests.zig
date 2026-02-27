/// Phase 4 tests: precompile dispatch through Host.call() and top-level CREATE transactions.
/// Imported from mainnet_builder.zig.
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
const ALLOC = std.heap.c_allocator;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const CALLER: primitives.Address = [_]u8{0xAA} ** 20;
const COINBASE: primitives.Address = [_]u8{0xCB} ** 20;

/// Address of the IDENTITY precompile (0x04)
const IDENTITY_ADDR: primitives.Address = blk: {
    var a = [_]u8{0} ** 20;
    a[19] = 0x04;
    break :blk a;
};

/// Address of the SHA256 precompile (0x02)
const SHA256_ADDR: primitives.Address = blk: {
    var a = [_]u8{0} ** 20;
    a[19] = 0x02;
    break :blk a;
};

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

fn insertCaller(db: *database.InMemoryDB, addr: primitives.Address, balance: primitives.U256, nonce: u64) !void {
    try db.insertAccount(addr, state.AccountInfo{
        .balance = balance,
        .nonce = nonce,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });
}

// ---------------------------------------------------------------------------
// Precompile dispatch tests (via Host.call)
// ---------------------------------------------------------------------------

test "precompile dispatch: IDENTITY returns input unchanged" {
    const input_data = "hello, precompile!";

    var db = database.InMemoryDB.init(ALLOC);
    try insertCaller(&db, CALLER, 1_000_000, 0);
    var parts = makeEvmParts(db, .prague);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(IDENTITY_ADDR);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .run_sub_call = interpreter_mod.protocol_schedule.runSubCallDefault,
        .precompiles = &parts.precompiles.precompiles,
    };

    const result = host.call(.{
        .caller = CALLER,
        .target = IDENTITY_ADDR,
        .callee = IDENTITY_ADDR,
        .value = 0,
        .data = input_data,
        .gas_limit = 100_000,
        .scheme = .call,
        .is_static = false,
    });

    try std.testing.expect(result.success);
    // IDENTITY returns the input data verbatim
    try std.testing.expectEqualSlices(u8, input_data, result.return_data);
    // Gas used: IDENTITY base=15, word_cost=3*(ceil(18/32))=3 → 18 gas
    try std.testing.expectEqual(@as(u64, 18), result.gas_used);
    try std.testing.expectEqual(@as(u64, 100_000 - 18), result.gas_remaining);
}

test "precompile dispatch: IDENTITY with no data returns empty" {
    var db = database.InMemoryDB.init(ALLOC);
    try insertCaller(&db, CALLER, 1_000_000, 0);
    var parts = makeEvmParts(db, .prague);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(IDENTITY_ADDR);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .run_sub_call = interpreter_mod.protocol_schedule.runSubCallDefault,
        .precompiles = &parts.precompiles.precompiles,
    };

    const result = host.call(.{
        .caller = CALLER,
        .target = IDENTITY_ADDR,
        .callee = IDENTITY_ADDR,
        .value = 0,
        .data = &[_]u8{},
        .gas_limit = 100_000,
        .scheme = .call,
        .is_static = false,
    });

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 0), result.return_data.len);
    // Gas: base=15 + 0 word cost = 15
    try std.testing.expectEqual(@as(u64, 15), result.gas_used);
}

test "precompile dispatch: out-of-gas fails and consumes all gas" {
    var db = database.InMemoryDB.init(ALLOC);
    try insertCaller(&db, CALLER, 1_000_000, 0);
    var parts = makeEvmParts(db, .prague);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(IDENTITY_ADDR);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .run_sub_call = interpreter_mod.protocol_schedule.runSubCallDefault,
        .precompiles = &parts.precompiles.precompiles,
    };

    // IDENTITY needs at least 15 gas; give it less
    const result = host.call(.{
        .caller = CALLER,
        .target = IDENTITY_ADDR,
        .callee = IDENTITY_ADDR,
        .value = 0,
        .data = &[_]u8{},
        .gas_limit = 10, // not enough
        .scheme = .call,
        .is_static = false,
    });

    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(u64, 0), result.gas_remaining);
}

test "precompile dispatch: null precompiles falls back to interpreter (no precompile)" {
    // Host with precompiles=null should NOT dispatch precompiles.
    // IDENTITY address with null precompiles → runs as empty contract → stop with empty return.
    var db = database.InMemoryDB.init(ALLOC);
    try insertCaller(&db, CALLER, 1_000_000, 0);
    var parts = makeEvmParts(db, .prague);
    _ = try parts.ctx.journaled_state.loadAccount(CALLER);
    _ = try parts.ctx.journaled_state.loadAccount(IDENTITY_ADDR);

    var host = interpreter_mod.Host{
        .ctx = &parts.ctx,
        .run_sub_call = interpreter_mod.protocol_schedule.runSubCallDefault,
        .precompiles = null, // disabled
    };

    const result = host.call(.{
        .caller = CALLER,
        .target = IDENTITY_ADDR,
        .callee = IDENTITY_ADDR,
        .value = 0,
        .data = "hi",
        .gas_limit = 100_000,
        .scheme = .call,
        .is_static = false,
    });

    // Without precompile dispatch, IDENTITY address is an empty contract (STOP)
    // → success but empty return data (not echoing input)
    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 0), result.return_data.len);
}

// ---------------------------------------------------------------------------
// Top-level CREATE transaction tests
// ---------------------------------------------------------------------------

test "executeFrame: CREATE tx with STOP init code deploys successfully" {
    // Init code = [STOP (0x00)]: sub-interpreter halts immediately,
    // return data is empty → deployed code is empty (0 bytes, no deposit gas).
    // Caller nonce=0 → bumped to 1 during validation, so address derived from nonce=0.
    const init_code = [_]u8{0x00}; // STOP

    var db = database.InMemoryDB.init(ALLOC);
    defer db.deinit();
    const balance: primitives.U256 = 1_000_000_000_000_000_000; // 1 ETH
    try db.insertAccount(CALLER, state.AccountInfo{
        .balance = balance,
        .nonce = 0,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });

    var parts = makeEvmParts(db, .prague);
    var evm = handler_main.Evm.init(
        &parts.ctx,
        null,
        &parts.instructions,
        &parts.precompiles,
        &parts.frame_stack,
    );

    const gwei: u128 = 1_000_000_000;
    parts.ctx.tx.caller = CALLER;
    parts.ctx.tx.gas_limit = 200_000;
    parts.ctx.tx.gas_price = gwei;
    parts.ctx.tx.gas_priority_fee = null;
    parts.ctx.tx.nonce = 0;
    parts.ctx.tx.value = 0;
    parts.ctx.tx.kind = .Create;
    parts.ctx.tx.data = blk: {
        var list = std.ArrayList(u8){};
        try list.appendSlice(ALLOC, &init_code);
        break :blk list;
    };
    parts.ctx.block.basefee = @as(u64, @intCast(gwei));
    parts.ctx.block.beneficiary = COINBASE;

    const result = try ExecuteEvm.execute(&evm);

    // Expect success — STOP is a valid (empty) deployment
    try std.testing.expectEqual(handler_main.ExecutionStatus.Success, result.status);
}

test "executeFrame: CREATE tx with REVERT init code fails gracefully" {
    // Init code = [REVERT 0 0]: deployment fails, tx should report Revert (not crash).
    // PUSH1 0x00 PUSH1 0x00 REVERT = 0x60 0x00 0x60 0x00 0xFD
    const init_code = [_]u8{ 0x60, 0x00, 0x60, 0x00, 0xFD }; // PUSH1 0 PUSH1 0 REVERT

    var db = database.InMemoryDB.init(ALLOC);
    defer db.deinit();
    const balance: primitives.U256 = 1_000_000_000_000_000_000;
    try db.insertAccount(CALLER, state.AccountInfo{
        .balance = balance,
        .nonce = 0,
        .code_hash = primitives.KECCAK_EMPTY,
        .code = null,
    });

    var parts = makeEvmParts(db, .prague);
    var evm = handler_main.Evm.init(
        &parts.ctx,
        null,
        &parts.instructions,
        &parts.precompiles,
        &parts.frame_stack,
    );

    const gwei: u128 = 1_000_000_000;
    parts.ctx.tx.caller = CALLER;
    parts.ctx.tx.gas_limit = 200_000;
    parts.ctx.tx.gas_price = gwei;
    parts.ctx.tx.gas_priority_fee = null;
    parts.ctx.tx.nonce = 0;
    parts.ctx.tx.value = 0;
    parts.ctx.tx.kind = .Create;
    parts.ctx.tx.data = blk: {
        var list = std.ArrayList(u8){};
        try list.appendSlice(ALLOC, &init_code);
        break :blk list;
    };
    parts.ctx.block.basefee = @as(u64, @intCast(gwei));
    parts.ctx.block.beneficiary = COINBASE;

    const result = try ExecuteEvm.execute(&evm);

    // REVERT → deployment fails, status should be Revert
    try std.testing.expectEqual(handler_main.ExecutionStatus.Revert, result.status);
}
