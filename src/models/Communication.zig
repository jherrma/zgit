const std = @import("std");

/// Bundles the process-wide I/O context that nearly every service needs:
/// the `Io` instance, the two output streams and the allocator.
pub const Communication = struct {
    io: std.Io,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    allocator: std.mem.Allocator,
};
