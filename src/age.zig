const std = @import("std");

/// Returns the decrypted contents of the file.
/// Caller is responsible for freeing the memory.
pub fn decrypt(
    io: std.Io,
    gpa: std.mem.Allocator,
    private_key: []const u8,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    const result = try std.process.run(gpa, io, .{
        .argv = &.{
            "age",
            "-d",
            "-i",
            private_key,
            "-o",
            output_path,
            input_path,
        },
    });
    defer gpa.free(result.stderr);
    defer gpa.free(result.stdout);

    if (result.stdout.len > 0) {
        std.debug.print("stdout: \"{s}\"\n", .{result.stdout});
        unreachable;
    }

    if (result.stderr.len > 0) {
        std.debug.print("stderr: \"{s}\"\n", .{result.stderr});
        unreachable;
    }
}

/// Returns the encrypted contents of the file.
/// Caller is responsible for freeing the memory.
pub fn encrypt(
    io: std.Io,
    gpa: std.mem.Allocator,
    public_key: []const u8,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    const result = try std.process.run(gpa, io, .{
        .argv = &.{
            "age",
            "-e",
            "-R",
            public_key,
            "-o",
            output_path,
            input_path,
        },
    });
    defer gpa.free(result.stderr);
    defer gpa.free(result.stdout);

    if (result.stdout.len > 0) {
        std.debug.print("stdout: \"{s}\"\n", .{result.stdout});
        unreachable;
    }

    if (result.stderr.len > 0) {
        std.debug.print("stderr: \"{s}\"\n", .{result.stderr});
        unreachable;
    }
}

test "sample file can be decrypted" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir_path);

    const output_path = try std.fs.path.join(gpa, &.{ dir_path, "got.txt" });
    defer gpa.free(output_path);

    try decrypt(
        io,
        gpa,
        "./fixtures/insecure-test-key",
        "./fixtures/hello-world.age",
        output_path,
    );

    const contents = try tmp.dir.readFileAlloc(io, output_path, gpa, .unlimited);
    defer gpa.free(contents);

    try std.testing.expectEqualSlices(u8, "Hello, World!\n", contents);
}

test "sample file can be encrypted" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(dir_path);

    const output_path = try std.fs.path.join(gpa, &.{ dir_path, "hello-world.age" });
    defer gpa.free(output_path);

    try encrypt(
        io,
        gpa,
        "./fixtures/insecure-test-key.pub",
        "./fixtures/hello-world.txt",
        output_path,
    );

    const got = try tmp.dir.readFileAlloc(io, output_path, gpa, .unlimited);
    defer gpa.free(got);

    const want = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "./fixtures/hello-world.age",
        gpa,
        .unlimited,
    );
    defer gpa.free(want);

    const contents = try tmp.dir.readFileAlloc(io, output_path, gpa, .unlimited);
    defer gpa.free(contents);

    try std.testing.expectEqual(want.len, got.len);

    // FIXME: Test that decrypted file contents match
    // try std.testing.expectEqualSlices(u8, "Hello, World!\n", decrypted_contents);
}
