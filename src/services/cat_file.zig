const std = @import("std");

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");
const object_helper_module = @import("../utils/object_helper.zig");

const Communication = @import("../models/Communication.zig").Communication;
const Repository = @import("../models/Repository.zig").Repository;
const OpenObjectError = @import("../models/errors.zig").OpenObjectError;
const tree_iterator_module = @import("../utils/tree_iterator.zig");

const exists_flag = "-e";
const print_flag = "-p";
const size_flag = "-s";
const type_flag = "-t";

const CatFlag = enum {
    exists,
    print,
    size,
    type_flag,
    unknown,
};

/// Implementation of the cat-file command
/// As of now, it only supports -p, -t, -s and -e as arguments
pub fn cat_file(communication: Communication, command: command_envelope_module.CommandEnvelope) !u8 {
    if (command.parameters.len < 2) {
        try communication.stderr.print("usage: zgit cat-file <type> <object>\n", .{});
        try communication.stderr.print("\tzgit cat-file (-e | -p | -t | -s) <object>\n", .{});
        return 0;
    }

    const flag = if (std.mem.eql(u8, command.parameters[0], exists_flag)) CatFlag.exists else if (std.mem.eql(u8, command.parameters[0], print_flag)) CatFlag.print else if (std.mem.eql(u8, command.parameters[0], type_flag)) CatFlag.type_flag else if (std.mem.eql(u8, command.parameters[0], size_flag)) CatFlag.size else CatFlag.unknown;

    if (flag == CatFlag.unknown) {
        try communication.stderr.print("error: unknown switch '{s}'\n", .{command.parameters[0]});
        return 1;
    }

    if (command.parameters[1].len < 4) {
        try communication.stderr.print("fatal: Not a valid object name {s}\n", .{command.parameters[1]});
        return 1;
    }

    const object_hash = command.parameters[1];
    const object_file_handle = try object_helper_module.get_git_object(communication, object_hash, null);

    defer object_file_handle.close(communication.io);

    const decompressor = try object_helper_module.get_decompressor(communication, object_file_handle);

    switch (flag) {
        CatFlag.exists => return 0,
        CatFlag.size => try size(communication, decompressor),
        CatFlag.type_flag => try object_type(communication, decompressor),
        CatFlag.print => try print(communication, decompressor),
        CatFlag.unknown => return 1,
    }

    return 0;
}

fn size(communication: Communication, decompressor: *std.compress.flate.Decompress) !void {
    _ = try decompressor.reader.takeDelimiterExclusive(' ');
    const size_section = try decompressor.reader.takeDelimiterExclusive(0x00);
    // skip the leading ' '
    try communication.stdout.print("{s}\n", .{size_section[1..]});
}

fn object_type(communication: Communication, decompressor: *std.compress.flate.Decompress) !void {
    const type_section = try decompressor.reader.takeDelimiterExclusive(' ');
    try communication.stdout.print("{s}\n", .{type_section});
}

fn print(communication: Communication, decompressor: *std.compress.flate.Decompress) !void {
    const type_section = try decompressor.reader.takeDelimiterExclusive(' ');
    const size_string = try decompressor.reader.takeDelimiterExclusive(0x00);

    // skip the leading ' ' when parsing
    const payload_size = try std.fmt.parseInt(usize, size_string[1..], 10);
    const payload = try communication.allocator.alloc(u8, payload_size);
    // discard the null byte
    _ = try decompressor.reader.take(1);
    try decompressor.reader.readSliceAll(payload);

    if (!std.mem.eql(u8, type_section, "tree")) {
        try communication.stdout.print("{s}\n", .{payload});
    }

    var iterator = tree_iterator_module.new(payload);

    while (try iterator.next()) |entry| {
        const hash_string: [40]u8 = std.fmt.bytesToHex(entry.oid, .lower);
        const object_type_name = @tagName(entry.object_type);
        try communication.stdout.print("{:0>6} {s} {s}\t{s}\n", .{ entry.mode, object_type_name, hash_string, entry.name });
    }
}
