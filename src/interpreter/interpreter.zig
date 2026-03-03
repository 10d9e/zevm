const std = @import("std");
const primitives = @import("primitives");
const bytecode = @import("bytecode");
const context = @import("context");
const Gas = @import("gas.zig").Gas;
const Stack = @import("stack.zig").Stack;
const Memory = @import("memory.zig").Memory;
const InstructionResult = @import("instruction_result.zig").InstructionResult;
const InterpreterAction = @import("interpreter_action.zig").InterpreterAction;
const CallScheme = @import("interpreter_action.zig").CallScheme;
// Lazy imports for dispatch types — pointer-only usage prevents circular dependency issues.
const InstructionContext = @import("instruction_context.zig").InstructionContext;
const Host = @import("host.zig").Host;

/// Input data for current execution context
pub const InputsImpl = struct {
    /// Caller address
    caller: primitives.Address,
    /// Target address
    target: primitives.Address,
    /// Value
    value: primitives.U256,
    /// Data
    data: primitives.Bytes,
    /// Gas limit
    gas_limit: u64,
    /// Call scheme
    scheme: CallScheme,
    /// Is static call
    is_static: bool,
    /// Depth
    depth: usize,

    /// Create new inputs
    pub fn new(
        caller: primitives.Address,
        target: primitives.Address,
        value: primitives.U256,
        data: primitives.Bytes,
        gas_limit: u64,
        scheme: CallScheme,
        is_static: bool,
        depth: usize,
    ) InputsImpl {
        return InputsImpl{
            .caller = caller,
            .target = target,
            .value = value,
            .data = data,
            .gas_limit = gas_limit,
            .scheme = scheme,
            .is_static = is_static,
            .depth = depth,
        };
    }

    /// Create default inputs
    pub fn default() InputsImpl {
        return InputsImpl{
            .caller = [_]u8{0} ** 20,
            .target = [_]u8{0} ** 20,
            .value = 0,
            .data = @as(primitives.Bytes, @constCast(&[_]u8{})),
            .gas_limit = 0,
            .scheme = .call,
            .is_static = false,
            .depth = 0,
        };
    }

    pub fn getCaller(self: InputsImpl) primitives.Address {
        return self.caller;
    }

    pub fn getTarget(self: InputsImpl) primitives.Address {
        return self.target;
    }

    pub fn getValue(self: InputsImpl) primitives.U256 {
        return self.value;
    }

    pub fn getData(self: InputsImpl) primitives.Bytes {
        return self.data;
    }

    pub fn getGasLimit(self: InputsImpl) u64 {
        return self.gas_limit;
    }

    pub fn getScheme(self: InputsImpl) CallScheme {
        return self.scheme;
    }

    pub fn getIsStatic(self: InputsImpl) bool {
        return self.is_static;
    }

    pub fn getDepth(self: InputsImpl) usize {
        return self.depth;
    }
};

/// Return data buffer
pub const ReturnDataImpl = struct {
    data: primitives.Bytes,
    gas_used: u64,
    success: bool,

    pub fn new(data: primitives.Bytes, gas_used: u64, success: bool) ReturnDataImpl {
        return ReturnDataImpl{
            .data = data,
            .gas_used = gas_used,
            .success = success,
        };
    }

    pub fn default() ReturnDataImpl {
        return ReturnDataImpl{
            .data = &[_]u8{},
            .gas_used = 0,
            .success = false,
        };
    }

    pub fn getData(self: ReturnDataImpl) primitives.Bytes {
        return self.data;
    }

    pub fn getGasUsed(self: ReturnDataImpl) u64 {
        return self.gas_used;
    }

    pub fn getSuccess(self: ReturnDataImpl) bool {
        return self.success;
    }

    pub fn setData(self: *ReturnDataImpl, data: primitives.Bytes) void {
        self.data = data;
    }

    pub fn setGasUsed(self: *ReturnDataImpl, gas_used: u64) void {
        self.gas_used = gas_used;
    }

    pub fn setSuccess(self: *ReturnDataImpl, success: bool) void {
        self.success = success;
    }
};

