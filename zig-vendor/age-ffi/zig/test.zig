//! Test suite for age-ffi Zig bindings

const std = @import("std");
const age = @import("age.zig");
const testing = std.testing;

test "version information" {
    const version = age.getVersion();
    const lib_version = age.getLibVersion();

    try testing.expect(version.len > 0);
    try testing.expect(lib_version.len > 0);

    std.debug.print("\nLibrary version: {s}\n", .{version});
    std.debug.print("Age library version: {s}\n", .{lib_version});
}

test "generate keypair" {
    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    const public_key = keypair.getPublicKey();
    const private_key = keypair.getPrivateKey();

    try testing.expect(public_key.len > 0);
    try testing.expect(private_key.len > 0);
    try testing.expect(std.mem.startsWith(u8, public_key, "age1"));
    try testing.expect(std.mem.startsWith(u8, private_key, "AGE-SECRET-KEY-1"));

    std.debug.print("\nGenerated keypair:\n", .{});
    std.debug.print("  Public:  {s}\n", .{public_key});
    std.debug.print("  Private: {s}\n", .{private_key});
}

test "derive public key from private" {
    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    const derived = try age.derivePublicKey(testing.allocator, keypair.getPrivateKey());
    defer testing.allocator.free(derived);

    try testing.expectEqualStrings(keypair.getPublicKey(), derived);
    std.debug.print("\nDerived public key matches: ✓\n", .{});
}

test "simple encrypt and decrypt" {
    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    const plaintext = "Hello, World! This is a test message.";

    // Encrypt
    var encrypted = try age.encrypt(plaintext, keypair.getPublicKey());
    defer encrypted.deinit();

    try testing.expect(encrypted.buffer.len > 0);
    std.debug.print("\nEncrypted {} bytes\n", .{encrypted.buffer.len});

    // Decrypt
    var decrypted = try age.decrypt(encrypted.toSlice(), keypair.getPrivateKey());
    defer decrypted.deinit();

    try testing.expectEqualStrings(plaintext, decrypted.toSlice());
    std.debug.print("Decrypted successfully: {s}\n", .{decrypted.toSlice()});
}

test "encrypt with armor" {
    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    const plaintext = "This message will be ASCII armored.";

    std.debug.print("\nTesting ASCII armor encryption...\n", .{});
    std.debug.print("Plaintext: {s}\n", .{plaintext});
    std.debug.print("Recipient: {s}\n", .{keypair.getPublicKey()});

    // Encrypt with armor
    var encrypted = try age.encryptArmor(plaintext, keypair.getPublicKey());
    defer encrypted.deinit();

    std.debug.print("Buffer after encryption:\n", .{});
    std.debug.print("  len: {}\n", .{encrypted.buffer.len});
    std.debug.print("  capacity: {}\n", .{encrypted.buffer.capacity});

    try testing.expect(encrypted.buffer.len > 0);

    const ciphertext = encrypted.toSlice();
    std.debug.print("Encrypted {} bytes\n", .{ciphertext.len});

    // Check if it looks like ASCII armor
    if (ciphertext.len > 0) {
        const has_armor_header = std.mem.indexOf(u8, ciphertext, "-----BEGIN AGE ENCRYPTED FILE-----") != null;
        std.debug.print("Has armor header: {}\n", .{has_armor_header});

        if (ciphertext.len < 500) {
            std.debug.print("Ciphertext:\n{s}\n", .{ciphertext});
        }
    }

    // Decrypt
    var decrypted = try age.decrypt(ciphertext, keypair.getPrivateKey());
    defer decrypted.deinit();

    try testing.expectEqualStrings(plaintext, decrypted.toSlice());
    std.debug.print("Decrypted successfully: {s}\n", .{decrypted.toSlice()});
}

