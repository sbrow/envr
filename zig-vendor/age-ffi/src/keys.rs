//! Key generation and derivation functions.

use crate::helpers::{cstr_to_str, string_to_cstr};
use crate::types::{AgeKeypair, AgeResult};
use age::secrecy::ExposeSecret;
use std::ffi::CString;
use std::os::raw::c_char;
use std::str::FromStr;

/// Generate a new age x25519 keypair.
///
/// # Arguments
/// * `keypair` - Pointer to receive the generated keypair
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_generate_x25519(keypair: *mut AgeKeypair) -> AgeResult {
    if keypair.is_null() {
        return AgeResult::InvalidInput;
    }

    let identity = age::x25519::Identity::generate();
    let public_key = identity.to_public().to_string();
    let private_key = identity.to_string().expose_secret().to_string();

    let c_public = match string_to_cstr(public_key) {
        Ok(s) => s,
        Err(e) => return e,
    };

    let c_private = match string_to_cstr(private_key) {
        Ok(s) => s,
        Err(e) => {
            unsafe { drop(CString::from_raw(c_public)); }
            return e;
        }
    };

    unsafe {
        (*keypair).public_key = c_public;
        (*keypair).private_key = c_private;
    }

    AgeResult::Success
}

/// Alias for age_generate_x25519 for backwards compatibility.
#[no_mangle]
pub extern "C" fn age_generate_keypair(keypair: *mut AgeKeypair) -> AgeResult {
    age_generate_x25519(keypair)
}

/// Derive the public key from a private x25519 identity.
///
/// # Arguments
/// * `private_key` - The private key string (AGE-SECRET-KEY-1...)
/// * `public_key` - Pointer to receive the public key string
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_x25519_to_public(
    private_key: *const c_char,
    public_key: *mut *mut c_char,
) -> AgeResult {
    if public_key.is_null() {
        return AgeResult::InvalidInput;
    }

    let private_str = match unsafe { cstr_to_str(private_key) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let identity = match age::x25519::Identity::from_str(private_str) {
        Ok(i) => i,
        Err(_) => return AgeResult::InvalidIdentity,
    };

    let public_str = identity.to_public().to_string();
    let c_public = match string_to_cstr(public_str) {
        Ok(s) => s,
        Err(e) => return e,
    };

    unsafe {
        *public_key = c_public;
    }

    AgeResult::Success
}
