package main

import "core:fmt"
import "core:sys/posix"
import "core:terminal/ansi"

MultiSelect_Result :: enum {
	Confirm,
	Cancel,
}

Key :: enum {
	Up,
	Down,
	Space,
	Enter,
	Escape,
	Unknown,
}

Raw_State :: struct {
	original: posix.termios,
	fd:       posix.FD,
}

MAX_VISIBLE :: 7

// Caller is responsible for deleting the responses.
multi_select :: proc(
	prompt: string,
	options: []string,
) -> (
	selected: [dynamic]bool,
	result: MultiSelect_Result,
) {
	if len(options) == 0 {
		return
	}

	selected = make([dynamic]bool, len(options))
	cursor: int = 0
	scroll_offset: int = 0

	fmt.printf(ansi.CSI + ansi.DECTCEM_HIDE)
	visible := render_options(prompt, options, selected[:], cursor, scroll_offset)

	raw, ok := enable_raw_mode(posix.STDIN_FILENO)
	if !ok {
		fmt.printf(ansi.CSI + ansi.DECTCEM_SHOW)
		return
	}
	defer disable_raw_mode(&raw)

	for {
		key := read_key()

		switch key {
		case .Up:
			if cursor > 0 {
				cursor -= 1
			}
		case .Down:
			if cursor < len(options) - 1 {
				cursor += 1
			}
		case .Space:
			selected[cursor] = !selected[cursor]
		case .Enter:
			fmt.printf(
				ansi.CSI + "%d" + ansi.CUU + ansi.CSI + ansi.ED + ansi.CSI + ansi.DECTCEM_SHOW,
				visible + 1,
			)
			result = .Confirm
			return
		case .Escape:
			fmt.printf(
				ansi.CSI + "%d" + ansi.CUU + ansi.CSI + ansi.ED + ansi.CSI + ansi.DECTCEM_SHOW,
				visible + 1,
			)
			result = .Cancel
			return
		case .Unknown:
		}

		scroll_offset = max(0, min(cursor - MAX_VISIBLE / 2, len(options) - MAX_VISIBLE))
		fmt.printf(ansi.CSI + "%d" + ansi.CUU + ansi.CSI + ansi.RESET + ansi.ED, visible + 1)
		visible = render_options(prompt, options, selected[:], cursor, scroll_offset)
	}
}

render_options :: proc(
	prompt: string,
	options: []string,
	selected: []bool,
	cursor: int,
	scroll_offset: int,
) -> int {
	fmt.printf(
		"%s (↑/↓ move, space select, enter confirm)\r\n",
		colorize(.Option_Label, prompt),
	)

	end := scroll_offset + MAX_VISIBLE
	if end > len(options) {
		end = len(options)
	}

	for i in scroll_offset ..< end {
		checkbox := " "
		if selected[i] {
			checkbox = "x"
		}
		if i == cursor {
			fmt.printf(
				"%s [%s] %s\r\n",
				colorize(.Caret, ">"),
				colorize(.Sucess, checkbox),
				options[i],
			)
		} else {
			fmt.printf("  [%s] %s\r\n", colorize(.Sucess, checkbox), options[i])
		}
	}

	return end - scroll_offset
}

enable_raw_mode :: proc(fd: posix.FD) -> (Raw_State, bool) {
	state: Raw_State
	state.fd = fd

	if posix.tcgetattr(fd, &state.original) != .OK {
		return state, false
	}

	attr: posix.termios = state.original
	attr.c_lflag -= {.ICANON, .ECHO, .ISIG, .IEXTEN}
	attr.c_iflag -= {.IXON, .ICRNL, .BRKINT, .INPCK, .ISTRIP}
	attr.c_oflag -= {.OPOST}
	attr.c_cflag += {.CS8}
	attr.c_cc[.VMIN] = 1
	attr.c_cc[.VTIME] = 0

	if posix.tcsetattr(fd, .TCSAFLUSH, &attr) != .OK {
		return state, false
	}

	return state, true
}

disable_raw_mode :: proc(state: ^Raw_State) {
	posix.tcsetattr(state.fd, .TCSAFLUSH, &state.original)
}

read_key :: proc() -> Key {
	buf: [3]u8

	n := posix.read(posix.STDIN_FILENO, &buf[0], 1)
	if n <= 0 {
		return .Unknown
	}

	switch buf[0] {
	case ' ':
		return .Space
	case '\n', '\r':
		return .Enter
	case 0x03:
		return .Escape
	case 0x1b:
		tv: posix.timeval
		tv.tv_sec = 0
		tv.tv_usec = posix.suseconds_t(100000)

		set: posix.fd_set
		posix.FD_ZERO(&set)
		posix.FD_SET(posix.STDIN_FILENO, &set)

		ready := posix.select(1, &set, nil, nil, &tv)
		if ready <= 0 {
			return .Escape
		}

		n2 := posix.read(posix.STDIN_FILENO, &buf[1], 1)
		if n2 <= 0 || buf[1] != '[' {
			return .Escape
		}

		posix.FD_ZERO(&set)
		posix.FD_SET(posix.STDIN_FILENO, &set)
		tv.tv_sec = 0
		tv.tv_usec = posix.suseconds_t(100000)

		ready = posix.select(1, &set, nil, nil, &tv)
		if ready <= 0 {
			return .Escape
		}

		n3 := posix.read(posix.STDIN_FILENO, &buf[2], 1)
		if n3 <= 0 {
			return .Escape
		}

		switch buf[2] {
		case 'A':
			return .Up
		case 'B':
			return .Down
		case:
			return .Escape
		}
	case:
		return .Unknown
	}
}

