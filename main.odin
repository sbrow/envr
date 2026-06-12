package main

import "core:fmt"
import "core:os"

GO_BINARY :: "./envr-go"

main :: proc() {
	cmd, ok := parse_args()
	if !ok {
		return
	}

	if !is_implemented(cmd.name) {
		fallback_to_go()
		return
	}

	switch cmd.name {
	case "version":
		cmd_version(&cmd)
	case "deps":
		cmd_deps(&cmd)
	case "list":
		cmd_list(&cmd)
	case "backup", "add":
		cmd_backup(&cmd)
	case:
		fmt.printf("Unknown command: %s\n", cmd.name)
		print_usage()
		os.exit(1)
	}
}

fallback_to_go :: proc() {
	args := make([dynamic]string)
	append(&args, "./envr-go")
	for i in 1..<len(os.args) {
		append(&args, os.args[i])
	}

	desc := os.Process_Desc{
		command = args[:],
		stdin = os.stdin,
		stdout = os.stdout,
		stderr = os.stderr,
	}

	p, err1 := os.process_start(desc)
	if err1 != nil {
		fmt.printf("Error: failed to run envr-go: %v\n", err1)
		os.exit(1)
	}

	state, err2 := os.process_wait(p)
	if err2 != nil {
		fmt.printf("Error waiting for envr-go: %v\n", err2)
		os.exit(1)
	}

	os.exit(int(state.exit_code))
}
