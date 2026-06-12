package main

import "core:fmt"
import "core:path/filepath"
import "core:strings"

cmd_remove :: proc(cmd: ^Command) {
    if len(cmd.args) != 1 {
		print_command_help("remove")
        return
    }

    path := cmd.args[0]
    if len(strings.trim_space(path)) == 0 {
        fmt.println("Error: No path provided")
        return
    }

    abs_path: string
    if filepath.is_abs(path) {
        abs_path = path
    } else {
        resolved, abs_err := filepath.abs(path)
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

    if !db_delete(&db, abs_path) {
        return
    }

    fmt.printf("Removed %s from the database\n", abs_path)
}
