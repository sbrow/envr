package main

import "core:bufio"
import "core:fmt"
import "core:os"

main :: proc() {
	cmd, ok := parse_args(os.args, os.to_writer(os.stdout), os.to_writer(os.stderr))
	defer bufio.writer_flush(cmd.out_buf)
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
		fmt.wprintf(cmd.err, "Unknown command: %s\n", cmd.name)
		write_usage(cmd.out)
		os.exit(1)
	}
}

