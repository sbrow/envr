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
    // FIXME: cheating here
    const db_path = try std.fs.path.join(gpa, &.{
        opts.home,
        opts.config.db_path[2..],
    });
    defer gpa.free(db_path);

    // const tmp_dir = try std.Io.Dir.cwd().openDir(io, tmp, .{});
    // defer tmp_dir.deleteFile(io, "envr.db");

    const tmp_db_path = try std.fs.path.joinZ(gpa, &.{ opts.tmp, "envr.db" });
    defer gpa.free(tmp_db_path);

    if (db_exists(io, db_path)) {
        // TODO: Use std.MultiArrayList? Had json issues
        {
            var private_keys: std.ArrayList([]const u8) = try .initCapacity(
                gpa,
                opts.config.keys.len,
            );
            defer private_keys.deinit(gpa);

            for (opts.config.keys) |key| {
                private_keys.appendAssumeCapacity(key.private);
            }

            // TODO: Pass key(s) from Config
            try age.decrypt(io, gpa, private_keys.items, db_path, tmp_db_path);
        }
    }

    return open_decrypted(opts.config, tmp_db_path);
}

const OpenOptions = struct {
    config: Config = .{},

    /// The path to the home directory
    home: []const u8 = "~/",
    /// The path to the /tmp directory
    // FIXME: Support windows
    tmp: []const u8 = "/tmp",
};

/// Create a new instance of the database
fn open_decrypted(config: Config, tmp_db_path: [:0]const u8) !@This() {
    var db = try sqlite.Db.init(.{
        .mode = .{ .File = tmp_db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });

    try db.exec(
        \\create table if not exists envr_env_files (
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

        {
            // TODO: Use std.MultiArrayList? Had json issues
            var public_keys: std.ArrayList([]const u8) = try .initCapacity(
                gpa,
                opts.config.keys.len,
            );
            defer public_keys.deinit(gpa);

            for (opts.config.keys) |key| {
                public_keys.appendAssumeCapacity(key.private);
            }

            try age.encrypt(io, gpa, public_keys.items, tmp_db_path, db_path);
        }

        self.changed = false;
    }
}

/// Returns a list of all the .env files present in the database.
/// The caller is responsible for freeing memory
fn list(self: *@This(), gpa: std.mem.Allocator) ![]EnvFile {
    var stmt = try self.sql_db.prepare(
        "select path, remotes, sha256, contents from envr_env_files",
    );
    defer stmt.deinit();

    return stmt.all(EnvFile, gpa, .{}, .{});
}

const EnvFile = struct {
    // TODO: Should use file_name in the struct and derive from the path.
    path: []const u8,

    // /// dir is derived from Path, and is not stored in the database.
    // dir: []const u8,

    /// JSON encoded list of strings
    remotes: []const u8,
    sha256: []const u8,
    contents: []const u8,

    fn deinit(self: *EnvFile, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
        alloc.free(self.remotes);
        alloc.free(self.sha256);
        alloc.free(self.contents);
    }
};

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

    try tmp_dir.dir.createDir(io, "home", .default_dir);
    try tmp_dir.dir.createDir(io, "tmp", .default_dir);

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(tmp_dir_path);

    const home = try std.fs.path.join(gpa, &.{ tmp_dir_path, "home" });
    defer gpa.free(home);
    const tmp = try std.fs.path.join(gpa, &.{ tmp_dir_path, "tmp" });
    defer gpa.free(tmp);

    // TODO: Pass testing keys
    var db: @This() = try .open(io, gpa, .{ .home = home, .tmp = tmp });

    // TODO: Get rid of direct access
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

test "single-file.db has envr_env_files table" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    const dir_path = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir_path);

    const path = try std.fs.path.joinZ(
        gpa,
        &.{ dir_path, "fixtures", "single-file.db" },
    );
    defer gpa.free(path);

    var db = try sqlite.Db.init(.{
        .mode = .{ .File = path },
        .open_flags = .{
            .write = false,
            .create = false,
        },
        .threading_mode = .MultiThread,
    });

    var diags: sqlite.Diagnostics = .{};
    var stmt = db.prepareDynamicWithDiags(
        "select name from sqlite_master where type='table'",
        .{ .diags = &diags },
    ) catch |err| {
        std.log.err(
            "unable to prepare statement, got error {}. diagnostics: {f}",
            .{ err, diags },
        );
        return err;
    };
    defer stmt.deinit();

    const tables = (try stmt.oneAlloc(
        []const u8,
        gpa,
        .{ .diags = &diags },
        .{},
    )).?;
    defer gpa.free(tables);

    try std.testing.expectEqualSlices(u8, "envr_env_files", tables);
}

