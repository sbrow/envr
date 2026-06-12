package main

import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"

Feature :: enum {
	Git,
	Fd,
}

AvailableFeatures :: bit_set[Feature]

check_features :: proc() -> AvailableFeatures {
	feats: AvailableFeatures

	s: mem.Scratch
	mem.scratch_init(&s, 4 * mem.DEFAULT_PAGE_SIZE)
	defer mem.scratch_destroy(&s)

	context.temp_allocator = mem.scratch_allocator(&s)

	path_env := os.get_env("PATH", context.temp_allocator)
	paths := strings.split(path_env, ":", context.temp_allocator)

	if find_binary(paths, "git") != "" {
		feats += {.Git}
	}
	if find_binary(paths, "fd") != "" {
		feats += {.Fd}
	}

	return feats
}

find_binary :: proc(
	paths: []string,
	name: string,
	allocator: runtime.Allocator = context.temp_allocator,
) -> string {
	for p in paths {
		candidate := strings.join({strings.trim_right(p, "/"), name}, "/", allocator)
		_, err := os.stat(candidate, allocator)
		if err == nil {
			return candidate
		}
	}
	return ""
}

