const std = @import("std");
const sqlite = @import("sqlite");

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
