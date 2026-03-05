// Arithmetic operations
pub const arithmetic = @import("arithmetic.zig");
pub const opAdd = arithmetic.opAdd;
pub const opSub = arithmetic.opSub;
pub const opMul = arithmetic.opMul;
pub const opDiv = arithmetic.opDiv;
pub const opSdiv = arithmetic.opSdiv;
pub const opMod = arithmetic.opMod;
pub const opSmod = arithmetic.opSmod;
pub const opAddmod = arithmetic.opAddmod;
pub const opMulmod = arithmetic.opMulmod;
pub const opExp = arithmetic.opExp;
pub const opSignextend = arithmetic.opSignextend;

// Bitwise operations
pub const bitwise = @import("bitwise.zig");
pub const opAnd = bitwise.opAnd;
pub const opOr = bitwise.opOr;
pub const opXor = bitwise.opXor;
pub const opNot = bitwise.opNot;
pub const opByte = bitwise.opByte;
pub const opShl = bitwise.opShl;
pub const opShr = bitwise.opShr;
pub const opSar = bitwise.opSar;

// Comparison operations
pub const comparison = @import("comparison.zig");
pub const opLt = comparison.opLt;
pub const opGt = comparison.opGt;
pub const opSlt = comparison.opSlt;
pub const opSgt = comparison.opSgt;
pub const opEq = comparison.opEq;
pub const opIsZero = comparison.opIsZero;

// Stack operations
pub const stack = @import("stack.zig");
pub const opPop = stack.opPop;
pub const opPush0 = stack.opPush0;
pub const opPushN = stack.opPushN;
pub const opDupN = stack.opDupN;
pub const opSwapN = stack.opSwapN;

// Control flow operations
pub const control = @import("control.zig");
pub const opStop = control.opStop;
pub const opJump = control.opJump;
pub const opJumpi = control.opJumpi;
pub const opJumpdest = control.opJumpdest;
pub const opPc = control.opPc;
pub const opGas = control.opGas;

// Memory operations
pub const memory = @import("memory.zig");
pub const opMload = memory.opMload;
pub const opMstore = memory.opMstore;
pub const opMstore8 = memory.opMstore8;
pub const opMsize = memory.opMsize;
pub const opMcopy = memory.opMcopy;

// Keccak256 operation
pub const keccak = @import("keccak.zig");
pub const opKeccak256 = keccak.opKeccak256;

// Gas constants
pub const GAS_BASE = stack.GAS_BASE;
pub const GAS_VERYLOW = arithmetic.GAS_VERYLOW;
pub const GAS_LOW = arithmetic.GAS_LOW;
pub const GAS_MID = arithmetic.GAS_MID;
pub const GAS_HIGH = control.GAS_HIGH;
pub const GAS_JUMPDEST = control.GAS_JUMPDEST;
pub const GAS_EXP = arithmetic.GAS_EXP;
pub const GAS_EXP_BYTE = arithmetic.GAS_EXP_BYTE;
pub const GAS_KECCAK256 = keccak.GAS_KECCAK256;
pub const GAS_KECCAK256WORD = keccak.GAS_KECCAK256WORD;
pub const GAS_MEMORY = memory.GAS_MEMORY;
