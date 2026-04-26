//! Memory management functions.

use crate::types::{AgeBuffer, AgeKeypair};
use std::ffi::CString;
use std::os::raw::c_char;

/// Free a buffer allocated by this library.
///
/// # Safety
/// The buffer must have been allocated by one of the age_* functions.
#[no_mangle]
pub extern "C" fn age_free_buffer(buffer: *mut AgeBuffer) {
    if buffer.is_null() {
        return;
    }

    unsafe {
        let buf = &*buffer;
        if !buf.data.is_null() && buf.capacity > 0 {
            // Reconstruct the boxed slice and drop it
            let slice = std::slice::from_raw_parts_mut(buf.data, buf.capacity);
            drop(Box::from_raw(slice as *mut [u8]));
        }
        (*buffer) = AgeBuffer::null();
    }
}

/// Free a string allocated by this library.
///
/// # Safety
/// The pointer must have been allocated by one of the age_* functions.
#[no_mangle]
pub extern "C" fn age_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Free a keypair allocated by age_generate_keypair.
///
/// # Safety
/// The keypair must have been allocated by age_generate_keypair.
#[no_mangle]
pub extern "C" fn age_free_keypair(keypair: *mut AgeKeypair) {
    if keypair.is_null() {
        return;
    }

    unsafe {
        if !(*keypair).public_key.is_null() {
            drop(CString::from_raw((*keypair).public_key));
        }
        if !(*keypair).private_key.is_null() {
            drop(CString::from_raw((*keypair).private_key));
        }
        (*keypair) = AgeKeypair::null();
    }
}
