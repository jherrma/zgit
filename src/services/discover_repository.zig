const std = @import("std");

const Communication = @import("../models/Communication.zig").Communication;
const Repository = @import("../models/Repository.zig").Repository;
const errors_module = @import("../models/errors.zig");

pub fn get_working_directory(communication: Communication, path: ?[:0]const u8) std.Io.Dir.OpenError!std.Io.Dir {
    if (path == null or path.?.len == 0) {
        return std.Io.Dir.cwd();
    } else {
        const param_dir = std.Io.Dir.cwd().openDir(communication.io, path.?, std.Io.Dir.OpenOptions{ .iterate = true });

        return param_dir;
    }
}

pub fn discover_at_dir(communication: Communication, working_directory: std.Io.Dir) errors_module.DiscoverRepositoryErrors!*Repository {
    var cwd = working_directory;
    const working_dir_parameter_stats = cwd.stat(communication.io) catch {
        return errors_module.DiscoverRepositoryErrors.DirError;
    };
    const cwd_fd = working_dir_parameter_stats.inode;

    while (true) {
        const git_dir = cwd.openDir(communication.io, ".git", std.Io.Dir.OpenOptions{}) catch {
            // no git dir, walk up
            const old_cwd = cwd;

            const old_cwd_stat = old_cwd.stat(communication.io) catch {
                old_cwd.close(communication.io);
                return errors_module.DiscoverRepositoryErrors.DirError;
            };

            // dir from parameter is owned by calling function, we must not close the dir of the caller here
            defer {
                if (old_cwd_stat.inode != cwd_fd) {
                    defer old_cwd.close(communication.io);
                }
            }

            cwd = cwd.openDir(communication.io, "..", std.Io.Dir.OpenOptions{}) catch {
                return errors_module.DiscoverRepositoryErrors.NotAGitRepository;
            };

            const cwd_stat = cwd.stat(communication.io) catch {
                cwd.close(communication.io);
                return errors_module.DiscoverRepositoryErrors.DirError;
            };

            if (old_cwd_stat.inode == cwd_stat.inode) {
                cwd.close(communication.io);
                return errors_module.DiscoverRepositoryErrors.NotAGitRepository;
            }

            continue;
        };

        const cwd_stats = cwd.stat(communication.io) catch {
            git_dir.close(communication.io);
            return errors_module.DiscoverRepositoryErrors.DirError;
        };

        defer {
            if (cwd_stats.inode != working_dir_parameter_stats.inode) {
                cwd.close(communication.io);
            }
        }

        const repository = communication.allocator.create(Repository) catch {
            git_dir.close(communication.io);
            return errors_module.DiscoverRepositoryErrors.OutOfMemory;
        };
        repository.* = Repository{ .dir = git_dir };
        return repository;
    }

    unreachable;
}

pub fn discover(communication: Communication, path: ?[:0]const u8) !*Repository {
    const target_directory = get_working_directory(communication, path) catch |err| {
        try communication.stderr.print("could not open dir due to {any}\n", .{err});
        return errors_module.DiscoverRepositoryErrors.OpenDirError;
    };

    return discover_at_dir(communication, target_directory);
}

/// Builds a `Communication` for tests: real `Io` and allocator, output captured
/// in fixed buffers so a test never writes to the terminal.
fn testCommunication(stdout_buffer: []u8, stderr_buffer: []u8, stdout: *std.Io.Writer, stderr: *std.Io.Writer) Communication {
    stdout.* = std.Io.Writer.fixed(stdout_buffer);
    stderr.* = std.Io.Writer.fixed(stderr_buffer);
    return Communication{
        .io = std.testing.io,
        .stdout = stdout,
        .stderr = stderr,
        .allocator = std.testing.allocator,
    };
}

test "discover_at_dir finds .git directly in the given directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(std.testing.io, ".git", .default_dir);

    var stdout_buffer: [256]u8 = undefined;
    var stderr_buffer: [256]u8 = undefined;
    var stdout: std.Io.Writer = undefined;
    var stderr: std.Io.Writer = undefined;
    const communication = testCommunication(&stdout_buffer, &stderr_buffer, &stdout, &stderr);

    const repository = try discover_at_dir(communication, tmp.dir);
    defer std.testing.allocator.destroy(repository);
    defer repository.dir.close(std.testing.io);

    const found_stat = try repository.dir.stat(std.testing.io);
    const git_dir = try tmp.dir.openDir(std.testing.io, ".git", .{});
    defer git_dir.close(std.testing.io);
    const expected_stat = try git_dir.stat(std.testing.io);

    try std.testing.expectEqual(expected_stat.inode, found_stat.inode);
}

test "discover_at_dir finds .git further up in directory tree" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(std.testing.io, ".git", .default_dir);
    try tmp.dir.createDir(std.testing.io, "subdirectory", .default_dir);
    const subdirecotry = try tmp.dir.openDir(std.testing.io, "subdirectory", std.Io.Dir.OpenOptions{});
    defer subdirecotry.close(std.testing.io);

    var stdout_buffer: [256]u8 = undefined;
    var stderr_buffer: [256]u8 = undefined;
    var stdout: std.Io.Writer = undefined;
    var stderr: std.Io.Writer = undefined;
    const communication = testCommunication(&stdout_buffer, &stderr_buffer, &stdout, &stderr);

    const repository = try discover_at_dir(communication, subdirecotry);
    defer std.testing.allocator.destroy(repository);
    defer repository.dir.close(std.testing.io);

    const found_stat = try repository.dir.stat(std.testing.io);
    const git_dir = try tmp.dir.openDir(std.testing.io, ".git", .{});
    defer git_dir.close(std.testing.io);
    const expected_stat = try git_dir.stat(std.testing.io);

    try std.testing.expectEqual(expected_stat.inode, found_stat.inode);
}
