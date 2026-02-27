const std = @import("std");
const primitives = @import("primitives");
const database_mod = @import("database");
const context_mod = @import("context");
const state_mod = @import("state");
const bytecode_mod = @import("bytecode");

const Interpreter = @import("../interpreter.zig").Interpreter;
const ExtBytecode = @import("../interpreter.zig").ExtBytecode;
const InputsImpl = @import("../interpreter.zig").InputsImpl;
const Memory = @import("../memory.zig").Memory;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const Host = @import("../host.zig").Host;
const host_module = @import("../host.zig");
const protocol_schedule = @import("../protocol_schedule.zig");

const call_ops = @import("call.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const U = primitives.U256;
const ALLOC = std.heap.page_allocator;

/// Caller/target address used in CREATE tests
const CALLER: primitives.Address = [_]u8{0xCA} ** 20;

// ---------------------------------------------------------------------------
// Address derivation unit tests (pure computation, no EVM context)
// ---------------------------------------------------------------------------

test "createAddress: deterministic — same inputs give same address" {
    const sender = [_]u8{0} ** 20;
    const addr = host_module.createAddress(sender, 0);
    const addr2 = host_module.createAddress(sender, 0);
    try expect(std.mem.eql(u8, &addr, &addr2));
    // Result must be non-zero (a real keccak hash)
    var all_zero = true;
    for (addr) |b| { if (b != 0) { all_zero = false; break; } }
    try expect(!all_zero);
}

test "createAddress: nonce=0 vs nonce=1 produce different addresses" {
    const sender = [_]u8{0x11} ** 20;
    const addr0 = host_module.createAddress(sender, 0);
    const addr1 = host_module.createAddress(sender, 1);
    try expect(!std.mem.eql(u8, &addr0, &addr1));
}

test "createAddress: nonce=127 vs nonce=128 (multi-byte RLP) produce different addresses" {
    const sender = [_]u8{0x22} ** 20;
    const addr127 = host_module.createAddress(sender, 127);
    const addr128 = host_module.createAddress(sender, 128);
    try expect(!std.mem.eql(u8, &addr127, &addr128));
}

test "create2Address: same inputs produce same address" {
    const sender = [_]u8{0x33} ** 20;
    const salt: U = 0xDEADBEEF;
    const init_hash: [32]u8 = [_]u8{0xAB} ** 32;
    const a1 = host_module.create2Address(sender, salt, init_hash);
    const a2 = host_module.create2Address(sender, salt, init_hash);
    try expect(std.mem.eql(u8, &a1, &a2));
    var all_zero = true;
    for (a1) |b| { if (b != 0) { all_zero = false; break; } }
    try expect(!all_zero);
}

test "create2Address: different salts produce different addresses" {
    const sender = [_]u8{0x44} ** 20;
    const init_hash: [32]u8 = [_]u8{0xAB} ** 32;
    const a1 = host_module.create2Address(sender, 1, init_hash);
    const a2 = host_module.create2Address(sender, 2, init_hash);
    try expect(!std.mem.eql(u8, &a1, &a2));
}

// ---------------------------------------------------------------------------
// Helpers for opcode handler tests
// ---------------------------------------------------------------------------

fn makeCtx(db: database_mod.InMemoryDB) context_mod.Context {
    return context_mod.Context.new(db, .prague);
}

fn makeInterp(target: primitives.Address, gas_limit: u64) Interpreter {
    return Interpreter.new(
        Memory.new(),
        ExtBytecode.default(),
        InputsImpl.new(
            CALLER,
            target,
            0,
            @as(primitives.Bytes, @constCast(&[_]u8{})),
            gas_limit,
            .call,
            false,
            0,
        ),
        false,
        .prague,
        gas_limit,
    );
}

// ---------------------------------------------------------------------------
// opCreate edge-case tests
// ---------------------------------------------------------------------------

test "opCreate: stack underflow with fewer than 3 items" {
    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(CALLER, state_mod.AccountInfo.new(1_000_000, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(CALLER);

    var interp = makeInterp(CALLER, 100_000);
    interp.stack.pushUnsafe(0);
    interp.stack.pushUnsafe(0); // only 2 items

    var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };
    call_ops.opCreate(&ic);

    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.stack_underflow, interp.result);
}

test "opCreate: static context halts with invalid_static" {
    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(CALLER, state_mod.AccountInfo.new(1_000_000, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(CALLER);

    var interp = makeInterp(CALLER, 100_000);
    interp.runtime_flags.is_static = true;
    interp.stack.pushUnsafe(0); // value (top)
    interp.stack.pushUnsafe(0); // offset
    interp.stack.pushUnsafe(0); // size

    var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };
    call_ops.opCreate(&ic);

    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.invalid_static, interp.result);
}

test "opCreate2: stack underflow with fewer than 4 items" {
    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(CALLER, state_mod.AccountInfo.new(1_000_000, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(CALLER);

    var interp = makeInterp(CALLER, 100_000);
    // Push only 3 items; CREATE2 needs 4
    interp.stack.pushUnsafe(0);
    interp.stack.pushUnsafe(0);
    interp.stack.pushUnsafe(0);

    var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };
    call_ops.opCreate2(&ic);

    try expect(!interp.bytecode.continue_execution);
    try expectEqual(.stack_underflow, interp.result);
}

test "opCreate: STOP init code deploys empty contract, returns non-zero address" {
    // Init code = [STOP]. Sub-interpreter halts with .stop and returns empty data.
    // Contract is deployed with zero-length code; address on stack must be non-zero.
    const INIT_CODE = [_]u8{0x00}; // STOP

    var db = database_mod.InMemoryDB.init(ALLOC);
    // Caller nonce = 1 so we can predict the CREATE address
    try db.insertAccount(CALLER, state_mod.AccountInfo.new(1_000_000, 1, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(CALLER);

    var interp = makeInterp(CALLER, 500_000);
    // Write init code into interpreter memory at offset 0
    interp.memory.buffer.resize(ALLOC, INIT_CODE.len) catch unreachable;
    @memcpy(interp.memory.buffer.items[0..INIT_CODE.len], &INIT_CODE);

    // Stack layout for CREATE (top to bottom): value, offset, size
    interp.stack.pushUnsafe(0);              // value (top)
    interp.stack.pushUnsafe(0);              // offset
    interp.stack.pushUnsafe(INIT_CODE.len);  // size

    var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };
    call_ops.opCreate(&ic);

    try expect(interp.bytecode.continue_execution); // parent keeps running
    const pushed = interp.stack.popUnsafe();
    try expect(pushed != 0); // non-zero = success
}

test "opCreate2: same inputs produce same address on stack" {
    const INIT_CODE = [_]u8{0x00}; // STOP

    // Run CREATE2 twice with fresh contexts but identical inputs
    const run = struct {
        fn exec() !U {
            var db = database_mod.InMemoryDB.init(ALLOC);
            try db.insertAccount(CALLER, state_mod.AccountInfo.new(1_000_000, 1, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
            var ctx = makeCtx(db);
            _ = try ctx.journaled_state.loadAccount(CALLER);

            var interp = makeInterp(CALLER, 500_000);
            interp.memory.buffer.resize(ALLOC, INIT_CODE.len) catch unreachable;
            @memcpy(interp.memory.buffer.items[0..INIT_CODE.len], &INIT_CODE);

            // Stack: salt (top), value, offset, size
            interp.stack.pushUnsafe(42);             // salt (top)
            interp.stack.pushUnsafe(0);              // value
            interp.stack.pushUnsafe(0);              // offset
            interp.stack.pushUnsafe(INIT_CODE.len);  // size

            var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
            var ic = InstructionContext{ .interpreter = &interp, .host = &host };
            call_ops.opCreate2(&ic);
            return interp.stack.popUnsafe();
        }
    };

    const addr1 = try run.exec();
    const addr2 = try run.exec();
    try expect(addr1 != 0);
    try expectEqual(addr1, addr2);
}

test "opCreate: collision at derived address returns 0" {
    // First CREATE deploys a contract at the address derived from (CALLER, nonce=1).
    // Then we pre-poison the address derived from (CALLER, nonce=2) with nonce=1 so
    // the second CREATE detects a collision and pushes 0.
    const INIT_CODE = [_]u8{0x00}; // STOP

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(CALLER, state_mod.AccountInfo.new(1_000_000, 1, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(CALLER);

    // First CREATE — succeeds, nonce bumped from 1→2
    {
        var interp = makeInterp(CALLER, 500_000);
        interp.memory.buffer.resize(ALLOC, INIT_CODE.len) catch unreachable;
        @memcpy(interp.memory.buffer.items[0..INIT_CODE.len], &INIT_CODE);
        interp.stack.pushUnsafe(0);
        interp.stack.pushUnsafe(0);
        interp.stack.pushUnsafe(INIT_CODE.len);
        var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
        var ic = InstructionContext{ .interpreter = &interp, .host = &host };
        call_ops.opCreate(&ic);
        const first_addr = interp.stack.popUnsafe();
        try expect(first_addr != 0);
    }

    // Pre-insert a non-empty account at the address that CALLER (nonce=2) would derive.
    // This forces a collision on the second CREATE.
    const collision_addr = host_module.createAddress(CALLER, 2);
    _ = ctx.journaled_state.loadAccount(collision_addr) catch {};
    const acc = ctx.journaled_state.inner.evm_state.getPtr(collision_addr) orelse unreachable;
    acc.info.nonce = 1; // non-zero nonce triggers collision

    // Second CREATE — should detect collision and return 0
    {
        var interp = makeInterp(CALLER, 500_000);
        interp.memory.buffer.resize(ALLOC, INIT_CODE.len) catch unreachable;
        @memcpy(interp.memory.buffer.items[0..INIT_CODE.len], &INIT_CODE);
        interp.stack.pushUnsafe(0);
        interp.stack.pushUnsafe(0);
        interp.stack.pushUnsafe(INIT_CODE.len);
        var host = Host{ .ctx = &ctx, .run_sub_call = protocol_schedule.runSubCallDefault };
        var ic = InstructionContext{ .interpreter = &interp, .host = &host };
        call_ops.opCreate(&ic);
        const second_result = interp.stack.popUnsafe();
        try expectEqual(@as(U, 0), second_result);
    }
}
