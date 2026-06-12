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

cmd_sync :: proc(cmd: ^Command) {
	db, db_ok := db_open()
	if !db_ok {
		return
	}
	defer db_close(&db)

	files, list_ok := db_list(&db)
	if !list_ok {
		return
	}
	defer delete(files)

	results: [dynamic]SyncEntry

	for &file in files {
		old_path: string
		old_path, _ = strings.clone(file.Path)

		result, err_msg := db_sync(&db, &file)

		status: string
		s := i32(result)
		is_error := (s & i32(SyncResult.Error)) != 0
		is_backed := (s & i32(SyncResult.BackedUp)) != 0
		is_restored := (s & i32(SyncResult.Restored)) != 0
		is_dir_updated := (s & i32(SyncResult.DirUpdated)) != 0

		if is_error {
			if len(err_msg) > 0 {
				status = err_msg
			} else {
				status = "error"
			}
		} else if is_backed {
			status = "Backed Up"
			if !db_insert(&db, file) {
				return
			}
		} else if is_restored {
			status = "Restored"
		} else if is_dir_updated && !is_restored {
			status = "Moved"
		} else {
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

		render_table(headers, table_rows[:])
	} else {
		data, marshal_err := json.marshal(results[:])
		if marshal_err != nil {
			fmt.printf("Error marshaling JSON: %v\n", marshal_err)
			return
		}
		fmt.println(string(data))
	}
}

