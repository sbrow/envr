package main

import "base:runtime"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/ini"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "sqlite"

SyncFlagEnum :: enum {
	DirUpdated,
	Restored,
	BackedUp,
}

SyncFlag :: bit_set[SyncFlagEnum]

SyncError :: enum {
	None,
	DirMissing,
	MultipleDirs,
	GitRootFailed,
	WriteFailed,
	ReadFailed,
	DbFailed,
}

Db :: struct {
	conn:    sqlite.Db,
	cfg:     Config,
	changed: bool,
	arena:   mem.Dynamic_Arena,
}

EnvFile :: struct {
	Path:     string,
	Dir:      string,
	Remotes:  [dynamic]string,
	Sha256:   string,
	contents: string,
}

@(deprecated = "call db_close to clean up EnvFiles")
delete_envfile :: proc(f: ^EnvFile) {
	delete(f.Path)
	for &remote in f.Remotes {
		delete(remote)
	}
	delete(f.Remotes)
	delete(f.Sha256)
	delete(f.contents)
}

db_open :: proc(cfg_path: string) -> (db: Db, ok: bool) {
	db = db_init() or_return
	db.cfg = load_config(cfg_path, db_allocator(&db)) or_return

	// TODO: Use different allocators?
	data_path := data_path(db.cfg.config_path, context.temp_allocator)
	if os.exists(data_path) {
		if ok = db_restore_from_encrypted(&db, data_path); !ok {
			sqlite.close(db.conn)
			return db, false
		}
	} else {
		// DB was created
		db.changed = true
	}

	return db, true
}

// Creates a database an allocator and fresh, empty table, with zero encryption.
// In production, you most likely want to use `db_open`.
db_init :: proc() -> (db: Db, ok: bool) {
	conn: sqlite.Db
	rc := sqlite.open(":memory:", &conn)
	if rc != sqlite.OK {
		fmt.printf("Error opening in-memory database: %s\n", sqlite.errmsg(conn))
		return
	}

	create_sql: cstring = "CREATE TABLE IF NOT EXISTS envr_env_files (path TEXT PRIMARY KEY NOT NULL, remotes TEXT, sha256 TEXT NOT NULL, contents TEXT NOT NULL)"
	rc = sqlite.exec(conn, create_sql, nil, nil, nil)
	if rc != sqlite.OK {
		fmt.printf("Error creating table: %s\n", sqlite.errmsg(conn))
		sqlite.close(conn)
		return
	}
	db.conn = conn

	mem.dynamic_arena_init(&db.arena)

	return db, true
}

db_allocator :: proc(db: ^Db) -> mem.Allocator {
	return mem.dynamic_arena_allocator(&db.arena)
}

