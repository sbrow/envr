package findr

import "core:strings"

Gitignore :: struct {
	rules: [dynamic]Rule,
}

Rule :: struct {
	pattern:  GlobPattern,
	negated:  bool,
	dir_only: bool,
}

Match :: enum {
	None,
	Ignored,
	Unignored,
}

is_ignored :: proc(gi: ^Gitignore, path: string, is_dir: bool) -> bool {
	return check_match(gi, path, is_dir) == .Ignored
}

check_match :: proc(gi: ^Gitignore, path: string, is_dir: bool) -> Match {
	result := Match.None
	for &rule in gi.rules {
		if rule.dir_only && !is_dir do continue
		if glob_match_compiled(&rule.pattern, path) {
			result = rule.negated ? .Unignored : .Ignored
		}
	}
	return result
}

parse :: proc(content: string) -> Gitignore {
	gi: Gitignore
	gi.rules = make([dynamic]Rule)

	remaining := content
	for {
		line, ok := strings.split_lines_iterator(&remaining)
		if !ok do break

		s := strings.trim_space(line)
		if len(s) == 0 do continue
		if s[0] == '#' do continue

		negated := false
		if s[0] == '!' {
			negated = true
			s = s[1:]
		}

		if len(s) > 0 && s[0] == '\\' {
			if len(s) > 1 && (s[1] == '#' || s[1] == '!') {
				s = s[1:]
			}
		}

		dir_only := false
		if len(s) > 0 && s[len(s) - 1] == '/' {
			dir_only = true
			s = s[:len(s) - 1]
		}

		anchored := false
		if len(s) > 0 && s[0] == '/' {
			anchored = true
			s = s[1:]
		}

		if len(s) == 0 do continue

		gp := glob_compile(s, anchored)
		append(&gi.rules, Rule{pattern = gp, negated = negated, dir_only = dir_only})
	}

	return gi
}

destroy :: proc(gi: ^Gitignore) {
	for &rule in gi.rules {
		glob_destroy(&rule.pattern)
	}
	delete(gi.rules)
}

