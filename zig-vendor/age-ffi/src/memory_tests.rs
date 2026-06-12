//! Tests for memory management functions.

use crate::encrypt::*;
use crate::keys::*;
use crate::memory::*;
use crate::types::*;
use std::os::raw::c_char;

#[test]
fn test_free_buffer_basic() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Test message for buffer freeing";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );

    // Should not crash
    age_free_buffer(&mut encrypted);

    // Buffer should be nulled out
    assert!(encrypted.data.is_null());
    assert_eq!(encrypted.len, 0);
    assert_eq!(encrypted.capacity, 0);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_free_buffer_null() {
    // Should not crash on null pointer
    age_free_buffer(std::ptr::null_mut());
}

#[test]
fn test_free_buffer_already_null() {
    let mut buffer = AgeBuffer::null();
    // Should not crash on already-null buffer
    age_free_buffer(&mut buffer);
}

#[test]
fn test_free_string_basic() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Test";
    let mut armored: *mut c_char = std::ptr::null_mut();
    crate::encrypt::age_encrypt_armor(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut armored,
    );

    // Should not crash
    age_free_string(armored);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_free_string_null() {
    // Should not crash on null pointer
    age_free_string(std::ptr::null_mut());
}

#[test]
fn test_free_keypair_basic() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Should not crash
    age_free_keypair(&mut keypair);

    // Keypair should be nulled out
    assert!(keypair.public_key.is_null());
    assert!(keypair.private_key.is_null());
}

#[test]
fn test_free_keypair_null() {
    // Should not crash on null pointer
    age_free_keypair(std::ptr::null_mut());
}

#[test]
fn test_free_keypair_already_null() {
    let mut keypair = AgeKeypair::null();
    // Should not crash on already-null keypair
    age_free_keypair(&mut keypair);
}

#[test]
fn test_double_free_buffer() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Test";
    let mut encrypted = AgeBuffer::null();
    age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );

    age_free_buffer(&mut encrypted);
    // Double free should be safe because we null out the pointer
    age_free_buffer(&mut encrypted);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_double_free_keypair() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    age_free_keypair(&mut keypair);
    // Double free should be safe because we null out the pointers
    age_free_keypair(&mut keypair);
}

#[test]
fn test_multiple_allocations_and_frees() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Allocate and free multiple times
    for _ in 0..100 {
        let plaintext = b"Test message for repeated allocation";
        let mut encrypted = AgeBuffer::null();

        let result = age_encrypt(
            plaintext.as_ptr(),
            plaintext.len(),
            keypair.public_key,
            &mut encrypted,
        );
        assert_eq!(result, AgeResult::Success);

        age_free_buffer(&mut encrypted);
    }

    age_free_keypair(&mut keypair);
}

#[test]
fn test_large_allocation_and_free() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Allocate a large buffer (1MB)
    let plaintext: Vec<u8> = vec![0x42; 1024 * 1024];
    let mut encrypted = AgeBuffer::null();

    let result = age_encrypt(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut encrypted,
    );
    assert_eq!(result, AgeResult::Success);
    assert!(encrypted.len > 1024 * 1024);

    age_free_buffer(&mut encrypted);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_age_buffer_from_vec() {
    // Test the internal from_vec function
    let vec = vec![1u8, 2, 3, 4, 5];
    let buffer = AgeBuffer::from_vec(vec);

    assert!(!buffer.data.is_null());
    assert_eq!(buffer.len, 5);
    assert_eq!(buffer.capacity, 5);

    // Verify data
    let slice = unsafe { std::slice::from_raw_parts(buffer.data, buffer.len) };
    assert_eq!(slice, &[1, 2, 3, 4, 5]);

    // Clean up
    let mut buffer = buffer;
    age_free_buffer(&mut buffer);
}

#[test]
fn test_age_buffer_null() {
    let buffer = AgeBuffer::null();
    assert!(buffer.data.is_null());
    assert_eq!(buffer.len, 0);
    assert_eq!(buffer.capacity, 0);
}

#[test]
fn test_age_keypair_null() {
    let keypair = AgeKeypair::null();
    assert!(keypair.public_key.is_null());
    assert!(keypair.private_key.is_null());
}