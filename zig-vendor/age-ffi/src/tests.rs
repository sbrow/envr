//! Tests for the age-ffi library.

use crate::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[test]
fn test_keygen() {
    let mut keypair = AgeKeypair::null();
    let result = age_generate_x25519(&mut keypair);
    assert_eq!(result, AgeResult::Success);
    assert!(!keypair.public_key.is_null());
    assert!(!keypair.private_key.is_null());

    unsafe {
        let public = CStr::from_ptr(keypair.public_key).to_str().unwrap();
        let private = CStr::from_ptr(keypair.private_key).to_str().unwrap();
        assert!(public.starts_with("age1"));
        assert!(private.starts_with("AGE-SECRET-KEY-1"));
    }

    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_decrypt() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Hello, world!";
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);
    assert!(!encrypted.data.is_null());
    assert!(encrypted.len > 0);

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
fn test_passphrase_encrypt_decrypt() {
    let plaintext = b"Secret message";
    let passphrase = CString::new("my-secret-passphrase").unwrap();

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
fn test_validation() {
    let invalid = CString::new("not-a-key").unwrap();
    assert!(!age_is_valid_x25519_recipient(invalid.as_ptr()));

    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);
    assert!(age_is_valid_x25519_recipient(keypair.public_key));
    assert!(age_is_valid_x25519_identity(keypair.private_key));
    assert_eq!(age_recipient_type(keypair.public_key), 1);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_armor_encrypt_decrypt() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Armored message";
    let mut armored: *mut c_char = std::ptr::null_mut();

    let result = age_encrypt_armor(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut armored,
    );
    assert_eq!(result, AgeResult::Success);
    assert!(!armored.is_null());

    let armored_str = unsafe { CStr::from_ptr(armored).to_str().unwrap() };
    assert!(armored_str.contains("-----BEGIN AGE ENCRYPTED FILE-----"));

    let mut dearmored = AgeBuffer::null();
    let result = age_dearmor(armored, &mut dearmored);
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        dearmored.data,
        dearmored.len,
        keypair.private_key,
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext);

    age_free_string(armored);
    age_free_buffer(&mut dearmored);
    age_free_buffer(&mut decrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_derive_public_key() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let mut derived_public: *mut c_char = std::ptr::null_mut();
    let result = age_x25519_to_public(keypair.private_key, &mut derived_public);
    assert_eq!(result, AgeResult::Success);

    let original = unsafe { CStr::from_ptr(keypair.public_key).to_str().unwrap() };
    let derived = unsafe { CStr::from_ptr(derived_public).to_str().unwrap() };
    assert_eq!(original, derived);

    age_free_string(derived_public);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_multi_recipient_encrypt() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    let plaintext = b"Message for multiple recipients";
    let recipients: [*const c_char; 2] = [
        keypair1.public_key as *const c_char,
        keypair2.public_key as *const c_char,
    ];
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt_multi(
        plaintext.as_ptr(),
        plaintext.len(),
        recipients.as_ptr(),
        recipients.len(),
        false,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    // Decrypt with first key
    let mut decrypted1 = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair1.private_key,
        &mut decrypted1,
    );
    assert_eq!(result, AgeResult::Success);
    let slice1 = unsafe { std::slice::from_raw_parts(decrypted1.data, decrypted1.len) };
    assert_eq!(slice1, plaintext);

    // Decrypt with second key
    let mut decrypted2 = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair2.private_key,
        &mut decrypted2,
    );
    assert_eq!(result, AgeResult::Success);
    let slice2 = unsafe { std::slice::from_raw_parts(decrypted2.data, decrypted2.len) };
    assert_eq!(slice2, plaintext);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted1);
    age_free_buffer(&mut decrypted2);
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}

#[test]
fn test_version_functions() {
    let version = age_version();
    assert!(!version.is_null());
    let version_str = unsafe { CStr::from_ptr(version).to_str().unwrap() };
    assert!(!version_str.is_empty());

    let lib_version = age_lib_version();
    assert!(!lib_version.is_null());
    let lib_version_str = unsafe { CStr::from_ptr(lib_version).to_str().unwrap() };
    assert!(lib_version_str.starts_with("0.11"));
}

#[test]
fn test_passphrase_with_armor() {
    let plaintext = b"Armored passphrase message";
    let passphrase = CString::new("test-passphrase-123").unwrap();

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

    // Dearmor first, then decrypt
    let armored_cstr = CString::new(encrypted_str).unwrap();
    let mut dearmored = AgeBuffer::null();
    let result = age_dearmor(armored_cstr.as_ptr(), &mut dearmored);
    assert_eq!(result, AgeResult::Success);

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
fn test_empty_plaintext() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"";
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair.private_key,
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);
    assert_eq!(decrypted.len, 0);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_large_plaintext() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // 1MB of data
    let plaintext: Vec<u8> = (0..1024 * 1024).map(|i| (i % 256) as u8).collect();
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let mut decrypted = AgeBuffer::null();
    let result = age_decrypt(
        encrypted.data,
        encrypted.len,
        keypair.private_key,
        &mut decrypted,
    );
    assert_eq!(result, AgeResult::Success);

    let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
    assert_eq!(decrypted_slice, plaintext.as_slice());

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted);
    age_free_keypair(&mut keypair);
}