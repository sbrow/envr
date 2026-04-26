//! Complete FFI wrapper for the age encryption library.
//!
//! Provides C-compatible functions for all age encryption operations:
//! - Key generation (x25519, SSH)
//! - Encryption/decryption (memory and file-based)
//! - Passphrase-based encryption (scrypt)
//! - ASCII armor support
//! - Multiple recipients support

extern crate libc;

// Internal modules
mod helpers;

// Public modules
pub mod types;
pub mod keys;
pub mod encrypt;
pub mod decrypt;
pub mod passphrase;
pub mod file;
pub mod armor;
pub mod validation;
pub mod memory;

// Re-export all public types
pub use types::{AgeBuffer, AgeEncryptConfig, AgeKeypair, AgeResult};

// Re-export all public functions
pub use keys::{age_generate_keypair, age_generate_x25519, age_x25519_to_public};
pub use encrypt::{age_encrypt, age_encrypt_armor, age_encrypt_multi};
pub use decrypt::{age_decrypt, age_decrypt_multi, age_decrypt_ssh, age_decrypt_ssh_file};
pub use passphrase::{age_decrypt_passphrase, age_encrypt_passphrase};
pub use file::{
    age_decrypt_file, age_decrypt_file_passphrase, age_decrypt_file_with_identity,
    age_encrypt_to_file, age_encrypt_to_file_armor,
};
pub use armor::{age_armor, age_dearmor};
pub use validation::{
    age_is_valid_ssh_recipient, age_is_valid_x25519_identity, age_is_valid_x25519_recipient,
    age_recipient_type,
};
pub use memory::{age_free_buffer, age_free_keypair, age_free_string};

use std::os::raw::c_char;

/// Get the version of the age-ffi library.
/// Returns a static string, do not free.
#[no_mangle]
pub extern "C" fn age_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

/// Get the version of the underlying age library.
/// Returns a static string, do not free.
#[no_mangle]
pub extern "C" fn age_lib_version() -> *const c_char {
    static VERSION: &[u8] = b"0.11.0\0";
    VERSION.as_ptr() as *const c_char
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod keys_tests;

#[cfg(test)]
mod encrypt_tests;

#[cfg(test)]
mod decrypt_tests;

#[cfg(test)]
mod passphrase_tests;

#[cfg(test)]
mod armor_tests;

#[cfg(test)]
mod validation_tests;

#[cfg(test)]
mod memory_tests;

#[cfg(test)]
mod file_tests;