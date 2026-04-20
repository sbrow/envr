const std = @import("std");
const Io = std.Io;

const config = @import("config");

const envr = @import("envr");

const goBinary = "envr-go";

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    run(init.io, args) catch return fallback_to_go(init.io, arena, args);
}

/// Attempt to run the requested command.
fn run(io: Io, args: []const [:0]const u8) !void {
    const cmd = try envr.root.parse(args[1..]);
    switch (cmd) {
        .envr => {
            // TODO: Print help
            return envr.ParseError.InvalidType;
        },
        .version => {
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
            const stdout_writer = &stdout_file_writer.interface;

            return version(stdout_writer);
        },
    }
}

fn version(writer: *Io.Writer) !void {
    try writer.print("{s}\n", .{config.version});
    try writer.flush();
}

fn fallback_to_go(
    io: Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
) std.process.ReplaceError {
    // Remap args
    var childArgs = try std.ArrayList([]const u8).initCapacity(arena, args.len);
    childArgs.appendAssumeCapacity(goBinary);

    for (args[1..]) |arg| {
        childArgs.appendAssumeCapacity(arg);
    }

    return std.process.replace(io, .{ .argv = childArgs.items });
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
