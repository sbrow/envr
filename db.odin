package main

import "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/ini"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "sqlite"

SyncFlagEnum :: enum {
	Noop,
	DirUpdated,
	Restored,
	BackedUp,
	Error,
}

SyncFlag :: bit_set[SyncFlagEnum]

SyncDirection :: enum {
	TrustDatabase,
	TrustFilesystem,
}

Db :: struct {
	// Pointer to the sqlite db
	db:      ^rawptr,
	cfg:     Config,
	changed: bool,
}

EnvFile :: struct {
	Path:     string,
	Dir:      string,
	Remotes:  [dynamic]string,
	Sha256:   string,
	contents: string,
}

delete_envfile :: proc(f: ^EnvFile) {
	delete(f.Path)
	for &remote in f.Remotes {
		delete(remote)
	}
	delete(f.Remotes)
	delete(f.Sha256)
	delete(f.contents)
}


db_open :: proc(cfg_path: string) -> (Db, bool) {
	cfg, ok := load_config(cfg_path)
	if !ok {
		return Db{}, false
	}

	data_path := data_path(cfg.config_path)
	_, stat_err := os.stat(data_path, context.allocator)

	db: ^rawptr
	rc := sqlite.db_open(":memory:", &db)
	if rc != sqlite.OK {
		fmt.printf("Error opening in-memory database: %s\n", sqlite.db_errmsg(db))
		return Db{}, false
	}

	create_sql: cstring = "CREATE TABLE IF NOT EXISTS envr_env_files (path TEXT PRIMARY KEY NOT NULL, remotes TEXT, sha256 TEXT NOT NULL, contents TEXT NOT NULL)"
	rc = sqlite.db_exec(db, create_sql, nil, nil, nil)
	if rc != sqlite.OK {
		fmt.printf("Error creating table: %s\n", sqlite.db_errmsg(db))
		sqlite.db_close(db)
		return Db{}, false
	}

	if stat_err == nil {
		if !db_restore_from_encrypted(db, cfg) {
			sqlite.db_close(db)
			return Db{}, false
		}
	}

	return Db{db = db, cfg = cfg, changed = stat_err != nil}, true
}

db_close :: proc(d: ^Db) {
	defer sqlite.db_close(d.db)

	if d.changed {
		rc := sqlite.db_exec(d.db, "VACUUM", nil, nil, nil)
		if rc != sqlite.OK {
			fmt.printf("Error vacuuming database: %s\n", sqlite.db_errmsg(d.db))
			return
		}

		sz: i64
		data := sqlite.serialize(d.db, "main", &sz, 0)
		if data == nil {
			fmt.println("Error: failed to serialize database")
			return
		}
		defer sqlite.free(data)

		sqlite_data := data[:sz]
		encrypted, enc_ok := encrypt(sqlite_data, d.cfg.Keys[:])
		if !enc_ok {
			fmt.println("Error: encryption failed")
			return
		}

		data_path := data_path(d.cfg.config_path)
		envr_d := envr_dir(d.cfg.config_path)
		os.mkdir_all(envr_d)

		write_err := os.write_entire_file(data_path, encrypted)
		delete(encrypted)
		if write_err != nil {
			fmt.printf("Error writing encrypted database: %v\n", write_err)
			return
		}

		d.changed = false
	}
}

// Caller is responsible for calling:
// ```odin
// delete(results)
// for &result in results {
// 	delete(&result)
// }
// ```
db_list :: proc(d: ^Db, allocator := context.allocator) -> (results: [dynamic]EnvFile, ok: bool) {
	stmt: ^rawptr
	rc := sqlite.prepare_v2(
		d.db,
		"SELECT path, remotes, sha256, contents FROM envr_env_files",
		-1,
		&stmt,
		nil,
	)
	if rc != sqlite.OK {
		fmt.printf("Error preparing query: %s\n", sqlite.db_errmsg(d.db))
		return
	}
	defer sqlite.finalize(stmt)

	for {
		rc = sqlite.step(stmt)
		if rc == sqlite.DONE {
			break
		}
		if rc != sqlite.ROW {
			fmt.printf("Error stepping query: %s\n", sqlite.db_errmsg(d.db))
			return
		}

		remotes_json := string(sqlite.column_text(stmt, 1))
		remotes: [dynamic]string = ---
		if len(remotes_json) > 0 {
			json.unmarshal_string(remotes_json, &remotes, allocator = allocator)
		}
		path := clone_cstring(sqlite.column_text(stmt, 0), allocator)

		append(
			&results,
			EnvFile {
				Path = path,
				Dir = filepath.dir(path),
				Remotes = remotes,
				Sha256 = clone_cstring(sqlite.column_text(stmt, 2), allocator),
				contents = clone_cstring(sqlite.column_text(stmt, 3), allocator),
			},
		)
	}

	ok = true
	return
}