test "passphrase encryption" {
    const plaintext = "Secret message encrypted with passphrase";
    const passphrase = "super-secret-password";

    // Encrypt
    var encrypted = try age.encryptPassphrase(plaintext, passphrase, false);
    defer encrypted.deinit();

    try testing.expect(encrypted.buffer.len > 0);
    std.debug.print("\nPassphrase encrypted {} bytes\n", .{encrypted.buffer.len});

    // Decrypt
    var decrypted = try age.decryptPassphrase(encrypted.toSlice(), passphrase);
    defer decrypted.deinit();

    try testing.expectEqualStrings(plaintext, decrypted.toSlice());
    std.debug.print("Decrypted: {s}\n", .{decrypted.toSlice()});
}

test "passphrase encryption with armor (manual dearmor)" {
    const plaintext = "Secret message with armor";
    const passphrase = "test-password";

    // Encrypt with armor
    var encrypted = try age.encryptPassphrase(plaintext, passphrase, true);
    defer encrypted.deinit();

    try testing.expect(encrypted.buffer.len > 0);
    std.debug.print("\nPassphrase encrypted with armor: {} bytes\n", .{encrypted.buffer.len});

    const ciphertext = encrypted.toSlice();
    const has_armor = std.mem.indexOf(u8, ciphertext, "-----BEGIN") != null;
    try testing.expect(has_armor);
    std.debug.print("Has ASCII armor: ✓\n", .{});

    // For passphrase encryption, armored data must be dearmored before decryption
    // (unlike x25519 encryption where age_decrypt auto-detects armor)
    std.debug.print("Manually dearmoring before passphrase decryption...\n", .{});
    var dearmored = try age.dearmor(ciphertext);
    defer dearmored.deinit();

    std.debug.print("Dearmored to {} bytes\n", .{dearmored.buffer.len});

    // Now decrypt the binary data
    var decrypted = try age.decryptPassphrase(dearmored.toSlice(), passphrase);
    defer decrypted.deinit();

    try testing.expectEqualStrings(plaintext, decrypted.toSlice());
    std.debug.print("Successfully decrypted armored passphrase data: ✓\n", .{});
}

test "passphrase encryption with armor (convenience function)" {
    const plaintext = "Testing convenience function";
    const passphrase = "convenient-pass";

    // Encrypt with armor
    var encrypted = try age.encryptPassphrase(plaintext, passphrase, true);
    defer encrypted.deinit();

    std.debug.print("\nTesting decryptPassphraseArmored convenience function...\n", .{});

    // Use the convenience function that handles dearmoring automatically
    var decrypted = try age.decryptPassphraseArmored(encrypted.toSlice(), passphrase);
    defer decrypted.deinit();

    try testing.expectEqualStrings(plaintext, decrypted.toSlice());
    std.debug.print("Convenience function works: ✓\n", .{});
}

test "multiple recipients" {
    var keypair1 = try age.generateKeypair();
    defer keypair1.deinit();

    var keypair2 = try age.generateKeypair();
    defer keypair2.deinit();

    const plaintext = "Message for multiple recipients";
    const recipients = [_][:0]const u8{
        keypair1.getPublicKey(),
        keypair2.getPublicKey(),
    };

    // Encrypt for both recipients
    var encrypted = try age.encryptMulti(plaintext, &recipients, false);
    defer encrypted.deinit();

    try testing.expect(encrypted.buffer.len > 0);
    std.debug.print("\nEncrypted for {} recipients: {} bytes\n", .{ recipients.len, encrypted.buffer.len });

    // Decrypt with first key
    var decrypted1 = try age.decrypt(encrypted.toSlice(), keypair1.getPrivateKey());
    defer decrypted1.deinit();
    try testing.expectEqualStrings(plaintext, decrypted1.toSlice());
    std.debug.print("Decrypted with key 1: ✓\n", .{});

    // Decrypt with second key
    var decrypted2 = try age.decrypt(encrypted.toSlice(), keypair2.getPrivateKey());
    defer decrypted2.deinit();
    try testing.expectEqualStrings(plaintext, decrypted2.toSlice());
    std.debug.print("Decrypted with key 2: ✓\n", .{});
}

