package main

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

