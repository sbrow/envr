package main

import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "sqlite"

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
