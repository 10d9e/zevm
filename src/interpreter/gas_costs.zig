const std = @import("std");
const primitives = @import("primitives");

// Base gas costs
pub const G_ZERO = 0;
pub const G_BASE = 2;
pub const G_VERYLOW = 3;
pub const G_LOW = 5;
pub const G_MID = 8;
pub const G_HIGH = 10;

// Special operation costs
pub const G_JUMPDEST = 1;
pub const G_SSET = 20000; // Storage set (from zero to non-zero)
pub const G_SRESET = 5000; // Storage reset (non-zero to non-zero or zero)

// Call costs
pub const G_CALL_FRONTIER = 40; // Frontier/Homestead CALL base gas
pub const G_CALL = 700;         // Tangerine+ (EIP-150) through pre-Berlin CALL base gas
pub const COLD_ACCOUNT_ACCESS = 2600;
pub const WARM_ACCOUNT_ACCESS = 100;
pub const COLD_SLOAD = 2100;
pub const WARM_SLOAD = 100;
pub const CALL_STIPEND = 2300; // Gas gifted to callee on value-bearing CALL (not deducted from caller)

// Storage costs - Pre-Berlin
pub const G_SLOAD_FRONTIER = 50;   // Frontier/Homestead SLOAD gas
pub const G_SLOAD_TANGERINE = 200; // Tangerine (EIP-150) through pre-Istanbul SLOAD gas
pub const G_SLOAD_ISTANBUL = 800;  // Istanbul (EIP-1884) SLOAD gas

// Storage costs - Berlin and later (EIP-2929)
pub const G_SLOAD_BERLIN_COLD = 2100;
pub const G_SLOAD_BERLIN_WARM = 100;

// SSTORE costs (EIP-2200, EIP-2929)
pub const SSTORE_SET = 20000;
pub const SSTORE_RESET = 5000;
pub const SSTORE_CLEARS_SCHEDULE = 15000; // Refund for clearing storage

// Create costs
pub const G_CREATE = 32000;
pub const G_CODEDEPOSIT = 200; // Per byte of deployed code

// Transaction costs
pub const G_TRANSACTION = 21000;
pub const G_TXCREATE = 32000;
pub const G_TXDATAZERO = 4;
pub const G_TXDATANONZERO = 16; // Pre-Istanbul
pub const G_TXDATANONZERO_ISTANBUL = 16; // Actually same
pub const G_TXDATANONZERO_EIP2028 = 16; // After EIP-2028

// Memory expansion cost
pub const G_MEMORY = 3; // Per word

// Copy operations
pub const G_COPY = 3; // Per word

// Log costs
pub const G_LOG = 375;
pub const G_LOGDATA = 8;
pub const G_LOGTOPIC = 375;

// SHA3/Keccak costs
pub const G_KECCAK256 = 30;
pub const G_KECCAK256WORD = 6;

// EXP costs
pub const G_EXP = 10;
pub const G_EXPBYTE = 50;           // Post-Spurious Dragon (EIP-160)
pub const G_EXPBYTE_FRONTIER = 10;  // Pre-Spurious Dragon

// SELFDESTRUCT
pub const G_SELFDESTRUCT = 5000;
pub const R_SELFDESTRUCT = 24000; // Refund

// Memory expansion cost formula
// cost = memory_size_word * G_MEMORY + (memory_size_word ^ 2) / 512
pub fn memoryExpansionCost(current_words: usize, new_words: usize) u64 {
    if (new_words <= current_words) return 0;

    const new_cost = memoryCost(new_words);
    const current_cost = memoryCost(current_words);

    return new_cost - current_cost;
}

fn memoryCost(num_words: usize) u64 {
    const linear = num_words * G_MEMORY;
    const quadratic = (num_words * num_words) / 512;
    return @intCast(linear + quadratic);
}

// Calculate memory size in words (rounded up)
pub fn toWordSize(size: usize) usize {
    return (size + 31) / 32;
}

// Get SLOAD gas cost based on spec and cold/warm access
pub fn getSloadCost(spec: primitives.SpecId, is_cold: bool) u64 {
    return switch (spec) {
        .frontier, .homestead => G_SLOAD_FRONTIER,
        .tangerine, .spurious, .byzantium, .constantinople, .petersburg => G_SLOAD_TANGERINE,
        .istanbul, .muir_glacier => G_SLOAD_ISTANBUL,
        .berlin, .london, .arrow_glacier, .gray_glacier => {
            return if (is_cold) G_SLOAD_BERLIN_COLD else G_SLOAD_BERLIN_WARM;
        },
        .merge, .shanghai, .cancun, .prague, .osaka, .amsterdam => {
            return if (is_cold) G_SLOAD_BERLIN_COLD else G_SLOAD_BERLIN_WARM;
        },
    };
}

