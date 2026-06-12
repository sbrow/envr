//! File-based encryption and decryption operations.

use crate::helpers::{cstr_to_str, cstr_to_string};
use crate::types::{AgeBuffer, AgeResult};
use age::secrecy::SecretString;
use std::fs::File;
use std::io::{Read, Write};
use std::os::raw::c_char;
use std::str::FromStr;

/// Encrypt data to a file using a recipient.
///
/// # Arguments
/// * `plaintext` - The data to encrypt
/// * `plaintext_len` - Length of the plaintext
/// * `output_path` - Path to write the encrypted .age file
/// * `recipient` - The recipient public key (age1...) or path to recipients file
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_encrypt_to_file(
    plaintext: *const c_char,
    plaintext_len: usize,
    output_path: *const c_char,
    recipient: *const c_char,
) -> AgeResult {
    if plaintext.is_null() || output_path.is_null() || recipient.is_null() {
        return AgeResult::InvalidInput;
    }

    let plaintext = unsafe { std::slice::from_raw_parts(plaintext as *const u8, plaintext_len) };

    let output_path = match unsafe { cstr_to_str(output_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let recipient_str = match unsafe { cstr_to_str(recipient) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    // Parse recipients - could be a file path or a direct recipient key
    // Supports: x25519 (age1...), plugin (age1<plugin>1...), and ssh (ssh-...)
    let mut recipients: Vec<Box<dyn age::Recipient + Send>> = Vec::new();
    let mut plugin_recipients: Vec<age::plugin::Recipient> = Vec::new();

    let recipient_lines: Vec<&str> = if recipient_str.starts_with("age1") || recipient_str.starts_with("ssh-") {
        vec![recipient_str]
    } else {
        // Assume it's a file path containing recipients
        match std::fs::read_to_string(recipient_str) {
            Ok(contents) => {
                // We need to own the string for the lines
                let contents_leaked: &'static str = Box::leak(contents.into_boxed_str());
                contents_leaked
                    .lines()
                    .filter(|line| !line.starts_with('#') && !line.is_empty())
                    .map(|line| line.trim())
                    .collect()
            }
            Err(_) => return AgeResult::IoError,
        }
    };

    for line in recipient_lines {
        // Try x25519 first
        if let Ok(r) = line.parse::<age::x25519::Recipient>() {
            recipients.push(Box::new(r));
            continue;
        }
        // Then try plugin recipient - collect these separately
        if let Ok(r) = line.parse::<age::plugin::Recipient>() {
            plugin_recipients.push(r);
            continue;
        }
        // Finally try SSH
        if let Ok(r) = line.parse::<age::ssh::Recipient>() {
            recipients.push(Box::new(r));
            continue;
        }
        // Skip unrecognized lines
    }

    // Create plugin recipients wrapper if we have any plugin recipients
    // Group them by plugin name
    if !plugin_recipients.is_empty() {
        use std::collections::HashMap;
        let mut by_plugin: HashMap<String, Vec<age::plugin::Recipient>> = HashMap::new();
        for r in plugin_recipients {
            by_plugin.entry(r.plugin().to_string()).or_default().push(r);
        }

        for (plugin_name, plugin_recs) in by_plugin {
            match age::plugin::RecipientPluginV1::new(
                &plugin_name,
                &plugin_recs,
                &[],
                age::NoCallbacks,
            ) {
                Ok(plugin) => recipients.push(Box::new(plugin)),
                Err(_) => return AgeResult::InvalidRecipient,
            }
        }
    }

    if recipients.is_empty() {
        return AgeResult::InvalidRecipient;
    }

    let output_file = match File::create(output_path) {
        Ok(f) => f,
        Err(_) => return AgeResult::IoError,
    };

    let encryptor = match age::Encryptor::with_recipients(recipients.iter().map(|r| r.as_ref() as &dyn age::Recipient)) {
        Ok(e) => e,
        Err(_) => return AgeResult::EncryptionFailed,
    };

    let mut writer = match encryptor.wrap_output(output_file) {
        Ok(w) => w,
        Err(_) => return AgeResult::EncryptionFailed,
    };

    if writer.write_all(plaintext).is_err() {
        return AgeResult::EncryptionFailed;
    }

    if writer.finish().is_err() {
        return AgeResult::EncryptionFailed;
    }

    AgeResult::Success
}

/// Encrypt data to a file with ASCII armor.
#[no_mangle]
pub extern "C" fn age_encrypt_to_file_armor(
    plaintext: *const u8,
    plaintext_len: usize,
    output_path: *const c_char,
    recipient: *const c_char,
) -> AgeResult {
    if plaintext.is_null() || output_path.is_null() {
        return AgeResult::InvalidInput;
    }

    let plaintext = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };

    let output_path = match unsafe { cstr_to_str(output_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

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

    if std::fs::write(output_path, encrypted).is_err() {
        return AgeResult::IoError;
    }

    AgeResult::Success
}

/// Decrypt data from a file using an identity file.
///
/// This function supports all identity types including:
/// - Standard x25519 identities (AGE-SECRET-KEY-...)
/// - SSH identities
/// - Plugin identities (AGE-PLUGIN-...)
#[no_mangle]
pub extern "C" fn age_decrypt_file(
    encrypted_path: *const c_char,
    identity_path: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if output.is_null() {
        return AgeResult::InvalidInput;
    }

    let encrypted_path = match unsafe { cstr_to_str(encrypted_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let identity_path = match unsafe { cstr_to_str(identity_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    // Use IdentityFile to parse the identity file - this supports all identity types
    // including plugin identities (AGE-PLUGIN-...)
    let identity_file = match age::IdentityFile::from_file(identity_path.to_string()) {
        Ok(f) => f,
        Err(_) => return AgeResult::IoError,
    };

    // Get all identities from the file
    let identities = match identity_file.into_identities() {
        Ok(ids) => ids,
        Err(_) => return AgeResult::InvalidIdentity,
    };

    if identities.is_empty() {
        return AgeResult::InvalidIdentity;
    }

    let encrypted_file = match File::open(encrypted_path) {
        Ok(f) => f,
        Err(_) => return AgeResult::IoError,
    };

    let decryptor = match age::Decryptor::new(encrypted_file) {
        Ok(d) => d,
        Err(_) => return AgeResult::DecryptionFailed,
    };

    let mut decrypted = Vec::new();
    let mut reader = match decryptor.decrypt(identities.iter().map(|i| i.as_ref() as &dyn age::Identity)) {
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

/// Decrypt data from a file using a single identity string.
#[no_mangle]
pub extern "C" fn age_decrypt_file_with_identity(
    encrypted_path: *const c_char,
    identity: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if output.is_null() {
        return AgeResult::InvalidInput;
    }

    let encrypted_path = match unsafe { cstr_to_str(encrypted_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let identity_str = match unsafe { cstr_to_str(identity) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let identity = match age::x25519::Identity::from_str(identity_str) {
        Ok(i) => i,
        Err(_) => return AgeResult::InvalidIdentity,
    };

    let encrypted_file = match File::open(encrypted_path) {
        Ok(f) => f,
        Err(_) => return AgeResult::IoError,
    };

    let decryptor = match age::Decryptor::new(encrypted_file) {
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

/// Decrypt a file using a passphrase.
#[no_mangle]
pub extern "C" fn age_decrypt_file_passphrase(
    encrypted_path: *const c_char,
    passphrase: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if output.is_null() {
        return AgeResult::InvalidInput;
    }

    let encrypted_path = match unsafe { cstr_to_str(encrypted_path) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let passphrase_str = match unsafe { cstr_to_string(passphrase) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let secret = SecretString::from(passphrase_str);
    let identity = age::scrypt::Identity::new(secret);

    let encrypted_file = match File::open(encrypted_path) {
        Ok(f) => f,
        Err(_) => return AgeResult::IoError,
    };

    let decryptor = match age::Decryptor::new(encrypted_file) {
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
