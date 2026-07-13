#+test
package main

import "core:bufio"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

@(test)
test_cmd_uninstall_force :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-uninstall-*")

	cfg_path, _ := filepath.join([]string{base, ".envr", "config.json"}, context.temp_allocator)
	cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
	testing.expect(t, save_config(cfg, force = true), "save should succeed")
	delete_config(&cfg)

	db, db_ok := db_open(cfg_path)
	testing.expect(t, db_ok, "db should open")
	if !db_ok do return
	f := make_test_env_file("/project/.env", "abc123", "SECRET=value")
	defer delete(f.remotes)
	db_insert(&db, f)
	db_close(&db)

	envr_d := filepath.dir(cfg_path)
	testing.expect(t, os.exists(envr_d), ".envr directory should exist before uninstall")

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok := parse_args(
		[]string{"envr", "uninstall", "--force", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "parse_args should succeed")
	if !ok do return
	defer delete_command(&cmd)

	cmd_uninstall(&cmd)
	bufio.writer_flush(cmd.out_buf)

	testing.expect(t, !os.exists(envr_d), ".envr directory should be removed")

	output := strings.to_string(out_b)
	testing.expect(t, strings.contains(output, "Removed"), "output should list removed files")
	testing.expect(
		t,
		strings.contains(output, "config.json"),
		"output should mention config.json",
	)
	testing.expect(
		t,
		strings.contains(output, "data.envr"),
		"output should mention data.envr",
	)
}

@(test)
test_cmd_uninstall_nothing_to_remove :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-uninstall-empty-*")
	defer os.remove_all(base)

	cfg_path, _ := filepath.join([]string{base, ".envr", "config.json"}, context.temp_allocator)

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok := parse_args(
		[]string{"envr", "uninstall", "--force", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "parse_args should succeed")
	if !ok do return
	defer delete_command(&cmd)

	cmd_uninstall(&cmd)
	bufio.writer_flush(cmd.out_buf)

	output := strings.to_string(out_b)
	testing.expect(
		t,
		strings.contains(output, "Nothing to remove"),
		"output should say nothing to remove",
	)
}
