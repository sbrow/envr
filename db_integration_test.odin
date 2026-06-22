#+test
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import "sqlite"

FIXTURES :: "fixtures"

fixture_key :: proc() -> SshKeyPair {
	priv, _ := strings.concatenate(
		[]string{FIXTURES, "/keys/insecure-test-key"},
		context.temp_allocator,
	)
	pub, _ := strings.concatenate(
		[]string{FIXTURES, "/keys/insecure-test-key.pub"},
		context.temp_allocator,
	)
	return SshKeyPair{private = priv, public = pub}
}

fixture_db_path :: proc() -> string {
	p, _ := strings.concatenate([]string{FIXTURES, "/single-file.db"}, context.temp_allocator)
	return p
}

fixture_config :: proc() -> Config {
	cfg := Config {
		keys = make([dynamic]SshKeyPair, 0, 1),
	}
	append(&cfg.keys, fixture_key())
	return cfg
}

@(test)
test_encrypt_decrypt_sqlite_roundtrip :: proc(t: ^testing.T) {
	cfg := fixture_config()
	defer {
		delete(cfg.keys)
	}

	db_path := fixture_db_path()
	sqlite_data, read_err := os.read_entire_file_from_path(db_path, context.allocator)
	testing.expectf(t, read_err == nil, "failed to read fixture db: %v", read_err)
	if read_err != nil {
		return
	}
	defer delete(sqlite_data)

	encrypted, enc_ok := encrypt(sqlite_data, cfg.keys[:])
	testing.expect(t, enc_ok, "encryption should succeed")
	if !enc_ok {
		return
	}
	defer delete(encrypted)

	testing.expect(t, len(encrypted) >= HEADER_SIZE, "ciphertext should have header")
	testing.expect(t, encrypted[0] == u8('E'), "magic byte 0")
	testing.expect(t, encrypted[1] == u8('N'), "magic byte 1")
	testing.expect(t, encrypted[2] == u8('V'), "magic byte 2")
	testing.expect(t, encrypted[3] == u8('R'), "magic byte 3")

	plaintext, dec_ok := decrypt(encrypted, cfg.keys[:])
	testing.expect(t, dec_ok, "decryption should succeed")
	if !dec_ok {
		return
	}
	defer delete(plaintext)

	testing.expectf(
		t,
		len(plaintext) == len(sqlite_data),
		"round-trip size mismatch: expected %d, got %d",
		len(sqlite_data),
		len(plaintext),
	)

	match := true
	for i in 0 ..< len(sqlite_data) {
		if plaintext[i] != sqlite_data[i] {
			match = false
			break
		}
	}
	testing.expect(t, match, "decrypted data should match original")
}

@(test)
test_encrypt_write_read_decrypt :: proc(t: ^testing.T) {
	cfg := fixture_config()
	defer {
		delete(cfg.keys)
	}

	db_path := fixture_db_path()
	sqlite_data, read_err := os.read_entire_file_from_path(db_path, context.allocator)
	testing.expectf(t, read_err == nil, "failed to read fixture db: %v", read_err)
	if read_err != nil {
		return
	}
	defer delete(sqlite_data)

	encrypted, enc_ok := encrypt(sqlite_data, cfg.keys[:])
	testing.expect(t, enc_ok, "encryption should succeed")
	if !enc_ok {
		return
	}
	defer delete(encrypted)

	tmp_enc_path := fmt.tprintf("/tmp/envr-test-ewrd-%d.envr", os.get_pid())
	write_err := os.write_entire_file(tmp_enc_path, encrypted)
	testing.expectf(t, write_err == nil, "failed to write encrypted file: %v", write_err)
	if write_err != nil {
		return
	}
	defer os.remove(tmp_enc_path)

	read_back, rb_err := os.read_entire_file_from_path(tmp_enc_path, context.allocator)
	testing.expectf(t, rb_err == nil, "failed to read back encrypted file: %v", rb_err)
	if rb_err != nil {
		return
	}
	defer delete(read_back)

	plaintext, dec_ok := decrypt(read_back, cfg.keys[:])
	testing.expect(t, dec_ok, "decryption after write/read should succeed")
	if !dec_ok {
		return
	}
	defer delete(plaintext)

	testing.expect(t, len(plaintext) == len(sqlite_data), "size mismatch after file round-trip")
}

