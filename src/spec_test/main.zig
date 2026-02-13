// Spec test runner entry point.
// Imports generated test data, runs each test case, reports results.

const std = @import("std");
const data = @import("spec_test_data");
const runner = @import("runner");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var fork_filter: ?[]const u8 = null;
    var name_filter: ?[]const u8 = null;
    var fail_fast = false;
    var verbose = false;

    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--fork=")) {
            fork_filter = arg[7..];
        } else if (std.mem.startsWith(u8, arg, "--filter=")) {
            name_filter = arg[9..];
        } else if (std.mem.eql(u8, arg, "--fail-fast")) {
            fail_fast = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        }
    }

    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var errors: usize = 0;

    var stdout_w = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_w.interface;

    var timer = try std.time.Timer.start();

    for (data.test_cases) |tc| {
        // Apply filters
        if (fork_filter) |ff| {
            if (!std.mem.eql(u8, tc.fork, ff)) {
                skipped += 1;
                continue;
            }
        }
        if (name_filter) |nf| {
            if (std.mem.indexOf(u8, tc.name, nf) == null) {
                skipped += 1;
                continue;
            }
        }

        const outcome = runner.runTestCase(tc, allocator);
        switch (outcome.result) {
            .pass => {
                passed += 1;
                if (verbose) {
                    try stdout.print("PASS {s}\n", .{tc.name});
                }
            },
            .fail => {
                failed += 1;
                try stdout.print("FAIL {s}\n", .{tc.name});
                try printDetail(stdout, outcome.detail);
                if (fail_fast) {
                    try stdout.print("\n--fail-fast: stopping after first failure\n", .{});
                    try printSummary(stdout, passed, failed, skipped, errors, timer.read());
                    std.process.exit(1);
                }
            },
            .skip => skipped += 1,
            .err => {
                errors += 1;
                try stdout.print("ERROR {s}\n", .{tc.name});
                try printDetail(stdout, outcome.detail);
                if (fail_fast) {
                    try stdout.print("\n--fail-fast: stopping after first error\n", .{});
                    try printSummary(stdout, passed, failed, skipped, errors, timer.read());
                    std.process.exit(1);
                }
            },
        }
    }

    try printSummary(stdout, passed, failed, skipped, errors, timer.read());

    if (failed > 0 or errors > 0) {
        std.process.exit(1);
    }
}

fn printDetail(stdout: anytype, detail: runner.FailureDetail) !void {
    if (detail.address != null and detail.storage_key != null and detail.expected != null and detail.actual != null) {
        // Storage mismatch
        const addr_fmt = runner.fmtAddress(detail.address.?);
        var key_buf: [68]u8 = undefined;
        const key_len = runner.fmtU256Bytes(detail.storage_key.?, &key_buf);
        var exp_buf: [68]u8 = undefined;
        const exp_len = runner.fmtU256Bytes(detail.expected.?, &exp_buf);
        var act_buf: [68]u8 = undefined;
        const act_len = runner.fmtU256Bytes(detail.actual.?, &act_buf);
        try stdout.print("      {s} at {s} key={s} expected={s} actual={s}\n", .{
            detail.reason,
            addr_fmt[0..12],
            key_buf[0..key_len],
            exp_buf[0..exp_len],
            act_buf[0..act_len],
        });
    } else if (detail.exec_result) |er| {
        if (detail.opcode) |op| {
            try stdout.print("      {s}: {s} (opcode 0x{x:0>2})\n", .{ detail.reason, @tagName(er), op });
        } else {
            try stdout.print("      {s}: {s}\n", .{ detail.reason, @tagName(er) });
        }
    } else {
        try stdout.print("      {s}\n", .{detail.reason});
    }
}


fn printSummary(stdout: anytype, passed: usize, failed: usize, skipped: usize, errors: usize, elapsed_ns: u64) !void {
    const total = passed + failed + skipped + errors;
    try stdout.print("\n=== Spec Test Results ===\n", .{});
    try stdout.print("Total:   {d}\n", .{total});
    try stdout.print("Passed:  {d}\n", .{passed});
    try stdout.print("Failed:  {d}\n", .{failed});
    try stdout.print("Skipped: {d}\n", .{skipped});
    try stdout.print("Errors:  {d}\n", .{errors});
    if (elapsed_ns < std.time.ns_per_ms) {
        try stdout.print("Time:    {d}us\n", .{elapsed_ns / std.time.ns_per_us});
    } else if (elapsed_ns < std.time.ns_per_s) {
        try stdout.print("Time:    {d}ms\n", .{elapsed_ns / std.time.ns_per_ms});
    } else {
        const ms = elapsed_ns / std.time.ns_per_ms;
        try stdout.print("Time:    {d}.{d:0>3}s\n", .{ ms / 1000, ms % 1000 });
    }
}
