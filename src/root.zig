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
            .name = "init",
            .short = "Set up envr",
            .long =
            \\The init command generates your initial config and saves it to
            \\~/.envr/config in JSON format.
            \\
            \\During setup, you will be prompted to select one or more ssh keys with which to
            \\encrypt your databse. **Make 100% sure** that you have **a remote copy** of this
            \\key somewhere, otherwise your data could be lost forever.
            ,
            //.flags =  struct { force: bool }
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

// Display dependency statuses
pub fn deps(
    io: Io,
    writer: *Io.Writer,
    path: []const u8,
) !void {
    const feats: Features = try .scan(io, path);

    // FIXME: Draw as a table
    try writer.print("features: {}", .{feats});
    try writer.flush();
}

const Features = packed struct {
    git: bool = false,
    fd: bool = false,
    const all_features: Features = .{
        .git = true,
        .fd = true,
    };

    /// Scans your PATH variable for programs.
    pub fn scan(io: Io, path: []const u8) !@This() {
        var feats: Features = .{};

        var dirs = std.mem.splitScalar(u8, path, std.fs.path.delimiter);

        loop: while (dirs.next()) |dir| {
            const dirt = Io.Dir.openDir(Io.Dir.cwd(), io, dir, .{ .follow_symlinks = true, .iterate = true }) catch continue;
            defer dirt.close(io);

            var dir_paths = dirt.iterate();

            while (try dir_paths.next(io)) |file| {
                // FIXME: Check if executable
                if (std.mem.eql(u8, std.fs.path.basename(file.name), "git")) {
                    feats.git = true;

                    if (feats == Features.all_features) {
                        break :loop;
                    }
                }

                if (std.mem.eql(u8, std.fs.path.basename(file.name), "fd")) {
                    feats.fd = true;

                    if (feats == Features.all_features) {
                        break :loop;
                    }
                }
            }
        }

        return feats;
    }
};

pub fn init_cmd(
    io: Io,
    arena: std.mem.Allocator,
    out: *std.Io.Writer,
    home: []const u8,
    flags: struct { force: bool },
) !void {
    defer out.flush() catch unreachable;

    // TODO: Don't hardcode
    const cfgPath = try std.fs.path.join(arena, &.{ home, ".envr", "config.json" });
    defer arena.free(cfgPath);

    if (flags.force or !file_exists(io, cfgPath)) {
        const keys = try select_ssh_keys(io, arena, home, out);

        // defer {
        // for (keys) |*key| {
        // arena.destroy(key);
        // }
        // arena.free(&keys);
        // }

        // const cfg: Config = .{ .keys = keys };
        // TODO: How to handle this error?
        // try cfg.save(io, cfgPath);

        try out.print(
            "Config initialized with {} SSH key(s). You are ready to use envr.\n",
            .{keys.len},
        );
    } else {
        try out.writeAll(
            \\You have already initialized envr.
            \\Run again with the --force flag if you want to reinitialize.
            \\
            ,
        );
    }
}

/// Returns true if the file exists
fn file_exists(io: std.Io, path: []const u8) bool {
    if (std.Io.Dir.cwd().access(io, path, .{ .read = true })) {
        return true;
    } else |_| {
        return false;
    }
}

/// Returns a list of keys that the user has selected to add to their config.
/// Caller owns the returned memory
// TODO: Write a test for this
fn select_ssh_keys(
    io: std.Io,
    alloc: std.mem.Allocator,
    home_path: []const u8,
    out: *std.Io.Writer,
) ![]Config.SSHKeyPair {
    const ssh_path = try std.fs.path.join(alloc, &.{ home_path, ".ssh" });
    defer alloc.free(ssh_path);

    // TODO: Arbitrary capacity chosen
    var keys: std.ArrayList(Config.SSHKeyPair) = try .initCapacity(alloc, 3);

    {
        const ssh_dir = try std.Io.Dir.cwd().openDir(io, ssh_path, .{ .iterate = true });
        defer ssh_dir.close(io);

        var itr = ssh_dir.iterate();

        const expect1 =
            \\-----BEGIN OPENSSH PRIVATE KEY-----
            \\
        ;

        const expect2 =
            \\-----BEGIN RSA PRIVATE KEY-----
            \\
        ;

        var buf: [expect1.len]u8 = undefined;

        while (try itr.next(io)) |entry| {
            switch (entry.kind) {
                .file => {
                    var file = try ssh_dir.openFile(io, entry.name, .{});
                    _ = try file.readPositionalAll(io, &buf, 0);

                    // TODO: Faster to use hash or something?
                    if ( // zig fmt: off
                        std.mem.eql(u8, expect1, &buf) or 
                        std.mem.eql(u8, expect2, buf[0..expect2.len])
                       ) { // zig fmt: on
                        // File is a private ssh key

                        const full_path = try ssh_dir.realPathFileAlloc(
                            io,
                            entry.name,
                            alloc,
                        );

                        try keys.append(alloc, try .from_path(alloc, full_path));
                    }
                },
                .sym_link => {
                    // TODO: Handle symlinks
                },
                .block_device,
                .character_device,
                .directory,
                .named_pipe,
                .unix_domain_socket,
                .whiteout,
                .door,
                .event_port,
                .unknown,
                => continue,
            }
        }
    }

    for (keys.items, 1..) |key, n| {
        try out.print("{d}. {s}\n", .{ n, key.private });
    }
    try out.writeAll(
        "\nPlease enter the number(s) of SSH keys you'd like to use for encryption:\n> ",
    );
    try out.flush();
    defer out.writeAll("\n\n") catch unreachable;

    // TODO: ask user for number(s) to use.
    // TODO: confirm with a y/n prompt
    // TODO: only return selected keys

    return keys.toOwnedSlice(alloc);
}

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
