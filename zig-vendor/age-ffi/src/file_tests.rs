//! Tests for file-based encryption and decryption functions.

use crate::file::*;
use crate::keys::*;
use crate::memory::*;
use crate::passphrase::*;
use crate::types::*;
use std::ffi::CString;
use std::fs;
use std::io::Write;

fn create_temp_file(suffix: &str) -> String {
    let temp_dir = std::env::temp_dir();
    let unique_id = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    format!("{}/age_test_{}_{}", temp_dir.display(), unique_id, suffix)
}

// ============= age_encrypt_to_file tests =============

#[test]
fn test_encrypt_to_file_basic() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Hello, file encryption!";
    let output_path = create_temp_file("encrypted.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        output_path_c.as_ptr(),
        keypair.public_key,
    );

    assert_eq!(result, AgeResult::Success);
    assert!(std::path::Path::new(&output_path).exists());

    // Clean up
    fs::remove_file(&output_path).ok();
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_to_file_null_plaintext() {
    let output_path = create_temp_file("test.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();
    let recipient = CString::new("age1test").unwrap();

    let result = age_encrypt_to_file(
        std::ptr::null(),
        0,
        output_path_c.as_ptr(),
        recipient.as_ptr(),
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_encrypt_to_file_null_output_path() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        std::ptr::null(),
        keypair.public_key,
    );

    assert_eq!(result, AgeResult::InvalidInput);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_to_file_null_recipient() {
    let plaintext = b"test";
    let output_path = create_temp_file("test.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        output_path_c.as_ptr(),
        std::ptr::null(),
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_encrypt_to_file_invalid_recipient() {
    let plaintext = b"test";
    let output_path = create_temp_file("test.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();
    let invalid_recipient = CString::new("age1invalid_not_a_real_key").unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        output_path_c.as_ptr(),
        invalid_recipient.as_ptr(),
    );

    assert_eq!(result, AgeResult::InvalidRecipient);
}

#[test]
fn test_encrypt_to_file_and_decrypt_with_identity() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Round trip file encryption test!";
    let output_path = create_temp_file("roundtrip.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();

    // Encrypt to file
    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        output_path_c.as_ptr(),
        keypair.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    // Decrypt with identity string
    let mut output = AgeBuffer::null();
    let result = age_decrypt_file_with_identity(
        output_path_c.as_ptr(),
        keypair.private_key,
        &mut output,
    );

    assert_eq!(result, AgeResult::Success);

    let decrypted = unsafe { std::slice::from_raw_parts(output.data, output.len) };
    assert_eq!(decrypted, plaintext);

    // Clean up
    fs::remove_file(&output_path).ok();
    age_free_buffer(&mut output);
    age_free_keypair(&mut keypair);
}

// ============= age_encrypt_to_file_armor tests =============

#[test]
fn test_encrypt_to_file_armor_basic() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Armored file test";
    let output_path = create_temp_file("armored.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();

    let result = age_encrypt_to_file_armor(
        plaintext.as_ptr(),
        plaintext.len(),
        output_path_c.as_ptr(),
        keypair.public_key,
    );

    assert_eq!(result, AgeResult::Success);

    // Verify the file is armored
    let contents = fs::read_to_string(&output_path).unwrap();
    assert!(contents.contains("-----BEGIN AGE ENCRYPTED FILE-----"));
    assert!(contents.contains("-----END AGE ENCRYPTED FILE-----"));

    // Clean up
    fs::remove_file(&output_path).ok();
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_to_file_armor_null_plaintext() {
    let output_path = create_temp_file("test.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();
    let recipient = CString::new("age1test").unwrap();

    let result = age_encrypt_to_file_armor(
        std::ptr::null(),
        0,
        output_path_c.as_ptr(),
        recipient.as_ptr(),
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_encrypt_to_file_armor_null_output_path() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";

    let result = age_encrypt_to_file_armor(
        plaintext.as_ptr(),
        plaintext.len(),
        std::ptr::null(),
        keypair.public_key,
    );

    assert_eq!(result, AgeResult::InvalidInput);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_to_file_armor_invalid_recipient() {
    let plaintext = b"test";
    let output_path = create_temp_file("test.age");
    let output_path_c = CString::new(output_path.as_str()).unwrap();
    let invalid_recipient = CString::new("not-a-recipient").unwrap();

    let result = age_encrypt_to_file_armor(
        plaintext.as_ptr(),
        plaintext.len(),
        output_path_c.as_ptr(),
        invalid_recipient.as_ptr(),
    );

    assert_eq!(result, AgeResult::InvalidRecipient);
}

// ============= age_decrypt_file tests =============

#[test]
fn test_decrypt_file_basic() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Decrypt from identity file test";

    // Create encrypted file
    let encrypted_path = create_temp_file("encrypted.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        keypair.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    // Create identity file
    let identity_path = create_temp_file("identity.txt");
    let private_key = unsafe { std::ffi::CStr::from_ptr(keypair.private_key).to_str().unwrap() };
    fs::write(&identity_path, private_key).unwrap();
    let identity_path_c = CString::new(identity_path.as_str()).unwrap();

    // Decrypt
    let mut output = AgeBuffer::null();
    let result = age_decrypt_file(
        encrypted_path_c.as_ptr(),
        identity_path_c.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::Success);

    let decrypted = unsafe { std::slice::from_raw_parts(output.data, output.len) };
    assert_eq!(decrypted, plaintext);

    // Clean up
    fs::remove_file(&encrypted_path).ok();
    fs::remove_file(&identity_path).ok();
    age_free_buffer(&mut output);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_file_null_output() {
    let encrypted_path = CString::new("/tmp/test.age").unwrap();
    let identity_path = CString::new("/tmp/identity.txt").unwrap();

    let result = age_decrypt_file(
        encrypted_path.as_ptr(),
        identity_path.as_ptr(),
        std::ptr::null_mut(),
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_decrypt_file_null_encrypted_path() {
    let identity_path = CString::new("/tmp/identity.txt").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file(
        std::ptr::null(),
        identity_path.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_decrypt_file_nonexistent_identity_file() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Create a real encrypted file
    let plaintext = b"test";
    let encrypted_path = create_temp_file("test_enc.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        keypair.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    // Try to decrypt with nonexistent identity file
    let identity_path = CString::new("/nonexistent/identity.txt").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file(
        encrypted_path_c.as_ptr(),
        identity_path.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::IoError);

    fs::remove_file(&encrypted_path).ok();
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_file_nonexistent_encrypted_file() {
    // Create a valid identity file
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let identity_path = create_temp_file("identity.txt");
    let private_key = unsafe { std::ffi::CStr::from_ptr(keypair.private_key).to_str().unwrap() };
    fs::write(&identity_path, private_key).unwrap();
    let identity_path_c = CString::new(identity_path.as_str()).unwrap();

    let encrypted_path = CString::new("/nonexistent/encrypted.age").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file(
        encrypted_path.as_ptr(),
        identity_path_c.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::IoError);

    fs::remove_file(&identity_path).ok();
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_file_empty_identity_file() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Create encrypted file
    let plaintext = b"test";
    let encrypted_path = create_temp_file("enc.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        keypair.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    // Create empty identity file
    let identity_path = create_temp_file("empty_identity.txt");
    fs::write(&identity_path, "").unwrap();
    let identity_path_c = CString::new(identity_path.as_str()).unwrap();

    let mut output = AgeBuffer::null();
    let result = age_decrypt_file(
        encrypted_path_c.as_ptr(),
        identity_path_c.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::InvalidIdentity);

    fs::remove_file(&encrypted_path).ok();
    fs::remove_file(&identity_path).ok();
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_file_with_comments_in_identity() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Create encrypted file
    let plaintext = b"test with comments";
    let encrypted_path = create_temp_file("enc_comments.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        keypair.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    // Create identity file with comments
    let identity_path = create_temp_file("identity_with_comments.txt");
    let private_key = unsafe { std::ffi::CStr::from_ptr(keypair.private_key).to_str().unwrap() };
    let content = format!("# This is a comment\n\n{}\n# Another comment", private_key);
    fs::write(&identity_path, content).unwrap();
    let identity_path_c = CString::new(identity_path.as_str()).unwrap();

    let mut output = AgeBuffer::null();
    let result = age_decrypt_file(
        encrypted_path_c.as_ptr(),
        identity_path_c.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::Success);

    let decrypted = unsafe { std::slice::from_raw_parts(output.data, output.len) };
    assert_eq!(decrypted, plaintext);

    fs::remove_file(&encrypted_path).ok();
    fs::remove_file(&identity_path).ok();
    age_free_buffer(&mut output);
    age_free_keypair(&mut keypair);
}

// ============= age_decrypt_file_with_identity tests =============

#[test]
fn test_decrypt_file_with_identity_null_output() {
    let encrypted_path = CString::new("/tmp/test.age").unwrap();
    let identity = CString::new("AGE-SECRET-KEY-1TEST").unwrap();

    let result = age_decrypt_file_with_identity(
        encrypted_path.as_ptr(),
        identity.as_ptr(),
        std::ptr::null_mut(),
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_decrypt_file_with_identity_null_path() {
    let identity = CString::new("AGE-SECRET-KEY-1TEST").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file_with_identity(
        std::ptr::null(),
        identity.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_decrypt_file_with_identity_invalid_identity() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Create encrypted file
    let plaintext = b"test";
    let encrypted_path = create_temp_file("enc_invalid_id.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        keypair.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    let invalid_identity = CString::new("not-a-valid-identity").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file_with_identity(
        encrypted_path_c.as_ptr(),
        invalid_identity.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::InvalidIdentity);

    fs::remove_file(&encrypted_path).ok();
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_file_with_identity_wrong_key() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    // Encrypt with keypair1
    let plaintext = b"secret message";
    let encrypted_path = create_temp_file("wrong_key.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        keypair1.public_key,
    );
    assert_eq!(result, AgeResult::Success);

    // Try to decrypt with keypair2
    let mut output = AgeBuffer::null();
    let result = age_decrypt_file_with_identity(
        encrypted_path_c.as_ptr(),
        keypair2.private_key,
        &mut output,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    fs::remove_file(&encrypted_path).ok();
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}

#[test]
fn test_decrypt_file_with_identity_nonexistent_file() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let encrypted_path = CString::new("/nonexistent/file.age").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file_with_identity(
        encrypted_path.as_ptr(),
        keypair.private_key,
        &mut output,
    );

    assert_eq!(result, AgeResult::IoError);

    age_free_keypair(&mut keypair);
}

// ============= age_decrypt_file_passphrase tests =============

#[test]
fn test_decrypt_file_passphrase_basic() {
    let passphrase = CString::new("mysecretpassword").unwrap();
    let plaintext = b"Passphrase protected content";

    // Encrypt with passphrase first (using in-memory function)
    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    // Write encrypted content to file
    let encrypted_path = create_temp_file("passphrase.age");
    let encrypted_slice = unsafe { std::slice::from_raw_parts(encrypted.data, encrypted.len) };
    fs::write(&encrypted_path, encrypted_slice).unwrap();
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    // Decrypt file with passphrase
    let mut output = AgeBuffer::null();
    let result = age_decrypt_file_passphrase(
        encrypted_path_c.as_ptr(),
        passphrase.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::Success);

    let decrypted = unsafe { std::slice::from_raw_parts(output.data, output.len) };
    assert_eq!(decrypted, plaintext);

    // Clean up
    fs::remove_file(&encrypted_path).ok();
    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut output);
}

#[test]
fn test_decrypt_file_passphrase_null_output() {
    let encrypted_path = CString::new("/tmp/test.age").unwrap();
    let passphrase = CString::new("password").unwrap();

    let result = age_decrypt_file_passphrase(
        encrypted_path.as_ptr(),
        passphrase.as_ptr(),
        std::ptr::null_mut(),
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_decrypt_file_passphrase_null_path() {
    let passphrase = CString::new("password").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file_passphrase(
        std::ptr::null(),
        passphrase.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_decrypt_file_passphrase_wrong_passphrase() {
    let passphrase = CString::new("correctpassword").unwrap();
    let wrong_passphrase = CString::new("wrongpassword").unwrap();
    let plaintext = b"Secret content";

    // Encrypt with passphrase
    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    // Write to file
    let encrypted_path = create_temp_file("wrong_pass.age");
    let encrypted_slice = unsafe { std::slice::from_raw_parts(encrypted.data, encrypted.len) };
    fs::write(&encrypted_path, encrypted_slice).unwrap();
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    // Try to decrypt with wrong passphrase
    let mut output = AgeBuffer::null();
    let result = age_decrypt_file_passphrase(
        encrypted_path_c.as_ptr(),
        wrong_passphrase.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    // Clean up
    fs::remove_file(&encrypted_path).ok();
    age_free_buffer(&mut encrypted);
}

#[test]
fn test_decrypt_file_passphrase_nonexistent_file() {
    let passphrase = CString::new("password").unwrap();
    let encrypted_path = CString::new("/nonexistent/passphrase.age").unwrap();
    let mut output = AgeBuffer::null();

    let result = age_decrypt_file_passphrase(
        encrypted_path.as_ptr(),
        passphrase.as_ptr(),
        &mut output,
    );

    assert_eq!(result, AgeResult::IoError);
}

// ============= Recipient file tests =============

#[test]
fn test_encrypt_to_file_with_recipients_file() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    // Create recipients file
    let recipients_path = create_temp_file("recipients.txt");
    let pub_key1 = unsafe { std::ffi::CStr::from_ptr(keypair1.public_key).to_str().unwrap() };
    let pub_key2 = unsafe { std::ffi::CStr::from_ptr(keypair2.public_key).to_str().unwrap() };
    let content = format!("# Comment line\n{}\n{}\n", pub_key1, pub_key2);
    fs::write(&recipients_path, content).unwrap();
    let recipients_path_c = CString::new(recipients_path.as_str()).unwrap();

    // Encrypt to file
    let plaintext = b"Multi-recipient from file test";
    let encrypted_path = create_temp_file("multi_recip.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        recipients_path_c.as_ptr(),
    );

    assert_eq!(result, AgeResult::Success);

    // Both recipients should be able to decrypt
    let mut output1 = AgeBuffer::null();
    let result = age_decrypt_file_with_identity(
        encrypted_path_c.as_ptr(),
        keypair1.private_key,
        &mut output1,
    );
    assert_eq!(result, AgeResult::Success);

    let mut output2 = AgeBuffer::null();
    let result = age_decrypt_file_with_identity(
        encrypted_path_c.as_ptr(),
        keypair2.private_key,
        &mut output2,
    );
    assert_eq!(result, AgeResult::Success);

    // Clean up
    fs::remove_file(&recipients_path).ok();
    fs::remove_file(&encrypted_path).ok();
    age_free_buffer(&mut output1);
    age_free_buffer(&mut output2);
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}

#[test]
fn test_encrypt_to_file_empty_recipients_file() {
    let plaintext = b"test";
    let encrypted_path = create_temp_file("empty_recip.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    // Create empty recipients file
    let recipients_path = create_temp_file("empty_recipients.txt");
    fs::write(&recipients_path, "# Only comments\n\n").unwrap();
    let recipients_path_c = CString::new(recipients_path.as_str()).unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        recipients_path_c.as_ptr(),
    );

    assert_eq!(result, AgeResult::InvalidRecipient);

    // Clean up
    fs::remove_file(&recipients_path).ok();
}

#[test]
fn test_encrypt_to_file_nonexistent_recipients_file() {
    let plaintext = b"test";
    let encrypted_path = create_temp_file("test.age");
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();
    let recipients_path = CString::new("/nonexistent/recipients.txt").unwrap();

    let result = age_encrypt_to_file(
        plaintext.as_ptr() as *const i8,
        plaintext.len(),
        encrypted_path_c.as_ptr(),
        recipients_path.as_ptr(),
    );

    assert_eq!(result, AgeResult::IoError);
}

#[test]
fn test_decrypt_file_corrupted_file() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Create corrupted encrypted file
    let encrypted_path = create_temp_file("corrupted.age");
    fs::write(&encrypted_path, "not valid age encrypted content").unwrap();
    let encrypted_path_c = CString::new(encrypted_path.as_str()).unwrap();

    let mut output = AgeBuffer::null();
    let result = age_decrypt_file_with_identity(
        encrypted_path_c.as_ptr(),
        keypair.private_key,
        &mut output,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    // Clean up
    fs::remove_file(&encrypted_path).ok();
    age_free_keypair(&mut keypair);
}