# Age-FFI Zig Bindings

Idiomatic Zig bindings for the [age](https://age-encryption.org/) encryption library.

## Features

- **Complete FFI coverage** - All age-ffi functions exposed
- **Memory safety** - RAII wrappers with automatic cleanup
- **Idiomatic error handling** - Zig errors instead of C result codes
- **Type safety** - Strong typing with Zig's type system
- **Easy to use** - High-level API that feels native to Zig

## Building the C Library

First, build the Rust FFI library:

```bash
cd ..
cargo build --release
```

This creates a static library at `../target/release/libage_ffi.a`.

## Using the Bindings

### In Your Build Script

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add the age module
    const age_module = b.addModule("age", .{
        .root_source_file = .{ .path = "path/to/age-ffi/zig/age.zig" },
    });
    exe.root_module.addImport("age", age_module);

    // Link the static library
    exe.addLibraryPath(.{ .path = "path/to/age-ffi/target/release" });
    exe.linkSystemLibrary("age_ffi");
    exe.linkLibC();

    b.installArtifact(exe);
}
```

### In Your Code

```zig
const age = @import("age");

// Generate a keypair
var keypair = try age.generateKeypair();
defer keypair.deinit();

// Encrypt
const plaintext = "Secret message";
var encrypted = try age.encrypt(plaintext, keypair.getPublicKey());
defer encrypted.deinit();

// Decrypt
var decrypted = try age.decrypt(encrypted.toSlice(), keypair.getPrivateKey());
defer decrypted.deinit();
```

## API Overview

### Key Generation

```zig
// Generate new keypair
var keypair = try age.generateKeypair();
defer keypair.deinit();

// Derive public key from private key
const public_key = try age.derivePublicKey(allocator, private_key);
defer allocator.free(public_key);
```

### Encryption

```zig
// Simple encryption
var encrypted = try age.encrypt(plaintext, recipient);
defer encrypted.deinit();

// With ASCII armor
var armored = try age.encryptArmor(plaintext, recipient);
defer armored.deinit();

// Multiple recipients
const recipients = [_][:0]const u8{ recipient1, recipient2 };
var multi = try age.encryptMulti(plaintext, &recipients, false);
defer multi.deinit();

// Passphrase-based
var pass_enc = try age.encryptPassphrase(plaintext, passphrase, true);
defer pass_enc.deinit();
```

### Decryption

```zig
// Simple decryption
var decrypted = try age.decrypt(ciphertext, identity);
defer decrypted.deinit();

// With multiple identities (tries each)
const identities = [_][:0]const u8{ id1, id2 };
var multi = try age.decryptMulti(ciphertext, &identities);
defer multi.deinit();

// SSH key support
var ssh_dec = try age.decryptSsh(ciphertext, ssh_private_key);
defer ssh_dec.deinit();

// Passphrase-based
var pass_dec = try age.decryptPassphrase(ciphertext, passphrase);
defer pass_dec.deinit();
```

### File Operations

```zig
// Encrypt to file
try age.encryptToFileArmor(plaintext, recipient, "/path/to/file.age");

// Decrypt from file
var decrypted = try age.decryptFileWithIdentity("/path/to/file.age", identity);
defer decrypted.deinit();
```

### Validation

```zig
// Validate keys
const is_valid = age.isValidX25519Recipient(recipient);

// Check recipient type
const recipient_type = age.getRecipientType(recipient);
// Returns: .invalid, .x25519, or .ssh
```

### ASCII Armor

```zig
// Add armor
var armored = try age.armor(binary_data);
defer armored.deinit();

// Remove armor
var binary = try age.dearmor(armored_data);
defer binary.deinit();
```

## Memory Management

The bindings use RAII wrappers that automatically free resources:

- `Buffer` - Wraps `AgeBuffer`, freed on `deinit()`
- `Keypair` - Wraps `AgeKeypair`, freed on `deinit()`
- `CString` - Wraps C strings, freed on `deinit()`

Always call `defer x.deinit()` after creating these objects.

## Error Handling

All operations return `AgeError!T` with the following error types:

- `InvalidInput`
- `EncryptionFailed`
- `DecryptionFailed`
- `KeygenFailed`
- `IoError`
- `InvalidRecipient`
- `InvalidIdentity`
- `NoRecipients`
- `NoIdentities`
- `ArmorError`
- `PassphraseRequired`
- `InvalidPassphrase`
- `SshKeyError`
- `MemoryAllocationFailed`
- `InvalidUtf8`
- `UnsupportedKey`

## Example

See `example.zig` for a comprehensive demonstration of all features.

Run the example:

```bash
# Build the example (requires build.zig in this directory)
zig build-exe example.zig -I.. -L../target/release -lage_ffi -lc

# Or manually:
zig build-exe example.zig \
    -I.. \
    -L../target/release \
    -lage_ffi \
    -lc

./example
```

## Low-Level C API

The module also exposes the raw C functions if you need direct FFI access:

```zig
const result = age.age_encrypt(
    plaintext.ptr,
    plaintext.len,
    recipient.ptr,
    &output,
);
```

## Version Information

```zig
const version = age.getVersion();        // age-ffi version
const lib_version = age.getLibVersion(); // underlying age library version
```

## Safety Notes

1. All C strings must be null-terminated (`:0` sentinel)
2. Buffers returned by the library must be freed with `deinit()`
3. Don't use buffers after calling `deinit()`
4. The `toOwnedSlice()` method transfers ownership and calls `deinit()` automatically

## License

Same as the parent age-ffi project.
