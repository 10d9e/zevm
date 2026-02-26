const std = @import("std");
const primitives = @import("primitives");
const context = @import("context");
const interpreter = @import("interpreter");
const precompile = @import("precompile");
const database = @import("database");

// Import handler modules
const mainnet_builder = @import("mainnet_builder.zig");
const execution = @import("execution.zig");
const validation = @import("validation.zig");

// Re-export main components
pub const MainnetEvm = mainnet_builder.MainnetEvm;
pub const MainnetContext = mainnet_builder.MainnetContext;
pub const MainBuilder = mainnet_builder.MainBuilder;
pub const MainContext = mainnet_builder.MainContext;
pub const MainnetHandler = mainnet_builder.MainnetHandler;
pub const ExecuteEvm = mainnet_builder.ExecuteEvm;
pub const ExecuteCommitEvm = mainnet_builder.ExecuteCommitEvm;

// Re-export execution components
pub const Execution = execution.Execution;
pub const ExecutionLoop = execution.ExecutionLoop;
pub const GasCalculation = execution.GasCalculation;
pub const StateManagement = execution.StateManagement;

// Re-export validation components
pub const Validation = validation.Validation;
pub const InitialAndFloorGas = validation.InitialAndFloorGas;
pub const ValidationError = validation.ValidationError;

/// EVM execution result
pub const ExecutionResult = struct {
    /// Execution status
    status: ExecutionStatus,
    /// Gas used
    gas_used: u64,
    /// Logs emitted during execution
    logs: std.ArrayList(Log),
    /// Return data
    return_data: []const u8,
    /// Halt reason if execution halted
    halt_reason: ?HaltReason,

    /// Create new execution result
    pub fn new(status: ExecutionStatus, gas_used: u64) ExecutionResult {
        return ExecutionResult{
            .status = status,
            .gas_used = gas_used,
            .logs = std.ArrayList(Log){ .items = &[_]Log{}, .capacity = 0 },
            .return_data = &[_]u8{},
            .halt_reason = null,
        };
    }

    /// Deinitialize execution result
    pub fn deinit(self: *ExecutionResult) void {
        // ArrayList deinit requires allocator in Zig 0.15.1
        // For now, just clear the items
        self.logs.items = &[_]Log{};
    }
};

/// Execution status
pub const ExecutionStatus = enum {
    /// Execution succeeded
    Success,
    /// Execution reverted
    Revert,
    /// Execution halted
    Halt,
    /// Execution failed
    Fail,
};

/// Halt reason
pub const HaltReason = enum {
    /// Out of gas
    OutOfGas,
    /// Invalid opcode
    InvalidOpcode,
    /// Stack overflow
    StackOverflow,
    /// Stack underflow
    StackUnderflow,
    /// Invalid jump destination
    InvalidJump,
    /// Invalid memory access
    InvalidMemoryAccess,
    /// Call depth exceeded
    CallDepthExceeded,
    /// Precompile error
    PrecompileError,
    /// Other error
    Other,
};

/// Log entry
pub const Log = struct {
    /// Address that emitted the log
    address: primitives.Address,
    /// Topics
    topics: std.ArrayList(primitives.Hash),
    /// Data
    data: []const u8,

    /// Create new log entry
    pub fn new(address: primitives.Address, topics: std.ArrayList(primitives.Hash), data: []const u8) Log {
        return Log{
            .address = address,
            .topics = topics,
            .data = data,
        };
    }

    /// Deinitialize log entry
    pub fn deinit(self: *Log) void {
        self.topics.deinit();
    }
};

/// Frame result
pub const FrameResult = struct {
    /// Execution result
    result: ExecutionResult,
    /// Gas remaining
    gas_remaining: u64,
    /// Memory
    memory: interpreter.Memory,
    /// Stack
    stack: interpreter.Stack,

    /// Create new frame result
    pub fn new(result: ExecutionResult, gas_remaining: u64) FrameResult {
        return FrameResult{
            .result = result,
            .gas_remaining = gas_remaining,
            .memory = interpreter.Memory.new(),
            .stack = interpreter.Stack.new(),
        };
    }

    /// Deinitialize frame result
    pub fn deinit(self: *FrameResult) void {
        self.result.deinit();
        self.memory.deinit();
    }
};

/// Frame data for call/create operations
pub const FrameData = struct {
    /// Caller address
    caller: primitives.Address,
    /// Target address
    target: primitives.Address,
    /// Value being transferred
    value: primitives.U256,
    /// Input data
    input: []const u8,
    /// Gas limit
    gas_limit: u64,
    /// Is static call
    is_static: bool,
    /// Call scheme
    scheme: interpreter.CallScheme,

    /// Create new frame data
    pub fn new(
        caller: primitives.Address,
        target: primitives.Address,
        value: primitives.U256,
        input: []const u8,
        gas_limit: u64,
        is_static: bool,
        scheme: interpreter.CallScheme,
    ) FrameData {
        return FrameData{
            .caller = caller,
            .target = target,
            .value = value,
            .input = input,
            .gas_limit = gas_limit,
            .is_static = is_static,
            .scheme = scheme,
        };
    }
};

