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
const InstructionContext = @import("instruction_context.zig").InstructionContext;
const Host = @import("host.zig").Host;
const opcodes = @import("opcodes/main.zig");

const U256 = primitives.U256;

/// Convert a big-endian [32]u8 to U256
fn u256FromBeBytes(bytes: [32]u8) U256 {
    return @byteSwap(@as(U256, @bitCast(bytes)));
}

/// Convert a U256 to big-endian [32]u8
fn u256ToBeBytes(val: U256) [32]u8 {
    return @bitCast(@byteSwap(val));
}

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
            .caller = primitives.Address.zero(),
            .target = primitives.Address.zero(),
            .value = @as(primitives.U256, 0),
            .data = primitives.Bytes.init(std.heap.page_allocator, 0) catch unreachable,
            .gas_limit = 0,
            .scheme = .call,
            .is_static = false,
            .depth = 0,
        };
    }

    /// Get caller
    pub fn getCaller(self: InputsImpl) primitives.Address {
        return self.caller;
    }

    /// Get target
    pub fn getTarget(self: InputsImpl) primitives.Address {
        return self.target;
    }

    /// Get value
    pub fn getValue(self: InputsImpl) primitives.U256 {
        return self.value;
    }

    /// Get data
    pub fn getData(self: InputsImpl) primitives.Bytes {
        return self.data;
    }

    /// Get gas limit
    pub fn getGasLimit(self: InputsImpl) u64 {
        return self.gas_limit;
    }

    /// Get scheme
    pub fn getScheme(self: InputsImpl) CallScheme {
        return self.scheme;
    }

    /// Get is static
    pub fn getIsStatic(self: InputsImpl) bool {
        return self.is_static;
    }

    /// Get depth
    pub fn getDepth(self: InputsImpl) usize {
        return self.depth;
    }
};

/// Return data buffer
pub const ReturnDataImpl = struct {
    /// Return data
    data: primitives.Bytes,
    /// Gas used
    gas_used: u64,
    /// Success
    success: bool,

    /// Create new return data
    pub fn new(data: primitives.Bytes, gas_used: u64, success: bool) ReturnDataImpl {
        return ReturnDataImpl{
            .data = data,
            .gas_used = gas_used,
            .success = success,
        };
    }

    /// Create default return data
    pub fn default() ReturnDataImpl {
        return ReturnDataImpl{
            .data = &[_]u8{},
            .gas_used = 0,
            .success = false,
        };
    }

    /// Get data
    pub fn getData(self: ReturnDataImpl) primitives.Bytes {
        return self.data;
    }

    /// Get gas used
    pub fn getGasUsed(self: ReturnDataImpl) u64 {
        return self.gas_used;
    }

    /// Get success
    pub fn getSuccess(self: ReturnDataImpl) bool {
        return self.success;
    }

    /// Set data
    pub fn setData(self: *ReturnDataImpl, data: primitives.Bytes) void {
        self.data = data;
    }

    /// Set gas used
    pub fn setGasUsed(self: *ReturnDataImpl, gas_used: u64) void {
        self.gas_used = gas_used;
    }

    /// Set success
    pub fn setSuccess(self: *ReturnDataImpl, success: bool) void {
        self.success = success;
    }
};

/// Runtime flags controlling execution behavior
pub const RuntimeFlags = struct {
    /// Is static call
    is_static: bool,
    /// Spec ID
    spec_id: primitives.SpecId,

    /// Create new runtime flags
    pub fn new(is_static: bool, spec_id: primitives.SpecId) RuntimeFlags {
        return RuntimeFlags{
            .is_static = is_static,
            .spec_id = spec_id,
        };
    }

    /// Create default runtime flags
    pub fn default() RuntimeFlags {
        return RuntimeFlags{
            .is_static = false,
            .spec_id = primitives.SpecId.default(),
        };
    }

    /// Get is static
    pub fn getIsStatic(self: RuntimeFlags) bool {
        return self.is_static;
    }

    /// Get spec ID
    pub fn getSpecId(self: RuntimeFlags) primitives.SpecId {
        return self.spec_id;
    }

    /// Set is static
    pub fn setIsStatic(self: *RuntimeFlags, is_static: bool) void {
        self.is_static = is_static;
    }

    /// Set spec ID
    pub fn setSpecId(self: *RuntimeFlags, spec_id: primitives.SpecId) void {
        self.spec_id = spec_id;
    }
};

