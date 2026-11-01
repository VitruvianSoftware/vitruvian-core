// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::auth::{map_reqwest_error, read_bounded_bytes, XsrfTokenManager};
use crate::cookies::DomainCookieJar;
use crate::netguard::NetGuard;
use crate::pb;
use crate::GChatError;
use base64::Engine;
use prost::Message;
use rand::Rng;
use reqwest::Client;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::Duration;
use url::Url;

static TRACE_COUNTER: AtomicI64 = AtomicI64::new(1);
static RPC_COUNTER: AtomicI64 = AtomicI64::new(1);

const API_KEY: &str = "AIzaSyD7InnYR3VKdb4j2rMUEbTCIr2VyEazl6k"; // gitleaks:allow (public Google Chat web-client key, not a secret)

pub const CLIENT_VERSION: i64 = 2440378181258;
pub const MAX_RPC_RESPONSE_BYTES: usize = 16 * 1024 * 1024;
pub const MAX_RETRY_AFTER_SECS: u64 = 60;
const MAX_ERR_BODY_BYTES: usize = 256;

/// `/u/0/api/{endpoint}` with the query parameters the web client sends (spec §4).
fn rpc_url(base_url: &Url, endpoint: &str, counter: i64) -> Result<Url, GChatError> {
    let rel_path = format!("/u/0/api/{endpoint}");
    let mut url = base_url
        .join(&rel_path)
        .map_err(|e| GChatError::Internal(format!("invalid RPC URL for {endpoint}: {e}")))?;
    url.query_pairs_mut()
        .append_pair("c", &counter.to_string())
        .append_pair("rt", "b")
        .append_pair("alt", "proto")
        .append_pair("key", API_KEY);
    Ok(url)
}

pub fn parse_retry_after_clamped(raw: &str) -> Option<Duration> {
    raw.trim()
        .parse::<u64>()
        .ok()
        .map(|secs| Duration::from_secs(secs.min(MAX_RETRY_AFTER_SECS)))
}

pub fn build_request_header() -> pb::RequestHeader {
    let trace_id = TRACE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let full = pb::client_feature_capabilities::CapabilityLevel::FullySupported as i32;
    pb::RequestHeader {
        trace_id: Some(trace_id),
        client_type: Some(pb::request_header::ClientType::Web as i32),
        client_version: Some(CLIENT_VERSION),
        locale: Some("en".to_string()),
        client_feature_capabilities: Some(pb::ClientFeatureCapabilities {
            enable_all_features: Some(false),
            post_rooms_level: Some(full),
            spam_room_invites_level: Some(full),
            tombstone_level: Some(full),
            rich_text_viewing_level: Some(full),
            ..Default::default()
        }),
    }
}

fn prepend_request_header(endpoint: &str, req_bytes: &[u8]) -> Vec<u8> {
    if !req_bytes.is_empty() {
        if let Ok(probe) = pb::GetSelfUserStatusRequest::decode(req_bytes) {
            if probe.request_header.is_some() {
                return req_bytes.to_vec();
            }
        }
    }
    let header = build_request_header();
    let mut prefix = if endpoint == "paginated_world" {
        pb::PaginatedWorldRequest {
            request_header: Some(header),
            ..Default::default()
        }
        .encode_to_vec()
    } else {
        pb::GetSelfUserStatusRequest {
            request_header: Some(header),
        }
        .encode_to_vec()
    };
    prefix.extend_from_slice(req_bytes);
    prefix
}

fn compute_backoff_delay(attempt: u32) -> Duration {
    let base_ms = 1000u64 << (attempt.saturating_sub(1));
    let jitter_permille: u64 = rand::thread_rng().gen_range(750..=1250);
    Duration::from_millis((base_ms * jitter_permille) / 1000)
}

fn strip_ascii_whitespace(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .copied()
        .filter(|b| !b.is_ascii_whitespace())
        .collect()
}

pub fn is_idempotent_rpc_endpoint(endpoint: &str) -> bool {
    matches!(
        endpoint,
        "get_self_user_status"
            | "paginated_world"
            | "list_topics"
            | "list_messages"
            | "catch_up_user"
            | "catch_up_group"
            | "get_members"
            | "get_group"
    )
}

