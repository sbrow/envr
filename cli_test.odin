#+feature dynamic-literals

#+test
package main

import "core:bufio"
import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_usage_text_contains_all_commands :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	write_usage(strings.to_writer(&b))
	text := strings.to_string(b)

	for c in COMMANDS {
		testing.expect(
			t,
			strings.contains(text, c.name),
			fmt.tprintf("usage missing command %q", c.name),
		)
		for a in c.aliases {
			testing.expect(t, strings.contains(text, a), fmt.tprintf("usage missing alias %q", a))
		}
	}
}

@(test)
test_usage_text_contains_steps :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	write_usage(strings.to_writer(&b))
	text := strings.to_string(b)

	testing.expect(t, strings.contains(text, "1."), "missing step 1")
	testing.expect(t, strings.contains(text, "2."), "missing step 2")
	testing.expect(t, strings.contains(text, "3."), "missing step 3")
	testing.expect(t, strings.contains(text, "4."), "missing step 4")
	testing.expect(t, strings.contains(text, "5."), "missing step 5")
	testing.expect(t, strings.contains(text, "> envr sync\n"), "step 4 missing 'envr sync'")
	testing.expect(t, strings.contains(text, "> envr restore"), "step 5 missing 'envr restore'")
}

@(test)
test_usage_text_contains_flags_and_help_hint :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	write_usage(strings.to_writer(&b))
	text := strings.to_string(b)

	testing.expect(t, strings.contains(text, "Flags:"), "missing Flags section")
	testing.expect(t, strings.contains(text, "--help"), "missing --help flag")
	testing.expect(t, strings.contains(text, "[command] --help"), "missing help hint")
}

@(test)
test_command_help_backup :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	ok := write_command_help("backup", strings.to_writer(&b))
	testing.expect(t, ok, "write_command_help(\"backup\") returned false")

	text := strings.to_string(b)
	testing.expect(t, strings.contains(text, "Usage:"), "missing Usage line")
	testing.expect(t, strings.contains(text, "envr backup <path>"), "missing usage pattern")
	testing.expect(t, strings.contains(text, "Aliases:"), "missing Aliases section")
	testing.expect(t, strings.contains(text, "add"), "missing 'add' alias")
	testing.expect(t, strings.contains(text, "Flags:"), "missing Flags section")
	testing.expect(t, strings.contains(text, "--help"), "missing --help in flags")
}

@(test)
test_command_help_add_alias :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	ok := write_command_help("add", strings.to_writer(&b))
	testing.expect(t, ok, "write_command_help(\"add\") returned false")

	text := strings.to_string(b)
	testing.expect(
		t,
		strings.contains(text, "envr backup <path>"),
		"'add' alias should resolve to backup usage",
	)
	testing.expect(t, strings.contains(text, "Aliases:"), "missing Aliases section")
}

@(test)
test_command_help_init_no_aliases :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	ok := write_command_help("init", strings.to_writer(&b))
	testing.expect(t, ok, "write_command_help(\"init\") returned false")

	text := strings.to_string(b)
	testing.expect(t, strings.contains(text, "Usage:"), "missing Usage line")
	testing.expect(t, !strings.contains(text, "Aliases:"), "init should not have Aliases section")
	testing.expect(t, strings.contains(text, "Flags:"), "missing Flags section")
	testing.expect(t, strings.contains(text, "show this documentation"), "missing help flag description")
	testing.expect(t, strings.contains(text, "--force"), "missing --force flag")
}

@(test)
test_command_help_unknown :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	ok := write_command_help("nonexistent", strings.to_writer(&b))
	testing.expect(t, !ok, "write_command_help(\"nonexistent\") should return false")

	text := strings.to_string(b)
	testing.expect_value(t, len(text), 0)
}

@(test)
test_command_help_version :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	ok := write_command_help("version", strings.to_writer(&b))
	testing.expect(t, ok, "write_command_help(\"version\") returned false")

	text := strings.to_string(b)
	testing.expect(t, strings.contains(text, "Usage:"), "missing Usage line")
	testing.expect(
		t,
		!strings.contains(text, "Aliases:"),
		"version should not have Aliases section",
	)
}

test_parse_args :: proc(
	args: []string,
) -> (
	cmd: Command,
	ok: bool,
	out_text: string,
	err_text: string,
) {
	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok = parse_args(args, strings.to_stream(&out_b), strings.to_stream(&err_b))

	if ok {
		bufio.writer_flush(cmd.out_buf)
		out_text = strings.to_string(out_b)
		err_text = strings.to_string(err_b)
	}

	return
}

@(test)
test_parse_args_bare_command :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.name, "list")
	testing.expect_value(t, len(cmd.args), 0)
}

@(test)
test_parse_args_positional :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "backup", "/project/.env"})
	defer delete_command(&cmd)
	testing.expect(t, ok, "should succeed")

	testing.expect_value(t, cmd.name, "backup")
	testing.expect_value(t, len(cmd.args), 1)
	testing.expect_value(t, cmd.args[0], "/project/.env")
}

@(test)
test_parse_args_config_file_long_flag :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args(
		[]string{"envr", "sync", "--config-file", "x.json"},
	)
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.config_file, "x.json")
}

@(test)
test_parse_args_config_file_short_flag :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "sync", "-c", "x.json"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.config_file, "x.json")
}

@(test)
test_parse_args_force_long_flag :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "init", "--force"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.force, true)
}

@(test)
test_parse_args_force_short_flag :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "init", "-f"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.force, true)
}

@(test)
test_parse_args_multiple_positionals :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "backup", "a", "b"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, len(cmd.args), 2)
	testing.expect_value(t, cmd.args[0], "a")
	testing.expect_value(t, cmd.args[1], "b")
}

@(test)
test_parse_args_mixed_flags_and_positionals :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "backup", "/project/.env", "--force"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.force, true)
	testing.expect_value(t, len(cmd.args), 1)
	testing.expect_value(t, cmd.args[0], "/project/.env")
}

@(test)
test_parse_args_no_args :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr"})
	defer delete_command(&cmd)
	testing.expect(t, !ok, "no args should return false")
}

@(test)
test_parse_args_flag_then_positional_then_flag :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "backup", "--force", "a.env", "--output", "json"})
	defer delete_command(&cmd)
	testing.expect(t, ok, "should succeed")

	testing.expect_value(t, cmd.flags.force, true)
	testing.expect_value(t, cmd.flags.output, Output_Format.JSON)
	testing.expect_value(t, len(cmd.args), 1)
	testing.expect_value(t, cmd.args[0], "a.env")
}

@(test)
test_parse_args_config_file_default :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect(t, len(cmd.flags.config_file) > 0, "config_file should default to non-empty path")
	testing.expect(
		t,
		strings.contains(cmd.flags.config_file, ".envr"),
		"default config_file should contain .envr dir, got %s",
	)
}

@(test)
test_parse_args_output_long_json :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list", "--output", "json"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.output, Output_Format.JSON)
}

@(test)
test_parse_args_output_short_json :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list", "-o", "json"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.output, Output_Format.JSON)
}

@(test)
test_parse_args_output_long_table :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list", "--output", "table"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.output, Output_Format.Table)
}

@(test)
test_parse_args_output_short_table :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list", "-o", "table"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.output, Output_Format.Table)
}

@(test)
test_parse_args_output_equals_syntax :: proc(t: ^testing.T) {
	cmd, ok, _, _ := test_parse_args([]string{"envr", "list", "--output=json"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect_value(t, cmd.flags.output, Output_Format.JSON)
}