test "validation functions" {
    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    // Valid keys
    try testing.expect(age.isValidX25519Recipient(keypair.getPublicKey()));
    try testing.expect(age.isValidX25519Identity(keypair.getPrivateKey()));

    std.debug.print("\nValidation tests:\n", .{});
    std.debug.print("  Valid recipient: ✓\n", .{});
    std.debug.print("  Valid identity: ✓\n", .{});

    // Invalid keys
    try testing.expect(!age.isValidX25519Recipient("not-a-key"));
    try testing.expect(!age.isValidX25519Identity("not-a-key"));
    std.debug.print("  Invalid key detection: ✓\n", .{});

    // Recipient type
    const recip_type = age.getRecipientType(keypair.getPublicKey());
    try testing.expectEqual(age.RecipientType.x25519, recip_type);
    std.debug.print("  Recipient type: {s}\n", .{@tagName(recip_type)});
}

test "error handling - wrong key" {
    var keypair1 = try age.generateKeypair();
    defer keypair1.deinit();

    var keypair2 = try age.generateKeypair();
    defer keypair2.deinit();

    const plaintext = "Encrypted for keypair1";

    var encrypted = try age.encrypt(plaintext, keypair1.getPublicKey());
    defer encrypted.deinit();

    // Try to decrypt with wrong key
    const result = age.decrypt(encrypted.toSlice(), keypair2.getPrivateKey());
    try testing.expectError(age.AgeError.DecryptionFailed, result);
    std.debug.print("\nWrong key error: ✓\n", .{});
}

test "error handling - invalid recipient" {
    const plaintext = "Test message";
    const invalid_recipient = "not-a-valid-recipient";

    const result = age.encrypt(plaintext, invalid_recipient);
    try testing.expectError(age.AgeError.InvalidRecipient, result);
    std.debug.print("\nInvalid recipient error: ✓\n", .{});
}

test "error handling - invalid passphrase" {
    const plaintext = "Secret";
    const correct_pass = "correct";
    const wrong_pass = "wrong";

    var encrypted = try age.encryptPassphrase(plaintext, correct_pass, false);
    defer encrypted.deinit();

    const result = age.decryptPassphrase(encrypted.toSlice(), wrong_pass);
    // Note: The underlying age library returns DecryptionFailed for wrong passphrase
    // rather than a specific InvalidPassphrase error
    try testing.expectError(age.AgeError.DecryptionFailed, result);
    std.debug.print("\nInvalid passphrase error: ✓\n", .{});
}

test "armor and dearmor operations" {
    const data = "Some binary data to armor";

    // Armor the data
    var armored = try age.armor(data);
    defer armored.deinit();

    try testing.expect(armored.buffer.len > 0);
    std.debug.print("\nArmored {} bytes -> {} bytes\n", .{ data.len, armored.buffer.len });

    const armored_data = armored.toSlice();
    const has_header = std.mem.indexOf(u8, armored_data, "-----BEGIN") != null;
    try testing.expect(has_header);

    // Dearmor it
    var dearmored = try age.dearmor(armored_data);
    defer dearmored.deinit();

    try testing.expectEqualStrings(data, dearmored.toSlice());
    std.debug.print("Dearmored successfully: ✓\n", .{});
}

test "file operations" {
    const tmp_file = "/tmp/age_test_encrypted.age";
    const plaintext = "File encryption test data";

    var keypair = try age.generateKeypair();
    defer keypair.deinit();

    // Encrypt to file
    try age.encryptToFile(plaintext, keypair.getPublicKey(), tmp_file);
    std.debug.print("\nEncrypted to file: {s}\n", .{tmp_file});

    // Decrypt from file
    var decrypted = try age.decryptFileWithIdentity(tmp_file, keypair.getPrivateKey());
    defer decrypted.deinit();

    try testing.expectEqualStrings(plaintext, decrypted.toSlice());
    std.debug.print("Decrypted from file: ✓\n", .{});

    // Clean up
    std.fs.cwd().deleteFile(tmp_file) catch {};
}