/// Extended bytecode functionality
pub const ExtBytecode = struct {
    /// Bytecode
    bytecode: bytecode.Bytecode,
    /// Is EOF
    is_eof: bool,
    /// EOF version
    eof_version: ?u8,
    /// EOF sections
    eof_sections: ?std.ArrayList(EofSection),

    /// Create new extended bytecode
    pub fn new(bytecode_data: bytecode.Bytecode) ExtBytecode {
        return ExtBytecode{
            .bytecode = bytecode_data,
            .is_eof = false,
            .eof_version = null,
            .eof_sections = null,
        };
    }

    /// Create default extended bytecode
    pub fn default() ExtBytecode {
        return ExtBytecode{
            .bytecode = bytecode.Bytecode.default(),
            .is_eof = false,
            .eof_version = null,
            .eof_sections = null,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *ExtBytecode) void {
        if (self.eof_sections) |*sections| {
            sections.deinit(std.heap.c_allocator);
        }
    }

    /// Get bytecode
    pub fn getBytecode(self: ExtBytecode) bytecode.Bytecode {
        return self.bytecode;
    }

    /// Get is EOF
    pub fn getIsEof(self: ExtBytecode) bool {
        return self.is_eof;
    }

    /// Get EOF version
    pub fn getEofVersion(self: ExtBytecode) ?u8 {
        return self.eof_version;
    }

    /// Get EOF sections
    pub fn getEofSections(self: ExtBytecode) ?std.ArrayList(EofSection) {
        return self.eof_sections;
    }

    /// Set bytecode
    pub fn setBytecode(self: *ExtBytecode, bytecode_data: bytecode.Bytecode) void {
        self.bytecode = bytecode_data;
    }

    /// Set is EOF
    pub fn setIsEof(self: *ExtBytecode, is_eof: bool) void {
        self.is_eof = is_eof;
    }

    /// Set EOF version
    pub fn setEofVersion(self: *ExtBytecode, version: ?u8) void {
        self.eof_version = version;
    }

    /// Set EOF sections
    pub fn setEofSections(self: *ExtBytecode, sections: ?std.ArrayList(EofSection)) void {
        self.eof_sections = sections;
    }
};

/// EOF section
pub const EofSection = struct {
    /// Section type
    section_type: u8,
    /// Section data
    data: primitives.Bytes,

    /// Create new EOF section
    pub fn new(section_type: u8, data: primitives.Bytes) EofSection {
        return EofSection{
            .section_type = section_type,
            .data = data,
        };
    }

    /// Get section type
    pub fn getSectionType(self: EofSection) u8 {
        return self.section_type;
    }

    /// Get data
    pub fn getData(self: EofSection) primitives.Bytes {
        return self.data;
    }

    /// Set section type
    pub fn setSectionType(self: *EofSection, section_type: u8) void {
        self.section_type = section_type;
    }

    /// Set data
    pub fn setData(self: *EofSection, data: primitives.Bytes) void {
        self.data = data;
    }
};

/// Main interpreter structure that contains all components
pub const Interpreter = struct {
    /// Bytecode being executed
    bytecode: ExtBytecode,
    /// Gas tracking for execution costs
    gas: Gas,
    /// EVM stack for computation
    stack: Stack,
    /// Buffer for return data from calls
    return_data: ReturnDataImpl,
    /// EVM memory for data storage
    memory: Memory,
    /// Input data for current execution context
    input: InputsImpl,
    /// Runtime flags controlling execution behavior
    runtime_flags: RuntimeFlags,
    /// Extended functionality and customizations
    extend: void,

    /// Create new interpreter
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
            .extend = {},
        };
    }

    /// Create a new interpreter with default extended functionality
    pub fn defaultExt() Interpreter {
        return Interpreter.new(
            Memory.new(),
            ExtBytecode.default(),
            InputsImpl.default(),
            false,
            primitives.SpecId.default(),
            std.math.maxInt(u64),
        );
    }

    /// Create a new invalid interpreter
    pub fn invalid() Interpreter {
        return Interpreter.new(
            Memory.new(),
            ExtBytecode.default(),
            InputsImpl.default(),
            false,
            primitives.SpecId.default(),
            0,
        );
    }

    /// Deinitialize the interpreter
    pub fn deinit(self: *Interpreter) void {
        self.bytecode.deinit();
        self.memory.deinit();
    }

    /// Clear and reinitialize the interpreter with new parameters
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
        self.extend = {};
    }

    /// Get bytecode
    pub fn getBytecode(self: Interpreter) ExtBytecode {
        return self.bytecode;
    }

    /// Get gas
    pub fn getGas(self: Interpreter) Gas {
        return self.gas;
    }

    /// Get gas mutably
    pub fn getGasMut(self: *Interpreter) *Gas {
        return &self.gas;
    }

    /// Get stack
    pub fn getStack(self: Interpreter) Stack {
        return self.stack;
    }

    /// Get stack mutably
    pub fn getStackMut(self: *Interpreter) *Stack {
        return &self.stack;
    }

    /// Get return data
    pub fn getReturnData(self: Interpreter) ReturnDataImpl {
        return self.return_data;
    }

    /// Get return data mutably
    pub fn getReturnDataMut(self: *Interpreter) *ReturnDataImpl {
        return &self.return_data;
    }

    /// Get memory
    pub fn getMemory(self: Interpreter) Memory {
        return self.memory;
    }

    /// Get memory mutably
    pub fn getMemoryMut(self: *Interpreter) *Memory {
        return &self.memory;
    }

    /// Get input
    pub fn getInput(self: Interpreter) InputsImpl {
        return self.input;
    }

    /// Get input mutably
    pub fn getInputMut(self: *Interpreter) *InputsImpl {
        return &self.input;
    }

    /// Get runtime flags
    pub fn getRuntimeFlags(self: Interpreter) RuntimeFlags {
        return self.runtime_flags;
    }

    /// Get runtime flags mutably
    pub fn getRuntimeFlagsMut(self: *Interpreter) *RuntimeFlags {
        return &self.runtime_flags;
    }

    /// Get extend
    pub fn getExtend(self: Interpreter) void {
        return self.extend;
    }

    /// Get extend mutably
    pub fn getExtendMut(self: *Interpreter) *void {
        return &self.extend;
    }

    /// Execute the bytecode using block/tx environment and host for state lookups.
    pub fn execute(
        self: *Interpreter,
        block_env: context.BlockEnv,
        tx_env: context.TxEnv,
        host: Host,
    ) InstructionResult {
        const code = self.bytecode.bytecode.originalBytes();
        const bytecode_obj = bytecode.Bytecode.newLegacy(code);
        const jump_table = bytecode_obj.legacyJumpTable();
        var pc: usize = 0;
        const stack = &self.stack;
        const gas = &self.gas;
        const memory = &self.memory;

        while (pc < code.len) {
            const opcode = code[pc];

            const result: InstructionResult = switch (opcode) {
                // Stop & Arithmetic
                bytecode.STOP => return .stop,
                bytecode.ADD => opcodes.opAdd(stack, gas),
                bytecode.MUL => opcodes.opMul(stack, gas),
                bytecode.SUB => opcodes.opSub(stack, gas),
                bytecode.DIV => opcodes.opDiv(stack, gas),
                bytecode.SDIV => opcodes.opSdiv(stack, gas),
                bytecode.MOD => opcodes.opMod(stack, gas),
                bytecode.SMOD => opcodes.opSmod(stack, gas),
                bytecode.ADDMOD => opcodes.opAddmod(stack, gas),
                bytecode.MULMOD => opcodes.opMulmod(stack, gas),
                bytecode.EXP => opcodes.opExp(stack, gas),
                bytecode.SIGNEXTEND => opcodes.opSignextend(stack, gas),

                // Comparison
                bytecode.LT => opcodes.opLt(stack, gas),
                bytecode.GT => opcodes.opGt(stack, gas),
                bytecode.SLT => opcodes.opSlt(stack, gas),
                bytecode.SGT => opcodes.opSgt(stack, gas),
                bytecode.EQ => opcodes.opEq(stack, gas),
                bytecode.ISZERO => opcodes.opIsZero(stack, gas),

                // Bitwise
                bytecode.AND => opcodes.opAnd(stack, gas),
                bytecode.OR => opcodes.opOr(stack, gas),
                bytecode.XOR => opcodes.opXor(stack, gas),
                bytecode.NOT => opcodes.opNot(stack, gas),
                bytecode.BYTE => opcodes.opByte(stack, gas),
                bytecode.SHL => opcodes.opShl(stack, gas),
                bytecode.SHR => opcodes.opShr(stack, gas),
                bytecode.SAR => opcodes.opSar(stack, gas),

                // Keccak
                bytecode.KECCAK256 => opcodes.opKeccak256(stack, gas, memory),

                // Environmental info
                bytecode.ADDRESS => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(addressToU256(self.input.target));
                    break :blk InstructionResult.continue_;
                },
                bytecode.CALLER => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(addressToU256(self.input.caller));
                    break :blk InstructionResult.continue_;
                },
                bytecode.CALLVALUE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(self.input.value);
                    break :blk InstructionResult.continue_;
                },
                bytecode.CALLDATALOAD => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                    const offset_val = stack.peekUnsafe(0);
                    const calldata = self.input.data;
                    const offset_u64 = std.math.cast(u64, offset_val) orelse {
                        stack.setTopUnsafe().* = @as(U256, 0);
                        break :blk InstructionResult.continue_;
                    };
                    const offset: usize = @intCast(@min(offset_u64, calldata.len));
                    var buf: [32]u8 = [_]u8{0} ** 32;
                    const available = if (offset < calldata.len) calldata.len - offset else 0;
                    const to_copy = @min(available, 32);
                    if (to_copy > 0) {
                        @memcpy(buf[0..to_copy], calldata[offset .. offset + to_copy]);
                    }
                    stack.setTopUnsafe().* = u256FromBeBytes(buf);
                    break :blk InstructionResult.continue_;
                },
                bytecode.CALLDATASIZE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, @intCast(self.input.data.len)));
                    break :blk InstructionResult.continue_;
                },
                bytecode.CALLDATACOPY => blk: {
                    if (!stack.hasItems(3)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                    const dest_offset = stack.peekUnsafe(0);
                    const src_offset = stack.peekUnsafe(1);
                    const length = stack.peekUnsafe(2);
                    stack.shrinkUnsafe(3);

                    const len_u64 = std.math.cast(u64, length) orelse break :blk InstructionResult.memory_limit_oog;
                    if (len_u64 == 0) break :blk InstructionResult.continue_;

                    const dest_u64 = std.math.cast(u64, dest_offset) orelse break :blk InstructionResult.memory_limit_oog;
                    const src_u64 = std.math.cast(u64, src_offset) orelse 0;
                    const dest: usize = @intCast(dest_u64);
                    const len: usize = @intCast(len_u64);
                    const new_size = dest + len;

                    if (new_size > memory.size()) {
                        memory.buffer.resize(std.heap.c_allocator, new_size) catch break :blk InstructionResult.memory_limit_oog;
                    }

                    const calldata = self.input.data;
                    const src: usize = @intCast(@min(src_u64, calldata.len));
                    var i: usize = 0;
                    while (i < len) : (i += 1) {
                        const src_pos = src + i;
                        memory.buffer.items[dest + i] = if (src_pos < calldata.len) calldata[src_pos] else 0;
                    }
                    break :blk InstructionResult.continue_;
                },
                bytecode.CODESIZE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, @intCast(code.len)));
                    break :blk InstructionResult.continue_;
                },
                bytecode.CODECOPY => blk: {
                    if (!stack.hasItems(3)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                    const dest_offset = stack.peekUnsafe(0);
                    const src_offset = stack.peekUnsafe(1);
                    const length = stack.peekUnsafe(2);
                    stack.shrinkUnsafe(3);

                    const len_u64 = std.math.cast(u64, length) orelse break :blk InstructionResult.memory_limit_oog;
                    if (len_u64 == 0) break :blk InstructionResult.continue_;

                    const dest_u64 = std.math.cast(u64, dest_offset) orelse break :blk InstructionResult.memory_limit_oog;
                    const src_u64 = std.math.cast(u64, src_offset) orelse 0;
                    const dest: usize = @intCast(dest_u64);
                    const src: usize = @intCast(@min(src_u64, code.len));
                    const len: usize = @intCast(len_u64);
                    const new_size = dest + len;

                    if (new_size > memory.size()) {
                        memory.buffer.resize(std.heap.c_allocator, new_size) catch break :blk InstructionResult.memory_limit_oog;
                    }

                    var i: usize = 0;
                    while (i < len) : (i += 1) {
                        const src_pos = src + i;
                        memory.buffer.items[dest + i] = if (src_pos < code.len) code[src_pos] else 0;
                    }
                    break :blk InstructionResult.continue_;
                },
                bytecode.GASPRICE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, tx_env.gas_price));
                    break :blk InstructionResult.continue_;
                },
                bytecode.ORIGIN => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(addressToU256(tx_env.caller));
                    break :blk InstructionResult.continue_;
                },

                // Block info
                bytecode.COINBASE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(addressToU256(block_env.beneficiary));
                    break :blk InstructionResult.continue_;
                },
                bytecode.TIMESTAMP => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(block_env.timestamp);
                    break :blk InstructionResult.continue_;
                },
                bytecode.NUMBER => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(block_env.number);
                    break :blk InstructionResult.continue_;
                },
                bytecode.DIFFICULTY => blk: {
                    // Post-merge: returns prevrandao
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    const val = if (block_env.prevrandao) |pr| u256FromBeBytes(pr) else @as(U256, 0);
                    stack.pushUnsafe(val);
                    break :blk InstructionResult.continue_;
                },
                bytecode.GASLIMIT => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, block_env.gas_limit));
                    break :blk InstructionResult.continue_;
                },
                bytecode.BASEFEE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, block_env.basefee));
                    break :blk InstructionResult.continue_;
                },

                // Memory ops
                bytecode.MLOAD => opcodes.opMload(stack, gas, memory),
                bytecode.MSTORE => opcodes.opMstore(stack, gas, memory),
                bytecode.MSTORE8 => opcodes.opMstore8(stack, gas, memory),
                bytecode.MSIZE => opcodes.opMsize(stack, gas, memory),
                bytecode.MCOPY => opcodes.opMcopy(stack, gas, memory),

                // Storage operations
                bytecode.SLOAD => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    const key = stack.peekUnsafe(0);
                    const val = host.sload(self.input.target, key);
                    stack.setTopUnsafe().* = val;
                    break :blk InstructionResult.continue_;
                },
                bytecode.SSTORE => blk: {
                    if (!stack.hasItems(2)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    const key = stack.peekUnsafe(0);
                    const value = stack.peekUnsafe(1);
                    stack.shrinkUnsafe(2);
                    host.sstore(self.input.target, key, value);
                    break :blk InstructionResult.continue_;
                },

                // Stack operations
                bytecode.POP => opcodes.opPop(stack, gas),
                bytecode.PUSH0 => opcodes.opPush0(stack, gas),

                // PUSH1-PUSH32
                inline bytecode.PUSH1...bytecode.PUSH32 => |push_op| blk: {
                    const n: u8 = push_op - bytecode.PUSH1 + 1;
                    break :blk opcodes.opPushN(stack, gas, code, &pc, n);
                },

                // DUP1-DUP16
                inline bytecode.DUP1...bytecode.DUP16 => |dup_op| blk: {
                    const n: u8 = dup_op - bytecode.DUP1 + 1;
                    break :blk opcodes.opDupN(stack, gas, n);
                },

                // SWAP1-SWAP16
                inline bytecode.SWAP1...bytecode.SWAP16 => |swap_op| blk: {
                    const n: u8 = swap_op - bytecode.SWAP1 + 1;
                    break :blk opcodes.opSwapN(stack, gas, n);
                },

                // Control flow
                bytecode.JUMP => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(8)) break :blk InstructionResult.out_of_gas;
                    const dest = stack.popUnsafe();
                    const dest_u64 = std.math.cast(u64, dest) orelse break :blk InstructionResult.invalid_jump;
                    const dest_usize: usize = @intCast(dest_u64);
                    if (dest_usize >= code.len) break :blk InstructionResult.invalid_jump;
                    if (jump_table) |jt| {
                        if (!jt.isValid(dest_usize)) break :blk InstructionResult.invalid_jump;
                    } else {
                        if (code[dest_usize] != bytecode.JUMPDEST) break :blk InstructionResult.invalid_jump;
                    }
                    pc = dest_usize;
                    continue;
                },
                bytecode.JUMPI => blk: {
                    if (!stack.hasItems(2)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(10)) break :blk InstructionResult.out_of_gas;
                    const dest = stack.peekUnsafe(0);
                    const cond = stack.peekUnsafe(1);
                    stack.shrinkUnsafe(2);
                    if (cond != 0) {
                        const dest_u64 = std.math.cast(u64, dest) orelse break :blk InstructionResult.invalid_jump;
                        const dest_usize: usize = @intCast(dest_u64);
                        if (dest_usize >= code.len) break :blk InstructionResult.invalid_jump;
                        if (jump_table) |jt| {
                            if (!jt.isValid(dest_usize)) break :blk InstructionResult.invalid_jump;
                        } else {
                            if (code[dest_usize] != bytecode.JUMPDEST) break :blk InstructionResult.invalid_jump;
                        }
                        pc = dest_usize;
                        continue;
                    }
                    break :blk InstructionResult.continue_;
                },
                bytecode.JUMPDEST => opcodes.opJumpdest(stack, gas),
                bytecode.PC => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, @intCast(pc)));
                    break :blk InstructionResult.continue_;
                },
                bytecode.GAS => opcodes.opGas(stack, gas),

                // Return / Revert
                bytecode.RETURN => return .@"return",
                bytecode.REVERT => return .revert,
                bytecode.INVALID => return .invalid_opcode,

                // LOG0-LOG4
                inline bytecode.LOG0...bytecode.LOG4 => |log_op| blk: {
                    const topic_count: u8 = log_op - bytecode.LOG0;
                    const items_needed: u8 = topic_count + 2;
                    if (!stack.hasItems(items_needed)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(375)) break :blk InstructionResult.out_of_gas;
                    stack.shrinkUnsafe(items_needed);
                    break :blk InstructionResult.continue_;
                },

                // BALANCE, EXTCODESIZE, etc.
                bytecode.BALANCE => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    const addr_val = stack.peekUnsafe(0);
                    const full = u256ToBeBytes(addr_val);
                    var addr_bytes: [20]u8 = undefined;
                    @memcpy(&addr_bytes, full[12..32]);
                    stack.setTopUnsafe().* = host.balance(addr_bytes);
                    break :blk InstructionResult.continue_;
                },
                bytecode.SELFBALANCE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(5)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(host.balance(self.input.target));
                    break :blk InstructionResult.continue_;
                },
                bytecode.EXTCODESIZE => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    const addr_val = stack.peekUnsafe(0);
                    const full = u256ToBeBytes(addr_val);
                    var addr_bytes: [20]u8 = undefined;
                    @memcpy(&addr_bytes, full[12..32]);
                    stack.setTopUnsafe().* = @as(U256, @intCast(host.codeSize(addr_bytes)));
                    break :blk InstructionResult.continue_;
                },
                bytecode.EXTCODEHASH => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    const addr_val = stack.peekUnsafe(0);
                    const full = u256ToBeBytes(addr_val);
                    var addr_bytes: [20]u8 = undefined;
                    @memcpy(&addr_bytes, full[12..32]);
                    stack.setTopUnsafe().* = host.codeHash(addr_bytes);
                    break :blk InstructionResult.continue_;
                },

                // BLOCKHASH, CHAINID
                bytecode.BLOCKHASH => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(20)) break :blk InstructionResult.out_of_gas;
                    const num = stack.peekUnsafe(0);
                    stack.setTopUnsafe().* = host.blockHash(num);
                    break :blk InstructionResult.continue_;
                },
                bytecode.CHAINID => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, tx_env.chain_id orelse 1));
                    break :blk InstructionResult.continue_;
                },

                // Transient storage (EIP-1153) - stubs
                bytecode.TLOAD => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    stack.setTopUnsafe().* = @as(U256, 0);
                    break :blk InstructionResult.continue_;
                },
                bytecode.TSTORE => blk: {
                    if (!stack.hasItems(2)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    stack.shrinkUnsafe(2);
                    break :blk InstructionResult.continue_;
                },

                // RETURNDATASIZE, RETURNDATACOPY (no sub-calls, so always 0)
                bytecode.RETURNDATASIZE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, 0));
                    break :blk InstructionResult.continue_;
                },
                bytecode.RETURNDATACOPY => blk: {
                    if (!stack.hasItems(3)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                    stack.shrinkUnsafe(3);
                    break :blk InstructionResult.continue_;
                },

                // BLOBHASH, BLOBBASEFEE
                bytecode.BLOBHASH => blk: {
                    if (!stack.hasItems(1)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(3)) break :blk InstructionResult.out_of_gas;
                    stack.setTopUnsafe().* = @as(U256, 0);
                    break :blk InstructionResult.continue_;
                },
                bytecode.BLOBBASEFEE => blk: {
                    if (!stack.hasSpace(1)) break :blk InstructionResult.stack_overflow;
                    if (!gas.spend(2)) break :blk InstructionResult.out_of_gas;
                    stack.pushUnsafe(@as(U256, 0));
                    break :blk InstructionResult.continue_;
                },

                // EXTCODECOPY
                bytecode.EXTCODECOPY => blk: {
                    if (!stack.hasItems(4)) break :blk InstructionResult.stack_underflow;
                    if (!gas.spend(100)) break :blk InstructionResult.out_of_gas;
                    stack.shrinkUnsafe(4);
                    break :blk InstructionResult.continue_;
                },

                // CALL family, CREATE - not supported yet
                bytecode.CALL,
                bytecode.CALLCODE,
                bytecode.DELEGATECALL,
                bytecode.STATICCALL,
                bytecode.CREATE,
                bytecode.CREATE2,
                => return .invalid_opcode,

                bytecode.SELFDESTRUCT => return .selfdestruct,

                else => return .invalid_opcode,
            };

            switch (result) {
                .continue_ => {
                    pc += 1;
                },
                .stop => return .stop,
                .@"return" => return .@"return",
                .revert => return .revert,
                else => return result,
            }
        }

        // Fell off the end of bytecode — implicit STOP
        return .stop;
    }
};

fn addressToU256(addr: [20]u8) U256 {
    var buf: [32]u8 = [_]u8{0} ** 32;
    @memcpy(buf[12..32], &addr);
    return u256FromBeBytes(buf);
}

/// Calculate number of words from bytes
pub fn numWords(bytes: usize) usize {
    return (bytes + 31) / 32;
}

/// Resize memory to accommodate new size
pub fn resizeMemory(memory: *Memory, new_size: usize) !void {
    try memory.resize(new_size);
}
