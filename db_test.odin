#+test
package main

import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "sqlite"

make_test_env_file :: proc(path, sha, contents: string, remotes: []string = {}) -> EnvFile {
	f := EnvFile {
		path     = path,
		dir      = "",
		sha256   = sha,
		contents = contents,
		remotes  = make([dynamic]string, 0, len(remotes), context.temp_allocator),
	}
	for r in remotes {
		append(&f.remotes, r)
	}
	return f
}

@(test)
test_db_insert_and_fetch :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	path := "/project/.env"
	sha := "abc123"
	contents := "SECRET=value"

	f := make_test_env_file(path, sha, contents, []string{"git@github.com:user/repo.git"})
	defer delete(f.remotes)

	testing.expect(t, db_insert(&db, f), "insert should succeed")

	fetched, fetch_ok := db_fetch(&db, "/project/.env")
	// defer delete_envfile(&fetched)
	testing.expect(t, fetch_ok, "fetch should succeed")
	if !fetch_ok do return

	testing.expect_value(t, fetched.path, path)
	testing.expect_value(t, fetched.sha256, sha)
	testing.expect_value(t, fetched.contents, contents)
	testing.expect_value(t, len(fetched.remotes), 1)
	testing.expect_value(t, fetched.remotes[0], "git@github.com:user/repo.git")
}

@(test)
test_db_fetch_missing :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	_, fetch_ok := db_fetch(&db, "/nonexistent/.env")
	testing.expect(t, !fetch_ok, "fetch missing should return false")
}

@(test)
test_db_insert_or_replace :: proc(t: ^testing.T) {
	db, ok := db_init()
	defer db_close(&db)
	testing.expect(t, ok, "failed to create test db")

	f1 := make_test_env_file("/project/.env", "sha1", "KEY=old")
	defer delete(f1.remotes)
	testing.expect(t, db_insert(&db, f1), "first insert should succeed")

	f2 := make_test_env_file("/project/.env", "sha2", "KEY=new")
	defer delete(f2.remotes)
	testing.expect(t, db_insert(&db, f2), "second insert should succeed")

	results, list_ok := db_list(&db)
	testing.expect(t, list_ok, "list should succeed")

	testing.expect(t, len(results) == 1, "should have 1 row, not 2")

	fetched, fetch_ok := db_fetch(&db, "/project/.env")
	testing.expect(t, fetch_ok, "fetch should succeed")
	if !fetch_ok do return
	// defer delete_envfile(&fetched)

	testing.expect_value(t, fetched.contents, "KEY=new")
	testing.expect_value(t, fetched.sha256, "sha2")
}

@(test)
test_db_delete_existing :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.remotes)
	db_insert(&db, f)

	testing.expect(t, db_delete(&db, "/project/.env"), "delete should return true")

	_, fetch_ok := db_fetch(&db, "/project/.env")
	testing.expect(t, !fetch_ok, "row should be gone after delete")
}

@(test)
test_db_delete_missing :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	testing.expect(t, !db_delete(&db, "/nonexistent/.env"), "delete missing should return false")
}

@(test)
test_db_list_multiple :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	f1 := make_test_env_file("/proj1/.env", "sha1", "A=1", []string{"git@github.com:a/repo.git"})
	defer delete(f1.remotes)
	f2 := make_test_env_file("/proj2/.env", "sha2", "B=2", []string{"git@github.com:b/repo.git"})
	defer delete(f2.remotes)
	f3 := make_test_env_file("/proj3/.env", "sha3", "C=3")

	db_insert(&db, f1)
	db_insert(&db, f2)
	db_insert(&db, f3)

	results, list_ok := db_list(&db)
	testing.expect(t, list_ok, "list should succeed")

	testing.expect_value(t, len(results), 3)
}

@(test)
test_db_list_empty :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	results, list_ok := db_list(&db)
	testing.expect(t, list_ok, "list should succeed on empty db")
	testing.expect(t, len(results) == 0, "should have 0 rows")
}

@(test)
test_db_insert_sets_changed :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	testing.expect(t, !db.changed, "changed should start false")

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.remotes)
	db_insert(&db, f)

	testing.expect(t, db.changed, "changed should be true after insert")
}

