const std = @import("std");

const TreeEntry = struct {
    mode: u32,
    name: []const u8,
    oid: [20]u8,
};

const TreeIterator = struct {
    payload: []const u8,
    pos: usize = 0,

    fn next(self: *TreeIterator) ?TreeEntry {
        if (self.pos >= self.payload.len) return null;

        // 1. read mode digits from self.payload[self.pos..] until a space
        // 2. advance self.pos past mode + space
        // 3. read name from self.payload[self.pos..] until '\0'
        // 4. advance self.pos past name + '\0'
        // 5. copy the next 20 bytes as oid
        // 6. advance self.pos by 20
        // 7. return the assembled TreeEntry
    }
};
