//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const comma = @import("comma");
const Command = comma.Command;

pub const root: Command = .new(.{
    .name = "envr",
    .subcommands = &.{.{ .name = "version" }},
});

test "enum type" {
    const got: root.Type = @enumFromInt(1);

    try std.testing.expectEqual(.version, got);
}

test "parse version" {
    const args = &[_][]const u8{"version"};
    const cmd = root.parse(args);

    try std.testing.expectEqual(.version, cmd);
}
