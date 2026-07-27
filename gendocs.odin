package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

when #config(GENDOCS, false) {
	main :: proc() {
		args := os.args
		if len(args) < 2 {
			fmt.eprintln("Usage: gendocs --man | --md")
			os.exit(1)
		}

		switch args[1] {
		case "--man":
			generate_man_pages()
		case "--md":
			generate_markdown()
		case:
			fmt.eprintf("Unknown format: %s\n", args[1])
			os.exit(1)
		}
	}
}

generate_man_pages :: proc() {
	os.mkdir_all("docs/man")

	now := time.now()
	month_year := fmt.tprintf("%s %d", time.month(now), time.year(now))

	generate_man_main(month_year)

	for &c in COMMANDS {
		generate_man_command(&c, month_year)
	}

	fmt.println("Generated man pages in docs/man/")
}

generate_man_main :: proc(month_year: string) {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	defer strings.builder_destroy(&sb)

	fmt.sbprintf(&sb, ".TH ENVR 1 \"%s\" \"envr\" \"envr Manual\"\n", month_year)
	fmt.sbprintf(&sb, ".SH NAME\nenvr \\- keep your .env files synced to an encrypted database\n")
	fmt.sbprintf(&sb, ".SH SYNOPSIS\n\\fBenvr\\fR [\\fIcommand\\fR] [\\fIflags\\fR]\n")
	fmt.sbprintf(
		&sb,
		".SH DESCRIPTION\nenvr keeps your .env synced to a local, encrypted database.\n",
	)
	fmt.sbprintf(
		&sb,
		"Is a safe and easy way to gather all your .env files in one place where they can\n",
	)
	fmt.sbprintf(&sb, "easily be backed by another tool such as restic or git.\n")
	fmt.sbprintf(&sb, ".PP\nAll your data is stored in ~/.envr/data.envr\n")
	fmt.sbprintf(&sb, ".SH COMMANDS\n")
	for c in COMMANDS {
		fmt.sbprintf(&sb, ".TP\n\\fB%s\\fR\n%s\n", c.name, c.short)
		for a in c.aliases {
			fmt.sbprintf(&sb, ".TP\n\\fB%s\\fR (alias for %s)\n%s\n", a, c.name, c.short)
		}
	}
	fmt.sbprintf(&sb, ".SH GLOBAL OPTIONS\n")
	for ft in Flag_Type {
		if ft not_in GLOBAL_FLAGS do continue
		write_man_flag(&sb, ft)
	}
	fmt.sbprintf(&sb, ".SH SEE ALSO\n")
	for c, i in COMMANDS {
		if i > 0 do fmt.sbprintf(&sb, ",\n")
		fmt.sbprintf(&sb, ".BR envr-%s (1)", c.name)
	}
	fmt.sbprintf(&sb, "\n")

	path := "docs/man/envr.1"
	err := os.write_entire_file(path, transmute([]u8)strings.to_string(sb))
	if err != nil {
		fmt.eprintf("Error writing %s: %v\n", path, err)
	}
}

generate_man_command :: proc(c: ^CommandInfo, month_year: string) {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	defer strings.builder_destroy(&sb)

	upper_name := strings.to_upper(fmt.tprintf("envr-%s", c.name))

	fmt.sbprintf(&sb, ".TH %s 1 \"%s\" \"envr\" \"envr Manual\"\n", upper_name, month_year)
	fmt.sbprintf(&sb, ".SH NAME\nenvr-%s \\- %s\n", c.name, c.short)
	fmt.sbprintf(&sb, ".SH SYNOPSIS\n\\fB%s\\fR", c.usage)

	has_positionals := false
	for arg in c.args {
		has_positionals = true
		if arg.optional {
			fmt.sbprintf(&sb, " [\\fI%s\\fR]", arg.name)
		} else {
			fmt.sbprintf(&sb, " \\fI%s\\fR", arg.name)
		}
	}
	fmt.sbprintf(&sb, "\n")

	if len(c.long) > 0 {
		fmt.sbprintf(&sb, ".SH DESCRIPTION\n%s\n", c.long)
	}

	if has_positionals {
		fmt.sbprintf(&sb, ".SH ARGUMENTS\n")
		for arg in c.args {
			fmt.sbprintf(&sb, ".TP\n\\fB%s\\fR\n%s\n", arg.name, arg.desc)
		}
	}

	fmt.sbprintf(&sb, ".SH OPTIONS\n")
	for ft in Flag_Type {
		if ft not_in c.flags do continue
		write_man_flag(&sb, ft)
	}

	path := fmt.tprintf("docs/man/envr-%s.1", c.name)
	err := os.write_entire_file(path, transmute([]u8)strings.to_string(sb))
	if err != nil {
		fmt.eprintf("Error writing %s: %v\n", path, err)
	}
}

