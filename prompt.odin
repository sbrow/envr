package main

import "core:fmt"
import "core:strings"
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
	Backspace,
	Char,
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
	filter: [dynamic]u8
	defer delete(filter)
	filtered: [dynamic]int
	defer delete(filtered)
	rebuild_filtered(options, filter[:], &filtered)

	cursor: int = 0
	scroll_offset: int = 0

	fmt.printf(ansi.CSI + ansi.DECTCEM_HIDE)
	visible := render_options(prompt, options, selected[:], filtered[:], string(filter[:]), cursor, scroll_offset)

	raw, ok := enable_raw_mode(posix.STDIN_FILENO)
	if !ok {
		fmt.printf(ansi.CSI + ansi.DECTCEM_SHOW)
		return
	}
	defer disable_raw_mode(&raw)

	for {
		key, ch := read_key()

		switch key {
		case .Char:
			append(&filter, u8(ch))
			rebuild_filtered(options, filter[:], &filtered)
			cursor = clamp(cursor, 0, max(0, len(filtered) - 1))
		case .Backspace:
			if len(filter) > 0 {
				pop(&filter)
				rebuild_filtered(options, filter[:], &filtered)
				cursor = clamp(cursor, 0, max(0, len(filtered) - 1))
			}
		case .Up:
			if cursor > 0 {
				cursor -= 1
			}
		case .Down:
			if cursor < len(filtered) - 1 {
				cursor += 1
			}
		case .Space:
			if len(filtered) > 0 {
				selected[filtered[cursor]] = !selected[filtered[cursor]]
			}
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

		scroll_offset = max(0, min(cursor - MAX_VISIBLE / 2, len(filtered) - MAX_VISIBLE))
		fmt.printf(ansi.CSI + "%d" + ansi.CUU + ansi.CSI + ansi.RESET + ansi.ED, visible + 1)
		visible = render_options(prompt, options, selected[:], filtered[:], string(filter[:]), cursor, scroll_offset)
	}
}

rebuild_filtered :: proc(options: []string, filter: []u8, filtered: ^[dynamic]int) {
	clear(filtered)
	filter_str := string(filter)
	filter_lower := strings.to_lower(filter_str, context.temp_allocator)
	for opt, i in options {
		opt_lower := strings.to_lower(opt, context.temp_allocator)
		if strings.contains(opt_lower, filter_lower) {
			append(filtered, i)
		}
	}
}

render_options :: proc(
	prompt: string,
	options: []string,
	selected: []bool,
	filtered: []int,
	filter_text: string,
	cursor: int,
	scroll_offset: int,
) -> int {
	fmt.printf(
		"%s (type to filter, ↑/↓ move, space select, enter confirm)\r\n",
		colorize(.Option_Label, prompt),
	)

	fmt.printf("filter: %s\r\n", filter_text)

	line_count := 1

	if len(filtered) == 0 {
		fmt.printf("  No matches\r\n")
		return line_count + 1
	}

	end := scroll_offset + MAX_VISIBLE
	if end > len(filtered) {
		end = len(filtered)
	}

	for i in scroll_offset ..< end {
		original := filtered[i]
		checkbox := " "
		if selected[original] {
			checkbox = "x"
		}
		if i == cursor {
			fmt.printf(
				"%s [%s] %s\r\n",
				colorize(.Caret, ">"),
				colorize(.Sucess, checkbox),
				options[original],
			)
		} else {
			fmt.printf("  [%s] %s\r\n", colorize(.Sucess, checkbox), options[original])
		}
	}

	return line_count + (end - scroll_offset)
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

read_key :: proc() -> (key: Key, ch: rune) {
	buf: [3]u8

	n := posix.read(posix.STDIN_FILENO, &buf[0], 1)
	if n <= 0 {
		return .Unknown, 0
	}

	switch buf[0] {
	case ' ':
		return .Space, 0
	case '\n', '\r':
		return .Enter, 0
	case 0x03:
		return .Escape, 0
	case 0x08, 0x7F:
		return .Backspace, 0
	case 0x1b:
		tv: posix.timeval
		tv.tv_sec = 0
		tv.tv_usec = posix.suseconds_t(100000)

		set: posix.fd_set
		posix.FD_ZERO(&set)
		posix.FD_SET(posix.STDIN_FILENO, &set)

		ready := posix.select(1, &set, nil, nil, &tv)
		if ready <= 0 {
			return .Escape, 0
		}

		n2 := posix.read(posix.STDIN_FILENO, &buf[1], 1)
		if n2 <= 0 || buf[1] != '[' {
			return .Escape, 0
		}

		posix.FD_ZERO(&set)
		posix.FD_SET(posix.STDIN_FILENO, &set)
		tv.tv_sec = 0
		tv.tv_usec = posix.suseconds_t(100000)

		ready = posix.select(1, &set, nil, nil, &tv)
		if ready <= 0 {
			return .Escape, 0
		}

		n3 := posix.read(posix.STDIN_FILENO, &buf[2], 1)
		if n3 <= 0 {
			return .Escape, 0
		}

		switch buf[2] {
		case 'A':
			return .Up, 0
		case 'B':
			return .Down, 0
		case:
			return .Escape, 0
		}
	case:
		if buf[0] >= 0x20 && buf[0] <= 0x7E {
			return .Char, rune(buf[0])
		}
		return .Unknown, 0
	}
}

