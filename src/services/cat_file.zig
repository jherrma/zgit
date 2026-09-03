const std = @import("std");

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");
const Repository = @import("../models/Repository.zig").Repository;
const OpenObjectError = @import("../models/errors.zig").OpenObjectError;

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
pub fn cat_file(io: std.Io, allocator: std.mem.Allocator, command: command_envelope_module.CommandEnvelope) !u8 {
    if (command.parameters.len < 2) {
        std.debug.print("usage: zgit cat-file <type> <object>\n", .{});
        std.debug.print("\tzgit cat-file (-e | -p | -t | -s) <object>\n", .{});
        return 0;
    }

    const flag = if (std.mem.eql(u8, command.parameters[0], exists_flag)) CatFlag.exists else if (std.mem.eql(u8, command.parameters[0], print_flag)) CatFlag.print else if (std.mem.eql(u8, command.parameters[0], type_flag)) CatFlag.type_flag else if (std.mem.eql(u8, command.parameters[0], size_flag)) CatFlag.size else CatFlag.unknown;

    if (flag == CatFlag.unknown) {
        std.debug.print("error: unknown switch '{s}'\n", .{command.parameters[0]});
        return 1;
    }

    if (command.parameters[1].len < 4) {
        std.debug.print("fatal: Not a valid object name {s}\n", .{command.parameters[1]});
        return 1;
    }

    const repository = discover_repository_module.discover(io, allocator, null) catch |err| {
        std.log.err("could not open repository due to {any}\n", .{err});
        return 1;
    };

    errdefer std.log.err("fatal: Not a valid object name {s}\n", .{command.parameters[1]});

    const object_file_handle = exists(io, allocator, repository, command) catch {
        return 1;
    };

    defer object_file_handle.close(io);

    const decompressor = try get_decompressor(io, allocator, object_file_handle);

    switch (flag) {
        CatFlag.exists => return 0,
        CatFlag.size => try size(decompressor),
        CatFlag.type_flag => try object_type(decompressor),
        CatFlag.print => try print(decompressor, allocator),
        CatFlag.unknown => return 1,
    }

    return 0;
}

fn exists(io: std.Io, allocator: std.mem.Allocator, repository: *Repository, command: command_envelope_module.CommandEnvelope) !std.Io.File {
    // check if the blob for this sha exists at .git/objects/<sha[..2]/sha[2..]
    // if not, print "fatal: Not a valid object name <sha in parameter>"
    // prints for object names shorter than 4 characters

    const prefix = command.parameters[1][0..2];
    const suffix = command.parameters[1][2..];

    const objects_dir = try repository.dir.openDir(io, "objects", std.Io.Dir.OpenOptions{});
    defer objects_dir.close(io);
    const prefix_dir = try objects_dir.openDir(io, prefix, std.Io.Dir.OpenOptions{ .iterate = true });
    defer prefix_dir.close(io);

    const elegible_file_name = try allocator.alloc(u8, 38);
    var filename_set = false;
    const suffix_length = suffix.len;

    var iter = prefix_dir.iterate();

    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.eql(u8, suffix, entry.name[0..suffix_length])) {
            if (!filename_set) {
                std.mem.copyForwards(u8, elegible_file_name, entry.name);
                filename_set = true;
            } else {
                return OpenObjectError.AmbigousName;
            }
        }
    }

    if (!filename_set) {
        return OpenObjectError.FileNotFound;
    }

    const object_file = try prefix_dir.openFile(io, elegible_file_name, std.Io.Dir.OpenFileOptions{});

    return object_file;
}

fn get_decompressor(io: std.Io, allocator: std.mem.Allocator, file: std.Io.File) !*std.compress.flate.Decompress {
    const buffer_reading_file = try allocator.alloc(u8, 4096);
    const buffer_decompressing = try allocator.alloc(u8, std.compress.flate.max_window_len);

    var reader = std.Io.File.reader(file, io, buffer_reading_file);
    const reader_interface = &reader.interface;
    const decompressor = try allocator.create(std.compress.flate.Decompress);
    decompressor.* = std.compress.flate.Decompress.init(reader_interface, .zlib, buffer_decompressing);
    return decompressor;
}

fn size(decompressor: *std.compress.flate.Decompress) !void {
    _ = try decompressor.reader.takeDelimiterExclusive(' ');
    const size_section = try decompressor.reader.takeDelimiterExclusive(0x00);
    // skip the leading ' '
    std.debug.print("{s}\n", .{size_section[1..]});
}

fn object_type(decompressor: *std.compress.flate.Decompress) !void {
    const type_section = try decompressor.reader.takeDelimiterExclusive(' ');
    std.debug.print("{s}\n", .{type_section});
}

fn print(decompressor: *std.compress.flate.Decompress, allocator: std.mem.Allocator) !void {
    _ = try decompressor.reader.takeDelimiterExclusive(' ');
    const size_string = try decompressor.reader.takeDelimiterExclusive(0x00);

    // skip the leading ' ' when parsing
    const payload_size = try std.fmt.parseInt(usize, size_string[1..], 10);
    const payload = try allocator.alloc(u8, payload_size);
    try decompressor.reader.readSliceAll(payload);
    std.debug.print("{s}\n", .{payload});
}
