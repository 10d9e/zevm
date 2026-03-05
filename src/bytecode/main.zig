const std = @import("std");
const primitives = @import("primitives");

/// EVM opcode definitions and utilities. It contains opcode information and utilities to work with opcodes.
/// An EVM opcode
/// This is always a valid opcode, as declared in the opcode module or the OPCODE_INFO constant.
pub const OpCode = struct {
    value: u8,

    const Self = @This();

    /// Instantiates a new opcode from a u8.
    /// Returns null if the opcode is not valid.
    pub fn new(opcode: u8) ?Self {
        if (OPCODE_INFO[opcode]) |_| {
            return Self{ .value = opcode };
        }
        return null;
    }

    /// Returns true if the opcode is a jump destination.
    pub fn isJumpdest(self: Self) bool {
        return self.value == JUMPDEST;
    }

    /// Takes a u8 and returns true if it is a jump destination.
    pub fn isJumpdestByOp(opcode: u8) bool {
        if (Self.new(opcode)) |op| {
            return op.isJumpdest();
        }
        return false;
    }

    /// Returns true if the opcode is a legacy jump instruction.
    pub fn isJump(self: Self) bool {
        return self.value == JUMP;
    }

    /// Takes a u8 and returns true if it is a jump instruction.
    pub fn isJumpByOp(opcode: u8) bool {
        if (Self.new(opcode)) |op| {
            return op.isJump();
        }
        return false;
    }

    /// Returns true if the opcode is a PUSH instruction.
    pub fn isPush(self: Self) bool {
        return self.value >= PUSH1 and self.value <= PUSH32;
    }

    /// Takes a u8 and returns true if it is a push instruction.
    pub fn isPushByOp(opcode: u8) bool {
        if (Self.new(opcode)) |op| {
            return op.isPush();
        }
        return false;
    }

    /// Instantiates a new opcode from a u8 without checking if it is valid.
    /// Safety: All code using Opcode values assume that they are valid opcodes, so providing an invalid
    /// opcode may cause undefined behavior.
    pub fn newUnchecked(opcode: u8) Self {
        return Self{ .value = opcode };
    }

    /// Returns the opcode as a string.
    pub fn asStr(self: Self) []const u8 {
        return self.info().name;
    }

    /// Returns the opcode name.
    pub fn nameByOp(opcode: u8) []const u8 {
        if (Self.new(opcode)) |op| {
            return op.asStr();
        }
        return "Unknown";
    }

    /// Returns the number of input stack elements.
    pub fn inputs(self: Self) u8 {
        return self.info().inputs;
    }

    /// Returns the number of output stack elements.
    pub fn outputs(self: Self) u8 {
        return self.info().outputs;
    }

    /// Calculates the difference between the number of input and output stack elements.
    pub fn ioDiff(self: Self) i16 {
        return @as(i16, self.outputs()) - @as(i16, self.inputs());
    }

    /// Returns the opcode information for the given opcode.
    pub fn infoByOp(opcode: u8) ?OpCodeInfo {
        if (Self.new(opcode)) |op| {
            return op.info();
        }
        return null;
    }

    /// Returns the opcode as a usize.
    pub fn asUsize(self: Self) usize {
        return self.value;
    }

    /// Returns the opcode information.
    pub fn info(self: Self) OpCodeInfo {
        return OPCODE_INFO[self.value] orelse unreachable;
    }

    /// Returns the number of both input and output stack elements.
    pub fn inputOutput(self: Self) struct { u8, u8 } {
        const opcode_info = self.info();
        return .{ opcode_info.inputs, opcode_info.outputs };
    }

    /// Returns the opcode as a u8.
    pub fn get(self: Self) u8 {
        return self.value;
    }

    /// Returns true if the opcode modifies memory.
    pub fn modifiesMemory(self: Self) bool {
        return switch (self.value) {
            EXTCODECOPY, MSTORE, MSTORE8, MCOPY, CODECOPY, CALLDATACOPY, RETURNDATACOPY, CALL, CALLCODE, DELEGATECALL, STATICCALL => true,
            else => false,
        };
    }

    /// Returns true if the opcode is valid
    pub fn isValid(self: Self) bool {
        return OPCODE_INFO[self.value] != null;
    }

    /// Format opcode for display
    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (OPCODE_INFO[self.value]) |opcode_info| {
            try writer.writeAll(opcode_info.name);
        } else {
            try writer.print("UNKNOWN(0x{0:02X})", .{self.value});
        }
    }
};

/// Information about opcode, such as name, and stack inputs and outputs
pub const OpCodeInfo = struct {
    name: []const u8,
    inputs: u8,
    outputs: u8,
    immediate_size: u8,
    terminating: bool,

    /// Calculates the difference between the number of input and output stack elements.
    pub fn ioDiff(self: OpCodeInfo) i16 {
        return @as(i16, self.outputs) - @as(i16, self.inputs);
    }

    /// Returns whether this opcode terminates execution, e.g. STOP, RETURN, etc.
    pub fn isTerminating(self: OpCodeInfo) bool {
        return self.terminating;
    }
};

