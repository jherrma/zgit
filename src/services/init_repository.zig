const std = @import("std");

const Communication = @import("../models/Communication.zig").Communication;
const Repository = @import("../models/Repository.zig").Repository;

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");
const errors_module = @import("../models/errors.zig");

pub fn initialize(communication: Communication, command: command_envelope_module.CommandEnvelope) !void {
    const discover_at_dir = if (command.parameters.len > 0) command.parameters[0] else null;

    const working_directory = discover_repository_module.get_working_directory(communication, discover_at_dir) catch |err| {
        try communication.stderr.print("could not open working directory at {any} due to {any}\n", .{ discover_at_dir, err });
        return;
    };
    defer working_directory.close(communication.io);

    const repository = discover_repository_module.discover_at_dir(communication, working_directory);

    if (repository) |repo| {
        try communication.stdout.print("found an existing repository, skipping init\n", .{});
        repo.dir.close(communication.io);
        return;
    } else |err| switch (err) {
        errors_module.DiscoverRepositoryErrors.NotAGitRepository => {
            // continue
        },
        else => return err,
    }

    try createFilesAndDirectories(communication, working_directory);
}

fn createFilesAndDirectories(communication: Communication, working_directory: std.Io.Dir) !void {
    createDirsForInit(communication, working_directory) catch |err| {
        try communication.stderr.print("could not create directory due to {any}\n", .{err});
        return;
    };

    const head_file = working_directory.createFile(communication.io, ".git/HEAD", std.Io.Dir.CreateFileOptions{ .exclusive = true }) catch |err| {
        try communication.stderr.print("could not create .git/HEAD due to {any}\n", .{err});
        return;
    };
    defer head_file.close(communication.io);

    const config_file = working_directory.createFile(communication.io, ".git/config", std.Io.Dir.CreateFileOptions{ .exclusive = true }) catch |err| {
        try communication.stderr.print("could not create .git/config due to {any}\n", .{err});
        return;
    };
    defer config_file.close(communication.io);

    var file_writer_buffer: [1024]u8 = undefined;
    const header_content = "ref: refs/heads/main\n";
    var head_file_writer = head_file.writer(communication.io, &file_writer_buffer);
    const head_file_writer_interface = &head_file_writer.interface;
    _ = head_file_writer_interface.write(header_content) catch |err| {
        try communication.stderr.print("could not write to .git/HEAD due to {any}\n", .{err});
        return;
    };
    try head_file_writer_interface.flush();

    const config_content = "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\nlogallrefupdates = true\n";
    var config_file_writer = config_file.writer(communication.io, &file_writer_buffer);
    const config_file_writer_interface = &config_file_writer.interface;
    _ = config_file_writer_interface.write(config_content) catch |err| {
        try communication.stderr.print("could not write to .git/config due to {any}\n", .{err});
        return;
    };
    try config_file_writer_interface.flush();
}

fn createDirsForInit(communication: Communication, target_directory: std.Io.Dir) std.Io.Dir.CreateDirPathError!void {
    try target_directory.createDirPath(communication.io, ".git/objects");
    try target_directory.createDirPath(communication.io, ".git/refs/heads");
    try target_directory.createDirPath(communication.io, ".git/refs/tags");
}
