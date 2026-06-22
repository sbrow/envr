package main

import "core:fmt"
import "core:os"

cmd_edit_config :: proc(cmd: ^Command) {
	editor := os.get_env("EDITOR", context.allocator)
	if len(editor) == 0 {
		fmt.wprintln(cmd.err, "Error: $EDITOR environment variable is not set", flush = false)
		return
	}

	config_path := cmd.config_path

	if !os.exists(config_path) {
		fmt.wprintf(
			cmd.err,
			"Config file does not exist at %s. Run 'envr init' first.\n",
			config_path,
			flush = false,
		)
		return
	}

	args := []string{editor, config_path}
	desc := os.Process_Desc {
		command = args,
		stdin   = os.stdin,
		stdout  = os.stdout,
		stderr  = os.stderr,
	}

	p, start_err := os.process_start(desc)
	if start_err != nil {
		fmt.wprintf(cmd.err, "Error running editor: %v\n", start_err, flush = false)
		return
	}

	state, wait_err := os.process_wait(p)
	if wait_err != nil {
		fmt.wprintf(cmd.err, "Error waiting for editor: %v\n", wait_err, flush = false)
		return
	}

	// TODO: Should we call exit inside of commands?
	if state.exit_code != 0 {
		os.exit(int(state.exit_code))
	}
}

