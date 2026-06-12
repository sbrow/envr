//! ASCII armor utilities.

use crate::helpers::cstr_to_str;
use crate::helpers::string_to_cstr;
use crate::types::{AgeBuffer, AgeResult};
use std::io::{Read, Write};
use std::os::raw::c_char;

/// Wrap binary data in ASCII armor.
///
/// # Arguments
/// * `data` - Pointer to the binary data
/// * `data_len` - Length of the data
/// * `output` - Pointer to receive the armored string
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_armor(
    data: *const u8,
    data_len: usize,
    output: *mut *mut c_char,
) -> AgeResult {
    if data.is_null() || output.is_null() {
        return AgeResult::InvalidInput;
    }

    let data = unsafe { std::slice::from_raw_parts(data, data_len) };

    let mut armored = Vec::new();
    let mut writer = match age::armor::ArmoredWriter::wrap_output(&mut armored, age::armor::Format::AsciiArmor) {
        Ok(w) => w,
        Err(_) => return AgeResult::ArmorError,
    };

    if writer.write_all(data).is_err() {
        return AgeResult::ArmorError;
    }

    if writer.finish().is_err() {
        return AgeResult::ArmorError;
    }

    let armored_str = match String::from_utf8(armored) {
        Ok(s) => s,
        Err(_) => return AgeResult::ArmorError,
    };

    let c_output = match string_to_cstr(armored_str) {
        Ok(s) => s,
        Err(e) => return e,
    };

    unsafe {
        *output = c_output;
    }

    AgeResult::Success
}

/// Remove ASCII armor from data.
///
/// # Arguments
/// * `armored` - The armored string
/// * `output` - Pointer to receive the binary buffer
///
/// # Returns
/// AgeResult indicating success or failure
#[no_mangle]
pub extern "C" fn age_dearmor(
    armored: *const c_char,
    output: *mut AgeBuffer,
) -> AgeResult {
    if output.is_null() {
        return AgeResult::InvalidInput;
    }

    let armored_str = match unsafe { cstr_to_str(armored) } {
        Ok(s) => s,
        Err(e) => return e,
    };

    let mut reader = age::armor::ArmoredReader::new(armored_str.as_bytes());

    let mut dearmored = Vec::new();
    if reader.read_to_end(&mut dearmored).is_err() {
        return AgeResult::ArmorError;
    }

    unsafe {
        *output = AgeBuffer::from_vec(dearmored);
    }

    AgeResult::Success
}
