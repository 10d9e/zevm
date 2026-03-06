const std = @import("std");
const primitives = @import("primitives");
const database_mod = @import("database");
const context_mod = @import("context");
const state_mod = @import("state");
const bytecode_mod = @import("bytecode");

const Interpreter = @import("../interpreter.zig").Interpreter;
const ExtBytecode = @import("../interpreter.zig").ExtBytecode;
const Gas = @import("../gas.zig").Gas;
const InstructionContext = @import("../instruction_context.zig").InstructionContext;
const Host = @import("../host.zig").Host;
const host_module = @import("../host.zig");
const gas_costs = @import("../gas_costs.zig");

const host_ops = @import("host_ops.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const U = primitives.U256;
const ALLOC = std.heap.page_allocator;

/// Test contract address (interpreter target / msg.this)
const TARGET: primitives.Address = [_]u8{0xAA} ** 20;
/// External address for balance / extcode tests
const OTHER: primitives.Address = [_]u8{0xCC} ** 20;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Default interpreter with TARGET as the executing contract address.
fn makeInterp() Interpreter {
    var interp = Interpreter.defaultExt();
    interp.input.target = TARGET;
    return interp;
}

/// Build a test context with the given pre-populated database.
/// Note: InMemoryDB is copied by value into Context; both copies share the same
/// underlying HashMap heap data, so insertions done to `db` before this call
/// are visible in the returned context.
fn makeCtx(db: database_mod.InMemoryDB) context_mod.Context {
    return context_mod.Context.new(db, .prague);
}

// ---------------------------------------------------------------------------
// SLOAD tests
// ---------------------------------------------------------------------------

test "SLOAD: slot present in state returns stored value" {
    const KEY: U = 0xDEAD;
    const VALUE: U = 0xBEEF;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    try db.insertStorage(TARGET, KEY, VALUE);
    var ctx = makeCtx(db);
    // Pre-load account so journal sload can find it in evm_state
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    interp.stack.pushUnsafe(KEY);

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSload(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(VALUE, interp.stack.popUnsafe());
}

test "SLOAD: slot absent returns zero" {
    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 0x1234)); // key with no storage entry

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSload(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "SLOAD: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 1));
    var ic = InstructionContext{ .interpreter = &interp }; // host = null

    host_ops.opSload(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

test "SLOAD: stack underflow halts" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSload(&ic);

    try expectEqual(.stack_underflow, interp.result);
}

test "SLOAD: cold access charges COLD_SLOAD gas (Berlin+)" {
    const KEY: U = 42;
    const GAS_LIMIT: u64 = 100_000;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    interp.gas = Gas.new(GAS_LIMIT);
    interp.stack.pushUnsafe(KEY);

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSload(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(GAS_LIMIT - gas_costs.COLD_SLOAD, interp.gas.remaining);
}

test "SLOAD: second access to same slot charges WARM_SLOAD gas" {
    const KEY: U = 42;
    const GAS_LIMIT: u64 = 100_000;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    try db.insertStorage(TARGET, KEY, 0xFF);
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    interp.gas = Gas.new(GAS_LIMIT);
    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    // First access: cold
    interp.stack.pushUnsafe(KEY);
    host_ops.opSload(&ic);
    try expect(interp.bytecode.continue_execution);
    _ = interp.stack.popUnsafe(); // discard value

    const after_cold = interp.gas.remaining;
    try expectEqual(GAS_LIMIT - gas_costs.COLD_SLOAD, after_cold);

    // Second access: warm
    interp.stack.pushUnsafe(KEY);
    host_ops.opSload(&ic);
    try expect(interp.bytecode.continue_execution);

    try expectEqual(after_cold - gas_costs.WARM_SLOAD, interp.gas.remaining);
}

test "SLOAD: out of gas halts with out_of_gas" {
    const KEY: U = 1;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    // Set gas below COLD_SLOAD cost (2100)
    interp.gas = Gas.new(gas_costs.COLD_SLOAD - 1);
    interp.stack.pushUnsafe(KEY);

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSload(&ic);

    try expectEqual(.out_of_gas, interp.result);
}

// ---------------------------------------------------------------------------
// SSTORE tests
// ---------------------------------------------------------------------------

test "SSTORE: writes value verifiable via sload" {
    const KEY: U = 0xCAFE;
    const VALUE: U = 0x1337;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    // Stack for SSTORE: [key (top), value]
    interp.stack.pushUnsafe(VALUE);
    interp.stack.pushUnsafe(KEY);

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSstore(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 0), interp.stack.len());

    // Verify the value was written via sload
    interp.stack.pushUnsafe(KEY);
    host_ops.opSload(&ic);
    try expectEqual(VALUE, interp.stack.popUnsafe());
}

test "SSTORE: static context halts with invalid_static" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.runtime_flags.is_static = true;
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 1));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSstore(&ic);

    try expectEqual(.invalid_static, interp.result);
}

