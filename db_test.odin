package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "sqlite"

make_test_db :: proc() -> (Db, bool) {
	db: ^rawptr
	rc := sqlite.db_open(":memory:", &db)
	if rc != sqlite.OK {
		return Db{}, false
	}

	create_sql := "CREATE TABLE IF NOT EXISTS envr_env_files (path TEXT PRIMARY KEY NOT NULL, remotes TEXT, sha256 TEXT NOT NULL, contents TEXT NOT NULL)"
	rc = sqlite.db_exec(db, string_to_cstring(create_sql), nil, nil, nil)
	if rc != sqlite.OK {
		sqlite.db_close(db)
		return Db{}, false
	}

	return Db{db = db}, true
}

make_test_env_file :: proc(path, sha, contents: string, remotes: []string = {}) -> EnvFile {
	f := EnvFile {
		Path     = path,
		Dir      = "",
		Sha256   = sha,
		contents = contents,
		Remotes  = make([dynamic]string, 0, len(remotes)),
	}
	for r in remotes {
		append(&f.Remotes, r)
	}
	return f
}

@(test)
test_db_insert_and_fetch :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	f := make_test_env_file(
		"/project/.env",
		"abc123",
		"SECRET=value",
		[]string{"git@github.com:user/repo.git"},
	)
	defer delete(f.Remotes)

	testing.expect(t, db_insert(&d, f), "insert should succeed")

	fetched, fetch_ok := db_fetch(&d, "/project/.env")
	testing.expect(t, fetch_ok, "fetch should succeed")
	if !fetch_ok do return
	defer delete(fetched.Remotes)

	testing.expect(t, fetched.Path == "/project/.env", "path mismatch")
	testing.expect(t, fetched.Sha256 == "abc123", "sha mismatch")
	testing.expect(t, fetched.contents == "SECRET=value", "contents mismatch")
	testing.expect(t, len(fetched.Remotes) == 1, "remotes count mismatch")
	testing.expect(t, fetched.Remotes[0] == "git@github.com:user/repo.git", "remote mismatch")
}

@(test)
test_db_fetch_missing :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	_, fetch_ok := db_fetch(&d, "/nonexistent/.env")
	testing.expect(t, !fetch_ok, "fetch missing should return false")
}

@(test)
test_db_insert_or_replace :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	f1 := make_test_env_file("/project/.env", "sha1", "KEY=old")
	defer delete(f1.Remotes)
	testing.expect(t, db_insert(&d, f1), "first insert should succeed")

	f2 := make_test_env_file("/project/.env", "sha2", "KEY=new")
	defer delete(f2.Remotes)
	testing.expect(t, db_insert(&d, f2), "second insert should succeed")

	results, list_ok := db_list(&d)
	testing.expect(t, list_ok, "list should succeed")
	if !list_ok do return
	defer delete(results)

	testing.expect(t, len(results) == 1, "should have 1 row, not 2")

	fetched, fetch_ok := db_fetch(&d, "/project/.env")
	testing.expect(t, fetch_ok, "fetch should succeed")
	if !fetch_ok do return
	defer delete(fetched.Remotes)

	testing.expect(t, fetched.contents == "KEY=new", "contents should be updated")
	testing.expect(t, fetched.Sha256 == "sha2", "sha should be updated")
}

@(test)
test_db_delete_existing :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.Remotes)
	db_insert(&d, f)

	testing.expect(t, db_delete(&d, "/project/.env"), "delete should return true")

	_, fetch_ok := db_fetch(&d, "/project/.env")
	testing.expect(t, !fetch_ok, "row should be gone after delete")
}

@(test)
test_db_delete_missing :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	testing.expect(t, !db_delete(&d, "/nonexistent/.env"), "delete missing should return false")
}

@(test)
test_db_list_multiple :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	f1 := make_test_env_file("/proj1/.env", "sha1", "A=1", []string{"git@github.com:a/repo.git"})
	f2 := make_test_env_file("/proj2/.env", "sha2", "B=2", []string{"git@github.com:b/repo.git"})
	f3 := make_test_env_file("/proj3/.env", "sha3", "C=3")
	defer delete(f1.Remotes)
	defer delete(f2.Remotes)
	defer delete(f3.Remotes)

	db_insert(&d, f1)
	db_insert(&d, f2)
	db_insert(&d, f3)

	results, list_ok := db_list(&d)
	testing.expect(t, list_ok, "list should succeed")
	if !list_ok do return
	defer delete(results)

	testing.expect(t, len(results) == 3, "should have 3 rows")
}

@(test)
test_db_list_empty :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	results, list_ok := db_list(&d)
	testing.expect(t, list_ok, "list should succeed on empty db")
	testing.expect(t, len(results) == 0, "should have 0 rows")
	if list_ok do delete(results)
}

@(test)
test_db_insert_sets_changed :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	testing.expect(t, !d.changed, "changed should start false")

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.Remotes)
	db_insert(&d, f)

	testing.expect(t, d.changed, "changed should be true after insert")
}

@(test)
test_db_delete_sets_changed :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.Remotes)
	db_insert(&d, f)
	d.changed = false

	db_delete(&d, "/project/.env")
	testing.expect(t, d.changed, "changed should be true after delete")
}

@(test)
test_db_vacuum_to_file :: proc(t: ^testing.T) {
	d, ok := make_test_db()
	testing.expect(t, ok, "failed to create test db")
	if !ok do return
	defer sqlite.db_close(d.db)

	f := make_test_env_file("/project/.env", "sha", "KEY=val")
	defer delete(f.Remotes)
	db_insert(&d, f)

	vacuum_path := fmt.tprintf("/tmp/envr-test-vacuum-%d.db", os.get_pid())
	defer os.remove(vacuum_path)

	testing.expect(t, db_vacuum_to_file(d.db, vacuum_path), "vacuum should succeed")

	_, stat_err := os.stat(vacuum_path, context.allocator)
	testing.expect(t, stat_err == nil, "vacuumed file should exist")
	if stat_err != nil do return

	data, read_err := os.read_entire_file_from_path(vacuum_path, context.allocator)
	testing.expect(t, read_err == nil, "should read vacuumed file")
	if read_err != nil do return
	defer delete(data)

	testing.expect(t, len(data) > 0, "vacuumed file should be non-empty")
}

