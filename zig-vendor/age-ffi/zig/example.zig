//! Example usage of the age-ffi Zig bindings
//!
//! This file demonstrates various encryption/decryption operations using the age library.

const std = @import("std");
const age = @import("age.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Set up unbuffered stdout for Zig 0.15+ (simpler for examples)
    // var stdout_writer = std.fs.File.stdout().writer(&.{});
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;

    try stdout.print("age-ffi Zig Bindings Example\n", .{});
    try stdout.print("============================\n\n", .{});

    // Print version information
    try stdout.print("Library version: {s}\n", .{age.getVersion()});
    try stdout.print("Age library version: {s}\n\n", .{age.getLibVersion()});

    // Example 1: Generate a keypair
    try stdout.print("Example 1: Generating a keypair\n", .{});
    try stdout.print("--------------------------------\n", .{});

    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    try stdout.print("Public key:  {s}\n", .{keypair.getPublicKey()});
    try stdout.print("Private key: {s}\n\n", .{keypair.getPrivateKey()});
    try stdout.flush();

    // Example 2: Simple encryption and decryption
    try stdout.print("Example 2: Simple encryption/decryption\n", .{});
    try stdout.print("---------------------------------------\n", .{});

    const plaintext = "Hello, World! This is a secret message.";
    try stdout.print("Original: {s}\n", .{plaintext});

    // Encrypt
    var encrypted = try age.encrypt(plaintext, keypair.getPublicKey());
    defer encrypted.deinit();

    try stdout.print("Encrypted: {} bytes\n", .{encrypted.buffer.len});

    // Decrypt
    var decrypted = try age.decrypt(encrypted.toSlice(), keypair.getPrivateKey());
    defer decrypted.deinit();

    try stdout.print("Decrypted: {s}\n\n", .{decrypted.toSlice()});
    try stdout.flush();

    // Example 3: ASCII armor
    try stdout.print("Example 3: ASCII armor encryption\n", .{});
    try stdout.print("----------------------------------\n", .{});

    var armored = try age.encryptArmor("This message will be ASCII armored.", keypair.getPublicKey());
    defer armored.deinit();

    try stdout.print("Encrypted with ASCII armor: {} bytes\n", .{armored.buffer.len});

    // Decrypt armored message
    var decrypted_armored = try age.decrypt(armored.toSlice(), keypair.getPrivateKey());
    defer decrypted_armored.deinit();

    try stdout.print("Decrypted successfully: {s}\n\n", .{decrypted_armored.toSlice()});
    try stdout.flush();

    // Example 4: Passphrase-based encryption
    try stdout.print("Example 4: Passphrase encryption\n", .{});
    try stdout.print("---------------------------------\n", .{});

    const passphrase = "super-secret-passphrase";
    const secret_data = "Encrypted with a passphrase!";

    // Encrypt without armor (armor with passphrase has decryption issues in upstream library)
    var pass_encrypted = try age.encryptPassphrase(secret_data, passphrase, false);
    defer pass_encrypted.deinit();

    try stdout.print("Passphrase-encrypted: {} bytes\n", .{pass_encrypted.buffer.len});

    var pass_decrypted = try age.decryptPassphrase(pass_encrypted.toSlice(), passphrase);
    defer pass_decrypted.deinit();

    try stdout.print("Decrypted: {s}\n\n", .{pass_decrypted.toSlice()});
    try stdout.flush();

    // Example 5: Multiple recipients
    try stdout.print("Example 5: Multiple recipients\n", .{});
    try stdout.print("-------------------------------\n", .{});

    // Generate a second keypair
    var keypair2 = try age.generateKeypair();
    defer keypair2.deinit();

    try stdout.print("Recipient 1: {s}\n", .{keypair.getPublicKey()});
    try stdout.print("Recipient 2: {s}\n", .{keypair2.getPublicKey()});

    // Create array of recipients
    const recipients = [_][:0]const u8{
        keypair.getPublicKey(),
        keypair2.getPublicKey(),
    };

    const multi_plaintext = "This can be decrypted by either recipient!";
    var multi_encrypted = try age.encryptMulti(multi_plaintext, &recipients, false);
    defer multi_encrypted.deinit();

    try stdout.print("Encrypted for both recipients ({} bytes)\n", .{multi_encrypted.buffer.len});

    // Decrypt with first identity
    var multi_decrypted1 = try age.decrypt(multi_encrypted.toSlice(), keypair.getPrivateKey());
    defer multi_decrypted1.deinit();

    try stdout.print("Decrypted with key 1: {s}\n", .{multi_decrypted1.toSlice()});

    // Decrypt with second identity
    var multi_decrypted2 = try age.decrypt(multi_encrypted.toSlice(), keypair2.getPrivateKey());
    defer multi_decrypted2.deinit();

    try stdout.print("Decrypted with key 2: {s}\n\n", .{multi_decrypted2.toSlice()});

    try stdout.flush();
    // Example 6: File operations
    try stdout.print("Example 6: File encryption/decryption\n", .{});
    try stdout.print("--------------------------------------\n", .{});

    const file_data = "This will be written to an encrypted file.";
    const encrypted_file = "/tmp/test.age";

    // Encrypt to file (non-armored)
    try age.encryptToFile(file_data, keypair.getPublicKey(), encrypted_file);
    try stdout.print("Encrypted to file: {s}\n", .{encrypted_file});

    // Decrypt from file
    var file_decrypted = try age.decryptFileWithIdentity(encrypted_file, keypair.getPrivateKey());
    defer file_decrypted.deinit();

    try stdout.print("Decrypted from file: {s}\n\n", .{file_decrypted.toSlice()});

    try stdout.flush();
    // Example 7: Validation
    try stdout.print("Example 7: Key validation\n", .{});
    try stdout.print("--------------------------\n", .{});

    const valid_recipient = keypair.getPublicKey();
    const valid_identity = keypair.getPrivateKey();
    const invalid_key = "not-a-valid-key";

    try stdout.print("Is '{s}' a valid recipient? {}\n", .{ valid_recipient, age.isValidX25519Recipient(valid_recipient) });
    try stdout.print("Is '{s}' a valid identity? {}\n", .{ valid_identity, age.isValidX25519Identity(valid_identity) });
    try stdout.print("Is '{s}' a valid recipient? {}\n", .{ invalid_key, age.isValidX25519Recipient(invalid_key) });

    const recipient_type = age.getRecipientType(valid_recipient);
    try stdout.print("Recipient type: {s}\n\n", .{@tagName(recipient_type)});

    try stdout.flush();
    // Example 8: Deriving public key from private key
    try stdout.print("Example 8: Derive public key\n", .{});
    try stdout.print("-----------------------------\n", .{});

    const derived_public = try age.derivePublicKey(gpa, keypair.getPrivateKey());
    defer gpa.free(derived_public);

    try stdout.print("Original public:  {s}\n", .{keypair.getPublicKey()});
    try stdout.print("Derived public:   {s}\n", .{derived_public});
    try stdout.print("Keys match: {}\n\n", .{std.mem.eql(u8, keypair.getPublicKey(), derived_public)});

    try stdout.flush();
    // Example 9: Error handling
    try stdout.print("Example 9: Error handling\n", .{});
    try stdout.print("-------------------------\n", .{});

    // Try to decrypt with wrong key
    if (age.decrypt(encrypted.toSlice(), keypair2.getPrivateKey())) |_| {
        try stdout.print("Unexpected success!\n", .{});
    } else |err| {
        try stdout.print("Expected error: {s}\n", .{@errorName(err)});
    }

    // Try to use invalid passphrase
    if (age.decryptPassphrase(pass_encrypted.toSlice(), "wrong-passphrase")) |_| {
        try stdout.print("Unexpected success!\n", .{});
    } else |err| {
        try stdout.print("Expected error: {s}\n", .{@errorName(err)});
    }

    try stdout.print("\nAll examples completed successfully!\n", .{});

    // Flush all output to ensure it's displayed
    try stdout.flush();
}
