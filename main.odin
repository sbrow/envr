package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:prof/spall"
import "core:sync"

SPALL :: #config(SPALL, false)
when SPALL {
	spall_ctx: spall.Context
	@(thread_local)
	spall_buffer: spall.Buffer
}

main :: proc() {
	when SPALL {
		ctx, spall_ok := spall.context_create_with_scale("envr.spall", false, 1.0)
		if !spall_ok {
			fmt.eprintln("Failed to create spall trace file")
			os.exit(1)
		}
		spall_ctx = ctx
		defer spall.context_destroy(&spall_ctx)

		spall_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
		defer delete(spall_backing)

		spall_buffer = spall.buffer_create(spall_backing, u32(sync.current_thread_id()))
		defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
	}

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

when SPALL {
	@(instrumentation_enter)
	spall_enter :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}

	@(instrumentation_exit)
	spall_exit :: proc "contextless" (
		proc_address, call_site_return_address: rawptr,
		loc: runtime.Source_Code_Location,
	) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}

