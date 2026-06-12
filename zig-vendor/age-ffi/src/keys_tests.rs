//! Tests for key generation and derivation functions.

use crate::keys::*;
use crate::memory::*;
use crate::types::*;
use std::ffi::CStr;

#[test]
fn test_generate_x25519_keypair() {
    let mut keypair = AgeKeypair::null();
    let result = age_generate_x25519(&mut keypair);

    assert_eq!(result, AgeResult::Success);
    assert!(!keypair.public_key.is_null());
    assert!(!keypair.private_key.is_null());

    unsafe {
        let public = CStr::from_ptr(keypair.public_key).to_str().unwrap();
        let private = CStr::from_ptr(keypair.private_key).to_str().unwrap();

        assert!(public.starts_with("age1"), "Public key should start with 'age1'");
        assert!(private.starts_with("AGE-SECRET-KEY-1"), "Private key should start with 'AGE-SECRET-KEY-1'");

        // Check key lengths are reasonable
        assert!(public.len() > 50, "Public key should be at least 50 chars");
        assert!(private.len() > 50, "Private key should be at least 50 chars");
    }

    age_free_keypair(&mut keypair);
}

#[test]
fn test_generate_keypair_alias() {
    let mut keypair = AgeKeypair::null();
    let result = age_generate_keypair(&mut keypair);

    assert_eq!(result, AgeResult::Success);
    assert!(!keypair.public_key.is_null());
    assert!(!keypair.private_key.is_null());

    age_free_keypair(&mut keypair);
}

#[test]
fn test_generate_x25519_null_pointer() {
    let result = age_generate_x25519(std::ptr::null_mut());
    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_derive_public_key() {
    let mut keypair = AgeKeypair::null();
    age_generate_x25519(&mut keypair);

    let mut derived_public: *mut std::os::raw::c_char = std::ptr::null_mut();
    let result = age_x25519_to_public(keypair.private_key, &mut derived_public);

    assert_eq!(result, AgeResult::Success);
    assert!(!derived_public.is_null());

    // The derived public key should match the original
    let original = unsafe { CStr::from_ptr(keypair.public_key).to_str().unwrap() };
    let derived = unsafe { CStr::from_ptr(derived_public).to_str().unwrap() };
    assert_eq!(original, derived);

    age_free_string(derived_public);
    age_free_keypair(&mut keypair);
}

#[test]
fn test_derive_public_key_invalid_input() {
    use std::ffi::CString;

    let mut derived_public: *mut std::os::raw::c_char = std::ptr::null_mut();

    // Null output pointer
    let result = age_x25519_to_public(std::ptr::null(), std::ptr::null_mut());
    assert_eq!(result, AgeResult::InvalidInput);

    // Invalid private key
    let invalid_key = CString::new("not-a-valid-key").unwrap();
    let result = age_x25519_to_public(invalid_key.as_ptr(), &mut derived_public);
    assert_eq!(result, AgeResult::InvalidIdentity);
}

#[test]
fn test_derive_public_key_null_private_key() {
    let mut derived_public: *mut std::os::raw::c_char = std::ptr::null_mut();

    // Null private key but valid output pointer
    let result = age_x25519_to_public(std::ptr::null(), &mut derived_public);
    assert_eq!(result, AgeResult::InvalidInput);
}

#[test]
fn test_multiple_keypair_generation() {
    // Generate multiple keypairs and ensure they're all unique
    let mut keypairs: Vec<AgeKeypair> = Vec::new();

    for _ in 0..10 {
        let mut keypair = AgeKeypair::null();
        let result = age_generate_x25519(&mut keypair);
        assert_eq!(result, AgeResult::Success);
        keypairs.push(keypair);
    }

    // Check all public keys are unique
    let public_keys: Vec<String> = keypairs.iter().map(|kp| {
        unsafe { CStr::from_ptr(kp.public_key).to_str().unwrap().to_string() }
    }).collect();

    for i in 0..public_keys.len() {
        for j in (i+1)..public_keys.len() {
            assert_ne!(public_keys[i], public_keys[j], "Keypairs should be unique");
        }
    }

    // Cleanup
    for keypair in &mut keypairs {
        age_free_keypair(keypair);
    }
}