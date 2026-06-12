package main

import "core:fmt"
import "core:strings"

cmd_backup :: proc(cmd: ^Command) {
	if len(cmd.args) != 1 {
		print_command_help("backup")
		return
	}

	path := cmd.args[0]
	if len(strings.trim_space(path)) == 0 {
		fmt.println("Error: No path provided")
		return
	}

	file, ok := new_env_file(path)
	if !ok {
		return
	}

	db, db_ok := db_open()
	if !db_ok {
		return
	}
	defer db_close(&db)

	if !db_insert(&db, file) {
		return
	}

	fmt.printf("Saved %s into the database\n", path)
}
