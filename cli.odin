package main

import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:terminal"
import "core:text/table"

Command :: struct {
	name:    string,
	args:    [dynamic]string,
	flags:   Flags,
	out_buf: ^bufio.Writer,
	out:     io.Writer,
	err:     io.Writer,
}

Flags :: struct {
	help:        bool `args:"short=h" usage:"show this documentation"`,
	config_file: string `args:"name=config-file,short=c" usage:"config file" default:"~/.envr/config.json"`,
	output:      Output_Format `args:"short=o" usage:"the format of output data" default:"table" completion:"output"`,
	color:       Color_Mode `usage:"Whether or not to colorize output" default:"auto" completion:"color"`,
	force:       bool `args:"short=f" usage:"Overwrite existing config"`,
}

Flag_Type :: enum {
	Help,
	Config_File,
	Output,
	Color,
	Force,
}

Output_Format :: enum {
	Auto,
	Table,
	JSON,
}

Color_Mode :: enum {
	Auto,
	Always,
	Never,
}

Positional_Arg :: struct {
	name:       string,
	completion: string,
	optional:   bool,
}

CommandInfo :: struct {
	name:    string,
	usage:   string,
	short:   string,
	long:    string,
	aliases: []string,
	// Flags supported by the command
	flags:   bit_set[Flag_Type],
	args:    []Positional_Arg,
}

GLOBAL_FLAGS: bit_set[Flag_Type] = {.Help, .Config_File, .Color}

COMMANDS := []CommandInfo {
	{
		name  = "init",
		usage = "envr init",
		short = "Set up envr",
		long  = `The init command generates your initial config and saves it to
~/.envr/config in JSON format.\n\nDuring setup, you will be prompted to select one or more ssh keys with which to
encrypt your databse. **Make 100% sure** that you have **a remote copy** of this
key somewhere, otherwise your data could be lost forever.`,
		flags = GLOBAL_FLAGS + {.Force},
	},
	{
		name  = "scan",
		usage = "envr scan",
		short = "Find and select .env files for backup",
		flags = GLOBAL_FLAGS,
	},
	{
		name  = "sync",
		usage = "envr sync",
		short = "Update or restore your env backups",
		flags = GLOBAL_FLAGS + {.Output},
	},
	{
		name    = "backup",
		usage   = "envr backup <path>",
		short   = "Import a .env file into envr",
		aliases = {"add"},
		flags   = GLOBAL_FLAGS,
		args    = {{name = "path", completion = "untracked-paths"}},
	},
	{
		name  = "restore",
		usage = "envr restore <path>",
		short = "Restore a .env file from the database",
		flags = GLOBAL_FLAGS,
		args  = {{name = "path", completion = "tracked-paths"}},
	},
	{
		name  = "list",
		usage = "envr list",
		short = "View your tracked files",
		flags = GLOBAL_FLAGS + {.Output},
	},
	{
		name  = "remove",
		usage = "envr remove <path>",
		short = "Remove a .env file from your database",
		flags = GLOBAL_FLAGS,
		args  = {{name = "path", completion = "tracked-paths"}},
	},
	{
		name  = "check",
		usage = "envr check [path]",
		short = "Check if files are backed up",
		flags = GLOBAL_FLAGS,
		args  = {{name = "path", optional = true}},
	},
	{
		name  = "version",
		usage = "envr version",
		short = "Show envr's version",
		flags = {.Help},
	},
	{
		name  = "edit-config",
		usage = "envr edit-config",
		short = "Edit your config with your default editor",
		flags = GLOBAL_FLAGS,
	},
	{
		name  = "nushell-completion",
		usage = "envr nushell-completion",
		short = "Generate custom completions for nushell",
		flags = {.Help},
	},
}

