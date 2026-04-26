//! Passphrase-based encryption and decryption (scrypt).

use crate::helpers::cstr_to_string;
use crate::types::{AgeBuffer, AgeResult};
use age::secrecy::SecretString;
use std::io::{Read, Write};
use std::os::raw::c_char;

/// Encrypt data using a passphrase.
///
/// # Arguments
/// * `plaintext` - Pointer to the plaintext data
/// * `plaintext_len` - Length of the plaintext
/// * `passphrase` - The passphrase string
/// * `armor` - If true, output will be ASCII-armored
/// * `output` - Pointer to receive the encrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_encrypt_passphrase(
    plaintext: *const u8,
    plaintext_len: usize,
    passphrase: *const c_char,
    armor: bool,
    output: *mut AgeBuffer,
) -> AgeResult {
    if plaintext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let plaintext = unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) };

    let passphrase_str = match unsafe { cstr_to_string(passphrase) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let secret = SecretString::from(passphrase_str);
    let encryptor = age::Encryptor::with_user_passphrase(secret);

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

/// Decrypt data using a passphrase.
///
/// # Arguments
/// * `ciphertext` - Pointer to the encrypted data
/// * `ciphertext_len` - Length of the ciphertext
/// * `passphrase` - The passphrase string
/// * `output` - Pointer to receive the decrypted buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_decrypt_passphrase(
    ciphertext: *const u8,
    ciphertext_len: usize,
    passphrase: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if ciphertext.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let ciphertext = unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) };

    let passphrase_str = match unsafe { cstr_to_string(passphrase) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let secret = SecretString::from(passphrase_str);
    let identity = age::scrypt::Identity::new(secret);

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
