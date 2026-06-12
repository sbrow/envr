package main

import "core:c"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "sqlite"

SyncResult :: enum i32 {
    Noop = 0,
    DirUpdated = 1,
    Restored = 1 << 1,
    BackedUp = 1 << 2,
    Error = 1 << 3,
}

SyncDirection :: enum {
    TrustDatabase,
    TrustFilesystem,
}

Db :: struct {
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

make_temp_path :: proc() -> string {
    ts := time.time_to_unix(time.now())
    b: strings.Builder
    strings.builder_init(&b)
    fmt.sbprintf(&b, "/tmp/envr-%d-%d.db", os.get_pid(), ts)
    return strings.to_string(b)
}

db_open :: proc() -> (Db, bool) {
    cfg, ok := load_config()
    if !ok {
        return Db{}, false
    }

    age_path := data_age_path()
    _, stat_err := os.stat(age_path, context.allocator)

    db: ^rawptr
    rc := sqlite.db_open(":memory:", &db)
    if rc != sqlite.OK {
        fmt.printf("Error opening in-memory database: %s\n", sqlite.db_errmsg(db))
        return Db{}, false
    }

    create_sql := "CREATE TABLE IF NOT EXISTS envr_env_files (path TEXT PRIMARY KEY NOT NULL, remotes TEXT, sha256 TEXT NOT NULL, contents TEXT NOT NULL)"
    rc = sqlite.db_exec(db, string_to_cstring(create_sql), nil, nil, nil)
    if rc != sqlite.OK {
        fmt.printf("Error creating table: %s\n", sqlite.db_errmsg(db))
        sqlite.db_close(db)
        return Db{}, false
    }

    if stat_err == nil {
        if !db_restore_from_age(db, cfg) {
            sqlite.db_close(db)
            return Db{}, false
        }
    }

    return Db{db = db, cfg = cfg, changed = stat_err != nil}, true
}

db_close :: proc(d: ^Db) {
    if d.changed {
        tmp_path := make_temp_path()

        if !db_vacuum_to_file(d.db, tmp_path) {
            os.remove(tmp_path)
            sqlite.db_close(d.db)
            return
        }

        db_encrypt_file(tmp_path, d.cfg.Keys)
        os.remove(tmp_path)
        d.changed = false
    }
    sqlite.db_close(d.db)
}

db_list :: proc(d: ^Db) -> (results: [dynamic]EnvFile, ok: bool) {
    sql := "SELECT path, remotes, sha256, contents FROM envr_env_files"
    stmt: ^rawptr
    rc := sqlite.prepare_v2(d.db, string_to_cstring(sql), -1, &stmt, nil)
    if rc != sqlite.OK {
        fmt.printf("Error preparing query: %s\n", sqlite.db_errmsg(d.db))
        return
    }

    for {
        rc = sqlite.step(stmt)
        if rc == sqlite.DONE {
            break
        }
        if rc != sqlite.ROW {
            fmt.printf("Error stepping query: %s\n", sqlite.db_errmsg(d.db))
            sqlite.finalize(stmt)
            return
        }

        path := cstring_to_string(sqlite.column_text(stmt, 0))
        remotes_json := cstring_to_string(sqlite.column_text(stmt, 1))
        sha := cstring_to_string(sqlite.column_text(stmt, 2))
        contents := cstring_to_string(sqlite.column_text(stmt, 3))

        remotes: [dynamic]string
        if len(remotes_json) > 0 {
            json.unmarshal_string(remotes_json, &remotes)
        }

        append(&results, EnvFile{
            Path = path,
            Dir = filepath.dir(path),
            Remotes = remotes,
            Sha256 = sha,
            contents = contents,
        })
    }

    sqlite.finalize(stmt)
    ok = true
    return
}

db_vacuum_to_file :: proc(db: ^rawptr, path: string) -> bool {
    b: strings.Builder
    strings.builder_init(&b)
    fmt.sbprintf(&b, "VACUUM INTO '%s'", path)
    sql := strings.to_string(b)
    rc := sqlite.db_exec(db, string_to_cstring(sql), nil, nil, nil)
    if rc != sqlite.OK {
        fmt.printf("Error vacuuming database: %s\n", sqlite.db_errmsg(db))
        return false
    }
    return true
}

db_restore_from_age :: proc(db: ^rawptr, cfg: Config) -> bool {
    tmp_path := make_temp_path()
    defer os.remove(tmp_path)

    if !db_decrypt_to_file(tmp_path, cfg.Keys) {
        return false
    }

    if !db_attach_and_copy(db, tmp_path) {
        return false
    }

    return true
}

db_decrypt_to_file :: proc(tmp_path: string, keys: []SshKeyPair) -> bool {
    age_path := data_age_path()

    args := make([dynamic]string)
    append(&args, "age")
    append(&args, "--decrypt")
    append(&args, "-o")
    append(&args, tmp_path)
    for key in keys {
        append(&args, "-i")
        append(&args, key.Private)
    }
    append(&args, age_path)

    desc := os.Process_Desc{
        command = args[:],
        stdout = os.stderr,
        stderr = os.stderr,
    }

    p, err := os.process_start(desc)
    if err != nil {
        fmt.printf("Error running age decrypt: %v\n", err)
        return false
    }

    state, wait_err := os.process_wait(p)
    if wait_err != nil {
        fmt.printf("Error waiting for age: %v\n", wait_err)
        return false
    }
    if state.exit_code != 0 {
        fmt.println("Error: age decryption failed")
        return false
    }
    return true
}

db_encrypt_file :: proc(tmp_path: string, keys: []SshKeyPair) -> bool {
    age_path := data_age_path()
    envr_d := envr_dir()
    os.mkdir_all(envr_d)

    args := make([dynamic]string)
    append(&args, "age")
    append(&args, "--encrypt")
    for key in keys {
        append(&args, "-r")
        pub_data, pub_err := os.read_entire_file_from_path(key.Public, context.allocator)
        if pub_err != nil {
            fmt.printf("Error reading public key: %s\n", key.Public)
            return false
        }
        pub_str := string(pub_data)
        if strings.has_suffix(pub_str, "\n") {
            pub_str = pub_str[:len(pub_str)-1]
        }
        append(&args, pub_str)
    }
    append(&args, "-o")
    append(&args, age_path)
    append(&args, tmp_path)

    desc := os.Process_Desc{
        command = args[:],
        stdout = os.stderr,
        stderr = os.stderr,
    }

    p, err := os.process_start(desc)
    if err != nil {
        fmt.printf("Error running age encrypt: %v\n", err)
        return false
    }

    state, wait_err := os.process_wait(p)
    if wait_err != nil {
        fmt.printf("Error waiting for age: %v\n", wait_err)
        return false
    }
    if state.exit_code != 0 {
        fmt.println("Error: age encryption failed")
        return false
    }
    return true
}

db_attach_and_copy :: proc(mem_db: ^rawptr, src_path: string) -> bool {
    b: strings.Builder
    strings.builder_init(&b)
    fmt.sbprintf(&b, "ATTACH DATABASE '%s' AS source", src_path)
    attach_sql := strings.to_string(b)

    rc := sqlite.db_exec(mem_db, string_to_cstring(attach_sql), nil, nil, nil)
    if rc != sqlite.OK {
        fmt.printf("Error attaching database: %s\n", sqlite.db_errmsg(mem_db))
        return false
    }

    rc = sqlite.db_exec(mem_db, "INSERT INTO main.envr_env_files SELECT * FROM source.envr_env_files", nil, nil, nil)
    if rc != sqlite.OK {
        fmt.printf("Error copying data: %s\n", sqlite.db_errmsg(mem_db))
        sqlite.db_exec(mem_db, "DETACH DATABASE source", nil, nil, nil)
        return false
    }

    sqlite.db_exec(mem_db, "DETACH DATABASE source", nil, nil, nil)
    return true
}

get_git_remotes :: proc(dir: string) -> [dynamic]string {
    remotes: [dynamic]string
    remote_set: map[string]bool

    b: strings.Builder
    strings.builder_init(&b)
    fmt.sbprintf(&b, "%s-git-remotes", make_temp_path())
    tmp_path := strings.to_string(b)
    tmp_file, tmp_err := os.open(tmp_path, os.O_CREATE | os.O_WRONLY | os.O_TRUNC)
    if tmp_err != nil {
        return remotes
    }

    args := []string{"git", "remote", "-v"}
    desc := os.Process_Desc{
        command = args,
        stdout = tmp_file,
        stderr = nil,
        working_dir = dir,
    }

    p, start_err := os.process_start(desc)
    os.close(tmp_file)
    if start_err != nil {
        os.remove(tmp_path)
        return remotes
    }

    state, wait_err := os.process_wait(p)
    if wait_err != nil || state.exit_code != 0 {
        os.remove(tmp_path)
        return remotes
    }

    data, read_err := os.read_entire_file_from_path(tmp_path, context.allocator)
    os.remove(tmp_path)
    if read_err != nil {
        return remotes
    }

    output_str := string(data)
    lines := strings.split(output_str, "\n")

    for &line in lines {
        line = strings.trim_space(line)
        if len(line) == 0 {
            continue
        }
        parts := strings.fields(line)
        if len(parts) >= 2 {
            remote_set[parts[1]] = true
        }
    }

    for remote, _ in remote_set {
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
    cloned_path, _ := strings.clone(abs_path)

    dir := filepath.dir(cloned_path)

    remotes := get_git_remotes(dir)

    data, read_err := os.read_entire_file_from_path(cloned_path, context.allocator)
    if read_err != nil {
        fmt.printf("Error reading file %s: %v\n", cloned_path, read_err)
        return EnvFile{}, false
    }

    digest := hash.hash_bytes(hash.Algorithm.SHA256, data)
    hex_bytes, _ := hex.encode(digest)
    sha_str := string(hex_bytes)

    return EnvFile{
        Path = cloned_path,
        Dir = dir,
        Remotes = remotes,
        Sha256 = sha_str,
        contents = string(data),
    }, true
}

db_insert :: proc(d: ^Db, file: EnvFile) -> bool {
    remotes_json, marshal_err := json.marshal(file.Remotes)
    if marshal_err != nil {
        fmt.printf("Error marshaling remotes: %v\n", marshal_err)
        return false
    }

    sql := "INSERT OR REPLACE INTO envr_env_files (path, remotes, sha256, contents) VALUES (?, ?, ?, ?)"
    stmt: ^rawptr
    rc := sqlite.prepare_v2(d.db, string_to_cstring(sql), -1, &stmt, nil)
    if rc != sqlite.OK {
        fmt.printf("Error preparing insert: %s\n", sqlite.db_errmsg(d.db))
        return false
    }
    defer sqlite.finalize(stmt)

    rc = sqlite.bind_text(stmt, 1, string_to_cstring(file.Path), -1, nil)
    rc = sqlite.bind_text(stmt, 2, string_to_cstring(string(remotes_json)), -1, nil)
    rc = sqlite.bind_text(stmt, 3, string_to_cstring(file.Sha256), -1, nil)
    rc = sqlite.bind_text(stmt, 4, string_to_cstring(file.contents), -1, nil)

    rc = sqlite.step(stmt)
    if rc != sqlite.DONE {
        fmt.printf("Error inserting: %s\n", sqlite.db_errmsg(d.db))
        return false
    }

    d.changed = true
    return true
}

db_fetch :: proc(d: ^Db, path: string) -> (EnvFile, bool) {
    sql := "SELECT path, remotes, sha256, contents FROM envr_env_files WHERE path = ?"
    stmt: ^rawptr
    rc := sqlite.prepare_v2(d.db, string_to_cstring(sql), -1, &stmt, nil)
    if rc != sqlite.OK {
        fmt.printf("Error preparing fetch: %s\n", sqlite.db_errmsg(d.db))
        return EnvFile{}, false
    }
    defer sqlite.finalize(stmt)

    rc = sqlite.bind_text(stmt, 1, string_to_cstring(path), -1, nil)
    rc = sqlite.step(stmt)
    if rc == sqlite.DONE {
        fmt.printf("No file found with path: %s\n", path)
        return EnvFile{}, false
    }
    if rc != sqlite.ROW {
        fmt.printf("Error fetching: %s\n", sqlite.db_errmsg(d.db))
        return EnvFile{}, false
    }

    file_path := cstring_to_string(sqlite.column_text(stmt, 0))
    remotes_json := cstring_to_string(sqlite.column_text(stmt, 1))
    sha := cstring_to_string(sqlite.column_text(stmt, 2))
    contents := cstring_to_string(sqlite.column_text(stmt, 3))

    remotes: [dynamic]string
    if len(remotes_json) > 0 {
        json.unmarshal_string(remotes_json, &remotes)
    }

    cloned_path, _ := strings.clone(file_path)
    return EnvFile{
        Path = cloned_path,
        Dir = filepath.dir(cloned_path),
        Remotes = remotes,
        Sha256 = sha,
        contents = contents,
    }, true
}

db_delete :: proc(d: ^Db, path: string) -> bool {
    sql := "DELETE FROM envr_env_files WHERE path = ?"
    stmt: ^rawptr
    rc := sqlite.prepare_v2(d.db, string_to_cstring(sql), -1, &stmt, nil)
    if rc != sqlite.OK {
        fmt.printf("Error preparing delete: %s\n", sqlite.db_errmsg(d.db))
        return false
    }
    defer sqlite.finalize(stmt)

    rc = sqlite.bind_text(stmt, 1, string_to_cstring(path), -1, nil)
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

cstring_to_string :: proc(cs: cstring) -> string {
    if cs == nil {
        return ""
    }
    s, _ := strings.clone_from_cstring(cs)
    return s
}

string_to_cstring :: proc(s: string) -> cstring {
    cs, _ := strings.clone_to_cstring(s)
    return cs
}

db_update_required :: proc(status: SyncResult) -> bool {
    s := i32(status)
    return (s & (i32(SyncResult.BackedUp) | i32(SyncResult.DirUpdated))) != 0
}

shares_remote :: proc(f: ^EnvFile, remotes: []string) -> bool {
    remote_set: map[string]bool
    for r in f.Remotes {
        remote_set[r] = true
    }
    for r in remotes {
        if r in remote_set {
            return true
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
    feats := check_features()
    if .Fd not_in feats || .Git not_in feats {
        fmt.println("Error: fd and git are required for moved dir detection")
        return {}, false
    }

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

env_file_backup :: proc(f: ^EnvFile) -> bool {
    data, read_err := os.read_entire_file_from_path(f.Path, context.allocator)
    if read_err != nil {
        fmt.printf("Error reading file %s: %v\n", f.Path, read_err)
        return false
    }

    f.contents = string(data)
    digest := hash.hash_bytes(hash.Algorithm.SHA256, data)
    hex_bytes, _ := hex.encode(digest)
    f.Sha256 = string(hex_bytes)
    return true
}

env_file_sync :: proc(f: ^EnvFile, dir: SyncDirection, d: ^Db) -> (SyncResult, string) {
    result: SyncResult = .Noop
    err_msg: string

    _, stat_err := os.stat(f.Dir, context.allocator)
    if stat_err != nil {
        moved_dirs: [dynamic]string

        if d != nil {
            dirs, dirs_ok := find_moved_dirs(d, f)
            if !dirs_ok {
                return .Error, "failed to find moved dirs"
            }
            moved_dirs = dirs
        }

        if len(moved_dirs) == 0 {
            return .Error, "directory missing"
        } else if len(moved_dirs) == 1 {
            update_dir(f, moved_dirs[0])
            result = .DirUpdated
        } else {
            return .Error, "multiple directories found"
        }
    }

    _, file_stat_err := os.stat(f.Path, context.allocator)
    if file_stat_err != nil {
        write_err := os.write_entire_file(f.Path, f.contents)
        if write_err != nil {
            msg, _ := strings.concatenate({"failed to write file: ", fmt.tprintf("%v", write_err)})
            return .Error, msg
        }

        s := i32(result) | i32(SyncResult.Restored)
        return SyncResult(s), ""
    }

    data, read_err := os.read_entire_file_from_path(f.Path, context.allocator)
    if read_err != nil {
        msg, _ := strings.concatenate({"failed to read file for SHA comparison: ", fmt.tprintf("%v", read_err)})
        return .Error, msg
    }

    digest := hash.hash_bytes(hash.Algorithm.SHA256, data)
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
            return .Error, msg
        }
        s := i32(result) | i32(SyncResult.Restored)
        return SyncResult(s), ""
    case .TrustFilesystem:
        if !env_file_backup(f) {
            return .Error, "failed to backup file"
        }
        return .BackedUp, ""
    }

    return result, ""
}

db_sync :: proc(d: ^Db, f: ^EnvFile) -> (SyncResult, string) {
    return env_file_sync(f, .TrustFilesystem, d)
}