db_restore_from_encrypted :: proc(db: ^rawptr, cfg: Config) -> bool {
	encrypted_data, read_err := os.read_entire_file_from_path(
		data_path(cfg.config_path),
		context.allocator,
	)
	defer delete(encrypted_data)
	if read_err != nil {
		fmt.printf("Error reading encrypted database: %v\n", read_err)
		return false
	}

	plaintext, dec_ok := decrypt(encrypted_data, cfg.Keys[:])
	if !dec_ok {
		fmt.println("Error: decryption failed")
		return false
	}
	defer delete(plaintext)

	n := i64(len(plaintext))
	buf := sqlite.malloc64(n)
	if buf == nil {
		fmt.println("Error: failed to allocate buffer for deserialization")
		return false
	}
	copy(buf[:len(plaintext)], plaintext)

	rc := sqlite.deserialize(
		db,
		"main",
		buf,
		n,
		n,
		sqlite.DESERIALIZE_FREEONCLOSE | sqlite.DESERIALIZE_RESIZEABLE,
	)
	if rc != sqlite.OK {
		sqlite.free(buf)
		fmt.printf("Error deserializing database: %s\n", sqlite.db_errmsg(db))
		return false
	}

	return true
}


get_git_remotes :: proc(dir: string) -> [dynamic]string {
	remotes: [dynamic]string
	remote_set: map[string]bool
	defer delete(remote_set)

	config_path, _ := filepath.join({dir, ".git", "config"}, context.temp_allocator)
	m, _, ok := ini.load_map_from_path(config_path, context.allocator)
	if !ok {
		return remotes
	}
	defer ini.delete_map(m)

	for section_name, section in m {
		if strings.has_prefix(section_name, "remote ") {
			if url, ok := section["url"]; ok {
				remote_set[url] = true
			}
		}
	}

	for remote in remote_set {
		cloned, _ := strings.clone(remote)
		append(&remotes, cloned)
	}

	return remotes
}

new_env_file :: proc(path: string) -> (EnvFile, bool) {
	abs_path, abs_err := filepath.abs(path)
	if abs_err != nil {
		fmt.printf("Error getting absolute path: %v\n", abs_err)
		return EnvFile{}, false
	}

	dir := filepath.dir(abs_path)

	remotes := get_git_remotes(dir)

	data, read_err := os.read_entire_file_from_path(abs_path, context.allocator)
	defer delete(data)
	if read_err != nil {
		fmt.printf("Error reading file %s: %v\n", abs_path, read_err)
		return EnvFile{}, false
	}

	digest := hash.hash_bytes(hash.Algorithm.SHA256, data, context.temp_allocator)
	// TODO: Handle error
	hex_bytes, _ := hex.encode(digest)

	return EnvFile {
			Path = abs_path,
			Dir = dir,
			Remotes = remotes,
			Sha256 = string(hex_bytes),
			contents = string(data),
		},
		true
}

