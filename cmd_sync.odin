package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:terminal"
import "core:text/table"

SyncEntry :: struct {
	path:   string `json:"path"`,
	status: string `json:"status"`,
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

		results[i] = SyncEntry {
			path   = file.path,
			status = status,
		}
	}

	if terminal.is_terminal(os.stdout) {
		t: table.Table
		table.init(&t, context.temp_allocator, context.temp_allocator)
		table.padding(&t, 1, 1)

		table.aligned_header_of_values(
			&t,
			.Center,
			COLOR_TABLE_HEADING + "File" + ANSI_RESET,
			COLOR_TABLE_HEADING + "Status" + ANSI_RESET,
		)

		for res in results {
			table.row(&t, res.path, res.status)
		}

		table.write_decorated_table(cmd.out, &t, decorations, ansi_aware_width)
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

