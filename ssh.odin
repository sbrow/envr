package main

import "base:runtime"
import "core:encoding/base64"
import "core:encoding/endian"
import "core:fmt"
import "core:mem"
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

	rest := decoded
	key_type, type_ok := read_wire_string(&rest)
	if !type_ok || string(key_type) != SSH_ED25519 {
		return
	}

	pk_data, pk_ok := read_wire_string(&rest)
	if !pk_ok || len(pk_data) != 32 {
		return
	}

	mem.copy_non_overlapping(&pub[0], &pk_data[0], 32)

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

	magic :: "openssh-key-v1\x00"
	if !strings.has_prefix(string(decoded), magic) {
		return
	}

	rest := decoded[len(magic):]

	ciphername, cipher_ok := read_wire_string(&rest)
	if !cipher_ok || string(ciphername) != "none" {
		return
	}

	kdfname, kdf_ok := read_wire_string(&rest)
	if !kdf_ok || string(kdfname) != "none" {
		return
	}

	_, opts_ok := read_wire_string(&rest)
	if !opts_ok {
		return
	}

	num_keys, nkeys_ok := read_wire_u32(&rest)
	if !nkeys_ok || num_keys != 1 {
		return
	}

	_, pub_blob_ok := read_wire_string(&rest)
	if !pub_blob_ok {
		return
	}

	priv_blob, priv_blob_ok := read_wire_string(&rest)
	if !priv_blob_ok {
		return
	}

	inner := priv_blob

	check1, c1_ok := read_wire_u32(&inner)
	check2, c2_ok := read_wire_u32(&inner)
	if !c1_ok || !c2_ok || check1 != check2 {
		return
	}

	priv_type, type_ok := read_wire_string(&inner)
	if !type_ok || string(priv_type) != SSH_ED25519 {
		return
	}

	pub_wire, pub_ok := read_wire_string(&inner)
	if !pub_ok || len(pub_wire) != 32 {
		return
	}
	mem.copy_non_overlapping(&kp.Public[0], &pub_wire[0], 32)

	priv_wire, priv_ok := read_wire_string(&inner)
	if !priv_ok || len(priv_wire) != 64 {
		return
	}

	mem.copy_non_overlapping(&kp.Private[0], &priv_wire[0], 32)

	ok = true
	return
}

is_ed25519_key :: proc(
	priv_path: string,
) -> (
	ok: bool,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	pub_path := strings.concatenate([]string{priv_path, ".pub"}, context.temp_allocator) or_return
	_, ok = parse_ssh_public_key(pub_path)
	return ok, nil
}

read_wire_string :: proc(data: ^[]u8) -> (s: []u8, ok: bool) {
	if len(data^) < 4 do return
	length := endian.get_u32(data^[:4], .Big) or_return
	data^ = data^[4:]

	if len(data^) < int(length) do return
	s = data^[:int(length)]
	data^ = data^[int(length):]
	ok = true
	return
}

read_wire_u32 :: proc(data: ^[]u8) -> (v: u32, ok: bool) {
	if len(data^) < 4 do return
	v = endian.get_u32(data^[:4], .Big) or_return
	data^ = data^[4:]
	ok = true
	return
}

