const std = @import("std");

const Repository = @import("../models/Repository.zig").Repository;
const errors_module = @import("../models/errors.zig");

pub fn get_working_directory(io: std.Io, path: ?[:0]const u8) std.Io.Dir.OpenError!std.Io.Dir {
    if (path == null or path.?.len == 0) {
        return std.Io.Dir.cwd();
    } else {
        const param_dir = std.Io.Dir.cwd().openDir(io, path.?, std.Io.Dir.OpenOptions{ .iterate = true });

        return param_dir;
    }
}

pub fn discover_at_dir(io: std.Io, allocator: std.mem.Allocator, working_directory: std.Io.Dir) errors_module.DiscoverRepositoryErrors!*Repository {
    var cwd = working_directory;
    const working_dir_parameter_stats = cwd.stat(io) catch {
        return errors_module.DiscoverRepositoryErrors.DirError;
    };
    const cwd_fd = working_dir_parameter_stats.inode;

    while (true) {
        const git_dir = cwd.openDir(io, ".git", std.Io.Dir.OpenOptions{}) catch {
            // no git dir, walk up
            const old_cwd = cwd;

            const old_cwd_stat = old_cwd.stat(io) catch {
                old_cwd.close(io);
                return errors_module.DiscoverRepositoryErrors.DirError;
            };

            // dir from parameter is owned by calling function, we must not close the dir of the caller here
            defer {
                if (old_cwd_stat.inode != cwd_fd) {
                    defer old_cwd.close(io);
                }
            }

            cwd = cwd.openDir(io, "..", std.Io.Dir.OpenOptions{}) catch {
                return errors_module.DiscoverRepositoryErrors.NotAGitRepository;
            };

            const cwd_stat = cwd.stat(io) catch {
                cwd.close(io);
                return errors_module.DiscoverRepositoryErrors.DirError;
            };

            if (old_cwd_stat.inode == cwd_stat.inode) {
                cwd.close(io);
                return errors_module.DiscoverRepositoryErrors.NotAGitRepository;
            }

            continue;
        };

        const cwd_stats = cwd.stat(io) catch {
            git_dir.close(io);
            return errors_module.DiscoverRepositoryErrors.DirError;
        };

        defer {
            if (cwd_stats.inode != working_dir_parameter_stats.inode) {
                cwd.close(io);
            }
        }

        const repository = allocator.create(Repository) catch {
            git_dir.close(io);
            return errors_module.DiscoverRepositoryErrors.OutOfMemory;
        };
        repository.* = Repository{ .dir = git_dir };
        return repository;
    }

    unreachable;
}

pub fn discover(io: std.Io, allocator: std.mem.Allocator, path: ?[:0]const u8) errors_module.DiscoverRepositoryErrors!*Repository {
    const target_directory = get_working_directory(io, path) catch |err| {
        std.log.err("could not open dir due to {any}", .{err});
        return errors_module.DiscoverRepositoryErrors.OpenDirError;
    };

    return discover_at_dir(io, allocator, target_directory);
}

test "discover_at_dir finds .git directly in the given directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDir(std.testing.io, ".git", .default_dir);

    const repository = try discover_at_dir(std.testing.io, std.testing.allocator, tmp.dir);
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

    const repository = try discover_at_dir(std.testing.io, std.testing.allocator, subdirecotry);
    defer std.testing.allocator.destroy(repository);
    defer repository.dir.close(std.testing.io);

    const found_stat = try repository.dir.stat(std.testing.io);
    const git_dir = try tmp.dir.openDir(std.testing.io, ".git", .{});
    defer git_dir.close(std.testing.io);
    const expected_stat = try git_dir.stat(std.testing.io);

    try std.testing.expectEqual(expected_stat.inode, found_stat.inode);
}
