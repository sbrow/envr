package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"

Command :: struct {
	name:        string,
	args:        [dynamic]string,
	flags:       map[string]string,
	bool_set:    map[string]bool,
	config_path: string,
	out_buf:     ^bufio.Writer,
	out:         io.Writer,
	err:         io.Writer,
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
		bufio.writer_init(cmd.out_buf, out)
		cmd.out = bufio.writer_to_writer(cmd.out_buf)
		cmd.err = err
	}

	if len(args) < 2 || args[1] == "--help" || args[1] == "-h" {
		write_usage(cmd.out)
		return cmd, false
	}

	cmd.name = args[1]

	cmd.args = make([dynamic]string)
	cmd.flags = make(map[string]string)
	cmd.bool_set = make(map[string]bool)

	i := 2
	for i < len(args) {
		arg := args[i]
		if strings.starts_with(arg, "--") {
			key := arg[2:]
			if i + 1 < len(args) && !strings.starts_with(args[i + 1], "-") {
				cmd.flags[key] = args[i + 1]
				i += 2
			} else {
				cmd.bool_set[key] = true
				i += 1
			}
		} else if strings.starts_with(arg, "-") && len(arg) == 2 {
			key_slice := arg[1:2]
			if i + 1 < len(args) && !strings.starts_with(args[i + 1], "-") {
				cmd.flags[key_slice] = args[i + 1]
				i += 2
			} else {
				cmd.bool_set[key_slice] = true
				i += 1
			}
		} else {
			append(&cmd.args, arg)
			i += 1
		}
	}

	if val, ok := cmd.flags["config-file"]; ok {
		cmd.config_path = val
	} else if val, ok := cmd.flags["c"]; ok {
		cmd.config_path = val
	} else {
		// FIXME: Handle err
		// TODO: Is this right?
		home, _ := os.user_home_dir(context.temp_allocator)
		// TODO: should we copy out of the temp_allocator?
		cmd.config_path = default_config_path(home, context.temp_allocator)
	}

	if has_flag(&cmd, "help") {
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

	fmt.wprintf(w, "Usage: %s [flags]\n\n", info.usage, flush = false)
	fmt.wprintf(w, "%s\n", info.short, flush = false)

	if len(info.aliases) > 0 {
		fmt.wprintf(w, "\nAliases:\n  %s", info.name, flush = false)
		for a in info.aliases {
			fmt.wprintf(w, ", %s", a, flush = false)
		}
		fmt.wprintf(w, "\n", flush = false)
	}

	if len(info.long) > 0 {
		fmt.wprintf(w, "\n%s\n", info.long, flush = false)
	}

	fmt.wprintf(
		w,
		"\nFlags:\n  -h, --help   help for %s\n  -c, --config-file <path>   config file (default \"~/.envr/config.json\")\n",
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
		`envr keeps your .env synced to a local, age encrypted database.
Is a safe and easy way to gather all your .env files in one place where they can
easily be backed by another tool such as restic or git.

All your data is stored in ~/data.age

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

Usage:
  envr [command]

Available Commands:
`,
		flush = false,
	)

	for c in COMMANDS {
		name_start := len(c.name)
		fmt.wprintf(w, "%s", c.name, flush = false)
		for a in c.aliases {
			fmt.wprintf(w, ", %s", a, flush = false)
			name_start += len(a) + 2
		}
		padding := 20 - name_start
		if padding > 0 {
			for _ in 0 ..< padding {
				io.write_byte(w, ' ')
			}
		}
		fmt.wprintf(w, " %s\n", c.short, flush = false)
	}

	fmt.wprintf(
		w,
		`
Flags:
  -h, --help   help for envr
  -c, --config-file <path>   config file (default "~/.envr/config.json")

Use "envr [command] --help" for more information about a command.
`,
		flush = false,
	)
}

has_flag :: proc(cmd: ^Command, name: string) -> bool {
	_, ok := cmd.flags[name]
	if ok {
		return true
	}
	_, ok2 := cmd.bool_set[name]
	return ok2
}

delete_command :: proc(cmd: ^Command) {
	delete(cmd.args)
	delete(cmd.flags)
	delete(cmd.bool_set)
	bufio.writer_destroy(cmd.out_buf)
	free(cmd.out_buf)
}
