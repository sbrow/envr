//! Tests for in-memory decryption functions.

use crate::decrypt::*;
use crate::encrypt::*;
use crate::keys::*;
use crate::memory::*;
use crate::types::*;
use std::ffi::CString;
use std::os::raw::c_char;

#[test]
fn test_basic_decrypt() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Decryption test message";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair.private_key,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::Success);
    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_null_ciphertext() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt(
        std::ptr::null(),
        0,
        keypair.private_key,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_null_output() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair.private_key,
        std::ptr::null_mut(),
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_invalid_identity() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    let invalid_identity = CString::new("not-a-valid-identity").unwrap();
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        invalid_identity.as_ptr(),
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidIdentity);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_wrong_key() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    let plaintext = b"Secret message";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair1.public_key, &mut encrypted);

    // Try to decrypt with wrong key
    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair2.private_key, // Wrong key!
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}

#[test]
fn test_decrypt_corrupted_ciphertext() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Original message";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    // Corrupt the ciphertext
    if encrypted.len > 50 {
        unsafe {
            *encrypted.data.add(50) ^= 0xFF;
        }
    }

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair.private_key,
        &mut decrypted,
    );

    // Should fail (either DecryptionFailed or other error depending on what was corrupted)
    assert_ne!(result, AgeResult::Success);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_with_multiple_identities() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    let plaintext = b"Multi-identity message";
    let recipients: [*const c_char; 1] = [keypair1.public_key as *const c_char];
    let mut encrypted = AgeBuffer::null();
    age_encrypt_multi(
        plaintext.as_ptr(),
        plaintext.len(),
        recipients.as_ptr(),
        1,
        false,
        &mut encrypted,
    );

    // Decrypt with multiple identities (one valid, one invalid for this message)
    let identities: [*const c_char; 2] = [
        keypair2.private_key as *const c_char, // Wrong key first
        keypair1.private_key as *const c_char, // Correct key
    ];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        identities.as_ptr(),
        2,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::Success);
    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}

#[test]
fn test_decrypt_multi_empty_identities() {
    let plaintext = b"test";
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        std::ptr::null(),
        0,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_null_identity() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        std::ptr::null(),
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_null_identity_in_array() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    // Array with a null pointer inside
    let identities: [*const c_char; 2] = [
        keypair.private_key as *const c_char,
        std::ptr::null(),
    ];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        identities.as_ptr(),
        2,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_with_comments_and_empty() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test with comments";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    // Mix of comments, empty strings, and valid identity
    let comment = CString::new("# This is a comment").unwrap();
    let empty = CString::new("").unwrap();
    let identities: [*const c_char; 3] = [
        comment.as_ptr(),
        empty.as_ptr(),
        keypair.private_key as *const c_char,
    ];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        identities.as_ptr(),
        3,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::Success);

    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_only_comments() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    // Only comments and empty - no valid identities
    let comment1 = CString::new("# Comment 1").unwrap();
    let comment2 = CString::new("# Comment 2").unwrap();
    let empty = CString::new("").unwrap();
    let identities: [*const c_char; 3] = [
        comment1.as_ptr(),
        comment2.as_ptr(),
        empty.as_ptr(),
    ];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        identities.as_ptr(),
        3,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::NoIdentities);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_invalid_identity_format() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair.public_key, &mut encrypted);

    // Invalid identity (not a comment, not empty, not valid key)
    let invalid = CString::new("invalid-key-format").unwrap();
    let identities: [*const c_char; 1] = [invalid.as_ptr()];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        identities.as_ptr(),
        1,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidIdentity);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_corrupted_ciphertext() {
    let corrupted = b"not valid age encrypted data at all";
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let identities: [*const c_char; 1] = [keypair.private_key as *const c_char];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        corrupted.as_ptr(),
        corrupted.len(),
        identities.as_ptr(),
        1,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_decrypt_multi_wrong_key_only() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(plaintext.as_ptr(), plaintext.len(), keypair1.public_key, &mut encrypted);

    // Only provide wrong key
    let identities: [*const c_char; 1] = [keypair2.private_key as *const c_char];
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_multi(
        encrypted.data,
        encrypted.len,
        identities.as_ptr(),
        1,
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}