// test "raw restore works" {
//     const io = std.testing.io;
//     const gpa = std.testing.allocator;

//     var db = try sqlite.Db.init(.{
//         .mode = .Memory,
//         .open_flags = .{
//             .write = true,
//             .create = true,
//         },
//         .threading_mode = .MultiThread,
//     });

//     try db.exec(
//         \\create table envr_env_files (
//         \\  path text primary key not null
//         \\, remotes text -- JSON
//         \\, sha256 text not null
//         \\, contents text not null
//         \\)
//     , .{}, .{});

//     const dir_path = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", gpa);
//     defer gpa.free(dir_path);

//     const path = try std.fs.path.join(
//         gpa,
//         &.{ dir_path, "fixtures", "single-file.db" },
//     );
//     defer gpa.free(path);

//     std.debug.print("path: {s}\n", .{path});
//     try db.exec(
//         "ATTACH DATABASE ? AS source",
//         .{},
//         .{path},
//     );
//     defer db.exec("DETACH DATABASE source", .{}, .{}) catch unreachable;

//     var diags: sqlite.Diagnostics = .{};
//     db.exec(
//         "INSERT INTO main.envr_env_files SELECT * FROM source.envr_env_files",
//         .{ .diags = &diags },
//         .{},
//     ) catch |err| {
//         std.log.err(
//             "unable to prepare statement, got error {}. diagnostics: {f}",
//             .{ err, diags },
//         );
//         return err;
//     };
// }

// test "Closing a modified database does create a file" {}

test "list displays the database's keys" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.createDir(io, "home", .default_dir);
    try tmp_dir.dir.createDir(io, "home/.envr", .default_dir);
    try tmp_dir.dir.createDir(io, "tmp", .default_dir);

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(tmp_dir_path);

    const home = try std.fs.path.join(gpa, &.{ tmp_dir_path, "home" });
    defer gpa.free(home);
    const tmp = try std.fs.path.join(gpa, &.{ tmp_dir_path, "tmp" });
    defer gpa.free(tmp);

    // TODO: Get rid of direct access
    const db_path = try std.fs.path.join(gpa, &.{ home, ".envr", "data.age" });
    defer gpa.free(db_path);

    try std.Io.Dir.cwd().copyFile(
        "fixtures/encrypted-single-file.db.age",
        tmp_dir.dir,
        "home/.envr/data.age",
        io,
        .{},
    );

    // Asserts file existence
    try tmp_dir.dir.access(io, db_path, .{ .read = true });

    // TODO: Pass testing keys
    const config: Config = .{
        .keys = &.{.from_pub_path("fixtures/insecure-test-key.pub")},
    };
    var db: @This() = try .open(io, gpa, .{
        .config = config,
        .home = home,
        .tmp = tmp,
    });

    const env_files = try db.list(gpa);
    defer gpa.free(env_files);
    try std.testing.expectEqual(1, env_files.len);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    try std.testing.expectEqual(1, env_files.len);

    for (env_files) |*file| {
        defer file.deinit(gpa);

        try std.testing.expectEqualSlices(
            u8,
            "~/project/.env.example",
            file.path,
        );
        try std.testing.expectEqualSlices(
            u8,
            "API_KEY=\\\"sk_my_api_key\\\"\\nAPP_ENV=testing",
            file.contents,
        );
        try std.testing.expectEqualSlices(
            u8,
            "[\"git@github.com:user/project.git\"]",
            file.remotes,
        );

        hasher.update(file.contents);
        const hash = hasher.finalResult();
        try std.testing.expectEqualStrings(&std.fmt.bytesToHex(&hash, .lower), file.sha256);
    }

    try db.close(io, gpa, .{ .home = home, .tmp = tmp });
}
