#+test
package main

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_nushell_completion_nonempty :: proc(t: ^testing.T) {
	script := generate_nushell_completion()
	testing.expect(t, len(script) > 0, "completion script should not be empty")
}

@(test)
test_nushell_completion_contains_commands :: proc(t: ^testing.T) {
	script := generate_nushell_completion()
	expected := []string{
		"tracked-paths",
		"untracked-paths",
		"envr backup",
		"envr check",
		"envr edit-config",
		"envr init",
		"envr list",
		"envr remove",
		"envr restore",
		"envr scan",
		"envr sync",
		"envr version",
		"envr completion",
	}
	for ext in expected {
		testing.expect(
			t,
			strings.contains(script, ext),
			fmt.tprintf("expected script to contain %q", ext),
		)
	}
}

@(test)
test_nushell_completion_contains_flags :: proc(t: ^testing.T) {
	script := generate_nushell_completion()
	expected_flags := []string{
		"--help(-h)",
		"--config-file(-c)",
		"--color",
		"--force(-f)",
		"--output(-o)",
	}
	for flag in expected_flags {
		testing.expect(
			t,
			strings.contains(script, flag),
			fmt.tprintf("expected script to contain %q", flag),
		)
	}
}

@(test)
test_nushell_completion_contains_aliases :: proc(t: ^testing.T) {
	script := generate_nushell_completion()
	testing.expect(
		t,
		strings.contains(script, "envr add"),
		"expected script to contain 'envr add' alias",
	)
}

@(test)
test_nushell_completion_no_help_command :: proc(t: ^testing.T) {
	script := generate_nushell_completion()
	testing.expect(
		t,
		!strings.contains(script, "envr help"),
		"script should not contain 'envr help' (not a real command)",
	)
}

@(test)
test_bash_completion_nonempty :: proc(t: ^testing.T) {
	script := generate_bash_completion()
	testing.expect(t, len(script) > 0, "bash completion script should not be empty")
}

@(test)
test_bash_completion_contains_registration :: proc(t: ^testing.T) {
	script := generate_bash_completion()
	testing.expect(
		t,
		strings.contains(script, "complete -F _envr envr"),
		"expected bash script to register completion function",
	)
}

@(test)
test_bash_completion_contains_commands :: proc(t: ^testing.T) {
	script := generate_bash_completion()
	expected := []string{
		"init", "scan", "sync", "backup", "add",
		"restore", "list", "remove", "check",
		"version", "edit-config", "completion",
	}
	for cmd in expected {
		testing.expect(
			t,
			strings.contains(script, cmd),
			fmt.tprintf("expected bash script to contain %q", cmd),
		)
	}
}

@(test)
test_bash_completion_contains_flags :: proc(t: ^testing.T) {
	script := generate_bash_completion()
	expected := []string{
		"--help", "--config-file", "--color", "--force", "--output",
	}
	for flag in expected {
		testing.expect(
			t,
			strings.contains(script, flag),
			fmt.tprintf("expected bash script to contain %q", flag),
		)
	}
}

@(test)
test_bash_completion_contains_enum_values :: proc(t: ^testing.T) {
	script := generate_bash_completion()
	testing.expect(t, strings.contains(script, "auto table json"), "missing output enum values")
	testing.expect(t, strings.contains(script, "auto always never"), "missing color enum values")
}
