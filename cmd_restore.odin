package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

cmd_restore :: proc(cmd: ^Command) {
	if len(cmd.args) != 1 {
		print_command_help("restore")
		return
	}

	path := cmd.args[0]
	if len(strings.trim_space(path)) == 0 {
		fmt.println("Error: No path provided")
		return
	}

	// TODO: Is this the right way to handle this?
	abs_path: string
	if filepath.is_abs(path) {
		abs_path = path
	} else {
		resolved, abs_err := filepath.abs(path)
		if abs_err != nil {
			fmt.printf("Error getting absolute path: %v\n", abs_err)
			return
		}
		abs_path = resolved
	}

	db, db_ok := db_open(cmd.config_path)
	if !db_ok {
		return
	}
	defer db_close(&db)

	file, fetch_ok := db_fetch(&db, abs_path)
	if !fetch_ok {
		return
	}

	dir := filepath.dir(file.Path)
	os.mkdir_all(dir)

	write_err := os.write_entire_file(file.Path, file.contents)
	if write_err != nil {
		fmt.printf("Error writing file: %v\n", write_err)
		return
	}

	fmt.printf("Restored %s\n", file.Path)
}

