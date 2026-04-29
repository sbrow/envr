//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const comma = @import("comma");
const Command = comma.Command;

pub const root: Command = .new(.{
    .name = "envr",
    .short = "Manage your .env files.",
    .long =
    \\envr keeps your .env synced to a local, age encrypted database.
    \\It is a safe and eay way to gather all your .env files in one place where they can
    \\easily be backed by another tool such as restic or git.
    \\All your data is stored in ~/data.age
    \\
    \\Getting started is easy:
    \\
    \\1. Create your configuration file and set up encrypted storage:
    \\
    \\> envr init
    \\
    \\2. Scan for existing .env files:
    \\
    \\> envr scan
    \\
    \\Select the files you want to back up from the interactive list.
    \\
    \\3. Verify that it worked:
    \\
    \\> envr list
    \\
    \\4. After changing any of your .env files, update the backup with:
    \\
    \\> envr sync
    \\
    \\5. If you lose a repository, after re-cloning the repo into the same path it was
    \\at before, restore your backup with:
    \\
    \\> envr restore <path to repository> .env
    ,
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
        .{
            .name = "version",
            .short = "Show envr's version",
        },
    },
});

test {
    std.testing.refAllDecls(@import("Config.zig"));
    std.testing.refAllDecls(@import("Db.zig"));
}

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
    const args = &[_][]const u8{ "bad", "value" };
    const cmd = root.parse(args);

    try std.testing.expectEqual(.unknown, cmd);
}
