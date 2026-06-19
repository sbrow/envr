#+test
package main

import "core:fmt"
import "core:strings"
import "core:terminal/ansi"
import "core:testing"

@(test)
test_render_table_normal :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	headers := []string{"Name", "Path"}
	rows := [][]string{{"foo", "/home/user/.env"}, {"bar", "/home/user/project/.env"}}

	w := strings.to_writer(&b)
	render_table(w, headers, rows)

	output := strings.to_string(b)

	g := ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR
	r := ANSI_RESET
	n := ansi.CSI + ansi.SGR

	expected := fmt.tprintf(
		"┌──────┬─────────────────────────┐\n" +
		"│ %sName%s │ %s         Path          %s │\n" +
		"├──────┼─────────────────────────┤\n" +
		"│ %sfoo %s │ %s/home/user/.env        %s │\n" +
		"│ %sbar %s │ %s/home/user/project/.env%s │\n" +
		"└──────┴─────────────────────────┘\n",
		g,
		r,
		g,
		r,
		n,
		r,
		n,
		r,
		n,
		r,
		n,
		r,
	)
	testing.expect(
		t,
		output == expected,
		fmt.tprintf(
			"table output mismatch\n--- expected ---\n%s\n--- got ---\n%s\n",
			expected,
			output,
		),
	)
}

@(test)
test_render_table_empty :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	headers := []string{"Name"}
	rows: [][]string

	w := strings.to_writer(&b)
	render_table(w, headers, rows)

	output := strings.to_string(b)

	g := ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR
	r := ANSI_RESET

	expected := fmt.tprintf(
		"┌──────┐\n" +
		"│ %sName%s │\n" +
		"├──────┤\n" +
		"└──────┘\n",
		g,
		r,
	)
	testing.expect(
		t,
		output == expected,
		fmt.tprintf(
			"table output mismatch\n--- expected ---\n%s\n--- got ---\n%s\n",
			expected,
			output,
		),
	)
}

@(test)
test_render_table_unicode :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	headers := []string{"Status", "Detail"}
	rows := [][]string{{"\u2713 Available", "ok"}, {"\u2717 Missing", "fail"}}

	w := strings.to_writer(&b)
	render_table(w, headers, rows)

	output := strings.to_string(b)

	g := ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR
	r := ANSI_RESET
	n := ansi.CSI + ansi.SGR

	expected := fmt.tprintf(
		"┌─────────────┬────────┐\n" +
		"│ %s  Status   %s │ %sDetail%s │\n" +
		"├─────────────┼────────┤\n" +
		"│ %s✓ Available%s │ %sok    %s │\n" +
		"│ %s✗ Missing  %s │ %sfail  %s │\n" +
		"└─────────────┴────────┘\n",
		g,
		r,
		g,
		r,
		n,
		r,
		n,
		r,
		n,
		r,
		n,
		r,
	)
	testing.expect(
		t,
		output == expected,
		fmt.tprintf(
			"table output mismatch\n--- expected ---\n%s\n--- got ---\n%s\n",
			expected,
			output,
		),
	)
}

