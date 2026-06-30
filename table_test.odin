#+test

package main

import "core:strings"
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
	colored := colorize(.Heading, "Directory", disable = false)
	testing.expect_value(t, ansi_aware_width(colored), 9)
}

@(test)
test_ansi_aware_width_multibyte :: proc(t: ^testing.T) {
	testing.expect_value(t, ansi_aware_width("\u2713 Available"), 13)
	testing.expect_value(t, ansi_aware_width("\u2717 Missing"), 11)
}

@(test)
test_ansi_aware_width_multiple_escape_sequences :: proc(t: ^testing.T) {
	colored := strings.concatenate(
		{
			colorize(.Heading, "a", disable = false),
			colorize(.Heading, "b", disable = false),
			colorize(.Heading, "c", disable = false),
		},
		context.temp_allocator,
	)
	testing.expect_value(t, ansi_aware_width(colored), 3)
}

