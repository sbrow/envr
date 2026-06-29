package main

import "base:runtime"
import "core:strings"
import "core:terminal/ansi"

Color_Code :: enum {
	Heading,
	Command,
	// Example
	Flag,
	Table_Heading,
	Message,
	Sucess,
	Caret,
	Option_Label,
}

// COLOR_EXAMPLE :: ansi.CSI + ansi.ITALIC + ansi.SGR

@(private = "file")
ANSI_RESET :: ansi.CSI + ansi.RESET + ansi.SGR

disable_color := false

colorize :: proc(
	color: Color_Code,
	text: string,
	allocator := context.temp_allocator,
	disable := disable_color,
) -> (
	string,
	runtime.Allocator_Error,
) #optional_allocator_error {
	if disable {
		return text, nil
	} else {
		return strings.concatenate(
			{ansi.CSI, color_code(color), ansi.SGR, text, ANSI_RESET},
			allocator,
		)
	}
}

@(private = "file")
color_code :: proc(code: Color_Code) -> string {
	switch code {
	case .Heading:
		return ansi.BOLD + ";" + ansi.UNDERLINE + ";" + ansi.FG_BRIGHT_GREEN
	case .Command:
		return ansi.BOLD + ";" + ansi.FG_BRIGHT_CYAN
	case .Flag:
		return ansi.BOLD + ";" + ansi.FG_BRIGHT_WHITE
	case .Table_Heading:
		return ansi.FG_BRIGHT_GREEN
	case .Message:
		return ansi.FAINT
	case .Sucess, .Caret:
		return ansi.BOLD + ";" + ansi.FG_GREEN
	case .Option_Label:
		return ansi.BOLD + ";" + ansi.FG_CYAN
	case:
		panic("Unknown case")
	}
}

