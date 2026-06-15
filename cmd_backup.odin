package main

import "core:fmt"
import "core:strings"

cmd_backup :: proc(cmd: ^Command) {
	if len(cmd.args) != 1 {
		print_command_help(cmd)
		return
	}

	path := cmd.args[0]
	if len(strings.trim_space(path)) == 0 {
		fmt.wprintln(cmd.err, "Error: No path provided", flush = false)
		return
	}

	file, ok := new_env_file(path)
	if !ok {
		return
	}

	db, db_ok := db_open(cmd.config_path)
	if !db_ok {
		return
	}
	defer db_close(&db)

	if !db_insert(&db, file) {
		return
	}

	fmt.wprintf(cmd.out, "Saved %s into the database\n", path, flush = false)
}

