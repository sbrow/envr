package main

import "core:fmt"
import "core:os"
import "core:path/filepath"

cmd_check :: proc(cmd: ^Command) {
	check_path: string
	if len(cmd.args) > 0 {
		check_path = cmd.args[0]
	} else {
		cwd, cwd_err := os.get_working_directory(context.temp_allocator)
		if cwd_err != nil {
			fmt.wprintf(cmd.err, "Error getting current directory: %v\n", cwd_err, flush = false)
			return
		}
		check_path = cwd
	}

	abs_path: string
	if filepath.is_abs(check_path) {
		abs_path = check_path
	} else {
		resolved, abs_err := filepath.abs(check_path)
		if abs_err != nil {
			fmt.wprintf(cmd.err, "Error getting absolute path: %v\n", abs_err, flush = false)
			return
		}
		abs_path = resolved
	}

	db, db_ok := db_open(cmd.config_path)
	if !db_ok {
		return
	}
	defer db_close(&db)

	is_dir := os.is_directory(abs_path)

	files_in_path: [dynamic]string

	if is_dir {
		scanned, scan_ok := scan_path(abs_path, db.cfg)
		if !scan_ok {
			fmt.wprintln(cmd.err, "Error scanning directory for .env files", flush = false)
			return
		}
		files_in_path = scanned
	} else {
		append(&files_in_path, abs_path)
	}

	db_files, list_ok := db_list(&db)
	if !list_ok {
		return
	}

	not_backed := find_unbacked(files_in_path[:], db_files[:])

	if len(not_backed) == 0 {
		if len(files_in_path) == 0 {
			fmt.wprintln(cmd.out, "No .env files found in the specified directory.", flush = false)
		} else {
			fmt.wprintln(cmd.out, "✓ All .env files in the directory are backed up.", flush = false)
		}
	} else {
		fmt.wprintf(cmd.out, "Found %d .env file(s) that are not backed up:\n", len(not_backed), flush = false)
		for file in not_backed {
			fmt.wprintf(cmd.out, "  %s\n", file, flush = false)
		}
		fmt.wprintln(cmd.out, "\nRun 'envr sync' to back up these files.", flush = false)
	}
}
