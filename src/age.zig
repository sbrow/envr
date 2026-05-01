const std = @import("std");

/// Decrypts the file into output path
pub fn decrypt(
    io: std.Io,
    gpa: std.mem.Allocator,
    private_keys: []const []const u8,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    // TODO: use raw array?
    var argv: std.ArrayList([]const u8) = try .initCapacity(gpa, 2 + (2 * private_keys.len) + 3);
    defer argv.deinit(gpa);

    argv.appendAssumeCapacity("age");
    argv.appendAssumeCapacity("-d");

    for (private_keys) |key| {
        argv.appendAssumeCapacity("-i");
        argv.appendAssumeCapacity(key);
    }

    argv.appendAssumeCapacity("-o");
    argv.appendAssumeCapacity(output_path);

    argv.appendAssumeCapacity(input_path);

    const result = try std.process.run(gpa, io, .{
        .argv = argv.items,
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

/// Encrypts the file into output path
pub fn encrypt(
    io: std.Io,
    gpa: std.mem.Allocator,
    // TODO: Accept multiple keys
    public_keys: []const []const u8,
    input_path: []const u8,
    output_path: []const u8,
) !void {
    var argv: std.ArrayList([]const u8) = try .initCapacity(gpa, 2 + (2 * public_keys.len) + 3);
    defer argv.deinit(gpa);

    argv.appendAssumeCapacity("age");
    argv.appendAssumeCapacity("-e");

    for (public_keys) |key| {
        argv.appendAssumeCapacity("-R");
        argv.appendAssumeCapacity(key);
    }

    argv.appendAssumeCapacity("-o");
    argv.appendAssumeCapacity(output_path);

    argv.appendAssumeCapacity(input_path);

    const result = try std.process.run(gpa, io, .{
        .argv = argv.items,
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
        &.{"./fixtures/insecure-test-key"},
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
        &.{"./fixtures/insecure-test-key.pub"},
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