/// EVM for execution
pub const Evm = struct {
    /// Context
    ctx: *context.Context,
    /// Inspector (optional)
    inspector: ?*Inspector,
    /// Instructions
    instructions: *Instructions,
    /// Precompiles
    precompiles: *Precompiles,
    /// Frame stack
    frame_stack: *FrameStack,

    /// Create new EVM
    pub fn init(
        ctx: *context.Context,
        inspector: ?*Inspector,
        instructions: *Instructions,
        precompiles: *Precompiles,
        frame_stack: *FrameStack,
    ) Evm {
        return Evm{
            .ctx = ctx,
            .inspector = inspector,
            .instructions = instructions,
            .precompiles = precompiles,
            .frame_stack = frame_stack,
        };
    }

    /// Get context
    pub fn getContext(self: *Evm) *context.Context {
        return self.ctx;
    }

    /// Create frame
    pub fn createFrame(self: *Evm, frame_data: FrameData) !Frame {
        return Frame.init(frame_data, self.instructions, self.precompiles);
    }

    /// Execute frame
    pub fn executeFrame(self: *Evm, frame: *Frame) !FrameResult {
        return frame.execute(self.ctx);
    }
};

/// Frame for execution
pub const Frame = struct {
    /// Frame data
    data: FrameData,
    /// Instructions
    instructions: *Instructions,
    /// Precompiles
    precompiles: *Precompiles,
    /// Interpreter
    interpreter: interpreter.Interpreter,

    /// Create new frame
    pub fn init(data: FrameData, instructions: *Instructions, precompiles: *Precompiles) Frame {
        // Extract spec from instructions provider (configured for this hardfork)
        const spec = instructions.spec;

        return Frame{
            .data = data,
            .instructions = instructions,
            .precompiles = precompiles,
            .interpreter = interpreter.Interpreter.new(
                interpreter.Memory.new(),
                interpreter.ExtBytecode.new(bytecode.Bytecode.new()),
                interpreter.InputsImpl.new(
                    data.caller,
                    data.target,
                    data.value,
                    @constCast(data.input),
                    data.gas_limit,
                    data.scheme,
                    data.is_static,
                    0,
                ),
                data.is_static,
                spec, // Use spec from instructions instead of hardcoding
                data.gas_limit,
            ),
        };
    }

    /// Execute frame with host access for full EVM semantics.
    pub fn execute(self: *Frame, ctx: *context.Context) !FrameResult {
        const schedule = interpreter.protocol_schedule.ProtocolSchedule.forSpec(
            self.interpreter.runtime_flags.spec_id,
        );

        // Build a Host that delegates to the context, and set the sub-call runner.
        var host = interpreter.Host{
            .ctx = ctx,
            .run_sub_call = interpreter.protocol_schedule.runSubCallDefault,
        };

        const result = self.interpreter.runWithHost(
            &schedule.instructions,
            &host,
        );

        const gas_used = self.interpreter.gas.getSpent();
        const status: ExecutionStatus = switch (result) {
            .stop, .@"return", .selfdestruct => .Success,
            .revert => .Revert,
            else => .Halt,
        };

        return FrameResult.new(
            ExecutionResult.new(status, gas_used),
            self.interpreter.gas.remaining,
        );
    }
};

/// Instructions provider for EVM execution
pub const Instructions = struct {
    /// Instruction table for the configured spec
    table: interpreter.protocol_schedule.InstructionTable,
    /// Hardfork specification
    spec: primitives.SpecId,

    /// Create instructions provider for a specific hardfork spec
    pub fn new(spec: primitives.SpecId) Instructions {
        return Instructions{
            .table = interpreter.protocol_schedule.makeInstructionTable(spec),
            .spec = spec,
        };
    }

    /// Get instruction entry for an opcode
    pub fn getInstruction(self: *const Instructions, opcode: u8) interpreter.protocol_schedule.InstructionEntry {
        return self.table[opcode];
    }

    /// Get static gas cost for an opcode
    pub fn getStaticGas(self: *const Instructions, opcode: u8) u64 {
        return self.table[opcode].static_gas;
    }
};

