package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:terminal"

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

	if terminal.is_terminal(os.stdout) {
		w := io.to_writer(os.to_writer(os.stdout))
		render_table(w, headers, rows[:])
	} else {
		w := io.to_writer(os.to_writer(os.stdout))
		render_json_rows(w, headers, rows[:])
		io.write_string(w, "\n")
	}
}

