package main

import "core:path/filepath"
import "core:testing"

@(test)
test_filepath_base_equals_rel :: proc(t: ^testing.T) {
	cases := []string{
		"/home/user/.env",
		"/home/user/project/.envrc",
		"/tmp/foo",
		"/a/b/c/d.txt",
	}

	for path in cases {
		dir := filepath.dir(path)
		rel, rel_err := filepath.rel(dir, path)
		testing.expect(t, rel_err == nil, "filepath.rel returned an error")
		base := filepath.base(path)
		testing.expect(
			t,
			rel == base,
			"filepath.rel(dir, path) should equal filepath.base(path)",
		)
	}
}
