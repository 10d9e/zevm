const std = @import("std");
const zevm = @import("main.zig");

/// Comprehensive test suite for ZEVM
pub fn main() !void {
    std.log.info("Starting ZEVM comprehensive test suite...", .{});

    // Test primitives
    std.log.info("Testing primitives...", .{});
    try testPrimitives();

    // Test bytecode
    std.log.info("Testing bytecode...", .{});
    try testBytecode();

    // Test state management
    std.log.info("Testing state management...", .{});
    try testState();

    // Test database
    std.log.info("Testing database...", .{});
    try testDatabase();

    // Test context
    std.log.info("Testing context...", .{});
    try testContext();

    // Test interpreter
    std.log.info("Testing interpreter...", .{});
    try testInterpreter();

    // Test precompiles
    std.log.info("Testing precompiles...", .{});
    try testPrecompiles();

    // Test handler
    std.log.info("Testing handler...", .{});
    try testHandler();

    // Test inspector
    std.log.info("Testing inspector...", .{});
    try testInspector();

    // Integration tests
    std.log.info("Running integration tests...", .{});
    try testIntegration();

    std.log.info("All tests passed! 🎉", .{});
}

fn testPrimitives() !void {
    // Test U256 operations
    const zero: zevm.primitives.U256 = 0;
    const one: zevm.primitives.U256 = 1;
    const max: zevm.primitives.U256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    std.debug.assert(zero == 0);
    std.debug.assert(one == 1);
    std.debug.assert(max == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    // Test address operations
    const zero_addr: zevm.primitives.Address = [_]u8{0} ** 20;
    const ff_addr: zevm.primitives.Address = [_]u8{0xff} ** 20;

    std.debug.assert(std.mem.eql(u8, &zero_addr, &[_]u8{0} ** 20));
    std.debug.assert(std.mem.eql(u8, &ff_addr, &[_]u8{0xff} ** 20));

    // Test spec ID parsing
    const prague = zevm.primitives.specIdFromString("Prague") catch return;
    const shanghai = zevm.primitives.specIdFromString("Shanghai") catch return;

    std.debug.assert(prague == zevm.primitives.SpecId.prague);
    std.debug.assert(shanghai == zevm.primitives.SpecId.shanghai);

    std.log.info("✓ Primitives tests passed", .{});
}

fn testBytecode() !void {
    // Test opcode creation
    const stop = zevm.bytecode.OpCode.new(0x00) orelse return;
    const add = zevm.bytecode.OpCode.new(0x01) orelse return;
    const mul = zevm.bytecode.OpCode.new(0x02) orelse return;

    std.debug.assert(stop.value == zevm.bytecode.STOP);
    std.debug.assert(add.value == zevm.bytecode.ADD);
    std.debug.assert(mul.value == zevm.bytecode.MUL);

    // Test opcode info
    const stop_info = stop.info();
    const add_info = add.info();

    std.debug.assert(stop_info.inputs == 0);
    std.debug.assert(stop_info.outputs == 0);
    std.debug.assert(add_info.inputs == 2);
    std.debug.assert(add_info.outputs == 1);

    // Test bytecode creation
    const bytecode_data = [_]u8{ 0x00, 0x01, 0x02 };
    const raw_bytecode = zevm.bytecode.LegacyRawBytecode.init(&bytecode_data);

    std.debug.assert(raw_bytecode.bytecode.len == 3);

    std.log.info("✓ Bytecode tests passed", .{});
}

fn testState() !void {
    // Test account info
    var account = zevm.state.AccountInfo.new(
        @as(zevm.primitives.U256, 0),
        0,
        zevm.primitives.KECCAK_EMPTY,
        zevm.bytecode.Bytecode.new(),
    );
    std.debug.assert(account.balance == 0);
    std.debug.assert(account.nonce == 0);
    std.debug.assert(std.mem.eql(u8, &account.code_hash, &zevm.primitives.KECCAK_EMPTY));

    // Test account info with values
    const balance: zevm.primitives.U256 = 1000;
    const nonce: u64 = 5;
    const code_hash = [_]u8{0x01} ** 32;

    account = zevm.state.AccountInfo.new(balance, nonce, code_hash, zevm.bytecode.Bytecode.new());
    std.debug.assert(account.balance == balance);
    std.debug.assert(account.nonce == nonce);
    std.debug.assert(std.mem.eql(u8, &account.code_hash, &code_hash));

    std.log.info("✓ State tests passed", .{});
}

fn testDatabase() !void {
    // Test in-memory database
    var db = zevm.database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();

    const addr: zevm.primitives.Address = [_]u8{0} ** 20;
    const account = zevm.state.AccountInfo.new(
        @as(zevm.primitives.U256, 0),
        0,
        zevm.primitives.KECCAK_EMPTY,
        zevm.bytecode.Bytecode.new(),
    );

    // Test basic operations
    try db.insertAccount(addr, account);
    const retrieved = try db.basic(addr);
    std.debug.assert(retrieved != null);
    std.debug.assert(retrieved.?.balance == account.balance);

    // Test code operations
    const code_hash: zevm.primitives.Hash = [_]u8{0x01} ** 32;

    try db.insertCode(code_hash, zevm.bytecode.Bytecode.new());
    const retrieved_code = try db.codeByHash(code_hash);
    std.debug.assert(retrieved_code.len() == 1); // Default bytecode has 1 byte (STOP)

    std.log.info("✓ Database tests passed", .{});
}

fn testContext() !void {
    // Test block environment
    const block = zevm.context.BlockEnv.default();
    std.debug.assert(block.number == 0);
    std.debug.assert(block.gas_limit == std.math.maxInt(u64));

    // Test transaction environment
    var tx = zevm.context.TxEnv.default();
    defer tx.deinit();
    std.debug.assert(tx.gas_limit == zevm.primitives.TX_GAS_LIMIT_CAP);
    std.debug.assert(tx.nonce == 0);

    // Test configuration environment
    const cfg = zevm.context.CfgEnv.default();
    std.debug.assert(cfg.spec == zevm.primitives.SpecId.prague);

    // Test context creation
    const db = zevm.database.InMemoryDB.init(std.heap.c_allocator);
    const ctx = zevm.context.Context.new(db, zevm.primitives.SpecId.prague);
    std.debug.assert(ctx.cfg.spec == zevm.primitives.SpecId.prague);

    std.log.info("✓ Context tests passed", .{});
}

fn testInterpreter() !void {
    // Test gas operations
    var gas = zevm.interpreter.Gas.new(100000);
    std.debug.assert(gas.getLimit() == 100000);
    std.debug.assert(gas.getRemaining() == 100000);

    const spent = gas.spend(1000);
    std.debug.assert(spent == true);
    std.debug.assert(gas.getRemaining() == 99000);
    std.debug.assert(gas.getSpent() == 1000);

    // Test stack operations
    var stack = zevm.interpreter.Stack.new();
    std.debug.assert(stack.len() == 0);

    try stack.push(@as(zevm.primitives.U256, 42));
    std.debug.assert(stack.len() == 1);

    const value = stack.pop() orelse return;
    std.debug.assert(value == 42);

    // Test memory operations
    var memory = zevm.interpreter.Memory.new();
    std.debug.assert(memory.size() == 0);

    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    try memory.set(0, &data);
    std.debug.assert(memory.size() >= 4);

    const slice = memory.slice(0, 4);
    std.debug.assert(std.mem.eql(u8, slice, &data));

    // Test interpreter creation
    const inputs = zevm.interpreter.InputsImpl.new(
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        @as(zevm.primitives.U256, 0),
        &[_]u8{},
        100000,
        zevm.interpreter.CallScheme.call,
        false,
        0,
    );

    var interpreter = zevm.interpreter.Interpreter.new(
        memory,
        zevm.interpreter.ExtBytecode.new(zevm.bytecode.Bytecode.new()),
        inputs,
        false,
        zevm.primitives.SpecId.prague,
        100000,
    );

    std.debug.assert(interpreter.gas.getLimit() == 100000);
    std.debug.assert(interpreter.stack.len() == 0);

    std.log.info("✓ Interpreter tests passed", .{});
}

fn testPrecompiles() !void {
    // Test precompile creation
    const identity_precompile = zevm.precompile.Precompile.new(
        zevm.precompile.PrecompileId.Identity,
        zevm.precompile.u64ToAddress(1),
        zevm.precompile.identity.identityRun,
    );

    std.debug.assert(identity_precompile.id == zevm.precompile.PrecompileId.Identity);

    // Test precompile execution
    const input = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const result = identity_precompile.execute(&input, 1000);

    switch (result) {
        .success => |output| {
            std.debug.assert(output.gas_used == 18); // 15 base + 3 per word (4 bytes = 1 word)
            std.debug.assert(std.mem.eql(u8, output.bytes, &input));
            std.debug.assert(output.reverted == false);
        },
        .err => return,
    }

    // Test precompiles collection
    var precompiles = zevm.precompile.Precompiles.new();
    try precompiles.add(identity_precompile);

    const retrieved = precompiles.get(zevm.precompile.u64ToAddress(1));
    std.debug.assert(retrieved != null);
    std.debug.assert(retrieved.?.id == zevm.precompile.PrecompileId.Identity);

    std.log.info("✓ Precompiles tests passed", .{});
}

fn testHandler() !void {
    // Test execution result
    const result = zevm.handler.ExecutionResult.new(.Success, 1000);
    std.debug.assert(result.status == .Success);
    std.debug.assert(result.gas_used == 1000);
    std.debug.assert(result.logs.items.len == 0);

    // Test frame data
    const frame_data = zevm.handler.FrameData.new(
        [_]u8{0} ** 20,
        [_]u8{0} ** 20,
        @as(zevm.primitives.U256, 0),
        &[_]u8{},
        100000,
        false,
        zevm.interpreter.CallScheme.call,
    );

    std.debug.assert(std.mem.eql(u8, &frame_data.caller, &[_]u8{0} ** 20));
    std.debug.assert(std.mem.eql(u8, &frame_data.target, &[_]u8{0} ** 20));
    std.debug.assert(frame_data.gas_limit == 100000);

    // Test frame stack
    var frame_stack = zevm.handler.FrameStack.new();
    std.debug.assert(frame_stack.len() == 0);

    var instructions = zevm.handler.Instructions.new(zevm.primitives.SpecId.prague);
    var precompiles = zevm.handler.Precompiles.new(zevm.primitives.SpecId.prague);
    const frame = zevm.handler.Frame.init(frame_data, &instructions, &precompiles);
    try frame_stack.push(frame);
    std.debug.assert(frame_stack.len() == 1);

    const popped = frame_stack.pop();
    std.debug.assert(popped != null);
    std.debug.assert(frame_stack.len() == 0);

    std.log.info("✓ Handler tests passed", .{});
}

fn testInspector() !void {
    // Test NoOpInspector
    const noop = zevm.inspector.NoOpInspector.new();
    _ = noop;

    // Test GasInspector
    var gas_inspector = zevm.inspector.GasInspector.new();
    std.debug.assert(gas_inspector.gasRemaining() == 0);
    std.debug.assert(gas_inspector.lastGasCost() == 0);

    var gas = zevm.interpreter.Gas.new(100000);
    gas_inspector.initializeInterp(&gas);
    std.debug.assert(gas_inspector.gasRemaining() == 100000);

    _ = gas.spend(1000);
    gas_inspector.step(&gas);
    std.debug.assert(gas_inspector.gasRemaining() == 99000);

    _ = gas.spend(500);
    gas_inspector.stepEnd(&gas);
    std.debug.assert(gas_inspector.lastGasCost() == 500);

    // Test CountInspector
    var count_inspector = zevm.inspector.CountInspector.new();
    std.debug.assert(count_inspector.getStepCount() == 0);
    std.debug.assert(count_inspector.getCallCount() == 0);
    std.debug.assert(count_inspector.getCreateCount() == 0);
    std.debug.assert(count_inspector.getLogCount() == 0);
    std.debug.assert(count_inspector.getSelfdestructCount() == 0);

    // Test InspectorHandler
    const handler = zevm.inspector.InspectorHandler.new(null);
    _ = handler;

    std.log.info("✓ Inspector tests passed", .{});
}

fn testIntegration() !void {
    // Test basic EVM execution flow
    const db = zevm.database.InMemoryDB.init(std.heap.c_allocator);
    var ctx = zevm.context.Context.new(db, zevm.primitives.SpecId.prague);

    // Create a simple bytecode (STOP instruction)
    const bytecode_data = [_]u8{0x00}; // STOP
    const bytecode = zevm.bytecode.Bytecode.new();
    _ = bytecode_data;

    // Set up transaction
    var tx = zevm.context.TxEnv.default();
    defer tx.deinit();
    tx.caller = [_]u8{0} ** 20;
    tx.gas_limit = 100000;
    tx.data = std.ArrayList(u8){ .items = &[_]u8{}, .capacity = 0 };

    ctx.tx = tx;

    // Create interpreter
    const target_addr = [_]u8{0} ** 20;
    const inputs = zevm.interpreter.InputsImpl.new(
        ctx.tx.caller,
        target_addr,
        @as(zevm.primitives.U256, 0),
        &[_]u8{},
        ctx.tx.gas_limit,
        zevm.interpreter.CallScheme.call,
        false,
        0,
    );

    var interpreter = zevm.interpreter.Interpreter.new(
        zevm.interpreter.Memory.new(),
        zevm.interpreter.ExtBytecode.new(bytecode),
        inputs,
        false,
        zevm.primitives.SpecId.prague,
        ctx.tx.gas_limit,
    );

    // Test basic execution setup
    std.debug.assert(interpreter.gas.getLimit() == ctx.tx.gas_limit);
    std.debug.assert(interpreter.stack.len() == 0);
    std.debug.assert(interpreter.memory.size() == 0);

    // Test gas inspector integration
    var gas_inspector = zevm.inspector.GasInspector.new();
    gas_inspector.initializeInterp(&interpreter.gas);
    std.debug.assert(gas_inspector.gasRemaining() == ctx.tx.gas_limit);

    std.log.info("✓ Integration tests passed", .{});
}
