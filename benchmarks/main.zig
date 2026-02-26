const std = @import("std");
const primitives = @import("primitives");
const interpreter = @import("interpreter");
const bytecode = @import("bytecode");
const zbench = @import("zbench");

const InstructionTable = interpreter.protocol_schedule.InstructionTable;
const InstructionContext = interpreter.InstructionContext;

const U256 = primitives.U256;
const MAX = std.math.maxInt(U256);

// Category modules
const arithmetic_bench = @import("arithmetic.zig");
const bitwise_bench = @import("bitwise.zig");
const comparison_bench = @import("comparison.zig");
const memory_bench = @import("memory.zig");
const keccak_bench = @import("keccak.zig");
const stack_bench = @import("stack.zig");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

pub const OPS_PER_BATCH = 400;
pub const PREFILL = 900; // must be divisible by 2 and 3
pub const NUM_VALUES = 1024;
pub const MEM_SIZE = 32 * 1024; // 32KB pre-allocated memory region

// ---------------------------------------------------------------------------
// Global state (zbench hooks require fn() void, so globals are necessary)
// ---------------------------------------------------------------------------

pub var g_stack: interpreter.Stack = interpreter.Stack.new();
pub var g_gas: interpreter.Gas = interpreter.Gas.new(0);
pub var g_memory: interpreter.Memory = interpreter.Memory.new();
var g_spec: primitives.SpecId = .osaka; // Default to latest fork
pub var g_instruction_table: InstructionTable = undefined;
pub var g_bytecode: [32 * 1024]u8 = undefined;
pub var g_pc: usize = 0;
pub var g_interp: interpreter.Interpreter = undefined;

// ---------------------------------------------------------------------------
// Reproducible test data
// ---------------------------------------------------------------------------

var prng_state: u64 = 42;

fn xorshift64() u64 {
    var x = prng_state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    prng_state = x;
    return x;
}

fn randomU256() U256 {
    const lo: u128 = @as(u128, xorshift64()) | (@as(u128, xorshift64()) << 64);
    const hi: u128 = @as(u128, xorshift64()) | (@as(u128, xorshift64()) << 64);
    return @as(U256, hi) << 128 | lo;
}

pub var g_values: [NUM_VALUES]U256 = undefined; // random 256-bit values
pub var g_divisor_128: U256 = undefined; // 128-bit divisor (2 non-zero limbs)
pub var g_divisor_64: U256 = undefined; // 64-bit divisor (single limb)
pub var g_small_exp: [NUM_VALUES]U256 = undefined; // 1-byte exponents (1..255)
var g_initialized = false;

fn initValues() void {
    prng_state = 42;
    for (&g_values) |*v| v.* = randomU256();
    const lo: u128 = @as(u128, xorshift64() | 1) | (@as(u128, xorshift64()) << 64);
    g_divisor_128 = @as(U256, lo);
    g_divisor_64 = @as(U256, xorshift64() | 1);
    for (&g_small_exp) |*v| v.* = @as(U256, (xorshift64() & 0xFF) | 1);
    for (&g_bytecode) |*b| b.* = @truncate(xorshift64());
    g_initialized = true;
}

pub fn ensureInit() void {
    if (!g_initialized) initValues();
}

// ---------------------------------------------------------------------------
// Stack fill helpers
//
// Stack layout reminder: opcodes pop TOS first (a), then second (b), then
// third (N). So we push in reverse order: deepest operand first.
// ---------------------------------------------------------------------------

/// Common pre-benchmark setup: init test data, clear stack, set gas budget.
pub fn setup(gas_cost: u64) void {
    ensureInit();
    g_stack.clear();
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * gas_cost + 1000);
}