write_man_flag :: proc(sb: ^strings.Builder, ft: Flag_Type) {
	f := flag_field(ft)

	fmt.sbprintf(sb, ".TP\n")
	if len(f.short_name) > 0 {
		fmt.sbprintf(sb, "\\fB-%s\\fR, \\fB--%s\\fR", f.short_name, f.long_name)
	} else {
		fmt.sbprintf(sb, "\\fB--%s\\fR", f.long_name)
	}

	#partial switch f.kind {
	case .String:
		fmt.sbprintf(sb, " \\fIvalue\\fR")
	case .Enum:
		values, _ := strings.replace(f.enum_values, "'", "", -1)
		fmt.sbprintf(sb, " \\fI%s\\fR", values)
	}

	fmt.sbprintf(sb, "\n%s\n", f.usage)

	if len(f.default_val) > 0 {
		#partial switch f.kind {
		case .String:
			fmt.sbprintf(sb, "(default \"%s\")\n", f.default_val)
		case .Enum:
			fmt.sbprintf(sb, "(default '%s')\n", f.default_val)
		}
	}
}

generate_markdown :: proc() {
	os.mkdir_all("docs/cli")

	generate_md_main()

	for &c in COMMANDS {
		generate_md_command(&c)
	}

	fmt.println("Generated markdown in docs/cli/")
}

generate_md_main :: proc() {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	defer strings.builder_destroy(&sb)

	fmt.sbprintf(&sb, "## envr\n\n")
	fmt.sbprintf(&sb, "Manage your .env files.\n\n")
	fmt.sbprintf(&sb, "### Synopsis\n\n")
	fmt.sbprint(&sb, ENVR_DESCRIPTION)
	fmt.sbprintf(&sb, "\n\n### Options\n\n")
	write_md_options(&sb, {.Help})
	fmt.sbprintf(&sb, "\n### SEE ALSO\n\n")
	for c in COMMANDS {
		fmt.sbprintf(&sb, "* [envr %s](envr_%s.md)\t - %s\n", c.name, c.name, c.short)
	}
	fmt.sbprintf(&sb, "\n")

	write_file("docs/cli/envr.md", strings.to_string(sb))
}

generate_md_command :: proc(c: ^CommandInfo) {
	sb: strings.Builder
	strings.builder_init(&sb, context.temp_allocator)
	defer strings.builder_destroy(&sb)

	fmt.sbprintf(&sb, "## envr %s\n\n", c.name)
	fmt.sbprintf(&sb, "%s\n\n", c.short)

	if len(c.long) > 0 {
		fmt.sbprintf(&sb, "### Synopsis\n\n")
		fmt.sbprint(&sb, c.long)
		fmt.sbprintf(&sb, "\n\n")
	}

	fmt.sbprintf(&sb, "```\n%s [flags]\n```\n\n", c.usage)

	if len(c.args) > 0 {
		fmt.sbprintf(&sb, "**Arguments:**\n\n")
		for arg in c.args {
			optional := arg.optional ? " (optional)" : ""
			fmt.sbprintf(&sb, "* `%s` — %s%s\n", arg.name, arg.desc, optional)
		}
		fmt.sbprintf(&sb, "\n")
	}

	fmt.sbprintf(&sb, "### Options\n\n")
	write_md_options(&sb, c.flags)

	for a in c.aliases {
		fmt.sbprintf(&sb, "\n*Alias: `%s`*\n", a)
	}

	fmt.sbprintf(&sb, "\n### SEE ALSO\n\n")
	fmt.sbprintf(&sb, "* [envr](envr.md)\t - Manage your .env files.\n")

	path := fmt.tprintf("docs/cli/envr_%s.md", c.name)
	write_file(path, strings.to_string(sb))
}

write_md_options :: proc(sb: ^strings.Builder, flags: bit_set[Flag_Type]) {
	displays := make([dynamic]string, 0, 5, context.temp_allocator)
	defer delete(displays)

	descs := make([dynamic]string, 0, 5, context.temp_allocator)
	defer delete(descs)

	max_width := 0

	for ft in Flag_Type {
		if ft not_in flags do continue
		f := flag_field(ft)

		display: string
		if len(f.short_name) > 0 {
			display = fmt.tprintf("-%s, --%s", f.short_name, f.long_name)
		} else {
			display = fmt.tprintf("    --%s", f.long_name)
		}

		desc := f.usage
		if len(f.default_val) > 0 {
			#partial switch f.kind {
			case .String:
				desc = fmt.tprintf(`%s (default "%s")`, f.usage, f.default_val)
			case .Enum:
				desc = fmt.tprintf("%s (default '%s')", f.usage, f.default_val)
			}
		}

		append(&displays, display)
		append(&descs, desc)
		if len(display) > max_width {
			max_width = len(display)
		}
	}

	fmt.sbprintf(sb, "```\n")
	pad_buf: [64]u8
	for i in 0..<len(displays) {
		padding := max_width - len(displays[i]) + 3
		for j in 0..<padding {
			pad_buf[j] = ' '
		}
		fmt.sbprintf(sb, "  %s%s%s\n", displays[i], string(pad_buf[:padding]), descs[i])
	}
	fmt.sbprintf(sb, "```\n")
}

write_file :: proc(path: string, content: string) {
	err := os.write_entire_file(path, transmute([]u8)content)
	if err != nil {
		fmt.eprintf("Error writing %s: %v\n", path, err)
	}
}

