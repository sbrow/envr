const std = @import("std");
const sqlite = @import("sqlite");

const age = @import("age.zig");

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
        "./fixtures/insecure-test-key",
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
