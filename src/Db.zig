//! Db interacts with an age encrypted sqlite database.
//!
const std = @import("std");
const sqlite = @import("sqlite");

const age = @import("age.zig");
const Config = @import("Config.zig");

/// controls the keys and filepaths used for saving
config: Config,

/// The underlying data store.
sql_db: sqlite.Db,

/// Set to true whenever the data updates. If false when close() is called,
/// the database will be closed without saving
changed: bool = false,

/// Decrypts the database into a temporary file and opens it in memory
// FIXME: Test me with real file
pub fn open(
    io: std.Io,
    gpa: std.mem.Allocator,
    opts: OpenOptions,
) !@This() {
    // TODO: Read from config?
    const db_path = try std.fs.path.join(gpa, &.{ opts.home, ".envr", "data.age" });
    defer gpa.free(db_path);

    var db = try new(opts.config);

    if (db_exists(io, db_path)) {
        // const tmp_dir = try std.Io.Dir.cwd().openDir(io, tmp, .{});
        // defer tmp_dir.deleteFile(io, "envr.db");

        const tmp_db_path = try std.fs.path.join(gpa, &.{ opts.tmp, "envr.db" });
        defer gpa.free(tmp_db_path);

        // TODO: Use std.MultiArrayList? Had json issues
        var private_keys: std.ArrayList([]const u8) = try .initCapacity(
            gpa,
            opts.config.keys.len,
        );

        for (opts.config.keys) |key| {
            private_keys.appendAssumeCapacity(key.private);
        }

        // TODO: Pass key(s) from Config
        try age.decrypt(io, gpa, private_keys.items, db_path, tmp_db_path);

        try db.restore(tmp_db_path);
        try std.Io.Dir.cwd().deleteFile(io, tmp_db_path);

        return db;
    } else {
        return db;
    }
}

const OpenOptions = struct {
    config: Config = .{},

    /// The path to the home directory
    home: []const u8 = "~/",
    /// The path to the /tmp directory
    // FIXME: Support windows
    tmp: []const u8 = "/tmp",
};

/// Create a new instance of the database in-memory
fn new(config: Config) !@This() {
    var db = try sqlite.Db.init(.{
        .mode = .Memory,
        .open_flags = .{ .write = true, .create = true },
        .threading_mode = .MultiThread,
    });

    try db.exec(
        \\create table envr_env_files (
        \\  path text primary key not null
        \\, remotes text -- JSON
        \\, sha256 text not null
        \\, contents text not null
        \\)
    , .{}, .{});

    return .{
        .sql_db = db,
        .config = config,
    };
}

/// Returns true if a file exists at ~/.envr/data.age
fn db_exists(io: std.Io, path: []const u8) bool {
    if (std.Io.Dir.cwd().access(io, path, .{ .read = true })) {
        return true;
    } else |_| {
        return false;
    }
}

/// Loads the unencrypted sqlite db at filepath path into the datbase
/// FIXME: Test me
fn restore(
    self: *@This(),
    path: []const u8,
) !void {
    try self.sql_db.exec(
        "ATTACH DATABASE ? AS source",
        .{},
        .{path},
    );
    defer self.sql_db.exec("DETACH DATABASE source", .{}, .{}) catch unreachable;

    try self.sql_db.exec(
        "INSERT INTO main.envr_env_files SELECT * FROM source.envr_env_files",
        .{},
        .{},
    );
}

// TODO: Finish
// pub fn tmpDir(opts: std.fs.Dir.OpenDirOptions) TmpDir {
//     var random_bytes: [TmpDir.random_bytes_count]u8 = undefined;
//     std.crypto.random.bytes(&random_bytes);
//     var sub_path: [TmpDir.sub_path_len]u8 = undefined;
//     _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);
// }
//
// const TmpDir = struct {};

/// Close the database
/// FIXME: Test me with data but no changes
/// FIXME: Test me with data and changes
pub fn close(
    self: *@This(),
    io: std.Io,
    gpa: std.mem.Allocator,
    opts: OpenOptions,
) !void {
    defer self.sql_db.deinit();

    if (self.changed) {
        const tmp_db_path = try std.fs.path.join(gpa, &.{ opts.tmp, "envr.db" });
        defer gpa.free(tmp_db_path);

        try self.sql_db.exec("VACUUM INTO ?", .{}, .{tmp_db_path});

        const db_path = try std.fs.path.join(gpa, &.{ opts.home, ".envr", "data.age" });
        defer gpa.free(db_path);

        // TODO: Use std.MultiArrayList? Had json issues
        var public_keys: std.ArrayList([]const u8) = try .initCapacity(
            gpa,
            opts.config.keys.len,
        );

        for (opts.config.keys) |key| {
            public_keys.appendAssumeCapacity(key.private);
        }

        try age.encrypt(io, gpa, public_keys.items, tmp_db_path, db_path);

        self.changed = false;
    }
}

test {
    std.testing.refAllDecls(@import("age.zig"));
}

test "simple database can be opened" {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "./fixtures/example.db" },
        .open_flags = .{
            .write = false,
            .create = false,
        },
        .threading_mode = .MultiThread,
    });

    var stmt = try db.prepare("SELECT * FROM hello");
    defer stmt.deinit();

    const alloc = std.testing.allocator;

    if (try stmt.oneAlloc(struct { text: []const u8 }, alloc, .{}, .{})) |got| {
        defer alloc.free(got.text);

        try std.testing.expectEqualSlices(u8, "world!", got.text);
    } else {
        return error.TestUnexpectedResult;
    }
}

test "encrypted database can be opened" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir_path);

    const decrypted_path = try std.fs.path.joinZ(gpa, &.{ dir_path, "example.db" });
    defer gpa.free(decrypted_path);

    try age.decrypt(
        io,
        gpa,
        &.{"./fixtures/insecure-test-key"},
        "./fixtures/encrypted-example.db.age",
        decrypted_path,
    );

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = decrypted_path },
        .open_flags = .{
            .write = false,
            .create = false,
        },
        .threading_mode = .MultiThread,
    });

    var stmt = try db.prepare("SELECT * FROM hello");
    defer stmt.deinit();

    const alloc = std.testing.allocator;

    if (try stmt.oneAlloc(struct { text: []const u8 }, alloc, .{}, .{})) |got| {
        defer alloc.free(got.text);

        try std.testing.expectEqualSlices(u8, "world!", got.text);
    } else {
        return error.TestUnexpectedResult;
    }
}

test "Closing a fresh database does not create a file" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // @compileLog(@typeInfo(std.Io.File.Permissions));
    try tmp_dir.dir.createDir(io, "home", .default_dir);
    try tmp_dir.dir.createDir(io, "tmp", .default_dir);

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(tmp_dir_path);

    const home = try std.fs.path.join(gpa, &.{ tmp_dir_path, "home" });
    defer gpa.free(home);
    const tmp = try std.fs.path.join(gpa, &.{ tmp_dir_path, "tmp" });
    defer gpa.free(tmp);

    var db: @This() = try .open(io, gpa, .{ .home = home, .tmp = tmp });

    const db_path = try std.fs.path.join(gpa, &.{ home, ".envr", "data.age" });
    defer gpa.free(db_path);

    try std.testing.expectError(
        error.FileNotFound,
        tmp_dir.dir.access(io, db_path, .{ .read = true }),
    );

    try db.close(io, gpa, .{ .home = home, .tmp = tmp });

    try std.testing.expectError(
        error.FileNotFound,
        tmp_dir.dir.access(io, db_path, .{ .read = true }),
    );
}

// test "Closing an unmodified database does not update the file" {}

// test "Closing a modified database does create a file" {}