// Caller is responsible for calling delete_command(cmd).
// FIXME: Works in kinda a wonky and awkward way.
parse_args :: proc(args: []string, out: io.Stream, err: io.Stream) -> (cmd: Command, ok: bool) {
	{
		cmd.out_buf = new(bufio.Writer)
		bufio.writer_init(cmd.out_buf, out, allocator = context.allocator)
		cmd.out = bufio.writer_to_writer(cmd.out_buf)
		cmd.err = err
	}

	if len(args) < 2 || args[1] == "--help" || args[1] == "-h" {
		write_usage(cmd.out)
		return cmd, false
	}

	cmd.name = args[1]
	cmd.args = make([dynamic]string)

	overflow := parse_flags(&cmd.flags, args[2:])
	for arg in overflow {
		append(&cmd.args, arg)
	}

	if cmd.flags.output == .Auto {
		cmd.flags.output = terminal.is_terminal(os.stdout) ? .Table : .JSON
	}

	if cmd.flags.color == .Auto {
		cmd.flags.color = terminal.is_terminal(os.stdout) ? .Always : .Never
	}
	if cmd.flags.color == .Never {
		disable_color = true
	}

	if cmd.flags.config_file == "" {
		// FIXME: Handle err
		// TODO: Is this right?
		home, _ := os.user_home_dir(context.temp_allocator)
		// TODO: should we copy out of the temp_allocator?
		cmd.flags.config_file = default_config_path(home, context.temp_allocator)
	}

	if cmd.flags.help {
		print_command_help(&cmd)
		return cmd, false
	}

	return cmd, true
}

print_command_help :: proc(cmd: ^Command) {
	ok := write_command_help(cmd.name, cmd.out)
	if !ok {
		fmt.wprintf(cmd.err, "Unknown command: %s\n", cmd.name)
		write_usage(cmd.out)
	}
}

write_command_help :: proc(name: string, w: io.Writer) -> bool {
	// TODO: rename info to cmd?
	info, found := find_command(name)
	if !found {
		return false
	}

	fmt.wprintf(
		w,
		"%s\n\n\n%s\n\n  %s [flags]\n\n",
		info.short,
		colorize(.Heading, "Usage:"),
		colorize(.Flag, info.usage),
		flush = false,
	)

	if len(info.aliases) > 0 {
		fmt.wprintf(
			w,
			"\n%s\n\n  %s",
			colorize(.Heading, "Aliases:"),
			colorize(.Command, info.name),
			flush = false,
		)
		for a in info.aliases {
			fmt.wprintf(w, ", %s", colorize(.Command, a), flush = false)
		}
		fmt.wprintf(w, "\n", flush = false)
	}

	if len(info.long) > 0 {
		fmt.wprintf(w, "\n%s\n", info.long, flush = false)
	}

	tbl: table.Table
	table.init(&tbl, context.temp_allocator, context.temp_allocator)
	table.padding(&tbl, 2, 0)
	write_flags_table(&tbl, info.flags)
	fmt.wprintf(w, "\n", flush = false)
	write_borderless_table(w, &tbl)
	table_reset(&tbl)
	return true
}

Flag_Kind :: enum {
	Bool,
	String,
	Enum,
}

Flag_Field :: struct {
	long_name:   string,
	short_name:  string,
	kind:        Flag_Kind,
	usage:       string,
	default_val: string,
	enum_values: string,
	completion:  string,
}

flag_field :: proc(ft: Flag_Type) -> Flag_Field {
	field := reflect.struct_field_at(Flags, int(ft))

	args_tag := reflect.struct_tag_get(field.tag, "args")
	long_name, _ := strings.replace(field.name, "_", "-", -1, context.temp_allocator)
	if n, ok := get_subtag(args_tag, "name"); ok {
		long_name = n
	}

	short, has_short := get_subtag(args_tag, "short")

	base_ti := runtime.type_info_base(field.type)
	kind: Flag_Kind
	enum_values: string

	if _, is_bool := base_ti.variant.(runtime.Type_Info_Boolean); is_bool {
		kind = .Bool
	} else if _, is_string := base_ti.variant.(runtime.Type_Info_String); is_string {
		kind = .String
	} else if enum_ti, is_enum := base_ti.variant.(runtime.Type_Info_Enum); is_enum {
		kind = .Enum
		parts := make([dynamic]string, 0, len(enum_ti.names), context.temp_allocator)
		for name in enum_ti.names {
			lower := strings.to_lower(name, context.temp_allocator)
			append(&parts, fmt.tprintf("'%s'", lower))
		}
		enum_values = strings.join(parts[:], "|", context.temp_allocator)
		delete(parts)
	}

	usage := reflect.struct_tag_get(field.tag, "usage")
	default_val := reflect.struct_tag_get(field.tag, "default")
	completion := reflect.struct_tag_get(field.tag, "completion")

	return {
		long_name = long_name,
		short_name = has_short ? short : "",
		kind = kind,
		usage = usage,
		default_val = default_val,
		enum_values = enum_values,
		completion = completion,
	}
}

