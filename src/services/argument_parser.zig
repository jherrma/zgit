const std = @import("std");

const command_envelope_module = @import("../models/command_envelope.zig");

pub fn parseArgs(args: []const [:0]const u8) command_envelope_module.CommandEnvelopeError!command_envelope_module.CommandEnvelope {
    if (args.len < 2) {
        return command_envelope_module.CommandEnvelope{
            .command = command_envelope_module.Command.help,
            .parameters = undefined,
        };
    }

    if (std.mem.eql(u8, args[1], "init")) {
        return command_envelope_module.CommandEnvelope{
            .command = command_envelope_module.Command.init,
            .parameters = args[2..],
        };
    }

    return command_envelope_module.CommandEnvelopeError.UnknownCommand;
}

test "parseArgs with no command returns help" {
    const result = try parseArgs(&.{"zgit"});
    try std.testing.expectEqual(command_envelope_module.Command.help, result.command);
}

test "parseArgs with no matching command returns unknown command" {
    const result = parseArgs(&.{ "zgit", "unknown" });
    try std.testing.expectError(command_envelope_module.CommandEnvelopeError.UnknownCommand, result);
}

test "parseArgs with init command returns init" {
    const result = try parseArgs(&.{ "zgit", "init" });
    try std.testing.expectEqual(command_envelope_module.Command.init, result.command);
    try std.testing.expectEqualDeep(&.{}, result.parameters);
}

test "parseArgs with init command and parameters returns init with parameters" {
    const result = try parseArgs(&.{ "zgit", "init", "/tmp/zgit" });
    try std.testing.expectEqual(command_envelope_module.Command.init, result.command);
    try std.testing.expectEqualDeep(&.{"/tmp/zgit"}, result.parameters);
}
