package main

import "core:fmt"

VERSION :: "0.2.0"

cmd_version :: proc(cmd: ^Command) {
	if has_flag(cmd, "long") || has_flag(cmd, "l") {
		fmt.printf("envr version %s\n", VERSION)
	} else {
		fmt.println(VERSION)
	}
}
