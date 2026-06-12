package main

import "core:encoding/json"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

ListEntry :: struct {
    Directory: string `json:"directory"`,
    Path:      string `json:"path"`,
}

cmd_list :: proc(cmd: ^Command) {
    db, db_ok := db_open()
    if !db_ok {
        return
    }
    defer db_close(&db)

    rows, list_ok := db_list(&db)
    if !list_ok {
        return
    }
    defer delete(rows)

    if is_tty() {
        headers := []string{"Directory", "Path"}
        table_rows := make([dynamic][]string, 0, len(rows))

        for row in rows {
            b: strings.Builder
            strings.builder_init(&b)
            strings.write_string(&b, row.Dir)
            strings.write_string(&b, "/")
            dir_str, _ := strings.clone(strings.to_string(b))

            rel, rel_err := filepath.rel(row.Dir, row.Path)
            if rel_err != nil {
                fmt.printf("Error getting relative path: %v\n", rel_err)
                return
            }
            cloned_rel, _ := strings.clone(rel)
            row_slice := make([]string, 2)
            row_slice[0] = dir_str
            row_slice[1] = cloned_rel
            append(&table_rows, row_slice)
        }

        render_table(headers, table_rows[:])
    } else {
        entries: [dynamic]ListEntry
        for row in rows {
            rel, rel_err := filepath.rel(row.Dir, row.Path)
            if rel_err != nil {
                fmt.printf("Error getting relative path: %v\n", rel_err)
                return
            }
            b: strings.Builder
            strings.builder_init(&b)
            strings.write_string(&b, row.Dir)
            strings.write_string(&b, "/")
            append(&entries, ListEntry{
                Directory = strings.to_string(b),
                Path = rel,
            })
        }

        data, marshal_err := json.marshal(entries[:])
        if marshal_err != nil {
            fmt.printf("Error marshaling JSON: %v\n", marshal_err)
            return
        }
        fmt.println(string(data))
    }
}
