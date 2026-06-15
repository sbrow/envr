package main

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:terminal"

ListEntry :: struct {
	Directory: string `json:"directory"`,
	Path:      string `json:"path"`,
}

cmd_list :: proc(cmd: ^Command) {
	db, db_ok := db_open(cmd.config_path)
	if !db_ok {
		return
	}
	defer db_close(&db)

	rows, list_ok := db_list(&db)
	if !list_ok {
		return
	}
	defer delete(rows)

	if terminal.is_terminal(os.stdout) {
		headers := []string{"Directory", "Path"}
		table_rows := make([dynamic][]string, 0, len(rows), context.temp_allocator)

		for row in rows {
			dir_str := strings.concatenate({row.Dir, "/"}, context.temp_allocator)
			filename := filepath.base(row.Path)
			row_slice := make([]string, 2)
			row_slice[0] = dir_str
			row_slice[1] = filename
			append(&table_rows, row_slice)
		}

		w := io.to_writer(os.to_writer(os.stdout))
		render_table(w, headers, table_rows[:])
	} else {
		entries: [dynamic]ListEntry
		for row in rows {
			filename := filepath.base(row.Path)
			append(
				&entries,
				ListEntry {
					Directory = strings.concatenate({row.Dir, "/"}, context.temp_allocator),
					Path = filename,
				},
			)
		}

		data, marshal_err := json.marshal(entries[:])
		if marshal_err != nil {
			fmt.printf("Error marshaling JSON: %v\n", marshal_err)
			return
		}
		fmt.println(string(data))
	}
}

