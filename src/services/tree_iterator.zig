const std = @import("std");

const TreeEntry = @import("../models/tree_entry.zig").TreeEntry;
const ObjectType = @import("../models/enums.zig").ObjectType;

pub fn new(payload: []u8) TreeIterator {
    return TreeIterator{
        .payload = payload,
        .pos = 0,
    };
}

const TreeIterator = struct {
    payload: []u8,
    pos: usize = 0,

    pub fn next(self: *TreeIterator) !?TreeEntry {
        if (self.pos >= self.payload.len) return null;

        var mode_pos = self.pos;
        while (true) {
            if (self.payload[mode_pos] == ' ') {
                break;
            }
            mode_pos += 1;
        }

        const mode_string = self.payload[self.pos..mode_pos];
        const mode = try std.fmt.parseInt(u32, mode_string, 10);
        self.pos = mode_pos + 1; // + 1 since we want to skip the space

        var name_pos = self.pos;
        while (true) {
            if (self.payload[name_pos] == 0x00) {
                break;
            }
            name_pos += 1;
        }

        const name = self.payload[self.pos..name_pos];
        self.pos = name_pos + 1; // + 1 since we want to skip the 0x00

        const oid: *[20]u8 = @ptrCast(&self.payload[self.pos]);

        self.pos += 20;

        const tree_entry = TreeEntry{
            .mode = mode,
            .name = name,
            .object_type = parse_mode(mode),
            .oid = oid.*,
        };

        return tree_entry;
    }
};

fn parse_mode(mode: u32) ObjectType {
    if (mode == 40_000) return ObjectType.tree;
    if (mode < 160_000) return ObjectType.blob;
    return ObjectType.commit;
}
