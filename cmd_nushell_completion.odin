package main

import "core:fmt"
import "core:strings"

nushell_header :: `def tracked-paths [] {
  (
    ^envr list
    | from json
    | each {
      [$in.directory $in.path] | path join
    }
  )
}

def untracked-paths [] {
  (
    ^envr scan
    | from json
  )
}

def color [] {
  ['auto' 'always' 'never']
}

def output [] {
  ['auto' 'table' 'json']
}

`

cmd_nushell_completion :: proc(cmd: ^Command) {
	fmt.wprint(cmd.out, generate_nushell_completion(), flush = true)
}

generate_nushell_completion :: proc() -> string {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	defer strings.builder_destroy(&sb)

	fmt.sbprint(&sb, nushell_header)

	for c in COMMANDS {
		fmt.sbprintf(&sb, "# %s\n", c.short)
		fmt.sbprintf(&sb, "export extern \"envr %s\" [\n", c.name)
		for ft in Flag_Type {
			if ft not_in c.flags do continue
			f := flag_field(ft)
			fmt.sbprintf(&sb, "  %s\n", nushell_flag_line(f))
		}
		for arg in c.args {
			fmt.sbprintf(&sb, "  %s\n", nushell_positional_line(arg))
		}
		fmt.sbprintf(&sb, "]\n")

		for a in c.aliases {
			fmt.sbprintf(&sb, "\nexport alias \"envr %s\" = envr %s\n", a, c.name)
		}
		fmt.sbprintf(&sb, "\n")
	}

	return strings.to_string(sb)
}

nushell_flag_line :: proc(f: Flag_Field) -> string {
	line: string
	if len(f.short_name) > 0 {
		line = fmt.tprintf("--%s(-%s)", f.long_name, f.short_name)
	} else {
		line = fmt.tprintf("--%s", f.long_name)
	}

	switch f.kind {
	case .Bool:
	case .String:
		line = fmt.tprintf("%s: path", line)
	case .Enum:
		if len(f.completion) > 0 {
			line = fmt.tprintf("%s: string@%s", line, f.completion)
		} else {
			line = fmt.tprintf("%s: string", line)
		}
	}

	return fmt.tprintf("%s  # %s", line, f.usage)
}

nushell_positional_line :: proc(arg: Positional_Arg) -> string {
	name := arg.name
	if arg.optional {
		name = fmt.tprintf("%s?", name)
	}
	if len(arg.completion) > 0 {
		return fmt.tprintf("%s: path@%s", name, arg.completion)
	}
	return fmt.tprintf("%s: path", name)
}

