#+test
package main

import "core:fmt"
import "core:os"
import "core:testing"

CRYPTO_TEST_KEY_DIR :: "fixtures" + os.Path_Separator_String + "keys"

make_test_key_pair :: proc(name: string) -> SshKeyPair {
	priv := fmt.tprintf("%s/%s", CRYPTO_TEST_KEY_DIR, name)
	pub := fmt.tprintf("%s/%s.pub", CRYPTO_TEST_KEY_DIR, name)
	return SshKeyPair{private = priv, public = pub}
}

@(test)
test_encrypt_decrypt_roundtrip :: proc(t: ^testing.T) {
	key := make_test_key_pair("test_ed25519")
	original := []u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

	encrypted, enc_ok := encrypt(original, []SshKeyPair{key})
	testing.expect(t, enc_ok, "encryption should succeed")
	testing.expect(t, len(encrypted) > 0, "ciphertext should not be empty")
	defer delete(encrypted)

	decrypted, dec_ok := decrypt(encrypted, []SshKeyPair{key})
	testing.expect(t, dec_ok, "decryption should succeed")
	defer delete(decrypted)

	testing.expect(
		t,
		len(decrypted) == len(original),
		fmt.tprintf("expected %d bytes, got %d", len(original), len(decrypted)),
	)
	for i in 0 ..< len(original) {
		testing.expect(t, decrypted[i] == original[i], fmt.tprintf("byte mismatch at index %d", i))
	}
}

@(test)
test_encrypt_decrypt_multi_recipient :: proc(t: ^testing.T) {
	key1 := make_test_key_pair("test_ed25519")
	key2 := make_test_key_pair("test_ed25519_second")
	original := []u8{42, 43, 44, 45}

	encrypted, enc_ok := encrypt(original, []SshKeyPair{key1, key2})
	testing.expect(t, enc_ok, "encryption with 2 keys should succeed")
	defer delete(encrypted)

	decrypted1, dec1_ok := decrypt(encrypted, []SshKeyPair{key1})
	testing.expect(t, dec1_ok, "decryption with key1 should succeed")
	defer delete(decrypted1)

	decrypted2, dec2_ok := decrypt(encrypted, []SshKeyPair{key2})
	testing.expect(t, dec2_ok, "decryption with key2 should succeed")
	defer delete(decrypted2)

	for i in 0 ..< len(original) {
		testing.expect(
			t,
			decrypted1[i] == original[i],
			fmt.tprintf("key1: byte mismatch at %d", i),
		)
		testing.expect(
			t,
			decrypted2[i] == original[i],
			fmt.tprintf("key2: byte mismatch at %d", i),
		)
	}
}

@(test)
test_decrypt_wrong_key_fails :: proc(t: ^testing.T) {
	key1 := make_test_key_pair("test_ed25519")
	key2 := make_test_key_pair("test_ed25519_second")
	original := []u8{1, 2, 3}

	encrypted, enc_ok := encrypt(original, []SshKeyPair{key1})
	testing.expect(t, enc_ok, "encryption should succeed")
	defer delete(encrypted)

	_, dec_ok := decrypt(encrypted, []SshKeyPair{key2})
	testing.expect(t, !dec_ok, "decryption with wrong key should fail")
}

@(test)
test_encrypt_empty_plaintext :: proc(t: ^testing.T) {
	key := make_test_key_pair("test_ed25519")
	original: []u8

	encrypted, enc_ok := encrypt(original, []SshKeyPair{key})
	testing.expect(t, enc_ok, "encryption of empty data should succeed")
	defer delete(encrypted)

	decrypted, dec_ok := decrypt(encrypted, []SshKeyPair{key})
	testing.expect(t, dec_ok, "decryption should succeed")
	defer delete(decrypted)

	testing.expect(t, len(decrypted) == 0, "decrypted empty data should be empty")
}

@(test)
test_recipient_can_decrypt_senders_data :: proc(t: ^testing.T) {
	key1 := make_test_key_pair("test_ed25519")
	key2 := make_test_key_pair("test_ed25519_second")
	original := []u8{10, 20, 30, 40, 50}

	encrypted, enc_ok := encrypt(original, []SshKeyPair{key1, key2})
	testing.expect(t, enc_ok, "encryption with 2 keys should succeed")
	defer delete(encrypted)

	decrypted, dec_ok := decrypt(encrypted, []SshKeyPair{key2})
	testing.expect(t, dec_ok, "second recipient should decrypt without the sender key present")
	defer delete(decrypted)

	for i in 0 ..< len(original) {
		testing.expect(t, decrypted[i] == original[i], fmt.tprintf("byte mismatch at %d", i))
	}
}

@(test)
test_ciphertext_has_magic :: proc(t: ^testing.T) {
	key := make_test_key_pair("test_ed25519")
	original := []u8{1, 2, 3}

	encrypted, enc_ok := encrypt(original, []SshKeyPair{key})
	testing.expect(t, enc_ok, "encryption should succeed")
	defer delete(encrypted)

	testing.expect(t, len(encrypted) >= 4, "ciphertext should have at least 4 bytes")
	testing.expect(t, encrypted[0] == u8('E'), "magic byte 0")
	testing.expect(t, encrypted[1] == u8('N'), "magic byte 1")
	testing.expect(t, encrypted[2] == u8('V'), "magic byte 2")
	testing.expect(t, encrypted[3] == u8('R'), "magic byte 3")
}

