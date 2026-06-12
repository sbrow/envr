package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:terminal"

fd_counter: sync.Atomic_Mutex
fd_seq: int

// Caller is responsible for freeing paths
scan_path :: proc(search_path: string, cfg: Config) -> (paths: [dynamic]string, ok: bool) {
	if terminal.is_terminal(os.stdout) {
		fmt.printf("Searching for all files in \"%s\"...\n", search_path)
	}
	all_files, all_ok := run_fd(build_fd_args(search_path, cfg, true))
	if !all_ok {
		return
	}

	if terminal.is_terminal(os.stdout) {
		fmt.printf("Search for unignored fies in \"%s\"...\n", search_path)
	}
	unignored_files, unignored_ok := run_fd(build_fd_args(search_path, cfg, false))
	if !unignored_ok {
		return
	}

	unignored_set := make(map[string]bool, len(unignored_files), context.temp_allocator)
	for file in unignored_files {
		unignored_set[file] = true
	}

	for file in all_files {
		if !(file in unignored_set) {
			append(&paths, file)
		}
	}

	ok = true
	return
}

@(private = "file")
build_fd_args :: proc(search_path: string, cfg: Config, include_ignored: bool) -> []string {
	args_len := 3 + 2 * len(cfg.ScanConfig.Exclude) + 2
	args := make([dynamic]string, 0, args_len, context.temp_allocator)
	append(&args, "fd")
	append(&args, "-a")
	append(&args, cfg.ScanConfig.Matcher)

	for exclude in cfg.ScanConfig.Exclude {
		append(&args, "-E")
		append(&args, exclude)
	}

	if include_ignored {
		append(&args, "-HI")
	} else {
		append(&args, "-H")
	}

	append(&args, search_path)
	return args[:]
}

run_fd :: proc(args: []string) -> (lines: []string, ok: bool) {
	tmp_path := next_fd_tmp_path()
	tmp_file, tmp_err := os.open(tmp_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
	if tmp_err != nil {
		return
	}

	desc := os.Process_Desc {
		command = args,
		stdout  = tmp_file,
		stderr  = nil,
	}

	p, start_err := os.process_start(desc)
	os.close(tmp_file)
	if start_err != nil {
		os.remove(tmp_path)
		return
	}

	state, wait_err := os.process_wait(p)
	if wait_err != nil || state.exit_code != 0 {
		os.remove(tmp_path)
		return
	}

	data, read_err := os.read_entire_file_from_path(tmp_path, context.temp_allocator)
	os.remove(tmp_path)
	if read_err != nil {
		return
	}

	output := string(data)
	output = strings.trim_space(output)
	if len(output) == 0 {
		ok = true
		return
	}

	raw_lines := strings.split(output, "\n", context.temp_allocator)
	result := make([dynamic]string, 0, len(raw_lines), context.temp_allocator)
	for line in raw_lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) > 0 {
			append(&result, trimmed)
		}
	}

	return result[:], true
}

@(private = "file")
next_fd_tmp_path :: proc() -> string {
	sync.atomic_mutex_lock(&fd_counter)
	n := fd_seq
	fd_seq += 1
	sync.atomic_mutex_unlock(&fd_counter)
	return fmt.tprintf("/tmp/envr-fd-%d-%d", os.get_pid(), n)
}

cant_scan :: proc(feats: AvailableFeatures) -> bool {
	return Feature.Fd not_in feats
}

find_unbacked :: proc(local_files: []string, db_files: []EnvFile) -> []string {
	// Lives until the end of the function
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

