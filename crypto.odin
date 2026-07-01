package main

import "core:fmt"
import "core:mem"
import "core:os"

MAGIC :: "ENVR"
MAGIC_BYTES: [4]u8 = MAGIC

RECIPIENT_ENTRY_SIZE ::
	CRYPTO_BOX_PUBLICKEY_BYTES +
	CRYPTO_BOX_NONCE_BYTES +
	CRYPTO_SECRETBOX_KEY_BYTES +
	CRYPTO_BOX_MAC_BYTES

HEADER_SIZE :: 4 + CRYPTO_BOX_PUBLICKEY_BYTES + CRYPTO_SECRETBOX_NONCE_BYTES + 4

RecipientEntry :: struct {
	PublicKey:    [CRYPTO_BOX_PUBLICKEY_BYTES]u8,
	Nonce:        [CRYPTO_BOX_NONCE_BYTES]u8,
	EncryptedKey: [CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES]u8,
}

X25519Keypair :: struct {
	Public:  [CRYPTO_BOX_PUBLICKEY_BYTES]u8,
	Private: [CRYPTO_BOX_SECRETKEY_BYTES]u8,
}

@(init)
init_sodium :: proc "contextless" () {
	if sodium_init() < 0 {
		os.exit(1)
	}
}

// TODO: Optimize performance
encrypt :: proc(plaintext: []u8, keys: []SshKeyPair) -> (ciphertext: []u8, ok: bool) {
	x25519_pairs, pairs_ok := ssh_to_x25519(keys, context.temp_allocator)
	if !pairs_ok {
		return
	}

	sym_key: [CRYPTO_SECRETBOX_KEY_BYTES]u8
	randombytes_buf(&sym_key[0], CRYPTO_SECRETBOX_KEY_BYTES)

	main_nonce: [CRYPTO_SECRETBOX_NONCE_BYTES]u8
	randombytes_buf(&main_nonce[0], CRYPTO_SECRETBOX_NONCE_BYTES)

	ct_len := len(plaintext) + CRYPTO_SECRETBOX_MAC_BYTES
	secret_ct := make([]u8, ct_len, context.temp_allocator)
	pt_ptr: [^]u8
	if len(plaintext) > 0 {
		pt_ptr = &plaintext[0]
	}
	rc := crypto_secretbox_easy(
		&secret_ct[0],
		pt_ptr,
		u64(len(plaintext)),
		&main_nonce[0],
		&sym_key[0],
	)
	if rc != 0 {
		fmt.eprintln("Error: symmetric encryption failed")
		delete(secret_ct)
		return
	}

	num_recipients := u32(len(x25519_pairs))
	entries := make([]RecipientEntry, num_recipients, context.temp_allocator)

	for i in 0 ..< len(x25519_pairs) {
		for j in 0 ..< CRYPTO_BOX_PUBLICKEY_BYTES {
			entries[i].PublicKey[j] = x25519_pairs[i].Public[j]
		}

		randombytes_buf(&entries[i].Nonce[0], CRYPTO_BOX_NONCE_BYTES)

		rc = crypto_box_easy(
			&entries[i].EncryptedKey[0],
			&sym_key[0],
			CRYPTO_SECRETBOX_KEY_BYTES,
			&entries[i].Nonce[0],
			&x25519_pairs[i].Public[0],
			&x25519_pairs[0].Private[0],
		)
		if rc != 0 {
			fmt.eprintf("Error: failed to encrypt for recipient %d\n", i)
			delete(entries)
			delete(secret_ct)
			return
		}
	}

	total_len := HEADER_SIZE + int(num_recipients) * RECIPIENT_ENTRY_SIZE + ct_len
	ciphertext = make([]u8, total_len)

	pos := 0

	mem.copy(&ciphertext[pos], &MAGIC_BYTES[0], 4)
	pos += 4

	mem.copy(&ciphertext[pos], &x25519_pairs[0].Public[0], CRYPTO_BOX_PUBLICKEY_BYTES)
	pos += CRYPTO_BOX_PUBLICKEY_BYTES

	mem.copy(&ciphertext[pos], &main_nonce[0], CRYPTO_SECRETBOX_NONCE_BYTES)
	pos += CRYPTO_SECRETBOX_NONCE_BYTES

	ciphertext[pos] = u8((num_recipients >> 24) & 0xff)
	ciphertext[pos + 1] = u8((num_recipients >> 16) & 0xff)
	ciphertext[pos + 2] = u8((num_recipients >> 8) & 0xff)
	ciphertext[pos + 3] = u8(num_recipients & 0xff)
	pos += 4

	for i in 0 ..< int(num_recipients) {
		mem.copy(&ciphertext[pos], &entries[i].PublicKey[0], CRYPTO_BOX_PUBLICKEY_BYTES)
		pos += CRYPTO_BOX_PUBLICKEY_BYTES
		mem.copy(&ciphertext[pos], &entries[i].Nonce[0], CRYPTO_BOX_NONCE_BYTES)
		pos += CRYPTO_BOX_NONCE_BYTES
		mem.copy(
			&ciphertext[pos],
			&entries[i].EncryptedKey[0],
			CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES,
		)
		pos += CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES
	}

	mem.copy(&ciphertext[pos], &secret_ct[0], ct_len)

	ok = true
	return
}

