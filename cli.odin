package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:strings"

Command :: struct {
	name:     string,
	args:     [dynamic]string,
	flags:    map[string]string,
	bool_set: map[string]bool,
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
		"The init command generates your initial config and saves it to\n~/.envr/config in JSON format.\n\nDuring setup, you will be prompted to select one or more ssh keys with which to\nencrypt your databse. **Make 100% sure** that you have **a remote copy** of this\nkey somewhere, otherwise your data could be lost forever.",
		{},
	},
	{"scan", "envr scan", "Find and select .env files for backup", "", {}},
	{"sync", "envr sync", "Update or restore your env backups", "", {}},
	{"backup", "envr backup <path>", "Import a .env file into envr", "", {"add"}},
	{"restore", "envr restore <path>", "Restore a .env file from the database", "", {}},
	{"list", "envr list", "View your tracked files", "", {}},
	{"remove", "envr remove <path>", "Remove a .env file from your database", "", {}},
	{"check", "envr check [path]", "Check if files are backed up", "", {}},
	{
		"deps",
		"envr deps",
		"Check for missing binaries",
		"envr relies on external binaries for certain functionality.\n\nThe check command reports on which binaries are available and which are not.",
		{},
	},
	{"version", "envr version", "Show envr's version", "", {}},
	{"edit-config", "envr edit-config", "Edit your config with your default editor", "", {}},
}

parse_args :: proc() -> (cmd: Command, ok: bool) {
	args := os.args
	if len(args) < 2 {
		print_usage()
		return Command{}, false
	}

	cmd.name = args[1]

	if cmd.name == "--help" || cmd.name == "-h" {
		print_usage()
		return Command{}, false
	}

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

	if has_flag(&cmd, "help") {
		print_command_help(cmd.name)
		return Command{}, false
	}

	return cmd, true
}

has_flag :: proc(cmd: ^Command, name: string) -> bool {
	_, ok := cmd.flags[name]
	if ok {
		return true
	}
	_, ok2 := cmd.bool_set[name]
	return ok2
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

	fmt.wprintf(w, "\nFlags:\n  -h, --help   help for %s\n", info.name, flush = false)
	return true
}

print_command_help :: proc(name: string) {
	bw: bufio.Writer
	bufio.writer_init(&bw, io.to_writer(os.to_writer(os.stdout)), mem.DEFAULT_PAGE_SIZE)
	defer bufio.writer_destroy(&bw)

	w := bufio.writer_to_writer(&bw)
	ok := write_command_help(name, w)
	if !ok {
		fmt.printf("Unknown command: %s\n", name)
		print_usage()
	}
	bufio.writer_flush(&bw)
}

usage_text :: proc() -> string {
	b: strings.Builder
	strings.builder_init(&b)

	fmt.sbprintf(&b, "envr keeps your .env synced to a local, age encrypted database.\n")
	fmt.sbprintf(
		&b,
		"Is a safe and easy way to gather all your .env files in one place where they can\n",
	)
	fmt.sbprintf(&b, "easily be backed by another tool such as restic or git.\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "All your data is stored in ~/data.age\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "Getting started is easy:\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "1. Create your configuration file and set up encrypted storage:\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "> envr init\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "2. Scan for existing .env files:\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "> envr scan\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "Select the files you want to back up from the interactive list.\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "3. Verify that it worked:\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "> envr list\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "4. After changing any of your .env files, update the backup with:\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "> envr sync\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(
		&b,
		"5. If you lose a repository, after re-cloning the repo into the same path it was\n",
	)
	fmt.sbprintf(&b, "at before, restore your backup with:\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "> envr restore ~/<path to repository>/.env\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "Usage:\n")
	fmt.sbprintf(&b, "  envr [command]\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "Available Commands:\n")

	for c in COMMANDS {
		name_start := len(b.buf)
		fmt.sbprintf(&b, "%s", c.name)
		for a in c.aliases {
			fmt.sbprintf(&b, ", %s", a)
		}
		name_len := len(b.buf) - name_start
		padding := 20 - name_len
		if padding > 0 {
			for _ in 0 ..< padding {
				strings.write_byte(&b, ' ')
			}
		}
		fmt.sbprintf(&b, " %s\n", c.short)
	}

	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "Flags:\n")
	fmt.sbprintf(&b, "  -h, --help   help for envr\n")
	fmt.sbprintf(&b, "\n")
	fmt.sbprintf(&b, "Use \"envr [command] --help\" for more information about a command.\n")

	s := strings.clone(strings.to_string(b))
	strings.builder_destroy(&b)
	return s
}

print_usage :: proc() {
	fmt.print(usage_text())
}

