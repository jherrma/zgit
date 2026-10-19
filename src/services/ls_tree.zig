const std = @import("std");

const Communication = @import("../models/Communication.zig").Communication;
const ObjectType = @import("../models/enums.zig").ObjectType;
const Repository = @import("../models/Repository.zig").Repository;
const TreeEntry = @import("../models/tree_entry.zig").TreeEntry;

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");
const object_helper_module = @import("../utils/object_helper.zig");
const tree_iterator_module = @import("../utils/tree_iterator.zig");

const LsTreeOptions = struct {
    object_hash: [:0]const u8,
    recursive: bool,
    name_only: bool,
    unknown_option: bool,
};

pub fn ls_tree(communication: Communication, command: command_envelope_module.CommandEnvelope) !u8 {
    // example command: git ls-tree 832eb0ee5f4e4e02fbd0f671014247066dbdf102 -r --name-only

    if (command.parameters.len < 1) {
        try communication.stderr.print("usage: zgit ls-tree [<options>] <tree-ish>\n", .{});
        try communication.stderr.print("\tzgit ls-tree (-r | --name-only) <object>\n", .{});
        return 0;
    }

    const ls_tree_options = try parse_parameters(communication, command);

    if (ls_tree_options.unknown_option) {
        try communication.stderr.print("error: unknown switch '{s}'\n", .{command.parameters[0]});
        return 1;
    }

    if (ls_tree_options.object_hash.len < 4) {
        try communication.stderr.print("fatal: Not a valid object name {s}\n", .{command.parameters[1]});
        return 1;
    }

    return try print_tree(communication, ls_tree_options, ls_tree_options.object_hash, "");
}

fn parse_parameters(communication: Communication, command: command_envelope_module.CommandEnvelope) !LsTreeOptions {
    var ls_tree_options = LsTreeOptions{
        .object_hash = "",
        .name_only = false,
        .recursive = false,
        .unknown_option = false,
    };

    for (command.parameters) |param| {
        if (std.mem.eql(u8, param, "-r")) {
            ls_tree_options.recursive = true;
            continue;
        }

        if (std.mem.eql(u8, param, "--name-only")) {
            ls_tree_options.name_only = true;
            continue;
        }

        if (param[0] == '-') {
            try communication.stderr.print("error: unknown switch '{s}'\n", .{param[1..]});
            ls_tree_options.unknown_option = true;
            return ls_tree_options;
        }

        if (std.mem.eql(u8, ls_tree_options.object_hash, "")) {
            ls_tree_options.object_hash = param;
            continue;
        } else {
            try communication.stderr.print("only one object hash at a time is supported\n", .{});
            ls_tree_options.unknown_option = true;
            return ls_tree_options;
        }
    }

    return ls_tree_options;
}

fn print_tree(communication: Communication, ls_tree_options: LsTreeOptions, object_hash: []const u8, prefix: []const u8) !u8 {
    const object_file_handle = try object_helper_module.get_git_object(communication, object_hash, null);

    defer object_file_handle.close(communication.io);

    const decompressor = try object_helper_module.get_decompressor(communication, object_file_handle);

    const type_section = try decompressor.reader.takeDelimiterExclusive(' ');
    if (!std.mem.eql(u8, type_section, "tree")) {
        try communication.stderr.print("fatal: not a tree object", .{});
        return 1;
    }

    const size_string = try decompressor.reader.takeDelimiterExclusive(0x00);

    // skip the leading ' ' when parsing
    const payload_size = try std.fmt.parseInt(usize, size_string[1..], 10);
    const payload = try communication.allocator.alloc(u8, payload_size);

    // discard the null byte
    _ = try decompressor.reader.take(1);
    try decompressor.reader.readSliceAll(payload);

    var iterator = tree_iterator_module.new(payload);

    while (try iterator.next()) |entry| {
        const hash_string: [40]u8 = std.fmt.bytesToHex(entry.oid, .lower);
        const object_type_name = @tagName(entry.object_type);
        const path = try std.fmt.allocPrint(communication.allocator, "{s}{s}", .{ prefix, entry.name });

        if (ls_tree_options.recursive and std.mem.eql(u8, object_type_name, "tree")) {
            const child_prefix = try std.fmt.allocPrint(communication.allocator, "{s}/", .{path});
            const status = try print_tree(communication, ls_tree_options, hash_string[0..], child_prefix);
            if (status != 0) {
                return status;
            }
        } else {
            try print_tree_line(communication, ls_tree_options, entry, hash_string[0..], object_type_name, path);
        }
    }

    return 0;
}

fn print_tree_line(communication: Communication, ls_tree_options: LsTreeOptions, entry: TreeEntry, hash_string: []const u8, object_type_name: [:0]const u8, path: []const u8) !void {
    if (ls_tree_options.name_only) {
        try communication.stdout.print("{s}\n", .{path});
        return;
    }

    try communication.stdout.print("{:0>6} {s} {s}\t{s}\n", .{ entry.mode, object_type_name, hash_string, path });
}