db_restore_from_encrypted :: proc(db: ^Db, data_path: string) -> bool {
	encrypted_data, read_err := os.read_entire_file_from_path(data_path, context.temp_allocator)
	if read_err != nil {
		fmt.printf("Error reading encrypted database: %v\n", read_err)
		return false
	}

	// TODO: Use context.temp_allocator
	plaintext, dec_ok := decrypt(encrypted_data, db.cfg.keys[:])
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

	flags: sqlite.DESERIALIZE_FLAGS = {.FREEONCLOSE, .RESIZEABLE}

	rc := sqlite.deserialize(db.conn, "main", buf, n, n, flags)
	if rc != sqlite.OK {
		sqlite.free(buf)
		fmt.printf("Error deserializing database: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	return true
}

db_close :: proc(db: ^Db) {
	allocator := db_allocator(db)

	defer {
		sqlite.close(db.conn)

		delete_config(&db.cfg, allocator)

		mem.dynamic_arena_destroy(&db.arena)
	}

	if db.changed {
		rc := sqlite.exec(db.conn, "VACUUM", nil, nil, nil)
		if rc != sqlite.OK {
			fmt.printf("Error vacuuming database: %s\n", sqlite.errmsg(db.conn))
			return
		}

		sz: i64
		data := sqlite.serialize(db.conn, "main", &sz, 0)
		if data == nil {
			fmt.println("Error: failed to serialize database")
			return
		}
		defer sqlite.free(data)

		sqlite_data := data[:sz]
		// TODO: PAss allocator chain
		encrypted, enc_ok := encrypt(sqlite_data, db.cfg.keys[:])
		if !enc_ok {
			fmt.println("Error: encryption failed")
			return
		}

		data_path := data_path(db.cfg.config_path, allocator)
		envr_d := envr_dir(db.cfg.config_path)
		os.mkdir_all(envr_d)

		write_err := os.write_entire_file(data_path, encrypted)
		delete(encrypted)
		if write_err != nil {
			fmt.printf("Error writing encrypted database: %v\n", write_err)
			return
		}

		db.changed = false
	}
}

// Results will be freed when `db_close` is called.
db_list :: proc(db: ^Db) -> ([]EnvFile, bool) {
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(
		db.conn,
		"SELECT path, remotes, sha256, contents FROM envr_env_files",
		-1,
		&stmt,
		nil,
	)
	if rc != sqlite.OK {
		fmt.printf("Error preparing query: %s\n", sqlite.errmsg(db.conn))
		return []EnvFile{}, false
	}
	defer sqlite.finalize(stmt)

	allocator := db_allocator(db)
	results := make([dynamic]EnvFile, 0, 10, allocator)

	for {
		rc = sqlite.step(stmt)
		if rc == sqlite.DONE {
			break
		}
		if rc != sqlite.ROW {
			fmt.printf("Error stepping query: %s\n", sqlite.errmsg(db.conn))
			#no_bounds_check return results[:], false
		}

		remotes_json := string(sqlite.column_text(stmt, 1))
		remotes: [dynamic]string = ---
		if len(remotes_json) > 0 {
			err := json.unmarshal_string(remotes_json, &remotes, allocator = allocator)
			if err != nil {
				fmt.eprintf("Warning: malformed remotes JSON: %v\n", err)
			}
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

	#no_bounds_check return results[:], true
}

// TODO: Should we use context.temp_allocator for proc scoped lifetimes?
db_insert :: proc(db: ^Db, file: EnvFile) -> bool {
	remotes_json, marshal_err := json.marshal(file.Remotes, allocator = context.temp_allocator)
	if marshal_err != nil {
		fmt.printf("Error marshaling remotes: %v\n", marshal_err)
		return false
	}

	sql: cstring =
		"INSERT OR REPLACE INTO " +
		"envr_env_files (path, remotes, sha256, contents) VALUES (?, ?, ?, ?)"
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(db.conn, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.printf("Error preparing insert: %s\n", sqlite.errmsg(db.conn))
		return false
	}
	defer sqlite.finalize(stmt)

	// TODO: deal with elsewhere?
	cpath := to_cstring(file.Path)
	defer delete(cpath)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding path: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	cremotes := to_cstring(string(remotes_json))
	defer delete(cremotes)
	rc = sqlite.bind_text(stmt, 2, cremotes, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding remotes: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	csha := to_cstring(file.Sha256)
	defer delete(csha)
	rc = sqlite.bind_text(stmt, 3, csha, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding sha256: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	ccontents := to_cstring(file.contents)
	defer delete(ccontents)
	rc = sqlite.bind_text(stmt, 4, ccontents, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding contents: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	rc = sqlite.step(stmt)
	if rc != sqlite.DONE {
		fmt.printf("Error inserting: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	db.changed = true
	return true
}

// Result will be freed when `db_close` is called.
db_fetch :: proc(db: ^Db, path: string) -> (EnvFile, bool) {
	sql: cstring = "SELECT path, remotes, sha256, contents FROM envr_env_files WHERE path = ?"
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(db.conn, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.printf("Error preparing fetch: %s\n", sqlite.errmsg(db.conn))
		return EnvFile{}, false
	}
	defer sqlite.finalize(stmt)

	allocator := db_allocator(db)

	cpath := to_cstring(path, allocator)
	defer delete(cpath, allocator)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding path: %s\n", sqlite.errmsg(db.conn))
		return EnvFile{}, false
	}
	rc = sqlite.step(stmt)
	if rc == sqlite.DONE {
		fmt.printf("No file found with path: %s\n", path)
		return EnvFile{}, false
	}
	if rc != sqlite.ROW {
		fmt.printf("Error fetching: %s\n", sqlite.errmsg(db.conn))
		return EnvFile{}, false
	}

	remotes_json := string(sqlite.column_text(stmt, 1))
	remotes: [dynamic]string = ---
	if len(remotes_json) > 0 {
		err := json.unmarshal_string(remotes_json, &remotes, allocator = allocator)
		if err != nil {
			fmt.eprintf("Warning: malformed remotes JSON: %v\n", err)
		}
	}

	file_path := clone_cstring(sqlite.column_text(stmt, 0), allocator)

	return EnvFile {
			Path = file_path,
			Dir = filepath.dir(file_path),
			Remotes = remotes,
			Sha256 = clone_cstring(sqlite.column_text(stmt, 2), allocator),
			contents = clone_cstring(sqlite.column_text(stmt, 3), allocator),
		},
		true
}

db_delete :: proc(db: ^Db, path: string) -> bool {
	sql: cstring = "DELETE FROM envr_env_files WHERE path = ?"
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(db.conn, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.printf("Error preparing delete: %s\n", sqlite.errmsg(db.conn))
		return false
	}
	defer sqlite.finalize(stmt)

	cpath := to_cstring(path)
	defer delete(cpath)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.printf("Error binding path: %s\n", sqlite.errmsg(db.conn))
		return false
	}
	rc = sqlite.step(stmt)
	if rc != sqlite.DONE {
		fmt.printf("Error deleting: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	if sqlite.changes(db.conn) == 0 {
		fmt.printf("No file found with path: %s\n", path)
		return false
	}

	db.changed = true
	return true
}

new_env_file :: proc(path: string) -> (EnvFile, bool) {
	abs_path, abs_err := filepath.abs(path)
	if abs_err != nil {
		fmt.printf("Error getting absolute path: %v\n", abs_err)
		return EnvFile{}, false
	}

	dir := filepath.dir(abs_path)

	// TODO: Should we use the db allocator here?
	remotes := get_git_remotes(dir, context.allocator)

	data, read_err := os.read_entire_file_from_path(abs_path, context.allocator)
	defer delete(data)
	if read_err != nil {
		fmt.printf("Error reading file %s: %v\n", abs_path, read_err)
		return EnvFile{}, false
	}

	digest := hash.hash_bytes(hash.Algorithm.SHA256, data, context.temp_allocator)
	hex_bytes := hex.encode(digest, context.allocator)
	return EnvFile {
			Path = abs_path,
			Dir = dir,
			Remotes = remotes,
			Sha256 = string(hex_bytes),
			contents = string(data),
		},
		true
}

// Reconciles `f` with the filesystem and persists changes to the database.
db_sync :: proc(db: ^Db, f: ^EnvFile) -> (SyncFlag, SyncError) {
	allocator := db_allocator(db)
	result: SyncFlag = {}
	old_path := f.Path

	if !os.exists(f.Dir) {
		moved, err := try_move_dir(db, f, allocator)
		if !moved {
			return {}, err
		}
		result += {.DirUpdated}
	}

	if !os.exists(f.Path) {
		write_err := os.write_entire_file(f.Path, f.contents)
		if write_err != nil {
			fmt.eprintf("db_sync: failed to write %s: %v\n", f.Path, write_err)
			return result, .WriteFailed
		}

		if !db_persist(db, f, old_path) {
			return result, .DbFailed
		}
		return result + {.Restored}, .None
	}

	data, read_err := os.read_entire_file_from_path(f.Path, allocator)
	if read_err != nil {
		fmt.eprintf("db_sync: failed to read %s: %v\n", f.Path, read_err)
		return result, .ReadFailed
	}

	digest := hash.hash_bytes(hash.Algorithm.SHA256, data, context.temp_allocator)
	hex_bytes := hex.encode(digest, allocator)
	current_sha := string(hex_bytes)

	if current_sha == f.Sha256 {
		if !db_persist(db, f, old_path) {
			return result, .DbFailed
		}
		return result, .None
	}

	f.contents = string(data)
	f.Sha256 = current_sha
	if !db_persist(db, f, old_path) {
		return result, .DbFailed
	}
	return result + {.BackedUp}, .None
}

db_persist :: proc(db: ^Db, f: ^EnvFile, old_path: string) -> bool {
	if f.Path != old_path {
		if !db_delete(db, old_path) {
			return false
		}
	}
	return db_insert(db, f^)
}

try_move_dir :: proc(db: ^Db, f: ^EnvFile, allocator: mem.Allocator) -> (bool, SyncError) {
	roots, ok := find_git_roots(db.cfg)
	if !ok {
		return false, .GitRootFailed
	}
	defer {
		for root in roots {
			delete(root)
		}
		delete(roots)
	}

	match_count := 0
	matched_dir: string
	for root in roots {
		remotes := get_git_remotes(root, context.temp_allocator)
		if shares_remote(f, remotes[:]) {
			match_count += 1
			matched_dir = root
		}
	}

	switch match_count {
	case 0:
		return false, .DirMissing
	case 1:
		f.Dir, _ = strings.clone(matched_dir, allocator)
		base := filepath.base(f.Path)
		new_path, _ := filepath.join({f.Dir, base}, allocator)
		f.Path = new_path
		f.Remotes = get_git_remotes(f.Dir, allocator)
		return true, .None
	case:
		return false, .MultipleDirs
	}
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

get_git_remotes :: proc(dir: string, allocator: mem.Allocator) -> [dynamic]string {
	config_path, _ := filepath.join({dir, ".git", "config"}, context.temp_allocator)
	// TODO: Handle error
	m, _, read_ok := ini.load_map_from_path(config_path, context.temp_allocator)
	if !read_ok {
		return nil
	}

	remotes := make([dynamic]string, 0, 1, allocator)

	for section_name, section in m {
		if strings.has_prefix(section_name, "remote ") {
			if url, ok := section["url"]; ok {
				found := false
				for r in remotes {
					if r == url {found = true; break}
				}
				if !found {
					// FIXME: Currently leaks when adding a file with envr scan
					cloned, _ := strings.clone(url, allocator)
					append(&remotes, cloned)
				}
			}
		}
	}

	return remotes
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

// Unless an explicit allocator is passed, caller is responsible for freeing the result
clone_cstring :: proc(c: cstring, allocator := context.allocator) -> string {
	str, err := strings.clone_from_cstring(c, allocator)
	if err != nil {
		fmt.printf("Failed to convert string to cstring: %v\n", err)
		delete(str)
		panic("Allocation Exception")
	}

	return str
}