flag_field_info :: proc(
	ft: Flag_Type,
) -> (
	names: string,
	value_hint: string,
	description: string,
) {
	f := flag_field(ft)

	if len(f.short_name) > 0 {
		names = fmt.tprintf("-%s, --%s", f.short_name, f.long_name)
	} else {
		names = fmt.tprintf("--%s", f.long_name)
	}

	switch f.kind {
	case .Bool:
		value_hint = ""
	case .String:
		value_hint = " <value>"
	case .Enum:
		value_hint = fmt.tprintf(" %s", f.enum_values)
	}

	description = f.usage
	if len(f.default_val) > 0 {
		switch f.kind {
		case .Bool:
		// do nothing
		case .String:
			description = fmt.tprintf(`%s (default "%s")`, f.usage, f.default_val)
		case .Enum:
			description = fmt.tprintf("%s (default '%s')", f.usage, f.default_val)
		}
	}

	return
}

write_flags_table :: proc(tbl: ^table.Table, flags: bit_set[Flag_Type]) {
	table.caption(tbl, "Flags:")
	for ft in Flag_Type {
		if ft not_in flags do continue
		names, hint, desc := flag_field_info(ft)
		if len(hint) > 0 {
			display := table.format(
				tbl,
				"%s%s",
				colorize(.Flag, names, tbl.format_allocator),
				hint,
			)
			table.row(tbl, display, desc)
		} else {
			table.row(tbl, colorize(.Flag, names, tbl.format_allocator), desc)
		}
	}
}

find_command :: proc(name: string) -> (CommandInfo, bool) {
	for c in COMMANDS {
		if c.name == name {
			return c, true
		}
		for a in c.aliases {
			if a == name {
				return c, true
			}
		}
	}
	return CommandInfo{}, false
}

// TODO: command args should be shown in usage.
write_usage :: proc(w: io.Writer) {
	fmt.wprintf(
		w,
		`envr keeps your .env synced to a local, encrypted database.
Is a safe and easy way to gather all your .env files in one place where they can
easily be backed by another tool such as restic or git.

All your data is stored in ~/.envr/data.envr

Getting started is easy:

1. Create your configuration file and set up encrypted storage:

> envr init

2. Scan for existing .env files:

> envr scan

Select the files you want to back up from the interactive list.

3. Verify that it worked:

> envr list

4. After changing any of your .env files, update the backup with:

> envr sync

5. If you lose a repository, after re-cloning the repo into the same path it was
at before, restore your backup with:

> envr restore ~/<path to repository>/.env

%s

  %s [command]

`,
		colorize(.Heading, "Usage:"),
		colorize(.Flag, "envr"),
		flush = false,
	)

	tbl: table.Table
	table.init(&tbl, context.temp_allocator, context.temp_allocator)
	table.padding(&tbl, 2, 0)

	table.caption(&tbl, "Available Commands:")

	for c in COMMANDS {
		name := c.name
		// TODO: Can we do better?
		for a in c.aliases {
			name = strings.join([]string{name, a}, ", ", tbl.format_allocator)
		}
		table.row(&tbl, colorize(.Command, name, tbl.format_allocator), c.short)
	}

	write_borderless_table(w, &tbl)
	table_reset(&tbl)

	write_flags_table(&tbl, GLOBAL_FLAGS)
	write_borderless_table(w, &tbl)
	table_reset(&tbl)

	fmt.wprintf(
		w,
		`Use "%s [command] --help" for more information about a command.`,
		colorize(.Flag, "envr", tbl.format_allocator),
		flush = false,
	)
}

delete_command :: proc(cmd: ^Command) {
	bufio.writer_flush(cmd.out_buf)
	delete(cmd.args)
	bufio.writer_destroy(cmd.out_buf)
	free(cmd.out_buf)
}