decrypt :: proc(ciphertext: []u8, keys: []SshKeyPair) -> (plaintext: []u8, ok: bool) {
	if len(ciphertext) < HEADER_SIZE {
		fmt.eprintln("Error: ciphertext too short (header)")
		return
	}

	for i in 0 ..< 4 {
		if ciphertext[i] != MAGIC_BYTES[i] {
			fmt.eprintln("Error: invalid magic bytes")
			return
		}
	}

	offset := 4

	sender_pk: [CRYPTO_BOX_PUBLICKEY_BYTES]u8
	for i in 0 ..< CRYPTO_BOX_PUBLICKEY_BYTES {
		sender_pk[i] = ciphertext[offset + i]
	}
	offset += CRYPTO_BOX_PUBLICKEY_BYTES

	main_nonce: [CRYPTO_SECRETBOX_NONCE_BYTES]u8
	for i in 0 ..< CRYPTO_SECRETBOX_NONCE_BYTES {
		main_nonce[i] = ciphertext[offset + i]
	}
	offset += CRYPTO_SECRETBOX_NONCE_BYTES

	num_recipients :=
		u32(ciphertext[offset]) << 24 |
		u32(ciphertext[offset + 1]) << 16 |
		u32(ciphertext[offset + 2]) << 8 |
		u32(ciphertext[offset + 3])
	offset += 4

	recipients_end := offset + int(num_recipients) * RECIPIENT_ENTRY_SIZE
	if recipients_end > len(ciphertext) {
		fmt.eprintln("Error: ciphertext too short (recipient data)")
		return
	}

	enc_sym_key: [CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES]u8
	enc_nonce: [CRYPTO_BOX_NONCE_BYTES]u8
	enc_pub: [CRYPTO_BOX_PUBLICKEY_BYTES]u8

	x25519_pairs, pairs_ok := ssh_to_x25519(keys, context.temp_allocator)
	if !pairs_ok {
		return
	}

	found := false
	matched_pi := 0
	for pi in 0 ..< len(x25519_pairs) {
		scan_offset := offset
		for _ in 0 ..< int(num_recipients) {
			for i in 0 ..< CRYPTO_BOX_PUBLICKEY_BYTES {
				enc_pub[i] = ciphertext[scan_offset + i]
			}
			scan_offset += CRYPTO_BOX_PUBLICKEY_BYTES

			match := true
			for i in 0 ..< CRYPTO_BOX_PUBLICKEY_BYTES {
				if enc_pub[i] != x25519_pairs[pi].Public[i] {
					match = false
					break
				}
			}
			if !match {
				scan_offset +=
					CRYPTO_BOX_NONCE_BYTES + CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES
				continue
			}

			for i in 0 ..< CRYPTO_BOX_NONCE_BYTES {
				enc_nonce[i] = ciphertext[scan_offset + i]
			}
			scan_offset += CRYPTO_BOX_NONCE_BYTES

			for i in 0 ..< CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES {
				enc_sym_key[i] = ciphertext[scan_offset + i]
			}
			scan_offset += CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES

			found = true
			matched_pi = pi
			break
		}
		if found {
			break
		}
	}

	if !found {
		fmt.eprintln("Error: no matching recipient found")
		return
	}

	sym_key: [CRYPTO_SECRETBOX_KEY_BYTES]u8
	rc := crypto_box_open_easy(
		&sym_key[0],
		&enc_sym_key[0],
		CRYPTO_SECRETBOX_KEY_BYTES + CRYPTO_BOX_MAC_BYTES,
		&enc_nonce[0],
		&sender_pk[0],
		&x25519_pairs[matched_pi].Private[0],
	)
	if rc != 0 {
		fmt.eprintln("Error: failed to decrypt symmetric key")
		return
	}

	ct_data := ciphertext[recipients_end:]
	pt_len := len(ct_data) - CRYPTO_SECRETBOX_MAC_BYTES
	if pt_len < 0 {
		fmt.eprintln("Error: ciphertext too short (no encrypted data)")
		return
	}

	plaintext = make([]u8, pt_len)
	pt_ptr: [^]u8
	if len(plaintext) > 0 {
		pt_ptr = &plaintext[0]
	}
	rc = crypto_secretbox_open_easy(
		pt_ptr,
		&ct_data[0],
		u64(len(ct_data)),
		&main_nonce[0],
		&sym_key[0],
	)
	if rc != 0 {
		fmt.eprintln("Error: symmetric decryption failed")
		delete(plaintext)
		return
	}

	ok = true
	return
}

ssh_to_x25519 :: proc(
	keys: []SshKeyPair,
	allocator := context.temp_allocator,
) -> (
	[]X25519Keypair,
	bool,
) {
	if len(keys) == 0 {
		return {}, false
	}

	pairs := make([]X25519Keypair, len(keys), allocator)

	for i in 0 ..< len(keys) {
		ssh_kp, parse_ok := parse_ssh_private_key(keys[i].private)
		if !parse_ok {
			fmt.eprintf("Error: failed to parse SSH private key: %s\n", keys[i].private)
			delete(pairs)
			return pairs, false
		}

		ssh_pub, pub_ok := parse_ssh_public_key(keys[i].public)
		if !pub_ok {
			fmt.eprintf("Error: failed to parse SSH public key: %s\n", keys[i].public)
			delete(pairs)
			return pairs, false
		}

		pk_rc := crypto_sign_ed25519_pk_to_curve25519(&pairs[i].Public[0], &ssh_pub[0])
		if pk_rc != 0 {
			fmt.eprintln("Error: failed to convert ed25519 public key to curve25519")
			delete(pairs)
			return pairs, false
		}

		ed25519_sk: [64]u8
		for j in 0 ..< 32 {
			ed25519_sk[j] = ssh_kp.Private[j]
		}
		for j in 0 ..< 32 {
			ed25519_sk[32 + j] = ssh_kp.Public[j]
		}

		sk_rc := crypto_sign_ed25519_sk_to_curve25519(&pairs[i].Private[0], &ed25519_sk[0])
		if sk_rc != 0 {
			fmt.eprintln("Error: failed to convert ed25519 private key to curve25519")
			delete(pairs)
			return pairs, false
		}
	}

	return pairs, true
}

