#+test
package main

import "core:testing"

@(test)
test_find_unbacked_finds_missing :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env", "/c/.env"}
	db := []EnvFile{{path = "/a/.env"}, {path = "/b/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 1)
	if len(result) > 0 {
		testing.expect_value(t, result[0], "/c/.env")
	}
}

@(test)
test_find_unbacked_all_backed :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env"}
	db := []EnvFile{{path = "/a/.env"}, {path = "/b/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 0)
}

@(test)
test_find_unbacked_no_local :: proc(t: ^testing.T) {
	local: []string
	db := []EnvFile{{path = "/a/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 0)
}

@(test)
test_find_unbacked_none_backed :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env"}
	db: []EnvFile

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 2)
}

