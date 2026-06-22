#+test
package main

import "core:fmt"
import "core:os"
import "core:testing"

TEST_KEY_DIR :: "fixtures" + os.Path_Separator_String + "keys"

@(test)
test_parse_ed25519_public_key :: proc(t: ^testing.T) {
	pub, ok := parse_ssh_public_key(TEST_KEY_DIR + "/test_ed25519.pub")
	testing.expect(t, ok, "expected ed25519 public key to parse")
	testing.expect(t, pub != [32]u8{}, fmt.tprintf("expected non-zero public key"))
}

@(test)
test_parse_ed25519_private_key :: proc(t: ^testing.T) {
	kp, ok := parse_ssh_private_key(TEST_KEY_DIR + "/test_ed25519")
	testing.expect(t, ok, "expected ed25519 private key to parse")
	testing.expect(t, kp.Public != [32]u8{}, "expected non-zero public key")
	testing.expect(t, kp.Private != [32]u8{}, "expected non-zero private key")
}

@(test)
test_parse_rsa_public_key_fails :: proc(t: ^testing.T) {
	_, ok := parse_ssh_public_key(TEST_KEY_DIR + "/test_rsa.pub")
	testing.expect(t, !ok, "expected RSA key parsing to fail")
}

@(test)
test_is_ed25519_key_true :: proc(t: ^testing.T) {
	testing.expect(t, is_ed25519_key(TEST_KEY_DIR + "/test_ed25519"))
}

@(test)
test_is_ed25519_key_false_for_rsa :: proc(t: ^testing.T) {
	testing.expect(t, !is_ed25519_key(TEST_KEY_DIR + "/test_rsa"))
}

@(test)
test_private_key_pub_matches_public_key :: proc(t: ^testing.T) {
	pub_from_pub, pub_ok := parse_ssh_public_key(TEST_KEY_DIR + "/test_ed25519.pub")
	testing.expect(t, pub_ok, "expected public key to parse")

	kp, priv_ok := parse_ssh_private_key(TEST_KEY_DIR + "/test_ed25519")
	testing.expect(t, priv_ok, "expected private key to parse")

	testing.expect(
		t,
		pub_from_pub == kp.Public,
		fmt.tprintf(
			"public key mismatch:\n  from .pub: %v\n  from priv: %v",
			pub_from_pub,
			kp.Public,
		),
	)
}

@(test)
test_read_wire_string :: proc(t: ^testing.T) {
	data := []u8{0, 0, 0, 5, u8('h'), u8('e'), u8('l'), u8('l'), u8('o'), 0, 0, 0, 0}
	offset := 0

	s, ok := read_wire_string(data, &offset)
	testing.expect(t, ok, "expected read_wire_string to succeed")
	testing.expect(t, s == "hello", fmt.tprintf("expected 'hello', got %q", s))
	testing.expect(t, offset == 9, fmt.tprintf("expected offset 9, got %d", offset))

	s2, ok2 := read_wire_string(data, &offset)
	testing.expect(t, ok2, "expected second read to succeed")
	testing.expect(t, s2 == "", "expected empty string")
}


