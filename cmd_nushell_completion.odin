package main

import "core:fmt"

COMPLETION_SCRIPT: string : string(#load("mod.nu"))

cmd_nushell_completion :: proc(cmd: ^Command) {
	fmt.wprint(cmd.out, COMPLETION_SCRIPT, flush = false)
}

