package main

import "core:fmt"

cmd_version :: proc(cmd: ^Command) {
	if has_flag(cmd, "long") || has_flag(cmd, "l") {
		fmt.printf("envr version %s\n", VERSION)
	} else {
		fmt.println(VERSION)
	}
}

