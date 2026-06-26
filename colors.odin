package main

import "core:io"
import "core:terminal/ansi"

COLOR_HEADINGS ::
	ansi.CSI + ansi.FG_BRIGHT_GREEN + ";" + ansi.BOLD + ";" + ansi.UNDERLINE + ansi.SGR

COLOR_COMMANDS :: ansi.CSI + ansi.FG_BRIGHT_CYAN + ";" + ansi.BOLD + ansi.SGR

COLOR_EXAMPLE :: ansi.CSI + ansi.ITALIC + ansi.SGR

COLOR_FLAGS :: ansi.CSI + ansi.BOLD + ";" + ansi.FG_BRIGHT_WHITE + ansi.SGR

COLOR_TABLE_HEADING :: ansi.CSI + ansi.FG_BRIGHT_GREEN + ansi.SGR

ANSI_RESET :: ansi.CSI + ansi.RESET + ansi.SGR

ANSI_Strip_State :: enum { Normal, GotESC, InCSI }

ANSI_Strip_Data :: struct {
	inner: io.Writer,
	state: ANSI_Strip_State,
}

ansi_strip_proc :: proc(
	stream_data: rawptr,
	mode:        io.Stream_Mode,
	p:           []byte,
	offset:      i64,
	whence:      io.Seek_From,
) -> (n: i64, err: io.Error) {
	data := cast(^ANSI_Strip_Data) stream_data

	#partial switch mode {
	case .Write:
		start := 0
		for i in 0..<len(p) {
			b := p[i]

			switch data.state {
			case .Normal:
				if b == 0x1b {
					if i > start {
						io.write(data.inner, p[start:i])
					}
					data.state = .GotESC
				}

			case .GotESC:
				if b == '[' {
					data.state = .InCSI
				} else {
					start = i
					data.state = .Normal
				}

			case .InCSI:
				if b >= 0x40 && b <= 0x7E {
					start = i + 1
					data.state = .Normal
				}
			}
		}

		if data.state == .Normal && len(p) > start {
			io.write(data.inner, p[start:])
		}

		n = i64(len(p))
		return

	case .Flush:
		return 0, io.flush(data.inner)
	case .Close:
		return 0, io.close(data.inner)
	case:
		return data.inner.procedure(data.inner.data, mode, p, offset, whence)
	}
}

make_ansi_strip_writer :: proc(inner: io.Writer) -> io.Writer {
	data := new(ANSI_Strip_Data, context.temp_allocator)
	data.inner = inner
	return io.Writer{procedure = ansi_strip_proc, data = rawptr(data)}
}
