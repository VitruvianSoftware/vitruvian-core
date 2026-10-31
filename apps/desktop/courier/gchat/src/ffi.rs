// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::auth::XsrfTokenManager;
use crate::cookies::{normalize_user_agent, DomainCookieJar, ScopedCookie};
use crate::netguard::NetGuard;
use crate::pb;
use crate::rpc::invoke_proto_rpc;
use crate::GChatError;
use base64::Engine;
use prost::Message;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use url::Url;

pub struct GChatClient {
    _private: (),
}

pub type GChatEventCallback =
    extern "C" fn(userdata: usize, event_json_ptr: *const c_char, event_json_len: usize);

#[derive(Deserialize)]
struct SessionConfigInput {
    #[serde(default)]
    cookies: Vec<ScopedCookie>,
    #[serde(default)]
    cookie_map: Option<BTreeMap<String, String>>,
    #[serde(default)]
    user_agent: Option<String>,
    #[serde(default)]
    base_url: Option<String>,
    #[serde(default)]
    allow_loopback_for_test: bool,
}

#[derive(Serialize)]
struct ValidatedSessionOutput {
    gaia_id: String,
    name: String,
    email: String,
    avatar_url: String,
}

pub(crate) unsafe fn write_err(err_out: *mut *mut c_char, msg: impl Into<String>) {
    if !err_out.is_null() {
        let s = msg.into().replace('\0', " ");
        if let Ok(cs) = CString::new(s) {
            *err_out = cs.into_raw();
        }
    }
}

pub(crate) unsafe fn read_cstr(ptr: *const c_char, label: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{label} pointer is null"));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map(|s| s.to_owned())
        .map_err(|e| format!("{label} is not valid UTF-8: {e}"))
}

pub(crate) fn into_c_string(s: String) -> *mut c_char {
    let clean = s.replace('\0', " ");
    CString::new(clean).expect("nul bytes replaced").into_raw()
}

fn decode_proto_or_base64<M: Message + Default>(bytes: &[u8]) -> Result<M, GChatError> {
    if let Ok(msg) = M::decode(bytes) {
        return Ok(msg);
    }
    let cleaned: Vec<u8> = bytes
        .iter()
        .copied()
        .filter(|b| !b.is_ascii_whitespace())
        .collect();
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(&cleaned)
        .map_err(|e| GChatError::Proto(format!("neither binary proto nor base64: {e}")))?;
    M::decode(decoded.as_slice())
        .map_err(|e| GChatError::Proto(format!("failed to decode protobuf after base64: {e}")))
}

async fn validate_session_async(config_json: &str) -> Result<ValidatedSessionOutput, GChatError> {
    let cfg: SessionConfigInput = serde_json::from_str(config_json)
        .map_err(|e| GChatError::CookieValidation(format!("invalid session config JSON: {e}")))?;

    let jar = if !cfg.cookies.is_empty() {
        DomainCookieJar::from_scoped_cookies(cfg.cookies)?
    } else if let Some(map) = &cfg.cookie_map {
        DomainCookieJar::from_flat_cookie_map(map)?
    } else {
        return Err(GChatError::CookieValidation(
            "no cookies provided".to_string(),
        ));
    };

    let user_agent = normalize_user_agent(cfg.user_agent.as_deref());
    let base_url_str = cfg
        .base_url
        .as_deref()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or("https://chat.google.com/");
    let base_url = Url::parse(base_url_str)
        .map_err(|e| GChatError::Internal(format!("invalid base_url: {e}")))?;

    let guard = NetGuard::from_test_flag(cfg.allow_loopback_for_test);
    guard.validate_url(&base_url, false).await?;

    let http = Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|e| GChatError::Internal(format!("failed to build HTTP client: {e}")))?;

    let xsrf = XsrfTokenManager::new(
        http.clone(),
        jar.clone(),
        base_url.clone(),
        user_agent.clone(),
        guard.clone(),
    );

    let status_bytes = invoke_proto_rpc(
        &http,
        &jar,
        &xsrf,
        &guard,
        &user_agent,
        &base_url,
        "get_self_user_status",
        &[],
    )
    .await?;

    let status_resp: pb::GetSelfUserStatusResponse = decode_proto_or_base64(&status_bytes)?;
    let gaia_id = status_resp
        .user_status
        .and_then(|s| s.user_id)
        .and_then(|u| u.id)
        .filter(|id| !id.trim().is_empty())
        .ok_or_else(|| {
            GChatError::AuthExpired("get_self_user_status returned no gaia_id".to_string())
        })?;

    let mut name = String::new();
    let mut email = String::new();
    let mut avatar_url = String::new();

    // Best-effort profile lookup via get_members (matching ref/pkg/connector/userinfo.go:38-73).
    let get_members_req = pb::GetMembersRequest {
        request_header: None,
        member_ids: vec![pb::MemberId {
            id: Some(pb::member_id::Id::UserId(pb::UserId {
                id: Some(gaia_id.clone()),
                r#type: Some(pb::UserType::Human as i32),
            })),
        }],
        membership_ids: Vec::new(),
    };
    if let Ok(members_bytes) = invoke_proto_rpc(
        &http,
        &jar,
        &xsrf,
        &guard,
        &user_agent,
        &base_url,
        "get_members",
        &get_members_req.encode_to_vec(),
    )
    .await
    {
        if let Ok(members_resp) = decode_proto_or_base64::<pb::GetMembersResponse>(&members_bytes) {
            let user_opt = members_resp
                .members
                .into_iter()
                .find_map(|m| match m.profile {
                    Some(pb::member::Profile::User(u)) => Some(u),
                    None => None,
                })
                .or_else(|| {
                    members_resp.member_profiles.into_iter().find_map(|mp| {
                        mp.member.and_then(|m| match m.profile {
                            Some(pb::member::Profile::User(u)) => Some(u),
                            None => None,
                        })
                    })
                });
            if let Some(u) = user_opt {
                name = u.name.unwrap_or_default();
                email = u.email.unwrap_or_default();
                avatar_url = u.avatar_url.unwrap_or_default();
            }
        }
    }

    Ok(ValidatedSessionOutput {
        gaia_id,
        name,
        email,
        avatar_url,
    })
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
    config_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    let raw = match read_cstr(config_json, "config_json") {
        Ok(s) => s,
        Err(e) => {
            write_err(err_out, e);
            return ptr::null_mut();
        }
    };

    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            write_err(err_out, format!("failed to build tokio runtime: {e}"));
            return ptr::null_mut();
        }
    };

    match rt.block_on(validate_session_async(&raw)) {
        Ok(out) => match serde_json::to_string(&out) {
            Ok(json) => into_c_string(json),
            Err(e) => {
                write_err(err_out, format!("failed to serialize session output: {e}"));
                ptr::null_mut()
            }
        },
        Err(e) => {
            write_err(err_out, e.to_string());
            ptr::null_mut()
        }
    }
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
