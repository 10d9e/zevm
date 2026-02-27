const std = @import("std");
const primitives = @import("primitives");

/// Represents the state of gas during execution.
pub const Gas = struct {
    /// The initial gas limit. This is constant throughout execution.
    limit: u64,
    /// The remaining gas.
    remaining: u64,
    /// Refunded gas. This is used only at the end of execution.
    refunded: i64,
    /// Memoisation of values for memory expansion cost.
    memory: MemoryGas,

    /// Creates a new `Gas` struct with the given gas limit.
    pub fn new(limit: u64) Gas {
        return Gas{
            .limit = limit,
            .remaining = limit,
            .refunded = 0,
            .memory = MemoryGas.new(),
        };
    }

    /// Creates a new `Gas` struct with the given gas limit, but without any gas remaining.
    pub fn newSpent(limit: u64) Gas {
        return Gas{
            .limit = limit,
            .remaining = 0,
            .refunded = 0,
            .memory = MemoryGas.new(),
        };
    }

    /// Returns the gas limit.
    pub fn getLimit(self: Gas) u64 {
        return self.limit;
    }

    /// Returns the memory gas.
    pub fn getMemory(self: Gas) MemoryGas {
        return self.memory;
    }

    /// Returns the memory gas mutably.
    pub fn getMemoryMut(self: *Gas) *MemoryGas {
        return &self.memory;
    }

    /// Returns the total amount of gas that was refunded.
    pub fn getRefunded(self: Gas) i64 {
        return self.refunded;
    }

    /// Returns the total amount of gas spent.
    pub fn getSpent(self: Gas) u64 {
        return self.limit - self.remaining;
    }

    /// Returns the final amount of gas used by subtracting the refund from spent gas.
    pub fn getUsed(self: Gas) u64 {
        const used = self.getSpent();
        const refund_amount = @as(u64, @intCast(@max(0, self.refunded)));
        return if (used > refund_amount) used - refund_amount else 0;
    }

    /// Returns the remaining gas.
    pub fn getRemaining(self: Gas) u64 {
        return self.remaining;
    }

    /// Spend gas
    pub fn spend(self: *Gas, amount: u64) bool {
        if (self.remaining < amount) {
            return false;
        }
        self.remaining -= amount;
        return true;
    }

    /// Spend all remaining gas
    pub fn spendAll(self: *Gas) void {
        self.remaining = 0;
    }

    /// Refund gas
    pub fn refund(self: *Gas, amount: u64) void {
        self.refunded += @as(i64, @intCast(amount));
    }

    /// Record gas refund
    pub fn recordRefund(self: *Gas, amount: u64) void {
        self.refunded += @as(i64, @intCast(amount));
    }

    /// Erase gas refund
    pub fn eraseRefund(self: *Gas) void {
        self.refunded = 0;
    }

    /// Load gas
    pub fn loadGas(self: *Gas, amount: u64) void {
        self.remaining = amount;
    }

    /// Load gas with limit
    pub fn loadGasWithLimit(self: *Gas, amount: u64, limit: u64) void {
        self.remaining = @min(amount, limit);
    }

    /// Load gas with limit and refund
    pub fn loadGasWithLimitAndRefund(self: *Gas, amount: u64, limit: u64, refund_amount: i64) void {
        self.remaining = @min(amount, limit);
        self.refunded = refund_amount;
    }

    /// Load gas with refund
    pub fn loadGasWithRefund(self: *Gas, amount: u64, refund_amount: i64) void {
        self.remaining = amount;
        self.refunded = refund_amount;
    }

    /// Load gas with memory
    pub fn loadGasWithMemory(self: *Gas, amount: u64, memory: MemoryGas) void {
        self.remaining = amount;
        self.memory = memory;
    }

    /// Load gas with memory and refund
    pub fn loadGasWithMemoryAndRefund(self: *Gas, amount: u64, memory: MemoryGas, refund_amount: i64) void {
        self.remaining = amount;
        self.memory = memory;
        self.refunded = refund_amount;
    }

    /// Load gas with limit and memory
    pub fn loadGasWithLimitAndMemory(self: *Gas, amount: u64, limit: u64, memory: MemoryGas) void {
        self.remaining = @min(amount, limit);
        self.memory = memory;
    }

    /// Load gas with limit, memory and refund
    pub fn loadGasWithLimitMemoryAndRefund(self: *Gas, amount: u64, limit: u64, memory: MemoryGas, refund_amount: i64) void {
        self.remaining = @min(amount, limit);
        self.memory = memory;
        self.refunded = refund_amount;
    }

    /// Apply EIP-3529 refund cap in-place.
    /// Pre-London: cap at gas_spent / 2. London+: cap at gas_spent / 5.
    pub fn setFinalRefund(self: *Gas, is_london: bool) void {
        const quotient: u64 = if (is_london) 5 else 2;
        const spent = self.getSpent();
        const raw = @as(u64, @intCast(@max(0, self.refunded)));
        self.refunded = @as(i64, @intCast(@min(raw, spent / quotient)));
    }

    /// Returns gas_spent − capped_refund (never negative). Used by EIP-7623 check.
    pub fn spentSubRefunded(self: Gas) u64 {
        const spent = self.getSpent();
        const ref = @as(u64, @intCast(@max(0, self.refunded)));
        return if (spent > ref) spent - ref else 0;
    }
};

/// Memory gas tracking for memory expansion costs
pub const MemoryGas = struct {
    /// The current memory size in words
    size: u64,
    /// The maximum memory size reached during execution
    max_size: u64,

    pub fn new() MemoryGas {
        return MemoryGas{
            .size = 0,
            .max_size = 0,
        };
    }

    /// Get the current memory size in words
    pub fn getSize(self: MemoryGas) u64 {
        return self.size;
    }

    /// Get the maximum memory size reached
    pub fn maxSize(self: MemoryGas) u64 {
        return self.max_size;
    }

    /// Set the memory size
    pub fn setSize(self: *MemoryGas, size: u64) void {
        self.size = size;
        self.max_size = @max(self.max_size, size);
    }

    /// Calculate memory expansion cost
    pub fn expansionCost(self: MemoryGas, new_size: u64) u64 {
        if (new_size <= self.size) {
            return 0;
        }

        const new_words = (new_size + 31) / 32;
        const current_words = (self.size + 31) / 32;

        if (new_words <= current_words) {
            return 0;
        }

        const cost = (new_words * new_words) / 512 + (3 * new_words);
        const current_cost = (current_words * current_words) / 512 + (3 * current_words);

        return cost - current_cost;
    }

    /// Record memory expansion
    pub fn recordExpansion(self: *MemoryGas, new_size: u64) u64 {
        const cost = self.expansionCost(new_size);
        self.setSize(new_size);
        return cost;
    }
};
