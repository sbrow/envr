# age-ffi

A Rust FFI wrapper for the [age](https://github.com/str4d/rage) encryption library, with Zig bindings.

## Overview

This library provides C-compatible FFI bindings for the age encryption library, making it easy to use age encryption from other languages. It includes comprehensive Zig bindings and examples.

## Features

- **X25519 encryption** - Standard age public key encryption (`age1...`)
- **SSH key support** - Encrypt to SSH keys (`ssh-ed25519`, `ssh-rsa`)
- **Plugin support** - Full support for age plugins including:
  - [age-plugin-se](https://github.com/remko/age-plugin-se) (Secure Enclave on macOS)
  - [age-plugin-yubikey](https://github.com/str4d/age-plugin-yubikey)
  - Any other age-compatible plugin
- **Passphrase encryption** - Scrypt-based passphrase encryption
- **Multiple recipients** - Encrypt to multiple recipients at once
- **Armor format** - ASCII-armored output support
- **File operations** - Direct file encryption/decryption
- **Memory-safe API** - Proper error handling and memory management
- **Comprehensive test suite**

## Supported Identity/Recipient Types

| Type | Recipient Format | Identity Format |
|------|-----------------|-----------------|
| X25519 | `age1...` | `AGE-SECRET-KEY-1...` |
| SSH | `ssh-ed25519 ...`, `ssh-rsa ...` | SSH private key file |
| Plugin | `age1<plugin>1...` | `AGE-PLUGIN-<NAME>-1...` |
| Passphrase | N/A | Passphrase string |

## Building

### Rust Library

```bash
cargo build --release
```

This produces `target/release/libage_ffi.a` (static library).

### Zig Bindings

```bash
cd zig
zig build
```

Run the example:

```bash
cd zig
zig build run
```

Run tests:

```bash
cd zig
zig build test
```

## Usage

### Zig

```zig
const age = @import("age");

// Generate a keypair
var keypair = try age.generateKeypair();
defer keypair.deinit();

// Encrypt data
const plaintext = "Hello, World!";
var encrypted = try age.encrypt(plaintext, keypair.getPublicKey());
defer encrypted.deinit();

// Decrypt data
var decrypted = try age.decrypt(encrypted.toSlice(), keypair.getPrivateKey());
defer decrypted.deinit();

// File operations with plugin support
try age.encryptToFile(plaintext, "age1se1...", "/path/to/output.age");
var content = try age.decryptFile("/path/to/file.age", "/path/to/identities");
defer content.deinit();
```

### C

```c
#include <age_ffi.h>

// Generate keypair
AgeKeypair keypair;
age_generate_keypair(&keypair);

// Encrypt
AgeBuffer encrypted;
age_encrypt(plaintext, plaintext_len, keypair.public_key, &encrypted);

// Decrypt
AgeBuffer decrypted;
age_decrypt(encrypted.data, encrypted.len, keypair.private_key, &decrypted);

// Free resources
age_free_buffer(&encrypted);
age_free_buffer(&decrypted);
age_free_keypair(&keypair);
```

## Plugin Support

This library supports the [age plugin protocol](https://github.com/C2SP/C2SP/blob/main/age.md), allowing encryption and decryption with hardware-backed keys and other plugin-based identities.

### Requirements

- The plugin binary must be in your `$PATH` (e.g., `age-plugin-se`)
- For Secure Enclave: macOS with Touch ID or Apple Watch

### Example with Secure Enclave

```bash
# Install the plugin
brew install age-plugin-se

# Generate a Secure Enclave identity
age-plugin-se --generate -o ~/.age/se-identity.txt

# The library will automatically use the plugin when it sees:
# - Recipients starting with age1se1...
# - Identities starting with AGE-PLUGIN-SE-...
```

## API Reference

### Key Generation
- `age_generate_keypair()` - Generate X25519 keypair
- `age_generate_x25519()` - Generate X25519 keypair (alias)
- `age_x25519_to_public()` - Derive public key from private key

### Encryption
- `age_encrypt()` - Encrypt to a single recipient
- `age_encrypt_multi()` - Encrypt to multiple recipients
- `age_encrypt_armor()` - Encrypt with ASCII armor
- `age_encrypt_passphrase()` - Encrypt with passphrase
- `age_encrypt_to_file()` - Encrypt directly to file

### Decryption
- `age_decrypt()` - Decrypt with identity string
- `age_decrypt_multi()` - Decrypt with multiple identities
- `age_decrypt_file()` - Decrypt file using identity file (supports plugins)
- `age_decrypt_passphrase()` - Decrypt with passphrase

### Utilities
- `age_armor()` - Wrap binary data in ASCII armor
- `age_dearmor()` - Unwrap ASCII-armored data
- `age_validate_recipient()` - Check if recipient string is valid
- `age_validate_identity()` - Check if identity string is valid
- `age_version()` - Get library version

## License

This project is dual-licensed under MIT and Apache-2.0, matching the age library.
