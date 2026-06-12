package main

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_usage_text_contains_all_commands :: proc(t: ^testing.T) {
	text := usage_text()

	for c in COMMANDS {
		testing.expect(
			t,
			strings.contains(text, c.name),
			fmt.aprintf("usage_text missing command %q", c.name),
		)
		for a in c.aliases {
			testing.expect(
				t,
				strings.contains(text, a),
				fmt.aprintf("usage_text missing alias %q", a),
			)
		}
	}
}

@(test)
test_usage_text_contains_steps :: proc(t: ^testing.T) {
	text := usage_text()

	testing.expect(t, strings.contains(text, "1."), "missing step 1")
	testing.expect(t, strings.contains(text, "2."), "missing step 2")
	testing.expect(t, strings.contains(text, "3."), "missing step 3")
	testing.expect(t, strings.contains(text, "4."), "missing step 4")
	testing.expect(t, strings.contains(text, "5."), "missing step 5")
	testing.expect(t, strings.contains(text, "> envr sync\n"), "step 4 missing 'envr sync'")
	testing.expect(
		t,
		strings.contains(text, "> envr restore"),
		"step 5 missing 'envr restore'",
	)
}

@(test)
test_usage_text_contains_flags_and_help_hint :: proc(t: ^testing.T) {
	text := usage_text()

	testing.expect(t, strings.contains(text, "Flags:"), "missing Flags section")
	testing.expect(t, strings.contains(text, "--help"), "missing --help flag")
	testing.expect(
		t,
		strings.contains(text, "Use \"envr [command] --help\""),
		"missing help hint",
	)
}

@(test)
test_command_help_backup :: proc(t: ^testing.T) {
	text, ok := command_help_text("backup")
	testing.expect(t, ok, "command_help_text(\"backup\") returned false")

	testing.expect(t, strings.contains(text, "Usage:"), "missing Usage line")
	testing.expect(
		t,
		strings.contains(text, "envr backup <path>"),
		"missing usage pattern",
	)
	testing.expect(
		t,
		strings.contains(text, "Aliases:"),
		"missing Aliases section",
	)
	testing.expect(t, strings.contains(text, "add"), "missing 'add' alias")
	testing.expect(t, strings.contains(text, "Flags:"), "missing Flags section")
	testing.expect(
		t,
		strings.contains(text, "--help"),
		"missing --help in flags",
	)
}

@(test)
test_command_help_add_alias :: proc(t: ^testing.T) {
	text, ok := command_help_text("add")
	testing.expect(t, ok, "command_help_text(\"add\") returned false")
	testing.expect(
		t,
		strings.contains(text, "envr backup <path>"),
		"'add' alias should resolve to backup usage",
	)
	testing.expect(t, strings.contains(text, "Aliases:"), "missing Aliases section")
}

@(test)
test_command_help_init_no_aliases :: proc(t: ^testing.T) {
	text, ok := command_help_text("init")
	testing.expect(t, ok, "command_help_text(\"init\") returned false")

	testing.expect(t, strings.contains(text, "Usage:"), "missing Usage line")
	testing.expect(
		t,
		!strings.contains(text, "Aliases:"),
		"init should not have Aliases section",
	)
	testing.expect(t, strings.contains(text, "Flags:"), "missing Flags section")
	testing.expect(
		t,
		strings.contains(text, "help for init"),
		"missing 'help for init'",
	)
}

@(test)
test_command_help_unknown :: proc(t: ^testing.T) {
	text, ok := command_help_text("nonexistent")
	testing.expect(t, !ok, "command_help_text(\"nonexistent\") should return false")
	testing.expect(t, len(text) == 0, "text should be empty for unknown command")
}

@(test)
test_command_help_version :: proc(t: ^testing.T) {
	text, ok := command_help_text("version")
	testing.expect(t, ok, "command_help_text(\"version\") returned false")
	testing.expect(t, strings.contains(text, "Usage:"), "missing Usage line")
	testing.expect(
		t,
		!strings.contains(text, "Aliases:"),
		"version should not have Aliases section",
	)
}