db_insert :: proc(d: ^Db, file: EnvFile) -> bool {
	remotes_json, marshal_err := json.marshal(file.Remotes)
	if marshal_err != nil {
		fmt.printf("Error marshaling remotes: %v\n", marshal_err)
		return false
	}
	defer delete(remotes_json)

	sql: cstring =
		"INSERT OR REPLACE INTO " +
		"envr_env_files (path, remotes, sha256, contents) VALUES (?, ?, ?, ?)"
	stmt: ^rawptr
	rc := sqlite.prepare_v2(d.db, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.printf("Error preparing insert: %s\n", sqlite.db_errmsg(d.db))
		return false
	}
	defer sqlite.finalize(stmt)

	// TODO: deal with elsewhere?
	cpath := to_cstring(file.Path)
	defer delete(cpath)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding path: %s\n", sqlite.db_errmsg(d.db))
		return false
	}

	cremotes := to_cstring(string(remotes_json))
	defer delete(cremotes)
	rc = sqlite.bind_text(stmt, 2, cremotes, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding remotes: %s\n", sqlite.db_errmsg(d.db))
		return false
	}

	csha := to_cstring(file.Sha256)
	defer delete(csha)
	rc = sqlite.bind_text(stmt, 3, csha, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding sha256: %s\n", sqlite.db_errmsg(d.db))
		return false
	}

	ccontents := to_cstring(file.contents)
	defer delete(ccontents)
	rc = sqlite.bind_text(stmt, 4, ccontents, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding contents: %s\n", sqlite.db_errmsg(d.db))
		return false
	}

	rc = sqlite.step(stmt)
	if rc != sqlite.DONE {
		fmt.printf("Error inserting: %s\n", sqlite.db_errmsg(d.db))
		return false
	}

	d.changed = true
	return true
}

db_fetch :: proc(d: ^Db, path: string, allocator := context.allocator) -> (EnvFile, bool) {
	sql: cstring = "SELECT path, remotes, sha256, contents FROM envr_env_files WHERE path = ?"
	stmt: ^rawptr
	rc := sqlite.prepare_v2(d.db, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.printf("Error preparing fetch: %s\n", sqlite.db_errmsg(d.db))
		return EnvFile{}, false
	}
	defer sqlite.finalize(stmt)

	cpath := to_cstring(path, allocator)
	defer delete(cpath, allocator)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding path: %s\n", sqlite.db_errmsg(d.db))
		return EnvFile{}, false
	}
	rc = sqlite.step(stmt)
	if rc == sqlite.DONE {
		fmt.printf("No file found with path: %s\n", path)
		return EnvFile{}, false
	}
	if rc != sqlite.ROW {
		fmt.printf("Error fetching: %s\n", sqlite.db_errmsg(d.db))
		return EnvFile{}, false
	}

	remotes_json := string(sqlite.column_text(stmt, 1))
	remotes: [dynamic]string = ---
	if len(remotes_json) > 0 {
		json.unmarshal_string(remotes_json, &remotes, allocator = allocator)
	}

	file_path := clone_cstring(sqlite.column_text(stmt, 0))

	return EnvFile {
			Path = file_path,
			Dir = filepath.dir(file_path),
			Remotes = remotes,
			Sha256 = clone_cstring(sqlite.column_text(stmt, 2), allocator),
			contents = clone_cstring(sqlite.column_text(stmt, 3), allocator),
		},
		true
}

db_delete :: proc(d: ^Db, path: string) -> bool {
	sql: cstring = "DELETE FROM envr_env_files WHERE path = ?"
	stmt: ^rawptr
	rc := sqlite.prepare_v2(d.db, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.printf("Error preparing delete: %s\n", sqlite.db_errmsg(d.db))
		return false
	}
	defer sqlite.finalize(stmt)

	cpath := to_cstring(path)
	defer delete(cpath)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding path: %s\n", sqlite.db_errmsg(d.db))
		return false
	}
	rc = sqlite.step(stmt)
	if rc != sqlite.DONE {
		fmt.printf("Error deleting: %s\n", sqlite.db_errmsg(d.db))
		return false
	}

	if sqlite.changes(d.db) == 0 {
		fmt.printf("No file found with path: %s\n", path)
		return false
	}

	d.changed = true
	return true
}

to_cstring :: proc {
	string_to_cstring,
	strings.to_cstring,
}

string_to_cstring :: proc(s: string, allocator := context.allocator) -> cstring {
	cs, err := strings.clone_to_cstring(s, allocator)
	if err != nil {
		fmt.printf("Failed to convert string to cstring: %v\n", err)
		panic("Allocation Exception")
	}
	return cs
}

clone_cstring :: proc(c: cstring, allocator := context.allocator) -> string {
	str, err := strings.clone_from_cstring(c, allocator)
	if err != nil {
		fmt.printf("Failed to convert string to cstring: %v\n", err)
		delete(str)
		panic("Allocation Exception")
	}

	return str
}

db_update_required :: proc(status: SyncFlag) -> bool {
	return .BackedUp in status || .DirUpdated in status
}

