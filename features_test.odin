package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_find_binary_exists :: proc(t: ^testing.T) {
	path := os.get_env("PATH", context.allocator)
	paths := strings.split(path, ":")

	result := find_binary(paths, "sh")
	testing.expect(t, result != "", "sh should be found on PATH")
}

@(test)
test_find_binary_not_exists :: proc(t: ^testing.T) {
	old_path := os.get_env("PATH", context.allocator)
	defer {
		if old_path != "" {
			os.set_env("PATH", old_path)
		}
	}

	os.set_env("PATH", "/tmp/envr-nope")

	path := os.get_env("PATH", context.allocator)
	paths := strings.split(path, ":")


	result := find_binary(paths, "no_such_binary_xyz")
	testing.expect(t, result == "", "nonexistent binary should not be found")
}