@(test)
test_db_delete_sets_changed :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.remotes)
	db_insert(&db, f)
	db.changed = false

	db_delete(&db, "/project/.env")
	testing.expect(t, db.changed, "changed should be true after delete")
}

@(test)
test_db_serialize :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer db_close(&db)

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.remotes)
	db_insert(&db, f)

	sz: i64
	data := sqlite.serialize(db.conn, "main", &sz, 0)
	testing.expect(t, data != nil, "serialize should return non-nil")
	if data == nil do return
	defer sqlite.free(data)

	testing.expect(t, sz > 0, "serialized size should be > 0")
}

@(test)
test_shares_remote_overlap :: proc(t: ^testing.T) {
	f := EnvFile {
		remotes = make([dynamic]string, 2, context.temp_allocator),
	}
	append(&f.remotes, "git@github.com:user/repo.git")
	append(&f.remotes, "git@gitlab.com:user/repo.git")

	remotes := []string{"git@github.com:user/repo.git"}
	testing.expect(t, shares_remote(&f, remotes), "should share remote")
}

@(test)
test_shares_remote_no_overlap :: proc(t: ^testing.T) {
	f := EnvFile {
		remotes = make([dynamic]string, 1, context.temp_allocator),
	}
	append(&f.remotes, "git@github.com:user/repo.git")

	remotes := []string{"git@github.com:other/repo.git"}
	testing.expect(t, !shares_remote(&f, remotes), "should not share remote")
}

@(test)
test_shares_remote_empty_file_remotes :: proc(t: ^testing.T) {
	f := EnvFile {
		remotes = make([dynamic]string, 0, context.temp_allocator),
	}

	remotes := []string{"git@github.com:user/repo.git"}
	testing.expect(t, !shares_remote(&f, remotes), "empty file remotes should not share")
}

@(test)
test_shares_remote_empty_check_remotes :: proc(t: ^testing.T) {
	f := EnvFile {
		remotes = make([dynamic]string, 1, context.temp_allocator),
	}
	append(&f.remotes, "git@github.com:user/repo.git")

	remotes: []string
	testing.expect(t, !shares_remote(&f, remotes), "empty check remotes should not share")
}

@(test)
test_shares_remote_both_empty :: proc(t: ^testing.T) {
	f := EnvFile {
		remotes = make([dynamic]string, 0),
	}

	remotes: []string
	testing.expect(t, !shares_remote(&f, remotes), "both empty should not share")
}

delete_remotes :: proc(remotes: [dynamic]string) {
	for &r in remotes {
		delete(r)
	}
	delete(remotes)
}

@(test)
test_get_git_remotes_single :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-remotes-*")
	defer os.remove_all(base)

	git_dir := fmt.tprintf("%s/.git", base)
	os.mkdir_all(git_dir)

	config_content := "[core]\n\trepositoryformatversion = 0\n[remote \"origin\"]\n\turl = git@github.com:user/repo.git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n"
	config_path := fmt.tprintf("%s/config", git_dir)
	err := os.write_entire_file(config_path, transmute([]u8)config_content)
	testing.expect(t, err == nil, "should write .git/config")

	remotes := get_git_remotes(base, context.temp_allocator)

	testing.expect(t, len(remotes) == 1, "should find 1 remote")
	if len(remotes) != 1 do return
	testing.expect_value(t, remotes[0], "git@github.com:user/repo.git")
}

@(test)
test_get_git_remotes_multiple :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-remotes-multi-*")
	defer os.remove_all(base)

	git_dir := fmt.tprintf("%s/.git", base)
	os.mkdir_all(git_dir)

	config_content := "[remote \"origin\"]\n\turl = git@github.com:user/repo.git\n[remote \"upstream\"]\n\turl = https://gitlab.com/upstream/repo.git\n"
	config_path := fmt.tprintf("%s/config", git_dir)
	err := os.write_entire_file(config_path, transmute([]u8)config_content)
	testing.expect(t, err == nil, "should write .git/config")

	remotes := get_git_remotes(base, context.temp_allocator)

	testing.expect(t, len(remotes) == 2, "should find 2 remotes")
}

