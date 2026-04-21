const std = @import("std");
const Io = std.Io;

const config = @import("config");

const comma = @import("comma");
const envr = @import("envr");

const goBinary = "envr-go";

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    try run(init.environ_map, init.io, arena, args);
}

/// Attempt to run the requested command.
fn run(
    environ_map: *std.process.Environ.Map,
    io: Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
) !void {
    const cmd = envr.root.parse(args[1..]);
    switch (cmd) {
        .envr, .unknown => {
            return fallback_to_go(io, arena, args);
        },
        .version => {
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
            const stdout_writer = &stdout_file_writer.interface;

            return version(stdout_writer);
        },
        .deps => {
            var stdout_buffer: [1024]u8 = undefined;
            var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
            const stdout_writer = &stdout_file_writer.interface;

            return deps(
                io,
                stdout_writer,
                environ_map.get("PATH").?,
            );
        },
    }
}

fn version(writer: *Io.Writer) !void {
    try writer.print("{s}\n", .{config.version});
    try writer.flush();
}

// Display dependency statuses
fn deps(
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