shares_remote :: proc(f: ^EnvFile, remotes: []string) -> bool {
	for r1 in f.Remotes {
		for r2 in remotes {
			if r1 == r2 {
				return true
			}
		}
	}
	return false
}

update_dir :: proc(f: ^EnvFile, new_dir: string) {
	f.Dir = new_dir
	base := filepath.base(f.Path)
	new_path, _ := strings.concatenate({new_dir, "/", base})
	f.Path = new_path
	f.Remotes = get_git_remotes(new_dir)
}

find_moved_dirs :: proc(d: ^Db, f: ^EnvFile) -> ([dynamic]string, bool) {
	roots, roots_ok := find_git_roots(d.cfg)
	if !roots_ok {
		return {}, false
	}

	moved: [dynamic]string
	for root in roots {
		remotes := get_git_remotes(root)
		if shares_remote(f, remotes[:]) {
			cloned, _ := strings.clone(root)
			append(&moved, cloned)
		}
	}
	return moved, true
}

db_sync :: proc(d: ^Db, f: ^EnvFile) -> (SyncFlag, string) {
	return env_file_sync(f, .TrustFilesystem, d)
}

// If SyncFlag is .BackedUp, Caller is responsible for calling delete on f.contents and f.Sha256
env_file_sync :: proc(f: ^EnvFile, dir: SyncDirection, d: ^Db) -> (SyncFlag, string) {
	result: SyncFlag = {}

	_, stat_err := os.stat(f.Dir, context.allocator)
	if stat_err != nil {
		moved_dirs: [dynamic]string

		if d != nil {
			dirs, dirs_ok := find_moved_dirs(d, f)
			if !dirs_ok {
				return {.Error}, "failed to find moved dirs"
			}
			moved_dirs = dirs
		}

		if len(moved_dirs) == 0 {
			return {.Error}, "directory missing"
		} else if len(moved_dirs) == 1 {
			update_dir(f, moved_dirs[0])
			result = {.DirUpdated}
		} else {
			return {.Error}, "multiple directories found"
		}
	}

	_, file_stat_err := os.stat(f.Path, context.allocator)
	if file_stat_err != nil {
		write_err := os.write_entire_file(f.Path, f.contents)
		if write_err != nil {
			msg, _ := strings.concatenate({"failed to write file: ", fmt.tprintf("%v", write_err)})
			return {.Error}, msg
		}

		return result + {.Restored}, ""
	}

	data, read_err := os.read_entire_file_from_path(f.Path, context.allocator)
	if read_err != nil {
		msg, _ := strings.concatenate(
			{"failed to read file for SHA comparison: ", fmt.tprintf("%v", read_err)},
		)
		return {.Error}, msg
	}

	digest := hash.hash_bytes(hash.Algorithm.SHA256, data)
	// TODO: Handle error
	hex_bytes, _ := hex.encode(digest)
	current_sha := string(hex_bytes)

	if current_sha == f.Sha256 {
		return result, ""
	}

	switch dir {
	case .TrustDatabase:
		write_err := os.write_entire_file(f.Path, f.contents)
		if write_err != nil {
			msg, _ := strings.concatenate({"failed to write file: ", fmt.tprintf("%v", write_err)})
			return {.Error}, msg
		}
		return result + {.Restored}, ""
	case .TrustFilesystem:
		if !env_file_backup(f) {
			return {.Error}, "failed to backup file"
		}
		return result + {.BackedUp}, ""
	}

	return result, ""
}

// Loads the contents of the the file at f.Path into f.contents
//
// Caller is responsible for calling delete on f.contents and f.Sha256
env_file_backup :: proc(f: ^EnvFile) -> bool {
	data, read_err := os.read_entire_file_from_path(f.Path, context.allocator)
	if read_err != nil {
		fmt.printf("Error reading file %s: %v\n", f.Path, read_err)
		return false
	}

	f.contents = string(data)
	digest := hash.hash_bytes(hash.Algorithm.SHA256, data, context.temp_allocator)
	hex_bytes, alloc_err := hex.encode(digest)
	if alloc_err != nil {
		fmt.printf("Error generating hash for file %s: %v\n", f.Path, alloc_err)
		return false
	}
	f.Sha256 = string(hex_bytes)
	return true
}

