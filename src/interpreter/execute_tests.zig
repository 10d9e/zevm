const std = @import("std");
const primitives = @import("primitives");
const bytecode_mod = @import("bytecode");
const context = @import("context");
const Interpreter = @import("interpreter.zig").Interpreter;
const ExtBytecode = @import("interpreter.zig").ExtBytecode;
const InputsImpl = @import("interpreter.zig").InputsImpl;
const Memory = @import("memory.zig").Memory;
const InstructionResult = @import("instruction_result.zig").InstructionResult;
const Host = @import("host.zig").Host;

const U256 = primitives.U256;
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

fn u256FromBeBytes(bytes: [32]u8) U256 {
    return @byteSwap(@as(U256, @bitCast(bytes)));
}

fn addrToU256(addr: [20]u8) U256 {
    var buf: [32]u8 = [_]u8{0} ** 32;
    @memcpy(buf[12..32], &addr);
    return u256FromBeBytes(buf);
}

// --- Test host that records calls ---

const RecordingHost = struct {
    // sload: return this value for any key
    sload_return: U256 = @as(U256, 0),
    // sstore: record last call
    sstore_called: bool = false,
    sstore_addr: [20]u8 = [_]u8{0} ** 20,
    sstore_key: U256 = @as(U256, 0),
    sstore_val: U256 = @as(U256, 0),
    // balance
    balance_return: U256 = @as(U256, 0),
    balance_addr: [20]u8 = [_]u8{0} ** 20,
    balance_called: bool = false,
    // code
    code_return: []const u8 = &.{},
    code_called: bool = false,
    // codeSize
    code_size_return: usize = 0,
    code_size_called: bool = false,
    // codeHash
    code_hash_return: U256 = @as(U256, 0),
    code_hash_called: bool = false,
    // blockHash
    block_hash_return: U256 = @as(U256, 0),
    block_hash_called: bool = false,
    block_hash_number: U256 = @as(U256, 0),

    fn host(self: *RecordingHost) Host {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable = Host.VTable{
        .sload = @ptrCast(&sloadFn),
        .sstore = @ptrCast(&sstoreFn),
        .balance = @ptrCast(&balanceFn),
        .code = @ptrCast(&codeFn),
        .codeSize = @ptrCast(&codeSizeFn),
        .codeHash = @ptrCast(&codeHashFn),
        .blockHash = @ptrCast(&blockHashFn),
    };

    fn sloadFn(self: *RecordingHost, _: [20]u8, _: U256) U256 {
        return self.sload_return;
    }

    fn sstoreFn(self: *RecordingHost, addr: [20]u8, key: U256, val: U256) void {
        self.sstore_called = true;
        self.sstore_addr = addr;
        self.sstore_key = key;
        self.sstore_val = val;
    }

    fn balanceFn(self: *RecordingHost, addr: [20]u8) U256 {
        self.balance_called = true;
        self.balance_addr = addr;
        return self.balance_return;
    }

    fn codeFn(self: *RecordingHost, _: [20]u8) []const u8 {
        self.code_called = true;
        return self.code_return;
    }

    fn codeSizeFn(self: *RecordingHost, _: [20]u8) usize {
        self.code_size_called = true;
        return self.code_size_return;
    }

    fn codeHashFn(self: *RecordingHost, _: [20]u8) U256 {
        self.code_hash_called = true;
        return self.code_hash_return;
    }

    fn blockHashFn(self: *RecordingHost, number: U256) U256 {
        self.block_hash_called = true;
        self.block_hash_number = number;
        return self.block_hash_return;
    }
};

// Helpers

fn defaultBlockEnv() context.BlockEnv {
    return context.BlockEnv.default();
}

fn defaultTxEnv() context.TxEnv {
    return context.TxEnv.default();
}

fn makeInterpreter(code: []const u8, input: InputsImpl) Interpreter {
    return Interpreter.new(
        Memory.new(),
        ExtBytecode.new(bytecode_mod.Bytecode.newLegacy(code)),
        input,
        false,
        primitives.SpecId.prague,
        std.math.maxInt(u64),
    );
}

fn defaultInput() InputsImpl {
    return .{
        .caller = [_]u8{0} ** 20,
        .target = [_]u8{0} ** 20,
        .value = @as(U256, 0),
        .data = @constCast(@as([]const u8, &.{})),
        .gas_limit = std.math.maxInt(u64),
        .scheme = .call,
        .is_static = false,
        .depth = 0,
    };
}

// --- SSTORE: host receives correct address, key, value ---

test "execute: SSTORE calls host with target address, key, value" {
    // PUSH1 0x42, PUSH1 0x01, SSTORE, STOP
    const code = [_]u8{
        bytecode_mod.PUSH1, 0x42, // value
        bytecode_mod.PUSH1,  0x01, // key
        bytecode_mod.SSTORE, bytecode_mod.STOP,
    };
    var input = defaultInput();
    const target = [_]u8{0} ** 19 ++ [_]u8{0xAA};
    input.target = target;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, input);
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.sstore_called);
    try expect(std.mem.eql(u8, &rh.sstore_addr, &target));
    try expectEqual(@as(U256, 0x01), rh.sstore_key);
    try expectEqual(@as(U256, 0x42), rh.sstore_val);
}