test "SSTORE: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 1));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opSstore(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

test "SSTORE: stack underflow halts" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 1)); // only 1 item, need 2

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSstore(&ic);

    try expectEqual(.stack_underflow, interp.result);
}

// ---------------------------------------------------------------------------
// TLOAD / TSTORE tests
// ---------------------------------------------------------------------------

test "TSTORE then TLOAD round-trips a value" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    // TSTORE: stack [key (top), value]
    interp.stack.pushUnsafe(@as(U, 99)); // value
    interp.stack.pushUnsafe(@as(U, 5)); // key (top)
    host_ops.opTstore(&ic);
    try expect(interp.bytecode.continue_execution);

    // TLOAD: stack [key (top)]
    interp.stack.pushUnsafe(@as(U, 5));
    host_ops.opTload(&ic);
    try expectEqual(@as(U, 99), interp.stack.popUnsafe());
}

test "TLOAD: unset key returns zero" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 7)); // key not set

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opTload(&ic);

    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "TSTORE: static context halts with invalid_static" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.runtime_flags.is_static = true;
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 1));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opTstore(&ic);

    try expectEqual(.invalid_static, interp.result);
}

test "TLOAD: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 1));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opTload(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

// ---------------------------------------------------------------------------
// BALANCE tests
// ---------------------------------------------------------------------------

