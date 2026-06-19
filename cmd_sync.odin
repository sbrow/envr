package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:terminal"

SyncEntry :: struct {
	Path:   string `json:"path"`,
	Status: string `json:"status"`,
}

// TODO: Check for quiet failures.
// TODO: Support --format -f flags
cmd_sync :: proc(cmd: ^Command) {
	db, db_ok := db_open(cmd.config_path)
	if !db_ok {
		return
	}
	defer db_close(&db)

	files, list_ok := db_list(&db)
	if !list_ok {
		return
	}

	results := make([]SyncEntry, len(files), context.temp_allocator)

	for &file, i in files {
		result, err := db_sync(&db, &file)

		status: string
		if err != .None {
			status = sync_error_message(err)
		} else if .BackedUp in result {
			status = .DirUpdated in result ? "Moved & Backed Up" : "Backed Up"
		} else if .Restored in result {
			status = .DirUpdated in result ? "Moved & Restored" : "Restored"
		} else if .DirUpdated in result {
			status = "Moved"
		} else {
			status = "OK"
		}

		// TODO: Handle errors
		path_str, _ := strings.clone(file.Path, context.temp_allocator)
		status_str, _ := strings.clone(status, context.temp_allocator)
		results[i] = SyncEntry {
			Path   = path_str,
			Status = status_str,
		}
	}

	if terminal.is_terminal(os.stdout) {
		headers := []string{"File", "Status"}
		// TODO: Use [2]string instead of slice here
		table_rows := make([dynamic][]string, 0, len(results), context.temp_allocator)

		for res in results {
			row_slice := [2]string{res.Path, res.Status}
			append(&table_rows, row_slice[:])
		}

		render_table(cmd.out, headers, table_rows[:])
	} else {
		data, marshal_err := json.marshal(results[:], allocator = context.temp_allocator)
		if marshal_err != nil {
			fmt.wprintf(cmd.err, "Error marshaling JSON: %v\n", marshal_err, flush = false)
			return
		}
		fmt.wprintln(cmd.out, string(data), flush = false)
	}
}

sync_error_message :: proc(e: SyncError) -> string {
	switch e {
	case .None:
		return ""
	case .DirMissing:
		return "directory missing"
	case .MultipleDirs:
		return "multiple directories found"
	case .GitRootFailed:
		return "failed to find git roots"
	case .WriteFailed:
		return "failed to write file"
	case .ReadFailed:
		return "failed to read file"
	case .DbFailed:
		return "failed to update database"
	}
	return "unknown error"
}

