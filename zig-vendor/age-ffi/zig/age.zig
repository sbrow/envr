//! Zig bindings for the age-ffi library
//!
//! This module provides idiomatic Zig wrappers around the age encryption library's C FFI.
//! It handles memory management, error conversion, and provides safe interfaces.

const std = @import("std");
const c = @cImport({});

// ============================================================================
// C Types and Structures
// ============================================================================

/// Result codes for FFI functions
pub const AgeResult = enum(c_int) {
    success = 0,
    invalid_input = 1,
    encryption_failed = 2,
    decryption_failed = 3,
    keygen_failed = 4,
    io_error = 5,
    invalid_recipient = 6,
    invalid_identity = 7,
    no_recipients = 8,
    no_identities = 9,
    armor_error = 10,
    passphrase_required = 11,
    invalid_passphrase = 12,
    ssh_key_error = 13,
    memory_allocation_failed = 14,
    invalid_utf8 = 15,
    unsupported_key = 16,
};

/// A buffer containing binary data allocated by the library.
/// Caller must free using age_free_buffer.
pub const AgeBuffer = extern struct {
    data: [*]u8,
    len: usize,
    capacity: usize,

    pub fn toSlice(self: AgeBuffer) []u8 {
        return self.data[0..self.len];
    }
};

/// A keypair containing public and private keys as C strings.
/// Caller must free using age_free_keypair.
pub const AgeKeypair = extern struct {
    public_key: [*:0]u8,
    private_key: [*:0]u8,

    pub fn getPublicKey(self: AgeKeypair) [:0]const u8 {
        return std.mem.span(self.public_key);
    }

    pub fn getPrivateKey(self: AgeKeypair) [:0]const u8 {
        return std.mem.span(self.private_key);
    }
};

/// Configuration for encryption operations.
pub const AgeEncryptConfig = extern struct {
    armor: bool,
    scrypt_work_factor: u8,

    pub fn default() AgeEncryptConfig {
        return .{
            .armor = false,
            .scrypt_work_factor = 0,
        };
    }
};

// ============================================================================
// Raw C FFI Declarations
// ============================================================================

/// Get the version of the age-ffi library (static string, do not free)
pub extern "C" fn age_version() [*:0]const u8;

/// Get the version of the underlying age library (static string, do not free)
pub extern "C" fn age_lib_version() [*:0]const u8;

// Key generation
pub extern "C" fn age_generate_x25519(keypair: *AgeKeypair) AgeResult;
pub extern "C" fn age_generate_keypair(keypair: *AgeKeypair) AgeResult;
pub extern "C" fn age_x25519_to_public(private_key: [*:0]const u8, public_key: *[*:0]u8) AgeResult;

