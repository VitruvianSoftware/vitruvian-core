// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::auth::XsrfTokenManager;
use crate::cookies::DomainCookieJar;
use crate::netguard::NetGuard;
use crate::pb;
use crate::GChatError;
use base64::Engine;
use prost::Message;
use reqwest::Client;
use std::sync::atomic::{AtomicI64, Ordering};
use std::time::Duration;
use url::Url;

static TRACE_COUNTER: AtomicI64 = AtomicI64::new(1);

pub const CLIENT_VERSION: i64 = 2440378181258;

pub const SUPPORTED_CAPABILITIES: &[(i32, i32)] = &[
    (
        4,
        pb::client_feature_capabilities::CapabilityLevel::FullySupported as i32,
    ),
    (
        5,
        pb::client_feature_capabilities::CapabilityLevel::FullySupported as i32,
    ),
    (
        6,
        pb::client_feature_capabilities::CapabilityLevel::FullySupported as i32,
    ),
    (
        7,
        pb::client_feature_capabilities::CapabilityLevel::FullySupported as i32,
    ),
];

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

fn strip_ascii_whitespace(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .copied()
        .filter(|b| !b.is_ascii_whitespace())
        .collect()
}

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
    let rel_path = format!("/u/0/api/{endpoint}?alt=proto");
    let url = base_url
        .join(&rel_path)
        .map_err(|e| GChatError::Internal(format!("invalid RPC URL for {endpoint}: {e}")))?;
    guard.validate_url(&url, false).await?;

    let payload = prepend_request_header(endpoint, req_bytes);
    let mut refreshed_xsrf = false;
    let mut rate_limit_attempt = 0u32;

    loop {
        let (xsrf_token, xsrf_gen) = xsrf.get_token().await?;

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

        if let Some(cookie_hdr) =
            jar.cookie_header_for_request(&url, guard.is_loopback_test_allowed())
        {
            req = req.header("Cookie", cookie_hdr);
        }

        let resp = req
            .send()
            .await
            .map_err(|e| GChatError::Network(format!("RPC {endpoint} failed: {e}")))?;

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

        if status.as_u16() == 429 || matches!(status.as_u16(), 502 | 503 | 504) {
            rate_limit_attempt += 1;
            if rate_limit_attempt >= 3 {
                if status.as_u16() == 429 {
                    return Err(GChatError::RateLimited);
                }
                return Err(GChatError::HttpStatus(
                    status.as_u16(),
                    format!("RPC {endpoint} failed after {rate_limit_attempt} attempts"),
                ));
            }
            let delay = resp
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.trim().parse::<u64>().ok())
                .map(|secs| Duration::from_secs(secs.min(30)))
                .unwrap_or_else(|| {
                    let base_ms = 1000u64 << (rate_limit_attempt - 1);
                    Duration::from_millis(base_ms)
                });
            if !delay.is_zero() {
                tokio::time::sleep(delay).await;
            }
            continue;
        }

        if !status.is_success() {
            let body_text = resp.text().await.unwrap_or_default();
            if body_text.contains("\"invalid_grant\"") {
                return Err(GChatError::AuthExpired(
                    "Google returned invalid_grant".to_string(),
                ));
            }
            return Err(GChatError::HttpStatus(status.as_u16(), body_text));
        }

        let is_base64_header = resp
            .headers()
            .get("x-goog-safety-encoding")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.eq_ignore_ascii_case("base64"))
            .unwrap_or(false);

        let raw_bytes = resp
            .bytes()
            .await
            .map_err(|e| GChatError::Network(format!("reading RPC {endpoint} body: {e}")))?
            .to_vec();

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
    }

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

                    if first_line.starts_with("POST /u/0/api/get_self_user_status?alt=proto") {
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
                                let resp = format!(
                                    "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Goog-Safety-Encoding: base64\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                    b64.len(),
                                    b64
                                );
                                let _ = stream.write_all(resp.as_bytes()).await;
                            }
                            3 => {
                                let resp = "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                                let _ = stream.write_all(resp.as_bytes()).await;
                            }
                            4 => {
                                assert!(lower_headers.contains(
                                    "x-framework-xsrf-token: af1qipp_token_gen_2:1710000000000"
                                ));
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
        let http = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap();
        let xsrf = XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            DEFAULT_MACOS_SAFARI_UA.to_string(),
            guard.clone(),
        );

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
            matches!(second_res, Err(GChatError::AuthExpired(_))),
            "expected AuthExpired on repeated 401, got: {second_res:?}"
        );
        assert_eq!(mole_world_hits.load(Ordering::SeqCst), 2);

        server_handle.abort();
    }
}
