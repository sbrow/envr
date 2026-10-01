package main

import "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/ini"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:path/slashpath"
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
	path:     string,
	dir:      string,
	remotes:  [dynamic]string,
	sha256:   string,
	contents: string,
}

@(deprecated = "call db_close to clean up EnvFiles")
delete_envfile :: proc(f: ^EnvFile) {
	delete(f.path)
	for &remote in f.remotes {
		delete(remote)
	}
	delete(f.remotes)
	delete(f.sha256)
	delete(f.contents)
}

db_open :: proc(cfg_path: string) -> (db: Db, ok: bool) {
	db = db_init() or_return
	db.cfg = load_config(cfg_path, db_allocator(&db)) or_return

	if len(db.cfg.keys) == 0 {
		fmt.eprintf("Error: no SSH keys configured in %s\n", cfg_path)
		db_close(&db)
		return db, false
	}

	_, keys_ok := ssh_to_x25519(db.cfg.keys[:], context.temp_allocator)
	if !keys_ok {
		db_close(&db)
		return db, false
	}

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
		fmt.eprintf("Error opening in-memory database: %s\n", sqlite.errmsg(conn))
		return
	}

	create_sql: cstring = "CREATE TABLE IF NOT EXISTS envr_env_files (path TEXT PRIMARY KEY NOT NULL, remotes TEXT, sha256 TEXT NOT NULL, contents TEXT NOT NULL)"
	rc = sqlite.exec(conn, create_sql, nil, nil, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error creating table: %s\n", sqlite.errmsg(conn))
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
		fmt.eprintf("Error reading encrypted database: %v\n", read_err)
		return false
	}

	// TODO: Use context.temp_allocator
	plaintext, dec_ok := decrypt(encrypted_data, db.cfg.keys[:])
	if !dec_ok {
		fmt.eprintln("Error: decryption failed")
		return false
	}
	defer delete(plaintext)

	n := i64(len(plaintext))
	buf := sqlite.malloc64(n)
	if buf == nil {
		fmt.eprintln("Error: failed to allocate buffer for deserialization")
		return false
	}
	copy(buf[:len(plaintext)], plaintext)

	flags: sqlite.DESERIALIZE_FLAGS = {.FREEONCLOSE, .RESIZEABLE}

	rc := sqlite.deserialize(db.conn, "main", buf, n, n, flags)
	if rc != sqlite.OK {
		sqlite.free(buf)
		fmt.eprintf("Error deserializing database: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	return true
}

// db_close will fail silently if cfg.keys is empty. If you want to save the
// Db, be sure to use db_open rather than db_init
db_close :: proc(db: ^Db) {
	allocator := db_allocator(db)

	defer {
		sqlite.close(db.conn)

		delete_config(&db.cfg, allocator)

		mem.dynamic_arena_destroy(&db.arena)
	}

	if db.changed && len(db.cfg.keys) > 0 {
		rc := sqlite.exec(db.conn, "VACUUM", nil, nil, nil)
		if rc != sqlite.OK {
			fmt.eprintf("Error vacuuming database: %s\n", sqlite.errmsg(db.conn))
			return
		}

		sz: i64
		data := sqlite.serialize(db.conn, "main", &sz, {})
		if data == nil {
			fmt.eprintln("Error: failed to serialize database")
			return
		}
		defer sqlite.free(data)

		sqlite_data := data[:sz]
		// TODO: PAss allocator chain
		encrypted, enc_ok := encrypt(sqlite_data, db.cfg.keys[:])
		if !enc_ok {
			fmt.eprintln("Database encryption failed")

			return
		}

		data_path := data_path(db.cfg.config_path, allocator)
		envr_d := envr_dir(db.cfg.config_path)
		os.mkdir_all(envr_d)

		write_err := os.write_entire_file(data_path, encrypted)
		delete(encrypted)
		if write_err != nil {
			fmt.eprintf("Error writing encrypted database: %v\n", write_err)
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
		fmt.eprintf("Error preparing query: %s\n", sqlite.errmsg(db.conn))
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
			fmt.eprintf("Error stepping query: %s\n", sqlite.errmsg(db.conn))
			#no_bounds_check return results[:], false
		}

		remotes_raw := string(sqlite.column_text(stmt, 1))
		split := strings.split_lines(remotes_raw, context.temp_allocator)
		remotes := make([dynamic]string, 0, len(split), allocator = allocator)
		for s in split {
			append(&remotes, strings.clone(s, allocator))
		}

		path := clone_cstring(sqlite.column_text(stmt, 0), allocator)

		append(
			&results,
			EnvFile {
				path = path,
				dir = filepath.dir(path),
				remotes = remotes,
				sha256 = clone_cstring(sqlite.column_text(stmt, 2), allocator),
				contents = clone_cstring(sqlite.column_text(stmt, 3), allocator),
			},
		)
	}

	#no_bounds_check return results[:], true
}

// TODO: Should we use context.temp_allocator for proc scoped lifetimes?
db_insert :: proc(db: ^Db, file: EnvFile) -> bool {
	remotes := strings.join(file.remotes[:], "\n", allocator = context.temp_allocator)

	sql: cstring =
		"INSERT OR REPLACE INTO " +
		"envr_env_files (path, remotes, sha256, contents) VALUES (?, ?, ?, ?)"
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(db.conn, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error preparing insert: %s\n", sqlite.errmsg(db.conn))
		return false
	}
	defer sqlite.finalize(stmt)

	// TODO: deal with elsewhere?
	cpath := to_cstring(file.path)
	defer delete(cpath)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error binding path: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	cremotes := to_cstring(remotes)
	defer delete(cremotes)
	rc = sqlite.bind_text(stmt, 2, cremotes, -1, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error binding remotes: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	csha := to_cstring(file.sha256)
	defer delete(csha)
	rc = sqlite.bind_text(stmt, 3, csha, -1, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error binding sha256: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	ccontents := to_cstring(file.contents)
	defer delete(ccontents)
	rc = sqlite.bind_text(stmt, 4, ccontents, -1, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error binding contents: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	rc = sqlite.step(stmt)
	if rc != sqlite.DONE {
		fmt.eprintf("Error inserting: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	db.changed = true
	return true
}

// Result will be freed when `db_close` is called.
//
// Expects an absolute path
db_fetch :: proc(db: ^Db, path: string) -> (EnvFile, bool) {
	if _, remote_path, is_remote := parse_remote_path(path); is_remote {
		assert(slashpath.is_abs(remote_path))
	} else {
		assert(os.is_absolute_path(path))
	}

	sql: cstring = "SELECT path, remotes, sha256, contents FROM envr_env_files WHERE path = ?"
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(db.conn, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error preparing fetch: %s\n", sqlite.errmsg(db.conn))
		return EnvFile{}, false
	}
	defer sqlite.finalize(stmt)

	allocator := db_allocator(db)

	cpath := to_cstring(path, allocator)
	defer delete(cpath, allocator)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error binding path: %s\n", sqlite.errmsg(db.conn))
		return EnvFile{}, false
	}
	rc = sqlite.step(stmt)
	if rc == sqlite.DONE {
		fmt.eprintf("No file found with path: %s\n", path)
		return EnvFile{}, false
	}
	if rc != sqlite.ROW {
		fmt.eprintf("Error fetching: %s\n", sqlite.errmsg(db.conn))
		return EnvFile{}, false
	}

	remotes_raw := string(sqlite.column_text(stmt, 1))
	split := strings.split_lines(remotes_raw, context.temp_allocator)
	remotes := make([dynamic]string, 0, len(split), allocator = allocator)
	for s in split {
		append(&remotes, strings.clone(s, allocator))
	}

	file_path := clone_cstring(sqlite.column_text(stmt, 0), allocator)

	return EnvFile {
			path = file_path,
			dir = filepath.dir(file_path),
			remotes = remotes,
			sha256 = clone_cstring(sqlite.column_text(stmt, 2), allocator),
			contents = clone_cstring(sqlite.column_text(stmt, 3), allocator),
		},
		true
}

db_delete :: proc(db: ^Db, path: string) -> bool {
	sql: cstring = "DELETE FROM envr_env_files WHERE path = ?"
	stmt: sqlite.Stmt
	rc := sqlite.prepare_v2(db.conn, sql, -1, &stmt, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error preparing delete: %s\n", sqlite.errmsg(db.conn))
		return false
	}
	defer sqlite.finalize(stmt)

	cpath := to_cstring(path)
	defer delete(cpath)
	rc = sqlite.bind_text(stmt, 1, cpath, -1, nil)
	if rc != sqlite.OK {
		fmt.eprintf("Error binding path: %s\n", sqlite.errmsg(db.conn))
		return false
	}
	rc = sqlite.step(stmt)
	if rc != sqlite.DONE {
		fmt.eprintf("Error deleting: %s\n", sqlite.errmsg(db.conn))
		return false
	}

	if sqlite.changes(db.conn) == 0 {
		fmt.eprintf("No file found with path: %s\n", path)
		return false
	}

	db.changed = true
	return true
}

// Caller is responsible for the returned memory
new_env_file :: proc(path: string) -> (EnvFile, bool) {
	if identity, host, remote_path, is_remote, resolved := normalize_remote_identity(path); is_remote {
		if !resolved {
			return EnvFile{}, false
		}
		contents, read_ok := read_remote_file(host, remote_path)
		if !read_ok {
			return EnvFile{}, false
		}
		return new_remote_env_file(identity, contents), true
	}

	abs_path, abs_err := filepath.abs(path)
	if abs_err != nil {
		fmt.eprintf("Error getting absolute path: %v\n", abs_err)
		return EnvFile{}, false
	}

	dir := filepath.dir(abs_path)

	// TODO: Should we use the db allocator here?
	remotes := get_git_remotes(dir, context.allocator)

	data, read_err := os.read_entire_file_from_path(abs_path, context.allocator)
	if read_err != nil {
		fmt.eprintf("Error reading file %s: %v\n", abs_path, read_err)
		return EnvFile{}, false
	}

	digest := hash.hash_bytes(hash.Algorithm.SHA256, data, context.temp_allocator)
	hex_bytes := hex.encode(digest, context.allocator)
	return EnvFile {
			path = abs_path,
			dir = dir,
			remotes = remotes,
			sha256 = string(hex_bytes),
			contents = string(data),
		},
		true
}

// Takes ownership of contents and returns an EnvFile that owns all its fields.
new_remote_env_file :: proc(path: string, contents: []byte) -> EnvFile {
	digest := hash.hash_bytes(hash.Algorithm.SHA256, contents, context.temp_allocator)
	hex_bytes := hex.encode(digest, context.allocator)

	return EnvFile {
		path = strings.clone(path, context.allocator),
		dir = "",
		sha256 = string(hex_bytes),
		contents = string(contents),
	}
}

// Reconciles `f` with the filesystem and persists changes to the database.
db_sync :: proc(db: ^Db, f: ^EnvFile) -> (SyncFlag, SyncError) {
	allocator := db_allocator(db)
	result: SyncFlag = {}
	old_path := f.path

	if _, _, is_remote := parse_remote_path(f.path); is_remote {
		identity, host, remote_path, _, resolved := normalize_remote_identity(f.path)
		if !resolved {
			return {}, .ReadFailed
		}
		contents, read_ok := read_remote_file(host, remote_path)
		if !read_ok {
			return {}, .ReadFailed
		}

		digest := hash.hash_bytes(hash.Algorithm.SHA256, contents, context.temp_allocator)
		hex_bytes := hex.encode(digest, allocator)
		current_sha := string(hex_bytes)
		if current_sha == f.sha256 {
			delete(contents)
			if identity != old_path {
				f.path = strings.clone(identity, allocator)
				if !db_persist(db, f, old_path) {
					return {}, .DbFailed
				}
			}
			return {}, .None
		}

		if identity != old_path {
			f.path = strings.clone(identity, allocator)
		}
		f.contents = string(contents)
		f.sha256 = current_sha
		if !db_persist(db, f, old_path) {
			return {}, .DbFailed
		}
		return {.BackedUp}, .None
	}

	if !os.exists(f.dir) {
		moved, err := try_move_dir(db, f, allocator)
		if !moved {
			return {}, err
		}
		result += {.DirUpdated}
	}

	if !os.exists(f.path) {
		write_err := os.write_entire_file(f.path, f.contents)
		if write_err != nil {
			fmt.eprintf("db_sync: failed to write %s: %v\n", f.path, write_err)
			return result, .WriteFailed
		}

		if !db_persist(db, f, old_path) {
			return result, .DbFailed
		}
		return result + {.Restored}, .None
	}

	data, read_err := os.read_entire_file_from_path(f.path, allocator)
	if read_err != nil {
		fmt.eprintf("db_sync: failed to read %s: %v\n", f.path, read_err)
		return result, .ReadFailed
	}

	digest := hash.hash_bytes(hash.Algorithm.SHA256, data, context.temp_allocator)
	hex_bytes := hex.encode(digest, allocator)
	current_sha := string(hex_bytes)

	if current_sha == f.sha256 {
		if !db_persist(db, f, old_path) {
			return result, .DbFailed
		}
		return result, .None
	}

	f.contents = string(data)
	f.sha256 = current_sha
	if !db_persist(db, f, old_path) {
		return result, .DbFailed
	}
	return result + {.BackedUp}, .None
}

// A remote identity uses user@host:path; CLI input is expanded to an absolute path.
parse_remote_path :: proc(path: string) -> (host, remote_path: string, is_remote: bool) {
	separator := strings.index(path, ":")
	if separator <= 0 || separator + 1 >= len(path) {
		return
	}
	host = path[:separator]
	if strings.index(host, "@") <= 0 ||
	   strings.index(host, " ") >= 0 ||
	   strings.index(host, "'") >= 0 {
		return "", "", false
	}
	remote_path = path[separator + 1:]
	is_remote = true
	return
}

// Resolves relative and tilde-prefixed remote input against the remote HOME.
// Absolute paths stay absolute, independent of the local host OS.
normalize_remote_identity :: proc(path: string) -> (
	identity, host, remote_path: string,
	is_remote, ok: bool,
) {
	parsed_host, parsed_path, parsed_is_remote := parse_remote_path(path)
	if !parsed_is_remote {
		return path, "", "", false, true
	}
	host = parsed_host
	is_remote = true

	if slashpath.is_abs(parsed_path) {
		remote_path = slashpath.clean(parsed_path, context.temp_allocator)
	} else {
		home, home_ok := remote_home_directory(host)
		if !home_ok {
			return "", host, "", true, false
		}
		remote_path = expand_remote_path(home, parsed_path)
	}

	identity = fmt.tprintf("%s:%s", host, remote_path)
	ok = true
	return
}

// Expands relative and tilde-prefixed remote input against an absolute POSIX home.
expand_remote_path :: proc(home, path: string) -> string {
	if slashpath.is_abs(path) {
		return slashpath.clean(path, context.temp_allocator)
	}
	relative := path
	if strings.has_prefix(relative, "~") {
		relative = relative[1:]
		if strings.has_prefix(relative, "/") {
			relative = relative[1:]
		}
	}
	return slashpath.join({home, relative}, context.temp_allocator)
}

remote_home_directory :: proc(host: string) -> (home: string, ok: bool) {
	// The command is constant; HOME is expanded by the remote shell and no
	// user-supplied path is interpolated into it.
	desc := os.Process_Desc {
		command = []string{"ssh", "-T", "--", host, "printf '%s' \"$HOME\""},
	}
	state, stdout, stderr, err := os.process_exec(desc, context.temp_allocator)
	delete(stderr)
	if err != nil {
		fmt.eprintf("Error querying remote home directory over ssh: %v\n", err)
		delete(stdout)
		return "", false
	}
	if !state.success {
		fmt.eprintf("Error querying remote home directory over ssh (exit code %d)\n", state.exit_code)
		delete(stdout)
		return "", false
	}

	home = string(stdout)
	if !slashpath.is_abs(home) {
		fmt.eprintf("Error: remote HOME is not an absolute POSIX path\n")
		return "", false
	}
	home = slashpath.clean(home, context.temp_allocator)
	ok = true
	return
}

// Read a remote file through OpenSSH. The path is quoted for the remote shell;
// the host and command are passed as distinct local argv elements.
read_remote_file :: proc(host, remote_path: string) -> (contents: []byte, ok: bool) {
	quoted_path := quote_remote_shell_path(remote_path)
	remote_command := fmt.tprintf("cat -- '%s'", quoted_path)
	desc := os.Process_Desc {
		command = []string{"ssh", "-T", "--", host, remote_command},
		stdin   = nil,
	}
	state, stdout, stderr, err := os.process_exec(desc, context.allocator)
	if err != nil {
		fmt.eprintf("Error starting ssh: %v\n", err)
		delete(stdout)
		delete(stderr)
		return nil, false
	}
	delete(stderr)
	if !state.success {
		fmt.eprintf("Error reading remote file via ssh (exit code %d)\n", state.exit_code)
		delete(stdout)
		return nil, false
	}
	return stdout, true
}

quote_remote_shell_path :: proc(path: string) -> string {
	quoted_path, _ := strings.replace_all(path, "'", "'\"'\"'", context.temp_allocator)
	return quoted_path
}

// Atomically writes a remote file via SSH stdin, never staging plaintext locally.
// Existing remote contents must match the stored digest unless force is set.
write_remote_file :: proc(host, remote_path, contents, expected_sha: string, force: bool) -> bool {
	if len(expected_sha) != 64 {
		fmt.eprintf("Error: invalid stored SHA-256 digest for remote restore\n")
		return false
	}
	for c in expected_sha {
		if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') && !(c >= 'A' && c <= 'F') {
			fmt.eprintf("Error: invalid stored SHA-256 digest for remote restore\n")
			return false
		}
	}
	quoted_path := quote_remote_shell_path(remote_path)
	force_check := force ? ":" : fmt.tprintf(`
if [ -e "$target" ]; then
	if command -v sha256sum >/dev/null 2>&1; then
		current=$(sha256sum -- "$target" | cut -d ' ' -f 1)
	elif command -v shasum >/dev/null 2>&1; then
		current=$(shasum -a 256 -- "$target" | cut -d ' ' -f 1)
	else
		echo 'Remote restore requires sha256sum or shasum; use --force to bypass conflict checking' >&2
		exit 74
	fi
	if [ "$current" != '%s' ]; then
		echo 'Remote file changed since backup; use --force to overwrite' >&2
		exit 73
	fi
fi
`, expected_sha)
	remote_command := fmt.tprintf(`
set -eu
target='%s'
dir=${target%/*}
[ -n "$dir" ] || dir=/
mkdir -p -- "$dir"
umask 077
tmp=$(mktemp "$dir/.envr.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT HUP INT TERM
cat > "$tmp"
%s
mv -f -- "$tmp" "$target"
trap - EXIT HUP INT TERM
`, quoted_path, force_check)
	read_pipe, write_pipe, pipe_err := os.pipe()
	if pipe_err != nil {
		fmt.eprintf("Error creating SSH input pipe: %v\n", pipe_err)
		return false
	}
	desc := os.Process_Desc {
		command = []string{"ssh", "-T", "--", host, remote_command},
		stdin = read_pipe,
	}
	process, start_err := os.process_start(desc)
	_ = os.close(read_pipe)
	if start_err != nil {
		_ = os.close(write_pipe)
		fmt.eprintf("Error starting ssh: %v\n", start_err)
		return false
	}
	remaining := transmute([]byte)contents
	write_err: os.Error
	for len(remaining) > 0 {
		written, err := os.write(write_pipe, remaining)
		if err != nil {
			write_err = err
			break
		}
		if written == 0 {
			break
		}
		remaining = remaining[written:]
	}
	_ = os.close(write_pipe)
	state, wait_err := os.process_wait(process)
	if write_err != nil {
		fmt.eprintf("Error sending file contents over ssh: %v\n", write_err)
		return false
	}
	if wait_err != nil || !state.success {
		fmt.eprintf("Error writing remote file via ssh (exit code %d)\n", state.exit_code)
		return false
	}
	return true
}

db_persist :: proc(db: ^Db, f: ^EnvFile, old_path: string) -> bool {
	if f.path != old_path {
		if !db_delete(db, old_path) {
			return false
		}
	}
	return db_insert(db, f^)
}

try_move_dir :: proc(db: ^Db, f: ^EnvFile, allocator: mem.Allocator) -> (bool, SyncError) {
	roots, ok := find_git_roots(db.cfg, context.allocator)
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
		f.dir = strings.clone(matched_dir, allocator)
		base := filepath.base(f.path)
		new_path, _ := filepath.join({f.dir, base}, allocator)
		f.path = new_path
		f.remotes = get_git_remotes(f.dir, allocator)
		return true, .None
	case:
		return false, .MultipleDirs
	}
}

shares_remote :: proc(f: ^EnvFile, remotes: []string) -> bool {
	for r1 in f.remotes {
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
					cloned := strings.clone(url, allocator)
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
		fmt.eprintf("Failed to convert string to cstring: %v\n", err)
		panic("Allocation Exception")
	}
	return cs
}

// Unless an explicit allocator is passed, caller is responsible for freeing the result
clone_cstring :: proc(c: cstring, allocator := context.allocator) -> string {
	str, err := strings.clone_from_cstring(c, allocator)
	if err != nil {
		fmt.eprintf("Failed to convert string to cstring: %v\n", err)
		delete(str)
		panic("Allocation Exception")
	}

	return str
}
