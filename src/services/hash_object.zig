const std = @import("std");

const Communication = @import("../models/Communication.zig").Communication;
const ObjectType = @import("../models/enums.zig").ObjectType;
const Repository = @import("../models/Repository.zig").Repository;

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");

const HashObjectFlag = enum {
    write,
    stdin,
    type,
    unknown,
};

const HashObjectParameters = struct {
    switches: HashObjectSwitches,
    file_paths: []const [:0]const u8,
};

const HashObjectSwitches = struct {
    is_write: bool,
    is_stdin: bool,
    is_type: bool,
    object_type: ObjectType,
    object_type_string: [:0]const u8,
    is_unknown_parameter: bool,
};

const tmp_dir = "objects/tmp_obj";

pub fn hash_object(communication: Communication, command: command_envelope_module.CommandEnvelope) !u8 {
    if (command.parameters.len == 0) {
        try communication.stderr.print("usage: zgit hash-object [-t <type>] [-w] [--stdin] [--] <path>...\n", .{});
        return 1;
    }

    const hash_parameters = try parse_parameters(communication, command.parameters);

    if (hash_parameters.switches.is_unknown_parameter) {
        return 1;
    }

    const repository = discover_repository_module.discover(communication, null) catch |err| {
        try communication.stderr.print("could not open repository due to {any}\n", .{err});
        return 1;
    };

    for (hash_parameters.file_paths) |path| {
        _ = try hash_file(communication, hash_parameters.switches, path, repository);
    }

    return 0;
}

fn parse_parameters(communication: Communication, parameters: []const [:0]const u8) !HashObjectParameters {
    var path_index: usize = 0;
    var paths = try communication.allocator.alloc([:0]const u8, parameters.len);

    var hash_object_parameters: HashObjectParameters = .{
        .switches = HashObjectSwitches{
            .is_write = false,
            .is_stdin = false,
            .is_type = false,
            .object_type = .blob, // blob is default
            .object_type_string = "blob",
            .is_unknown_parameter = false,
        },
        .file_paths = paths,
    };

    var i: usize = 0;
    while (i < parameters.len) {
        const param = parameters[i];

        if (std.mem.eql(u8, "-w", param)) {
            hash_object_parameters.switches.is_write = true;
            i += 1;
            continue;
        }

        if (std.mem.eql(u8, "--stdin", param)) {
            try communication.stderr.print("error: stdin is not yet implemented\n", .{});
            hash_object_parameters.switches.is_unknown_parameter = true;
            return hash_object_parameters;

            //hash_object_parameters.switches.is_stdin = true;
            //i += 1;
            //continue;
        }

        if (std.mem.eql(u8, "-t", param)) {
            hash_object_parameters.switches.is_type = true;

            if (i + 1 > parameters.len - 1) {
                try communication.stderr.print("error: switch 't' requires a value\n", .{});
                hash_object_parameters.switches.is_unknown_parameter = true;
                return hash_object_parameters;
            }

            const converted_object_type = std.meta.stringToEnum(ObjectType, parameters[i + 1]);

            if (converted_object_type == null) {
                try communication.stderr.print("error: switch 't' requires a value\n", .{});
                hash_object_parameters.switches.is_unknown_parameter = true;
                return hash_object_parameters;
            }

            hash_object_parameters.switches.object_type = converted_object_type.?;

            // store the u8 bytes separately
            hash_object_parameters.switches.object_type_string = parameters[i + 1];

            i += 2;
            continue;
        }

        if (param[0] == '-') {
            try communication.stderr.print("error: unknown switch '{s}'\n", .{param[1..]});
            hash_object_parameters.switches.is_unknown_parameter = true;
            return hash_object_parameters;
        }

        paths[path_index] = param;
        path_index += 1;
        i += 1;
    }

    hash_object_parameters.file_paths = paths[0..path_index];

    return hash_object_parameters;
}