// --- SLOAD: host return value lands on stack ---

test "execute: SLOAD reads from host and pushes result" {
    // PUSH1 0x07, SLOAD, PUSH1 0x00, SSTORE, STOP
    // Load slot 7, store the result into slot 0.
    const code = [_]u8{
        bytecode_mod.PUSH1, 0x07,
        bytecode_mod.SLOAD, bytecode_mod.PUSH1,
        0x00,               bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var rh = RecordingHost{ .sload_return = @as(U256, 0xBEEF) };
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.sstore_called);
    // SSTORE was called with key=0, val=0xBEEF (the value returned by SLOAD)
    try expectEqual(@as(U256, 0x00), rh.sstore_key);
    try expectEqual(@as(U256, 0xBEEF), rh.sstore_val);
}

// --- COINBASE reads from block_env.beneficiary ---

test "execute: COINBASE pushes block_env.beneficiary" {
    // COINBASE, PUSH1 0x00, SSTORE, STOP
    const code = [_]u8{
        bytecode_mod.COINBASE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    const coinbase = [_]u8{0} ** 19 ++ [_]u8{0x42};
    block_env.beneficiary = coinbase;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    // COINBASE should produce address in the low 20 bytes of U256
    try expectEqual(addrToU256(coinbase), rh.sstore_val);
}

// --- TIMESTAMP reads from block_env.timestamp ---

test "execute: TIMESTAMP pushes block_env.timestamp" {
    const code = [_]u8{
        bytecode_mod.TIMESTAMP,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    block_env.timestamp = @as(U256, 1700000000);

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 1700000000), rh.sstore_val);
}

// --- NUMBER reads from block_env.number ---

test "execute: NUMBER pushes block_env.number" {
    const code = [_]u8{
        bytecode_mod.NUMBER,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    block_env.number = @as(U256, 12345678);

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 12345678), rh.sstore_val);
}

// --- DIFFICULTY/PREVRANDAO reads from block_env.prevrandao ---

test "execute: DIFFICULTY pushes block_env.prevrandao" {
    const code = [_]u8{
        bytecode_mod.DIFFICULTY,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    var prevrandao: [32]u8 = [_]u8{0} ** 32;
    prevrandao[31] = 0xFF;
    prevrandao[30] = 0xAB;
    block_env.prevrandao = prevrandao;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(u256FromBeBytes(prevrandao), rh.sstore_val);
}

test "execute: DIFFICULTY pushes zero when prevrandao is null" {
    const code = [_]u8{
        bytecode_mod.DIFFICULTY,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    block_env.prevrandao = null;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 0), rh.sstore_val);
}

// --- GASLIMIT reads from block_env.gas_limit ---