/// Runtime flags controlling execution behavior
pub const RuntimeFlags = struct {
    is_static: bool,
    spec_id: primitives.SpecId,

    pub fn new(is_static: bool, spec_id: primitives.SpecId) RuntimeFlags {
        return RuntimeFlags{
            .is_static = is_static,
            .spec_id = spec_id,
        };
    }

    pub fn default() RuntimeFlags {
        return RuntimeFlags{
            .is_static = false,
            .spec_id = .prague,
        };
    }

    pub fn getIsStatic(self: RuntimeFlags) bool {
        return self.is_static;
    }

    pub fn getSpecId(self: RuntimeFlags) primitives.SpecId {
        return self.spec_id;
    }

    pub fn setIsStatic(self: *RuntimeFlags, is_static: bool) void {
        self.is_static = is_static;
    }

    pub fn setSpecId(self: *RuntimeFlags, spec_id: primitives.SpecId) void {
        self.spec_id = spec_id;
    }
};

/// Extended bytecode functionality
pub const ExtBytecode = struct {
    bytecode: bytecode.Bytecode,
    pc: usize,
    /// Whether execution is still running (false after halt/stop/return)
    continue_execution: bool,
    is_eof: bool,
    eof_version: ?u8,
    eof_sections: ?std.ArrayList(EofSection),

    pub fn new(bytecode_data: bytecode.Bytecode) ExtBytecode {
        return ExtBytecode{
            .bytecode = bytecode_data,
            .pc = 0,
            .continue_execution = true,
            .is_eof = false,
            .eof_version = null,
            .eof_sections = null,
        };
    }

    pub fn default() ExtBytecode {
        return ExtBytecode{
            .bytecode = bytecode.Bytecode.new(),
            .pc = 0,
            .continue_execution = true,
            .is_eof = false,
            .eof_version = null,
            .eof_sections = null,
        };
    }

    pub fn deinit(self: *ExtBytecode) void {
        if (self.eof_sections) |*sections| {
            sections.deinit(std.heap.c_allocator);
        }
    }

    /// Read current opcode byte (returns 0x00/STOP if past end)
    pub fn opcode(self: *const ExtBytecode) u8 {
        const bytes = self.bytecode.bytecode();
        if (self.pc >= bytes.len) return 0x00;
        return bytes[self.pc];
    }

    /// Advance PC by delta bytes
    pub fn relativeJump(self: *ExtBytecode, delta: usize) void {
        self.pc += delta;
    }

    /// Set PC to absolute destination
    pub fn absoluteJump(self: *ExtBytecode, dest: usize) void {
        self.pc = dest;
    }

    /// Check if jump destination is a valid JUMPDEST
    pub fn isValidJump(self: *const ExtBytecode, dest: usize) bool {
        return self.bytecode.isValidJump(dest);
    }

    /// Read n immediate bytes at current PC (zero-padded if near end of code)
    pub fn readImmediates(self: *const ExtBytecode, comptime n: u8) [n]u8 {
        const bytes = self.bytecode.bytecode();
        var result: [n]u8 = .{0} ** n;
        if (self.pc >= bytes.len) return result;
        const available = bytes.len - self.pc;
        const to_read = @min(@as(usize, n), available);
        @memcpy(result[0..to_read], bytes[self.pc .. self.pc + to_read]);
        return result;
    }

    pub fn isNotEnd(self: *const ExtBytecode) bool {
        return self.continue_execution;
    }

    pub fn getBytecode(self: ExtBytecode) bytecode.Bytecode {
        return self.bytecode;
    }

    pub fn getIsEof(self: ExtBytecode) bool {
        return self.is_eof;
    }

    pub fn getEofVersion(self: ExtBytecode) ?u8 {
        return self.eof_version;
    }

    pub fn getEofSections(self: ExtBytecode) ?std.ArrayList(EofSection) {
        return self.eof_sections;
    }

    pub fn setBytecode(self: *ExtBytecode, bytecode_data: bytecode.Bytecode) void {
        self.bytecode = bytecode_data;
    }

    pub fn setIsEof(self: *ExtBytecode, is_eof: bool) void {
        self.is_eof = is_eof;
    }

    pub fn setEofVersion(self: *ExtBytecode, version: ?u8) void {
        self.eof_version = version;
    }

    pub fn setEofSections(self: *ExtBytecode, sections: ?std.ArrayList(EofSection)) void {
        self.eof_sections = sections;
    }
};