/// Push `count` random 256-bit values from the pool.
pub fn fillRandom(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push `count` [a, b] pairs: a = random from pool, b = fixed value.
pub fn fillPairs(count: usize, b: U256) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push `count` [a, b] pairs: both random from pool, b guaranteed non-zero.
pub fn fillRandomPairs(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[(i + 512) & (NUM_VALUES - 1)] | 1);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push `count` [a, b] pairs with both values constant.
pub fn fillConstantPairs(count: usize, a: U256, b: U256) void {
    for (0..count) |_| {
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(a);
    }
}

/// Push [a, b, N] triples: all random from pool, N guaranteed non-zero.
pub fn fillRandomTriples(count: usize) void {
    var i: usize = 0;
    while (i + 2 < count) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1);
        g_stack.pushUnsafe(g_values[(i + 1) & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push [a, b, N] triples: a and b fixed, N random non-zero.
pub fn fillFixedTriples(count: usize, a: U256, b: U256) void {
    var i: usize = 0;
    while (i + 2 < count) : (i += 3) {
        g_stack.pushUnsafe(g_values[(i + 2) & (NUM_VALUES - 1)] | 1);
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(a);
    }
}

/// Push [base, exponent] pairs: base = random, exponent = 1-byte (1..255).
pub fn fillExpSmall(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_small_exp[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push [base, exponent] pairs: base = random, exponent = random 32-byte.
pub fn fillExpLarge(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[(i + 512) & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
    }
}

/// Push [a, b] pairs where a has sign bit set (negative in two's complement).
pub fn fillNegativePairs(count: usize, b: U256) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        g_stack.pushUnsafe(b);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit);
    }
}

/// Push [a, b] pairs where both have sign bit set.
pub fn fillBothNegPairs(count: usize, b: U256) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        g_stack.pushUnsafe(b | sign_bit);
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit);
    }
}

/// Push [byte_pos, value] pairs for SIGNEXTEND.
pub fn fillSignextendPairs(count: usize, mask: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, i & mask));
    }
}

/// Push [shift, value] pairs for SHL/SHR/SAR.
pub fn fillShiftPairs(count: usize, mask: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, (i * 7) & mask));
    }
}

/// Push [shift, value] pairs where value has sign bit set (for SAR negative).
pub fn fillShiftNegPairs(count: usize, mask: usize) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)] | sign_bit);
        g_stack.pushUnsafe(@as(U256, (i * 7) & mask));
    }
}

/// Push [shift, value] pairs alternating pos/neg for SAR.
pub fn fillShiftMixedPairs(count: usize, mask: usize) void {
    const sign_bit: U256 = 1 << 255;
    for (0..count) |i| {
        const val = g_values[i & (NUM_VALUES - 1)];
        g_stack.pushUnsafe(if (i & 1 == 0) val else val | sign_bit);
        g_stack.pushUnsafe(@as(U256, (i * 7) & mask));
    }
}

/// Push [position, value] pairs for BYTE extraction.
pub fn fillBytePairs(count: usize) void {
    for (0..count) |i| {
        g_stack.pushUnsafe(g_values[i & (NUM_VALUES - 1)]);
        g_stack.pushUnsafe(@as(U256, i & 31));
    }
}

// ---------------------------------------------------------------------------
// Benchmark runners (generates the inner loop for any opcode via comptime)
// ---------------------------------------------------------------------------

fn makeCtx() InstructionContext {
    g_interp.stack = g_stack;
    g_interp.gas = g_gas;
    return InstructionContext{ .interpreter = &g_interp };
}

fn syncFromCtx() void {
    g_stack = g_interp.stack;
    g_gas = g_interp.gas;
}

pub fn OpRunner(comptime opFn: anytype) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            var ctx = makeCtx();
            for (0..OPS_PER_BATCH) |_| {
                opFn(&ctx);
            }
            syncFromCtx();
            std.mem.doNotOptimizeAway(&g_interp.stack);
        }
    };
}

pub fn MemOpRunner(comptime opFn: anytype) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            g_interp.memory = g_memory;
            var ctx = makeCtx();
            for (0..OPS_PER_BATCH) |_| {
                opFn(&ctx);
            }
            syncFromCtx();
            g_memory = g_interp.memory;
            std.mem.doNotOptimizeAway(&g_interp.stack);
            std.mem.doNotOptimizeAway(&g_interp.memory);
        }
    };
}

