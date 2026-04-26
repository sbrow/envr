//! Tests for passphrase-based encryption and decryption.

use crate::passphrase::*;
use crate::armor::*;
use crate::memory::*;
use crate::types::*;
use std::ffi::CString;

#[test]
fn test_passphrase_encrypt_decrypt() {
    let plaintext = b"Secret passphrase message";
    let passphrase = CString::new("my-secure-passphrase").unwrap();

    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        passphrase.as_ptr(),
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
}

#[test]
fn test_passphrase_wrong_passphrase() {
    let plaintext = b"Secret message";
    let correct_passphrase = CString::new("correct-passphrase").unwrap();
    let wrong_passphrase = CString::new("wrong-passphrase").unwrap();

    let mut encrypted = AgeBuffer::null();
    age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        correct_passphrase.as_ptr(),
        false,
        &mut encrypted,
    );

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        wrong_passphrase.as_ptr(),
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);

    age_free_buffer(&mut encrypted);
}

#[test]
fn test_passphrase_empty_passphrase() {
    let plaintext = b"Message with empty passphrase";
    let empty_passphrase = CString::new("").unwrap();

    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        empty_passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        empty_passphrase.as_ptr(),
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
}

#[test]
fn test_passphrase_special_characters() {
    let plaintext = b"Message with special passphrase";
    let special_passphrase = CString::new("p@$$w0rd!#$%^&*()_+-=[]{}|;':\",./<>?").unwrap();

    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        special_passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        special_passphrase.as_ptr(),
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
}

#[test]
fn test_passphrase_with_armor() {
    let plaintext = b"Armored passphrase message";
    let passphrase = CString::new("armor-test-pass").unwrap();

    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        true, // armor = true
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    // Verify it's armored
    let encrypted_slice = unsafe { std::slice::from_raw_parts(encrypted.data, encrypted.len) };
    let encrypted_str = std::str::from_utf8(encrypted_slice).unwrap();
    assert!(encrypted_str.contains("-----BEGIN AGE ENCRYPTED FILE-----"));

    // Dearmor first
    let armored_cstr = CString::new(encrypted_str).unwrap();
    let mut dearmored = AgeBuffer::null();
    age_dearmor(armored_cstr.as_ptr(), &mut dearmored);

    // Then decrypt
    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        dearmored.data,
        dearmored.len,
        passphrase.as_ptr(),
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut dearmored);
    age_free_buffer(&mut decrypted);
}

#[test]
fn test_passphrase_null_input() {
    let passphrase = CString::new("test").unwrap();
    let mut output = AgeBuffer::null();

    // Null plaintext
    let result = age_encrypt_passphrase(
        std::ptr::null(),
        0,
        passphrase.as_ptr(),
        false,
        &mut output,
    );
    assert_eq!(result, AgeResult::InvalidInput);

    // Null output
    let plaintext = b"test";
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        false,
        std::ptr::null_mut(),
    );
    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_passphrase_long_passphrase() {
    let plaintext = b"Message with very long passphrase";
    // 1000 character passphrase
    let long_passphrase = CString::new("a".repeat(1000)).unwrap();

    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        long_passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        long_passphrase.as_ptr(),
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
}

#[test]
fn test_passphrase_encrypt_null_passphrase() {
    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        std::ptr::null(),
        false,
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_passphrase_decrypt_null_passphrase() {
    let passphrase = CString::new("test").unwrap();
    let plaintext = b"test";

    // First encrypt with valid passphrase
    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    // Try to decrypt with null passphrase
    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        std::ptr::null(),
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_buffer(&mut encrypted);
}

#[test]
fn test_passphrase_decrypt_null_output() {
    let passphrase = CString::new("test").unwrap();
    let plaintext = b"test";

    let mut encrypted = AgeBuffer::null();
    let result = age_encrypt_passphrase(
        plaintext.as_ptr(),
        plaintext.len(),
        passphrase.as_ptr(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    // Try to decrypt with null output
    let result = age_decrypt_passphrase(
        encrypted.data,
        encrypted.len,
        passphrase.as_ptr(),
        std::ptr::null_mut(),
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_buffer(&mut encrypted);
}

#[test]
fn test_passphrase_decrypt_null_ciphertext() {
    let passphrase = CString::new("test").unwrap();
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_passphrase(
        std::ptr::null(),
        0,
        passphrase.as_ptr(),
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_passphrase_decrypt_corrupted_data() {
    let passphrase = CString::new("test").unwrap();
    let corrupted = b"not valid encrypted data";
    let mut decrypted = AgeBuffer::null();

    let result = age_decrypt_passphrase(
        corrupted.as_ptr(),
        corrupted.len(),
        passphrase.as_ptr(),
        &mut decrypted,
    );

    assert_eq!(result, AgeResult::DecryptionFailed);
}