test "execute: GASLIMIT pushes block_env.gas_limit" {
    const code = [_]u8{
        bytecode_mod.GASLIMIT,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    block_env.gas_limit = 30_000_000;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 30_000_000), rh.sstore_val);
}

// --- BASEFEE reads from block_env.basefee ---

test "execute: BASEFEE pushes block_env.basefee" {
    const code = [_]u8{
        bytecode_mod.BASEFEE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var block_env = defaultBlockEnv();
    block_env.basefee = 7;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(block_env, defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 7), rh.sstore_val);
}

// --- GASPRICE reads from tx_env.gas_price ---

test "execute: GASPRICE pushes tx_env.gas_price" {
    const code = [_]u8{
        bytecode_mod.GASPRICE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var tx_env = defaultTxEnv();
    tx_env.gas_price = 20_000_000_000; // 20 gwei

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), tx_env, rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 20_000_000_000), rh.sstore_val);
}

// --- ORIGIN reads from tx_env.caller ---

test "execute: ORIGIN pushes tx_env.caller" {
    const code = [_]u8{
        bytecode_mod.ORIGIN,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var tx_env = defaultTxEnv();
    const origin = [_]u8{0} ** 19 ++ [_]u8{0xBB};
    tx_env.caller = origin;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), tx_env, rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(addrToU256(origin), rh.sstore_val);
}

// --- CHAINID reads from tx_env.chain_id ---

test "execute: CHAINID pushes tx_env.chain_id" {
    const code = [_]u8{
        bytecode_mod.CHAINID,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var tx_env = defaultTxEnv();
    tx_env.chain_id = 137; // Polygon

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), tx_env, rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 137), rh.sstore_val);
}

test "execute: CHAINID defaults to 1 when chain_id is null" {
    const code = [_]u8{
        bytecode_mod.CHAINID,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var tx_env = defaultTxEnv();
    tx_env.chain_id = null;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), tx_env, rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 1), rh.sstore_val);
}

// --- BALANCE dispatches to host ---

test "execute: BALANCE calls host.balance with address from stack" {
    // PUSH20 <addr>, BALANCE, PUSH1 0x00, SSTORE, STOP
    const addr = [_]u8{0} ** 19 ++ [_]u8{0xCC};
    const code = [_]u8{bytecode_mod.PUSH20} ++ ([_]u8{0} ** 19 ++ [_]u8{0xCC}) ++ [_]u8{
        bytecode_mod.BALANCE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var rh = RecordingHost{ .balance_return = @as(U256, 1_000_000) };
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.balance_called);
    try expect(std.mem.eql(u8, &rh.balance_addr, &addr));
    try expectEqual(@as(U256, 1_000_000), rh.sstore_val);
}

// --- SELFBALANCE dispatches to host with self address ---

test "execute: SELFBALANCE calls host.balance with target address" {
    const code = [_]u8{
        bytecode_mod.SELFBALANCE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var input = defaultInput();
    const target = [_]u8{0} ** 19 ++ [_]u8{0xDD};
    input.target = target;

    var rh = RecordingHost{ .balance_return = @as(U256, 5_000_000) };
    var interp = makeInterpreter(&code, input);
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.balance_called);
    try expect(std.mem.eql(u8, &rh.balance_addr, &target));
    try expectEqual(@as(U256, 5_000_000), rh.sstore_val);
}

// --- EXTCODESIZE dispatches to host ---

test "execute: EXTCODESIZE calls host.codeSize" {
    const code = [_]u8{bytecode_mod.PUSH20} ++ ([_]u8{0} ** 19 ++ [_]u8{0xEE}) ++ [_]u8{
        bytecode_mod.EXTCODESIZE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var rh = RecordingHost{ .code_size_return = 256 };
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.code_size_called);
    try expectEqual(@as(U256, 256), rh.sstore_val);
}

// --- EXTCODEHASH dispatches to host ---