/// EOF section
pub const EofSection = struct {
    section_type: u8,
    data: primitives.Bytes,

    pub fn new(section_type: u8, data: primitives.Bytes) EofSection {
        return EofSection{
            .section_type = section_type,
            .data = data,
        };
    }

    pub fn getSectionType(self: EofSection) u8 {
        return self.section_type;
    }

    pub fn getData(self: EofSection) primitives.Bytes {
        return self.data;
    }

    pub fn setSectionType(self: *EofSection, section_type: u8) void {
        self.section_type = section_type;
    }

    pub fn setData(self: *EofSection, data: primitives.Bytes) void {
        self.data = data;
    }
};

// ---------------------------------------------------------------------------
// Dispatch table types
// ---------------------------------------------------------------------------

/// Function pointer type for opcode handlers (re-exported from instruction_context.zig).
pub const InstructionFn = @import("instruction_context.zig").InstructionFn;

/// One entry in the dispatch table: a handler function and its static gas cost.
pub const InstructionEntry = struct {
    func: InstructionFn,
    static_gas: u64,

    pub fn unknown() InstructionEntry {
        return .{ .func = opUnknown, .static_gas = 0 };
    }
};

/// 256-entry dispatch table indexed by opcode byte.
pub const InstructionTable = [256]InstructionEntry;

/// Handler for unknown/disabled opcodes.
fn opUnknown(ctx: *InstructionContext) void {
    ctx.interpreter.halt(.invalid_opcode);
}

// ---------------------------------------------------------------------------
// Main interpreter
// ---------------------------------------------------------------------------

