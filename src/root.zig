//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const comma = @import("comma");
const Command = comma.Command;

const Config = @import("Config.zig");
const Db = @import("Db.zig");

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
            .name = "list",
            .short = "View your tracked files",
        },
        .{
            .name = "version",
            .short = "Show envr's version",
        },
    },
});

pub fn list(
    io: Io,
    arena: std.mem.Allocator,
    out: *std.Io.Writer,
    home: []const u8,
    tmp: []const u8,
) !void {
    // TODO: Don't hardcode
    const cfgPath = try std.fs.path.join(arena, &.{ home, ".envr", "config.json" });
    const cfg: Config = (try Config.load(io, arena, cfgPath)).value;

    var db: Db = try .open(io, arena, .{
        .config = cfg,
        .home = home,
        .tmp = tmp,
    });

    _ = try out.write("Path\n");
    const files = try db.list(arena);
    for (files) |file| {
        // TODO: Table printer
        try out.print("{s}\n", .{file.path});
    }
    try out.flush();

    return db.close(io, arena); // TODO: Defer this
}

test {
    std.testing.refAllDecls(@import("Config.zig"));
    std.testing.refAllDecls(@import("Db.zig"));
}

test "enum type" {
    const got: root.Type = @enumFromInt(3);

    try std.testing.expectEqual(.version, got);
}

test "parse deps" {
    const args = &[_][]const u8{"deps"};
    const cmd = root.parse(args);

    try std.testing.expectEqual(.deps, cmd);
}

test "parse list" {
    const args = &[_][]const u8{"list"};
    const cmd = root.parse(args);

    try std.testing.expectEqual(.list, cmd);
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
