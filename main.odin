package main

import "core:fmt"
import "core:mem"
import "core:os"

main :: proc() {
	when ODIN_DEBUG {
		heap_track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&heap_track, context.allocator)
		defer mem.tracking_allocator_destroy(&heap_track)
		defer if len(heap_track.allocation_map) > 0 {
			for _, leak in heap_track.allocation_map {
				fmt.eprintf("LEAK: %v leaked %m\n", leak.location, leak.size)
			}
		}
		context.allocator = mem.tracking_allocator(&heap_track)

		temp_track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&temp_track, context.temp_allocator)
		defer mem.tracking_allocator_destroy(&temp_track)
		context.temp_allocator = mem.tracking_allocator(&temp_track)
	}

	defer free_all(context.temp_allocator)

	cmd, ok := parse_args(os.args, os.to_writer(os.stdout), os.to_writer(os.stderr))
	defer delete_command(&cmd) // delete flushes automatically
	if !ok {
		return
	}

	switch cmd.name {
	case "init":
		cmd_init(&cmd)
	case "version":
		cmd_version(&cmd)
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

