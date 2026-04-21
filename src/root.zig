//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const comma = @import("comma");
const Command = comma.Command;

pub const root: Command = .new(.{
    .name = "envr",
    .subcommands = &.{
        .{
            .name = "deps",
            .short = "Check for missing binaries",
            .long =
            \\envr relies on external binaries for certain functionality.
            \\
            \\ The deps command reports which binaries are available and which are not."
            ,
        },
        .{ .name = "version" },
    },
});

test "enum type" {
    const got: root.Type = @enumFromInt(2);

    try std.testing.expectEqual(.version, got);
}

test "parse version" {
    const args = &[_][]const u8{"version"};
    const cmd = root.parse(args);

    try std.testing.expectEqual(.version, cmd);
}

test "parse unknown" {
    const args = &[_][]const u8{"bad", "value"};
    const cmd = root.parse(args);

    try std.testing.expectEqual(.unknown, cmd);
}
