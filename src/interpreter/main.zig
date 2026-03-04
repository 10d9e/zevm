const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const context = @import("context");
pub const InputsImpl = @import("interpreter.zig").InputsImpl;
pub const Interpreter = @import("interpreter.zig").Interpreter;
pub const ExtBytecode = @import("interpreter.zig").ExtBytecode;
pub const PendingCallData = @import("interpreter.zig").PendingCallData;
pub const PendingCreateData = @import("interpreter.zig").PendingCreateData;
pub const PendingSubCall = @import("interpreter.zig").PendingSubCall;

// Re-export commonly used types
pub const U256 = primitives.U256;
pub const U128 = primitives.U128;
pub const U64 = primitives.U64;
pub const U32 = primitives.U32;
pub const U16 = primitives.U16;
pub const U8 = primitives.U8;
pub const Address = primitives.Address;
pub const Hash = primitives.Hash;
pub const SpecId = primitives.SpecId;
pub const Bytes = primitives.Bytes;

// Re-export interpreter components
pub const Gas = @import("gas.zig").Gas;
pub const Stack = @import("stack.zig").Stack;
pub const Memory = @import("memory.zig").Memory;
pub const InstructionResult = @import("instruction_result.zig").InstructionResult;
pub const InterpreterAction = @import("interpreter_action.zig").InterpreterAction;
pub const CallScheme = @import("interpreter_action.zig").CallScheme;
pub const InstructionContext = @import("instruction_context.zig").InstructionContext;
pub const InstructionFn = @import("instruction_context.zig").InstructionFn;
pub const InstructionEntry = @import("interpreter.zig").InstructionEntry;
pub const InstructionTable = @import("interpreter.zig").InstructionTable;
pub const host_module = @import("host.zig");
pub const Host = host_module.Host;
pub const CallInputs = host_module.CallInputs;
pub const CallResult = host_module.CallResult;
pub const CreateResult = host_module.CreateResult;
pub const CreateInputs = @import("interpreter_action.zig").CreateInputs;
pub const opcodes = @import("opcodes/main.zig");
pub const instruction_table = @import("instruction_table.zig");
pub const protocol_schedule = @import("protocol_schedule.zig");
pub const ProtocolSchedule = protocol_schedule.ProtocolSchedule;
pub const gas_costs = @import("gas_costs.zig");

// Constants
pub const STACK_LIMIT = 1024;

// Pull in tests from submodules
test {
    _ = @import("stack.zig");
    _ = @import("opcodes/arithmetic.zig");
    _ = @import("opcodes/arithmetic_tests.zig");
    _ = @import("opcodes/host_ops_tests.zig");
}

/// Main interpreter module for EVM bytecode execution
pub const testing = struct {
    pub fn testGas() !void {
        var gas = Gas.new(1000000);
        std.debug.assert(gas.getLimit() == 1000000);
        std.debug.assert(gas.getRemaining() == 1000000);
        std.debug.assert(gas.getSpent() == 0);

        _ = gas.spend(1000);
        std.debug.assert(gas.getRemaining() == 999000);
        std.debug.assert(gas.getSpent() == 1000);

        std.debug.print("Gas tests passed.\n", .{});
    }

    pub fn testMemory() !void {
        var memory = Memory.new();
        std.debug.assert(memory.size() == 0);

        const data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
        try memory.set(0, &data);
        std.debug.assert(memory.size() >= 4);

        const slice = memory.slice(0, 4);
        std.debug.assert(std.mem.eql(u8, slice, &data));

        std.debug.print("Memory tests passed.\n", .{});
    }

    pub fn testInterpreter() !void {
        const inputs = InputsImpl.new([_]u8{0} ** 20, [_]u8{0} ** 20, @as(primitives.U256, 0), &[_]u8{}, 1000000, CallScheme.call, false, 0);

        var interpreter = Interpreter.new(Memory.new(), ExtBytecode.new(bytecode.Bytecode.new()), inputs, false, primitives.SpecId.prague, 1000000);
        defer interpreter.deinit();

        std.debug.assert(interpreter.gas.getLimit() == 1000000);
        std.debug.assert(interpreter.stack.len() == 0);
        std.debug.assert(interpreter.memory.size() == 0);

        std.debug.print("Interpreter tests passed.\n", .{});
    }
};
