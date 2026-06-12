//! Recipient and identity validation functions.

use crate::helpers::cstr_to_str;
use std::os::raw::c_char;
use std::str::FromStr;

/// Check if a string is a valid x25519 recipient (public key).
///
/// # Arguments
/// * `recipient` - The recipient string to validate
///
/// # Returns
/// true if valid, false otherwise
#[no_mangle]
pub extern "C" fn age_is_valid_x25519_recipient(recipient: *const c_char) -> bool {
    let recipient_str = match unsafe { cstr_to_str(recipient) } {
        Ok(s) => s,
        Err(_) => return false,
    };

    recipient_str.parse::<age::x25519::Recipient>().is_ok()
}

/// Check if a string is a valid x25519 identity (private key).
///
/// # Arguments
/// * `identity` - The identity string to validate
///
/// # Returns
/// true if valid, false otherwise
#[no_mangle]
pub extern "C" fn age_is_valid_x25519_identity(identity: *const c_char) -> bool {
    let identity_str = match unsafe { cstr_to_str(identity) } {
        Ok(s) => s,
        Err(_) => return false,
    };

    age::x25519::Identity::from_str(identity_str).is_ok()
}

/// Check if a string is a valid SSH recipient (public key).
///
/// # Arguments
/// * `recipient` - The recipient string to validate
///
/// # Returns
/// true if valid, false otherwise
#[no_mangle]
pub extern "C" fn age_is_valid_ssh_recipient(recipient: *const c_char) -> bool {
    let recipient_str = match unsafe { cstr_to_str(recipient) } {
        Ok(s) => s,
        Err(_) => return false,
    };

    recipient_str.parse::<age::ssh::Recipient>().is_ok()
}

/// Get the type of a recipient string.
///
/// # Arguments
/// * `recipient` - The recipient string
///
/// # Returns
/// 0 = invalid, 1 = x25519, 2 = ssh (ed25519 or rsa)
#[no_mangle]
pub extern "C" fn age_recipient_type(recipient: *const c_char) -> u8 {
    let recipient_str = match unsafe { cstr_to_str(recipient) } {
        Ok(s) => s.trim(),
        Err(_) => return 0,
    };

    if recipient_str.parse::<age::x25519::Recipient>().is_ok() {
        return 1;
    }

    if recipient_str.parse::<age::ssh::Recipient>().is_ok() {
        return 2;
    }

    0
}
