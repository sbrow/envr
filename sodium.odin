package main

import "core:c"

foreign import libsodium "system:sodium"

CRYPTO_BOX_PUBLICKEY_BYTES :: 32
CRYPTO_BOX_SECRETKEY_BYTES :: 32
CRYPTO_BOX_NONCE_BYTES :: 24
CRYPTO_BOX_MAC_BYTES :: 16

CRYPTO_SECRETBOX_KEY_BYTES :: 32
CRYPTO_SECRETBOX_NONCE_BYTES :: 24
CRYPTO_SECRETBOX_MAC_BYTES :: 16

CRYPTO_SIGN_PUBLICKEY_BYTES :: 32
CRYPTO_SIGN_SECRETKEY_BYTES :: 64

@(default_calling_convention = "c")
foreign libsodium {
	sodium_init :: proc() -> c.int ---
	// crypto_box_keypair :: proc(pk: [^]u8, sk: [^]u8) -> c.int ---
	crypto_box_easy :: proc(ciphertext: [^]u8, plaintext: [^]u8, mlen: c.ulong, nonce: [^]u8, pk: [^]u8, sk: [^]u8) -> c.int ---
	crypto_box_open_easy :: proc(plaintext: [^]u8, ciphertext: [^]u8, clen: c.ulong, nonce: [^]u8, pk: [^]u8, sk: [^]u8) -> c.int ---
	crypto_secretbox_easy :: proc(ciphertext: [^]u8, plaintext: [^]u8, mlen: c.ulong, nonce: [^]u8, key: [^]u8) -> c.int ---
	crypto_secretbox_open_easy :: proc(plaintext: [^]u8, ciphertext: [^]u8, clen: c.ulong, nonce: [^]u8, key: [^]u8) -> c.int ---
	crypto_sign_ed25519_pk_to_curve25519 :: proc(curve25519_pk: [^]u8, ed25519_pk: [^]u8) -> c.int ---
	crypto_sign_ed25519_sk_to_curve25519 :: proc(curve25519_sk: [^]u8, ed25519_sk: [^]u8) -> c.int ---
	randombytes_buf :: proc(buf: [^]u8, size: c.ulong) ---
}

