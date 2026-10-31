// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;

pub struct GChatClient {
    _private: (),
}

pub type GChatEventCallback =
    extern "C" fn(userdata: usize, event_json_ptr: *const c_char, event_json_len: usize);

pub(crate) unsafe fn write_err(err_out: *mut *mut c_char, msg: impl Into<String>) {
    if !err_out.is_null() {
        let s = msg.into().replace('\0', " ");
        if let Ok(cs) = CString::new(s) {
            *err_out = cs.into_raw();
        }
    }
}

#[allow(dead_code)]
pub(crate) unsafe fn read_cstr(ptr: *const c_char, label: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{label} pointer is null"));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map(|s| s.to_owned())
        .map_err(|e| format!("{label} is not valid UTF-8: {e}"))
}

#[allow(dead_code)]
pub(crate) fn into_c_string(s: String) -> *mut c_char {
    let clean = s.replace('\0', " ");
    CString::new(clean).expect("nul bytes replaced").into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn gchat_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_bytes_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len > 0 {
        drop(Vec::from_raw_parts(ptr, len, len));
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_validate_session(
    _config_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    write_err(err_out, "gchat_validate_session not yet implemented");
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_new(
    _config_json: *const c_char,
    _cb: GChatEventCallback,
    _userdata: usize,
    err_out: *mut *mut c_char,
) -> *mut GChatClient {
    write_err(err_out, "gchat_client_new not yet implemented");
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_connect(
    _client: *mut GChatClient,
    err_out: *mut *mut c_char,
) -> c_int {
    write_err(err_out, "gchat_client_connect not yet implemented");
    -1
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_disconnect(_client: *mut GChatClient) {}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_free(client: *mut GChatClient) {
    if !client.is_null() {
        drop(Box::from_raw(client));
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_call_json(
    _client: *mut GChatClient,
    _method: *const c_char,
    _req_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    write_err(err_out, "gchat_client_call_json not yet implemented");
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_upload_media(
    _client: *mut GChatClient,
    _group_id: *const c_char,
    _filename: *const c_char,
    _mime_type: *const c_char,
    _bytes_ptr: *const u8,
    _bytes_len: usize,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    write_err(err_out, "gchat_client_upload_media not yet implemented");
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_download_media(
    _client: *mut GChatClient,
    _url: *const c_char,
    _bytes_out: *mut *mut u8,
    _len_out: *mut usize,
    _mime_out: *mut *mut c_char,
    err_out: *mut *mut c_char,
) -> c_int {
    write_err(err_out, "gchat_client_download_media not yet implemented");
    -1
}
