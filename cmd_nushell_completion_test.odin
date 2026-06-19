#+test
package main

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_nushell_completion_nonempty :: proc(t: ^testing.T) {
	testing.expect(t, len(COMPLETION_SCRIPT) > 0, "completion script should not be empty")
}

@(test)
test_nushell_completion_contains_externs :: proc(t: ^testing.T) {
	expected := []string{
		"tracked-paths",
		"untracked-paths",
		"envr backup",
		"envr check",
		"envr edit-config",
		"envr help",
		"envr init",
		"envr list",
		"envr remove",
		"envr restore",
		"envr scan",
		"envr sync",
		"envr nushell-completion",
	}
	for ext in expected {
		testing.expect(
			t,
			strings.contains(COMPLETION_SCRIPT, ext),
			fmt.tprintf("expected script to contain %q", ext),
		)
	}
}
