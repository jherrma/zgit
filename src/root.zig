//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const command_envelope_module = @import("models/command_envelope.zig");
const argument_parser_module = @import("services/argument_parser.zig");
const init_command_module = @import("services/init_repository.zig");
const cat_file_module = @import("services//cat_file.zig");

pub fn run(init: std.process.Init, args: []const [:0]const u8) !u8 {
    const parsed_command = argument_parser_module.parseArgs(args) catch |err| switch (err) {
        command_envelope_module.CommandEnvelopeError.UnknownCommand => {
            std.log.info("received unknown command, printing help", .{});
            return 0;
        },
    };

    switch (parsed_command.command) {
        command_envelope_module.Command.init => try init_command_module.initialize(init.io, init.arena.allocator(), parsed_command),
        command_envelope_module.Command.cat_file => return handle_cat_file(init.io, init.arena.allocator(), parsed_command),
        command_envelope_module.Command.help => std.log.info("This is the help message", .{}),
    }

    return 0;
}

fn handle_cat_file(io: std.Io, allocator: std.mem.Allocator, command: command_envelope_module.CommandEnvelope) !u8 {
    const status = try cat_file_module.cat_file(io, allocator, command);
    return status;
}