/// Main interpreter structure that contains all components
pub const Interpreter = struct {
    bytecode: ExtBytecode,
    gas: Gas,
    stack: Stack,
    return_data: ReturnDataImpl,
    memory: Memory,
    input: InputsImpl,
    runtime_flags: RuntimeFlags,
    /// Execution result (set by halt())
    result: InstructionResult,
    extend: void,
    last_opcode: ?u8 = null,

    pub fn new(
        memory: Memory,
        bytecode_data: ExtBytecode,
        input: InputsImpl,
        is_static: bool,
        spec_id: primitives.SpecId,
        gas_limit: u64,
    ) Interpreter {
        return Interpreter{
            .bytecode = bytecode_data,
            .gas = Gas.new(gas_limit),
            .stack = Stack.new(),
            .return_data = ReturnDataImpl.default(),
            .memory = memory,
            .input = input,
            .runtime_flags = RuntimeFlags.new(is_static, spec_id),
            .result = .stop,
            .extend = {},
        };
    }

    pub fn defaultExt() Interpreter {
        return Interpreter.new(
            Memory.new(),
            ExtBytecode.default(),
            InputsImpl.default(),
            false,
            .prague,
            std.math.maxInt(u64),
        );
    }

    pub fn invalid() Interpreter {
        return Interpreter.new(
            Memory.new(),
            ExtBytecode.default(),
            InputsImpl.default(),
            false,
            .prague,
            0,
        );
    }

    /// Halt execution with the given result
    pub fn halt(self: *Interpreter, r: InstructionResult) void {
        self.bytecode.continue_execution = false;
        self.result = r;
        // EVM spec: all remaining gas is consumed on any error (OOG, invalid opcode, etc.).
        // Revert and success are NOT errors — they preserve remaining gas for refund/return.
        if (r.isError()) {
            self.gas.remaining = 0;
        }
    }

    pub fn deinit(self: *Interpreter) void {
        self.bytecode.deinit();
        self.memory.deinit();
    }

    pub fn clear(
        self: *Interpreter,
        memory: Memory,
        bytecode_data: ExtBytecode,
        input: InputsImpl,
        is_static: bool,
        spec_id: primitives.SpecId,
        gas_limit: u64,
    ) void {
        self.bytecode = bytecode_data;
        self.gas = Gas.new(gas_limit);
        self.stack.clear();
        self.return_data = ReturnDataImpl.default();
        self.memory = memory;
        self.input = input;
        self.runtime_flags = RuntimeFlags.new(is_static, spec_id);
        self.result = .stop;
        self.extend = {};
    }

    // -----------------------------------------------------------------------
    // Getters / setters (kept for backwards compatibility)
    // -----------------------------------------------------------------------

    pub fn getBytecode(self: Interpreter) ExtBytecode {
        return self.bytecode;
    }

    pub fn getGas(self: Interpreter) Gas {
        return self.gas;
    }

    pub fn getGasMut(self: *Interpreter) *Gas {
        return &self.gas;
    }

    pub fn getStack(self: Interpreter) Stack {
        return self.stack;
    }

    pub fn getStackMut(self: *Interpreter) *Stack {
        return &self.stack;
    }

    pub fn getReturnData(self: Interpreter) ReturnDataImpl {
        return self.return_data;
    }

    pub fn getReturnDataMut(self: *Interpreter) *ReturnDataImpl {
        return &self.return_data;
    }

    pub fn getMemory(self: Interpreter) Memory {
        return self.memory;
    }

    pub fn getMemoryMut(self: *Interpreter) *Memory {
        return &self.memory;
    }

    pub fn getInput(self: Interpreter) InputsImpl {
        return self.input;
    }

    pub fn getInputMut(self: *Interpreter) *InputsImpl {
        return &self.input;
    }

    pub fn getRuntimeFlags(self: Interpreter) RuntimeFlags {
        return self.runtime_flags;
    }

    pub fn getRuntimeFlagsMut(self: *Interpreter) *RuntimeFlags {
        return &self.runtime_flags;
    }

    pub fn getExtend(self: Interpreter) void {
        return self.extend;
    }

    pub fn getExtendMut(self: *Interpreter) *void {
        return &self.extend;
    }

    // -----------------------------------------------------------------------
    // Dispatch methods
    // -----------------------------------------------------------------------

    /// Execute one opcode: read opcode at PC, advance PC, charge static gas, call handler.
    pub fn step(self: *Interpreter, table: *const InstructionTable) void {
        const op = self.bytecode.opcode();
        self.bytecode.relativeJump(1);
        const ins = table[op];
        if (!self.gas.spend(ins.static_gas)) {
            self.halt(.out_of_gas);
            return;
        }
        var ctx = InstructionContext{ .interpreter = self };
        ins.func(&ctx);
    }

    /// Run the interpreter until execution halts (no host).
    pub fn run(self: *Interpreter, table: *const InstructionTable) InstructionResult {
        while (self.bytecode.isNotEnd()) {
            self.step(table);
        }
        return self.result;
    }

    /// Execute one opcode with a host for state access.
    pub fn stepWithHost(self: *Interpreter, table: *const InstructionTable, host: *Host) void {
        const op = self.bytecode.opcode();
        self.bytecode.relativeJump(1);
        const ins = table[op];
        if (!self.gas.spend(ins.static_gas)) {
            self.halt(.out_of_gas);
            return;
        }
        var ctx = InstructionContext{ .interpreter = self, .host = host };
        ins.func(&ctx);
    }

    /// Run the interpreter until execution halts, with full host access.
    pub fn runWithHost(self: *Interpreter, table: *const InstructionTable, host: *Host) InstructionResult {
        while (self.bytecode.isNotEnd()) {
            self.stepWithHost(table, host);
        }
        return self.result;
    }
};

/// Calculate number of words from bytes
pub fn numWords(bytes: usize) usize {
    return (bytes + 31) / 32;
}
