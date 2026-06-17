package findr

Range :: struct {
	lo: u8,
	hi: u8,
}

Class_Data :: struct {
	negated: bool,
	ranges:  [dynamic]Range,
}

Token_Kind :: enum u8 { Char, Star, Globstar, Question, Class }

Token :: struct {
	kind:      Token_Kind,
	byte:      u8,
	class_idx: u16,
}

GlobPattern :: struct {
	tokens:   [dynamic]Token,
	classes:  [dynamic]Class_Data,
	anchored: bool,
}

glob_compile :: proc(pattern: string, anchored: bool) -> GlobPattern {
	gp: GlobPattern
	gp.tokens = make([dynamic]Token)
	gp.classes = make([dynamic]Class_Data)
	gp.anchored = anchored

	i := 0
	for i < len(pattern) {
		c := pattern[i]

		if c == '*' {
			if i + 1 < len(pattern) && pattern[i + 1] == '*' {
				prev_slash := i == 0 || pattern[i - 1] == '/'
				at_end := i + 2 >= len(pattern)
				next_slash := !at_end && pattern[i + 2] == '/'

				if prev_slash && (next_slash || at_end) {
					append(&gp.tokens, Token{kind = .Globstar})
					if next_slash {
						i += 3
					} else {
						i += 2
					}
				} else {
					append(&gp.tokens, Token{kind = .Star})
					i += 2
				}
			} else {
				append(&gp.tokens, Token{kind = .Star})
				i += 1
			}
		} else if c == '?' {
			append(&gp.tokens, Token{kind = .Question})
			i += 1
		} else if c == '[' {
			i += 1
			negated := false
			if i < len(pattern) && pattern[i] == '!' {
				negated = true
				i += 1
			}

			ranges := make([dynamic]Range)

			if i < len(pattern) && pattern[i] == ']' {
				append(&ranges, Range{lo = ']', hi = ']'})
				i += 1
			}

			for i < len(pattern) && pattern[i] != ']' {
				if i + 2 < len(pattern) && pattern[i + 1] == '-' && pattern[i + 2] != ']' {
					append(&ranges, Range{lo = pattern[i], hi = pattern[i + 2]})
					i += 3
				} else {
					append(&ranges, Range{lo = pattern[i], hi = pattern[i]})
					i += 1
				}
			}

			if i < len(pattern) {
				i += 1
			}

			class_idx := u16(len(gp.classes))
			append(&gp.classes, Class_Data{negated = negated, ranges = ranges})
			append(&gp.tokens, Token{kind = .Class, class_idx = class_idx})
		} else if c == '\\' {
			i += 1
			if i < len(pattern) {
				append(&gp.tokens, Token{kind = .Char, byte = pattern[i]})
				i += 1
			}
		} else {
			append(&gp.tokens, Token{kind = .Char, byte = c})
			i += 1
		}
	}

	return gp
}

match_tokens :: proc(tokens: []Token, classes: []Class_Data, ti: int, path: string, pi: int) -> bool {
	if ti >= len(tokens) {
		return pi == len(path)
	}

	tok := tokens[ti]
	switch tok.kind {
	case .Char:
		if pi < len(path) && path[pi] == tok.byte {
			return match_tokens(tokens, classes, ti + 1, path, pi + 1)
		}
		return false

	case .Question:
		if pi < len(path) && path[pi] != '/' {
			return match_tokens(tokens, classes, ti + 1, path, pi + 1)
		}
		return false

	case .Star:
		max_end := pi
		for max_end < len(path) && path[max_end] != '/' {
			max_end += 1
		}
		for end := max_end; end >= pi; end -= 1 {
			if match_tokens(tokens, classes, ti + 1, path, end) {
				return true
			}
		}
		return false

	case .Globstar:
		if ti + 1 >= len(tokens) {
			return true
		}
		if match_tokens(tokens, classes, ti + 1, path, pi) {
			return true
		}
		for end := pi + 1; end <= len(path); end += 1 {
			if path[end - 1] == '/' {
				if match_tokens(tokens, classes, ti + 1, path, end) {
					return true
				}
			}
		}
		return false

	case .Class:
		if pi >= len(path) {
			return false
		}
		cd := classes[tok.class_idx]
		ch := path[pi]
		in_range := false
		for r in cd.ranges {
			if ch >= r.lo && ch <= r.hi {
				in_range = true
				break
			}
		}
		if in_range != cd.negated {
			return match_tokens(tokens, classes, ti + 1, path, pi + 1)
		}
		return false
	}
	return false
}

glob_match_compiled :: proc(gp: ^GlobPattern, path: string) -> bool {
	tokens := gp.tokens[:]
	classes := gp.classes[:]

	if gp.anchored {
		return match_tokens(tokens, classes, 0, path, 0)
	}

	if match_tokens(tokens, classes, 0, path, 0) {
		return true
	}
	for i := 1; i < len(path); i += 1 {
		if path[i - 1] == '/' {
			if match_tokens(tokens, classes, 0, path, i) {
				return true
			}
		}
	}
	return false
}

glob_destroy :: proc(gp: ^GlobPattern) {
	for &cd in gp.classes {
		delete(cd.ranges)
	}
	delete(gp.classes)
	delete(gp.tokens)
}