pub fn KeccakRunner(comptime data_size: usize) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            const opcodes = interpreter.opcodes;
            g_interp.memory = g_memory;
            var ctx = makeCtx();
            for (0..OPS_PER_BATCH) |_| {
                g_interp.stack.pushUnsafe(@as(U256, data_size)); // length
                g_interp.stack.pushUnsafe(@as(U256, 0)); // offset
                opcodes.opKeccak256(&ctx);
            }
            syncFromCtx();
            std.mem.doNotOptimizeAway(&g_interp.stack);
        }
    };
}

pub fn DupRunner(comptime n: u8) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            const opDupN = interpreter.opcodes.makeDupFn(n);
            var ctx = makeCtx();
            for (0..OPS_PER_BATCH) |_| {
                opDupN(&ctx);
            }
            syncFromCtx();
            std.mem.doNotOptimizeAway(&g_interp.stack);
        }
    };
}

pub fn SwapRunner(comptime n: u8) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            const opSwapN = interpreter.opcodes.makeSwapFn(n);
            var ctx = makeCtx();
            for (0..OPS_PER_BATCH) |_| {
                opSwapN(&ctx);
            }
            syncFromCtx();
            std.mem.doNotOptimizeAway(&g_interp.stack);
        }
    };
}

pub fn PushRunner(comptime n: u8) type {
    return struct {
        pub fn run(_: std.mem.Allocator) void {
            const opPushN = interpreter.opcodes.makePushFn(n);
            var ctx = makeCtx();
            // Point interpreter bytecode at g_bytecode
            ctx.interpreter.bytecode.pc = 0;
            for (0..OPS_PER_BATCH) |_| {
                opPushN(&ctx);
                // Reset PC so each push reads from same position
                ctx.interpreter.bytecode.pc = 0;
            }
            syncFromCtx();
            std.mem.doNotOptimizeAway(&g_interp.stack);
        }
    };
}

// ---------------------------------------------------------------------------
// Helper: get gas cost from instruction table
// ---------------------------------------------------------------------------

pub fn gasFor(comptime opcode: u8) u64 {
    return g_instruction_table[opcode].static_gas;
}

// ---------------------------------------------------------------------------
// Memory setup helpers
// ---------------------------------------------------------------------------

pub fn setupMem(gas_cost: u64) void {
    ensureInit();
    g_stack.clear();
    g_memory.buffer.clearRetainingCapacity();
    g_gas = interpreter.Gas.new(OPS_PER_BATCH * gas_cost + 1000);
}

pub fn preExpandMemory(mem_size: usize) void {
    g_memory.buffer.resize(std.heap.c_allocator, mem_size) catch unreachable;
    for (g_memory.buffer.items, 0..) |*b, i| b.* = @truncate(i);
}

// ---------------------------------------------------------------------------
// Gas cost lookup (for MGas/sec column) — delegates to category modules
// ---------------------------------------------------------------------------

fn gasCostForName(name: []const u8) f64 {
    const modules = .{ arithmetic_bench, bitwise_bench, comparison_bench, memory_bench, keccak_bench, stack_bench };
    inline for (modules) |mod| {
        if (mod.gasCost(name)) |g| return g;
    }
    return 3.0;
}

// ---------------------------------------------------------------------------
// Category detection for section separators — delegates to category modules
// ---------------------------------------------------------------------------

fn getOpcodeCategory(name: []const u8) []const u8 {
    const modules = .{ arithmetic_bench, bitwise_bench, comparison_bench, memory_bench, keccak_bench, stack_bench };
    inline for (modules) |mod| {
        if (mod.category(name)) |c| return c;
    }
    return "OTHER";
}

// ---------------------------------------------------------------------------
// Filter and fork parsing
// ---------------------------------------------------------------------------

