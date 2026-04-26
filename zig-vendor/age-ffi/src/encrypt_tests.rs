//! Tests for in-memory encryption functions.

use crate::encrypt::*;
use crate::decrypt::*;
use crate::keys::*;
use crate::memory::*;
use crate::types::*;
use std::ffi::CString;
use std::os::raw::c_char;

#[test]
fn test_basic_encrypt() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Hello, encryption!";
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::Success);
    assert!(!encrypted.data.is_null());
    assert!(encrypted.len > plaintext.len()); // Encrypted should be larger

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_null_plaintext() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        std::ptr::null(),
        0,
        keypair.public_key,
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_null_output() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);
    let plaintext = b"test";

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        std::ptr::null_mut(),
    );

    assert_eq!(result, AgeResult::InvalidInput);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_invalid_recipient() {
    let invalid_recipient = CString::new("not-a-valid-recipient").unwrap();
    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        invalid_recipient.as_ptr(),
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::InvalidRecipient);
}

#[test]
fn test_encrypt_multi_two_recipients() {
    let mut keypair1 = AgeKeypair::null();
    let mut keypair2 = AgeKeypair::null();
    age_generate_x25519(&mut keypair1);
    age_generate_x25519(&mut keypair2);

    let plaintext = b"Message for both recipients";
    let recipients: [*const c_char; 2] = [
        keypair1.public_key as *const c_char,
        keypair2.public_key as *const c_char,
    ];
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt_multi(
        plaintext.as_ptr(),
        plaintext.len(),
        recipients.as_ptr(),
        2,
        false,
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::Success);

    // Both recipients should be able to decrypt
    let mut decrypted1 = AgeBuffer::null();
    let result = age_decrypt(encrypted.data, encrypted.len, keypair1.private_key, &mut decrypted1);
    assert_eq!(result, AgeResult::Success);

    let mut decrypted2 = AgeBuffer::null();
    let result = age_decrypt(encrypted.data, encrypted.len, keypair2.private_key, &mut decrypted2);
    assert_eq!(result, AgeResult::Success);

    age_free_buffer(&mut encrypted);
    age_free_buffer(&mut decrypted1);
    age_free_buffer(&mut decrypted2);
    age_free_keypair(&mut keypair1);
    age_free_keypair(&mut keypair2);
}

#[test]
fn test_encrypt_multi_with_armor() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Armored multi-recipient message";
    let recipients: [*const c_char; 1] = [keypair.public_key as *const c_char];
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt_multi(
        plaintext.as_ptr(),
        plaintext.len(),
        recipients.as_ptr(),
        1,
        true, // armor
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::Success);

    // Check it's armored
    let encrypted_slice = unsafe { std::slice::from_raw_parts(encrypted.data, encrypted.len) };
    let encrypted_str = std::str::from_utf8(encrypted_slice).unwrap();
    assert!(encrypted_str.contains("-----BEGIN AGE ENCRYPTED FILE-----"));

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_multi_empty_recipients() {
    let plaintext = b"test";
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt_multi(
        plaintext.as_ptr(),
        plaintext.len(),
        std::ptr::null(),
        0,
        false,
        &mut encrypted,
    );

    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_encrypt_armor() {
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

    let armored_str = unsafe { std::ffi::CStr::from_ptr(armored).to_str().unwrap() };
    assert!(armored_str.starts_with("-----BEGIN AGE ENCRYPTED FILE-----"));
    assert!(armored_str.contains("-----END AGE ENCRYPTED FILE-----"));

    age_free_string(armored);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_encrypt_various_sizes() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let sizes = [0, 1, 16, 256, 1024, 4096, 65536];

    for size in sizes {
        let plaintext: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();
        let mut encrypted = AgeBuffer::null();

        let result = age_encrypt(
            plaintext.as_ptr(),
            plaintext.len(),
            keypair.public_key,
            &mut encrypted,
        );

        assert_eq!(result, AgeResult::Success, "Failed for size {}", size);

        // Verify we can decrypt it back
        let mut decrypted = AgeBuffer::null();
        let result = age_decrypt(encrypted.data, encrypted.len, keypair.private_key, &mut decrypted);
        assert_eq!(result, AgeResult::Success, "Decrypt failed for size {}", size);

        let decrypted_slice = unsafe { std::slice::from_raw_parts(decrypted.data, decrypted.len) };
        assert_eq!(decrypted_slice, plaintext.as_slice(), "Mismatch for size {}", size);

        age_free_buffer(&mut encrypted);
        age_free_buffer(&mut decrypted);
    }

    age_free_keypair(&mut keypair);
}