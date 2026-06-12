//! Internal helper functions for FFI conversions.

use crate::types::AgeResult;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Safely convert a C string pointer to a Rust &str
pub unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, AgeResult> {
    if ptr.is_null() {
        return Err(AgeResult::InvalidInput);
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|_| AgeResult::InvalidUtf8)
}

/// Safely convert a C string pointer to a Rust String
pub unsafe fn cstr_to_string(ptr: *const c_char) -> Result<String, AgeResult> {
    cstr_to_str(ptr).map(|s| s.to_owned())
}

/// Convert a Rust String to a C string pointer (caller must free)
pub fn string_to_cstr(s: String) -> Result<*mut c_char, AgeResult> {
    CString::new(s)
        .map(|cs| cs.into_raw())
        .map_err(|_| AgeResult::InvalidInput)
}