package main

import "core:encoding/json"
import "core:fmt"
import "core:io"
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
	defer delete(files)

	// TODO: Set sane default size
	results: [dynamic]SyncEntry
	defer delete(results)

	for &file in files {
		old_path: string
		old_path, _ = strings.clone(file.Path, context.temp_allocator)

		result, err_msg := db_sync(&db, &file)

		status: string
		is_dir_updated := .DirUpdated in result

		switch {
		case .Error in result:
			if len(err_msg) > 0 {
				status = err_msg
			} else {
				status = "error"
			}
		case .BackedUp in result:
			status = "Backed Up"
		case .Restored in result:
			status = "Restored"
		case .DirUpdated in result:
			status = "Moved"
		case:
			status = "OK"
		}

		if is_dir_updated {
			if !db_delete(&db, old_path) {
				return
			}
		}
		if db_update_required(result) {
			if !db_insert(&db, file) {
				return
			}
		}

		path_str, _ := strings.clone(file.Path)
		status_str, _ := strings.clone(status)
		append(&results, SyncEntry{Path = path_str, Status = status_str})
	}

	if terminal.is_terminal(os.stdout) {
		headers := []string{"File", "Status"}
		table_rows := make([dynamic][]string, 0, len(results))

		for res in results {
			row_slice := make([]string, 2)
			row_slice[0] = res.Path
			row_slice[1] = res.Status
			append(&table_rows, row_slice)
		}

		w := io.to_writer(os.to_writer(os.stdout))
		render_table(w, headers, table_rows[:])
	} else {
		data, marshal_err := json.marshal(results[:])
		if marshal_err != nil {
			fmt.printf("Error marshaling JSON: %v\n", marshal_err)
			return
		}
		fmt.println(string(data))
	}
}

