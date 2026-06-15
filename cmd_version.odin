package main

import "core:fmt"

VERSION :: #load("version.txt", string)

cmd_version :: proc(cmd: ^Command) {
	fmt.println(VERSION)
}

