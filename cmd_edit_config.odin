package main

import "core:fmt"
import "core:os"
import "core:path/filepath"

cmd_edit_config :: proc(cmd: ^Command) {
	editor := os.get_env("EDITOR", context.allocator)
	if len(editor) == 0 {
		fmt.println("Error: $EDITOR environment variable is not set")
		return
	}

	config_path, join_err := filepath.join([]string{envr_dir(), "config.json"})
	if join_err != nil {
		fmt.printf("Error building config path: %v\n", join_err)
		return
	}

	_, stat_err := os.stat(config_path, context.allocator)
	if stat_err != nil {
		fmt.printf("Config file does not exist at %s. Run 'envr init' first.\n", config_path)
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
		fmt.printf("Error running editor: %v\n", start_err)
		return
	}

	state, wait_err := os.process_wait(p)
	if wait_err != nil {
		fmt.printf("Error waiting for editor: %v\n", wait_err)
		return
	}
	if state.exit_code != 0 {
		os.exit(int(state.exit_code))
	}
}

