package main

import "core:os"
import "core:strings"

Feature :: enum {
	Git,
	Fd,
	Age,
}

AvailableFeatures :: bit_set[Feature]

check_features :: proc() -> AvailableFeatures {
	feats: AvailableFeatures

	if find_binary("git") != "" {
		feats += {.Git}
	}
	if find_binary("fd") != "" {
		feats += {.Fd}
	}
	if find_binary("age") != "" {
		feats += {.Age}
	}

	return feats
}

find_binary :: proc(name: string) -> string {
	path_env := os.get_env("PATH", context.allocator)
	paths := strings.split(path_env, ":")
	for p in paths {
		candidate := strings.join({strings.trim_right(p, "/"), name}, "/")
		_, err := os.stat(candidate, context.allocator)
		if err == nil {
			return candidate
		}
	}
	return ""
}

has_feature :: proc(feats: AvailableFeatures, f: Feature) -> bool {
	return f in feats
}
