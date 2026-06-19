#+test

package main

import "core:testing"

@(test)
test_ansi_aware_width_plain_ascii :: proc(t: ^testing.T) {
	testing.expect_value(t, ansi_aware_width("hello"), 5)
}

@(test)
test_ansi_aware_width_empty :: proc(t: ^testing.T) {
	testing.expect_value(t, ansi_aware_width(""), 0)
}

@(test)
test_ansi_aware_width_with_color_codes :: proc(t: ^testing.T) {
	colored := COLOR_TABLE_HEADING + "Directory" + ANSI_RESET
	testing.expect_value(t, ansi_aware_width(colored), 9)
}

@(test)
test_ansi_aware_width_unicode :: proc(t: ^testing.T) {
	testing.expect_value(t, ansi_aware_width("\u2713 Available"), 11)
	testing.expect_value(t, ansi_aware_width("\u2717 Missing"), 9)
}

@(test)
test_ansi_aware_width_multiple_escape_sequences :: proc(t: ^testing.T) {
	colored := COLOR_TABLE_HEADING + "a" + ANSI_RESET + "b" + COLOR_TABLE_HEADING + "c" + ANSI_RESET
	testing.expect_value(t, ansi_aware_width(colored), 3)
}
