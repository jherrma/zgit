const std = @import("std");

const Communication = @import("../models/Communication.zig").Communication;
const ObjectType = @import("../models/enums.zig").ObjectType;
const Repository = @import("../models/Repository.zig").Repository;

const command_envelope_module = @import("../models/command_envelope.zig");
const discover_repository_module = @import("discover_repository.zig");

pub fn ls_tree(communication: Communication, command: command_envelope_module.CommandEnvelope) !u8 {

    // if object is not a tree, print: "fatal: not a tree object"
}
