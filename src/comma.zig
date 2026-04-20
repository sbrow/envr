//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
// const Io = std.Io;

pub const Command = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    long: ?[]const u8 = null,
    subcommands: []const Command = &[0]Command{},
    Type: type,

    pub fn new(cmd: CommandOptions) Command {
        const subcommands: [cmd.subcommands.len]Command = blk: {
            var result: [cmd.subcommands.len]Command = undefined;
            inline for (cmd.subcommands, 0..) |sub, idx| {
                result[idx] = new(sub);
            }
            break :blk result;
        };

        return .{
            .name = cmd.name,
            .short = cmd.short,
            .long = cmd.long,
            .subcommands = &subcommands,
            .Type = cmd.as_enum(),
        };
    }

    pub fn parse(comptime self: @This(), args: []const []const u8) ParseError!self.Type {
        if (args.len == 0) {
            return ParseError.InvalidType;
        }
        const target = args[0];

        inline for (self.subcommands, 1..) |cmd, idx| {
            if (std.mem.eql(u8, target, cmd.name)) {
                return @enumFromInt(idx);
            }
        }

        return @enumFromInt(0);
    }
};

pub const ParseError = error{
    InvalidType,
};

const CommandOptions = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    long: ?[]const u8 = null,
    subcommands: []const CommandOptions = &[0]CommandOptions{},

    fn as_enum(self: @This()) type {
        var field_names: [self.subcommands.len + 1][]const u8 = undefined;
        var field_values: [self.subcommands.len + 1]u32 = undefined;

        field_names[0] = self.name;
        field_values[0] = 0;

        inline for (self.subcommands, 1..) |cmd, idx| {
            field_names[idx] = cmd.name;
            field_values[idx] = idx;
        }

        return @Enum(
            u32,
            .exhaustive,
            &field_names,
            &field_values,
        );
    }
};
