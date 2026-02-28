const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Detect target OS for platform-specific defaults
    // Use the resolved target to get OS information
    const target_info = target.result;
    const is_windows = target_info.os.tag == .windows;

    // Build options for crypto libraries
    // All precompile dependencies are required by default
    // Users can disable them with -Dblst=false or -Dmcl=false if needed
    const enable_blst = b.option(bool, "blst", "Enable blst library for BLS12-381 and KZG operations") orelse true;
    const enable_mcl = b.option(bool, "mcl", "Enable mcl library for BN254 operations") orelse true;

    // Platform-specific default include paths
    // Note: Users should override these with -Dblst-include=... or -Dmcl-include=...
    // if libraries are installed in non-standard locations
    const default_include_path = if (is_windows)
        "C:/Program Files" // Windows default (users should override)
    else if (target_info.os.tag == .macos)
        "/opt/homebrew/include" // macOS Homebrew default
    else
        "/usr/local/include"; // Unix default (Linux, BSD)

    const blst_include_path = b.option([]const u8, "blst-include", "Path to blst include directory") orelse default_include_path;
    const mcl_include_path = b.option([]const u8, "mcl-include", "Path to mcl include directory") orelse default_include_path;

    // Add compile flags for optional libraries
    const lib_options = b.addOptions();
    lib_options.addOption(bool, "enable_blst", enable_blst);
    lib_options.addOption(bool, "enable_mcl", enable_mcl);
    const lib_options_module = lib_options.createModule();

    // Helper function to add crypto library linking to a step
    const addCryptoLibraries = struct {
        fn add(
            b_ctx: *std.Build,
            step: *std.Build.Step.Compile,
            blst_enabled: bool,
            mcl_enabled: bool,
            blst_inc: []const u8,
            mcl_inc: []const u8,
            is_win: bool,
            is_macos: bool,
        ) void {
            step.linkSystemLibrary("c");

            // Math library (libm) is Unix-specific, not needed on Windows
            if (!is_win) {
                step.linkSystemLibrary("m");
            }

            step.linkSystemLibrary("secp256k1");

            // OpenSSL library names differ by platform
            if (is_win) {
                // Windows: OpenSSL libraries are typically named libssl and libcrypto
                // May need to adjust based on how OpenSSL is installed
                step.linkSystemLibrary("ssl");
                step.linkSystemLibrary("crypto");
            } else {
                // Unix (macOS, Linux, BSD): standard names
                step.linkSystemLibrary("ssl");
                step.linkSystemLibrary("crypto");
            }

            // blst is required by default
            if (blst_enabled) {
                // Try to link static library directly if available
                const blst_static_paths = if (is_macos)
                    [_][]const u8{ "/opt/homebrew/lib/libblst.a", "/usr/local/lib/libblst.a" }
                else
                    [_][]const u8{ "/usr/local/lib/libblst.a", "/usr/lib/libblst.a" };

                var found_blst_static = false;
                for (blst_static_paths) |path| {
                    // Check if static library exists
                    const file = std.fs.openFileAbsolute(path, .{}) catch continue;
                    file.close();
                    // Link the static library directly
                    step.addObjectFile(.{ .cwd_relative = path });
                    found_blst_static = true;
                    break;
                }

                // Fall back to system library if static not found
                if (!found_blst_static) {
                    step.linkSystemLibrary("blst");
                }

                // Add include path for blst headers
                // For absolute paths, we need to handle them specially
                // The issue is that cwd_relative doesn't work well with absolute paths
                // So we'll add the include path directly using addIncludePath
                if (std.fs.path.isAbsolute(blst_inc)) {
                    // For absolute paths, try using cwd_relative (may not work in all cases)
                    // If this fails, the Makefile should install headers to a standard location
                    step.root_module.addIncludePath(.{ .cwd_relative = blst_inc });
                } else {
                    step.root_module.addIncludePath(b_ctx.path(blst_inc));
                }
            }

            if (mcl_enabled) {
                // Link C++ standard library BEFORE static library on Linux
                // libmcl.a was compiled with libstdc++ (GNU C++ library), not libc++
                if (!is_macos) {
                    // Linux: explicitly link libstdc++ BEFORE static library
                    // This is critical - libmcl.a needs libstdc++ symbols
                    step.linkSystemLibrary("stdc++");
                }

                // Try to link static library directly if available
                const mcl_static_paths = if (is_macos)
                    [_][]const u8{ "/opt/homebrew/lib/libmcl.a", "/usr/local/lib/libmcl.a" }
                else
                    [_][]const u8{ "/usr/local/lib/libmcl.a", "/usr/lib/libmcl.a" };

                var found_mcl_static = false;
                for (mcl_static_paths) |path| {
                    // Check if static library exists
                    const file = std.fs.openFileAbsolute(path, .{}) catch continue;
                    file.close();
                    // On Linux, addObjectFile() may trigger automatic linkLibCpp() which adds -lc++
                    // But we need -lstdc++. So we'll use the library path approach instead
                    if (is_macos) {
                        // macOS: use addObjectFile() for static linking
                        step.addObjectFile(.{ .cwd_relative = path });
                        found_mcl_static = true;
                        break;
                    } else {
                        // Linux: add library path and let linker find static library
                        // This avoids automatic linkLibCpp() call
                        const lib_dir = std.fs.path.dirname(path) orelse continue;
                        step.addLibraryPath(.{ .cwd_relative = lib_dir });
                        step.linkSystemLibrary("mcl");
                        found_mcl_static = true;
                        break;
                    }
                }

                // Fall back to system library if static not found
                if (!found_mcl_static) {
                    step.linkSystemLibrary("mcl");
                }

                // Link C++ standard library AFTER the static library
                // On macOS, use libc++
                // On Linux, add libstdc++ again after static library to ensure symbols are resolved
                if (is_macos) {
                    step.linkLibCpp(); // macOS uses libc++
                } else {
                    // Linux: link libstdc++ AFTER static library to resolve undefined symbols
                    step.linkSystemLibrary("stdc++");
                }

                // Use cwd_relative for absolute paths, or path for relative paths
                if (std.fs.path.isAbsolute(mcl_inc)) {
                    step.root_module.addIncludePath(.{ .cwd_relative = mcl_inc });
                } else {
                    step.root_module.addIncludePath(b_ctx.path(mcl_inc));
                }
            }
        }
    }.add;

    // Main library
    const lib = b.addLibrary(.{
        .name = "zevm",
        .root_module = b.addModule("zevm", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addImport("build_options", lib_options_module);

    // Add crypto dependencies
    addCryptoLibraries(b, lib, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);

    // Install the library
    b.installArtifact(lib);

    // Create modules for each component
    const primitives_module = b.addModule("primitives", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/primitives/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const bytecode_module = b.addModule("bytecode", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/bytecode/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const state_module = b.addModule("state", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/state/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const database_module = b.addModule("database", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/database/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const context_module = b.addModule("context", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/context/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const interpreter_module = b.addModule("interpreter", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/interpreter/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const precompile_module = b.addModule("precompile", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/precompile/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const handler_module = b.addModule("handler", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/handler/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const inspector_module = b.addModule("inspector", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/inspector/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    // Add module dependencies
    bytecode_module.addImport("primitives", primitives_module);
    state_module.addImport("primitives", primitives_module);
    state_module.addImport("bytecode", bytecode_module);
    database_module.addImport("primitives", primitives_module);
    database_module.addImport("state", state_module);
    database_module.addImport("bytecode", bytecode_module);
    context_module.addImport("primitives", primitives_module);
    context_module.addImport("bytecode", bytecode_module);
    context_module.addImport("state", state_module);
    context_module.addImport("database", database_module);
    interpreter_module.addImport("primitives", primitives_module);
    interpreter_module.addImport("bytecode", bytecode_module);
    interpreter_module.addImport("context", context_module);
    interpreter_module.addImport("database", database_module);
    interpreter_module.addImport("state", state_module);
    interpreter_module.addImport("precompile", precompile_module);
    precompile_module.addImport("build_options", lib_options_module);
    precompile_module.addImport("primitives", primitives_module);
    handler_module.addImport("primitives", primitives_module);
    handler_module.addImport("bytecode", bytecode_module);
    handler_module.addImport("state", state_module);
    handler_module.addImport("database", database_module);
    handler_module.addImport("interpreter", interpreter_module);
    handler_module.addImport("context", context_module);
    handler_module.addImport("precompile", precompile_module);
    inspector_module.addImport("primitives", primitives_module);
    inspector_module.addImport("interpreter", interpreter_module);

    // Add modules to main library
    lib.root_module.addImport("primitives", primitives_module);
    lib.root_module.addImport("bytecode", bytecode_module);
    lib.root_module.addImport("state", state_module);
    lib.root_module.addImport("database", database_module);
    lib.root_module.addImport("context", context_module);
    lib.root_module.addImport("interpreter", interpreter_module);
    lib.root_module.addImport("precompile", precompile_module);
    lib.root_module.addImport("handler", handler_module);
    lib.root_module.addImport("inspector", inspector_module);

    // Test executable
    const test_exe = b.addExecutable(.{
        .name = "zevm-test",
        .root_module = b.addModule("zevm-test", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/test.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    addCryptoLibraries(b, test_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    test_exe.root_module.addImport("build_options", lib_options_module);
    test_exe.root_module.addImport("primitives", primitives_module);
    test_exe.root_module.addImport("bytecode", bytecode_module);
    test_exe.root_module.addImport("state", state_module);
    test_exe.root_module.addImport("database", database_module);
    test_exe.root_module.addImport("context", context_module);
    test_exe.root_module.addImport("interpreter", interpreter_module);
    test_exe.root_module.addImport("precompile", precompile_module);
    test_exe.root_module.addImport("handler", handler_module);
    test_exe.root_module.addImport("inspector", inspector_module);

    b.installArtifact(test_exe);

    // Benchmark executable (always ReleaseFast for accurate timing)
    const bench_exe = b.addExecutable(.{
        .name = "zevm-bench",
        .root_module = b.addModule("zevm-bench", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "benchmarks/main.zig" } },
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    addCryptoLibraries(b, bench_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    bench_exe.root_module.addImport("build_options", lib_options_module);
    bench_exe.root_module.addImport("primitives", primitives_module);
    bench_exe.root_module.addImport("bytecode", bytecode_module);
    bench_exe.root_module.addImport("state", state_module);
    bench_exe.root_module.addImport("database", database_module);
    bench_exe.root_module.addImport("context", context_module);
    bench_exe.root_module.addImport("interpreter", interpreter_module);
    bench_exe.root_module.addImport("precompile", precompile_module);
    bench_exe.root_module.addImport("handler", handler_module);
    bench_exe.root_module.addImport("inspector", inspector_module);

    // Add zbench dependency for benchmarking
    const zbench_dep = b.dependency("zbench", .{ .target = target, .optimize = .ReleaseFast });
    bench_exe.root_module.addImport("zbench", zbench_dep.module("zbench"));

    b.installArtifact(bench_exe);

    // Run tests
    const run_tests = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Inline zig tests for interpreter module (discovers tests in all imported files)
    const interpreter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/interpreter/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    interpreter_tests.root_module.addImport("primitives", primitives_module);
    interpreter_tests.root_module.addImport("bytecode", bytecode_module);
    interpreter_tests.root_module.addImport("context", context_module);
    interpreter_tests.root_module.addImport("database", database_module);
    interpreter_tests.root_module.addImport("state", state_module);
    interpreter_tests.root_module.addImport("precompile", precompile_module);
    addCryptoLibraries(b, interpreter_tests, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    const run_interpreter_tests = b.addRunArtifact(interpreter_tests);
    test_step.dependOn(&run_interpreter_tests.step);

    // Inline zig tests for handler module (validation, gas calculation, etc.)
    const handler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/handler/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    handler_tests.root_module.addImport("primitives", primitives_module);
    handler_tests.root_module.addImport("bytecode", bytecode_module);
    handler_tests.root_module.addImport("context", context_module);
    handler_tests.root_module.addImport("database", database_module);
    handler_tests.root_module.addImport("state", state_module);
    handler_tests.root_module.addImport("interpreter", interpreter_module);
    handler_tests.root_module.addImport("precompile", precompile_module);
    addCryptoLibraries(b, handler_tests, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    const run_handler_tests = b.addRunArtifact(handler_tests);
    test_step.dependOn(&run_handler_tests.step);

    // Precompile unit tests - these are run via zig test command in CI
    // The command needs to link libc and include all modules
    // See .github/workflows/ci.yml for the full command

    // Example executable
    const example_exe = b.addExecutable(.{
        .name = "zevm-example",
        .root_module = b.addModule("zevm-example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/simple_evm.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    addCryptoLibraries(b, example_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    example_exe.root_module.addImport("build_options", lib_options_module);
    example_exe.root_module.addImport("zevm", lib.root_module);
    example_exe.root_module.addImport("primitives", primitives_module);
    example_exe.root_module.addImport("bytecode", bytecode_module);
    example_exe.root_module.addImport("state", state_module);
    example_exe.root_module.addImport("database", database_module);
    example_exe.root_module.addImport("context", context_module);
    example_exe.root_module.addImport("interpreter", interpreter_module);
    example_exe.root_module.addImport("precompile", precompile_module);
    example_exe.root_module.addImport("handler", handler_module);
    example_exe.root_module.addImport("inspector", inspector_module);

    b.installArtifact(example_exe);

    // Example executables
    const simple_contract_exe = b.addExecutable(.{
        .name = "simple_contract",
        .root_module = b.addModule("simple_contract", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/simple_contract.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, simple_contract_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    simple_contract_exe.root_module.addImport("build_options", lib_options_module);
    simple_contract_exe.root_module.addImport("primitives", primitives_module);
    simple_contract_exe.root_module.addImport("bytecode", bytecode_module);
    simple_contract_exe.root_module.addImport("state", state_module);
    simple_contract_exe.root_module.addImport("database", database_module);
    simple_contract_exe.root_module.addImport("context", context_module);
    simple_contract_exe.root_module.addImport("interpreter", interpreter_module);
    simple_contract_exe.root_module.addImport("precompile", precompile_module);
    simple_contract_exe.root_module.addImport("handler", handler_module);
    simple_contract_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(simple_contract_exe);

    const gas_inspector_exe = b.addExecutable(.{
        .name = "gas_inspector_example",
        .root_module = b.addModule("gas_inspector_example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/gas_inspector_example.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, gas_inspector_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    gas_inspector_exe.root_module.addImport("build_options", lib_options_module);
    gas_inspector_exe.root_module.addImport("primitives", primitives_module);
    gas_inspector_exe.root_module.addImport("bytecode", bytecode_module);
    gas_inspector_exe.root_module.addImport("state", state_module);
    gas_inspector_exe.root_module.addImport("database", database_module);
    gas_inspector_exe.root_module.addImport("context", context_module);
    gas_inspector_exe.root_module.addImport("interpreter", interpreter_module);
    gas_inspector_exe.root_module.addImport("precompile", precompile_module);
    gas_inspector_exe.root_module.addImport("handler", handler_module);
    gas_inspector_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(gas_inspector_exe);

    const precompile_exe = b.addExecutable(.{
        .name = "precompile_example",
        .root_module = b.addModule("precompile_example", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/precompile_example.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, precompile_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    precompile_exe.root_module.addImport("build_options", lib_options_module);
    precompile_exe.root_module.addImport("primitives", primitives_module);
    precompile_exe.root_module.addImport("bytecode", bytecode_module);
    precompile_exe.root_module.addImport("state", state_module);
    precompile_exe.root_module.addImport("database", database_module);
    precompile_exe.root_module.addImport("context", context_module);
    precompile_exe.root_module.addImport("interpreter", interpreter_module);
    precompile_exe.root_module.addImport("precompile", precompile_module);
    precompile_exe.root_module.addImport("handler", handler_module);
    precompile_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(precompile_exe);

    // Contract deployment example
    const contract_deployment_exe = b.addExecutable(.{
        .name = "contract_deployment",
        .root_module = b.addModule("contract_deployment", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/contract_deployment.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, contract_deployment_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    contract_deployment_exe.root_module.addImport("build_options", lib_options_module);
    contract_deployment_exe.root_module.addImport("primitives", primitives_module);
    contract_deployment_exe.root_module.addImport("bytecode", bytecode_module);
    contract_deployment_exe.root_module.addImport("state", state_module);
    contract_deployment_exe.root_module.addImport("database", database_module);
    contract_deployment_exe.root_module.addImport("context", context_module);
    contract_deployment_exe.root_module.addImport("interpreter", interpreter_module);
    contract_deployment_exe.root_module.addImport("precompile", precompile_module);
    contract_deployment_exe.root_module.addImport("handler", handler_module);
    contract_deployment_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(contract_deployment_exe);

    // Uniswap reserves example
    const uniswap_reserves_exe = b.addExecutable(.{
        .name = "uniswap_reserves",
        .root_module = b.addModule("uniswap_reserves", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/uniswap_reserves.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, uniswap_reserves_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    uniswap_reserves_exe.root_module.addImport("build_options", lib_options_module);
    uniswap_reserves_exe.root_module.addImport("primitives", primitives_module);
    uniswap_reserves_exe.root_module.addImport("bytecode", bytecode_module);
    uniswap_reserves_exe.root_module.addImport("state", state_module);
    uniswap_reserves_exe.root_module.addImport("database", database_module);
    uniswap_reserves_exe.root_module.addImport("context", context_module);
    uniswap_reserves_exe.root_module.addImport("interpreter", interpreter_module);
    uniswap_reserves_exe.root_module.addImport("precompile", precompile_module);
    uniswap_reserves_exe.root_module.addImport("handler", handler_module);
    uniswap_reserves_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(uniswap_reserves_exe);

    // Custom opcodes example
    const custom_opcodes_exe = b.addExecutable(.{
        .name = "custom_opcodes",
        .root_module = b.addModule("custom_opcodes", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/custom_opcodes.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, custom_opcodes_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    custom_opcodes_exe.root_module.addImport("build_options", lib_options_module);
    custom_opcodes_exe.root_module.addImport("primitives", primitives_module);
    custom_opcodes_exe.root_module.addImport("bytecode", bytecode_module);
    custom_opcodes_exe.root_module.addImport("state", state_module);
    custom_opcodes_exe.root_module.addImport("database", database_module);
    custom_opcodes_exe.root_module.addImport("context", context_module);
    custom_opcodes_exe.root_module.addImport("interpreter", interpreter_module);
    custom_opcodes_exe.root_module.addImport("precompile", precompile_module);
    custom_opcodes_exe.root_module.addImport("handler", handler_module);
    custom_opcodes_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(custom_opcodes_exe);

    // Database components example
    const database_components_exe = b.addExecutable(.{
        .name = "database_components",
        .root_module = b.addModule("database_components", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/database_components.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, database_components_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    database_components_exe.root_module.addImport("build_options", lib_options_module);
    database_components_exe.root_module.addImport("primitives", primitives_module);
    database_components_exe.root_module.addImport("bytecode", bytecode_module);
    database_components_exe.root_module.addImport("state", state_module);
    database_components_exe.root_module.addImport("database", database_module);
    database_components_exe.root_module.addImport("context", context_module);
    database_components_exe.root_module.addImport("interpreter", interpreter_module);
    database_components_exe.root_module.addImport("precompile", precompile_module);
    database_components_exe.root_module.addImport("handler", handler_module);
    database_components_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(database_components_exe);

    // Cheatcode inspector example
    const cheatcode_inspector_exe = b.addExecutable(.{
        .name = "cheatcode_inspector",
        .root_module = b.addModule("cheatcode_inspector", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "examples/cheatcode_inspector.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    addCryptoLibraries(b, cheatcode_inspector_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    cheatcode_inspector_exe.root_module.addImport("build_options", lib_options_module);
    cheatcode_inspector_exe.root_module.addImport("primitives", primitives_module);
    cheatcode_inspector_exe.root_module.addImport("bytecode", bytecode_module);
    cheatcode_inspector_exe.root_module.addImport("state", state_module);
    cheatcode_inspector_exe.root_module.addImport("database", database_module);
    cheatcode_inspector_exe.root_module.addImport("context", context_module);
    cheatcode_inspector_exe.root_module.addImport("interpreter", interpreter_module);
    cheatcode_inspector_exe.root_module.addImport("precompile", precompile_module);
    cheatcode_inspector_exe.root_module.addImport("handler", handler_module);
    cheatcode_inspector_exe.root_module.addImport("inspector", inspector_module);
    b.installArtifact(cheatcode_inspector_exe);

    // --- Spec test runner (links ZEVM modules, parses fixtures at runtime) ---
    const spec_test_types_module = b.addModule("types", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/spec_test/types.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const runner_exe = b.addExecutable(.{
        .name = "spec-test-runner",
        .root_module = b.createModule(.{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/spec_test/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });
    runner_exe.root_module.addImport("types", spec_test_types_module);
    runner_exe.root_module.addImport("runner", b.addModule("runner", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/spec_test/runner.zig" } },
        .target = target,
        .optimize = optimize,
    }));

    // The runner module needs access to ZEVM modules
    const runner_mod = runner_exe.root_module.import_table.get("runner").?;
    runner_mod.addImport("types", spec_test_types_module);
    runner_mod.addImport("primitives", primitives_module);
    runner_mod.addImport("bytecode", bytecode_module);
    runner_mod.addImport("interpreter", interpreter_module);
    runner_mod.addImport("context", context_module);
    runner_mod.addImport("database", database_module);
    runner_mod.addImport("state", state_module);
    runner_mod.addImport("precompile", precompile_module);

    addCryptoLibraries(b, runner_exe, enable_blst, enable_mcl, blst_include_path, mcl_include_path, is_windows, target_info.os.tag == .macos);
    b.installArtifact(runner_exe);

    const runner_step = b.step("spec-test-runner", "Build the spec test runner");
    runner_step.dependOn(&b.addInstallArtifact(runner_exe, .{}).step);
}
