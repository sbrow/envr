package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

cmd_restore :: proc(cmd: ^Command) {
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

	file, fetch_ok := db_fetch(&db, abs_path)
	if !fetch_ok {
		return
	}

	dir := filepath.dir(file.path)
	if err := os.mkdir_all(dir); err != nil {
		fmt.wprintf(cmd.err, "Failed to create directory: %v\n", err, flush = false)

		return
	}

	write_err := os.write_entire_file(file.path, file.contents)
	if write_err != nil {
		fmt.wprintf(cmd.err, "Error writing file: %v\n", write_err, flush = false)

		return
	}

	fmt.wprintf(cmd.out, "Restored %s\n", file.path, flush = false)
}

