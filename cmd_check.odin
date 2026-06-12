package main

import "core:fmt"
import "core:os"
import "core:path/filepath"

cmd_check :: proc(cmd: ^Command) {
	feats := check_features()

	check_path: string
	if len(cmd.args) > 0 {
		check_path = cmd.args[0]
	} else {
		cwd, cwd_err := os.get_working_directory(context.allocator)
		if cwd_err != nil {
			fmt.printf("Error getting current directory: %v\n", cwd_err)
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
			fmt.printf("Error getting absolute path: %v\n", abs_err)
			return
		}
		abs_path = resolved
	}

	db, db_ok := db_open()
	if !db_ok {
		return
	}
	defer db_close(&db)

	is_dir := os.is_directory(abs_path)

	files_in_path: [dynamic]string

	if is_dir {
		if cant_scan(feats) {
			fmt.println(
				"Error: please install fd to use the check command (https://github.com/sharkdp/fd)",
			)
			return
		}

		scanned, scan_ok := scan_path(abs_path, db.cfg)
		if !scan_ok {
			fmt.println("Error scanning directory for .env files")
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
			fmt.println("No .env files found in the specified directory.")
		} else {
			fmt.println("✓ All .env files in the directory are backed up.")
		}
	} else {
		fmt.printf("Found %d .env file(s) that are not backed up:\n", len(not_backed))
		for file in not_backed {
			fmt.printf("  %s\n", file)
		}
		fmt.println("\nRun 'envr sync' to back up these files.")
	}
}