// SSTORE gas cost result
pub const SstoreGas = struct {
    gas_cost: u64,
    gas_refund: i64,
};

// Calculate SSTORE gas cost based on EIP-2200 and EIP-2929
pub fn getSstoreCost(
    spec: primitives.SpecId,
    original: primitives.U256,
    current: primitives.U256,
    new: primitives.U256,
    is_cold: bool,
) SstoreGas {
    // Pre-Istanbul: simple gas model
    if (!primitives.isEnabledIn(spec, .istanbul)) {
        if (current == new) {
            return .{ .gas_cost = WARM_SLOAD, .gas_refund = 0 };
        }

        if (original == current and original == 0) {
            return .{ .gas_cost = SSTORE_SET, .gas_refund = 0 };
        }

        if (original == current) {
            return .{ .gas_cost = SSTORE_RESET, .gas_refund = 0 };
        }

        // Modifying already modified slot
        return .{ .gas_cost = WARM_SLOAD, .gas_refund = 0 };
    }

    // EIP-2200 (Istanbul) and EIP-2929 (Berlin) gas model
    const cold_cost: u64 = if (primitives.isEnabledIn(spec, .berlin) and is_cold) COLD_SLOAD else 0;

    // EIP-2929: Berlin+ reduces the base SSTORE_RESET by COLD_SLOAD to avoid
    // double-counting when cold_cost is separately added. Pre-Berlin uses 5000.
    const sstore_reset_cost: u64 = if (primitives.isEnabledIn(spec, .berlin)) SSTORE_RESET - COLD_SLOAD else SSTORE_RESET;

    if (current == new) {
        // No change
        return .{ .gas_cost = WARM_SLOAD + cold_cost, .gas_refund = 0 };
    }

    if (original == current) {
        // First time modification in transaction
        if (original == 0) {
            // Setting from zero
            return .{ .gas_cost = SSTORE_SET + cold_cost, .gas_refund = 0 };
        } else {
            // Modifying non-zero value
            if (new == 0) {
                // Clearing storage - provide refund
                const refund = if (primitives.isEnabledIn(spec, .london))
                    @as(i64, SSTORE_CLEARS_SCHEDULE) - @as(i64, COLD_SLOAD)
                else
                    @as(i64, SSTORE_CLEARS_SCHEDULE);
                return .{ .gas_cost = sstore_reset_cost + cold_cost, .gas_refund = refund };
            } else {
                // Non-zero to non-zero
                return .{ .gas_cost = sstore_reset_cost + cold_cost, .gas_refund = 0 };
            }
        }
    }

    // Subsequent modification (dirty)
    var refund: i64 = 0;

    if (original != 0) {
        if (current == 0) {
            // Previously cleared, now setting
            refund -= SSTORE_CLEARS_SCHEDULE;
        } else if (new == 0) {
            // Now clearing
            refund += SSTORE_CLEARS_SCHEDULE;
        }
    }

    if (original == new) {
        // Restoring original value
        if (original == 0) {
            refund += SSTORE_SET - WARM_SLOAD;
        } else {
            refund += @as(i64, @intCast(sstore_reset_cost - WARM_SLOAD));
        }
    }

    return .{ .gas_cost = WARM_SLOAD + cold_cost, .gas_refund = refund };
}

// Calculate call gas cost
pub fn getCallGasCost(
    spec: primitives.SpecId,
    is_cold: bool,
    transfers_value: bool,
    account_exists: bool,
) u64 {
    // Base access cost:
    //   Berlin+ (EIP-2929): cold/warm account access replaces the flat G_CALL
    //   Tangerine+ (EIP-150) through pre-Berlin: flat 700
    //   Frontier/Homestead (pre-Tangerine): flat 40
    var cost: u64 = if (primitives.isEnabledIn(spec, .berlin))
        (if (is_cold) COLD_ACCOUNT_ACCESS else WARM_ACCOUNT_ACCESS)
    else if (primitives.isEnabledIn(spec, .tangerine))
        G_CALL
    else
        G_CALL_FRONTIER;

    // Value transfer cost (G_CALLVALUE = 9000, unchanged across all forks)
    if (transfers_value) {
        cost += 9000;
        // New account creation cost (G_NEWACCOUNT = 25000)
        if (!account_exists) {
            cost += 25000;
        }
    }

    return cost;
}
