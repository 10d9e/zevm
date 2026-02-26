const Interpreter = @import("interpreter.zig").Interpreter;
const host_module = @import("host.zig");

pub const Host = host_module.Host;

/// Minimal context passed to every opcode handler.
/// Handlers access stack, gas, memory, and PC through interpreter.
/// Handlers that need block/tx/state access use the optional host pointer.
pub const InstructionContext = struct {
    interpreter: *Interpreter,
    /// Optional host providing block/tx environment and account state.
    /// Null in hostless execution (e.g. benchmarks, pure arithmetic tests).
    /// Handlers that require a host halt with .invalid_opcode when host is null.
    host: ?*Host = null,
};

/// Function pointer type for all opcode handlers.
pub const InstructionFn = *const fn (ctx: *InstructionContext) void;
