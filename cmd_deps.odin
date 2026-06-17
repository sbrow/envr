package main

import "core:fmt"
import "core:os"
import "core:terminal"

// TODO: Improve table rendering
cmd_deps :: proc(cmd: ^Command) {
	feats := check_features()

	headers := []string{"Feature", "Status"}
	rows: [dynamic][]string

	if .Git in feats {
		append(&rows, []string{"Git", "\u2713 Available"})
	} else {
		append(&rows, []string{"Git", "\u2717 Missing"})
	}

	if terminal.is_terminal(os.stdout) {
		render_table(cmd.out, headers, rows[:])
	} else {
		render_json_rows(cmd.out, headers, rows[:])
		fmt.wprint(cmd.out, "\n", flush = false)
	}
}

