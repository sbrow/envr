package main

import "core:fmt"
import "core:io"
import "core:text/table"
import "core:unicode/utf8"

decorations := table.Decorations {
	"┌",
	"┬",
	"┐",
	"├",
	"┼",
	"┤",
	"└",
	"┴",
	"┘",
	"│",
	"─",
}

// TODO: Optimize ansi_aware_width
ansi_aware_width :: proc(str: string) -> int {
	buf: [4096]byte
	pos := 0
	i := 0
	for i < len(str) {
		if i + 1 < len(str) && str[i] == 0x1b && str[i + 1] == '[' {
			i += 2
			for i < len(str) {c := str[i]; i += 1; if c >= 0x40 && c <= 0x7E {break}}
		} else {
			buf[pos] = str[i]; pos += 1; i += 1
		}
	}
	_, _, width := utf8.grapheme_count(string(buf[:pos]))
	return width
}

write_borderless_table :: proc(w: io.Writer, t: ^table.Table) {
	table.build(t, ansi_aware_width)

	write_table_separator :: proc(w: io.Writer, tbl: ^table.Table) {
		io.write_byte(w, '\n')
	}

	if t.caption != "" {
		table.write_text_align(
			w,
			fmt.tprintf("%s%s%s", COLOR_HEADINGS, t.caption, ANSI_RESET),
			.Left,
			0, //t.lpad,
			0, //t.rpad,
			t.tblw + t.nr_cols - 1 - ansi_aware_width(t.caption) - t.lpad - t.rpad,
		)
		io.write_byte(w, '\n')
	}

	write_table_separator(w, t)
	for row in 0 ..< t.nr_rows {
		for col in 0 ..< t.nr_cols {
			table.write_table_cell(w, t, row, col)
		}
		io.write_byte(w, '\n')
		if t.has_header_row && row == table.header_row(t) {
			write_table_separator(w, t)
		}
	}
	write_table_separator(w, t)
}

table_reset :: proc(t: ^table.Table) {
	clear(&t.cells)
	clear(&t.colw)
	t.caption = ""
	t.tblw = 0
	t.nr_cols = 0
	t.nr_rows = 0
}

