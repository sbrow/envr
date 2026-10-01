#+test
package main

import "core:strings"
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
	_, _, ok = parse_remote_path("user@example.com:relative.env")
	testing.expect(t, !ok, "remote path must be absolute")
}

@(test)
test_quote_remote_shell_path :: proc(t: ^testing.T) {
	testing.expect_value(t, quote_remote_shell_path("/srv/app/.env"), "/srv/app/.env")
	testing.expect_value(t, quote_remote_shell_path("/srv/app/a'b.env"), "/srv/app/a'\"'\"'b.env")
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
