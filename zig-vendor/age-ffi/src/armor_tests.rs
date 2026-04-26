//! Tests for ASCII armor utilities.

use crate::armor::*;
use crate::encrypt::*;
use crate::keys::*;
use crate::memory::*;
use crate::types::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[test]
fn test_armor_basic() {
    let data = b"Hello, this is binary data to armor!";
    let mut armored: *mut c_char = std::ptr::null_mut();

    let result = age_armor(data.as_ptr(), data.len(), &mut armored);
    assert_eq!(result, AgeResult::Success);
    assert!(!armored.is_null());

    let armored_str = unsafe { CStr::from_ptr(armored).to_str().unwrap() };
    assert!(armored_str.starts_with("-----BEGIN AGE ENCRYPTED FILE-----"));
    assert!(armored_str.contains("-----END AGE ENCRYPTED FILE-----"));

    age_free_string(armored);
}

#[test]
fn test_dearmor_basic() {
    let data = b"Test data for dearmoring";
    let mut armored: *mut c_char = std::ptr::null_mut();
    age_armor(data.as_ptr(), data.len(), &mut armored);

    let mut dearmored = AgeBuffer::null();
    let result = age_dearmor(armored, &mut dearmored);
    assert_eq!(result, AgeResult::Success);

    let dearmored_slice = unsafe { std::slice::from_raw_parts(dearmored.data, dearmored.len) };
    assert_eq!(dearmored_slice, data);

    age_free_string(armored);
    age_free_buffer(&mut dearmored);
}

#[test]
fn test_armor_round_trip() {
    // Test with various data sizes (skip empty - armor requires data)
    let test_data = [
        b"A".to_vec(),
        b"Short".to_vec(),
        (0u16..256).map(|i| i as u8).collect::<Vec<u8>>(),
        vec![0u8; 1000],
        (0..10000).map(|i| (i % 256) as u8).collect::<Vec<u8>>(),
    ];

    for data in &test_data {
        let mut armored: *mut c_char = std::ptr::null_mut();
        let result = age_armor(data.as_ptr(), data.len(), &mut armored);
        assert_eq!(result, AgeResult::Success, "Failed to armor data of len {}", data.len());

        let mut dearmored = AgeBuffer::null();
        let result = age_dearmor(armored, &mut dearmored);
        assert_eq!(result, AgeResult::Success, "Failed to dearmor data of len {}", data.len());

        let dearmored_slice = unsafe { std::slice::from_raw_parts(dearmored.data, dearmored.len) };
        assert_eq!(dearmored_slice, data.as_slice());

        age_free_string(armored);
        age_free_buffer(&mut dearmored);
    }
}

#[test]
fn test_armor_null_input() {
    let mut armored: *mut c_char = std::ptr::null_mut();

    let result = age_armor(std::ptr::null(), 0, &mut armored);
    assert_eq!(result, AgeResult::InvalidInput);

    let result = age_armor(b"test".as_ptr(), 4, std::ptr::null_mut());
    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_dearmor_null_input() {
    let mut dearmored = AgeBuffer::null();

    let result = age_dearmor(std::ptr::null(), &mut dearmored);
    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_dearmor_null_output() {
    let data = b"test";
    let mut armored: *mut c_char = std::ptr::null_mut();
    age_armor(data.as_ptr(), data.len(), &mut armored);

    let result = age_dearmor(armored, std::ptr::null_mut());
    assert_eq!(result, AgeResult::InvalidInput);

    age_free_string(armored);
}

#[test]
fn test_dearmor_invalid_armor() {
    let invalid_armor = CString::new("This is not valid armor").unwrap();
    let mut dearmored = AgeBuffer::null();

    let result = age_dearmor(invalid_armor.as_ptr(), &mut dearmored);
    // Should still succeed but return the data as-is or fail gracefully
    // The ArmoredReader is forgiving and may just return the raw data
    // Let's check that it doesn't crash at least
    if result == AgeResult::Success {
        age_free_buffer(&mut dearmored);
    }
}

#[test]
fn test_encrypt_armor_and_dearmor() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let plaintext = b"Test encrypt -> armor -> dearmor -> decrypt";
    let mut armored: *mut c_char = std::ptr::null_mut();

    let result = age_encrypt_armor(
        plaintext.as_ptr(),
        plaintext.len(),
        keypair.public_key,
        &mut armored,
    );
    assert_eq!(result, AgeResult::Success);

    // Dearmor
    let mut dearmored = AgeBuffer::null();
    let result = age_dearmor(armored, &mut dearmored);
    assert_eq!(result, AgeResult::Success);

    // Decrypt
    let mut decrypted = AgeBuffer::null();
    let result = crate::decrypt::age_decrypt(
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
fn test_armor_binary_data() {
    // Test with binary data including null bytes
    let binary_data: Vec<u8> = (0u16..256).map(|i| i as u8).collect();
    let mut armored: *mut c_char = std::ptr::null_mut();

    let result = age_armor(binary_data.as_ptr(), binary_data.len(), &mut armored);
    assert_eq!(result, AgeResult::Success);

    let mut dearmored = AgeBuffer::null();
    let result = age_dearmor(armored, &mut dearmored);
    assert_eq!(result, AgeResult::Success);

    let dearmored_slice = unsafe { std::slice::from_raw_parts(dearmored.data, dearmored.len) };
    assert_eq!(dearmored_slice, binary_data.as_slice());

    age_free_string(armored);
    age_free_buffer(&mut dearmored);
}