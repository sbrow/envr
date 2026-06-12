package main

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:terminal"

render_table :: proc(headers: []string, rows: [][]string) {
	if !terminal.is_terminal(os.stdout) {
		w := io.to_writer(os.to_writer(os.stdout))
		render_json_rows(w, headers, rows)
		io.write_string(w, "\n")
		return
	}

	col_widths := make([dynamic]int, 0, len(headers))
	for i in 0 ..< len(headers) {
		append(&col_widths, strings.rune_count(headers[i]))
	}
	for r in rows {
		for i in 0 ..< len(r) {
			w := strings.rune_count(r[i])
			if i < len(col_widths) && w > col_widths[i] {
				col_widths[i] = w
			}
		}
	}

	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	defer delete(col_widths)

	hline :: proc(b: ^strings.Builder, left, mid, right: string, widths: [dynamic]int) {
		strings.write_string(b, left)
		for i in 0 ..< len(widths) {
			for _ in 0 ..< widths[i] + 2 {
				strings.write_string(b, "\u2500")
			}
			if i < len(widths) - 1 {
				strings.write_string(b, mid)
			} else {
				strings.write_string(b, right)
			}
		}
		fmt.println(strings.to_string(b^))
		strings.builder_reset(b)
	}

	hline(&b, "\u250c", "\u252c", "\u2510", col_widths)

	cell :: proc(b: ^strings.Builder, s: string, width: int) {
		extra := len(s) - strings.rune_count(s)
		fmt.sbprintf(b, " %-*s \u2502", width + extra, s)
	}

	strings.write_string(&b, "\u2502")
	for i in 0 ..< len(headers) {
		cell(&b, headers[i], col_widths[i])
	}
	fmt.println(strings.to_string(b))
	strings.builder_reset(&b)

	hline(&b, "\u251c", "\u253c", "\u2524", col_widths)

	for r in rows {
		strings.write_string(&b, "\u2502")
		for i in 0 ..< len(r) {
			cell(&b, r[i], col_widths[i])
		}
		fmt.println(strings.to_string(b))
		strings.builder_reset(&b)
	}

	hline(&b, "\u2514", "\u2534", "\u2518", col_widths)
}

render_json_rows :: proc(w: io.Writer, headers: []string, rows: [][]string) {
	entries := make([dynamic]map[string]string, 0, len(rows), context.temp_allocator)

	for row in rows {
		entry := make(map[string]string, len(headers), context.temp_allocator)
		for i in 0 ..< len(headers) {
			entry[headers[i]] = row[i]
		}
		append(&entries, entry)
	}

	data, err := json.marshal(entries[:], allocator = context.temp_allocator)
	if err != nil {
		fmt.eprintf("Error marshaling JSON: %v\n", err)
		return
	}
	fmt.wprintf(w, "%s", data, flush = false)
}