fn parseSpecId(name: []const u8) ?primitives.SpecId {
    if (std.mem.eql(u8, name, "frontier")) return .frontier;
    if (std.mem.eql(u8, name, "frontier_thawing")) return .frontier_thawing;
    if (std.mem.eql(u8, name, "homestead")) return .homestead;
    if (std.mem.eql(u8, name, "dao_fork")) return .dao_fork;
    if (std.mem.eql(u8, name, "tangerine")) return .tangerine;
    if (std.mem.eql(u8, name, "spurious") or std.mem.eql(u8, name, "spurious_dragon")) return .spurious_dragon;
    if (std.mem.eql(u8, name, "byzantium")) return .byzantium;
    if (std.mem.eql(u8, name, "constantinople")) return .constantinople;
    if (std.mem.eql(u8, name, "petersburg")) return .petersburg;
    if (std.mem.eql(u8, name, "istanbul")) return .istanbul;
    if (std.mem.eql(u8, name, "muir_glacier")) return .muir_glacier;
    if (std.mem.eql(u8, name, "berlin")) return .berlin;
    if (std.mem.eql(u8, name, "london")) return .london;
    if (std.mem.eql(u8, name, "arrow_glacier")) return .arrow_glacier;
    if (std.mem.eql(u8, name, "gray_glacier")) return .gray_glacier;
    if (std.mem.eql(u8, name, "merge")) return .merge;
    if (std.mem.eql(u8, name, "shanghai")) return .shanghai;
    if (std.mem.eql(u8, name, "cancun")) return .cancun;
    if (std.mem.eql(u8, name, "prague")) return .prague;
    if (std.mem.eql(u8, name, "osaka")) return .osaka;
    if (std.mem.eql(u8, name, "amsterdam")) return .amsterdam;
    return null;
}

