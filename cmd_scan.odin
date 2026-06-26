package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:terminal"
import "core:terminal/ansi"

cmd_scan :: proc(cmd: ^Command) {
	db, db_ok := db_open(cmd.flags.config_file)
	if !db_ok {
		return
	}
	defer db_close(&db)

	search_dirs := search_paths(db.cfg, context.temp_allocator)
	if len(search_dirs) == 0 {
		fmt.wprintln(
			cmd.err,
			"No search paths configured. Please run `envr init -f` or edit your config.",
			flush = false,
		)
		return
	}

	// TODO: Figure out a sane default
	// Can't use temp allocator becuase strings inside are copied to context.allocator
	all_files := make([dynamic]string)
	defer {
		for &f in all_files {delete(f)}
		delete(all_files)
	}
	for dir in search_dirs {
		found, scan_ok := scan_path(dir, db.cfg)
		defer delete(found)
		if !scan_ok {
			fmt.wprintf(cmd.err, "Error scanning %s\n", dir, flush = false)
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
		fmt.wprintln(cmd.out, "No .env files found to add.", flush = false)
		return
	}

	if !terminal.is_terminal(os.stdout) {
		output, marshal_err := json.marshal(files[:])
		if marshal_err != nil {
			fmt.wprintf(
				cmd.err,
				"Error marshaling files to JSON: %v\n",
				marshal_err,
				flush = false,
			)
			return
		}
		fmt.wprintln(cmd.out, string(output), flush = false)
		return
	}

	selected, result := multi_select("Select .env files to backup:", files[:])
	defer delete(selected)
	if result == .Cancel {
		fmt.wprintln(
			cmd.out,
			ansi.CSI + ansi.FAINT + ansi.SGR + "Cancelled." + ANSI_RESET,
			flush = false,
		)
		return
	}

	added_count: int
	for i in 0 ..< len(files) {
		if !selected[i] {
			continue
		}
		// TODO: Test cover this leak
		env_file, ok := new_env_file(files[i])
		defer delete_envfile(&env_file)
		if !ok {
			fmt.wprintf(cmd.err, "Error reading %s\n", files[i], flush = false)
			continue
		}
		if !db_insert(&db, env_file) {
			fmt.wprintf(cmd.err, "Error adding %s\n", files[i], flush = false)
			continue
		}
		added_count += 1
	}

	if added_count > 0 {
		fmt.wprintf(
			cmd.out,
			ansi.CSI +
			ansi.BOLD +
			";" +
			ansi.FG_GREEN +
			ansi.SGR +
			"Successfully added %d file(s) to backup." +
			ANSI_RESET +
			"\n",
			added_count,
			flush = false,
		)
	} else {
		fmt.wprintln(
			cmd.out,
			ansi.CSI + ansi.FAINT + ansi.SGR + "No files were added." + ANSI_RESET,
			flush = false,
		)
	}
}

