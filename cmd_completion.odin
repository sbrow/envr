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

def shells [] {
  ['nushell' 'bash']
}

`

cmd_completion :: proc(cmd: ^Command) {
	if len(cmd.args) == 0 {
		print_command_help(cmd)
		return
	}

	switch cmd.args[0] {
	case "nushell":
		fmt.wprint(cmd.out, generate_nushell_completion(), flush = true)
	case "bash":
		fmt.wprint(cmd.out, generate_bash_completion(), flush = true)
	case:
		fmt.wprintf(cmd.err, "Unsupported shell: %s\n", cmd.args[0])
		fmt.wprintln(cmd.err, "Supported shells: nushell, bash")
	}
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
	ntype := len(arg.ntype) > 0 ? arg.ntype : "path"
	if len(arg.completion) > 0 {
		return fmt.tprintf("%s: %s@%s", name, ntype, arg.completion)
	}
	return fmt.tprintf("%s: %s", name, ntype)
}

bash_header :: `
_envr() {
    local cur prev cmd
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmd="${COMP_WORDS[1]}"

`

bash_footer :: `
}

complete -F _envr envr
`

generate_bash_completion :: proc() -> string {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	defer strings.builder_destroy(&sb)

	fmt.sbprint(&sb, bash_header)

	// B: Subcommand completion
	fmt.sbprintf(&sb, "    if [[ $COMP_CWORD -eq 1 ]]; then\n")
	fmt.sbprintf(&sb, "        COMPREPLY=( $(compgen -W \"")
	first := true
	for c in COMMANDS {
		if !first do fmt.sbprintf(&sb, " ")
		fmt.sbprintf(&sb, "%s", c.name)
		first = false
		for a in c.aliases {
			fmt.sbprintf(&sb, " %s", a)
		}
	}
	fmt.sbprintf(&sb, "\" -- \"$cur\") )\n")
	fmt.sbprintf(&sb, "        return\n")
	fmt.sbprintf(&sb, "    fi\n\n")

	// C: Flag value completion
	fmt.sbprintf(&sb, "    case \"$prev\" in\n")
	for ft in Flag_Type {
		f := flag_field(ft)
		if f.kind == .Bool do continue

		pattern := fmt.tprintf("--%s", f.long_name)
		if len(f.short_name) > 0 {
			pattern = fmt.tprintf("%s|-%s", pattern, f.short_name)
		}
		fmt.sbprintf(&sb, "        %s)\n", pattern)

		switch f.kind {
		case .Enum:
			fmt.sbprintf(
				&sb,
				"            COMPREPLY=( $(compgen -W \"%s\" -- \"$cur\") )\n",
				bash_enum_values(f.enum_values),
			)
		case .String:
			fmt.sbprintf(&sb, "            COMPREPLY=( $(compgen -f -- \"$cur\") )\n")
		case .Bool:
			panic("unexpected")
		}
		fmt.sbprintf(&sb, "            return\n")
		fmt.sbprintf(&sb, "            ;;\n")
	}
	fmt.sbprintf(&sb, "    esac\n\n")

	// D: Flag name completion per command
	fmt.sbprintf(&sb, "    case \"$cur\" in -*)\n")
	fmt.sbprintf(&sb, "        case \"$cmd\" in\n")
	for c in COMMANDS {
		if c.flags == {} do continue

		cmd_pattern := c.name
		for a in c.aliases {
			cmd_pattern = fmt.tprintf("%s|%s", cmd_pattern, a)
		}
		fmt.sbprintf(&sb, "            %s)\n", cmd_pattern)
		fmt.sbprintf(&sb, "                COMPREPLY=( $(compgen -W \"")

		flag_first := true
		for ft in Flag_Type {
			if ft not_in c.flags do continue
			f := flag_field(ft)
			if !flag_first do fmt.sbprintf(&sb, " ")
			fmt.sbprintf(&sb, "--%s", f.long_name)
			if len(f.short_name) > 0 {
				fmt.sbprintf(&sb, " -%s", f.short_name)
			}
			flag_first = false
		}
		fmt.sbprintf(&sb, "\" -- \"$cur\") )\n")
		fmt.sbprintf(&sb, "                return\n")
		fmt.sbprintf(&sb, "                ;;\n")
	}
	fmt.sbprintf(&sb, "        esac\n")
	fmt.sbprintf(&sb, "        ;;\n")
	fmt.sbprintf(&sb, "    esac\n\n")

	// E: Positional completion
	fmt.sbprintf(&sb, "    case \"$cmd\" in\n")
	for c in COMMANDS {
		has_comp := false
		for arg in c.args {
			if len(arg.completion) > 0 {
				has_comp = true
				break
			}
		}
		if !has_comp do continue

		cmd_pattern := c.name
		for a in c.aliases {
			cmd_pattern = fmt.tprintf("%s|%s", cmd_pattern, a)
		}
		fmt.sbprintf(&sb, "        %s)\n", cmd_pattern)

		for arg in c.args {
			if len(arg.completion) == 0 do continue

			comp: string
			switch arg.completion {
			case "tracked-paths":
				comp = "$(envr list --output json 2>/dev/null)"
			case "untracked-paths":
				comp = "$(envr scan --output json 2>/dev/null)"
			case "shells":
				comp = "nushell bash"
			case:
				continue
			}

			fmt.sbprintf(&sb, "            COMPREPLY=( $(compgen -W \"%s\" -- \"$cur\") )\n", comp)
		}
		fmt.sbprintf(&sb, "            return\n")
		fmt.sbprintf(&sb, "            ;;\n")
	}
	fmt.sbprintf(&sb, "    esac\n")

	fmt.sbprint(&sb, bash_footer)

	return strings.to_string(sb)
}

bash_enum_values :: proc(enum_values: string) -> string {
	s, _ := strings.replace(enum_values, "'", "", -1, context.temp_allocator)
	s, _ = strings.replace(s, "|", " ", -1, context.temp_allocator)
	return s
}

