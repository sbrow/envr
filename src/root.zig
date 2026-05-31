//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const Command = @import("comma").Command;

const Config = @import("Config.zig");
const Db = @import("Db.zig");
const tabula = @import("./tabula.zig");

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
    defer arena.free(cfgPath);

    var cfg = (try Config.load(io, arena, cfgPath));
    defer cfg.deinit();

    var db: Db = try .open(io, arena, .{
        .config = cfg.value,
        .home = home,
        .tmp = tmp,
    });

    const files = try db.list(arena);
    defer arena.free(files);

    const table: tabula.Table(Db.EnvFile, .initOne(.path)) = .{ .items = files };
    try out.print("{f}", .{table});
    try out.flush();

    try db.close(io, arena); // TODO: Defer this

    for (files) |*file| {
        file.deinit(arena);
    }
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

test "list returns a table" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.createDir(io, "home", .default_dir);
    try tmp_dir.dir.createDir(io, "home/.envr", .default_dir);
    try tmp_dir.dir.createDir(io, "home/.ssh", .default_dir);
    try tmp_dir.dir.createDir(io, "tmp", .default_dir);

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(tmp_dir_path);

    const home = try std.fs.path.join(gpa, &.{ tmp_dir_path, "home" });
    defer gpa.free(home);
    const tmp = try std.fs.path.join(gpa, &.{ tmp_dir_path, "tmp" });
    defer gpa.free(tmp);

    try std.Io.Dir.cwd().copyFile(
        "fixtures/encrypted-single-file.db.age",
        tmp_dir.dir,
        "home/.envr/data.age",
        io,
        .{},
    );

    try std.Io.Dir.cwd().copyFile(
        "fixtures/default_config.json",
        tmp_dir.dir,
        "home/.envr/config.json",
        io,
        .{},
    );

    try std.Io.Dir.cwd().copyFile(
        "fixtures/insecure-test-key",
        tmp_dir.dir,
        "home/.ssh/id_ed25519",
        io,
        .{},
    );

    try std.Io.Dir.cwd().copyFile(
        "fixtures/insecure-test-key.pub",
        tmp_dir.dir,
        "home/.ssh/id_ed25519.pub",
        io,
        .{},
    );

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    // Run Test

    try list(
        io,
        std.testing.allocator,
        &out.writer,
        home,
        tmp,
    );

    const got = try out.toOwnedSlice();
    defer gpa.free(got);

    try std.testing.expectEqualStrings(
        \\┌────────────────────────┐
        \\│          path          │
        \\├────────────────────────┤
        \\│ ~/project/.env.example │
        \\└────────────────────────┘
        \\
    , got);
}
