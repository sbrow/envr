package main

import "core:fmt"
import "core:os"
import "core:strings"

Command :: struct {
	name:     string,
	args:     [dynamic]string,
	flags:    map[string]string,
	bool_set: map[string]bool,
}

CommandInfo :: struct {
	name:  string,
	usage: string,
	short: string,
	long:  string,
}

COMMANDS := []CommandInfo{
	{"init", "envr init", "Set up envr",
		"The init command generates your initial config and saves it to\n~/.envr/config in JSON format.\n\nDuring setup, you will be prompted to select one or more ssh keys with which to\nencrypt your databse. **Make 100% sure** that you have **a remote copy** of this\nkey somewhere, otherwise your data could be lost forever."},
	{"scan", "envr scan", "Find and select .env files for backup", ""},
	{"sync", "envr sync", "Update or restore your env backups", ""},
	{"backup", "envr backup <path>", "Import a .env file into envr", ""},
	{"add", "envr add <path>", "Import a .env file into envr", ""},
	{"restore", "envr restore <path>", "Restore a .env file from the database", ""},
	{"list", "envr list", "View your tracked files", ""},
	{"remove", "envr remove <path>", "Remove a .env file from your database", ""},
	{"check", "envr check [path]", "Check if files are backed up", ""},
	{"deps", "envr deps", "Check for missing binaries",
		"envr relies on external binaries for certain functionality.\n\nThe check command reports on which binaries are available and which are not."},
	{"version", "envr version", "Show envr's version", ""},
	{"edit-config", "envr edit-config", "Edit your config with your default editor", ""},
}

IMPLEMENTED_COMMANDS := []string{
	"version",
	"deps",
	"list",
	"backup",
	"add",
	"remove",
	"restore",
	"edit-config",
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
			if i+1 < len(args) && !strings.starts_with(args[i+1], "-") {
				cmd.flags[key] = args[i+1]
				i += 2
			} else {
				cmd.bool_set[key] = true
				i += 1
			}
		} else if strings.starts_with(arg, "-") && len(arg) == 2 {
			key_slice := arg[1:2]
			if i+1 < len(args) && !strings.starts_with(args[i+1], "-") {
				cmd.flags[key_slice] = args[i+1]
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

is_implemented :: proc(name: string) -> bool {
	for c in IMPLEMENTED_COMMANDS {
		if c == name {
			return true
		}
	}
	return false
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
	}
	return CommandInfo{}, false
}

print_command_help :: proc(name: string) {
	info, found := find_command(name)
	if !found {
		fmt.printf("Unknown command: %s\n", name)
		print_usage()
		return
	}
	fmt.printf("Usage: %s\n\n%s\n", info.usage, info.short)
	if len(info.long) > 0 {
		fmt.printf("\n%s\n", info.long)
	}
}

print_usage :: proc() {
	fmt.println("envr - Manage your .env files.")
	fmt.println("")
	fmt.println("envr keeps your .env synced to a local, age encrypted database.")
	fmt.println("Is a safe and easy way to gather all your .env files in one place where they can")
	fmt.println("easily be backed by another tool such as restic or git.")
	fmt.println("")
	fmt.println("All your data is stored in ~/data.age")
	fmt.println("")
	fmt.println("Getting started is easy:")
	fmt.println("")
	fmt.println("1. Create your configuration file and set up encrypted storage:")
	fmt.println("")
	fmt.println("> envr init")
	fmt.println("")
	fmt.println("2. Scan for existing .env files:")
	fmt.println("")
	fmt.println("> envr scan")
	fmt.println("")
	fmt.println("Select the files you want to back up from the interactive list.")
	fmt.println("")
	fmt.println("3. Verify that it worked:")
	fmt.println("")
	fmt.println("> envr list")
	fmt.println("")
	fmt.println("Usage: envr <command> [args]")
	fmt.println("")
	fmt.println("Commands:")
	fmt.println("  init          Set up envr")
	fmt.println("  scan          Find and select .env files for backup")
	fmt.println("  sync          Update or restore your env backups")
	fmt.println("  backup <path> Import a .env file into envr")
	fmt.println("  restore <path> Restore a .env file from the database")
	fmt.println("  list          View your tracked files")
	fmt.println("  remove <path> Remove a .env file from your database")
	fmt.println("  check [path]  Check if files are backed up")
	fmt.println("  deps          Check for missing binaries")
	fmt.println("  version       Show envr's version")
	fmt.println("  edit-config   Edit your config with your default editor")
}