@(test)
test_get_git_remotes_no_config :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-remotes-none-*")
	defer os.remove_all(base)

	remotes := get_git_remotes(base, context.temp_allocator)

	testing.expect(t, len(remotes) == 0, "should return empty when no .git/config")
}

@(test)
test_get_git_remotes_no_remotes :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-remotes-empty-*")
	defer os.remove_all(base)

	git_dir := fmt.tprintf("%s/.git", base)
	os.mkdir_all(git_dir)

	config_content := "[core]\n\trepositoryformatversion = 0\n\tbare = false\n"
	config_path := fmt.tprintf("%s/config", git_dir)
	err := os.write_entire_file(config_path, transmute([]u8)config_content)
	testing.expect(t, err == nil, "should write .git/config")

	remotes := get_git_remotes(base, context.temp_allocator)

	testing.expect(t, len(remotes) == 0, "should return empty when no remote sections")
}

@(test)
test_new_env_file :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-envfile-*")
	defer os.remove_all(base)

	env_path := fmt.tprintf("%s/.env", base)
	err := os.write_entire_file(env_path, "SECRET=value\n")
	testing.expect(t, err == nil, ".env file should exists")

	file, ok := new_env_file(env_path)
	testing.expect(t, ok, "new_env_file should succeed")
	if !ok do return
	defer delete(file.contents)
	defer delete(file.remotes)
	defer delete(file.sha256)
	defer delete(file.path)

	testing.expect(t, filepath.is_abs(file.path), "path should be absolute")
	testing.expect(t, strings.has_suffix(file.path, "/.env"), "path should end with /.env")
	testing.expect(t, file.contents == "SECRET=value\n", "contents mismatch")
	testing.expect(t, len(file.sha256) == 64, "sha256 should be 64 hex chars")
}

@(test)
test_new_env_file_missing :: proc(t: ^testing.T) {
	_, ok := new_env_file("/tmp/envr-nonexistent-envfile/path/.env")
	testing.expect(t, !ok, "missing file should return false")
}

@(test)
test_closing_db_has_no_leaks :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-leak-*")
	defer os.remove_all(base)

	cfg_path, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect(t, err == nil, "cfgPath should build successfully")

	{
		cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
		testing.expect(t, save_config(cfg, force = true), "save should succeed")
		delete_config(&cfg)
	}

	db, ok := db_open(cfg_path)
	testing.expect(t, ok, "db should open")
	db_close(&db)
}

@(test)
test_open_existing_db_has_no_leaks :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-leak-existing-*")
	defer os.remove_all(base)

	cfg_path, err := filepath.join([]string{base, "config.json"}, context.temp_allocator)
	testing.expect(t, err == nil, "cfgPath should build successfully")

	{
		cfg := new_config([]string{"fixtures/keys/insecure-test-key"}, cfg_path)
		testing.expect(t, save_config(cfg, force = true), "save should succeed")
		delete_config(&cfg)
	}

	// First open/close creates data.envr on disk
	db, ok := db_open(cfg_path)
	testing.expect(t, ok, "db should open")
	if !ok do return
	f := make_test_env_file(
		"/project/.env",
		"abc123",
		"SECRET=value",
		[]string{"git@github.com:user/repo.git"},
	)
	defer delete(f.remotes)
	testing.expect(t, db_insert(&db, f), "insert should succeed")
	db_close(&db)

	// Second open exercises db_restore_from_encrypted
	db2, ok2 := db_open(cfg_path)
	testing.expect(t, ok2, "db should open existing")
	if !ok2 do return
	db_close(&db2)
}

@(test)
test_db_sync_noop :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-sync-noop-*")
	defer os.remove_all(base)

	env_path := fmt.tprintf("%s/.env", base)
	content := "KEY=value\n"
	write_err := os.write_entire_file(env_path, transmute([]u8)content)
	testing.expect(t, write_err == nil, "should write .env file")

	digest := hash.hash_bytes(
		hash.Algorithm.SHA256,
		transmute([]u8)content,
		context.temp_allocator,
	)
	hex_bytes := hex.encode(digest, context.temp_allocator)
	sha := string(hex_bytes)

	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	f := make_test_env_file(env_path, sha, content)
	f.dir = base
	db_insert(&db, f)

	result, sync_err := db_sync(&db, &f)
	testing.expect(t, sync_err == .None, "sync should not error")
	testing.expect(t, result == {}, "should be noop")
}

