#+test
package main

import "core:path/filepath"
import "core:testing"

@(test)
test_filepath_base_equals_rel :: proc(t: ^testing.T) {
	cases := []string{"/home/user/.env", "/home/user/project/.envrc", "/tmp/foo", "/a/b/c/d.txt"}

	for path in cases {
		dir := filepath.dir(path)
		rel, rel_err := filepath.rel(dir, path, context.temp_allocator)
		testing.expect_value(t, rel_err, nil)
		base := filepath.base(path)
		testing.expect_value(t, rel, base)
	}
}

