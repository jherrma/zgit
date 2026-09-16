const std = @import("std");
const Io = std.Io;

const zgit = @import("zgit");

pub fn main(init: std.process.Init) !u8 {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;

    // Flush on every exit path, including an error returned by `run` —
    // otherwise buffered diagnostics are lost exactly when they matter.
    defer stderr_writer.flush() catch {};
    defer stdout_writer.flush() catch {};

    return try zgit.run(init, stdout_writer, stderr_writer, args);
}