// Encryption
pub extern "C" fn age_encrypt(
    plaintext: [*]const u8,
    plaintext_len: usize,
    recipient: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_encrypt_multi(
    plaintext: [*]const u8,
    plaintext_len: usize,
    recipients: [*]const [*:0]const u8,
    recipient_count: usize,
    armor: bool,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_encrypt_armor(
    plaintext: [*]const u8,
    plaintext_len: usize,
    recipient: [*:0]const u8,
    output: *[*:0]u8,
) AgeResult;

// Decryption
pub extern "C" fn age_decrypt(
    ciphertext: [*]const u8,
    ciphertext_len: usize,
    identity: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_decrypt_multi(
    ciphertext: [*]const u8,
    ciphertext_len: usize,
    identities: [*]const [*:0]const u8,
    identity_count: usize,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_decrypt_ssh(
    ciphertext: [*]const u8,
    ciphertext_len: usize,
    ssh_key: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_decrypt_ssh_file(
    ciphertext: [*]const u8,
    ciphertext_len: usize,
    ssh_key_path: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

// Passphrase
pub extern "C" fn age_encrypt_passphrase(
    plaintext: [*]const u8,
    plaintext_len: usize,
    passphrase: [*:0]const u8,
    armor: bool,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_decrypt_passphrase(
    ciphertext: [*]const u8,
    ciphertext_len: usize,
    passphrase: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

// File operations
pub extern "C" fn age_encrypt_to_file(
    plaintext: [*]const u8,
    plaintext_len: usize,
    output_path: [*:0]const u8,
    recipient: [*:0]const u8,
) AgeResult;

pub extern "C" fn age_encrypt_to_file_armor(
    plaintext: [*]const u8,
    plaintext_len: usize,
    output_path: [*:0]const u8,
    recipient: [*:0]const u8,
) AgeResult;

pub extern "C" fn age_decrypt_file(
    input_path: [*:0]const u8,
    identity_path: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_decrypt_file_with_identity(
    input_path: [*:0]const u8,
    identity: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

pub extern "C" fn age_decrypt_file_passphrase(
    input_path: [*:0]const u8,
    passphrase: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

// Armor
pub extern "C" fn age_armor(
    data: [*]const u8,
    data_len: usize,
    output: *[*:0]u8,
) AgeResult;

pub extern "C" fn age_dearmor(
    armored: [*:0]const u8,
    output: *AgeBuffer,
) AgeResult;

// Validation
pub extern "C" fn age_is_valid_x25519_recipient(recipient: [*:0]const u8) bool;
pub extern "C" fn age_is_valid_x25519_identity(identity: [*:0]const u8) bool;
pub extern "C" fn age_is_valid_ssh_recipient(recipient: [*:0]const u8) bool;
pub extern "C" fn age_recipient_type(recipient: [*:0]const u8) c_int;

// Memory management
pub extern "C" fn age_free_buffer(buffer: *AgeBuffer) void;
pub extern "C" fn age_free_string(s: [*:0]u8) void;
pub extern "C" fn age_free_keypair(keypair: *AgeKeypair) void;

// ============================================================================
// Error Handling
// ============================================================================

pub const AgeError = error{
    InvalidInput,
    EncryptionFailed,
    DecryptionFailed,
    KeygenFailed,
    IoError,
    InvalidRecipient,
    InvalidIdentity,
    NoRecipients,
    NoIdentities,
    ArmorError,
    PassphraseRequired,
    InvalidPassphrase,
    SshKeyError,
    MemoryAllocationFailed,
    InvalidUtf8,
    UnsupportedKey,
};

fn resultToError(result: AgeResult) AgeError!void {
    return switch (result) {
        .success => {},
        .invalid_input => AgeError.InvalidInput,
        .encryption_failed => AgeError.EncryptionFailed,
        .decryption_failed => AgeError.DecryptionFailed,
        .keygen_failed => AgeError.KeygenFailed,
        .io_error => AgeError.IoError,
        .invalid_recipient => AgeError.InvalidRecipient,
        .invalid_identity => AgeError.InvalidIdentity,
        .no_recipients => AgeError.NoRecipients,
        .no_identities => AgeError.NoIdentities,
        .armor_error => AgeError.ArmorError,
        .passphrase_required => AgeError.PassphraseRequired,
        .invalid_passphrase => AgeError.InvalidPassphrase,
        .ssh_key_error => AgeError.SshKeyError,
        .memory_allocation_failed => AgeError.MemoryAllocationFailed,
        .invalid_utf8 => AgeError.InvalidUtf8,
        .unsupported_key => AgeError.UnsupportedKey,
    };
}

// ============================================================================
// RAII Wrappers for Memory Management
// ============================================================================

/// RAII wrapper for AgeBuffer that automatically frees on deinit
pub const Buffer = struct {
    buffer: AgeBuffer,

    pub fn deinit(self: *Buffer) void {
        age_free_buffer(&self.buffer);
    }

    pub fn toSlice(self: Buffer) []u8 {
        return self.buffer.toSlice();
    }

    pub fn toOwnedSlice(self: *Buffer, allocator: std.mem.Allocator) ![]u8 {
        const slice = try allocator.dupe(u8, self.buffer.toSlice());
        self.deinit();
        return slice;
    }
};

/// RAII wrapper for AgeKeypair that automatically frees on deinit
pub const Keypair = struct {
    keypair: AgeKeypair,

    pub fn deinit(self: *Keypair) void {
        age_free_keypair(&self.keypair);
    }

    pub fn getPublicKey(self: Keypair) [:0]const u8 {
        return self.keypair.getPublicKey();
    }

    pub fn getPrivateKey(self: Keypair) [:0]const u8 {
        return self.keypair.getPrivateKey();
    }
};

/// RAII wrapper for C strings that automatically frees on deinit
pub const CString = struct {
    ptr: [*:0]u8,

    pub fn deinit(self: CString) void {
        age_free_string(self.ptr);
    }

    pub fn slice(self: CString) [:0]const u8 {
        return std.mem.span(self.ptr);
    }
};

// ============================================================================
// High-Level Idiomatic Zig API
// ============================================================================

/// Get library version information
pub fn getVersion() [:0]const u8 {
    return std.mem.span(age_version());
}

/// Get underlying age library version
pub fn getLibVersion() [:0]const u8 {
    return std.mem.span(age_lib_version());
}

/// Generate a new x25519 keypair
pub fn generateKeypair() AgeError!Keypair {
    var keypair: AgeKeypair = undefined;
    const result = age_generate_x25519(&keypair);
    try resultToError(result);
    return Keypair{ .keypair = keypair };
}

/// Derive public key from a private x25519 identity
pub fn derivePublicKey(allocator: std.mem.Allocator, private_key: [:0]const u8) (AgeError || error{OutOfMemory})![]u8 {
    var public_key: [*:0]u8 = undefined;
    const result = age_x25519_to_public(private_key.ptr, &public_key);
    try resultToError(result);

    defer age_free_string(public_key);
    return allocator.dupe(u8, std.mem.span(public_key));
}

/// Encrypt data with a single recipient
pub fn encrypt(plaintext: []const u8, recipient: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_encrypt(
        plaintext.ptr,
        plaintext.len,
        recipient.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Encrypt data with multiple recipients
pub fn encryptMulti(plaintext: []const u8, recipients: []const [:0]const u8, use_armor: bool) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };

    // Convert Zig sentinel-terminated slices to C pointers
    // We need to build an array of [*:0]const u8 pointers
    var ptrs_buf: [16][*:0]const u8 = undefined;
    if (recipients.len > ptrs_buf.len) return AgeError.NoRecipients;

    for (recipients, 0..) |recip, i| {
        ptrs_buf[i] = recip.ptr;
    }

    const result = age_encrypt_multi(
        plaintext.ptr,
        plaintext.len,
        &ptrs_buf,
        recipients.len,
        use_armor,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Encrypt data with ASCII armor (returns armored string as bytes)
pub fn encryptArmor(plaintext: []const u8, recipient: [:0]const u8) AgeError!Buffer {
    var c_output: [*:0]u8 = undefined;
    const result = age_encrypt_armor(
        plaintext.ptr,
        plaintext.len,
        recipient.ptr,
        &c_output,
    );
    try resultToError(result);

    // Convert C string to buffer
    const str = std.mem.span(c_output);
    const output: AgeBuffer = .{
        .data = c_output,
        .len = str.len,
        .capacity = str.len,
    };

    return Buffer{ .buffer = output };
}

/// Decrypt data with a single identity
pub fn decrypt(ciphertext: []const u8, identity: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt(
        ciphertext.ptr,
        ciphertext.len,
        identity.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt data with multiple identities (tries each until one succeeds)
pub fn decryptMulti(ciphertext: []const u8, identities: []const [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };

    // Convert Zig sentinel-terminated slices to C pointers
    // We need to build an array of [*:0]const u8 pointers
    var ptrs_buf: [16][*:0]const u8 = undefined;
    if (identities.len > ptrs_buf.len) return AgeError.NoIdentities;

    for (identities, 0..) |ident, i| {
        ptrs_buf[i] = ident.ptr;
    }

    const result = age_decrypt_multi(
        ciphertext.ptr,
        ciphertext.len,
        &ptrs_buf,
        identities.len,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt using an SSH private key (from string)
pub fn decryptSsh(ciphertext: []const u8, ssh_key: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt_ssh(
        ciphertext.ptr,
        ciphertext.len,
        ssh_key.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt using an SSH private key file
pub fn decryptSshFile(ciphertext: []const u8, ssh_key_path: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt_ssh_file(
        ciphertext.ptr,
        ciphertext.len,
        ssh_key_path.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Encrypt with a passphrase
pub fn encryptPassphrase(plaintext: []const u8, passphrase: [:0]const u8, use_armor: bool) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_encrypt_passphrase(
        plaintext.ptr,
        plaintext.len,
        passphrase.ptr,
        use_armor,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt with a passphrase
/// Note: If the data is ASCII-armored, you must dearmor it first using dearmor()
/// or use decryptPassphraseArmored() for convenience.
pub fn decryptPassphrase(ciphertext: []const u8, passphrase: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt_passphrase(
        ciphertext.ptr,
        ciphertext.len,
        passphrase.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt armored passphrase-encrypted data (convenience function)
/// Automatically dearmors the data before decryption.
pub fn decryptPassphraseArmored(armored: []const u8, passphrase: [:0]const u8) AgeError!Buffer {
    // First dearmor the data
    var dearmored = try dearmor(armored);
    defer dearmored.deinit();

    // Then decrypt the binary data
    return try decryptPassphrase(dearmored.toSlice(), passphrase);
}

/// Encrypt data to a file
pub fn encryptToFile(plaintext: []const u8, recipient: [:0]const u8, output_path: [:0]const u8) AgeError!void {
    const result = age_encrypt_to_file(
        plaintext.ptr,
        plaintext.len,
        output_path.ptr,
        recipient.ptr,
    );
    try resultToError(result);
}

/// Encrypt data to a file with ASCII armor
pub fn encryptToFileArmor(plaintext: []const u8, recipient: [:0]const u8, output_path: [:0]const u8) AgeError!void {
    const result = age_encrypt_to_file_armor(
        plaintext.ptr,
        plaintext.len,
        output_path.ptr,
        recipient.ptr,
    );
    try resultToError(result);
}

/// Decrypt from a file using an identity file
pub fn decryptFile(input_path: [:0]const u8, identity_path: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt_file(
        input_path.ptr,
        identity_path.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt from a file using an identity string
pub fn decryptFileWithIdentity(input_path: [:0]const u8, identity: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt_file_with_identity(
        input_path.ptr,
        identity.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Decrypt from a file using a passphrase
pub fn decryptFilePassphrase(input_path: [:0]const u8, passphrase: [:0]const u8) AgeError!Buffer {
    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_decrypt_file_passphrase(
        input_path.ptr,
        passphrase.ptr,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

/// Wrap binary data in ASCII armor (returns armored string as bytes)
pub fn armor(data: []const u8) AgeError!Buffer {
    var c_output: [*:0]u8 = undefined;
    const result = age_armor(
        data.ptr,
        data.len,
        &c_output,
    );
    try resultToError(result);

    // Convert C string to buffer
    const str = std.mem.span(c_output);
    const output: AgeBuffer = .{
        .data = c_output,
        .len = str.len,
        .capacity = str.len,
    };

    return Buffer{ .buffer = output };
}

/// Remove ASCII armor from armored string
pub fn dearmor(armored: []const u8) AgeError!Buffer {
    // Need to ensure the armored data is null-terminated
    // Since it's coming from armor() it should be, but we need to treat it as a C string
    const c_armored: [*:0]const u8 = @ptrCast(armored.ptr);

    var output: AgeBuffer = .{ .data = undefined, .len = 0, .capacity = 0 };
    const result = age_dearmor(
        c_armored,
        &output,
    );
    try resultToError(result);
    return Buffer{ .buffer = output };
}

// ============================================================================
// Validation Functions
// ============================================================================

/// Validate an x25519 recipient (public key)
pub fn isValidX25519Recipient(recipient: [:0]const u8) bool {
    return age_is_valid_x25519_recipient(recipient.ptr);
}

/// Validate an x25519 identity (private key)
pub fn isValidX25519Identity(identity: [:0]const u8) bool {
    return age_is_valid_x25519_identity(identity.ptr);
}

/// Validate an SSH recipient
pub fn isValidSshRecipient(recipient: [:0]const u8) bool {
    return age_is_valid_ssh_recipient(recipient.ptr);
}

/// Identify recipient type (0=invalid, 1=x25519, 2=ssh)
pub const RecipientType = enum(c_int) {
    invalid = 0,
    x25519 = 1,
    ssh = 2,
};

pub fn getRecipientType(recipient: [:0]const u8) RecipientType {
    const type_code = age_recipient_type(recipient.ptr);
    return @enumFromInt(type_code);
}