@(test)
test_db_update_required_noop :: proc(t: ^testing.T) {
	testing.expect(t, !db_update_required({}), "Noop should not require update")
}

@(test)
test_db_update_required_backed_up :: proc(t: ^testing.T) {
	testing.expect(t, db_update_required({.BackedUp}), "BackedUp should require update")
}

@(test)
test_db_update_required_dir_updated :: proc(t: ^testing.T) {
	testing.expect(t, db_update_required({.DirUpdated}), "DirUpdated should require update")
}

@(test)
test_db_update_required_restored :: proc(t: ^testing.T) {
	testing.expect(t, !db_update_required({.Restored}), "Restored alone should not require update")
}

@(test)
test_db_update_required_error :: proc(t: ^testing.T) {
	testing.expect(t, !db_update_required({.Error}), "Error alone should not require update")
}

@(test)
test_db_update_required_combined :: proc(t: ^testing.T) {
	combined := SyncFlag{.DirUpdated, .Restored}
	testing.expect(t, db_update_required(combined), "DirUpdated|Restored should require update")
}

@(test)
test_shares_remote_overlap :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 2, context.temp_allocator),
	}
	append(&f.Remotes, "git@github.com:user/repo.git")
	append(&f.Remotes, "git@gitlab.com:user/repo.git")

	remotes := []string{"git@github.com:user/repo.git"}
	testing.expect(t, shares_remote(&f, remotes), "should share remote")
}

@(test)
test_shares_remote_no_overlap :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 1, context.temp_allocator),
	}
	append(&f.Remotes, "git@github.com:user/repo.git")

	remotes := []string{"git@github.com:other/repo.git"}
	testing.expect(t, !shares_remote(&f, remotes), "should not share remote")
}

@(test)
test_shares_remote_empty_file_remotes :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 0, context.temp_allocator),
	}

	remotes := []string{"git@github.com:user/repo.git"}
	testing.expect(t, !shares_remote(&f, remotes), "empty file remotes should not share")
}

@(test)
test_shares_remote_empty_check_remotes :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 1, context.temp_allocator),
	}
	append(&f.Remotes, "git@github.com:user/repo.git")

	remotes: []string
	testing.expect(t, !shares_remote(&f, remotes), "empty check remotes should not share")
}

@(test)
test_shares_remote_both_empty :: proc(t: ^testing.T) {
	f := EnvFile {
		Remotes = make([dynamic]string, 0),
	}

	remotes: []string
	testing.expect(t, !shares_remote(&f, remotes), "both empty should not share")
}

@(test)
test_make_temp_path_format :: proc(t: ^testing.T) {
	p := make_temp_path()
	testing.expect(t, strings.has_suffix(p, ".db"), "should end with .db")
	testing.expect(t, strings.contains(p, fmt.tprintf("%d", os.get_pid())), "should contain PID")
}

@(test)
test_new_env_file :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/envr-test-envfile-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	env_path := fmt.tprintf("%s/.env", base)
	err := os.write_entire_file(env_path, "SECRET=value\n")
	testing.expect(t, err == nil, ".env file should exists")

	file, ok := new_env_file(env_path)
	testing.expect(t, ok, "new_env_file should succeed")
	if !ok do return
	defer delete(file.Remotes)

	testing.expect(t, filepath.is_abs(file.Path), "path should be absolute")
	testing.expect(t, strings.has_suffix(file.Path, "/.env"), "path should end with /.env")
	testing.expect(t, file.contents == "SECRET=value\n", "contents mismatch")
	testing.expect(t, len(file.Sha256) == 64, "sha256 should be 64 hex chars")
}

@(test)
test_new_env_file_missing :: proc(t: ^testing.T) {
	_, ok := new_env_file("/tmp/envr-nonexistent-envfile/path/.env")
	testing.expect(t, !ok, "missing file should return false")
}

@(test)
test_env_file_backup :: proc(t: ^testing.T) {
	base := fmt.tprintf("/tmp/envr-test-backup-%d", os.get_pid())
	os.mkdir_all(base)
	defer os.remove_all(base)

	env_path := fmt.tprintf("%s/.env", base)
	err := os.write_entire_file(env_path, "KEY=12345\n")
	testing.expect(t, err == nil, ".env file should exist")

	f := EnvFile {
		Path = env_path,
	}
	testing.expect(t, env_file_backup(&f), "backup should succeed")
	testing.expect(t, f.contents == "KEY=12345\n", "contents should be populated")
	testing.expect(t, len(f.Sha256) == 64, "sha256 should be 64 hex chars")
}

@(test)
test_env_file_backup_missing :: proc(t: ^testing.T) {
	f := EnvFile {
		Path = "/tmp/envr-nonexistent-backup/.env",
	}
	testing.expect(t, !env_file_backup(&f), "missing file should return false")
}

@(test)
test_update_dir :: proc(t: ^testing.T) {
	f := EnvFile {
		Path    = "/old/project/.env",
		Dir     = "/old/project",
		Remotes = make([dynamic]string, 0),
	}
	defer delete(f.Remotes)

	update_dir(&f, "/new/location")

	testing.expect(t, f.Dir == "/new/location", "dir should be updated")
	testing.expect(t, f.Path == "/new/location/.env", "path should be updated")
}

