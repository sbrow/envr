package main

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_render_json_rows_normal :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	headers := []string{"name", "path"}
	rows := [][]string{{"foo", "/home/user/.env"}, {"bar", "/home/user/project/.env"}}

	w := strings.to_writer(&b)
	render_json_rows(w, headers, rows)

	output := strings.to_string(b)

	result: []map[string]string = ---
	unmarshal_err := json.unmarshal_string(output, &result, allocator = context.temp_allocator)
	testing.expect(
		t,
		unmarshal_err == nil,
		fmt.tprintf("json unmarshal failed: %v\noutput was: %q", unmarshal_err, output),
	)
	testing.expect(t, len(result) == 2, fmt.tprintf("expected 2 rows, got %d", len(result)))
	testing.expect(
		t,
		result[0]["name"] == "foo",
		fmt.tprintf("expected name=foo, got %q", result[0]["name"]),
	)
	testing.expect(t, result[0]["path"] == "/home/user/.env")
	testing.expect(t, result[1]["name"] == "bar")
	testing.expect(t, result[1]["path"] == "/home/user/project/.env")
}

@(test)
test_render_json_rows_special_chars :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	headers := []string{"key", "value"}
	rows := [][]string {
		{"quote", `has "double quotes"`},
		{"backslash", `path\to\file`},
		{"newline", "line1\nline2"},
		{"mixed", `a "b" c\nd`},
	}

	w := strings.to_writer(&b)
	render_json_rows(w, headers, rows)

	output := strings.to_string(b)

	result: []map[string]string = ---
	unmarshal_err := json.unmarshal(
		transmute([]byte)output,
		&result,
		allocator = context.temp_allocator,
	)
	testing.expect(
		t,
		unmarshal_err == nil,
		fmt.tprintf("json unmarshal failed: %v\noutput was: %q", unmarshal_err, output),
	)
	testing.expect(t, len(result) == 4)
	testing.expect(
		t,
		result[0]["value"] == `has "double quotes"`,
		fmt.tprintf("got %q", result[0]["value"]),
	)
	testing.expect(t, result[1]["value"] == `path\to\file`)
	testing.expect(t, result[2]["value"] == "line1\nline2")
	testing.expect(t, result[3]["value"] == `a "b" c\nd`)
}

@(test)
test_render_json_rows_empty :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	headers := []string{"name"}
	rows: [][]string

	w := strings.to_writer(&b)
	render_json_rows(w, headers, rows)

	output := strings.to_string(b)

	result: []map[string]string = ---
	unmarshal_err := json.unmarshal_string(output, &result, allocator = context.temp_allocator)
	testing.expect(
		t,
		unmarshal_err == nil,
		fmt.tprintf("json unmarshal failed: %v\noutput was: %q", unmarshal_err, output),
	)
	testing.expect(t, len(result) == 0)
}

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

	expected := `┌──────┬─────────────────────────┐
│ Name │ Path                    │
├──────┼─────────────────────────┤
│ foo  │ /home/user/.env         │
│ bar  │ /home/user/project/.env │
└──────┴─────────────────────────┘
`
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

	expected := `┌──────┐
│ Name │
├──────┤
└──────┘
`
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

	expected := `┌─────────────┬────────┐
│ Status      │ Detail │
├─────────────┼────────┤
│ ✓ Available │ ok     │
│ ✗ Missing   │ fail   │
└─────────────┴────────┘
`
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

