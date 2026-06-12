package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"

fd_counter: sync.Atomic_Mutex
fd_seq: int

next_fd_tmp_path :: proc() -> string {
	sync.atomic_mutex_lock(&fd_counter)
	n := fd_seq
	fd_seq += 1
	sync.atomic_mutex_unlock(&fd_counter)
	return fmt.aprintf("/tmp/envr-fd-%d-%d", os.get_pid(), n)
}

build_fd_args :: proc(search_path: string, cfg: Config, include_ignored: bool) -> []string {
	args := make([dynamic]string, 0, 3 + 2 * len(cfg.ScanConfig.Exclude) + 2)
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

run_fd :: proc(args: []string) -> (lines: [dynamic]string, ok: bool) {
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

	data, read_err := os.read_entire_file_from_path(tmp_path, context.allocator)
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

	raw_lines := strings.split(output, "\n")
	for line in raw_lines {
		trimmed, _ := strings.clone(strings.trim_space(line))
		if len(trimmed) > 0 {
			append(&lines, trimmed)
		}
	}

	ok = true
	return
}

scan_path :: proc(search_path: string, cfg: Config) -> (paths: [dynamic]string, ok: bool) {
	if is_tty() {
		fmt.printf("Searching for all files in \"%s\"...\n", search_path)
	}
	all_args := build_fd_args(search_path, cfg, true)
	all_files, all_ok := run_fd(all_args)
	if !all_ok {
		return
	}

	if is_tty() {
		fmt.printf("Search for unignored fies in \"%s\"...\n", search_path)
	}
	unignored_args := build_fd_args(search_path, cfg, false)
	unignored_files, unignored_ok := run_fd(unignored_args)
	if !unignored_ok {
		return
	}

	unignored_set: map[string]bool
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

can_scan :: proc() -> bool {
	feats := check_features()
	return has_feature(feats, .Fd)
}

find_unbacked :: proc(local_files: []string, db_files: []EnvFile) -> [dynamic]string {
	backed_set: map[string]bool
	for file in db_files {
		backed_set[file.Path] = true
	}

	unbacked: [dynamic]string
	for file in local_files {
		if !(file in backed_set) {
			append(&unbacked, file)
		}
	}
	return unbacked
}

