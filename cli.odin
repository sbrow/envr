package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
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

// TODO: Put help test in usage:"whatever" tag.
Flags :: struct {
	help:        bool `args:"short=h"`,
	config_file: string `args:"name=config-file,short=c"`,
	output:      Output_Format `args:"short=o"`,
	force:       bool `args:"short=f"`,
}

Output_Format :: enum {
	Auto,
	Table,
	JSON,
}

CommandInfo :: struct {
	name:    string,
	usage:   string,
	short:   string,
	long:    string,
	aliases: []string,
}

COMMANDS := []CommandInfo {
	{
		"init",
		"envr init",
		"Set up envr",
		`The init command generates your initial config and saves it to
~/.envr/config in JSON format.\n\nDuring setup, you will be prompted to select one or more ssh keys with which to
encrypt your databse. **Make 100% sure** that you have **a remote copy** of this
key somewhere, otherwise your data could be lost forever.`,
		{},
	},
	{"scan", "envr scan", "Find and select .env files for backup", "", {}},
	{"sync", "envr sync", "Update or restore your env backups", "", {}},
	{"backup", "envr backup <path>", "Import a .env file into envr", "", {"add"}},
	{"restore", "envr restore <path>", "Restore a .env file from the database", "", {}},
	{"list", "envr list", "View your tracked files", "", {}},
	{"remove", "envr remove <path>", "Remove a .env file from your database", "", {}},
	{"check", "envr check [path]", "Check if files are backed up", "", {}},
	{"version", "envr version", "Show envr's version", "", {}},
	{"edit-config", "envr edit-config", "Edit your config with your default editor", "", {}},
	{
		"nushell-completion",
		"envr nushell-completion",
		"Generate custom completions for nushell",
		"",
		{},
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
	info, found := find_command(name)
	if !found {
		return false
	}

	fmt.wprintf(
		w,
		"%s\n\n\n" +
		COLOR_HEADINGS +
		"Usage:" +
		ANSI_RESET +
		"\n\n  " +
		COLOR_FLAGS +
		"%s" +
		ANSI_RESET +
		" [flags]\n\n",
		info.short,
		info.usage,
		flush = false,
	)

	if len(info.aliases) > 0 {
		fmt.wprintf(
			w,
			"\n" +
			COLOR_HEADINGS +
			"Aliases:" +
			ANSI_RESET +
			"\n\n  " +
			COLOR_COMMANDS +
			"%s" +
			ANSI_RESET,
			info.name,
			flush = false,
		)
		for a in info.aliases {
			fmt.wprintf(w, ", " + COLOR_COMMANDS + "%s" + ANSI_RESET, a, flush = false)
		}
		fmt.wprintf(w, "\n", flush = false)
	}

	if len(info.long) > 0 {
		fmt.wprintf(w, "\n%s\n", info.long, flush = false)
	}

	fmt.wprintf(
		w,
		"\n" +
		COLOR_HEADINGS +
		"Flags:" +
		ANSI_RESET +
		"\n\n  " +
		COLOR_FLAGS +
		"-h, --help" +
		ANSI_RESET +
		"   help for %s\n  " +
		COLOR_FLAGS +
		"-c, --config-file" +
		ANSI_RESET +
		` <path>   config file (default "~/.envr/config.json")
`,
		info.name,
		flush = false,
	)
	return true
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

%sUsage:%s

  %senvr%s [command]

`,
		COLOR_HEADINGS,
		ANSI_RESET,
		COLOR_FLAGS,
		ANSI_RESET,
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
		table.row(&tbl, table.format(&tbl, "%s%s%s", COLOR_COMMANDS, name, ANSI_RESET), c.short)
	}

	write_borderless_table(w, &tbl)
	table_reset(&tbl)

	table.caption(&tbl, "Flags:")

	table.row(&tbl, COLOR_FLAGS + "-h, --help" + ANSI_RESET, `show this documentation`)
	table.row(
		&tbl,
		COLOR_FLAGS + "-c, --config-file" + ANSI_RESET + " <path>",
		`config file (default "~/.envr/config.json")`,
	)
	table.row(
		&tbl,
		COLOR_FLAGS + "-o, --output" + ANSI_RESET + " 'table'|'json'",
		`the format of output data. (default 'table')`,
	)
	write_borderless_table(w, &tbl)

	fmt.wprintf(
		w,
		`Use "%senvr%s [command] --help" for more information about a command.`,
		COLOR_FLAGS,
		ANSI_RESET,
		flush = false,
	)
}

delete_command :: proc(cmd: ^Command) {
	bufio.writer_flush(cmd.out_buf)
	delete(cmd.args)
	bufio.writer_destroy(cmd.out_buf)
	free(cmd.out_buf)
}

