package main

import "core:fmt"
import "core:testing"

@(test)
test_find_unbacked_finds_missing :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env", "/c/.env"}
	db := []EnvFile{{Path = "/a/.env"}, {Path = "/b/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect(t, len(result) == 1, fmt.aprintf("expected 1 unbacked, got %d", len(result)))
	if len(result) > 0 {
		testing.expect(
			t,
			result[0] == "/c/.env",
			fmt.aprintf("expected /c/.env, got %s", result[0]),
		)
	}
}

@(test)
test_find_unbacked_all_backed :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env"}
	db := []EnvFile{{Path = "/a/.env"}, {Path = "/b/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect(t, len(result) == 0, fmt.aprintf("expected 0 unbacked, got %d", len(result)))
}

@(test)
test_find_unbacked_no_local :: proc(t: ^testing.T) {
	local: []string
	db := []EnvFile{{Path = "/a/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect(t, len(result) == 0, fmt.aprintf("expected 0 unbacked, got %d", len(result)))
}

@(test)
test_find_unbacked_none_backed :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env"}
	db: []EnvFile

	result := find_unbacked(local, db[:])
	testing.expect(t, len(result) == 2, fmt.aprintf("expected 2 unbacked, got %d", len(result)))
}