fn hash_file(communication: Communication, switches: HashObjectSwitches, path: [:0]const u8, repository: *Repository) !u8 {
    const file = std.Io.Dir.cwd().openFile(communication.io, path, .{ .mode = .read_only }) catch |err| {
        if (err == std.Io.File.OpenError.FileNotFound) {
            try communication.stderr.print("fatal: could not open '{s}' for reading: No such file or directory\n", .{path});
            return 1;
        }

        if (err == std.Io.File.OpenError.IsDir) {
            try communication.stderr.print("fatal: could not open '{s}' for reading: File is a directory\n", .{path});
            return 1;
        }

        if (err == std.Io.File.OpenError.AccessDenied) {
            try communication.stderr.print("fatal: could not open '{s}' for reading: Access denied\n", .{path});
            return 1;
        }

        return err;
    };
    defer file.close(communication.io);

    const file_stats = try file.stat(communication.io);
    const size = file_stats.size;
    const size_string = try std.fmt.allocPrint(communication.allocator, "{d}", .{size});
    const object_type_string = switches.object_type_string;

    const file_buffer = try communication.allocator.alloc(u8, 4096);
    var file_reader = file.reader(communication.io, file_buffer);

    const tmp_file = if (switches.is_write) try create_temp_file(communication, repository) else null;
    defer {
        if (tmp_file != null) {
            tmp_file.?.close(communication.io);
            repository.dir.deleteFile(communication.io, tmp_dir) catch {};
        }
    }

    const tmp_file_writer_interface: ?*std.Io.Writer = if (tmp_file) |tf| blk: {
        const tmp_file_writer_buffer = try communication.allocator.alloc(u8, 4096);
        const tmp_file_writer = try communication.allocator.create(std.Io.File.Writer);
        tmp_file_writer.* = tf.writer(communication.io, tmp_file_writer_buffer);
        break :blk &tmp_file_writer.interface;
    } else null;

    const compressor = if (tmp_file_writer_interface) |wi| try get_compressor(communication, wi) else null;

    var sha1_hasher = std.crypto.hash.Sha1.init(std.crypto.hash.Sha1.Options{});
    sha1_hasher.update(object_type_string);
    try write_compressor_conditionally(compressor, object_type_string);

    const space_byte = [_]u8{' '};
    sha1_hasher.update(&space_byte);
    sha1_hasher.update(size_string);
    try write_compressor_conditionally(compressor, &space_byte);
    try write_compressor_conditionally(compressor, size_string);

    const zero_byte = [_]u8{0};
    sha1_hasher.update(&zero_byte);
    try write_compressor_conditionally(compressor, &zero_byte);

    const reader_buffer = try communication.allocator.alloc(u8, 4096);

    while (true) {
        const bytes_read = try file_reader.interface.readSliceShort(reader_buffer);
        sha1_hasher.update(reader_buffer[0..bytes_read]);
        try write_compressor_conditionally(compressor, reader_buffer[0..bytes_read]);

        if (bytes_read < reader_buffer.len) {
            break;
        }
    }

    if (compressor) |c| {
        try c.finish();
    }

    if (tmp_file_writer_interface) |w| {
        try w.flush();
    }

    const hash = sha1_hasher.finalResult();
    const hash_string: [40]u8 = std.fmt.bytesToHex(hash, .lower);

    try communication.stdout.print("{s}\n", .{hash_string});

    if (switches.is_write) {
        try write_to_disk(communication, repository, &hash_string);
    }

    return 0;
}

fn get_compressor(communication: Communication, writer: *std.Io.Writer) !*std.compress.flate.Compress {
    const compressor_buffer = try communication.allocator.alloc(u8, std.compress.flate.max_window_len);
    const compressor = try communication.allocator.create(std.compress.flate.Compress);
    compressor.* = try std.compress.flate.Compress.init(writer, compressor_buffer, .zlib, std.compress.flate.Compress.Options.default);
    return compressor;
}

fn write_compressor_conditionally(compressor: ?*std.compress.flate.Compress, bytes: []const u8) !void {
    if (compressor == null) {
        return;
    }

    _ = try compressor.?.writer.write(bytes);
}

fn create_temp_file(communication: Communication, repository: *Repository) !std.Io.File {
    return repository.dir.createFile(communication.io, tmp_dir, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => blk: {
            try repository.dir.deleteFile(communication.io, tmp_dir);
            break :blk try repository.dir.createFile(communication.io, tmp_dir, .{ .exclusive = true });
        },
        else => return err,
    };
}

fn write_to_disk(communication: Communication, repository: *Repository, hash: []const u8) !void {
    // target: .git/objects/<first-2-hex-chars>/<remaining-38-hex-chars>
    const prefix = "objects/" ++ hash[0..2];
    const suffix = hash[2..40];

    const prefix_directory = try repository.dir.createDirPathOpen(communication.io, prefix, std.Io.Dir.CreateDirPathOpenOptions{});
    defer prefix_directory.close(communication.io);

    const destination_file_exists = prefix_directory.openFile(communication.io, suffix, std.Io.Dir.OpenFileOptions{});

    if (destination_file_exists) |value| {
        // file exists, no-op
        value.close(communication.io);
        return;
    } else |err| {
        if (err != std.Io.File.OpenError.FileNotFound) {
            return err;
        }
    }

    try std.Io.Dir.rename(repository.dir, tmp_dir, prefix_directory, suffix, communication.io);
}
