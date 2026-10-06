#+test
package main

import "core:bufio"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:terminal"
import "core:testing"

@(test)
test_cmd_view_writes_decrypted_backup_to_stdout :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-view-*")
	defer os.remove_all(base)

	cfg_path, _ := filepath.join({base, "config.json"}, context.temp_allocator)
	file_path, _ := filepath.join({base, ".env"}, context.temp_allocator)
	{
		cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
		defer delete_config(&cfg)
		testing.expect(t, save_config(cfg, force = true), "config should save")
	}

	{
		db, db_ok := db_open(cfg_path)
		defer db_close(&db)
		testing.expect(t, db_ok, "db should open")
		if !db_ok do return
		file := make_test_env_file(file_path, "abc123", "SECRET=value\n")
		testing.expect(t, db_insert(&db, file), "backup should insert")
	}

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok := parse_args(
		[]string{"envr", "view", file_path, "--stdout", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "view command should parse")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect(t, cmd_view(&cmd), "stored backup should be viewable without local file")
	bufio.writer_flush(cmd.out_buf)
	testing.expect_value(t, strings.to_string(out_b), "SECRET=value\n")
	testing.expect_value(t, len(strings.to_string(err_b)), 0)
}

@(test)
test_cmd_view_number_follows_list_order :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-view-number-*")
	defer os.remove_all(base)
	cfg_path, _ := filepath.join({base, "config.json"}, context.temp_allocator)
	{
		cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
		defer delete_config(&cfg)
		testing.expect(t, save_config(cfg, force = true), "config should save")
	}

	{
		db, db_ok := db_open(cfg_path)
		defer db_close(&db)
		testing.expect(t, db_ok, "db should open")
		if !db_ok do return
		paths := []string{"/zeta/.env", "/alpha/.env"}
		for path, i in paths {
			contents := i == 0 ? "ZETA\n" : "ALPHA\n"
			file := make_test_env_file(path, "abc123", contents)
			testing.expect(t, db_insert(&db, file), "backup should insert")
			delete(file.remotes)
		}
	}

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)
	cmd, ok := parse_args(
		[]string{"envr", "view", "1", "--stdout", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "view command should parse")
	if !ok do return
	defer delete_command(&cmd)

	testing.expect(t, cmd_view(&cmd), "first list position should resolve")
	bufio.writer_flush(cmd.out_buf)
	testing.expect_value(t, strings.to_string(out_b), "ALPHA\n")
}

@(test)
test_view_path_matches :: proc(t: ^testing.T) {
	paths := []string{"/projects/api/.env", "/projects/web/.env", "user@host:/etc/service.env"}
	matches := matching_view_paths("WEB", paths)
	testing.expect_value(t, len(matches), 1)
	if len(matches) > 0 do testing.expect_value(t, matches[0], paths[1])
	remote := matching_view_paths("host:/etc", paths)
	testing.expect_value(t, len(remote), 1)
	if len(remote) > 0 do testing.expect_value(t, remote[0], paths[2])
}

@(test)
test_view_path_unique_and_missing :: proc(t: ^testing.T) {
	paths := []string{"/projects/api/.env", "/projects/web/.env", "/projects/2"}
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)
	w := strings.to_writer(&err_b)
	path, ok := choose_view_path("api", paths, w)
	testing.expect(t, ok, "unique substring should resolve")
	testing.expect_value(t, path, paths[0])
	path, ok = choose_view_path("/projects/web/.env", paths, w)
	testing.expect(t, ok, "exact stored path should resolve")
	testing.expect_value(t, path, paths[1])
	path, ok = choose_view_path("2", paths, w)
	testing.expect(t, ok, "list position should resolve")
	testing.expect_value(t, path, paths[1])
	testing.expect(
		t,
		path != paths[2],
		"list position should take priority over a partial path match",
	)
	path, ok = choose_view_path("3", paths, w)
	testing.expect(t, ok, "third list position should resolve")
	testing.expect_value(t, path, paths[2])
	_, ok = choose_view_path("0", paths, w)
	testing.expect(t, !ok, "zero is not a valid list position")
	_, ok = choose_view_path("missing", paths, w)
	testing.expect(t, !ok, "missing backup should fail")
	testing.expect(
		t,
		strings.contains(strings.to_string(err_b), "No backed-up file matches"),
		"missing backup should explain failure",
	)
}

@(test)
test_view_picker_requires_terminal :: proc(t: ^testing.T) {
	if terminal.is_terminal(os.stdin) && terminal.is_terminal(os.stderr) do return
	paths := []string{"/projects/api/.env", "/projects/web/.env"}
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)
	_, no_path_ok := choose_view_path("", paths, strings.to_writer(&err_b))
	testing.expect(t, !no_path_ok, "no path should require an interactive picker")
	_, ambiguous_ok := choose_view_path("projects", paths, strings.to_writer(&err_b))
	testing.expect(t, !ambiguous_ok, "ambiguous path should require an interactive picker")
}