test "BALANCE: returns correct balance for known account" {
    const BAL: U = 12345678;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(OTHER, state_mod.AccountInfo.new(BAL, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opBalance(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(BAL, interp.stack.popUnsafe());
}

test "BALANCE: cold access charges COLD_ACCOUNT_ACCESS gas (Berlin+)" {
    const GAS_LIMIT: u64 = 100_000;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(OTHER, state_mod.AccountInfo.new(1000, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.gas = Gas.new(GAS_LIMIT);
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opBalance(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(GAS_LIMIT - gas_costs.COLD_ACCOUNT_ACCESS, interp.gas.remaining);
}

test "BALANCE: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opBalance(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

test "BALANCE: stack underflow halts" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opBalance(&ic);

    try expectEqual(.stack_underflow, interp.result);
}

// ---------------------------------------------------------------------------
// SELFBALANCE tests
// ---------------------------------------------------------------------------

test "SELFBALANCE: returns balance of executing contract" {
    const BAL: U = 42_000_000;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.new(BAL, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.new()));
    var ctx = makeCtx(db);

    var interp = makeInterp(); // interp.input.target = TARGET

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSelfbalance(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(BAL, interp.stack.popUnsafe());
}

test "SELFBALANCE: no host halts with invalid_opcode" {
    var interp = makeInterp();
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opSelfbalance(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

// ---------------------------------------------------------------------------
// EXTCODESIZE tests
// ---------------------------------------------------------------------------

test "EXTCODESIZE: EOA with empty code returns 0" {
    // Bytecode.new() has original_len=1 (STOP padding); use newLegacy("") for truly empty code.
    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(OTHER, state_mod.AccountInfo.new(0, 0, primitives.KECCAK_EMPTY, bytecode_mod.Bytecode.newLegacy(&[_]u8{})));
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opExtcodesize(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "EXTCODESIZE: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opExtcodesize(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

test "EXTCODESIZE: stack underflow halts" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opExtcodesize(&ic);

    try expectEqual(.stack_underflow, interp.result);
}

// ---------------------------------------------------------------------------
// EXTCODEHASH tests
// ---------------------------------------------------------------------------

test "EXTCODEHASH: empty account returns 0" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db); // OTHER not in DB → empty account

    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opExtcodehash(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "EXTCODEHASH: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opExtcodehash(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

// ---------------------------------------------------------------------------
// BLOCKHASH tests
// ---------------------------------------------------------------------------

test "BLOCKHASH: known block returns hash" {
    const BLOCK_NUM: u64 = 100;
    const HASH: primitives.Hash = [_]u8{0xAB} ** 32;

    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertBlockHash(BLOCK_NUM, HASH);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, BLOCK_NUM));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opBlockhash(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(host_module.hashToU256(HASH), interp.stack.popUnsafe());
}

test "BLOCKHASH: unknown block returns 0" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 999));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opBlockhash(&ic);

    try expectEqual(@as(U, 0), interp.stack.popUnsafe());
}

test "BLOCKHASH: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 1));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opBlockhash(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

// ---------------------------------------------------------------------------
// LOG tests
// ---------------------------------------------------------------------------

test "LOG0: emits log with correct address and empty data" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp(); // input.target = TARGET
    // Stack: [offset (top), size]
    interp.stack.pushUnsafe(@as(U, 0)); // size
    interp.stack.pushUnsafe(@as(U, 0)); // offset (top)

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opLog0(&ic);

    try expect(interp.bytecode.continue_execution);
    try expectEqual(@as(usize, 0), interp.stack.len());

    const logs = ctx.journaled_state.inner.logs.items;
    try expectEqual(@as(usize, 1), logs.len);
    try expect(std.mem.eql(u8, &logs[0].address, &TARGET));
    try expectEqual(@as(usize, 0), logs[0].topics.len);
    try expectEqual(@as(usize, 0), logs[0].data.len);
}

test "LOG1: emits log with one topic" {
    const TOPIC_HASH: primitives.Hash = [_]u8{0x55} ** 32;
    const TOPIC_VAL: U = host_module.hashToU256(TOPIC_HASH);

    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    // Stack for LOG1: [offset (top), size, topic0]
    // Push in reverse order so offset ends up on top
    interp.stack.pushUnsafe(TOPIC_VAL); // topic0 (depth 2)
    interp.stack.pushUnsafe(@as(U, 0)); // size (depth 1)
    interp.stack.pushUnsafe(@as(U, 0)); // offset (top)

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opLog1(&ic);

    try expect(interp.bytecode.continue_execution);

    const logs = ctx.journaled_state.inner.logs.items;
    try expectEqual(@as(usize, 1), logs.len);
    try expectEqual(@as(usize, 1), logs[0].topics.len);
    try expect(std.mem.eql(u8, &logs[0].topics[0], &TOPIC_HASH));
}

test "LOG0: static context halts with invalid_static" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.runtime_flags.is_static = true;
    interp.stack.pushUnsafe(@as(U, 0)); // size
    interp.stack.pushUnsafe(@as(U, 0)); // offset

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opLog0(&ic);

    try expectEqual(.invalid_static, interp.result);
}

test "LOG4: emits log with four topics" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    // Stack for LOG4: [offset (top), size, t0, t1, t2, t3]
    interp.stack.pushUnsafe(@as(U, 4)); // topic3
    interp.stack.pushUnsafe(@as(U, 3)); // topic2
    interp.stack.pushUnsafe(@as(U, 2)); // topic1
    interp.stack.pushUnsafe(@as(U, 1)); // topic0
    interp.stack.pushUnsafe(@as(U, 0)); // size
    interp.stack.pushUnsafe(@as(U, 0)); // offset (top)

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opLog4(&ic);

    try expect(interp.bytecode.continue_execution);

    const logs = ctx.journaled_state.inner.logs.items;
    try expectEqual(@as(usize, 1), logs.len);
    try expectEqual(@as(usize, 4), logs[0].topics.len);
}

test "LOG0: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(@as(U, 0));
    interp.stack.pushUnsafe(@as(U, 0));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opLog0(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

// ---------------------------------------------------------------------------
// SELFDESTRUCT tests
// ---------------------------------------------------------------------------

test "SELFDESTRUCT: halts with selfdestruct result" {
    var db = database_mod.InMemoryDB.init(ALLOC);
    try db.insertAccount(TARGET, state_mod.AccountInfo.default());
    try db.insertAccount(OTHER, state_mod.AccountInfo.default());
    var ctx = makeCtx(db);
    _ = try ctx.journaled_state.loadAccount(TARGET);

    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER)); // target address

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSelfdestruct(&ic);

    try expectEqual(.selfdestruct, interp.result);
}

test "SELFDESTRUCT: static context halts with invalid_static" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    interp.runtime_flags.is_static = true;
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));

    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSelfdestruct(&ic);

    try expectEqual(.invalid_static, interp.result);
}

test "SELFDESTRUCT: no host halts with invalid_opcode" {
    var interp = makeInterp();
    interp.stack.pushUnsafe(host_module.addressToU256(OTHER));
    var ic = InstructionContext{ .interpreter = &interp };

    host_ops.opSelfdestruct(&ic);

    try expectEqual(.invalid_opcode, interp.result);
}

test "SELFDESTRUCT: stack underflow halts" {
    const db = database_mod.InMemoryDB.init(ALLOC);
    var ctx = makeCtx(db);

    var interp = makeInterp();
    var host = Host{ .ctx = &ctx };
    var ic = InstructionContext{ .interpreter = &interp, .host = &host };

    host_ops.opSelfdestruct(&ic);

    try expectEqual(.stack_underflow, interp.result);
}
