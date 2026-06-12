const std = @import("std");

pub const DceMode = enum {
    no,
    std,
    full,

    pub fn parse(text: []const u8) ?DceMode {
        if (std.mem.eql(u8, text, "no")) return .no;
        if (std.mem.eql(u8, text, "std")) return .std;
        if (std.mem.eql(u8, text, "full")) return .full;
        return null;
    }

    pub fn name(self: DceMode) []const u8 {
        return switch (self) {
            .no => "no",
            .std => "std",
            .full => "full",
        };
    }
};

pub const EmitOptions = struct {
    debug: bool = false,
    wasm_compat: bool = false,
    jobs: ?usize = null,
    test_mode: bool = false,
    codegen_unit_index: ?usize = null,
    codegen_unit_count: usize = 1,
    dce: DceMode = .std,
    std_root: ?[]const u8 = null,
};
