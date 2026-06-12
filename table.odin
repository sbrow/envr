package main

import "core:fmt"
import "core:strings"

render_table :: proc(headers: []string, rows: [][]string) {
	if !is_tty() {
		render_json_rows(headers, rows)
		return
	}

	col_widths := make([dynamic]int, 0, len(headers))
	for i in 0..<len(headers) {
		append(&col_widths, strings.rune_count(headers[i]))
	}
	for r in rows {
		for i in 0..<len(r) {
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
		for i in 0..<len(widths) {
			for _ in 0..<widths[i]+2 {
				strings.write_string(b, "\u2500")
			}
			if i < len(widths)-1 {
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
	for i in 0..<len(headers) {
		cell(&b, headers[i], col_widths[i])
	}
	fmt.println(strings.to_string(b))
	strings.builder_reset(&b)

	hline(&b, "\u251c", "\u253c", "\u2524", col_widths)

	for r in rows {
		strings.write_string(&b, "\u2502")
		for i in 0..<len(r) {
			cell(&b, r[i], col_widths[i])
		}
		fmt.println(strings.to_string(b))
		strings.builder_reset(&b)
	}

	hline(&b, "\u2514", "\u2534", "\u2518", col_widths)
}

render_json_rows :: proc(headers: []string, rows: [][]string) {
	fmt.print("[")
	for i in 0..<len(rows) {
		if i > 0 {
			fmt.print(",")
		}
		fmt.print("{")
		for j in 0..<len(headers) {
			if j > 0 {
				fmt.print(",")
			}
			fmt.printf("\"%s\":\"%s\"", headers[j], rows[i][j])
		}
		fmt.print("}")
	}
	fmt.println("]")
}
