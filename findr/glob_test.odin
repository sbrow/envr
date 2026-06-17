package findr

import "core:testing"

glob_match :: proc(pattern: string, path: string, anchored: bool) -> bool {
	gp := glob_compile(pattern, anchored)
	result := glob_match_compiled(&gp, path)
	glob_destroy(&gp)
	return result
}

@(test)
test_glob_simple :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("foo", "foo", false))
	testing.expect(t, glob_match("foo", "bar/foo", false))
	testing.expect(t, !glob_match("foo", "foobar", false))
	testing.expect(t, !glob_match("foo", "foo/bar", false))
}

@(test)
test_glob_anchored :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("foo", "foo", true))
	testing.expect(t, !glob_match("foo", "bar/foo", true))
	testing.expect(t, !glob_match("foo", "foobar", true))
}

@(test)
test_glob_star :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("*.log", "test.log", false))
	testing.expect(t, glob_match("*.log", ".log", false))
	testing.expect(t, !glob_match("*.log", "test.txt", false))
	testing.expect(t, !glob_match("*.log", "dir/test", false))
}

@(test)
test_glob_question :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("?.log", "a.log", false))
	testing.expect(t, !glob_match("?.log", "ab.log", false))
	testing.expect(t, !glob_match("?.log", ".log", false))
}

@(test)
test_glob_char_class :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("[abc].log", "a.log", false))
	testing.expect(t, glob_match("[abc].log", "b.log", false))
	testing.expect(t, !glob_match("[abc].log", "d.log", false))
}

@(test)
test_glob_negated_class :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("[!abc].log", "d.log", false))
	testing.expect(t, !glob_match("[!abc].log", "a.log", false))
}

@(test)
test_glob_dot_literal :: proc(t: ^testing.T) {
	testing.expect(t, glob_match(".env", ".env", false))
	testing.expect(t, glob_match(".env", "dir/.env", false))
	testing.expect(t, !glob_match(".env", "env", false))
	testing.expect(t, !glob_match(".env", "x.env", false))
}

@(test)
test_glob_globstar_prefix :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("**/foo", "foo", false))
	testing.expect(t, glob_match("**/foo", "a/b/foo", false))
	testing.expect(t, !glob_match("**/foo", "foobar", false))
	testing.expect(t, !glob_match("**/foo", "a/foobar", false))
}

@(test)
test_glob_globstar_suffix :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("abc/**", "abc/x", false))
	testing.expect(t, glob_match("abc/**", "abc/x/y", false))
	testing.expect(t, !glob_match("abc/**", "abc", false))
	testing.expect(t, !glob_match("abc/**", "abcd/x", false))
}

@(test)
test_glob_globstar_middle :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("foo/**/bar", "foo/bar", false))
	testing.expect(t, glob_match("foo/**/bar", "foo/x/bar", false))
	testing.expect(t, !glob_match("foo/**/bar", "foo/barx", false))
	testing.expect(t, !glob_match("foo/**/bar", "foo/x/y/baz", false))
}

@(test)
test_glob_backslash_escape :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("\\!foo", "!foo", false))
	testing.expect(t, !glob_match("\\!foo", "foo", false))
}

@(test)
test_glob_hash_literal :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("#foo", "#foo", false))
	testing.expect(t, !glob_match("#foo", "foo", false))
}

@(test)
test_glob_hash_pattern :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("#*#", "#test#", false))
	testing.expect(t, glob_match("#*#", "##", false))
	testing.expect(t, !glob_match("#*#", "test", false))
	testing.expect(t, !glob_match("#*#", "#test", false))
}

@(test)
test_glob_empty :: proc(t: ^testing.T) {
	testing.expect(t, glob_match("", "", false))
	testing.expect(t, !glob_match("", "foo", false))
}
