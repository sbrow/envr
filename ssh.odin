package main

import "core:encoding/base64"
import "core:fmt"
import "core:os"
import "core:strings"

SSH_ED25519 :: "ssh-ed25519"

Ed25519Keypair :: struct {
	Public:  [32]u8,
	Private: [32]u8,
}

parse_ssh_public_key :: proc(pub_path: string) -> (pub: [32]u8, ok: bool) {
	data, err := os.read_entire_file_from_path(pub_path, context.temp_allocator)
	if err != nil {
		return
	}

	text := strings.trim_right(string(data), "\n")
	parts := strings.split(text, " ", context.temp_allocator)
	if len(parts) < 2 {
		return
	}
	if parts[0] != SSH_ED25519 {
		return
	}

	decoded, decode_err := base64.decode(parts[1], allocator = context.temp_allocator)
	if decode_err != nil || len(decoded) < 51 {
		return
	}

	offset := 0
	key_type, type_ok := read_wire_string(decoded, &offset)
	if !type_ok || key_type != SSH_ED25519 {
		return
	}

	pk_data, pk_ok := read_wire_string(decoded, &offset)
	if !pk_ok || len(pk_data) != 32 {
		return
	}

	for i in 0 ..< 32 {
		pub[i] = pk_data[i]
	}

	ok = true
	return
}

parse_ssh_private_key :: proc(priv_path: string) -> (kp: Ed25519Keypair, ok: bool) {
	data, err := os.read_entire_file_from_path(priv_path, context.temp_allocator)
	if err != nil {
		return
	}

	text := string(data)
	lines := strings.split(text, "\n", context.temp_allocator)

	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	defer strings.builder_destroy(&b)

	in_block := false
	for line in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "-----BEGIN OPENSSH PRIVATE KEY-----" {
			in_block = true
			continue
		}
		if trimmed == "-----END OPENSSH PRIVATE KEY-----" {
			break
		}
		if in_block && len(trimmed) > 0 {
			fmt.sbprintf(&b, "%s", trimmed)
		}
	}

	b64_str := strings.to_string(b)
	decoded, decode_err := base64.decode(b64_str, allocator = context.temp_allocator)
	if decode_err != nil {
		return
	}

	magic := "openssh-key-v1\x00"
	if len(decoded) < len(magic) {
		return
	}
	for i in 0 ..< len(magic) {
		if decoded[i] != u8(magic[i]) {
			return
		}
	}

	offset := len(magic)

	ciphername, cipher_ok := read_wire_string(decoded, &offset)
	if !cipher_ok || ciphername != "none" {
		return
	}

	kdfname, kdf_ok := read_wire_string(decoded, &offset)
	if !kdf_ok || kdfname != "none" {
		return
	}

	_, opts_ok := read_wire_string(decoded, &offset)
	if !opts_ok {
		return
	}

	if offset + 4 > len(decoded) {
		return
	}
	num_keys := u32(decoded[offset]) << 24 | u32(decoded[offset + 1]) << 16 |
		u32(decoded[offset + 2]) << 8 | u32(decoded[offset + 3])
	offset += 4

	if num_keys != 1 {
		return
	}

	_, pub_blob_ok := read_wire_string(decoded, &offset)
	if !pub_blob_ok {
		return
	}

	priv_blob, priv_blob_ok := read_wire_string(decoded, &offset)
	if !priv_blob_ok {
		return
	}

	inner_offset := 0
	if inner_offset + 8 > len(priv_blob) {
		return
	}
	check1 := u32(priv_blob[inner_offset]) << 24 | u32(priv_blob[inner_offset + 1]) << 16 |
		u32(priv_blob[inner_offset + 2]) << 8 | u32(priv_blob[inner_offset + 3])
	inner_offset += 4
	check2 := u32(priv_blob[inner_offset]) << 24 | u32(priv_blob[inner_offset + 1]) << 16 |
		u32(priv_blob[inner_offset + 2]) << 8 | u32(priv_blob[inner_offset + 3])
	inner_offset += 4

	if check1 != check2 {
		return
	}

	priv_type, type_ok := read_wire_string(transmute([]u8)priv_blob, &inner_offset)
	if !type_ok || priv_type != SSH_ED25519 {
		return
	}

	pub_wire, pub_ok := read_wire_string(transmute([]u8)priv_blob, &inner_offset)
	if !pub_ok || len(pub_wire) != 32 {
		return
	}
	for i in 0 ..< 32 {
		kp.Public[i] = pub_wire[i]
	}

	priv_wire, priv_ok := read_wire_string(transmute([]u8)priv_blob, &inner_offset)
	if !priv_ok || len(priv_wire) != 64 {
		return
	}
	for i in 0 ..< 32 {
		kp.Private[i] = priv_wire[i]
	}

	ok = true
	return
}

is_ed25519_key :: proc(priv_path: string) -> bool {
	pub_path, _ := strings.concatenate([]string{priv_path, ".pub"}, context.temp_allocator)
	_, ok := parse_ssh_public_key(pub_path)
	return ok
}

is_encrypted_key :: proc(priv_path: string) -> bool {
	data, err := os.read_entire_file_from_path(priv_path, context.temp_allocator)
	if err != nil {
		return true
	}

	if !strings.contains(string(data), "BEGIN OPENSSH PRIVATE KEY") {
		return true
	}

	text := string(data)
	lines := strings.split(text, "\n", context.temp_allocator)

	b2: strings.Builder
	strings.builder_init(&b2, context.temp_allocator)
	defer strings.builder_destroy(&b2)

	in_block := false
	for line in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "-----BEGIN OPENSSH PRIVATE KEY-----" {
			in_block = true
			continue
		}
		if trimmed == "-----END OPENSSH PRIVATE KEY-----" {
			break
		}
		if in_block && len(trimmed) > 0 {
			fmt.sbprintf(&b2, "%s", trimmed)
		}
	}

	b64_str := strings.to_string(b2)
	decoded, decode_err := base64.decode(b64_str, allocator = context.temp_allocator)
	if decode_err != nil {
		return true
	}

	magic := "openssh-key-v1\x00"
	if len(decoded) < len(magic) {
		return true
	}
	for i in 0 ..< len(magic) {
		if decoded[i] != u8(magic[i]) {
			return true
		}
	}

	offset := len(magic)
	ciphername, cipher_ok := read_wire_string(decoded, &offset)
	if !cipher_ok {
		return true
	}

	return ciphername != "none"
}

read_wire_string :: proc(data: []u8, offset: ^int) -> (s: string, ok: bool) {
	if offset^ + 4 > len(data) {
		return
	}
	length := u32(data[offset^]) << 24 | u32(data[offset^ + 1]) << 16 |
		u32(data[offset^ + 2]) << 8 | u32(data[offset^ + 3])
	offset^ += 4

	if offset^ + int(length) > len(data) {
		return
	}

	s = string(data[offset^ : offset^ + int(length)])
	offset^ += int(length)
	ok = true
	return
}