/// Precompiles implementation
pub const Precompiles = struct {
    /// Precompiles collection
    precompiles: precompile.Precompiles,
    /// Hardfork specification
    spec: primitives.SpecId,

    /// Create precompiles provider for a specific hardfork spec
    pub fn new(spec: primitives.SpecId) Precompiles {
        // Map full SpecId to PrecompileSpecId (groups similar specs)
        const precompile_spec = precompile.PrecompileSpecId.fromSpec(spec);
        return Precompiles{
            .precompiles = precompile.Precompiles.forSpec(precompile_spec),
            .spec = spec,
        };
    }

    /// Get precompile by address
    pub fn get(self: *Precompiles, address: primitives.Address) ?precompile.Precompile {
        return self.precompiles.get(address);
    }
};

/// Frame stack
pub const FrameStack = struct {
    /// Stack of frames
    frames: std.ArrayList(Frame),

    /// Create new frame stack
    pub fn new() FrameStack {
        return FrameStack{
            .frames = std.ArrayList(Frame){ .items = &[_]Frame{}, .capacity = 0 },
        };
    }

    /// Create new frame stack with preallocated capacity
    pub fn newPrealloc(capacity: usize) FrameStack {
        var stack = FrameStack.new();
        stack.frames.ensureTotalCapacity(std.heap.c_allocator, capacity) catch {};
        return stack;
    }

    /// Push frame
    pub fn push(self: *FrameStack, frame: Frame) !void {
        try self.frames.append(std.heap.c_allocator, frame);
    }

    /// Pop frame
    pub fn pop(self: *FrameStack) ?Frame {
        if (self.frames.items.len == 0) {
            return null;
        }
        return self.frames.pop();
    }

    /// Get frame count
    pub fn len(self: *FrameStack) usize {
        return self.frames.items.len;
    }

    /// Deinitialize frame stack
    pub fn deinit(self: *FrameStack) void {
        // ArrayList deinit requires allocator in Zig 0.15.1
        // For now, just clear the items
        self.frames.items = &[_]Frame{};
    }
};

/// Inspector for execution monitoring
pub const Inspector = struct {
    /// Inspect before execution
    pub fn inspectBefore(self: *Inspector, evm: *Evm) !void {
        _ = self;
        _ = evm;
    }

    /// Inspect after execution
    pub fn inspectAfter(self: *Inspector, evm: *Evm, result: *FrameResult) !void {
        _ = self;
        _ = evm;
        _ = result;
    }
};

// Import required modules
const bytecode = @import("bytecode");

// Placeholder for testing
pub const testing = struct {
    pub fn testHandler() !void {
        std.log.info("Testing handler module...", .{});

        // Test basic handler components
        try testExecutionResult();
        try testFrameData();
        try testFrameStack();

        // Test mainnet builder
        try mainnet_builder.testing.testMainnetBuilder();
        try mainnet_builder.testing.testMainnetHandler();

        // Test execution
        try execution.testing.testExecution();

        std.log.info("Handler module test passed!", .{});
    }

    fn testExecutionResult() !void {
        var result = ExecutionResult.new(.Success, 1000);
        defer result.deinit();

        std.debug.assert(result.status == .Success);
        std.debug.assert(result.gas_used == 1000);
        std.debug.assert(result.logs.items.len == 0);
    }

    fn testFrameData() !void {
        const caller = [_]u8{0x01} ** 20;
        const target = [_]u8{0x02} ** 20;
        const value = @as(primitives.U256, 100);
        const input = "Hello, World!";
        const gas_limit: u64 = 10000;

        const frame_data = FrameData.new(
            caller,
            target,
            value,
            input,
            gas_limit,
            false,
            .call,
        );

        std.debug.assert(std.mem.eql(u8, &frame_data.caller, &caller));
        std.debug.assert(std.mem.eql(u8, &frame_data.target, &target));
        std.debug.assert(frame_data.value == value);
        std.debug.assert(std.mem.eql(u8, frame_data.input, input));
        std.debug.assert(frame_data.gas_limit == gas_limit);
        std.debug.assert(frame_data.is_static == false);
        std.debug.assert(frame_data.scheme == .call);
    }

    fn testFrameStack() !void {
        var stack = FrameStack.new();
        defer stack.deinit();

        std.debug.assert(stack.len() == 0);

        const frame_data = FrameData.new(
            [_]u8{0x01} ** 20,
            [_]u8{0x02} ** 20,
            @as(primitives.U256, 100),
            "test",
            1000,
            false,
            .call,
        );

        var instructions = Instructions.new(primitives.SpecId.prague);
        var precompiles = Precompiles.new(primitives.SpecId.prague);
        const frame = Frame.init(frame_data, &instructions, &precompiles);
        try stack.push(frame);

        std.debug.assert(stack.len() == 1);

        const popped = stack.pop();
        std.debug.assert(popped != null);
        std.debug.assert(stack.len() == 0);
    }
};

// Pull in tests from submodules
test {
    _ = @import("validation.zig");
    _ = @import("validation_tests.zig");
}
