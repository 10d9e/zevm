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

/// Simple example: Execute a basic smart contract
pub fn main() !void {
    std.log.info("=== Simple Contract Execution Example ===\n", .{});

    // Create an in-memory database
    var db = database.InMemoryDB.init(std.heap.c_allocator);
    defer db.deinit();

    // Create a context with Prague specification
    var ctx = context.Context.new(db, primitives.SpecId.prague);

    // Create a simple contract that adds two numbers
    // PUSH1 0x05  (push 5 onto stack)
    // PUSH1 0x03  (push 3 onto stack)
    // ADD         (add top two stack values)
    // PUSH1 0x00  (push 0 for memory offset)
    // MSTORE      (store result in memory)
    // PUSH1 0x20  (push 32 for return data size)
    // PUSH1 0x00  (push 0 for return data offset)
    // RETURN      (return the result)
    const bytecode_data = [_]u8{
        0x60, 0x05, // PUSH1 5
        0x60, 0x03, // PUSH1 3
        0x01, // ADD
        0x60, 0x00, // PUSH1 0
        0x52, // MSTORE
        0x60, 0x20, // PUSH1 32
        0x60, 0x00, // PUSH1 0
        0xF3, // RETURN
    };

    // Create bytecode
    const bytecode_obj = bytecode.Bytecode.new();
    std.log.info("Bytecode created", .{});

    // Set up the contract account
    const contract_address: primitives.Address = [_]u8{0x01} ** 20;
    const account = state.AccountInfo.new(
        primitives.U256.ZERO, // balance
        0, // nonce
        primitives.KECCAK_EMPTY, // code hash
        bytecode_obj,
    );
    _ = bytecode_data;

    try db.insertAccount(contract_address, account);
    std.log.info("Contract deployed at address: 0x{x}", .{contract_address[0]});

    // Set up transaction environment
    var tx = context.TxEnv.default();
    defer tx.deinit();
    tx.caller = [_]u8{0x02} ** 20;
    tx.gas_limit = 100000;
    ctx.tx = tx;

    std.log.info("Transaction caller: 0x{x}", .{tx.caller[0]});
    std.log.info("Gas limit: {}", .{tx.gas_limit});

    // Create interpreter inputs
    const inputs = interpreter.InputsImpl.new(
        tx.caller,
        contract_address,
        primitives.U256.ZERO, // value
        &[_]u8{}, // input data
        tx.gas_limit,
        interpreter.CallScheme.call,
        false, // not static
        0, // depth
    );

    // Create and run interpreter
    var interp = interpreter.Interpreter.new(
        interpreter.Memory.new(),
        interpreter.ExtBytecode.new(bytecode_obj),
        inputs,
        false, // not static
        primitives.SpecId.prague,
        tx.gas_limit,
    );

    std.log.info("\nExecution started...", .{});
    std.log.info("Initial gas: {}", .{interp.gas.getLimit()});
    std.log.info("Stack size: {}", .{interp.stack.len()});

    // Note: In a real implementation, we would execute the interpreter here
    // For now, we just demonstrate the setup
    std.log.info("\nExecution setup complete!", .{});
    std.log.info("Gas remaining: {}", .{interp.gas.getRemaining()});
    std.log.info("Stack size: {}", .{interp.stack.len()});
    std.log.info("Memory size: {}", .{interp.memory.size()});

    std.log.info("\n=== Example Complete ===", .{});
}
