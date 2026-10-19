const std = @import("std");

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("../services/discover_repository.zig");

const Communication = @import("../models/Communication.zig").Communication;
const Repository = @import("../models/Repository.zig").Repository;
const OpenObjectError = @import("../models/errors.zig").OpenObjectError;

pub fn exists(communication: Communication, repository: *Repository, object_hash: []const u8) !std.Io.File {
    // check if the blob for this sha exists at .git/objects/<sha[..2]/sha[2..]
    // if not, print "fatal: Not a valid object name <sha in parameter>"
    // prints for object names shorter than 4 characters

    const prefix = object_hash[0..2];
    const suffix = object_hash[2..];

    const objects_dir = try repository.dir.openDir(communication.io, "objects", std.Io.Dir.OpenOptions{});
    defer objects_dir.close(communication.io);
    const prefix_dir = try objects_dir.openDir(communication.io, prefix, std.Io.Dir.OpenOptions{ .iterate = true });
    defer prefix_dir.close(communication.io);

    const elegible_file_name = try communication.allocator.alloc(u8, 38);
    var filename_set = false;
    const suffix_length = suffix.len;

    var iter = prefix_dir.iterate();

    while (try iter.next(communication.io)) |entry| {
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

    const object_file = try prefix_dir.openFile(communication.io, elegible_file_name, std.Io.Dir.OpenFileOptions{});

    return object_file;
}

pub fn get_decompressor(communication: Communication, file: std.Io.File) !*std.compress.flate.Decompress {
    const buffer_reading_file = try communication.allocator.alloc(u8, 4096);
    const buffer_decompressing = try communication.allocator.alloc(u8, std.compress.flate.max_window_len);

    var reader = std.Io.File.reader(file, communication.io, buffer_reading_file);
    const reader_interface = &reader.interface;
    const decompressor = try communication.allocator.create(std.compress.flate.Decompress);
    decompressor.* = std.compress.flate.Decompress.init(reader_interface, .zlib, buffer_decompressing);
    return decompressor;
}

pub fn get_git_object(communication: Communication, object_hash: []const u8, path: ?[:0]const u8) !std.Io.File {
    const repository = discover_repository_module.discover(communication, path) catch |err| {
        try communication.stderr.print("could not open repository due to {any}\n", .{err});
        return err;
    };

    const object_file_handle = exists(communication, repository, object_hash) catch |err| {
        try communication.stderr.print("fatal: Not a valid object name {s}\n", .{object_hash});
        return err;
    };

    return object_file_handle;
}