/// Alias for the JUMPDEST opcode
pub const NOP: u8 = JUMPDEST;

// Opcode constants
pub const STOP: u8 = 0x00;
pub const ADD: u8 = 0x01;
pub const MUL: u8 = 0x02;
pub const SUB: u8 = 0x03;
pub const DIV: u8 = 0x04;
pub const SDIV: u8 = 0x05;
pub const MOD: u8 = 0x06;
pub const SMOD: u8 = 0x07;
pub const ADDMOD: u8 = 0x08;
pub const MULMOD: u8 = 0x09;
pub const EXP: u8 = 0x0A;
pub const SIGNEXTEND: u8 = 0x0B;
pub const LT: u8 = 0x10;
pub const GT: u8 = 0x11;
pub const SLT: u8 = 0x12;
pub const SGT: u8 = 0x13;
pub const EQ: u8 = 0x14;
pub const ISZERO: u8 = 0x15;
pub const AND: u8 = 0x16;
pub const OR: u8 = 0x17;
pub const XOR: u8 = 0x18;
pub const NOT: u8 = 0x19;
pub const BYTE: u8 = 0x1A;
pub const SHL: u8 = 0x1B;
pub const SHR: u8 = 0x1C;
pub const SAR: u8 = 0x1D;
pub const CLZ: u8 = 0x1E;
pub const KECCAK256: u8 = 0x20;
pub const ADDRESS: u8 = 0x30;
pub const BALANCE: u8 = 0x31;
pub const ORIGIN: u8 = 0x32;
pub const CALLER: u8 = 0x33;
pub const CALLVALUE: u8 = 0x34;
pub const CALLDATALOAD: u8 = 0x35;
pub const CALLDATASIZE: u8 = 0x36;
pub const CALLDATACOPY: u8 = 0x37;
pub const CODESIZE: u8 = 0x38;
pub const CODECOPY: u8 = 0x39;
pub const GASPRICE: u8 = 0x3A;
pub const EXTCODESIZE: u8 = 0x3B;
pub const EXTCODECOPY: u8 = 0x3C;
pub const RETURNDATASIZE: u8 = 0x3D;
pub const RETURNDATACOPY: u8 = 0x3E;
pub const EXTCODEHASH: u8 = 0x3F;
pub const BLOCKHASH: u8 = 0x40;
pub const COINBASE: u8 = 0x41;
pub const TIMESTAMP: u8 = 0x42;
pub const NUMBER: u8 = 0x43;
pub const DIFFICULTY: u8 = 0x44;
pub const GASLIMIT: u8 = 0x45;
pub const CHAINID: u8 = 0x46;
pub const SELFBALANCE: u8 = 0x47;
pub const BASEFEE: u8 = 0x48;
pub const BLOBHASH: u8 = 0x49;
pub const BLOBBASEFEE: u8 = 0x4A;
pub const POP: u8 = 0x50;
pub const MLOAD: u8 = 0x51;
pub const MSTORE: u8 = 0x52;
pub const MSTORE8: u8 = 0x53;
pub const SLOAD: u8 = 0x54;
pub const SSTORE: u8 = 0x55;
pub const JUMP: u8 = 0x56;
pub const JUMPI: u8 = 0x57;
pub const PC: u8 = 0x58;
pub const MSIZE: u8 = 0x59;
pub const GAS: u8 = 0x5A;
pub const JUMPDEST: u8 = 0x5B;
pub const TLOAD: u8 = 0x5C;
pub const TSTORE: u8 = 0x5D;
pub const MCOPY: u8 = 0x5E;
pub const PUSH0: u8 = 0x5F;
pub const PUSH1: u8 = 0x60;
pub const PUSH2: u8 = 0x61;
pub const PUSH3: u8 = 0x62;
pub const PUSH4: u8 = 0x63;
pub const PUSH5: u8 = 0x64;
pub const PUSH6: u8 = 0x65;
pub const PUSH7: u8 = 0x66;
pub const PUSH8: u8 = 0x67;
pub const PUSH9: u8 = 0x68;
pub const PUSH10: u8 = 0x69;
pub const PUSH11: u8 = 0x6A;
pub const PUSH12: u8 = 0x6B;
pub const PUSH13: u8 = 0x6C;
pub const PUSH14: u8 = 0x6D;
pub const PUSH15: u8 = 0x6E;
pub const PUSH16: u8 = 0x6F;
pub const PUSH17: u8 = 0x70;
pub const PUSH18: u8 = 0x71;
pub const PUSH19: u8 = 0x72;
pub const PUSH20: u8 = 0x73;
pub const PUSH21: u8 = 0x74;
pub const PUSH22: u8 = 0x75;
pub const PUSH23: u8 = 0x76;
pub const PUSH24: u8 = 0x77;
pub const PUSH25: u8 = 0x78;
pub const PUSH26: u8 = 0x79;
pub const PUSH27: u8 = 0x7A;
pub const PUSH28: u8 = 0x7B;
pub const PUSH29: u8 = 0x7C;
pub const PUSH30: u8 = 0x7D;
pub const PUSH31: u8 = 0x7E;
pub const PUSH32: u8 = 0x7F;
pub const DUP1: u8 = 0x80;
pub const DUP2: u8 = 0x81;
pub const DUP3: u8 = 0x82;
pub const DUP4: u8 = 0x83;
pub const DUP5: u8 = 0x84;
pub const DUP6: u8 = 0x85;
pub const DUP7: u8 = 0x86;
pub const DUP8: u8 = 0x87;
pub const DUP9: u8 = 0x88;
pub const DUP10: u8 = 0x89;
pub const DUP11: u8 = 0x8A;
pub const DUP12: u8 = 0x8B;
pub const DUP13: u8 = 0x8C;
pub const DUP14: u8 = 0x8D;
pub const DUP15: u8 = 0x8E;
pub const DUP16: u8 = 0x8F;
pub const SWAP1: u8 = 0x90;
pub const SWAP2: u8 = 0x91;
pub const SWAP3: u8 = 0x92;
pub const SWAP4: u8 = 0x93;
pub const SWAP5: u8 = 0x94;
pub const SWAP6: u8 = 0x95;
pub const SWAP7: u8 = 0x96;
pub const SWAP8: u8 = 0x97;
pub const SWAP9: u8 = 0x98;
pub const SWAP10: u8 = 0x99;
pub const SWAP11: u8 = 0x9A;
pub const SWAP12: u8 = 0x9B;
pub const SWAP13: u8 = 0x9C;
pub const SWAP14: u8 = 0x9D;
pub const SWAP15: u8 = 0x9E;
pub const SWAP16: u8 = 0x9F;
pub const LOG0: u8 = 0xA0;
pub const LOG1: u8 = 0xA1;
pub const LOG2: u8 = 0xA2;
pub const LOG3: u8 = 0xA3;
pub const LOG4: u8 = 0xA4;
pub const CREATE: u8 = 0xF0;
pub const CALL: u8 = 0xF1;
pub const CALLCODE: u8 = 0xF2;
pub const RETURN: u8 = 0xF3;
pub const DELEGATECALL: u8 = 0xF4;
pub const CREATE2: u8 = 0xF5;
pub const STATICCALL: u8 = 0xFA;
pub const REVERT: u8 = 0xFD;
pub const INVALID: u8 = 0xFE;
pub const SELFDESTRUCT: u8 = 0xFF;

