const std = @import("std");
const primitives = @import("primitives");
const state = @import("state");
const bytecode = @import("bytecode");
const database = @import("database");
const ContextError = @import("context.zig").ContextError;

pub const BlockEnv = @import("block.zig").BlockEnv;
pub const TxEnv = @import("tx.zig").TxEnv;
pub const TxKind = @import("tx.zig").TxKind;
pub const CfgEnv = @import("cfg.zig").CfgEnv;
pub const Journal = @import("journal.zig").Journal;
pub const LocalContext = @import("local.zig").LocalContext;
pub const Context = @import("context.zig").Context;
pub const Evm = @import("evm.zig").Evm;

// Re-export all context types
pub const BlockEnvBuilder = @import("block.zig").BlockEnvBuilder;
pub const TxEnvBuilder = @import("tx.zig").TxEnvBuilder;
pub const CfgEnvBuilder = @import("cfg.zig").CfgEnvBuilder;

// Testing functions
pub const testing = struct {
    pub fn testBlockEnv() !void {
        std.debug.print("Testing BlockEnv...\n", .{});

        var block_env = BlockEnv.default();
        std.debug.assert(block_env.number.eql(primitives.U256.ZERO));
        std.debug.assert(std.mem.eql(u8, &block_env.beneficiary, &([_]u8{0} ** 20)));
        std.debug.assert(block_env.timestamp.eql(primitives.U256.ONE));
        std.debug.assert(block_env.gas_limit == std.math.maxInt(u64));
        std.debug.assert(block_env.basefee == 0);
        std.debug.assert(block_env.difficulty.eql(primitives.U256.ZERO));
        std.debug.assert(block_env.prevrandao != null);
        std.debug.assert(block_env.blob_excess_gas_and_price != null);

        std.debug.print("BlockEnv tests passed.\n", .{});
    }

    pub fn testTxEnv() !void {
        std.debug.print("Testing TxEnv...\n", .{});

        var tx_env = TxEnv.default();
        std.debug.assert(tx_env.tx_type == 0);
        std.debug.assert(std.mem.eql(u8, &tx_env.caller, &([_]u8{0} ** 20)));
        std.debug.assert(tx_env.gas_limit == 30000000); // EIP-7825 cap
        std.debug.assert(tx_env.gas_price == 0);
        std.debug.assert(tx_env.value.eql(primitives.U256.ZERO));
        std.debug.assert(tx_env.nonce == 0);
        std.debug.assert(tx_env.chain_id == 1);
        std.debug.assert(tx_env.access_list.len() == 0);
        std.debug.assert(tx_env.gas_priority_fee == null);
        std.debug.assert(tx_env.blob_hashes == null);
        std.debug.assert(tx_env.max_fee_per_blob_gas == 0);
        std.debug.assert(tx_env.authorization_list == null);

        std.debug.print("TxEnv tests passed.\n", .{});
    }

    pub fn testCfgEnv() !void {
        std.debug.print("Testing CfgEnv...\n", .{});

        const cfg_env = CfgEnv.default();
        std.debug.assert(cfg_env.chain_id == 1);
        std.debug.assert(cfg_env.tx_chain_id_check == true);
        std.debug.assert(cfg_env.spec == primitives.SpecId.prague);
        std.debug.assert(cfg_env.limit_contract_code_size == null);
        std.debug.assert(cfg_env.limit_contract_initcode_size == null);
        std.debug.assert(cfg_env.disable_nonce_check == false);
        std.debug.assert(cfg_env.max_blobs_per_tx == null);
        std.debug.assert(cfg_env.blob_base_fee_update_fraction == null);
        std.debug.assert(cfg_env.tx_gas_limit_cap == null);

        std.debug.print("CfgEnv tests passed.\n", .{});
    }

    pub fn testLocalContext() !void {
        std.debug.print("Testing LocalContext...\n", .{});

        var local_ctx = LocalContext.default();
        std.debug.assert(local_ctx.shared_memory_buffer == null);
        std.debug.assert(local_ctx.precompile_error_message == null);

        local_ctx.clear();
        std.debug.assert(local_ctx.shared_memory_buffer == null);
        std.debug.assert(local_ctx.precompile_error_message == null);

        std.debug.print("LocalContext tests passed.\n", .{});
    }

    pub fn testContext() !void {
        std.debug.print("Testing Context...\n", .{});

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var db = database.InMemoryDB.init(allocator);
        defer db.deinit();

        const ctx = Context.new(db, primitives.SpecId.prague);
        std.debug.assert(ctx.block.number.eql(primitives.U256.ZERO));
        std.debug.assert(ctx.tx.tx_type == 0);
        std.debug.assert(ctx.cfg.spec == primitives.SpecId.prague);
        std.debug.assert(ctx.local.shared_memory_buffer == null);
        std.debug.assert(ctx.ctx_error == ContextError.ok);

        std.debug.print("Context tests passed.\n", .{});
    }

    pub fn testEvm() !void {
        std.debug.print("Testing Evm...\n", .{});

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var db = database.InMemoryDB.init(allocator);
        defer db.deinit();

        const ctx = Context.new(db, primitives.SpecId.prague);
        const evm = Evm.new(ctx, {}, {});

        std.debug.assert(evm.ctx.block.number.eql(primitives.U256.ZERO));
        std.debug.assert(evm.ctx.tx.tx_type == 0);
        std.debug.assert(evm.ctx.cfg.spec == primitives.SpecId.prague);
        std.debug.assert(evm.ctx.local.shared_memory_buffer == null);
        std.debug.assert(evm.ctx.ctx_error == ContextError.ok);

        std.debug.print("Evm tests passed.\n", .{});
    }
};
