#+feature dynamic-literals
#+test
package main

import "core:bufio"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_filepath_base_equals_rel :: proc(t: ^testing.T) {
	cases := []string{"/home/user/.env", "/home/user/project/.envrc", "/tmp/foo", "/a/b/c/d.txt"}

	for path in cases {
		dir := filepath.dir(path)
		rel, rel_err := filepath.rel(dir, path, context.temp_allocator)
		testing.expect_value(t, rel_err, nil)
		base := filepath.base(path)
		testing.expect_value(t, rel, base)
	}
}

@(test)
test_cmd_list_output_json :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-list-json-*")
	defer os.remove_all(base)

	cfg_path, _ := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
	testing.expect(t, save_config(cfg, force = true), "save should succeed")
	delete_config(&cfg)

	db, db_ok := db_open(cfg_path)
	testing.expect(t, db_ok, "db should open")
	if !db_ok do return
	f := make_test_env_file("/project/.env", "abc123", "SECRET=value")
	defer delete(f.remotes)
	testing.expect(t, db_insert(&db, f), "insert should succeed")
	db_close(&db)

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok := parse_args(
		[]string{"envr", "list", "--output", "json", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "parse_args should succeed")
	if !ok do return
	defer delete_command(&cmd)

	cmd_list(&cmd)
	bufio.writer_flush(cmd.out_buf)
	output := strings.to_string(out_b)

	testing.expect(t, strings.contains(output, "["), "json output should contain '['")
	testing.expect(
		t,
		strings.contains(output, "\"directory\""),
		"json output should contain directory key",
	)
}

@(test)
test_cmd_list_output_table :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-list-table-*")
	defer os.remove_all(base)

	cfg_path, _ := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
	testing.expect(t, save_config(cfg, force = true), "save should succeed")
	delete_config(&cfg)

	db, db_ok := db_open(cfg_path)
	testing.expect(t, db_ok, "db should open")
	if !db_ok do return
	f := make_test_env_file("/project/.env", "abc123", "SECRET=value")
	defer delete(f.remotes)
	testing.expect(t, db_insert(&db, f), "insert should succeed")
	db_close(&db)

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok := parse_args(
		[]string{"envr", "list", "--output", "table", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "parse_args should succeed")
	if !ok do return
	defer delete_command(&cmd)

	cmd_list(&cmd)
	bufio.writer_flush(cmd.out_buf)
	output := strings.to_string(out_b)

	testing.expect(t, strings.contains(output, "│"), "table output should contain border chars")
	testing.expect(
		t,
		strings.contains(output, "Directory"),
		"table output should contain Directory header",
	)
}

