package main

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:terminal"

cmd_uninstall :: proc(cmd: ^Command) {
	envr_d := envr_dir(cmd.flags.config_file)

	if !os.exists(envr_d) {
		fmt.wprintln(cmd.out, "Nothing to remove.", flush = false)
		return
	}

	entries, err := os.read_all_directory_by_path(envr_d, context.temp_allocator)
	if err != nil {
		fmt.wprintf(cmd.err, "Error reading %s: %v\n", envr_d, err, flush = false)
		return
	}

	paths := make([]string, len(entries), context.temp_allocator)
	for entry, i in entries {
		paths[i], _ = filepath.join([]string{envr_d, entry.name}, context.temp_allocator)
	}

	fmt.wprintln(cmd.out, "This will remove:", flush = false)
	for path in paths {
		fmt.wprintf(cmd.out, "  %s\n", path, flush = false)
	}
	fmt.wprintf(cmd.out, "  %s\n", envr_d, flush = false)

	if !cmd.flags.force {
		if !terminal.is_terminal(os.stdin) {
			fmt.wprintln(cmd.err, "Run with --force to skip confirmation.", flush = false)
			return
		}

		fmt.wprintf(cmd.out, "\nAre you sure? [y/N] ", flush = false)
		bufio.writer_flush(cmd.out_buf)

		buf: [128]u8
		n, _ := os.read(os.stdin, buf[:])
		response := strings.trim_space(string(buf[:n]))

		if response != "y" && response != "Y" {
			fmt.wprintln(cmd.out, "Aborted.", flush = false)
			return
		}
	}

	remove_err := os.remove_all(envr_d)
	if remove_err != nil {
		fmt.wprintf(cmd.err, "Error removing %s: %v\n", envr_d, remove_err, flush = false)
		return
	}

	for path in paths {
		fmt.wprintf(cmd.out, "Removed %s\n", path, flush = false)
	}
	fmt.wprintf(cmd.out, "Removed %s\n", envr_d, flush = false)
}