test "execute: EXTCODEHASH calls host.codeHash" {
    const code = [_]u8{bytecode_mod.PUSH20} ++ ([_]u8{0} ** 19 ++ [_]u8{0xFF}) ++ [_]u8{
        bytecode_mod.EXTCODEHASH,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    const fake_hash = @as(U256, 0xDEADCAFE);
    var rh = RecordingHost{ .code_hash_return = fake_hash };
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.code_hash_called);
    try expectEqual(fake_hash, rh.sstore_val);
}

// --- BLOCKHASH dispatches to host ---

test "execute: BLOCKHASH calls host.blockHash with number from stack" {
    const code = [_]u8{
        bytecode_mod.PUSH1,     0x05,
        bytecode_mod.BLOCKHASH, bytecode_mod.PUSH1,
        0x00,                   bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    const fake_hash = @as(U256, 0xABCD1234);
    var rh = RecordingHost{ .block_hash_return = fake_hash };
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expect(rh.block_hash_called);
    try expectEqual(@as(U256, 0x05), rh.block_hash_number);
    try expectEqual(fake_hash, rh.sstore_val);
}

// --- ADDRESS reads from input.target ---

test "execute: ADDRESS pushes input.target" {
    const code = [_]u8{
        bytecode_mod.ADDRESS,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var input = defaultInput();
    const target = [_]u8{0} ** 19 ++ [_]u8{0x77};
    input.target = target;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, input);
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(addrToU256(target), rh.sstore_val);
}

// --- CALLER reads from input.caller ---

test "execute: CALLER pushes input.caller" {
    const code = [_]u8{
        bytecode_mod.CALLER,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var input = defaultInput();
    const caller = [_]u8{0} ** 19 ++ [_]u8{0x88};
    input.caller = caller;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, input);
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(addrToU256(caller), rh.sstore_val);
}

// --- CALLVALUE reads from input.value ---

test "execute: CALLVALUE pushes input.value" {
    const code = [_]u8{
        bytecode_mod.CALLVALUE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var input = defaultInput();
    input.value = @as(U256, 1_000_000_000);

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, input);
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
    try expectEqual(@as(U256, 1_000_000_000), rh.sstore_val);
}

// --- Empty bytecode produces implicit STOP ---

test "execute: empty bytecode returns stop" {
    const code = [_]u8{};
    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, defaultInput());
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);
}

// --- CALLDATASIZE and CALLDATALOAD read from input.data ---

test "execute: CALLDATASIZE and CALLDATALOAD read from input.data" {
    // CALLDATASIZE, PUSH1 0x00, SSTORE  (store calldata size at slot 0)
    // PUSH1 0x00, CALLDATALOAD, PUSH1 0x01, SSTORE  (store calldataload(0) at slot 1)
    // STOP
    const code = [_]u8{
        bytecode_mod.CALLDATASIZE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.SSTORE,
        bytecode_mod.PUSH1,
        0x00,
        bytecode_mod.CALLDATALOAD,
        bytecode_mod.PUSH1,
        0x01,
        bytecode_mod.SSTORE,
        bytecode_mod.STOP,
    };

    var input = defaultInput();
    // 4 bytes of calldata: 0xAABBCCDD
    var calldata = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    input.data = &calldata;

    var rh = RecordingHost{};
    var interp = makeInterpreter(&code, input);
    defer interp.deinit();

    const result = interp.execute(defaultBlockEnv(), defaultTxEnv(), rh.host());
    try expectEqual(InstructionResult.stop, result);

    // Last SSTORE was slot 1 with calldataload(0).
    // calldataload(0) = 0xAABBCCDD padded to 32 bytes on the right
    var expected_cdl: [32]u8 = [_]u8{0} ** 32;
    expected_cdl[0] = 0xAA;
    expected_cdl[1] = 0xBB;
    expected_cdl[2] = 0xCC;
    expected_cdl[3] = 0xDD;
    try expectEqual(u256FromBeBytes(expected_cdl), rh.sstore_val);
    // The key should be 1
    try expectEqual(@as(U256, 0x01), rh.sstore_key);
}
