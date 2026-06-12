package main

import "core:fmt"

cmd_deps :: proc(cmd: ^Command) {
	feats := check_features()

	headers := []string{"Feature", "Status"}
	rows: [dynamic][]string

	if .Git in feats {
		append(&rows, []string{"Git", "\u2713 Available"})
	} else {
		append(&rows, []string{"Git", "\u2717 Missing"})
	}

	if .Fd in feats {
		append(&rows, []string{"fd", "\u2713 Available"})
	} else {
		append(&rows, []string{"fd", "\u2717 Missing"})
	}

	if .Age in feats {
		append(&rows, []string{"age", "\u2713 Available"})
	} else {
		append(&rows, []string{"age", "\u2717 Missing"})
	}

	render_table(headers, rows[:])
}
