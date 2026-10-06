package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:terminal"

cmd_view :: proc(cmd: ^Command) -> bool {
	if len(cmd.args) > 1 {
		print_command_help(cmd)
		return false
	}

	path := len(cmd.args) == 1 ? cmd.args[0] : ""

	db := db_open(cmd.flags.config_file) or_return
	defer db_close(&db)

	files := db_list(&db) or_return
	paths := make([]string, len(files), context.temp_allocator)
	for file, i in files do paths[i] = file.path
	resolved_path := choose_view_path(path, paths, cmd.err) or_return

	file := db_fetch(&db, resolved_path) or_return

	if cmd.flags.stdout || !terminal.is_terminal(os.stdout) {
		fmt.wprintf(cmd.out, "%s", file.contents, flush = false)
		return true
	}

	page_file_contents(file.contents, cmd.err)
	return true
}

choose_view_path :: proc(path: string, paths: []string, err_out: io.Writer) -> (string, bool) {
	if len(strings.trim_space(path)) > 0 {
		resolved, _, _, is_remote, path_ok := normalize_remote_identity(path)
		if is_remote && !path_ok do return "", false
		if !is_remote {
			abs_path, abs_err := filepath.abs(path, context.temp_allocator)
			if abs_err == nil do resolved = abs_path
		}
		for stored in paths {
			if stored == resolved do return stored, true
		}
		if number, number_ok := strconv.parse_int(path, 10);
		   number_ok && number > 0 && number <= len(paths) {
			return paths[number - 1], true
		}
	}

	matches := matching_view_paths(path, paths)
	if len(matches) == 0 {
		fmt.wprintf(err_out, "No backed-up file matches: %s\n", path, flush = false)
		return "", false
	}
	if len(path) > 0 && len(matches) == 1 {
		return matches[0], true
	}
	if !terminal.is_terminal(os.stdin) || !terminal.is_terminal(os.stderr) {
		fmt.wprintln(
			err_out,
			"An interactive terminal is required to choose a backup; pass a more specific path.",
			flush = false,
		)
		return "", false
	}
	selected := single_select("Select a backed-up file:", matches[:])
	if selected < 0 {
		return "", false
	}
	return matches[selected], true
}

matching_view_paths :: proc(path: string, paths: []string) -> [dynamic]string {
	matches := make([dynamic]string, 0, len(paths), context.temp_allocator)
	needle := strings.to_lower(path, context.temp_allocator)
	for stored in paths {
		if strings.contains(strings.to_lower(stored, context.temp_allocator), needle) {
			append(&matches, stored)
		}
	}
	return matches
}

page_file_contents :: proc(contents: string, err_out: io.Writer) {
	pager := os.get_env("PAGER", context.temp_allocator)
	if len(strings.trim_space(pager)) == 0 {
		when ODIN_OS == .Windows {
			pager = "more"
		} else {
			pager = "less"
		}
	}

	parts := strings.split(strings.trim_space(pager), " ", context.temp_allocator)
	command := make([dynamic]string, 0, len(parts) + 1, context.temp_allocator)
	for part in parts {
		if len(part) > 0 {
			append(&command, part)
		}
	}
	if len(command) == 0 {
		append(&command, "less")
	}
	when ODIN_OS == .Windows {
		if command[0] != "more" do append(&command, "-")
	} else {
		append(&command, "-")
	}

	read_end, write_end, pipe_err := os.pipe()
	if pipe_err != nil {
		fmt.wprintf(err_out, "Error creating pager pipe: %v\n", pipe_err, flush = false)
		return
	}
	defer os.close(write_end)

	desc := os.Process_Desc {
		command = command[:],
		stdin   = read_end,
		stdout  = os.stdout,
		stderr  = os.stderr,
	}
	process, start_err := os.process_start(desc)
	os.close(read_end)
	if start_err != nil {
		fmt.wprintf(err_out, "Error starting pager %q: %v\n", command[0], start_err, flush = false)
		return
	}

	remaining := transmute([]u8)contents
	write_err: os.Error
	for len(remaining) > 0 {
		written, err := os.write(write_end, remaining)
		if err != nil {
			write_err = err
			break
		}
		if written == 0 do break
		remaining = remaining[written:]
	}
	os.close(write_end)
	state, wait_err := os.process_wait(process)
	if write_err != nil {
		fmt.wprintf(err_out, "Error writing to pager: %v\n", write_err, flush = false)
	}
	if wait_err != nil {
		fmt.wprintf(err_out, "Error waiting for pager: %v\n", wait_err, flush = false)
	} else if state.exit_code != 0 {
		fmt.wprintf(err_out, "Pager exited with status %d\n", state.exit_code, flush = false)
	}
}

