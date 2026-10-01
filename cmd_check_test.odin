#+test
package main

import "core:testing"
import "core:bufio"
import "core:os"
import "core:path/filepath"
import "core:strings"

@(test)
test_find_unbacked_finds_missing :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env", "/c/.env"}
	db := []EnvFile{{path = "/a/.env"}, {path = "/b/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 1)
	if len(result) > 0 {
		testing.expect_value(t, result[0], "/c/.env")
	}
}

@(test)
test_find_unbacked_all_backed :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env"}
	db := []EnvFile{{path = "/a/.env"}, {path = "/b/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 0)
}

@(test)
test_find_unbacked_no_local :: proc(t: ^testing.T) {
	local: []string
	db := []EnvFile{{path = "/a/.env"}}

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 0)
}

@(test)
test_find_unbacked_none_backed :: proc(t: ^testing.T) {
	local := []string{"/a/.env", "/b/.env"}
	db: []EnvFile

	result := find_unbacked(local, db[:])
	testing.expect_value(t, len(result), 2)
}

@(test)
test_cmd_check_remote_path :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-check-remote-*")
	defer os.remove_all(base)
	cfg_path, _ := filepath.join({base, "config.json"}, context.temp_allocator)
	cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
	testing.expect(t, save_config(cfg, force = true), "config should save")
	delete_config(&cfg)

	db, db_ok := db_open(cfg_path)
	testing.expect(t, db_ok, "db should open")
	if !db_ok do return
	file := make_test_env_file("spencer@example.com:/etc/umami.env", "abc123", "SECRET=value")
	testing.expect(t, db_insert(&db, file), "remote record should insert")
	db_close(&db)

	out_b: strings.Builder
	strings.builder_init(&out_b)
	defer strings.builder_destroy(&out_b)
	err_b: strings.Builder
	strings.builder_init(&err_b)
	defer strings.builder_destroy(&err_b)

	cmd, ok := parse_args(
		[]string{"envr", "check", "spencer@example.com:/etc/umami.env", "--config-file", cfg_path},
		strings.to_stream(&out_b),
		strings.to_stream(&err_b),
	)
	testing.expect(t, ok, "command should parse")
	if !ok do return
	defer delete_command(&cmd)

	cmd_check(&cmd)
	bufio.writer_flush(cmd.out_buf)
	output := strings.to_string(out_b)
	error_output := strings.to_string(err_b)
	testing.expect(t, strings.contains(output, "Remote file is backed up"), "tracked remote should report backed up")
	testing.expect(t, len(error_output) == 0, "remote path should not be treated as a local path")
}
