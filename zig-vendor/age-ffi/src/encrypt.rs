//! In-memory encryption functions.

use crate::helpers::{cstr_to_str, string_to_cstr};
use crate::types::{AgeBuffer, AgeResult};
use std::io::Write;
use std::os::raw::c_char;

/// Encrypt data in memory using a single x25519 recipient.
/// This is a simple API for common use cases.
///
/// # Arguments
/// * `plaintext` - Pointer to the plaintext data
/// * `plaintext_len` - Length of the plaintext
/// * `recipient` - The recipient public key (age1...)
/// * `output` - Pointer to receive the encrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_encrypt(
    plaintext: *const u8,
    plaintext_len: usize,
    recipient: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if plaintext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let plaintext = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };

    let recipient_str = match unsafe { cstr_to_str(recipient) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let recipient = match recipient_str.parse::<age::x25519::Recipient>() {
        Ok(r) => r,
        Err(_) => return AgeResult::InvalidRecipient,
    };

    let encrypted = match age::encrypt(&recipient, plaintext) {
        Ok(e) => e,
        Err(_) => return AgeResult::EncryptionFailed,
    };

    unsafe {
        *output = AgeBuffer::from_vec(encrypted);
    }

    AgeResult::Success
}

/// Encrypt data in memory using multiple recipients.
///
/// # Arguments
/// * `plaintext` - Pointer to the plaintext data
/// * `plaintext_len` - Length of the plaintext
/// * `recipients` - Array of recipient public key C strings
/// * `recipient_count` - Number of recipients
/// * `armor` - If true, output will be ASCII-armored
/// * `output` - Pointer to receive the encrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_encrypt_multi(
    plaintext: *const u8,
    plaintext_len: usize,
    recipients: *const *const c_char,
    recipient_count: usize,
    armor: bool,
    output: *mut AgeBuffer,
) -> AgeResult {
    if plaintext.is_null() || recipients.is_null() || output.is_null() || recipient_count == 0 {
        return AgeResult::InvalidInput;
    }

    let plaintext = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };
    let recipient_ptrs = unsafe { std::slice::from_raw_parts(recipients, recipient_count) };

    let mut parsed_recipients: Vec<Box<dyn age::Recipient + Send>> = Vec::new();

    for &ptr in recipient_ptrs {
        let recipient_str = match unsafe { cstr_to_str(ptr) } {
            Ok(s) => s.trim(),
            Err(e) => return e,
        };

        // Try x25519 first
        if let Ok(r) = recipient_str.parse::<age::x25519::Recipient>() {
            parsed_recipients.push(Box::new(r));
            continue;
        }

        // Try SSH
        if let Ok(r) = recipient_str.parse::<age::ssh::Recipient>() {
            parsed_recipients.push(Box::new(r));
            continue;
        }

        return AgeResult::InvalidRecipient;
    }

    if parsed_recipients.is_empty() {
        return AgeResult::NoRecipients;
    }

    let encryptor = match age::Encryptor::with_recipients(
        parsed_recipients.iter().map(|r| r.as_ref() as &dyn age::Recipient)
    ) {
        Ok(e) => e,
        Err(_) => return AgeResult::EncryptionFailed,
    };

    let mut encrypted = Vec::new();

    let result = if armor {
        let armor_writer = age::armor::ArmoredWriter::wrap_output(&mut encrypted, age::armor::Format::AsciiArmor)
            .map_err(|_| AgeResult::ArmorError);

        match armor_writer {
            Ok(armor) => {
                match encryptor.wrap_output(armor) {
                    Ok(mut writer) => {
                        if writer.write_all(plaintext).is_err() {
                            return AgeResult::EncryptionFailed;
                        }
                        match writer.finish() {
                            Ok(armor) => armor.finish().map_err(|_| AgeResult::ArmorError),
                            Err(_) => return AgeResult::EncryptionFailed,
                        }
                    }
                    Err(_) => return AgeResult::EncryptionFailed,
                }
            }
            Err(e) => return e,
        }
    } else {
        match encryptor.wrap_output(&mut encrypted) {
            Ok(mut writer) => {
                if writer.write_all(plaintext).is_err() {
                    return AgeResult::EncryptionFailed;
                }
                writer.finish().map_err(|_| AgeResult::EncryptionFailed)
            }
            Err(_) => return AgeResult::EncryptionFailed,
        }
    };

    if result.is_err() {
        return AgeResult::EncryptionFailed;
    }

    unsafe {
        *output = AgeBuffer::from_vec(encrypted);
    }

    AgeResult::Success
}

/// Encrypt data with ASCII armor for text-safe output.
///
/// # Arguments
/// * `plaintext` - Pointer to the plaintext data
/// * `plaintext_len` - Length of the plaintext
/// * `recipient` - The recipient public key (age1...)
/// * `output` - Pointer to receive the armored string (null-terminated)
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_encrypt_armor(
    plaintext: *const u8,
    plaintext_len: usize,
    recipient: *const c_char,
    output: *mut *mut c_char,
) -> AgeResult {
    if plaintext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let plaintext = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };

    let recipient_str = match unsafe { cstr_to_str(recipient) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let recipient = match recipient_str.parse::<age::x25519::Recipient>() {
        Ok(r) => r,
        Err(_) => return AgeResult::InvalidRecipient,
    };

    let encrypted = match age::encrypt_and_armor(&recipient, plaintext) {
        Ok(e) => e,
        Err(_) => return AgeResult::EncryptionFailed,
    };

    let c_output = match string_to_cstr(encrypted) {
        Ok(s) => s,
        Err(e) => return e,
    };

    unsafe {
        *output = c_output;
    }

    AgeResult::Success
}
