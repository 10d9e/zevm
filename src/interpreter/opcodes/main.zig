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

// Stack operations — comptime generators for PUSH/DUP/SWAP families
pub const stack = @import("stack.zig");
pub const opPop = stack.opPop;
pub const opPush0 = stack.opPush0;
pub const makePushFn = stack.makePushFn;
pub const makeDupFn = stack.makeDupFn;
pub const makeSwapFn = stack.makeSwapFn;

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

// Environment opcodes (block/tx info, calldata, code access)
pub const environment = @import("environment.zig");
pub const opAddress = environment.opAddress;
pub const opCaller = environment.opCaller;
pub const opCallvalue = environment.opCallvalue;
pub const opCalldatasize = environment.opCalldatasize;
pub const opCalldataload = environment.opCalldataload;
pub const opCalldatacopy = environment.opCalldatacopy;
pub const opCodesize = environment.opCodesize;
pub const opCodecopy = environment.opCodecopy;
pub const opReturndatasize = environment.opReturndatasize;
pub const opReturndatacopy = environment.opReturndatacopy;
pub const opOrigin = environment.opOrigin;
pub const opGasprice = environment.opGasprice;
pub const opCoinbase = environment.opCoinbase;
pub const opTimestamp = environment.opTimestamp;
pub const opNumber = environment.opNumber;
pub const opDifficulty = environment.opDifficulty;
pub const opGaslimit = environment.opGaslimit;
pub const opChainid = environment.opChainid;
pub const opBasefee = environment.opBasefee;
pub const opBlobhash = environment.opBlobhash;
pub const opBlobbasefee = environment.opBlobbasefee;

// Host-requiring opcodes (account state, storage, logs, selfdestruct)
pub const host_ops = @import("host_ops.zig");
pub const opBalance = host_ops.opBalance;
pub const opSelfbalance = host_ops.opSelfbalance;
pub const opExtcodesize = host_ops.opExtcodesize;
pub const opExtcodecopy = host_ops.opExtcodecopy;
pub const opExtcodehash = host_ops.opExtcodehash;
pub const opBlockhash = host_ops.opBlockhash;
pub const opSload = host_ops.opSload;
pub const opSstore = host_ops.opSstore;
pub const opTload = host_ops.opTload;
pub const opTstore = host_ops.opTstore;
pub const opLog0 = host_ops.opLog0;
pub const opLog1 = host_ops.opLog1;
pub const opLog2 = host_ops.opLog2;
pub const opLog3 = host_ops.opLog3;
pub const opLog4 = host_ops.opLog4;
pub const opSelfdestruct = host_ops.opSelfdestruct;

// System opcodes (RETURN, REVERT, INVALID)
pub const system = @import("system.zig");
pub const opReturn = system.opReturn;
pub const opRevert = system.opRevert;
pub const opInvalid = system.opInvalid;

// Call family opcodes
pub const call_ops = @import("call.zig");
pub const opCall = call_ops.opCall;
pub const opCallcode = call_ops.opCallcode;
pub const opDelegatecall = call_ops.opDelegatecall;
pub const opStaticcall = call_ops.opStaticcall;
pub const opCreate = call_ops.opCreate;
pub const opCreate2 = call_ops.opCreate2;

// Gas constants re-exported from the single source of truth
const gas_costs = @import("../gas_costs.zig");
pub const GAS_BASE = gas_costs.G_BASE;
pub const GAS_VERYLOW = gas_costs.G_VERYLOW;
pub const GAS_LOW = gas_costs.G_LOW;
pub const GAS_MID = gas_costs.G_MID;
pub const GAS_HIGH = gas_costs.G_HIGH;
pub const GAS_JUMPDEST = gas_costs.G_JUMPDEST;
pub const GAS_EXP = gas_costs.G_EXP;
pub const GAS_EXP_BYTE = gas_costs.G_EXPBYTE;
pub const GAS_KECCAK256 = gas_costs.G_KECCAK256;
pub const GAS_KECCAK256WORD = gas_costs.G_KECCAK256WORD;
pub const GAS_MEMORY = gas_costs.G_MEMORY;
