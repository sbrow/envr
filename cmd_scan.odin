package main

import "core:encoding/json"
import "core:fmt"

cmd_scan :: proc(cmd: ^Command) {
	if !can_scan() {
		fmt.println(
			"Error: please install fd to use the scan command (https://github.com/sharkdp/fd)",
		)
		return
	}

	db, db_ok := db_open()
	if !db_ok {
		return
	}
	defer db_close(&db)

	search_dirs := search_paths(db.cfg)
	if len(search_dirs) == 0 {
		fmt.println("No search paths configured. Please run `envr init` or edit your config.")
		return
	}

	// TODO: Figure out a sane default
	all_files: [dynamic]string
	for dir in search_dirs {
		found, scan_ok := scan_path(dir, db.cfg)
		if !scan_ok {
			fmt.printf("Error scanning %s\n", dir)
			continue
		}
		for f in found {
			append(&all_files, f)
		}
	}

	db_files, list_ok := db_list(&db)
	if !list_ok {
		return
	}

	files := find_unbacked(all_files[:], db_files[:])

	if len(files) == 0 {
		fmt.println("No .env files found to add.")
		return
	}

	if !is_tty() {
		output, marshal_err := json.marshal(files[:])
		if marshal_err != nil {
			fmt.printf("Error marshaling files to JSON: %v\n", marshal_err)
			return
		}
		fmt.println(string(output))
		return
	}

	selected, result := multi_select("Select .env files to backup:", files[:])
	if result == .Cancel {
		fmt.println("\x1b[2mCancelled.\x1b[0m")
		return
	}

	added_count: int
	for i in 0 ..< len(files) {
		if !selected[i] {
			continue
		}
		env_file, ok := new_env_file(files[i])
		if !ok {
			fmt.printf("Error reading %s\n", files[i])
			continue
		}
		if !db_insert(&db, env_file) {
			fmt.printf("Error adding %s\n", files[i])
			continue
		}
		added_count += 1
	}

	if added_count > 0 {
		fmt.printf("\x1b[1;32mSuccessfully added %d file(s) to backup.\x1b[0m\n", added_count)
	} else {
		fmt.println("\x1b[2mNo files were added.\x1b[0m")
	}
}

