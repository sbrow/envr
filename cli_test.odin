#+feature dynamic-literals

package main

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
	testing.expect(t, strings.contains(text, "Use \"envr [command] --help\""), "missing help hint")
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
	testing.expect(t, strings.contains(text, "help for init"), "missing 'help for init'")
}

@(test)
test_command_help_unknown :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	ok := write_command_help("nonexistent", strings.to_writer(&b))
	testing.expect(t, !ok, "write_command_help(\"nonexistent\") should return false")

	text := strings.to_string(b)
	testing.expect(t, len(text) == 0, "text should be empty for unknown command")
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

@(test)
test_has_flag_bool_set :: proc(t: ^testing.T) {
	cmd := Command {
		name = "test",
		bool_set = map[string]bool{"force" = true},
	}
	defer delete(cmd.bool_set)

	testing.expect(t, has_flag(&cmd, "force"), "should find flag in bool_set")
	testing.expect(t, !has_flag(&cmd, "verbose"), "should not find missing flag")
}

@(test)
test_has_flag_value_map :: proc(t: ^testing.T) {
	cmd := Command {
		name = "test",
		flags = map[string]string{"output" = "/tmp/out"},
	}
	defer delete(cmd.flags)

	testing.expect(t, has_flag(&cmd, "output"), "should find flag in flags map")
	testing.expect(t, !has_flag(&cmd, "force"), "should not find missing flag")
}

@(test)
test_has_flag_both_maps :: proc(t: ^testing.T) {
	cmd := Command {
		name = "test",
		flags = map[string]string{"output" = "/tmp/out"},
		bool_set = map[string]bool{"force" = true},
	}
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, has_flag(&cmd, "output"), "should find in flags")
	testing.expect(t, has_flag(&cmd, "force"), "should find in bool_set")
	testing.expect(t, !has_flag(&cmd, "verbose"), "should not find missing flag")
}

@(test)
test_has_flag_empty_command :: proc(t: ^testing.T) {
	cmd := Command {
		name = "test",
	}
	testing.expect(t, !has_flag(&cmd, "anything"), "empty command should have no flags")
}

@(test)
test_parse_args_bare_command :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "list"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.name == "list", "name should be list")
	testing.expect(t, len(cmd.args) == 0, "should have no positional args")
	testing.expect(t, len(cmd.flags) == 0, "should have no flags")
	testing.expect(t, len(cmd.bool_set) == 0, "should have no bool flags")
}

@(test)
test_parse_args_positional :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "backup", "/project/.env"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.name == "backup")
	testing.expect(t, len(cmd.args) == 1)
	testing.expect(t, cmd.args[0] == "/project/.env")
}

@(test)
test_parse_args_long_flag_with_value :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "sync", "--config", "x.json"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.flags["config"] == "x.json")
}

@(test)
test_parse_args_short_flag_with_value :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "sync", "-c", "x.json"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.flags["c"] == "x.json")
}

@(test)
test_parse_args_long_bool_flag :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "init", "--force"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.bool_set["force"] == true)
}

@(test)
test_parse_args_short_bool_flag :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "version", "-l"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.bool_set["l"] == true)
}

@(test)
test_parse_args_multiple_positionals :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "backup", "a", "b"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, len(cmd.args) == 2)
	testing.expect(t, cmd.args[0] == "a")
	testing.expect(t, cmd.args[1] == "b")
}

@(test)
test_parse_args_mixed_flags_and_positionals :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "backup", "/project/.env", "--force"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.bool_set["force"] == true)
	testing.expect(t, len(cmd.args) == 1)
	testing.expect(t, cmd.args[0] == "/project/.env")
}

@(test)
test_parse_args_no_args :: proc(t: ^testing.T) {
	_, ok := parse_args([]string{"envr"})
	testing.expect(t, !ok, "no args should return false")
}

@(test)
test_parse_args_flag_then_positional_then_flag :: proc(t: ^testing.T) {
	cmd, ok := parse_args([]string{"envr", "backup", "a.env", "--force", "--verbose"})
	testing.expect(t, ok, "should succeed")
	if !ok do return
	defer delete(cmd.args)
	defer delete(cmd.flags)
	defer delete(cmd.bool_set)

	testing.expect(t, cmd.bool_set["force"] == true)
	testing.expect(t, cmd.bool_set["verbose"] == true)
	testing.expect(t, len(cmd.args) == 1)
	testing.expect(t, cmd.args[0] == "a.env")
}

