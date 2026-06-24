package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:terminal"
import "core:text/table"

ListEntry :: struct {
	dir:  string `json:"directory"`,
	path: string `json:"path"`,
}

// TODO: Support --format flag
// TODO: Improve table rendering
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

	if terminal.is_terminal(os.stdout) {
		t: table.Table
		table.init(&t, context.temp_allocator, context.temp_allocator)
		table.padding(&t, 1, 1)
		table.aligned_header_of_values(
			&t,
			.Center,
			COLOR_TABLE_HEADING + "Directory" + ANSI_RESET,
			COLOR_TABLE_HEADING + "Path" + ANSI_RESET,
		)

		for row in rows {
			dir_str := strings.concatenate(
				{row.dir, os.Path_Separator_String},
				context.temp_allocator,
			)
			filename := filepath.base(row.path)

			table.row(&t, dir_str, filename)
		}

		table.write_decorated_table(cmd.out, &t, decorations, ansi_aware_width)
	} else {
		// TODO: Should we instead print full entries here?
		entries: [dynamic]ListEntry
		for row in rows {
			filename := filepath.base(row.path)
			append(
				&entries,
				ListEntry {
					dir = strings.concatenate(
						{row.dir, os.Path_Separator_String},
						context.temp_allocator,
					),
					path = filename,
				},
			)
		}


		data, marshal_err := json.marshal(entries[:], allocator = context.temp_allocator)
		if marshal_err != nil {
			fmt.wprintf(cmd.err, "Error marshaling JSON: %v\n", marshal_err, flush = false)
			return
		}
		fmt.wprintln(cmd.out, string(data), flush = false)
	}
}