crate::edition2021! {
    pub async fn invoke_proto_rpc(
        http: &Client,
        jar: &DomainCookieJar,
        xsrf: &XsrfTokenManager,
        guard: &NetGuard,
        user_agent: &str,
        base_url: &Url,
        endpoint: &str,
        req_bytes: &[u8],
    ) -> Result<Vec<u8>, GChatError> {
        invoke_proto_rpc_with_idempotency(
            http,
            jar,
            xsrf,
            guard,
            user_agent,
            base_url,
            endpoint,
            req_bytes,
            is_idempotent_rpc_endpoint(endpoint),
        )
        .await
    }

    pub async fn invoke_proto_rpc_with_idempotency(
        http: &Client,
        jar: &DomainCookieJar,
        xsrf: &XsrfTokenManager,
        guard: &NetGuard,
        user_agent: &str,
        base_url: &Url,
        endpoint: &str,
        req_bytes: &[u8],
        idempotent: bool,
    ) -> Result<Vec<u8>, GChatError> {
        let initial_url = rpc_url(base_url, endpoint, 1)?;
        guard.validate_host_and_scheme(&initial_url, false)?;

        let payload = prepend_request_header(endpoint, req_bytes);
        let mut refreshed_xsrf = false;
        let mut rate_limit_attempt = 0u32;
        let mut server_err_attempt = 0u32;

        loop {
            let (xsrf_token, xsrf_gen) = xsrf.get_token().await?;
            let counter = RPC_COUNTER.fetch_add(1, Ordering::Relaxed);
            let url = rpc_url(base_url, endpoint, counter)?;

            let mut req = http
                .post(url.clone())
                .timeout(Duration::from_secs(15))
                .header("User-Agent", user_agent)
                .header("Content-Type", "application/x-protobuf")
                .header("X-Goog-Encode-Response-If-Executable", "base64")
                .header("Origin", "https://chat.google.com")
                .header("Referer", "https://chat.google.com/")
                .header("x-framework-xsrf-token", &xsrf_token)
                .body(payload.clone());

            if let Some(cookie_hdr) = jar.cookie_header_for_request(&url) {
                req = req.header("Cookie", cookie_hdr);
            }

            let resp = req
                .send()
                .await
                .map_err(|e| map_reqwest_error(&format!("RPC {endpoint} failed"), e))?;

            let status = resp.status();
            if status.as_u16() == 401 || status.as_u16() == 403 {
                if !refreshed_xsrf {
                    refreshed_xsrf = true;
                    xsrf.refresh_if_generation(xsrf_gen).await?;
                    continue;
                }
                return Err(GChatError::AuthExpired(format!(
                    "RPC {endpoint} returned HTTP {} after XSRF refresh",
                    status.as_u16()
                )));
            }

            if status.as_u16() == 429 {
                rate_limit_attempt += 1;
                if rate_limit_attempt >= 3 {
                    return Err(GChatError::RateLimited);
                }
                let delay = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|v| v.to_str().ok())
                    .and_then(parse_retry_after_clamped)
                    .unwrap_or_else(|| compute_backoff_delay(rate_limit_attempt));
                if !delay.is_zero() {
                    tokio::time::sleep(delay).await;
                }
                continue;
            }

            if idempotent && matches!(status.as_u16(), 502 | 503 | 504) {
                server_err_attempt += 1;
                if server_err_attempt >= 3 {
                    return Err(GChatError::HttpStatus(
                        status.as_u16(),
                        format!("RPC {endpoint} failed after {server_err_attempt} attempts"),
                    ));
                }
                let delay = resp
                    .headers()
                    .get(reqwest::header::RETRY_AFTER)
                    .and_then(|v| v.to_str().ok())
                    .and_then(parse_retry_after_clamped)
                    .unwrap_or_else(|| compute_backoff_delay(server_err_attempt));
                if !delay.is_zero() {
                    tokio::time::sleep(delay).await;
                }
                continue;
            }

            if !status.is_success() {
                let err_bytes = read_bounded_bytes(resp, MAX_ERR_BODY_BYTES, endpoint)
                    .await
                    .unwrap_or_default();
                let err_snippet = String::from_utf8_lossy(&err_bytes);
                if err_snippet.contains("\"invalid_grant\"") {
                    return Err(GChatError::AuthExpired(
                        "Google returned invalid_grant".to_string(),
                    ));
                }
                return Err(GChatError::HttpStatus(
                    status.as_u16(),
                    format!("RPC {endpoint} returned HTTP {}", status.as_u16()),
                ));
            }

            let is_base64_header = resp
                .headers()
                .get("x-goog-safety-encoding")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.eq_ignore_ascii_case("base64"))
                .unwrap_or(false);

            let raw_bytes = read_bounded_bytes(resp, MAX_RPC_RESPONSE_BYTES, endpoint).await?;

            if is_base64_header {
                let cleaned = strip_ascii_whitespace(&raw_bytes);
                let decoded = base64::engine::general_purpose::STANDARD
                    .decode(&cleaned)
                    .map_err(|e| {
                        GChatError::Proto(format!("base64 decode failed for {endpoint}: {e}"))
                    })?;
                return Ok(decoded);
            }

            return Ok(raw_bytes);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cookies::{ScopedCookie, DEFAULT_MACOS_SAFARI_UA};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    fn test_cookie_jar() -> DomainCookieJar {
        DomainCookieJar::from_scoped_cookies(vec![
            ScopedCookie {
                name: "COMPASS".to_string(),
                value: "compass_test".to_string(),
                domain: "chat.google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "OSID".to_string(),
                value: "osid_test".to_string(),
                domain: "chat.google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "SID".to_string(),
                value: "sid_test".to_string(),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "HSID".to_string(),
                value: "hsid_test".to_string(),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "SSID".to_string(),
                value: "ssid_test".to_string(),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            },
        ])
        .expect("valid test jar")
        .with_loopback_for_test(true)
    }

    crate::edition2021! {
        #[tokio::test]
        async fn test_rpc_caller_attaches_header_retries_429_and_decodes_base64_fallback() {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let base_url = Url::parse(&format!("http://127.0.0.1:{}/", addr.port())).unwrap();

            let mole_world_hits = Arc::new(AtomicUsize::new(0));
            let rpc_hits = Arc::new(AtomicUsize::new(0));

            let mole_hits_srv = Arc::clone(&mole_world_hits);
            let rpc_hits_srv = Arc::clone(&rpc_hits);

            let server_handle = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    let mole_hits = Arc::clone(&mole_hits_srv);
                    let rpc_hits = Arc::clone(&rpc_hits_srv);
                    tokio::spawn(async move {
                        let mut buf = vec![0u8; 16384];
                        let mut total = 0usize;
                        let header_end = loop {
                            let n = stream.read(&mut buf[total..]).await.unwrap_or(0);
                            if n == 0 {
                                return;
                            }
                            total += n;
                            if let Some(pos) = buf[..total].windows(4).position(|w| w == b"\r\n\r\n") {
                                break pos + 4;
                            }
                        };
                        let headers_str = String::from_utf8_lossy(&buf[..header_end]).to_string();
                        let content_length = headers_str
                            .lines()
                            .find_map(|line| {
                                let lower = line.to_ascii_lowercase();
                                lower
                                    .strip_prefix("content-length:")
                                    .and_then(|v| v.trim().parse::<usize>().ok())
                            })
                            .unwrap_or(0);
                        while total < header_end + content_length {
                            let n = stream.read(&mut buf[total..]).await.unwrap_or(0);
                            if n == 0 {
                                break;
                            }
                            total += n;
                        }
                        let body = &buf[header_end..header_end + content_length];
                        let first_line = headers_str.lines().next().unwrap_or("");

                        if first_line.starts_with("GET /u/0/mole/world") {
                            let count = mole_hits.fetch_add(1, Ordering::SeqCst) + 1;
                            let token = format!("AF1QipP_token_gen_{count}:1710000000000");
                            let html =
                                format!(r#"<html><script>{{"xsrf_token":"{token}"}}</script></html>"#);
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                html.len(),
                                html
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                            return;
                        }

                        if first_line.starts_with("POST /u/0/api/get_self_user_status?") {
                            assert!(
                                first_line.contains("rt=b")
                                    && first_line.contains("alt=proto")
                                    && first_line.contains(&format!("key={API_KEY}"))
                                    && first_line.contains("c="),
                                "missing expected query params in {first_line}"
                            );
                            let lower_headers = headers_str.to_ascii_lowercase();
                            assert!(
                                lower_headers.contains("x-goog-encode-response-if-executable: base64")
                            );
                            assert!(lower_headers.contains("content-type: application/x-protobuf"));
                            assert!(lower_headers.contains("origin: https://chat.google.com"));
                            assert!(lower_headers.contains("referer: https://chat.google.com/"));

                            let decoded_req = pb::GetSelfUserStatusRequest::decode(body)
                                .expect("valid GetSelfUserStatusRequest protobuf");
                            let req_header = decoded_req
                                .request_header
                                .expect("RequestHeader at field 100");
                            assert_eq!(req_header.locale.as_deref(), Some("en"));

                            let proto_resp = pb::GetSelfUserStatusResponse {
                                user_status: Some(pb::UserStatus {
                                    user_id: Some(pb::UserId {
                                        id: Some("112233445566778899001".to_string()),
                                        r#type: Some(pb::UserType::Human as i32),
                                    }),
                                    ..Default::default()
                                }),
                                ..Default::default()
                            };
                            let b64 = base64::engine::general_purpose::STANDARD
                                .encode(proto_resp.encode_to_vec());

                            let call_num = rpc_hits.fetch_add(1, Ordering::SeqCst) + 1;
                            match call_num {
                                1 => {
                                    assert!(lower_headers.contains(
                                        "x-framework-xsrf-token: af1qipp_token_gen_1:1710000000000"
                                    ));
                                    let resp = "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 0\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                                    let _ = stream.write_all(resp.as_bytes()).await;
                                }
                                2 => {
                                    assert!(lower_headers.contains(
                                        "x-framework-xsrf-token: af1qipp_token_gen_1:1710000000000"
                                    ));
                                    let resp = format!(
                                        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Goog-Safety-Encoding: base64\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                        b64.len(),
                                        b64
                                    );
                                    let _ = stream.write_all(resp.as_bytes()).await;
                                }
                                3 => {
                                    assert!(lower_headers.contains(
                                        "x-framework-xsrf-token: af1qipp_token_gen_1:1710000000000"
                                    ));
                                    let resp = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                                    let _ = stream.write_all(resp.as_bytes()).await;
                                }
                                4 => {
                                    assert!(lower_headers.contains(
                                        "x-framework-xsrf-token: af1qipp_token_gen_2:1710000000000"
                                    ));
                                    let resp = format!(
                                        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Goog-Safety-Encoding: base64\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                        b64.len(),
                                        b64
                                    );
                                    let _ = stream.write_all(resp.as_bytes()).await;
                                }
                                5 | 6 => {
                                    let resp = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                                    let _ = stream.write_all(resp.as_bytes()).await;
                                }
                                _ => {}
                            }
                        }
                    });
                }
            });

            let jar = test_cookie_jar();
            let guard = NetGuard::allow_loopback_for_test();
            let http = guard.build_http_client().unwrap();
            let xsrf = Arc::new(XsrfTokenManager::new(
                http.clone(),
                jar.clone(),
                base_url.clone(),
                DEFAULT_MACOS_SAFARI_UA.to_string(),
                guard.clone(),
            ));

            let empty_req = pb::GetSelfUserStatusRequest::default().encode_to_vec();
            let resp_bytes = invoke_proto_rpc(
                &http,
                &jar,
                &xsrf,
                &guard,
                DEFAULT_MACOS_SAFARI_UA,
                &base_url,
                "get_self_user_status",
                &empty_req,
            )
            .await
            .expect("first RPC should succeed after 429 retry and base64 decode");

            let decoded = pb::GetSelfUserStatusResponse::decode(resp_bytes.as_slice())
                .expect("decode GetSelfUserStatusResponse");
            let user_id = decoded.user_status.unwrap().user_id.unwrap();
            assert_eq!(user_id.id.as_deref(), Some("112233445566778899001"));
            assert_eq!(mole_world_hits.load(Ordering::SeqCst), 1);

            let second_res = invoke_proto_rpc(
                &http,
                &jar,
                &xsrf,
                &guard,
                DEFAULT_MACOS_SAFARI_UA,
                &base_url,
                "get_self_user_status",
                &empty_req,
            )
            .await;
            assert!(
                second_res.is_ok(),
                "single 401 should refresh XSRF once and succeed on retry, got: {second_res:?}"
            );
            assert_eq!(mole_world_hits.load(Ordering::SeqCst), 2);

            let xsrf_a = Arc::clone(&xsrf);
            let xsrf_b = Arc::clone(&xsrf);
            let (r1, r2) = tokio::join!(
                xsrf_a.refresh_if_generation(2),
                xsrf_b.refresh_if_generation(2)
            );
            assert_eq!(r1.unwrap().1, 3);
            assert_eq!(r2.unwrap().1, 3);
            assert_eq!(
                mole_world_hits.load(Ordering::SeqCst),
                3,
                "concurrent refresh_if_generation for the same failed generation must single-flight"
            );

            let third_res = invoke_proto_rpc(
                &http,
                &jar,
                &xsrf,
                &guard,
                DEFAULT_MACOS_SAFARI_UA,
                &base_url,
                "get_self_user_status",
                &empty_req,
            )
            .await;
            assert!(
                matches!(third_res, Err(GChatError::AuthExpired(_))),
                "expected AuthExpired after repeated 401, got: {third_res:?}"
            );
            assert_eq!(mole_world_hits.load(Ordering::SeqCst), 4);

            server_handle.abort();
        }

        #[tokio::test]
        async fn test_non_idempotent_rpcs_never_retry_on_5xx_while_idempotent_reads_retry() {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let base_url = Url::parse(&format!("http://127.0.0.1:{}/", addr.port())).unwrap();

            let create_topic_hits = Arc::new(AtomicUsize::new(0));
            let create_message_hits = Arc::new(AtomicUsize::new(0));
            let create_dm_hits = Arc::new(AtomicUsize::new(0));
            let paginated_world_hits = Arc::new(AtomicUsize::new(0));

            let ct_srv = Arc::clone(&create_topic_hits);
            let cm_srv = Arc::clone(&create_message_hits);
            let cd_srv = Arc::clone(&create_dm_hits);
            let pw_srv = Arc::clone(&paginated_world_hits);

            let server_handle = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    let ct = Arc::clone(&ct_srv);
                    let cm = Arc::clone(&cm_srv);
                    let cd = Arc::clone(&cd_srv);
                    let pw = Arc::clone(&pw_srv);
                    tokio::spawn(async move {
                        let mut buf = vec![0u8; 8192];
                        let mut total = 0usize;
                        loop {
                            let n = stream.read(&mut buf[total..]).await.unwrap_or(0);
                            if n == 0 {
                                return;
                            }
                            total += n;
                            if buf[..total].windows(4).any(|w| w == b"\r\n\r\n") {
                                break;
                            }
                        }
                        let headers_str = String::from_utf8_lossy(&buf[..total]).to_string();
                        let first_line = headers_str.lines().next().unwrap_or("");
                        if first_line.starts_with("GET /u/0/mole/world") {
                            let html = r#"<html><script>{"xsrf_token":"AF1QipP_tok:1710000000000"}</script></html>"#;
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                html.len(),
                                html
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                            return;
                        }
                        if first_line.starts_with("POST /u/0/api/create_topic?") {
                            ct.fetch_add(1, Ordering::SeqCst);
                            let _ = stream
                                .write_all(b"HTTP/1.1 503 Service Unavailable\r\nRetry-After: 0\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                .await;
                            return;
                        }
                        if first_line.starts_with("POST /u/0/api/create_message?") {
                            cm.fetch_add(1, Ordering::SeqCst);
                            let _ = stream
                                .write_all(b"HTTP/1.1 502 Bad Gateway\r\nRetry-After: 0\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                .await;
                            return;
                        }
                        if first_line.starts_with("POST /u/0/api/create_dm?") {
                            cd.fetch_add(1, Ordering::SeqCst);
                            let _ = stream
                                .write_all(b"HTTP/1.1 504 Gateway Timeout\r\nRetry-After: 0\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                .await;
                            return;
                        }
                        if first_line.starts_with("POST /u/0/api/paginated_world?") {
                            let n = pw.fetch_add(1, Ordering::SeqCst) + 1;
                            if n == 1 {
                                let _ = stream
                                    .write_all(b"HTTP/1.1 503 Service Unavailable\r\nRetry-After: 0\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                    .await;
                            } else {
                                let _ = stream
                                    .write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/x-protobuf\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                    .await;
                            }
                        }
                    });
                }
            });

            let jar = test_cookie_jar();
            let guard = NetGuard::allow_loopback_for_test();
            let http = guard.build_http_client().unwrap();
            let xsrf = Arc::new(XsrfTokenManager::new(
                http.clone(),
                jar.clone(),
                base_url.clone(),
                DEFAULT_MACOS_SAFARI_UA.to_string(),
                guard.clone(),
            ));

            for ep in ["create_topic", "create_message", "create_dm"] {
                let res = invoke_proto_rpc(
                    &http,
                    &jar,
                    &xsrf,
                    &guard,
                    DEFAULT_MACOS_SAFARI_UA,
                    &base_url,
                    ep,
                    &[],
                )
                .await;
                assert!(
                    matches!(res, Err(GChatError::HttpStatus(502..=504, _))),
                    "non-idempotent {ep} must fail immediately on 5xx, got: {res:?}"
                );
            }
            assert_eq!(create_topic_hits.load(Ordering::SeqCst), 1, "create_topic must not retry on 503");
            assert_eq!(create_message_hits.load(Ordering::SeqCst), 1, "create_message must not retry on 502");
            assert_eq!(create_dm_hits.load(Ordering::SeqCst), 1, "create_dm must not retry on 504");

            let pw_res = invoke_proto_rpc(
                &http,
                &jar,
                &xsrf,
                &guard,
                DEFAULT_MACOS_SAFARI_UA,
                &base_url,
                "paginated_world",
                &[],
            )
            .await;
            assert!(pw_res.is_ok(), "idempotent paginated_world must retry on 503 and succeed");
            assert_eq!(paginated_world_hits.load(Ordering::SeqCst), 2);

            server_handle.abort();
        }
    }

    #[test]
    fn test_prepend_request_header_does_not_duplicate_when_already_present() {
        let existing = pb::GetSelfUserStatusRequest {
            request_header: Some(pb::RequestHeader {
                trace_id: Some(777),
                client_type: Some(pb::request_header::ClientType::Web as i32),
                client_version: Some(CLIENT_VERSION),
                locale: Some("en".to_string()),
                ..Default::default()
            }),
        }
        .encode_to_vec();
        let out = prepend_request_header("get_self_user_status", &existing);
        assert_eq!(
            out, existing,
            "prepend_request_header must not prepend a second RequestHeader when field 100 is already present"
        );
    }

    #[test]
    fn test_retry_after_clamped_to_60_seconds_per_spec() {
        assert_eq!(parse_retry_after_clamped("0"), Some(Duration::from_secs(0)));
        assert_eq!(
            parse_retry_after_clamped("45"),
            Some(Duration::from_secs(45))
        );
        assert_eq!(
            parse_retry_after_clamped("60"),
            Some(Duration::from_secs(60))
        );
        assert_eq!(
            parse_retry_after_clamped("120"),
            Some(Duration::from_secs(60))
        );
    }

    #[test]
    fn test_backoff_delay_includes_25_percent_jitter_bounds() {
        for attempt in 1..=3 {
            let base_ms = 1000u64 << (attempt - 1);
            let min_ms = (base_ms * 750) / 1000;
            let max_ms = (base_ms * 1250) / 1000;
            for _ in 0..32 {
                let d = compute_backoff_delay(attempt).as_millis() as u64;
                assert!(
                    (min_ms..=max_ms).contains(&d),
                    "attempt {attempt} delay {d}ms outside [{min_ms}, {max_ms}]"
                );
            }
        }
    }

    #[test]
    fn test_rpc_url_carries_counter_rt_alt_and_key() {
        let base = Url::parse("https://chat.google.com/").unwrap();
        let url = rpc_url(&base, "get_self_user_status", 1).unwrap();

        assert_eq!(url.path(), "/u/0/api/get_self_user_status");
        let query: std::collections::HashMap<String, String> =
            url.query_pairs().into_owned().collect();
        assert_eq!(query.get("c").map(String::as_str), Some("1"));
        assert_eq!(query.get("rt").map(String::as_str), Some("b"));
        assert_eq!(query.get("alt").map(String::as_str), Some("proto"));
        assert_eq!(query.get("key").map(String::as_str), Some(API_KEY));
        assert_eq!(query.len(), 4);
    }
}
