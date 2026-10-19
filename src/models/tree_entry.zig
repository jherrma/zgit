const enums_module = @import("enums.zig");

pub const TreeEntry = struct {
    mode: u32,
    object_type: enums_module.ObjectType,
    name: []const u8,
    oid: [20]u8,
};
