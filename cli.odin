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

IMPLEMENTED_COMMANDS := []string{
	"version",
	"deps",
}

parse_args :: proc() -> (cmd: Command, ok: bool) {
	args := os.args
	if len(args) < 2 {
		print_usage()
		return Command{}, false
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

print_usage :: proc() {
	fmt.println("envr - Manage your .env files.")
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
