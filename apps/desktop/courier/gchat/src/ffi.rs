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
    pub(crate) runtime: tokio::runtime::Runtime,
    pub(crate) http: Client,
    pub(crate) jar: DomainCookieJar,
    pub(crate) xsrf: Arc<XsrfTokenManager>,
    pub(crate) guard: NetGuard,
    pub(crate) user_agent: String,
    pub(crate) base_url: Url,
    pub(crate) refresh_handle: tokio::task::JoinHandle<()>,
    pub(crate) manual_clock: std::sync::Mutex<Option<Arc<crate::channel::ManualChannelClock>>>,
    pub(crate) active_wc: std::sync::Mutex<Option<Arc<WebChannelClient>>>,
    pub(crate) stream_state: std::sync::Mutex<
        Option<(
            tokio::sync::watch::Sender<bool>,
            tokio::task::JoinHandle<()>,
        )>,
    >,
}

impl GChatClient {
    pub(crate) fn stop_stream_and_wait(&self) {
        let prev = self.stream_state.lock().ok().and_then(|mut g| g.take());
        if let Some((tx, handle)) = prev {
            let _ = tx.send(true);
            handle.abort();
            let _ = self.runtime.block_on(handle);
        }
    }
}

impl Drop for GChatClient {
    fn drop(&mut self) {
        self.stop_stream_and_wait();
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
    pub(crate) fn from_config_json(config_json: &str) -> Result<Self, GChatError> {
        Self::from_config_json_with_guard(config_json, NetGuard::from_ambient())
    }

    pub(crate) fn from_config_json_with_guard(
        config_json: &str,
        guard: NetGuard,
    ) -> Result<Self, GChatError> {
        let cfg: SessionConfigInput = serde_json::from_str(config_json).map_err(|e| {
            GChatError::CookieValidation(format!("invalid session config JSON: {e}"))
        })?;

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
            manual_clock: std::sync::Mutex::new(None),
            active_wc: std::sync::Mutex::new(None),
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
        client_ref.stop_stream_and_wait();

        let Ok(mut state_guard) = client_ref.stream_state.lock() else {
            write_err_slice(out_err, "stream_state mutex poisoned");
            return GChatStatus::GchatErrInternal;
        };

        let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
        let clock: Arc<dyn crate::channel::ChannelClock> = client_ref
            .manual_clock
            .lock()
            .ok()
            .and_then(|g| g.clone())
            .map(|c| c as Arc<dyn crate::channel::ChannelClock>)
            .unwrap_or_else(|| Arc::new(crate::channel::SystemChannelClock));
        let wc = Arc::new(WebChannelClient::with_clock(
            client_ref.http.clone(),
            client_ref.jar.clone(),
            client_ref.xsrf.clone(),
            client_ref.guard.clone(),
            client_ref.user_agent.clone(),
            client_ref.base_url.clone(),
            clock,
        ));
        if let Ok(mut wc_guard) = client_ref.active_wc.lock() {
            *wc_guard = Some(wc.clone());
        }
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
        client_ref.stop_stream_and_wait();
        client_ref.refresh_handle.abort();
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_use_manual_clock(client: *mut GChatClient, fixed_jitter: f64) {
    if !client.is_null() {
        let client_ref = &*client;
        let clock = Arc::new(crate::channel::ManualChannelClock::new(fixed_jitter));
        if let Ok(mut guard) = client_ref.manual_clock.lock() {
            *guard = Some(clock.clone());
        }
        if let Ok(wc_guard) = client_ref.active_wc.lock() {
            if let Some(wc) = wc_guard.as_ref() {
                wc.set_clock(clock);
            }
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn gchat_advance_manual_clock(
    client: *mut GChatClient,
    delta_ms: u64,
) -> usize {
    if client.is_null() {
        return 0;
    }
    let client_ref = &*client;
    let clock_opt = client_ref.manual_clock.lock().ok().and_then(|g| g.clone());
    let Some(clock) = clock_opt else {
        return 0;
    };
    if delta_ms > 0 {
        clock.advance(std::time::Duration::from_millis(delta_ms));
    }
    clock.sleeper_count()
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
    let plain_body = val
        .get("plain_body")
        .or_else(|| val.get("text"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let formatted_body = val
        .get("formatted_body")
        .or_else(|| val.get("html"))
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty());
    let allow_mention_all = val
        .get("allow_mention_all")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let converted = match crate::fmt::outbound::matrix_html_to_annotations(
        plain_body,
        formatted_body,
        allow_mention_all,
    ) {
        Ok(c) => c,
        Err(e) => {
            let st = status_from_error(&e);
            write_err_slice(out_err, e.to_string());
            return st;
        }
    };

    let annotations_b64: Vec<String> = converted
        .annotations
        .iter()
        .map(|a| base64::engine::general_purpose::STANDARD.encode(a.encode_to_vec()))
        .collect();
    let msg = pb::Message {
        text_body: Some(converted.text.clone()),
        annotations: converted.annotations,
        ..Default::default()
    };
    let proto_b64 = base64::engine::general_purpose::STANDARD.encode(msg.encode_to_vec());
    let out_json = serde_json::json!({
        "text": converted.text,
        "message_proto_base64": proto_b64,
        "annotations_proto_base64": annotations_b64,
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
    let html = converted
        .formatted_body
        .clone()
        .unwrap_or_else(|| crate::fmt::inbound::escape_html(&converted.body));
    let out_json = serde_json::json!({
        "body": converted.body,
        "formatted_body": converted.formatted_body,
        "mentions": converted.mentions,
        "mention_all": converted.mention_all,
        "text": converted.body,
        "html": html,
        "annotations_count": msg.annotations.len(),
    });
    write_slice_out(out_result_json, out_json.to_string().into_bytes());
    GChatStatus::GchatOk
}

#[derive(Deserialize)]
struct UploadMediaReqInput {
    #[serde(default)]
    group_id: String,
    #[serde(default)]
    filename: String,
    #[serde(default)]
    content_type: String,
}

#[derive(Deserialize)]
struct DownloadMediaReqInput {
    #[serde(default)]
    kind: String,
    #[serde(default)]
    attachment_token: String,
    #[serde(default)]
    content_type: String,
    #[serde(default)]
    url: String,
    #[serde(default)]
    external_enabled: bool,
}

#[no_mangle]
pub unsafe extern "C" fn gchat_upload_media(
    client: *mut GChatClient,
    req_json_ptr: *const u8,
    req_json_len: usize,
    data_ptr: *const u8,
    data_len: usize,
    out_upload_proto: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if client.is_null() || out_upload_proto.is_null() {
        write_err_slice(out_err, "client or out_upload_proto pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    let req_json = match read_utf8(req_json_ptr, req_json_len, "req_json") {
        Ok(s) => s,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let req: UploadMediaReqInput = match serde_json::from_str(&req_json) {
        Ok(r) => r,
        Err(e) => {
            write_err_slice(out_err, format!("invalid upload_media JSON: {e}"));
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let data = match read_bytes(data_ptr, data_len, "data") {
        Ok(b) => b,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let client_ref = &*client;
    let res = client_ref.runtime.block_on(crate::media::scotty_upload(
        client_ref,
        &req.group_id,
        &req.filename,
        &req.content_type,
        data,
    ));
    match res {
        Ok(upload_meta) => {
            write_slice_out(out_upload_proto, upload_meta.encode_to_vec());
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
pub unsafe extern "C" fn gchat_download_media(
    client: *mut GChatClient,
    req_json_ptr: *const u8,
    req_json_len: usize,
    out_bytes: *mut GChatByteSlice,
    out_err: *mut GChatByteSlice,
) -> GChatStatus {
    if client.is_null() || out_bytes.is_null() {
        write_err_slice(out_err, "client or out_bytes pointer is null");
        return GChatStatus::GchatErrInvalidArg;
    }
    let req_json = match read_utf8(req_json_ptr, req_json_len, "req_json") {
        Ok(s) => s,
        Err(e) => {
            write_err_slice(out_err, e);
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let req: DownloadMediaReqInput = match serde_json::from_str(&req_json) {
        Ok(r) => r,
        Err(e) => {
            write_err_slice(out_err, format!("invalid download_media JSON: {e}"));
            return GChatStatus::GchatErrInvalidArg;
        }
    };
    let client_ref = &*client;
    let kind = if req.kind.trim().is_empty() {
        "attachment"
    } else {
        req.kind.trim()
    };
    let res: Result<(Vec<u8>, String), GChatError> = match kind {
        "attachment" => {
            client_ref
                .runtime
                .block_on(crate::media::download_attachment_with_content_type(
                    client_ref,
                    &req.attachment_token,
                    &req.content_type,
                ))
        }
        "avatar" => client_ref
            .runtime
            .block_on(crate::media::download_avatar(&client_ref.guard, &req.url)),
        "external" => {
            match client_ref
                .runtime
                .block_on(crate::media::download_external_image_if_enabled(
                    &client_ref.guard,
                    &req.url,
                    req.external_enabled,
                )) {
                Ok(Some(pair)) => Ok(pair),
                Ok(None) => Ok((Vec::new(), String::new())),
                Err(e) => Err(e),
            }
        }
        other => Err(GChatError::Protocol(format!(
            "unsupported download_media kind: {other}"
        ))),
    };
    match res {
        Ok((bytes, _mime)) => {
            write_slice_out(out_bytes, bytes);
            GChatStatus::GchatOk
        }
        Err(e) => {
            let st = status_from_error(&e);
            write_err_slice(out_err, e.to_string());
            st
        }
    }
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
