package main

import "core:fmt"

COMPLETION_SCRIPT: string : string(#load("mod.nu"))

cmd_nushell_completion :: proc(cmd: ^Command) {
	// TODO: Use buffered writer?
	fmt.print(COMPLETION_SCRIPT)
}

