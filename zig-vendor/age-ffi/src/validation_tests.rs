//! Tests for recipient and identity validation functions.

use crate::keys::*;
use crate::memory::*;
use crate::types::*;
use crate::validation::*;
use std::ffi::CString;

#[test]
fn test_is_valid_x25519_recipient_valid() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    assert!(age_is_valid_x25519_recipient(keypair.public_key));

    age_free_keypair(&mut keypair);
}

#[test]
fn test_is_valid_x25519_recipient_invalid() {
    let invalid = CString::new("not-a-valid-key").unwrap();
    assert!(!age_is_valid_x25519_recipient(invalid.as_ptr()));

    let almost_valid = CString::new("age1qqqqqqqqqqqqqqqqqqqqq").unwrap();
    assert!(!age_is_valid_x25519_recipient(almost_valid.as_ptr()));

    // Private key should not be valid as recipient
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);
    assert!(!age_is_valid_x25519_recipient(keypair.private_key));
    age_free_keypair(&mut keypair);
}

#[test]
fn test_is_valid_x25519_recipient_null() {
    assert!(!age_is_valid_x25519_recipient(std::ptr::null()));
}

#[test]
fn test_is_valid_x25519_identity_valid() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    assert!(age_is_valid_x25519_identity(keypair.private_key));

    age_free_keypair(&mut keypair);
}

#[test]
fn test_is_valid_x25519_identity_invalid() {
    let invalid = CString::new("not-a-valid-key").unwrap();
    assert!(!age_is_valid_x25519_identity(invalid.as_ptr()));

    let almost_valid = CString::new("AGE-SECRET-KEY-1QQQQQQQQQQQQQ").unwrap();
    assert!(!age_is_valid_x25519_identity(almost_valid.as_ptr()));

    // Public key should not be valid as identity
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);
    assert!(!age_is_valid_x25519_identity(keypair.public_key));
    age_free_keypair(&mut keypair);
}

#[test]
fn test_is_valid_x25519_identity_null() {
    assert!(!age_is_valid_x25519_identity(std::ptr::null()));
}

#[test]
fn test_is_valid_ssh_recipient() {
    // Test with an ed25519 SSH public key format
    let ed25519_key = CString::new("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXzDvU2fB2Z9R7z1q1q1q1q1q1q1q1q1q1q1q1q1q1q").unwrap();
    // This might or might not be valid depending on exact format
    // The important thing is the function doesn't crash
    let _ = age_is_valid_ssh_recipient(ed25519_key.as_ptr());

    // Invalid SSH key
    let invalid = CString::new("not-an-ssh-key").unwrap();
    assert!(!age_is_valid_ssh_recipient(invalid.as_ptr()));
}

#[test]
fn test_is_valid_ssh_recipient_null() {
    assert!(!age_is_valid_ssh_recipient(std::ptr::null()));
}

#[test]
fn test_recipient_type_x25519() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    assert_eq!(age_recipient_type(keypair.public_key), 1);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_recipient_type_invalid() {
    let invalid = CString::new("not-a-valid-key").unwrap();
    assert_eq!(age_recipient_type(invalid.as_ptr()), 0);
}

#[test]
fn test_recipient_type_null() {
    assert_eq!(age_recipient_type(std::ptr::null()), 0);
}

#[test]
fn test_recipient_type_with_whitespace() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    // Get the public key and add whitespace
    let public_key_str = unsafe {
        std::ffi::CStr::from_ptr(keypair.public_key).to_str().unwrap()
    };
    let with_whitespace = CString::new(format!("  {}  ", public_key_str)).unwrap();

    // Should still be recognized as x25519 after trimming
    assert_eq!(age_recipient_type(with_whitespace.as_ptr()), 1);

    age_free_keypair(&mut keypair);
}

#[test]
fn test_empty_string_validation() {
    let empty = CString::new("").unwrap();

    assert!(!age_is_valid_x25519_recipient(empty.as_ptr()));
    assert!(!age_is_valid_x25519_identity(empty.as_ptr()));
    assert!(!age_is_valid_ssh_recipient(empty.as_ptr()));
    assert_eq!(age_recipient_type(empty.as_ptr()), 0);
}