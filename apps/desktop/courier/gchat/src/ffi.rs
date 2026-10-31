// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::auth::XsrfTokenManager;
use crate::channel::WebChannelClient;
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
use std::os::raw::c_char;
use std::ptr;
use std::slice;
use std::sync::Arc;
use url::Url;

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GChatStatus {
    GchatOk = 0,
    GchatErrInvalidArg = 1,
    GchatErrAuthExpired = 2,
    GchatErrRateLimited = 3,
    GchatErrTransient = 4,
    GchatErrSsrfBlocked = 5,
    GchatErrProtocol = 6,
    GchatErrInternal = 7,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct GChatByteSlice {
    pub ptr: *mut u8,
    pub len: usize,
}

impl Default for GChatByteSlice {
    fn default() -> Self {
        Self {
            ptr: ptr::null_mut(),
            len: 0,
        }
    }
}

pub type GChatEventCallback =
    extern "C" fn(userdata: usize, event_kind: i32, payload_ptr: *const u8, payload_len: usize);

pub struct GChatClient {
    runtime: tokio::runtime::Runtime,
    http: Client,
    jar: DomainCookieJar,
    xsrf: Arc<XsrfTokenManager>,
    guard: NetGuard,
    user_agent: String,
    base_url: Url,
    refresh_handle: tokio::task::JoinHandle<()>,
    stream_state: std::sync::Mutex<
        Option<(
            tokio::sync::watch::Sender<bool>,
            tokio::task::JoinHandle<()>,
        )>,
    >,
}

impl Drop for GChatClient {
    fn drop(&mut self) {
        if let Ok(mut guard) = self.stream_state.lock() {
            if let Some((tx, handle)) = guard.take() {
                let _ = tx.send(true);
                handle.abort();
            }
        }
        self.refresh_handle.abort();
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SessionConfigInput {
    #[serde(default)]
    cookies: Vec<ScopedCookie>,
    #[serde(default)]
    cookie_map: Option<BTreeMap<String, String>>,
    #[serde(default)]
    user_agent: Option<String>,
    #[serde(default)]
    base_url: Option<String>,
}

#[derive(Serialize)]
struct ValidatedSessionOutput {
    gaia_id: String,
    name: String,
    email: String,
    avatar_url: String,
}

fn vec_into_byte_slice(v: Vec<u8>) -> GChatByteSlice {
    if v.is_empty() {
        return GChatByteSlice::default();
    }
    let boxed = v.into_boxed_slice();
    let len = boxed.len();
    let ptr = Box::into_raw(boxed) as *mut u8;
    GChatByteSlice { ptr, len }
}

unsafe fn write_slice_out(out: *mut GChatByteSlice, bytes: Vec<u8>) {
    if !out.is_null() {
        *out = vec_into_byte_slice(bytes);
    }
}

unsafe fn write_err_slice(out_err: *mut GChatByteSlice, msg: impl Into<String>) {
    if !out_err.is_null() {
        *out_err = vec_into_byte_slice(msg.into().into_bytes());
    }
}

fn status_from_error(err: &GChatError) -> GChatStatus {
    match err {
        GChatError::CookieValidation(_) => GChatStatus::GchatErrInvalidArg,
        GChatError::AuthExpired(_) => GChatStatus::GchatErrAuthExpired,
        GChatError::RateLimited => GChatStatus::GchatErrRateLimited,
        GChatError::HttpStatus(code, _) if matches!(code, 500..=599) => {
            GChatStatus::GchatErrTransient
        }
        GChatError::HttpStatus(_, _) | GChatError::Network(_) => GChatStatus::GchatErrTransient,
        GChatError::SsrfBlocked(_) => GChatStatus::GchatErrSsrfBlocked,
        GChatError::Proto(_) | GChatError::Protocol(_) => GChatStatus::GchatErrProtocol,
        GChatError::Internal(_) => GChatStatus::GchatErrInternal,
    }
}

unsafe fn read_bytes<'a>(ptr: *const u8, len: usize, label: &str) -> Result<&'a [u8], String> {
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(format!(
            "{label} pointer is null with non-zero length {len}"
        ));
    }
    Ok(slice::from_raw_parts(ptr, len))
}

unsafe fn read_utf8(ptr: *const u8, len: usize, label: &str) -> Result<String, String> {
    let bytes = read_bytes(ptr, len, label)?;
    std::str::from_utf8(bytes)
        .map(|s| s.to_owned())
        .map_err(|e| format!("{label} is not valid UTF-8: {e}"))
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

impl GChatClient {
    fn from_config_json(config_json: &str) -> Result<Self, GChatError> {
        let cfg: SessionConfigInput = serde_json::from_str(config_json).map_err(|e| {
            GChatError::CookieValidation(format!("invalid session config JSON: {e}"))
        })?;

        let guard = NetGuard::from_ambient();

        #[allow(unused_mut)]
        let mut jar = if !cfg.cookies.is_empty() {
            DomainCookieJar::from_scoped_cookies(cfg.cookies)?
        } else if let Some(map) = &cfg.cookie_map {
            DomainCookieJar::from_flat_cookie_map(map)?
        } else {
            return Err(GChatError::CookieValidation(
                "no cookies provided".to_string(),
            ));
        };

        #[cfg(any(test, feature = "test-loopback"))]
        if guard.is_loopback_test_allowed() {
            jar = jar.with_loopback_for_test(true);
        }

        let user_agent = normalize_user_agent(cfg.user_agent.as_deref());
        let base_url_str = cfg
            .base_url
            .as_deref()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or("https://chat.google.com/");
        let base_url = Url::parse(base_url_str)
            .map_err(|e| GChatError::CookieValidation(format!("invalid base_url: {e}")))?;

        guard.validate_host_and_scheme(&base_url, false)?;
        let http = guard.build_http_client()?;

        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .map_err(|e| GChatError::Internal(format!("failed to build tokio runtime: {e}")))?;

        let xsrf = Arc::new(XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            user_agent.clone(),
            guard.clone(),
        ));

        let refresh_handle = {
            let _enter = runtime.enter();
            xsrf.start_background_refresh()
        };

        Ok(Self {
            runtime,
            http,
            jar,
            xsrf,
            guard,
            user_agent,
            base_url,
            refresh_handle,
            stream_state: std::sync::Mutex::new(None),
        })
    }
}

crate::edition2021! {
    impl GChatClient {
        async fn validate_session_async(&self) -> Result<ValidatedSessionOutput, GChatError> {
            self.guard.validate_url(&self.base_url, false).await?;

            let status_bytes = invoke_proto_rpc(
                &self.http,
                &self.jar,
                &self.xsrf,
                &self.guard,
                &self.user_agent,
                &self.base_url,
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
                &self.http,
                &self.jar,
                &self.xsrf,
                &self.guard,
                &self.user_agent,
                &self.base_url,
                "get_members",
                &get_members_req.encode_to_vec(),
            )
            .await
            {
                if let Ok(members_resp) =
                    decode_proto_or_base64::<pb::GetMembersResponse>(&members_bytes)
                {
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
    }
}

#[cfg(any(test, feature = "test-loopback"))]
#[no_mangle]
pub extern "C" fn gchat_test_only_set_allow_loopback(allow: std::os::raw::c_int) {
    crate::netguard::set_global_test_loopback_override(allow != 0);
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_new(
    config_json_ptr: *const u8,
    config_json_len: usize,
    out_client: *mut *mut GChatClient,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if out_client.is_null() {
        write_err_slice(out_err, "out_client pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    *out_client = ptr::null_mut();

    let config_json = match read_utf8(config_json_ptr, config_json_len, "config_json") {
        Ok(s) => s,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };

    match GChatClient::from_config_json(&config_json) {
        Ok(client) => {
            *out_client = Box::into_raw(Box::new(client));
            GChatStatus::GchatOk
        }
        Err(e) => {
            let st = status_from_error(&e);
            write_err_slice(out_err, e.to_string());
            st
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_client_free(client: *mut GChatClient) {
    if !client.is_null() {
        drop(Box::from_raw(client));
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_bytes_free(slice: GChatByteSlice) {
    if !slice.ptr.is_null() && slice.len > 0 {
        drop(Box::from_raw(ptr::slice_from_raw_parts_mut(
            slice.ptr, slice.len,
        )));
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_validate_session(
    client: *mut GChatClient,
    out_self_json: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if client.is_null() || out_self_json.is_null() {
        write_err_slice(out_err, "client or out_self_json pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    let client_ref = &*client;
    match client_ref
        .runtime
        .block_on(client_ref.validate_session_async())
    {
        Ok(out) => match serde_json::to_vec(&out) {
            Ok(bytes) => {
                write_slice_out(out_self_json, bytes);
                GChatStatus::GchatOk
            }
            Err(e) => {
                write_err_slice(out_err, format!("failed to serialize session output: {e}"));
                GChatStatus::GchatErrInternal
            }
        },
        Err(e) => {
            let st = status_from_error(&e);
            write_err_slice(out_err, e.to_string());
            st
        }
    }
}

crate::edition2021! {
    #[no_mangle]
    pub unsafe extern "C" fn gchat_start_stream(
        client: *mut GChatClient,
        cb: GChatEventCallback,
        userdata: usize,
        out_err: *mut GChatByteSlice,
    ) -> GChatStatus {
        if client.is_null() {
            write_err_slice(out_err, "client pointer is null");
            return GChatStatus::GchatErrInvalidArg;
        }
        let client_ref = &*client;
        let Ok(mut state_guard) = client_ref.stream_state.lock() else {
            write_err_slice(out_err, "stream_state mutex poisoned");
            return GChatStatus::GchatErrInternal;
        };
        if let Some((prev_tx, prev_handle)) = state_guard.take() {
            let _ = prev_tx.send(true);
            prev_handle.abort();
        }

        let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
        let wc = Arc::new(WebChannelClient::new(
            client_ref.http.clone(),
            client_ref.jar.clone(),
            client_ref.xsrf.clone(),
            client_ref.guard.clone(),
            client_ref.user_agent.clone(),
            client_ref.base_url.clone(),
        ));
        let handle = client_ref.runtime.spawn(async move {
            wc.run_forever(cancel_rx, move |event_kind, payload| {
                let ptr = if payload.is_empty() {
                    ptr::null()
                } else {
                    payload.as_ptr()
                };
                cb(userdata, event_kind, ptr, payload.len());
            })
            .await;
        });
        *state_guard = Some((cancel_tx, handle));
        GChatStatus::GchatOk
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_stop_stream(client: *mut GChatClient) {
    if !client.is_null() {
        let client_ref = &*client;
        if let Ok(mut guard) = client_ref.stream_state.lock() {
            if let Some((tx, handle)) = guard.take() {
                let _ = tx.send(true);
                handle.abort();
            }
        }
        client_ref.refresh_handle.abort();
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_rpc_call(
    client: *mut GChatClient,
    endpoint_ptr: *const c_char,
    endpoint_len: usize,
    req_proto_ptr: *const u8,
    req_proto_len: usize,
    out_resp_proto: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if client.is_null() || out_resp_proto.is_null() {
        write_err_slice(out_err, "client or out_resp_proto pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    let endpoint = match read_utf8(endpoint_ptr as *const u8, endpoint_len, "endpoint") {
        Ok(s) => s,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let req_bytes = match read_bytes(req_proto_ptr, req_proto_len, "req_proto") {
        Ok(b) => b,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let client_ref = &*client;
    let res = client_ref.runtime.block_on(invoke_proto_rpc(
        &client_ref.http,
        &client_ref.jar,
        &client_ref.xsrf,
        &client_ref.guard,
        &client_ref.user_agent,
        &client_ref.base_url,
        &endpoint,
        req_bytes,
    ));
    match res {
        Ok(bytes) => {
            write_slice_out(out_resp_proto, bytes);
            GChatStatus::GchatOk
        }
        Err(e) => {
            let st = status_from_error(&e);
            write_err_slice(out_err, e.to_string());
            st
        }
    }
}

fn escape_html(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c => out.push(c),
        }
    }
    out
}

fn render_message_annotations_to_html(msg: &pb::Message) -> String {
    let text = msg.text_body.as_deref().unwrap_or("");
    if msg.annotations.is_empty() {
        return escape_html(text);
    }
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::new();
    let mut idx = 0usize;
    let mut sorted = msg.annotations.clone();
    sorted.sort_by_key(|a| a.start_index.unwrap_or(0).max(0) as usize);

    for ann in &sorted {
        let start = (ann.start_index.unwrap_or(0).max(0) as usize).min(chars.len());
        let len = ann.length.unwrap_or(0).max(0) as usize;
        let end = (start + len).min(chars.len());
        if start < idx || start >= end {
            continue;
        }
        if start > idx {
            let prefix: String = chars[idx..start].iter().collect();
            out.push_str(&escape_html(&prefix));
        }
        let segment: String = chars[start..end].iter().collect();
        let escaped = escape_html(&segment);
        let fmt_type = match &ann.metadata {
            Some(pb::annotation::Metadata::FormatMetadata(fm)) => fm.format_type.unwrap_or(0),
            _ => 0,
        };
        match fmt_type {
            1 => {
                out.push_str("<b>");
                out.push_str(&escaped);
                out.push_str("</b>");
            }
            2 => {
                out.push_str("<i>");
                out.push_str(&escaped);
                out.push_str("</i>");
            }
            3 => {
                out.push_str("<s>");
                out.push_str(&escaped);
                out.push_str("</s>");
            }
            4 => {
                out.push_str("<code>");
                out.push_str(&escaped);
                out.push_str("</code>");
            }
            5 => {
                out.push_str("<pre><code>");
                out.push_str(&escaped);
                out.push_str("</code></pre>");
            }
            _ => out.push_str(&escaped),
        }
        idx = end;
    }
    if idx < chars.len() {
        let suffix: String = chars[idx..].iter().collect();
        out.push_str(&escape_html(&suffix));
    }
    out
}

#[no_mangle]
pub unsafe extern "C" fn gchat_html_to_annotations(
    input_json_ptr: *const u8,
    input_json_len: usize,
    out_result_json: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if out_result_json.is_null() {
        write_err_slice(out_err, "out_result_json pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    let input_str = match read_utf8(input_json_ptr, input_json_len, "input_json") {
        Ok(s) => s,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let val: serde_json::Value = match serde_json::from_str(&input_str) {
        Ok(v) => v,
        Err(e) => {
            write_err_slice(out_err, format!("invalid input JSON: {e}"));
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let html = val
        .get("html")
        .or_else(|| val.get("text"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let mut plain = String::new();
    let mut annotations = Vec::new();
    let mut rest = html;
    while let Some(open_idx) = rest.find("<b>") {
        plain.push_str(&rest[..open_idx]);
        let after_open = &rest[open_idx + 3..];
        if let Some(close_idx) = after_open.find("</b>") {
            let bold_text = &after_open[..close_idx];
            let start = plain.chars().count() as i32;
            let len = bold_text.chars().count() as i32;
            plain.push_str(bold_text);
            annotations.push(pb::Annotation {
                r#type: Some(pb::AnnotationType::FormatData as i32),
                start_index: Some(start),
                length: Some(len),
                metadata: Some(pb::annotation::Metadata::FormatMetadata(
                    pb::FormatMetadata {
                        format_type: Some(pb::format_metadata::FormatType::Bold as i32),
                        ..Default::default()
                    },
                )),
                ..Default::default()
            });
            rest = &after_open[close_idx + 4..];
        } else {
            plain.push_str("<b>");
            rest = after_open;
        }
    }
    plain.push_str(rest);

    let msg = pb::Message {
        text_body: Some(plain.clone()),
        annotations,
        ..Default::default()
    };
    let proto_b64 = base64::engine::general_purpose::STANDARD.encode(msg.encode_to_vec());
    let out_json = serde_json::json!({
        "text": plain,
        "message_proto_base64": proto_b64,
    });
    write_slice_out(out_result_json, out_json.to_string().into_bytes());
    GChatStatus::GchatOk
}

#[no_mangle]
pub unsafe extern "C" fn gchat_annotations_to_html(
    input_proto_ptr: *const u8,
    input_proto_len: usize,
    out_result_json: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if out_result_json.is_null() {
        write_err_slice(out_err, "out_result_json pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    let bytes = match read_bytes(input_proto_ptr, input_proto_len, "input_proto") {
        Ok(b) => b,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let msg = match pb::Message::decode(bytes) {
        Ok(m) => m,
        Err(e) => {
            write_err_slice(out_err, format!("failed to decode Message proto: {e}"));
            return GChatStatus::GchatErrProtocol;
        }
    };
    let converted = crate::fmt::inbound::annotations_to_matrix_html(
        msg.text_body.as_deref().unwrap_or_default(),
        &msg.annotations,
        &msg.attachments,
    );
    let legacy_html = render_message_annotations_to_html(&msg);
    let out_json = serde_json::json!({
        "body": converted.body,
        "formatted_body": converted.formatted_body,
        "mentions": converted.mentions,
        "mention_all": converted.mention_all,
        "text": converted.body,
        "html": legacy_html,
        "annotations_count": msg.annotations.len(),
    });
    write_slice_out(out_result_json, out_json.to_string().into_bytes());
    GChatStatus::GchatOk
}

#[no_mangle]
pub unsafe extern "C" fn gchat_upload_media(
    client: *mut GChatClient,
    _req_json_ptr: *const u8,
    _req_json_len: usize,
    _data_ptr: *const u8,
    _data_len: usize,
    out_upload_proto: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if client.is_null() || out_upload_proto.is_null() {
        write_err_slice(out_err, "client or out_upload_proto pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    write_err_slice(out_err, "gchat_upload_media not yet implemented");
    GChatStatus::GchatErrInternal
}

#[no_mangle]
pub unsafe extern "C" fn gchat_download_media(
    client: *mut GChatClient,
    _req_json_ptr: *const u8,
    _req_json_len: usize,
    out_bytes: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if client.is_null() || out_bytes.is_null() {
        write_err_slice(out_err, "client or out_bytes pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    write_err_slice(out_err, "gchat_download_media not yet implemented");
    GChatStatus::GchatErrInternal
}

#[cfg(test)]
mod tests {
    use super::*;

    fn slice_to_string(s: GChatByteSlice) -> String {
        if s.ptr.is_null() || s.len == 0 {
            return String::new();
        }
        let out =
            unsafe { String::from_utf8_lossy(slice::from_raw_parts(s.ptr, s.len)).into_owned() };
        unsafe { gchat_bytes_free(s) };
        out
    }

    #[test]
    fn test_c_abi_client_new_and_rejects_loopback_in_production() {
        let cfg_with_loopback = r#"{"cookie_map":{"COMPASS":"c","OSID":"o","SID":"s","HSID":"h","SSID":"ss"},"allow_loopback_for_test":true}"#;
        let mut client: *mut GChatClient = ptr::null_mut();
        let mut err_slice = GChatByteSlice::default();
        let status = unsafe {
            gchat_client_new(
                cfg_with_loopback.as_ptr(),
                cfg_with_loopback.len(),
                &mut client,
                &mut err_slice,
            )
        };
        let err_msg = slice_to_string(err_slice);
        unsafe { gchat_client_free(client) };
        assert_eq!(status, GChatStatus::GchatErrInvalidArg);
        assert!(
            err_msg.contains("unknown field `allow_loopback_for_test`"),
            "production config must reject allow_loopback_for_test, got err: {err_msg}"
        );

        let valid_cfg =
            r#"{"cookie_map":{"COMPASS":"c","OSID":"o","SID":"s","HSID":"h","SSID":"ss"}}"#;
        let mut ok_client: *mut GChatClient = ptr::null_mut();
        let mut ok_err = GChatByteSlice::default();
        let ok_status = unsafe {
            gchat_client_new(
                valid_cfg.as_ptr(),
                valid_cfg.len(),
                &mut ok_client,
                &mut ok_err,
            )
        };
        let ok_err_msg = slice_to_string(ok_err);
        assert_eq!(
            ok_status,
            GChatStatus::GchatOk,
            "valid config should construct GChatClient, got err: {ok_err_msg}"
        );
        assert!(!ok_client.is_null());
        unsafe { gchat_client_free(ok_client) };
    }
}
