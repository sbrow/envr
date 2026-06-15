package main

import "core:fmt"
import "core:os"

main :: proc() {
	cmd, ok := parse_args(os.args)
	if !ok {
		return
	}

	switch cmd.name {
	case "init":
		cmd_init(&cmd)
	case "version":
		cmd_version(&cmd)
	case "deps":
		cmd_deps(&cmd)
	case "list":
		cmd_list(&cmd)
	case "backup", "add":
		cmd_backup(&cmd)
	case "remove":
		cmd_remove(&cmd)
	case "restore":
		cmd_restore(&cmd)
	case "edit-config":
		cmd_edit_config(&cmd)
	case "check":
		cmd_check(&cmd)
	case "scan":
		cmd_scan(&cmd)
	case "sync":
		cmd_sync(&cmd)
	case "nushell-completion":
		cmd_nushell_completion(&cmd)
	case:
		fmt.printf("Unknown command: %s\n", cmd.name)
		print_usage()
		os.exit(1)
	}
}


