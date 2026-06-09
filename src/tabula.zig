const std = @import("std");

const hor = "─";
const tl = "┌";
const tm = "┬";
const tr = "┐";
const sep = "│";
const ml = "├";
const mm = "┼";
const mr = "┤";
const bl = "└";
const bm = "┴";
const br = "┘";

/// Prepare a TUI table to be written to a writer.
pub fn Table(
    comptime T: type,
    comptime fields: std.EnumSet(std.meta.FieldEnum(T)),
) type {
    return struct {
        items: []const T,

        pub fn format(self: @This(), writer: *std.Io.Writer) !void {
            const max_column_widths = determine_col_widths(T, self.items);

            try header(T, fields, &max_column_widths, writer);

            // Print body
            for (self.items) |item| {
                try writer.writeAll(sep);

                comptime var itr = fields.iterator();
                comptime var i: usize = 0;
                inline while (comptime itr.next()) |c| : (i += 1) {
                    try writer.writeByte(' ');
                    try write_aligned(writer, @field(item, @tagName(c)), max_column_widths[i], .left);
                    try writer.print(" {s}", .{sep});
                }

                try writer.writeAll("\n");
            }

            // Print post-body
            {
                try writer.writeAll(bl);

                var itr = fields.iterator();
                var i: usize = 0;
                while (itr.next()) |_| : (i += 1) {
                    if (i > 0) {
                        try writer.writeAll(bm);
                    }

                    const padding = max_column_widths[i] + 2;
                    for (0..padding) |_| {
                        try writer.writeAll(hor);
                    }
                }

                try writer.writeAll(br ++ "\n");
            }
        }
    };
}

fn determine_col_widths(
    T: type,
    items: []const T,
) [@typeInfo(T).@"struct".fields.len]usize {
    const all_fields = @typeInfo(T).@"struct".fields;

    var max_column_widths: [all_fields.len]usize = @splat(0);
    for (items) |item| {
        inline for (all_fields, 0..) |field, i| {
            // TODO: Get str len of item
            const value_len = @field(item, field.name).len;
            max_column_widths[i] = @max(
                max_column_widths[i],
                field.name.len,
                value_len,
            );
        }
    }

    return max_column_widths;
}

// Print the header of a table
fn header(
    T: type,
    comptime fields: std.EnumSet(std.meta.FieldEnum(T)),
    max_column_widths: []const usize,
    writer: *std.Io.Writer,
) !void {

    // Print Pre-Header
    {
        try writer.writeAll(tl);

        inline for (0..comptime fields.count()) |i| {
            if (i > 0) {
                try writer.writeAll(tm);
            }
            const padding = max_column_widths[i] + 2;
            for (0..padding) |_| {
                try writer.writeAll(hor);
            }
        }

        try writer.writeAll(tr ++ "\n");
    }

    // Main Header
    {
        try writer.writeAll(sep);

        comptime var itr = fields.iterator();
        comptime var i: usize = 0;
        inline while (comptime itr.next()) |field| : (i += 1) {
            try writer.writeByte(' ');
            try write_aligned(
                writer,
                @tagName(field),
                max_column_widths[i],
                .center,
            );
            try writer.print(" {s}", .{sep});
        }

        try writer.writeByte('\n');
    }

    // Print post-header
    {
        try writer.writeAll(ml);

        inline for (0..comptime fields.count()) |i| {
            if (i > 0) {
                try writer.writeAll(mm);
            }
            const padding = max_column_widths[i] + 2;
            for (0..padding) |_| {
                try writer.writeAll(hor);
            }
        }

      try writer.writeAll(mr ++ "\n");
    }
}

fn write_aligned(
    writer: *std.Io.Writer,
    data: []const u8,
    max_width: usize,
    alignment: Alignment,
) !void {
    std.debug.assert(data.len > 0);
    std.debug.assert(max_width >= data.len);

    const padding: [2]usize = switch (alignment) {
        .left => .{ 0, max_width - data.len },
        .right => .{ max_width - data.len, 0 },
        .center => blk: {
            // Faster to inline the divFloor?
            const half = @divFloor(max_width - data.len, 2);
            break :blk .{ half, max_width - data.len - half };
        },
    };

    for (0..padding[0]) |_| {
        try writer.writeByte(' ');
    }

    try writer.writeAll(data);

    for (0..padding[1]) |_| {
        try writer.writeByte(' ');
    }
}

const Alignment = enum { left, center, right };

test "can print a simple table" {
    const gpa = std.testing.allocator;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    const F = struct { foo: []const u8, bar: []const u8 };
    const table: Table(F, .full) = .{
        .items = &.{.{ .foo = "bat", .bar = "baz" }},
    };

    try out.writer.print("{f}", .{table});

    const got = try out.toOwnedSlice();
    defer gpa.free(got);

    try std.testing.expectEqualStrings(
        \\┌─────┬─────┐
        \\│ foo │ bar │
        \\├─────┼─────┤
        \\│ bat │ baz │
        \\└─────┴─────┘
        \\
    , got);
}

test "can print a table with varying header widths" {
    const gpa = std.testing.allocator;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    const F = struct { foo: []const u8, abart: []const u8 };
    const table: Table(F, .full) = .{
        .items = &.{.{ .foo = "bat", .abart = "baz" }},
    };
    try out.writer.print("{f}", .{table});

    const got = try out.toOwnedSlice();
    defer gpa.free(got);

    try std.testing.expectEqualStrings(
        \\┌─────┬───────┐
        \\│ foo │ abart │
        \\├─────┼───────┤
        \\│ bat │ baz   │
        \\└─────┴───────┘
        \\
    , got);
}

test "can print a table with varying column widths" {
    const gpa = std.testing.allocator;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    const F = struct { foo: []const u8, bar: []const u8 };
    const table: Table(F, .full) = .{ .items = &.{.{ .foo = "bat", .bar = "bazzar" }} };

    try out.writer.print("{f}", .{table});

    const got = try out.toOwnedSlice();
    defer gpa.free(got);

    try std.testing.expectEqualStrings(
        \\┌─────┬────────┐
        \\│ foo │  bar   │
        \\├─────┼────────┤
        \\│ bat │ bazzar │
        \\└─────┴────────┘
        \\
    , got);
}

test "can print a multi row table with varying column widths" {
    const gpa = std.testing.allocator;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    const F = struct { foo: []const u8, bar: []const u8 };
    const table: Table(F, .full) = .{
        .items = &.{
            .{ .foo = "baz", .bar = "quz" },
            .{ .foo = "bat", .bar = "bazzar" },
        },
    };
    try out.writer.print("{f}", .{table});

    const got = try out.toOwnedSlice();
    defer gpa.free(got);

    try std.testing.expectEqualStrings(
        \\┌─────┬────────┐
        \\│ foo │  bar   │
        \\├─────┼────────┤
        \\│ baz │ quz    │
        \\│ bat │ bazzar │
        \\└─────┴────────┘
        \\
    , got);
}

test "can print a table with limited columns" {
    const gpa = std.testing.allocator;

    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();

    const F = struct { foo: []const u8, bar: []const u8 };
    const table: Table(F, .initOne(.foo)) = .{
        .items = &.{.{ .foo = "bat", .bar = "baz" }},
    };

    try out.writer.print("{f}", .{table});

    const got = try out.toOwnedSlice();
    defer gpa.free(got);

    try std.testing.expectEqualStrings(
        \\┌─────┐
        \\│ foo │
        \\├─────┤
        \\│ bat │
        \\└─────┘
        \\
    , got);
}
