package main

import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:strings"
import "core:terminal/ansi"

render_table :: proc(w: io.Writer, headers: []string, rows: [][]string) {
	col_widths := make([dynamic]int, 0, len(headers), context.temp_allocator)
	for i in 0 ..< len(headers) {
		append(&col_widths, strings.rune_count(headers[i]))
	}
	for r in rows {
		for i in 0 ..< len(r) {
			rw := strings.rune_count(r[i])
			if i < len(col_widths) && rw > col_widths[i] {
				col_widths[i] = rw
			}
		}
	}

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)

	hline :: proc(
		w: io.Writer,
		b: ^strings.Builder,
		left, mid, right: string,
		widths: [dynamic]int,
	) {
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
		fmt.wprintf(w, "%s\n", strings.to_string(b^), flush = false)
		strings.builder_reset(b)
	}

	hline(w, &b, "\u250c", "\u252c", "\u2510", col_widths)

	cell :: proc(b: ^strings.Builder, s: string, width: int, color: string = "", center := false) {
		before: int
		after: int

		total_pad := width - strings.rune_count(s)

		if center {
			before = total_pad / 2
			after = total_pad - before
		} else {
			before = 0
			after = total_pad
		}

		fmt.sbprintf(
			b,
			" %s%s%s%*s%s%*s%s \u2502",
			ansi.CSI,
			color,
			ansi.SGR,
			before,
			"",
			s,
			after,
			"",
			ansi.CSI + ansi.RESET + ansi.SGR,
		)
	}

	strings.write_string(&b, "\u2502")
	for i in 0 ..< len(headers) {
		cell(&b, headers[i], col_widths[i], ansi.FG_BRIGHT_GREEN, true)
	}
	fmt.wprintf(w, "%s\n", strings.to_string(b), flush = false)
	strings.builder_reset(&b)

	hline(w, &b, "\u251c", "\u253c", "\u2524", col_widths)

	for r in rows {
		strings.write_string(&b, "\u2502")
		for i in 0 ..< len(r) {
			cell(&b, r[i], col_widths[i])
		}
		fmt.wprintf(w, "%s\n", strings.to_string(b), flush = false)
		strings.builder_reset(&b)
	}

	hline(w, &b, "\u2514", "\u2534", "\u2518", col_widths)
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

