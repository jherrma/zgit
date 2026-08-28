const std = @import("std");

const Repository = @import("../models/Repository.zig").Repository;

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");
const errors_module = @import("../models/errors.zig");

pub fn initialize(io: std.Io, allocator: std.mem.Allocator, command: command_envelope_module.CommandEnvelope) !void {
    const discover_at_dir = if (command.parameters.len > 0) command.parameters[0] else null;

    const working_directory = discover_repository_module.get_working_directory(io, discover_at_dir) catch |err| {
        std.log.err("could not open working directory at {any} due to {any}", .{ discover_at_dir, err });
        return;
    };
    defer working_directory.close(io);

    const repository = discover_repository_module.discover_at_dir(io, allocator, working_directory);

    if (repository) |repo| {
        std.log.warn("found an existing repository, skipping init", .{});
        repo.dir.close(io);
        return;
    } else |err| switch (err) {
        errors_module.DiscoverRepositoryErrors.NotAGitRepository => {
            // continue
        },
        else => return err,
    }

    try createFilesAndDirectories(io, working_directory);
}

fn createFilesAndDirectories(io: std.Io, working_directory: std.Io.Dir) !void {
    createDirsForInit(io, working_directory) catch |err| {
        std.log.err("could not create directory due to {any}", .{err});
        return;
    };

    const head_file = working_directory.createFile(io, ".git/HEAD", std.Io.Dir.CreateFileOptions{ .exclusive = true }) catch |err| {
        std.log.err("could not create .git/HEAD due to {any}", .{err});
        return;
    };
    defer head_file.close(io);

    const config_file = working_directory.createFile(io, ".git/config", std.Io.Dir.CreateFileOptions{ .exclusive = true }) catch |err| {
        std.log.err("could not create .git/config due to {any}", .{err});
        return;
    };
    defer config_file.close(io);

    var file_writer_buffer: [1024]u8 = undefined;
    const header_content = "ref: refs/heads/main\n";
    var head_file_writer = head_file.writer(io, &file_writer_buffer);
    const head_file_writer_interface = &head_file_writer.interface;
    _ = head_file_writer_interface.write(header_content) catch |err| {
        std.log.err("could not write to .git/HEAD due to {any}", .{err});
        return;
    };
    try head_file_writer_interface.flush();

    const config_content = "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\nlogallrefupdates = true\n";
    var config_file_writer = config_file.writer(io, &file_writer_buffer);
    const config_file_writer_interface = &config_file_writer.interface;
    _ = config_file_writer_interface.write(config_content) catch |err| {
        std.log.err("could not write to .git/config due to {any}", .{err});
        return;
    };
    try config_file_writer_interface.flush();
}

fn createDirsForInit(io: std.Io, target_directory: std.Io.Dir) std.Io.Dir.CreateDirPathError!void {
    try target_directory.createDirPath(io, ".git/objects");
    try target_directory.createDirPath(io, ".git/refs/heads");
    try target_directory.createDirPath(io, ".git/refs/tags");
}
