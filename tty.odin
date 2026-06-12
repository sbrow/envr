package main

import "core:sys/posix"

is_tty :: proc() -> bool {
	return bool(posix.isatty(1))
}