pub fn matchesFilter(name: []const u8, filter: []const u8) bool {
    if (filter.len == 0) return true;

    var name_lower_buf: [256]u8 = undefined;
    var filter_lower_buf: [256]u8 = undefined;
    if (name.len > name_lower_buf.len or filter.len > filter_lower_buf.len) return false;

    for (name, 0..) |c, i| name_lower_buf[i] = std.ascii.toLower(c);
    for (filter, 0..) |c, i| filter_lower_buf[i] = std.ascii.toLower(c);

    return std.mem.indexOf(u8, name_lower_buf[0..name.len], filter_lower_buf[0..filter.len]) != null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main() !void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    const writer = &stdout.interface;
    const allocator = std.heap.page_allocator;

    // Parse command-line arguments for fork selection and filter
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    var filter: []const u8 = "";

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--fork=")) {
            const fork_name = arg[7..];
            if (parseSpecId(fork_name)) |spec| {
                g_spec = spec;
            } else {
                try writer.print("Error: Unknown fork '{s}'\n", .{fork_name});
                try writer.writeAll("Available forks: frontier, homestead, tangerine, spurious_dragon, byzantium, ");
                try writer.writeAll("constantinople, petersburg, istanbul, berlin, london, shanghai, cancun, prague, osaka, amsterdam\n");
                return error.InvalidFork;
            }
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            filter = arg[9..];
        }
    }

    // Initialize instruction table and interpreter for the selected fork
    g_instruction_table = interpreter.protocol_schedule.makeInstructionTable(g_spec);
    g_interp = interpreter.Interpreter.defaultExt();

    try writer.print("\n=== ZEVM Opcode Benchmark (zBench) ===\n", .{});
    try writer.print("Fork: {s}\n", .{@tagName(g_spec)});
    if (filter.len > 0) {
        try writer.print("Filter: {s}\n", .{filter});
    }
    try writer.writeAll("\n");

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    // Register benchmarks from category modules
    try arithmetic_bench.register(&bench, filter);
    try bitwise_bench.register(&bench, filter);
    try comparison_bench.register(&bench, filter);
    try memory_bench.register(&bench, filter);
    try keccak_bench.register(&bench, filter);
    try stack_bench.register(&bench, filter);

    // Print results
    try writer.print("{s:<20}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
        "benchmark", "runs", "total time", "time/op (avg ± σ)", "(min ... max)", "p75", "p99", "MGas/sec",
    });
    try writer.writeAll("-" ** 135 ++ "\n");

    var current_category: []const u8 = "";
    var it = try bench.iterator();
    while (try it.next()) |step| {
        switch (step) {
            .progress => {},
            .result => |result| {
                defer result.deinit();

                // Print category separators
                const cat = getOpcodeCategory(result.name);
                if (!std.mem.eql(u8, cat, current_category)) {
                    if (current_category.len > 0) try writer.writeAll("\n");
                    try writer.print("--- {s} OPCODES ---\n\n", .{cat});
                }
                current_category = cat;

                const timings = result.readings.timings_ns;
                if (timings.len == 0) continue;
                const n: f64 = @floatFromInt(timings.len);
                const ops: f64 = @floatFromInt(OPS_PER_BATCH);

                var sum_f: f64 = 0;
                var min_f: f64 = std.math.floatMax(f64);
                var max_f: f64 = 0;
                for (timings) |t| {
                    const per_op: f64 = @as(f64, @floatFromInt(t)) / ops;
                    sum_f += per_op;
                    min_f = @min(min_f, per_op);
                    max_f = @max(max_f, per_op);
                }
                const mean_f = sum_f / n;

                var var_sum_f: f64 = 0;
                for (timings) |t| {
                    const per_op: f64 = @as(f64, @floatFromInt(t)) / ops;
                    const diff = per_op - mean_f;
                    var_sum_f += diff * diff;
                }
                const stddev_f = if (timings.len > 1) @sqrt(var_sum_f / (n - 1)) else 0;

                const per_op_buf = allocator.alloc(f64, timings.len) catch continue;
                defer allocator.free(per_op_buf);
                for (per_op_buf, timings) |*dst, t| dst.* = @as(f64, @floatFromInt(t)) / ops;
                std.mem.sort(f64, per_op_buf, {}, std.sort.asc(f64));
                const p75 = per_op_buf[timings.len * 75 / 100];
                const p99 = per_op_buf[timings.len * 99 / 100];

                const gas_per_op = gasCostForName(result.name);
                const mgas_per_sec = if (mean_f > 0) (gas_per_op * 1_000.0) / mean_f else 0;

                var total_ns: u64 = 0;
                for (timings) |t| total_ns += t;

                var buf_runs: [32]u8 = undefined;
                var buf_total: [32]u8 = undefined;
                var buf_avg: [64]u8 = undefined;
                var buf_range: [64]u8 = undefined;
                var buf_p75: [32]u8 = undefined;
                var buf_p99: [32]u8 = undefined;
                var buf_mgas: [32]u8 = undefined;

                const s_runs = std.fmt.bufPrint(&buf_runs, "{d}", .{timings.len}) catch continue;
                const s_total = std.fmt.bufPrint(&buf_total, "{d}ms", .{total_ns / 1_000_000}) catch continue;
                const s_avg = std.fmt.bufPrint(&buf_avg, "{d:.2}ns ± {d:.2}ns", .{ mean_f, stddev_f }) catch continue;
                const s_range = std.fmt.bufPrint(&buf_range, "({d:.2}ns ... {d:.2}ns)", .{ min_f, max_f }) catch continue;
                const s_p75 = std.fmt.bufPrint(&buf_p75, "{d:.2}ns", .{p75}) catch continue;
                const s_p99 = std.fmt.bufPrint(&buf_p99, "{d:.2}ns", .{p99}) catch continue;
                const s_mgas = std.fmt.bufPrint(&buf_mgas, "{d:.0}", .{mgas_per_sec}) catch continue;

                try writer.print("{s:<20}{s:<10}{s:<15}{s:<24}{s:<30}{s:<12}{s:<12}{s}\n", .{
                    result.name, s_runs, s_total, s_avg, s_range, s_p75, s_p99, s_mgas,
                });
            },
        }
    }

    try writer.writeAll("\n");
}
