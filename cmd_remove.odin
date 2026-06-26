package main

import "core:fmt"
import "core:path/filepath"
import "core:strings"

cmd_remove :: proc(cmd: ^Command) {
	if len(cmd.args) != 1 {
		print_command_help(cmd)
		return
	}

	path := cmd.args[0]
	if len(strings.trim_space(path)) == 0 {
		fmt.wprintln(cmd.err, "Error: No path provided", flush = false)
		return
	}

	abs_path, abs_err := filepath.abs(path, context.temp_allocator)
	if abs_err != nil {
		fmt.wprintf(cmd.err, "Error getting absolute path: %v\n", abs_err, flush = false)
		return
	}

	db, db_ok := db_open(cmd.flags.config_file)
	if !db_ok {
		return
	}
	defer db_close(&db)

	if !db_delete(&db, abs_path) {
		return
	}

	fmt.wprintf(cmd.out, "Removed %s from the database\n", abs_path, flush = false)
}

