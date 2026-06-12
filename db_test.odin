package main

import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_dir_slice_owns_parent :: proc(t: ^testing.T) {
	abs_path := "/home/user/project/.env"
	cloned_path, _ := strings.clone(abs_path)

	dir := filepath.dir(cloned_path)

	testing.expect(t, dir == "/home/user/project", "filepath.dir should return parent directory")
	testing.expect(t, len(dir) > 0, "dir should not be empty")

	cloned_dir, _ := strings.clone(dir)
	testing.expect(t, cloned_dir == dir, "clone of dir should equal dir")
}