/// Maps each opcode to its info.
pub const OPCODE_INFO: [256]?OpCodeInfo = blk: {
    var map: [256]?OpCodeInfo = [_]?OpCodeInfo{null} ** 256;

    // Arithmetic operations
    map[STOP] = OpCodeInfo{ .name = "STOP", .inputs = 0, .outputs = 0, .immediate_size = 0, .terminating = true };
    map[ADD] = OpCodeInfo{ .name = "ADD", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[MUL] = OpCodeInfo{ .name = "MUL", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SUB] = OpCodeInfo{ .name = "SUB", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[DIV] = OpCodeInfo{ .name = "DIV", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SDIV] = OpCodeInfo{ .name = "SDIV", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[MOD] = OpCodeInfo{ .name = "MOD", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SMOD] = OpCodeInfo{ .name = "SMOD", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[ADDMOD] = OpCodeInfo{ .name = "ADDMOD", .inputs = 3, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[MULMOD] = OpCodeInfo{ .name = "MULMOD", .inputs = 3, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[EXP] = OpCodeInfo{ .name = "EXP", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SIGNEXTEND] = OpCodeInfo{ .name = "SIGNEXTEND", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };

    // Comparison operations
    map[LT] = OpCodeInfo{ .name = "LT", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[GT] = OpCodeInfo{ .name = "GT", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SLT] = OpCodeInfo{ .name = "SLT", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SGT] = OpCodeInfo{ .name = "SGT", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[EQ] = OpCodeInfo{ .name = "EQ", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[ISZERO] = OpCodeInfo{ .name = "ISZERO", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[AND] = OpCodeInfo{ .name = "AND", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[OR] = OpCodeInfo{ .name = "OR", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[XOR] = OpCodeInfo{ .name = "XOR", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[NOT] = OpCodeInfo{ .name = "NOT", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[BYTE] = OpCodeInfo{ .name = "BYTE", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SHL] = OpCodeInfo{ .name = "SHL", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SHR] = OpCodeInfo{ .name = "SHR", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SAR] = OpCodeInfo{ .name = "SAR", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CLZ] = OpCodeInfo{ .name = "CLZ", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };

    // Hash operations
    map[KECCAK256] = OpCodeInfo{ .name = "KECCAK256", .inputs = 2, .outputs = 1, .immediate_size = 0, .terminating = false };

    // Environment information
    map[ADDRESS] = OpCodeInfo{ .name = "ADDRESS", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[BALANCE] = OpCodeInfo{ .name = "BALANCE", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[ORIGIN] = OpCodeInfo{ .name = "ORIGIN", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALLER] = OpCodeInfo{ .name = "CALLER", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALLVALUE] = OpCodeInfo{ .name = "CALLVALUE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALLDATALOAD] = OpCodeInfo{ .name = "CALLDATALOAD", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALLDATASIZE] = OpCodeInfo{ .name = "CALLDATASIZE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALLDATACOPY] = OpCodeInfo{ .name = "CALLDATACOPY", .inputs = 3, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[CODESIZE] = OpCodeInfo{ .name = "CODESIZE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CODECOPY] = OpCodeInfo{ .name = "CODECOPY", .inputs = 3, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[GASPRICE] = OpCodeInfo{ .name = "GASPRICE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[EXTCODESIZE] = OpCodeInfo{ .name = "EXTCODESIZE", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[EXTCODECOPY] = OpCodeInfo{ .name = "EXTCODECOPY", .inputs = 4, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[RETURNDATASIZE] = OpCodeInfo{ .name = "RETURNDATASIZE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[RETURNDATACOPY] = OpCodeInfo{ .name = "RETURNDATACOPY", .inputs = 3, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[EXTCODEHASH] = OpCodeInfo{ .name = "EXTCODEHASH", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[BLOCKHASH] = OpCodeInfo{ .name = "BLOCKHASH", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[COINBASE] = OpCodeInfo{ .name = "COINBASE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[TIMESTAMP] = OpCodeInfo{ .name = "TIMESTAMP", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[NUMBER] = OpCodeInfo{ .name = "NUMBER", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[DIFFICULTY] = OpCodeInfo{ .name = "DIFFICULTY", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[GASLIMIT] = OpCodeInfo{ .name = "GASLIMIT", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CHAINID] = OpCodeInfo{ .name = "CHAINID", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SELFBALANCE] = OpCodeInfo{ .name = "SELFBALANCE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[BASEFEE] = OpCodeInfo{ .name = "BASEFEE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[BLOBHASH] = OpCodeInfo{ .name = "BLOBHASH", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[BLOBBASEFEE] = OpCodeInfo{ .name = "BLOBBASEFEE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };

    // Stack operations
    map[POP] = OpCodeInfo{ .name = "POP", .inputs = 1, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[MLOAD] = OpCodeInfo{ .name = "MLOAD", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[MSTORE] = OpCodeInfo{ .name = "MSTORE", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[MSTORE8] = OpCodeInfo{ .name = "MSTORE8", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[SLOAD] = OpCodeInfo{ .name = "SLOAD", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[SSTORE] = OpCodeInfo{ .name = "SSTORE", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[JUMP] = OpCodeInfo{ .name = "JUMP", .inputs = 1, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[JUMPI] = OpCodeInfo{ .name = "JUMPI", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[PC] = OpCodeInfo{ .name = "PC", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[MSIZE] = OpCodeInfo{ .name = "MSIZE", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[GAS] = OpCodeInfo{ .name = "GAS", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[JUMPDEST] = OpCodeInfo{ .name = "JUMPDEST", .inputs = 0, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[TLOAD] = OpCodeInfo{ .name = "TLOAD", .inputs = 1, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[TSTORE] = OpCodeInfo{ .name = "TSTORE", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[MCOPY] = OpCodeInfo{ .name = "MCOPY", .inputs = 3, .outputs = 0, .immediate_size = 0, .terminating = false };

    // Push operations
    map[PUSH0] = OpCodeInfo{ .name = "PUSH0", .inputs = 0, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[PUSH1] = OpCodeInfo{ .name = "PUSH1", .inputs = 0, .outputs = 1, .immediate_size = 1, .terminating = false };
    map[PUSH2] = OpCodeInfo{ .name = "PUSH2", .inputs = 0, .outputs = 1, .immediate_size = 2, .terminating = false };
    map[PUSH3] = OpCodeInfo{ .name = "PUSH3", .inputs = 0, .outputs = 1, .immediate_size = 3, .terminating = false };
    map[PUSH4] = OpCodeInfo{ .name = "PUSH4", .inputs = 0, .outputs = 1, .immediate_size = 4, .terminating = false };
    map[PUSH5] = OpCodeInfo{ .name = "PUSH5", .inputs = 0, .outputs = 1, .immediate_size = 5, .terminating = false };
    map[PUSH6] = OpCodeInfo{ .name = "PUSH6", .inputs = 0, .outputs = 1, .immediate_size = 6, .terminating = false };
    map[PUSH7] = OpCodeInfo{ .name = "PUSH7", .inputs = 0, .outputs = 1, .immediate_size = 7, .terminating = false };
    map[PUSH8] = OpCodeInfo{ .name = "PUSH8", .inputs = 0, .outputs = 1, .immediate_size = 8, .terminating = false };
    map[PUSH9] = OpCodeInfo{ .name = "PUSH9", .inputs = 0, .outputs = 1, .immediate_size = 9, .terminating = false };
    map[PUSH10] = OpCodeInfo{ .name = "PUSH10", .inputs = 0, .outputs = 1, .immediate_size = 10, .terminating = false };
    map[PUSH11] = OpCodeInfo{ .name = "PUSH11", .inputs = 0, .outputs = 1, .immediate_size = 11, .terminating = false };
    map[PUSH12] = OpCodeInfo{ .name = "PUSH12", .inputs = 0, .outputs = 1, .immediate_size = 12, .terminating = false };
    map[PUSH13] = OpCodeInfo{ .name = "PUSH13", .inputs = 0, .outputs = 1, .immediate_size = 13, .terminating = false };
    map[PUSH14] = OpCodeInfo{ .name = "PUSH14", .inputs = 0, .outputs = 1, .immediate_size = 14, .terminating = false };
    map[PUSH15] = OpCodeInfo{ .name = "PUSH15", .inputs = 0, .outputs = 1, .immediate_size = 15, .terminating = false };
    map[PUSH16] = OpCodeInfo{ .name = "PUSH16", .inputs = 0, .outputs = 1, .immediate_size = 16, .terminating = false };
    map[PUSH17] = OpCodeInfo{ .name = "PUSH17", .inputs = 0, .outputs = 1, .immediate_size = 17, .terminating = false };
    map[PUSH18] = OpCodeInfo{ .name = "PUSH18", .inputs = 0, .outputs = 1, .immediate_size = 18, .terminating = false };
    map[PUSH19] = OpCodeInfo{ .name = "PUSH19", .inputs = 0, .outputs = 1, .immediate_size = 19, .terminating = false };
    map[PUSH20] = OpCodeInfo{ .name = "PUSH20", .inputs = 0, .outputs = 1, .immediate_size = 20, .terminating = false };
    map[PUSH21] = OpCodeInfo{ .name = "PUSH21", .inputs = 0, .outputs = 1, .immediate_size = 21, .terminating = false };
    map[PUSH22] = OpCodeInfo{ .name = "PUSH22", .inputs = 0, .outputs = 1, .immediate_size = 22, .terminating = false };
    map[PUSH23] = OpCodeInfo{ .name = "PUSH23", .inputs = 0, .outputs = 1, .immediate_size = 23, .terminating = false };
    map[PUSH24] = OpCodeInfo{ .name = "PUSH24", .inputs = 0, .outputs = 1, .immediate_size = 24, .terminating = false };
    map[PUSH25] = OpCodeInfo{ .name = "PUSH25", .inputs = 0, .outputs = 1, .immediate_size = 25, .terminating = false };
    map[PUSH26] = OpCodeInfo{ .name = "PUSH26", .inputs = 0, .outputs = 1, .immediate_size = 26, .terminating = false };
    map[PUSH27] = OpCodeInfo{ .name = "PUSH27", .inputs = 0, .outputs = 1, .immediate_size = 27, .terminating = false };
    map[PUSH28] = OpCodeInfo{ .name = "PUSH28", .inputs = 0, .outputs = 1, .immediate_size = 28, .terminating = false };
    map[PUSH29] = OpCodeInfo{ .name = "PUSH29", .inputs = 0, .outputs = 1, .immediate_size = 29, .terminating = false };
    map[PUSH30] = OpCodeInfo{ .name = "PUSH30", .inputs = 0, .outputs = 1, .immediate_size = 30, .terminating = false };
    map[PUSH31] = OpCodeInfo{ .name = "PUSH31", .inputs = 0, .outputs = 1, .immediate_size = 31, .terminating = false };
    map[PUSH32] = OpCodeInfo{ .name = "PUSH32", .inputs = 0, .outputs = 1, .immediate_size = 32, .terminating = false };

    // Duplicate operations
    map[DUP1] = OpCodeInfo{ .name = "DUP1", .inputs = 1, .outputs = 2, .immediate_size = 0, .terminating = false };
    map[DUP2] = OpCodeInfo{ .name = "DUP2", .inputs = 2, .outputs = 3, .immediate_size = 0, .terminating = false };
    map[DUP3] = OpCodeInfo{ .name = "DUP3", .inputs = 3, .outputs = 4, .immediate_size = 0, .terminating = false };
    map[DUP4] = OpCodeInfo{ .name = "DUP4", .inputs = 4, .outputs = 5, .immediate_size = 0, .terminating = false };
    map[DUP5] = OpCodeInfo{ .name = "DUP5", .inputs = 5, .outputs = 6, .immediate_size = 0, .terminating = false };
    map[DUP6] = OpCodeInfo{ .name = "DUP6", .inputs = 6, .outputs = 7, .immediate_size = 0, .terminating = false };
    map[DUP7] = OpCodeInfo{ .name = "DUP7", .inputs = 7, .outputs = 8, .immediate_size = 0, .terminating = false };
    map[DUP8] = OpCodeInfo{ .name = "DUP8", .inputs = 8, .outputs = 9, .immediate_size = 0, .terminating = false };
    map[DUP9] = OpCodeInfo{ .name = "DUP9", .inputs = 9, .outputs = 10, .immediate_size = 0, .terminating = false };
    map[DUP10] = OpCodeInfo{ .name = "DUP10", .inputs = 10, .outputs = 11, .immediate_size = 0, .terminating = false };
    map[DUP11] = OpCodeInfo{ .name = "DUP11", .inputs = 11, .outputs = 12, .immediate_size = 0, .terminating = false };
    map[DUP12] = OpCodeInfo{ .name = "DUP12", .inputs = 12, .outputs = 13, .immediate_size = 0, .terminating = false };
    map[DUP13] = OpCodeInfo{ .name = "DUP13", .inputs = 13, .outputs = 14, .immediate_size = 0, .terminating = false };
    map[DUP14] = OpCodeInfo{ .name = "DUP14", .inputs = 14, .outputs = 15, .immediate_size = 0, .terminating = false };
    map[DUP15] = OpCodeInfo{ .name = "DUP15", .inputs = 15, .outputs = 16, .immediate_size = 0, .terminating = false };
    map[DUP16] = OpCodeInfo{ .name = "DUP16", .inputs = 16, .outputs = 17, .immediate_size = 0, .terminating = false };

    // Swap operations
    map[SWAP1] = OpCodeInfo{ .name = "SWAP1", .inputs = 2, .outputs = 2, .immediate_size = 0, .terminating = false };
    map[SWAP2] = OpCodeInfo{ .name = "SWAP2", .inputs = 3, .outputs = 3, .immediate_size = 0, .terminating = false };
    map[SWAP3] = OpCodeInfo{ .name = "SWAP3", .inputs = 4, .outputs = 4, .immediate_size = 0, .terminating = false };
    map[SWAP4] = OpCodeInfo{ .name = "SWAP4", .inputs = 5, .outputs = 5, .immediate_size = 0, .terminating = false };
    map[SWAP5] = OpCodeInfo{ .name = "SWAP5", .inputs = 6, .outputs = 6, .immediate_size = 0, .terminating = false };
    map[SWAP6] = OpCodeInfo{ .name = "SWAP6", .inputs = 7, .outputs = 7, .immediate_size = 0, .terminating = false };
    map[SWAP7] = OpCodeInfo{ .name = "SWAP7", .inputs = 8, .outputs = 8, .immediate_size = 0, .terminating = false };
    map[SWAP8] = OpCodeInfo{ .name = "SWAP8", .inputs = 9, .outputs = 9, .immediate_size = 0, .terminating = false };
    map[SWAP9] = OpCodeInfo{ .name = "SWAP9", .inputs = 10, .outputs = 10, .immediate_size = 0, .terminating = false };
    map[SWAP10] = OpCodeInfo{ .name = "SWAP10", .inputs = 11, .outputs = 11, .immediate_size = 0, .terminating = false };
    map[SWAP11] = OpCodeInfo{ .name = "SWAP11", .inputs = 12, .outputs = 12, .immediate_size = 0, .terminating = false };
    map[SWAP12] = OpCodeInfo{ .name = "SWAP12", .inputs = 13, .outputs = 13, .immediate_size = 0, .terminating = false };
    map[SWAP13] = OpCodeInfo{ .name = "SWAP13", .inputs = 14, .outputs = 14, .immediate_size = 0, .terminating = false };
    map[SWAP14] = OpCodeInfo{ .name = "SWAP14", .inputs = 15, .outputs = 15, .immediate_size = 0, .terminating = false };
    map[SWAP15] = OpCodeInfo{ .name = "SWAP15", .inputs = 16, .outputs = 16, .immediate_size = 0, .terminating = false };
    map[SWAP16] = OpCodeInfo{ .name = "SWAP16", .inputs = 17, .outputs = 17, .immediate_size = 0, .terminating = false };

    // Logging operations
    map[LOG0] = OpCodeInfo{ .name = "LOG0", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[LOG1] = OpCodeInfo{ .name = "LOG1", .inputs = 3, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[LOG2] = OpCodeInfo{ .name = "LOG2", .inputs = 4, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[LOG3] = OpCodeInfo{ .name = "LOG3", .inputs = 5, .outputs = 0, .immediate_size = 0, .terminating = false };
    map[LOG4] = OpCodeInfo{ .name = "LOG4", .inputs = 6, .outputs = 0, .immediate_size = 0, .terminating = false };

    // System operations
    map[CREATE] = OpCodeInfo{ .name = "CREATE", .inputs = 3, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALL] = OpCodeInfo{ .name = "CALL", .inputs = 7, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CALLCODE] = OpCodeInfo{ .name = "CALLCODE", .inputs = 7, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[RETURN] = OpCodeInfo{ .name = "RETURN", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = true };
    map[DELEGATECALL] = OpCodeInfo{ .name = "DELEGATECALL", .inputs = 6, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[CREATE2] = OpCodeInfo{ .name = "CREATE2", .inputs = 4, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[STATICCALL] = OpCodeInfo{ .name = "STATICCALL", .inputs = 6, .outputs = 1, .immediate_size = 0, .terminating = false };
    map[REVERT] = OpCodeInfo{ .name = "REVERT", .inputs = 2, .outputs = 0, .immediate_size = 0, .terminating = true };
    map[INVALID] = OpCodeInfo{ .name = "INVALID", .inputs = 0, .outputs = 0, .immediate_size = 0, .terminating = true };
    map[SELFDESTRUCT] = OpCodeInfo{ .name = "SELFDESTRUCT", .inputs = 1, .outputs = 0, .immediate_size = 0, .terminating = true };

    break :blk map;
};

/// Main bytecode structure with all variants.
pub const Bytecode = union(enum) {
    /// EIP-7702 delegated bytecode
    eip7702: Eip7702Bytecode,
    /// The bytecode has been analyzed for valid jump destinations.
    legacy_analyzed: LegacyAnalyzedBytecode,

    const Self = @This();

    /// Creates a new legacy analyzed Bytecode with exactly one STOP opcode.
    pub fn new() Self {
        return Self{ .legacy_analyzed = LegacyAnalyzedBytecode.default() };
    }

    /// Returns jump table if bytecode is analyzed.
    pub fn legacyJumpTable(self: *const Self) ?*const JumpTable {
        return switch (self.*) {
            .legacy_analyzed => &self.legacy_analyzed.jump_table,
            else => null,
        };
    }

    /// Calculates hash of the bytecode.
    pub fn hashSlow(self: Self) primitives.Hash {
        switch (self) {
            .eip7702 => |eip7702| {
                // Hash the 23-byte delegation pointer directly from the switch-arm copy.
                // Avoids the dangling-pointer that arises when routing through raw() which
                // takes Self by value and returns &self.raw_bytes into its own stack frame.
                var hash: primitives.Hash = undefined;
                std.crypto.hash.sha3.Keccak256.hash(&eip7702.raw_bytes, &hash, .{});
                return hash;
            },
            .legacy_analyzed => {
                if (self.isEmpty()) {
                    return primitives.KECCAK_EMPTY;
                }
                const bytes = self.originalBytes();
                var hash: primitives.Hash = undefined;
                std.crypto.hash.sha3.Keccak256.hash(bytes, &hash, .{});
                return hash;
            },
        }
    }

    /// Returns true if bytecode is EIP-7702.
    pub fn isEip7702(self: Self) bool {
        return switch (self) {
            .eip7702 => true,
            else => false,
        };
    }

    /// Creates a new legacy Bytecode.
    pub fn newLegacy(raw: []const u8) Self {
        return Self{ .legacy_analyzed = LegacyRawBytecode.init(raw).intoAnalyzed() };
    }

    /// Returns a reference to the bytecode.
    pub fn bytecode(self: Self) []const u8 {
        return switch (self) {
            .legacy_analyzed => |analyzed| analyzed.getBytecode(),
            .eip7702 => |code| code.raw(),
        };
    }

    /// Returns raw bytes slice.
    pub fn bytesSlice(self: Self) []const u8 {
        return self.bytecode();
    }

    /// Returns the original bytecode.
    pub fn originalBytes(self: Self) []const u8 {
        return switch (self) {
            .legacy_analyzed => |analyzed| analyzed.originalBytes(),
            .eip7702 => |eip7702| eip7702.raw(),
        };
    }

    /// Returns the original bytecode as a byte slice.
    pub fn originalByteSlice(self: Self) []const u8 {
        return self.originalBytes();
    }

    /// Returns the length of the original bytes.
    pub fn len(self: Self) usize {
        return self.originalByteSlice().len;
    }

    /// Returns whether the bytecode is empty.
    pub fn isEmpty(self: Self) bool {
        return self.len() == 0;
    }

    /// Returns true if the given position is a valid JUMPDEST.
    pub fn isValidJump(self: Self, dest: usize) bool {
        return switch (self) {
            .legacy_analyzed => |analyzed| analyzed.jump_table.isValid(dest),
            .eip7702 => false,
        };
    }

    /// Creates a new legacy Bytecode from raw bytes (alias for newLegacy).
    pub fn newRaw(raw: []const u8) Self {
        return Self.newLegacy(raw);
    }

    /// Free any heap memory owned by this Bytecode (the jump table bit vector for legacy analyzed).
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .legacy_analyzed => |*bc| bc.deinit(),
            .eip7702 => {}, // 23-byte inline array, no heap allocation
        }
    }
};

/// Legacy analyzed bytecode with jump table
pub const LegacyAnalyzedBytecode = struct {
    bytecode: []const u8,
    original_len: usize,
    jump_table: JumpTable,

    const Self = @This();

    pub fn default() Self {
        return Self{
            .bytecode = &[_]u8{STOP},
            .original_len = 0,
            .jump_table = JumpTable.fromBytes(&[_]u8{0}, 1),
        };
    }

    pub fn getBytecode(self: Self) []const u8 {
        return self.bytecode;
    }

    pub fn originalBytes(self: Self) []const u8 {
        return self.bytecode[0..self.original_len];
    }

    pub fn deinit(self: *LegacyAnalyzedBytecode) void {
        // The bit vector is heap-allocated via c_allocator only when original_len > 0
        // (non-empty bytecode) AND the allocation succeeded (data.len > 0).
        // Cases that must NOT be freed:
        //   - default() / empty input: original_len == 0, data is a static &[_]u8{0}
        //   - alloc-failure fallback: jump_table.data.len == 0, data is static &[_]u8{}
        if (self.original_len > 0 and self.jump_table.data.len > 0) {
            std.heap.c_allocator.free(self.jump_table.data);
        }
    }
};

/// Legacy raw bytecode
pub const LegacyRawBytecode = struct {
    bytecode: []const u8,

    const Self = @This();

    pub fn init(bytecode: []const u8) Self {
        return Self{ .bytecode = bytecode };
    }

    pub fn intoAnalyzed(self: Self) LegacyAnalyzedBytecode {
        return analyzeLegacy(self.bytecode);
    }

};

/// EIP-7702 bytecode
pub const Eip7702Bytecode = struct {
    address: primitives.Address,
    version: u8,
    raw_bytes: [23]u8,

    const Self = @This();

    pub fn new(address: primitives.Address) Self {
        // EIP-7702 format: 0xEF01 (magic) + 0x00 (version) + 20 bytes (address) = 23 bytes total
        var raw_bytes: [23]u8 = undefined;
        raw_bytes[0] = 0xEF;
        raw_bytes[1] = 0x01; // Magic bytes
        raw_bytes[2] = 0x00; // Version (currently only version 0 is supported)
        @memcpy(raw_bytes[3..], &address);
        return Self{
            .address = address,
            .version = 0,
            .raw_bytes = raw_bytes,
        };
    }

    pub fn raw(self: Self) []const u8 {
        return &self.raw_bytes;
    }
};

/// Jump table for bytecode analysis
/// A table of valid `jump` destinations.
/// It is immutable, cheap to clone and memory efficient, with one bit per byte in the bytecode.
pub const JumpTable = struct {
    /// Bit vector data (one bit per bytecode position)
    data: []const u8,
    /// Number of bits in the table
    bit_len: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{ .data = &[_]u8{}, .bit_len = 0 };
    }

    /// Create new JumpTable from raw bytes and bit length
    pub fn fromBytes(data: []const u8, bit_len: usize) Self {
        return Self{ .data = data, .bit_len = bit_len };
    }

    /// Checks if `pc` is a valid jump destination.
    /// Uses bit operations for faster access
    pub fn isValid(self: Self, pc: usize) bool {
        if (pc >= self.bit_len) return false;
        const byte_idx = pc >> 3;
        const bit_idx = pc & 7;
        if (byte_idx >= self.data.len) return false;
        return (self.data[byte_idx] & (@as(u8, 1) << @intCast(bit_idx))) != 0;
    }

    /// Gets the length of the jump map in bits
    pub fn len(self: Self) usize {
        return self.bit_len;
    }

    /// Returns true if the jump map is empty
    pub fn isEmpty(self: Self) bool {
        return self.bit_len == 0;
    }
};

/// Analyzes the bytecode for use in LegacyAnalyzedBytecode.
/// The jump table bit vector is heap-allocated to avoid dangling stack pointers.
fn analyzeLegacy(bytecode: []const u8) LegacyAnalyzedBytecode {
    if (bytecode.len == 0) {
        return LegacyAnalyzedBytecode{
            .bytecode = &[_]u8{STOP},
            .original_len = 0,
            .jump_table = JumpTable.fromBytes(&[_]u8{0}, 1),
        };
    }

    // Allocate bit vector on heap (one bit per bytecode position) to avoid dangling pointer
    const bit_vec_len = (bytecode.len + 7) / 8;
    const bit_vec = std.heap.c_allocator.alloc(u8, bit_vec_len) catch {
        // Allocation failed: return bytecode with empty jump table
        return LegacyAnalyzedBytecode{
            .bytecode = bytecode,
            .original_len = bytecode.len,
            .jump_table = JumpTable.init(),
        };
    };
    @memset(bit_vec, 0);

    var i: usize = 0;

    // Analyze bytecode to find JUMPDEST positions
    while (i < bytecode.len) {
        const opcode = bytecode[i];

        if (opcode == JUMPDEST) {
            const byte_idx = i >> 3;
            const bit_idx = i & 7;
            bit_vec[byte_idx] |= @as(u8, 1) << @intCast(bit_idx);
            i += 1;
        } else {
            // Check if it's a PUSH instruction
            const push_offset = opcode -% PUSH1;
            if (push_offset < 32) {
                // PUSH1 through PUSH32: skip opcode + immediate bytes
                i += @as(usize, push_offset) + 2;
            } else {
                // Other opcodes: skip just the opcode
                i += 1;
            }
        }
    }

    return LegacyAnalyzedBytecode{
        .bytecode = bytecode,
        .original_len = bytecode.len,
        .jump_table = JumpTable.fromBytes(bit_vec, bytecode.len),
    };
}

/// Error type for bytecode decoding
pub const BytecodeDecodeError = error{
    InvalidFormat,
    InvalidMagicBytes,
    InvalidLength,
};

/// Test module for bytecode
pub const testing = struct {
    pub fn testOpcode() !void {
        const opcode = OpCode.new(STOP) orelse return error.TestFailed;
        try std.testing.expect(!opcode.isJumpdest());
        try std.testing.expect(!opcode.isJump());
        try std.testing.expect(!opcode.isPush());
        try std.testing.expectEqualStrings("STOP", opcode.asStr());
        try std.testing.expectEqual(STOP, opcode.get());
    }

    pub fn testBytecode() !void {
        const bytecode = Bytecode.new();
        try std.testing.expect(!bytecode.isEmpty());
        try std.testing.expectEqual(@as(usize, 1), bytecode.len());
    }
};