@(test)
test_db_sync_backed_up :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-sync-backup-*")
	defer os.remove_all(base)

	env_path := fmt.tprintf("%s/.env", base)
	changed_content := "KEY=changed\n"
	write_err := os.write_entire_file(env_path, transmute([]u8)changed_content)
	testing.expect(t, write_err == nil, "should write .env file")

	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	f := make_test_env_file(env_path, "old_sha", "KEY=original")
	f.dir = base
	db_insert(&db, f)

	result, sync_err := db_sync(&db, &f)
	testing.expect(t, sync_err == .None, "sync should not error")
	testing.expect(t, .BackedUp in result, "should be backed up")
}

@(test)
test_db_sync_restored :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-sync-restore-*")
	defer os.remove_all(base)

	env_path := fmt.tprintf("%s/.env", base)

	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	f := make_test_env_file(env_path, "some_sha", "SECRET=value")
	f.dir = base
	defer delete(f.remotes)
	db_insert(&db, f)

	result, err := db_sync(&db, &f)
	testing.expect(t, err == .None, "sync should not error")
	testing.expect(t, .Restored in result, "should be restored")

	data, read_err := os.read_entire_file_from_path(env_path, context.temp_allocator)
	testing.expect(t, read_err == nil, "file should exist after restore")
	if read_err == nil {
		testing.expect_value(t, string(data), "SECRET=value")
	}
}

@(test)
test_db_sync_dir_missing :: proc(t: ^testing.T) {
	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	f := make_test_env_file("/nonexistent/path/.env", "sha", "KEY=val")
	db_insert(&db, f)

	result, err := db_sync(&db, &f)
	testing.expect_value(t, err, SyncError.DirMissing)
	testing.expect_value(t, result, nil)
}

@(test)
test_db_sync_moved :: proc(t: ^testing.T) {
	base := test_temp_dir(t, "envr-test-sync-moved-*")
	search_root := fmt.tprintf("%s/search", base)
	repo_dir := fmt.tprintf("%s/myproject", search_root)
	git_dir := fmt.tprintf("%s/.git", repo_dir)
	defer os.remove_all(base)

	os.mkdir_all(git_dir)

	config_content := "[remote \"origin\"]\n\turl = git@github.com:user/repo.git\n"
	config_path := fmt.tprintf("%s/config", git_dir)
	write_err := os.write_entire_file(config_path, transmute([]u8)config_content)
	testing.expect(t, write_err == nil, "should write .git/config")

	db, ok := db_init()
	testing.expect(t, ok, "failed to create test db")
	defer db_close(&db)

	db.cfg.scan_config.include = make([dynamic]string, 0, 1, context.temp_allocator)
	append(&db.cfg.scan_config.include, search_root)

	f := make_test_env_file(
		"/old/nonexistent/path/.env",
		"some_sha",
		"SECRET=value",
		[]string{"git@github.com:user/repo.git"},
	)
	testing.expect(t, db_insert(&db, f), "insert should succeed")

	result, err := db_sync(&db, &f)
	testing.expect(t, err == .None, "sync should not error")
	if err != .None do return
	testing.expect(t, .DirUpdated in result, "should have DirUpdated flag")
	testing.expect(t, .Restored in result, "should have Restored flag")

	expected_path := fmt.tprintf("%s/.env", repo_dir)
	testing.expect_value(t, f.path, expected_path)
	testing.expect_value(t, f.dir, repo_dir)

	_, old_exists := db_fetch(&db, "/old/nonexistent/path/.env")
	testing.expect(t, !old_exists, "old path should be deleted from db")

	new_fetched, new_ok := db_fetch(&db, expected_path)
	testing.expect(t, new_ok, "new path should exist in db")
	if new_ok {
		testing.expect_value(t, new_fetched.contents, "SECRET=value")
	}
}

