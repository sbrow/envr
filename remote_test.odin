#+test
package main

import "core:strings"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"

@(test)
test_parse_remote_path :: proc(t: ^testing.T) {
	host, path, ok := parse_remote_path("spencer@example.com:/srv/app/.env")
	testing.expect(t, ok, "expected remote identity to be recognized")
	testing.expect_value(t, host, "spencer@example.com")
	testing.expect_value(t, path, "/srv/app/.env")
}

@(test)
test_parse_remote_path_rejects_local_paths :: proc(t: ^testing.T) {
	_, _, ok := parse_remote_path("/srv/app/.env")
	testing.expect(t, !ok, "local path should not be treated as remote")
	_, _, ok = parse_remote_path("user@example.com:")
	testing.expect(t, !ok, "remote path must not be empty")
}

@(test)
test_expand_remote_path_to_absolute_posix_path :: proc(t: ^testing.T) {
	cases := [?][2]string{
		{"outline/docker.env", "/root/outline/docker.env"},
		{"~/outline/docker.env", "/root/outline/docker.env"},
		{"~outline/docker.env", "/root/outline/docker.env"},
		{"/root/outline/docker.env", "/root/outline/docker.env"},
		{"../outside.env", "/outside.env"},
	}
	for c in cases {
		got := expand_remote_path("/root", c[0])
		testing.expect_value(t, got, c[1])
	}
}

@(test)
test_normalize_remote_absolute_identity :: proc(t: ^testing.T) {
	identity, host, path, is_remote, ok := normalize_remote_identity(
		"root@vertaxdev.com:/root/outline/docker.env",
	)
	testing.expect(t, is_remote && ok, "absolute remote identity should normalize without SSH")
	testing.expect_value(t, identity, "root@vertaxdev.com:/root/outline/docker.env")
	testing.expect_value(t, host, "root@vertaxdev.com")
	testing.expect_value(t, path, "/root/outline/docker.env")
}

@(test)
test_quote_remote_shell_path :: proc(t: ^testing.T) {
	testing.expect_value(t, quote_remote_shell_path("/srv/app/.env"), "/srv/app/.env")
	testing.expect_value(t, quote_remote_shell_path("/srv/app/a'b.env"), "/srv/app/a'\"'\"'b.env")
}

@(test)
test_quote_remote_shell_path_round_trips_without_injection :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		return
	}

	base := test_temp_dir(t, "envr-shell-quote-*")
	defer os.remove_all(base)
	marker, _ := filepath.join({base, "injected"}, context.temp_allocator)
	quoted_marker := quote_remote_shell_path(marker)

	paths := make([dynamic]string, 0, 10, context.temp_allocator)
	append(&paths,
		"",
		"plain-name_123./:+@%-=,",
		"spaces and\ttabs",
		"single'quote and \"double quote\"",
		"two''consecutive'''quotes",
		fmt.tprintf("; touch '%s'; #", marker),
		fmt.tprintf("$(touch '%s')", marker),
		fmt.tprintf("`touch '%s'`", marker),
		"&& || | < > ( ) $ ! * ? [ ] # ~ % { } \\",
		"line one\nline two",
	)

	for path in paths {
		if os.exists(marker) {
			_ = os.remove(marker)
		}
		quoted_path := quote_remote_shell_path(path)
		script := fmt.tprintf(
			"printf '%%s' '%s'; if [ -e '%s' ]; then printf INJECTED; fi",
			quoted_path,
			quoted_marker,
		)
		desc := os.Process_Desc {
			command = []string{"/bin/sh", "-c", script},
		}
		state, stdout, stderr, err := os.process_exec(desc, context.allocator)
		delete(stdout)
		delete(stderr)
		testing.expectf(t, err == nil, "shell execution failed for %q: %v", path, err)
		if err != nil {
			return
		}
		testing.expectf(t, state.success, "shell failed for %q", path)
		testing.expect_value(t, string(stdout), path)
		testing.expectf(t, !os.exists(marker), "path %q executed the marker command", path)
	}
}

@(test)
test_new_remote_env_file_owns_its_fields :: proc(t: ^testing.T) {
	input_path := strings.clone("spencer@example.com:/etc/umami.env", context.allocator)
	contents := make([]u8, len("SECRET=value"), context.allocator)
	copy(contents, "SECRET=value")

	file := new_remote_env_file(input_path, contents)
	delete(input_path)
	defer delete_envfile(&file)

	testing.expect_value(t, file.path, "spencer@example.com:/etc/umami.env")
	testing.expect_value(t, file.contents, "SECRET=value")
}
