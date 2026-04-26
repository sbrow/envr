//! In-memory decryption functions.

use crate::helpers::cstr_to_str;
use crate::types::{AgeBuffer, AgeResult};
use age::ssh;
use std::io::{BufReader, Read};
use std::os::raw::c_char;
use std::str::FromStr;

/// Decrypt data in memory using a single x25519 identity.
/// This is a simple API for common use cases.
///
/// # Arguments
/// * `ciphertext` - Pointer to the encrypted data
/// * `ciphertext_len` - Length of the ciphertext
/// * `identity` - The private key string (AGE-SECRET-KEY-1...)
/// * `output` - Pointer to receive the decrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_decrypt(
    ciphertext: *const u8,
    ciphertext_len: usize,
    identity: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if ciphertext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let ciphertext = unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) };

    let identity_str = match unsafe { cstr_to_str(identity) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let identity = match age::x25519::Identity::from_str(identity_str) {
        Ok(i) => i,
        Err(_) => return AgeResult::InvalidIdentity,
    };

    let decrypted = match age::decrypt(&identity, ciphertext) {
        Ok(d) => d,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    unsafe {
        *output = AgeBuffer::from_vec(decrypted);
    }

    AgeResult::Success
}

/// Decrypt data in memory using multiple identities.
/// The library will try each identity until one succeeds.
///
/// # Arguments
/// * `ciphertext` - Pointer to the encrypted data
/// * `ciphertext_len` - Length of the ciphertext
/// * `identities` - Array of identity C strings
/// * `identity_count` - Number of identities
/// * `output` - Pointer to receive the decrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_decrypt_multi(
    ciphertext: *const u8,
    ciphertext_len: usize,
    identities: *const *const c_char,
    identity_count: usize,
    output: *mut AgeBuffer,
) -> AgeResult {
    if ciphertext.is_null() || identities.is_null() || output.is_null() || identity_count == 0 {
        return AgeResult::InvalidInput;
    }

    let ciphertext = unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) };
    let identity_ptrs = unsafe { std::slice::from_raw_parts(identities, identity_count) };

    let mut parsed_identities: Vec<Box<dyn age::Identity>> = Vec::new();

    for &ptr in identity_ptrs {
        let identity_str = match unsafe { cstr_to_str(ptr) } {
            Ok(s) => s.trim(),
            Err(e) => return e,
        };

        // Try x25519 first
        if let Ok(i) = age::x25519::Identity::from_str(identity_str) {
            parsed_identities.push(Box::new(i));
            continue;
        }

        // Skip comments and empty lines
        if identity_str.is_empty() || identity_str.starts_with('#') {
            continue;
        }

        return AgeResult::InvalidIdentity;
    }

    if parsed_identities.is_empty() {
        return AgeResult::NoIdentities;
    }

    let decryptor = match age::Decryptor::new(ciphertext) {
        Ok(d) => d,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    let mut decrypted = Vec::new();
    let mut reader = match decryptor.decrypt(parsed_identities.iter().map(|i| i.as_ref())) {
        Ok(r) => r,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    if reader.read_to_end(&mut decrypted).is_err() {
        return AgeResult::DecryptionFailed;
    }

    unsafe {
        *output = AgeBuffer::from_vec(decrypted);
    }

    AgeResult::Success
}

/// Decrypt data using an SSH private key.
/// Supports both Ed25519 and RSA SSH keys.
///
/// # Arguments
/// * `ciphertext` - Pointer to the encrypted data
/// * `ciphertext_len` - Length of the ciphertext
/// * `ssh_key` - The SSH private key in PEM or OpenSSH format
/// * `passphrase` - Optional passphrase for encrypted SSH keys (can be null)
/// * `output` - Pointer to receive the decrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_decrypt_ssh(
    ciphertext: *const u8,
    ciphertext_len: usize,
    ssh_key: *const c_char,
    passphrase: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if ciphertext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let ciphertext = unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) };

    let ssh_key_str = match unsafe { cstr_to_str(ssh_key) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    // Parse SSH identity from buffer
    let buf_reader = BufReader::new(ssh_key_str.as_bytes());
    let identity = match ssh::Identity::from_buffer(buf_reader, None) {
        Ok(id) => id,
        Err(_) => return AgeResult::SshKeyError,
    };

    // Handle encrypted SSH keys - keep as ssh::Identity since it implements age::Identity
    let identity: ssh::Identity = match identity {
        ssh::Identity::Unencrypted(_) => identity,
        ssh::Identity::Encrypted(enc) => {
            let passphrase_str = if passphrase.is_null() {
                return AgeResult::PassphraseRequired;
            } else {
                match unsafe { cstr_to_str(passphrase) } {
                    Ok(s) if !s.is_empty() => s,
                    _ => return AgeResult::PassphraseRequired,
                }
            };

            match enc.decrypt(age::secrecy::SecretString::from(passphrase_str.to_string())) {
                Ok(id) => ssh::Identity::Unencrypted(id),
                Err(_) => return AgeResult::InvalidPassphrase,
            }
        }
        ssh::Identity::Unsupported(_) => return AgeResult::UnsupportedKey,
    };

    let decryptor = match age::Decryptor::new(ciphertext) {
        Ok(d) => d,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    let mut decrypted = Vec::new();
    let mut reader = match decryptor.decrypt(std::iter::once(&identity as &dyn age::Identity)) {
        Ok(r) => r,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    if reader.read_to_end(&mut decrypted).is_err() {
        return AgeResult::DecryptionFailed;
    }

    unsafe {
        *output = AgeBuffer::from_vec(decrypted);
    }

    AgeResult::Success
}

/// Decrypt data using an SSH private key file.
///
/// # Arguments
/// * `ciphertext` - Pointer to the encrypted data
/// * `ciphertext_len` - Length of the ciphertext
/// * `ssh_key_path` - Path to the SSH private key file
/// * `passphrase` - Optional passphrase for encrypted SSH keys (can be null)
/// * `output` - Pointer to receive the decrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_decrypt_ssh_file(
    ciphertext: *const u8,
    ciphertext_len: usize,
    ssh_key_path: *const c_char,
    passphrase: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if ciphertext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let ciphertext = unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) };

    let path_str = match unsafe { cstr_to_str(ssh_key_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    // The filename is passed as a hint for error messages
    let filename = Some(path_str.to_string());

    // Read and parse SSH key file
    let ssh_key_data = match std::fs::read(path_str) {
        Ok(data) => data,
        Err(_) => return AgeResult::IoError,
    };

    let buf_reader = BufReader::new(ssh_key_data.as_slice());
    let identity = match ssh::Identity::from_buffer(buf_reader, filename) {
        Ok(id) => id,
        Err(_) => return AgeResult::SshKeyError,
    };

    // Handle encrypted SSH keys - keep as ssh::Identity since it implements age::Identity
    let identity: ssh::Identity = match identity {
        ssh::Identity::Unencrypted(_) => identity,
        ssh::Identity::Encrypted(enc) => {
            // Parse passphrase if provided
            let passphrase_str = if passphrase.is_null() {
                return AgeResult::PassphraseRequired;
            } else {
                match unsafe { cstr_to_str(passphrase) } {
                    Ok(s) if !s.is_empty() => s,
                    _ => return AgeResult::PassphraseRequired,
                }
            };

            match enc.decrypt(age::secrecy::SecretString::from(passphrase_str.to_string())) {
                Ok(id) => ssh::Identity::Unencrypted(id),
                Err(_) => return AgeResult::InvalidPassphrase,
            }
        }
        ssh::Identity::Unsupported(_) => return AgeResult::UnsupportedKey,
    };

    let decryptor = match age::Decryptor::new(ciphertext) {
        Ok(d) => d,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    let mut decrypted = Vec::new();
    let mut reader = match decryptor.decrypt(std::iter::once(&identity as &dyn age::Identity)) {
        Ok(r) => r,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    if reader.read_to_end(&mut decrypted).is_err() {
        return AgeResult::DecryptionFailed;
    }

    unsafe {
        *output = AgeBuffer::from_vec(decrypted);
    }

    AgeResult::Success
}
