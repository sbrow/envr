package main

import "core:os"

import "findr"

// Caller is responsible for freeing paths
scan_path :: proc(search_path: string, cfg: Config) -> (paths: [dynamic]string, ok: bool) {
	opts := findr.WalkOptions {
		pattern  = cfg.ScanConfig.Matcher,
		excludes = cfg.ScanConfig.Exclude[:],
	}
	findr.walk({search_path}, &paths, opts, os.get_processor_core_count())
	ok = true
	return
}

find_unbacked :: proc(local_files: []string, db_files: []EnvFile) -> []string {
	backed_set := make(map[string]bool, len(db_files), context.temp_allocator)
	for file in db_files {
		backed_set[file.Path] = true
	}

	unbacked := make([dynamic]string, 0, len(db_files) / 2, context.temp_allocator)
	for file in local_files {
		if !(file in backed_set) {
			append(&unbacked, file)
		}
	}
	return unbacked[:]
}
