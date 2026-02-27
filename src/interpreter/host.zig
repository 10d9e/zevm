const primitives = @import("primitives");

const Address = primitives.Address;
const U256 = primitives.U256;

pub const Host = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        sload: *const fn (*anyopaque, Address, U256) U256,
        sstore: *const fn (*anyopaque, Address, U256, U256) void,
        balance: *const fn (*anyopaque, Address) U256,
        code: *const fn (*anyopaque, Address) []const u8,
        codeSize: *const fn (*anyopaque, Address) usize,
        codeHash: *const fn (*anyopaque, Address) U256,
        blockHash: *const fn (*anyopaque, U256) U256,
    };

    pub fn sload(self: Host, addr: Address, key: U256) U256 {
        return self.vtable.sload(self.ptr, addr, key);
    }

    pub fn sstore(self: Host, addr: Address, key: U256, val: U256) void {
        self.vtable.sstore(self.ptr, addr, key, val);
    }

    pub fn balance(self: Host, addr: Address) U256 {
        return self.vtable.balance(self.ptr, addr);
    }

    pub fn code(self: Host, addr: Address) []const u8 {
        return self.vtable.code(self.ptr, addr);
    }

    pub fn codeSize(self: Host, addr: Address) usize {
        return self.vtable.codeSize(self.ptr, addr);
    }

    pub fn codeHash(self: Host, addr: Address) U256 {
        return self.vtable.codeHash(self.ptr, addr);
    }

    pub fn blockHash(self: Host, number: U256) U256 {
        return self.vtable.blockHash(self.ptr, number);
    }
};
