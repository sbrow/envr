const std = @import("std");

db_path: []const u8 = "~/.envr/data.age",

/// Keys that are available for encryption
keys: []const SSHKeyPair = &.{
    .from_pub_path("~/.ssh/id_ed25519.pub"),
},

/// Rules for how to match the scan command
scan: ScanConfig = .default,

// TODO: Allow incomplete pairs
pub const SSHKeyPair = struct {
    private: []const u8,
    public: []const u8,

    /// Caller owns the returned memory
    pub fn from_path(gpa: std.mem.Allocator, path: []const u8) !SSHKeyPair {
        if (std.mem.eql(u8, std.fs.path.extension(path), ".pub")) {
            return from_pub_path(path);
        } else {
            return .{
                .public = try std.mem.concat(gpa, u8, &.{ path, ".pub" }),
                .private = path,
            };
        }
    }

    pub fn from_pub_path(path: []const u8) SSHKeyPair {
        std.debug.assert(std.mem.eql(u8, std.fs.path.extension(path), ".pub"));

        return .{
            .public = path,
            .private = path[0 .. path.len - 4],
        };
    }
};

/// Configuration for the scan command
pub const ScanConfig = struct {
    /// the file extension to look for
    matcher: []const u8,

    /// Glob patterns to ignore
    exclude: []const []const u8,

    /// paths to search in
    include: []const []const u8,

    const default: @This() = .{
        .matcher = "\\.env",
        .exclude = &.{
            "*\\.envrc",
            "\\.local",
            "node_modules",
            "vendor",
        },
        .include = &.{"~"},
    };
};

/// Load the Config from the file at path
pub fn load(
    io: std.Io,
    gpa: std.mem.Allocator,
    path: []const u8,
) !std.json.Parsed(@This()) {
    var file = try std.Io.Dir.cwd().openFile(
        io,
        path,
        .{ .mode = .read_only },
    );
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);

    var json_reader: std.json.Reader = .init(gpa, &reader.interface);
    defer json_reader.deinit();

    return try std.json.parseFromTokenSource(
        @This(),
        gpa,
        &json_reader,
        .{},
    );
}

/// Save the config to the given file
pub fn save(
    self: *@This(),
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
) !void {
    // TODO: Remove dependence on string?
    var string: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer string.deinit();

    try string.writer.print(
        "{f}",
        .{std.json.fmt(self, .{ .whitespace = .indent_2 })},
    );

    var file = try dir.createFile(io, path, .{ .truncate = true });
    defer file.close(io);

    try file.writeStreamingAll(io, string.written());
}

test "loading the default config from disk matches expected values" {
    const gpa = std.testing.allocator;

    const parsed = try load(std.testing.io, gpa, "./fixtures/default_config.json");
    defer parsed.deinit();

    const got = parsed.value;
    try std.testing.expectEqualDeep(got.scan, ScanConfig.default);
}

test "saving to a new file upserts the file" {
    const io = std.testing.io;

    var cfg: @This() = .{};

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var dir = tmp.dir;

    try std.testing.expectError(
        error.FileNotFound,
        dir.statFile(io, "config.json", .{}),
    );

    try cfg.save(io, dir, "config.json");

    const contents = try dir.readFileAlloc(
        io,
        "config.json",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(contents);

    const want =
        \\{
        \\  "db_path": "~/.envr/data.age",
        \\  "keys": [
        \\    {
        \\      "private": "~/.ssh/id_ed25519",
        \\      "public": "~/.ssh/id_ed25519.pub"
        \\    }
        \\  ],
        \\  "scan": {
        \\    "matcher": "\\.env",
        \\    "exclude": [
        \\      "*\\.envrc",
        \\      "\\.local",
        \\      "node_modules",
        \\      "vendor"
        \\    ],
        \\    "include": [
        \\      "~"
        \\    ]
        \\  }
        \\}
    ;

    try std.testing.expectEqualSlices(u8, want, contents);
}

test "saving to an existing file updates the file" {
    const io = std.testing.io;

    var cfg: @This() = .{};

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var dir = tmp.dir;

    try dir.writeFile(io, .{ .sub_path = "config.json", .data = "{}" });
    _ = try dir.statFile(io, "config.json", .{});

    try cfg.save(io, dir, "config.json");

    const contents = try dir.readFileAlloc(
        io,
        "config.json",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(contents);

    const want =
        \\{
        \\  "db_path": "~/.envr/data.age",
        \\  "keys": [
        \\    {
        \\      "private": "~/.ssh/id_ed25519",
        \\      "public": "~/.ssh/id_ed25519.pub"
        \\    }
        \\  ],
        \\  "scan": {
        \\    "matcher": "\\.env",
        \\    "exclude": [
        \\      "*\\.envrc",
        \\      "\\.local",
        \\      "node_modules",
        \\      "vendor"
        \\    ],
        \\    "include": [
        \\      "~"
        \\    ]
        \\  }
        \\}
    ;

    try std.testing.expectEqualSlices(u8, want, contents);
}
