//! FFI-compatible data types for the age encryption library.

use std::os::raw::c_char;

/// Result codes for FFI functions
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgeResult {
    Success = 0,
    InvalidInput = 1,
    EncryptionFailed = 2,
    DecryptionFailed = 3,
    KeygenFailed = 4,
    IoError = 5,
    InvalidRecipient = 6,
    InvalidIdentity = 7,
    NoRecipients = 8,
    NoIdentities = 9,
    ArmorError = 10,
    PassphraseRequired = 11,
    InvalidPassphrase = 12,
    SshKeyError = 13,
    MemoryAllocationFailed = 14,
    InvalidUtf8 = 15,
    UnsupportedKey = 16,
}

/// A buffer containing binary data allocated by the library.
/// Caller must free using age_free_buffer.
#[repr(C)]
pub struct AgeBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl AgeBuffer {
    pub fn null() -> Self {
        AgeBuffer {
            data: std::ptr::null_mut(),
            len: 0,
            capacity: 0,
        }
    }

    pub fn from_vec(v: Vec<u8>) -> Self {
        let mut v = v.into_boxed_slice();
        let data = v.as_mut_ptr();
        let len = v.len();
        std::mem::forget(v);
        AgeBuffer {
            data,
            len,
            capacity: len,
        }
    }
}

/// A keypair containing public and private keys as C strings.
/// Caller must free both strings using age_free_string.
#[repr(C)]
pub struct AgeKeypair {
    pub public_key: *mut c_char,
    pub private_key: *mut c_char,
}

impl AgeKeypair {
    pub fn null() -> Self {
        AgeKeypair {
            public_key: std::ptr::null_mut(),
            private_key: std::ptr::null_mut(),
        }
    }
}

/// Configuration for encryption operations.
#[repr(C)]
pub struct AgeEncryptConfig {
    /// If true, output will be ASCII-armored
    pub armor: bool,
    /// Work factor for scrypt (0 = default, typically 18-22)
    pub scrypt_work_factor: u8,
}

impl Default for AgeEncryptConfig {
    fn default() -> Self {
        AgeEncryptConfig {
            armor: false,
            scrypt_work_factor: 0,
        }
    }
}