@(test)
test_decrypt_then_deserialize_sqlite :: proc(t: ^testing.T) {
	cfg := fixture_config()
	defer {
		delete(cfg.keys)
	}

	db_path := fixture_db_path()
	sqlite_data, read_err := os.read_entire_file_from_path(db_path, context.allocator)
	testing.expectf(t, read_err == nil, "failed to read fixture db: %v", read_err)
	if read_err != nil {
		return
	}
	defer delete(sqlite_data)

	encrypted, enc_ok := encrypt(sqlite_data, cfg.keys[:])
	testing.expect(t, enc_ok, "encryption should succeed")
	if !enc_ok {
		return
	}
	defer delete(encrypted)

	plaintext, dec_ok := decrypt(encrypted, cfg.keys[:])
	testing.expect(t, dec_ok, "decryption should succeed")
	if !dec_ok {
		return
	}
	defer delete(plaintext)

	mem_db: sqlite.Db
	rc := sqlite.open(":memory:", &mem_db)
	testing.expectf(t, rc == sqlite.OK, "failed to open in-memory db")
	if rc != sqlite.OK {
		return
	}
	defer sqlite.close(mem_db)

	n := i64(len(plaintext))
	buf := sqlite.malloc64(n)
	testing.expect(t, buf != nil, "malloc64 should succeed")
	if buf == nil do return
	copy(buf[:len(plaintext)], plaintext)

	rc = sqlite.deserialize(mem_db, "main", buf, n, n, {.FREEONCLOSE, .RESIZEABLE})
	testing.expect(t, rc == sqlite.OK, "deserialize should succeed")
	if rc != sqlite.OK {
		sqlite.free(buf)
		return
	}

	sql: cstring = "SELECT path FROM envr_env_files"
	stmt: sqlite.Stmt
	rc = sqlite.prepare_v2(mem_db, sql, -1, &stmt, nil)
	testing.expect(t, rc == sqlite.OK, "prepare failed")
	if rc != sqlite.OK {
		return
	}
	defer sqlite.finalize(stmt)

	rc = sqlite.step(stmt)
	testing.expect(t, rc == sqlite.ROW, "expected at least one row")
	if rc == sqlite.ROW {
		path := string(sqlite.column_text(stmt, 0))
		testing.expect(t, len(path) > 0, "path should not be empty")
	}
}

@(test)
test_full_db_cycle :: proc(t: ^testing.T) {
	cfg := fixture_config()
	defer delete(cfg.keys)

	db_path := fixture_db_path()
	original_data, read_err := os.read_entire_file_from_path(db_path, context.allocator)
	testing.expectf(t, read_err == nil, "failed to read fixture db: %v", read_err)
	if read_err != nil {
		return
	}
	defer delete(original_data)

	encrypted, enc_ok := encrypt(original_data, cfg.keys[:])
	testing.expect(t, enc_ok, "first encryption should succeed")
	if !enc_ok {
		return
	}
	defer delete(encrypted)

	envr_dir_path := fmt.tprintf("/tmp/envr-test-cycle-%d/.envr", os.get_pid())
	os.mkdir_all(envr_dir_path)

	data_path, _ := filepath.join([]string{envr_dir_path, "data.envr"})
	defer delete(data_path)
	write_err := os.write_entire_file(data_path, encrypted)
	testing.expectf(t, write_err == nil, "failed to write data.envr: %v", write_err)
	if write_err != nil {
		return
	}

	read_back, rb_err := os.read_entire_file_from_path(data_path, context.allocator)
	testing.expectf(t, rb_err == nil, "failed to read data.envr: %v", rb_err)
	if rb_err != nil {
		return
	}
	defer delete(read_back)

	plaintext, dec_ok := decrypt(read_back, cfg.keys[:])
	testing.expect(t, dec_ok, "decryption should succeed")
	if !dec_ok {
		return
	}
	defer delete(plaintext)

	encrypted2, enc2_ok := encrypt(plaintext, cfg.keys[:])
	testing.expect(t, enc2_ok, "re-encryption should succeed")
	if !enc2_ok {
		return
	}
	defer delete(encrypted2)

	plaintext2, dec2_ok := decrypt(encrypted2, cfg.keys[:])
	testing.expect(t, dec2_ok, "second decryption should succeed")
	if !dec2_ok {
		return
	}
	defer delete(plaintext2)

	testing.expect(
		t,
		len(plaintext2) == len(original_data),
		fmt.tprintf(
			"double round-trip size mismatch: expected %d, got %d",
			len(original_data),
			len(plaintext2),
		),
	)

	os.remove(data_path)
	os.remove(envr_dir_path)
	home := filepath.dir(filepath.dir(envr_dir_path))
	os.remove(home)
}

@(test)
test_ssh_key_parse_from_fixtures :: proc(t: ^testing.T) {
	key := fixture_key()

	priv_kp, priv_ok := parse_ssh_private_key(key.private)
	testing.expect(t, priv_ok, "should parse private key from fixtures")
	if !priv_ok {
		return
	}

	pub_key, pub_ok := parse_ssh_public_key(key.public)
	testing.expect(t, pub_ok, "should parse public key from fixtures")
	if !pub_ok {
		return
	}

	for i in 0 ..< 32 {
		testing.expectf(t, priv_kp.Public[i] == pub_key[i], "public key mismatch at byte %d", i)
	}

	x25519_pairs, x_ok := ssh_to_x25519([]SshKeyPair{key})
	testing.expect(t, x_ok, "ssh_to_x25519 should succeed")
	if !x_ok {
		return
	}

	testing.expect(t, len(x25519_pairs) == 1, "should have 1 x25519 keypair")
}

@(test)
test_config_load_with_fixture_key :: proc(t: ^testing.T) {
	cfg := fixture_config()
	defer {
		delete(cfg.keys)
	}

	testing.expect(t, len(cfg.keys) == 1, "should have 1 key")

	key := cfg.keys[0]

	testing.expectf(t, len(key.private) > 0, "private key path should not be empty")
	testing.expectf(t, len(key.public) > 0, "public key path should not be empty")

	_, priv_ok := parse_ssh_private_key(key.private)
	testing.expect(t, priv_ok, "should parse private key using config paths")
	if !priv_ok {
		fmt.printf("  private key path was: '%s'\n", key.private)
	}
}

