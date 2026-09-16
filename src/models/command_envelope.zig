pub const Command = enum {
    help,
    init,
    cat_file,
    hash_object,
};

pub const CommandEnvelope = struct {
    command: Command,
    parameters: []const [:0]const u8,
};

pub const CommandEnvelopeError = error{
    UnknownCommand,
};
