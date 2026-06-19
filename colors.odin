package main

import "core:terminal/ansi"

COLOR_HEADINGS ::
	ansi.CSI + ansi.FG_BRIGHT_GREEN + ";" + ansi.BOLD + ";" + ansi.UNDERLINE + ansi.SGR

COLOR_COMMANDS :: ansi.CSI + ansi.FG_BRIGHT_CYAN + ";" + ansi.BOLD + ansi.SGR

COLOR_EXAMPLE :: ansi.CSI + ansi.ITALIC + ansi.SGR

COLOR_FLAGS :: ansi.CSI + ansi.BOLD + ";" + ansi.FG_BRIGHT_WHITE + ansi.SGR

COLOR_TABLE_HEADING :: ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR

ANSI_RESET :: ansi.CSI + ansi.RESET + ansi.SGR

