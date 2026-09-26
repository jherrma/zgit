//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const Communication = @import("models/Communication.zig").Communication;

const command_envelope_module = @import("models/command_envelope.zig");
const argument_parser_module = @import("services/argument_parser.zig");
const init_command_module = @import("services/init_repository.zig");
const cat_file_module = @import("services//cat_file.zig");
const hash_object_module = @import("services/hash_object.zig");
const ls_tree_module = @import("services/ls_tree.zig");

pub fn run(init: std.process.Init, stdout_writer: *std.Io.Writer, stderr_writer: *std.Io.Writer, args: []const [:0]const u8) !u8 {
    const communication = Communication{
        .io = init.io,
        .stdout = stdout_writer,
        .stderr = stderr_writer,
        .allocator = init.arena.allocator(),
    };

    const parsed_command = argument_parser_module.parseArgs(args) catch |err| switch (err) {
        command_envelope_module.CommandEnvelopeError.UnknownCommand => {
            try communication.stderr.print("zgit: '{s}' is not a zgit command\n", .{args[1]});
            return 1;
        },
    };

    switch (parsed_command.command) {
        command_envelope_module.Command.init => try init_command_module.initialize(communication, parsed_command),
        command_envelope_module.Command.cat_file => return handle_cat_file(communication, parsed_command),
        command_envelope_module.Command.hash_object => return hash_object_module.hash_object(communication, parsed_command),
        command_envelope_module.Command.ls_tree => return ls_tree_module.ls_tree(),
        command_envelope_module.Command.help => try communication.stdout.print("This is the help message\n", .{}),
    }

    return 0;
}

fn handle_cat_file(communication: Communication, command: command_envelope_module.CommandEnvelope) !u8 {
    const status = try cat_file_module.cat_file(communication, command);
    return status;
}
