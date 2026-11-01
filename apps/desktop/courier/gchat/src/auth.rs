// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::cookies::DomainCookieJar;
use crate::netguard::NetGuard;
use crate::GChatError;
use reqwest::Client;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use url::Url;

pub const XSRF_TTL: Duration = Duration::from_secs(24 * 60 * 60);
pub const MAX_MOLE_WORLD_BYTES: usize = 2 * 1024 * 1024;

fn validate_token_candidate(candidate: &str) -> Option<String> {
    let trimmed = candidate.trim();
    if !trimmed.is_empty()
        && !trimmed
            .chars()
            .any(|c| (c as u32) < 0x20 || (c as u32) == 0x7f)
    {
        Some(trimmed.to_string())
    } else {
        None
    }
}

fn extract_json_value_after_key(html: &str, key_literal: &str) -> Option<String> {
    let mut search_from = 0usize;
    while let Some(rel_idx) = html[search_from..].find(key_literal) {
        let after_key = search_from + rel_idx + key_literal.len();
        search_from = after_key;
        let rest = html[after_key..].trim_start();
        let Some(after_colon) = rest.strip_prefix(':') else {
            continue;
        };
        let val_rest = after_colon.trim_start();
        if let Some(after_quote) = val_rest.strip_prefix('"') {
            if let Some(end_quote) = after_quote.find('"') {
                if let Some(tok) = validate_token_candidate(&after_quote[..end_quote]) {
                    return Some(tok);
                }
            }
        } else if val_rest.starts_with('[') {
            if let Some(end_bracket) = val_rest.find(']') {
                let arr_slice = &val_rest[..=end_bracket];
                if let Ok(serde_json::Value::Array(items)) =
                    serde_json::from_str::<serde_json::Value>(arr_slice)
                {
                    for item in items.iter().rev() {
                        if let Some(s) = item.as_str() {
                            if let Some(tok) = validate_token_candidate(s) {
                                return Some(tok);
                            }
                        }
                    }
                }
            }
        }
    }
    None
}

pub fn extract_xsrf_token_from_mole_world_html(html: &str) -> Result<String, GChatError> {
    if html.contains("accounts.google.com/ServiceLogin") {
        return Err(GChatError::AuthExpired(
            "session redirected to Google sign-in".to_string(),
        ));
    }
    if let Some(qw) = extract_json_value_after_key(html, "\"qwAQke\"") {
        if qw == "AccountsSignInUi" {
            return Err(GChatError::AuthExpired(
                "session redirected to Google sign-in (AccountsSignInUi)".to_string(),
            ));
        }
    }

    for marker in ["\"xsrf_token\"", "\"SMqcke\""] {
        if let Some(tok) = extract_json_value_after_key(html, marker) {
            return Ok(tok);
        }
    }

    Err(GChatError::Network(
        "xsrf_token not found in /u/0/mole/world HTML".to_string(),
    ))
}

pub(crate) fn map_reqwest_error(context: &str, err: reqwest::Error) -> GChatError {
    let msg = format!("{err:?}");
    if msg.contains("SsrfBlocked") || err.to_string().contains("blocked by network guard") {
        return GChatError::SsrfBlocked(format!("{context}: {err}"));
    }
    GChatError::Network(format!("{context}: {err}"))
}

/// The `hs` query parameter the web client sends to `/u/0/mole/world` (spec §6, step 4).
const MOLE_WORLD_HS: &str = r#"["h_hs",null,null,[1,0],null,null,"gmail.pinto-server_20230730.06_p0",1,null,[15,38,36,35,26,30,41,18,24,11,21,14,6],null,null,"3Mu86PSulM4.en..es5",0,null,null,[0]]"#;

/// `/u/0/mole/world` with the query the web client sends. Google answers HTTP 400 without it.
fn mole_world_url(base_url: &Url) -> Result<Url, GChatError> {
    let mut url = base_url
        .join("/u/0/mole/world")
        .map_err(|e| GChatError::Internal(format!("invalid mole/world URL: {e}")))?;
    url.query_pairs_mut()
        .append_pair("origin", "https://mail.google.com")
        .append_pair("shell", "9")
        .append_pair("hl", "en")
        .append_pair("wfi", "gtn-roster-iframe-id")
        .append_pair("hs", MOLE_WORLD_HS);
    Ok(url)
}

/// The `/u/0/mole/world` GET with the web client's headers, `refer` misspelled as it sends it.
fn mole_world_request(
    http: &Client,
    url: Url,
    user_agent: &str,
    cookie_hdr: Option<String>,
) -> reqwest::RequestBuilder {
    let mut req = http
        .get(url)
        .timeout(Duration::from_secs(15))
        .header("User-Agent", user_agent)
        .header("authority", "chat.google.com")
        .header("refer", "https://mail.google.com/");
    if let Some(cookie_hdr) = cookie_hdr {
        req = req.header("Cookie", cookie_hdr);
    }
    req
}

struct XsrfState {
    token: Option<String>,
    fetched_at: Option<Instant>,
    generation: u64,
}

pub struct XsrfTokenManager {
    http: Client,
    jar: DomainCookieJar,
    base_url: Url,
    user_agent: String,
    guard: NetGuard,
    state: Mutex<XsrfState>,
}

crate::edition2021! {
    pub(crate) async fn read_bounded_bytes(
        mut resp: reqwest::Response,
        max_bytes: usize,
        label: &str,
    ) -> Result<Vec<u8>, GChatError> {
        if let Some(len) = resp.content_length() {
            if len > max_bytes as u64 {
                return Err(GChatError::Network(format!(
                    "{label} response content-length ({len} bytes) exceeds limit ({max_bytes} bytes)"
                )));
            }
        }
        let mut buf = Vec::new();
        while let Some(chunk) = resp
            .chunk()
            .await
            .map_err(|e| GChatError::Network(format!("reading {label} body: {e}")))?
        {
            if buf.len().saturating_add(chunk.len()) > max_bytes {
                return Err(GChatError::Network(format!(
                    "{label} response body exceeded limit ({max_bytes} bytes)"
                )));
            }
            buf.extend_from_slice(&chunk);
        }
        Ok(buf)
    }

    impl XsrfTokenManager {
        pub fn new(
            http: Client,
            jar: DomainCookieJar,
            base_url: Url,
            user_agent: String,
            guard: NetGuard,
        ) -> Self {
            Self {
                http,
                jar,
                base_url,
                user_agent,
                guard,
                state: Mutex::new(XsrfState {
                    token: None,
                    fetched_at: None,
                    generation: 0,
                }),
            }
        }

        pub fn start_background_refresh(self: &Arc<Self>) -> tokio::task::JoinHandle<()> {
            let mgr = Arc::clone(self);
            tokio::spawn(async move {
                let start = tokio::time::Instant::now() + XSRF_TTL;
                let mut interval = tokio::time::interval_at(start, XSRF_TTL);
                loop {
                    interval.tick().await;
                    let current_gen = {
                        let guard = mgr.state.lock().await;
                        guard.generation
                    };
                    let _ = mgr.refresh_if_generation(current_gen).await;
                }
            })
        }

        pub async fn get_token(&self) -> Result<(String, u64), GChatError> {
            let mut guard = self.state.lock().await;
            if let (Some(token), Some(fetched_at)) = (&guard.token, guard.fetched_at) {
                if fetched_at.elapsed() < XSRF_TTL {
                    return Ok((token.clone(), guard.generation));
                }
            }
            let token = self.fetch_mole_world().await?;
            guard.generation += 1;
            guard.token = Some(token.clone());
            guard.fetched_at = Some(Instant::now());
            Ok((token, guard.generation))
        }

        pub async fn refresh_if_generation(
            &self,
            failed_generation: u64,
        ) -> Result<(String, u64), GChatError> {
            let mut guard = self.state.lock().await;
            if guard.generation > failed_generation {
                if let Some(token) = &guard.token {
                    return Ok((token.clone(), guard.generation));
                }
            }
            let token = self.fetch_mole_world().await?;
            guard.generation += 1;
            guard.token = Some(token.clone());
            guard.fetched_at = Some(Instant::now());
            Ok((token, guard.generation))
        }

        async fn fetch_mole_world(&self) -> Result<String, GChatError> {
            let url = mole_world_url(&self.base_url)?;
            self.guard.validate_host_and_scheme(&url, false)?;
            let cookie_hdr = self.jar.cookie_header_for_request(&url);
            let req = mole_world_request(&self.http, url, &self.user_agent, cookie_hdr);

            let resp = req
                .send()
                .await
                .map_err(|e| map_reqwest_error("GET /u/0/mole/world failed", e))?;

            let status = resp.status();
            if status.is_redirection() {
                if let Some(loc) = resp.headers().get(reqwest::header::LOCATION) {
                    let loc_str = loc.to_str().unwrap_or("");
                    if loc_str.contains("accounts.google.com") || loc_str.contains("ServiceLogin") {
                        return Err(GChatError::AuthExpired(
                            "redirected to accounts.google.com/ServiceLogin".to_string(),
                        ));
                    }
                }
                return Err(GChatError::HttpStatus(
                    status.as_u16(),
                    format!("unexpected redirect from /u/0/mole/world: {status}"),
                ));
            }
            if !status.is_success() {
                return Err(GChatError::HttpStatus(
                    status.as_u16(),
                    "GET /u/0/mole/world failed".to_string(),
                ));
            }

            let body_bytes = read_bounded_bytes(resp, MAX_MOLE_WORLD_BYTES, "/u/0/mole/world").await?;
            let html = String::from_utf8_lossy(&body_bytes);
            extract_xsrf_token_from_mole_world_html(&html)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_xsrf_token_from_mole_world_html() {
        let html = r#"<!DOCTYPE html><html><head><script nonce="abc">window.WIZ_global_data = {"FdrFJe":"123","xsrf_token":"AF1QipP_synthetic_token:1710000000000","cfb2h":"boq"};</script></head><body></body></html>"#;
        let token = extract_xsrf_token_from_mole_world_html(html)
            .expect("should extract synthetic xsrf_token");
        assert_eq!(token, "AF1QipP_synthetic_token:1710000000000");

        let wiz_html = r#"<script>window.WIZ_global_data = {"SMqcke":"AF1QipP_wiz_token:1710000000000"};</script>"#;
        assert_eq!(
            extract_xsrf_token_from_mole_world_html(wiz_html).unwrap(),
            "AF1QipP_wiz_token:1710000000000"
        );

        let spaced_html = r#"<script>window.WIZ_global_data = { "xsrf_token" : "AF1QipP_spaced_token:1710000000000" };</script>"#;
        assert_eq!(
            extract_xsrf_token_from_mole_world_html(spaced_html)
                .expect("should tolerate whitespace around colon"),
            "AF1QipP_spaced_token:1710000000000"
        );

        let array_html = r#"<script>window.WIZ_global_data = {"SMqcke": [null, null, "AF1QipP_array_token:1710000000000"]};</script>"#;
        assert_eq!(
            extract_xsrf_token_from_mole_world_html(array_html)
                .expect("should extract token from array form"),
            "AF1QipP_array_token:1710000000000"
        );

        let login_html =
            r#"<html><body>Redirecting to https://accounts.google.com/ServiceLogin</body></html>"#;
        assert!(matches!(
            extract_xsrf_token_from_mole_world_html(login_html),
            Err(GChatError::AuthExpired(_))
        ));

        let sign_in_ui_html = r#"<script>window.WIZ_global_data = {"qwAQke":"AccountsSignInUi"};</script>"#;
        assert!(matches!(
            extract_xsrf_token_from_mole_world_html(sign_in_ui_html),
            Err(GChatError::AuthExpired(_))
        ));

        let empty_html = r#"<html><body>No token here</body></html>"#;
        assert!(matches!(
            extract_xsrf_token_from_mole_world_html(empty_html),
            Err(GChatError::Network(_))
        ));
    }

    crate::edition2021! {
        #[tokio::test]
        async fn test_fetch_mole_world_only_treats_signed_out_responses_as_auth_expired() {
            use crate::cookies::ScopedCookie;
            use std::sync::atomic::{AtomicUsize, Ordering};
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            use tokio::net::TcpListener;

            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let base_url = Url::parse(&format!("http://127.0.0.1:{}/", addr.port())).unwrap();
            let step = Arc::new(AtomicUsize::new(0));
            let step_srv = Arc::clone(&step);

            let server_handle = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    let step = Arc::clone(&step_srv);
                    tokio::spawn(async move {
                        let mut buf = [0u8; 4096];
                        let _ = stream.read(&mut buf).await;
                        let n = step.fetch_add(1, Ordering::SeqCst) + 1;
                        let resp = match n {
                            1 => "HTTP/1.1 302 Found\r\nLocation: https://accounts.google.com/ServiceLogin\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                            2 => "HTTP/1.1 302 Found\r\nLocation: https://chat.google.com/u/0/\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                            3 => "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                            4 => "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                            _ => "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                        };
                        let _ = stream.write_all(resp.as_bytes()).await;
                    });
                }
            });

            let jar = DomainCookieJar::from_scoped_cookies(vec![
                ScopedCookie { name: "COMPASS".into(), value: "c1".into(), domain: "chat.google.com".into(), path: "/".into() },
                ScopedCookie { name: "OSID".into(), value: "o1".into(), domain: "chat.google.com".into(), path: "/".into() },
                ScopedCookie { name: "SID".into(), value: "s1".into(), domain: ".google.com".into(), path: "/".into() },
                ScopedCookie { name: "HSID".into(), value: "h1".into(), domain: ".google.com".into(), path: "/".into() },
                ScopedCookie { name: "SSID".into(), value: "ss1".into(), domain: ".google.com".into(), path: "/".into() },
            ])
            .unwrap()
            .with_loopback_for_test(true);

            let guard = NetGuard::allow_loopback_for_test();
            let http = guard.build_http_client().unwrap();
            let mgr = XsrfTokenManager::new(http, jar, base_url, "UA".to_string(), guard);

            assert!(matches!(mgr.get_token().await, Err(GChatError::AuthExpired(_))));
            assert!(matches!(mgr.get_token().await, Err(GChatError::HttpStatus(302, _))));
            assert!(matches!(mgr.get_token().await, Err(GChatError::HttpStatus(401, _))));
            assert!(matches!(mgr.get_token().await, Err(GChatError::HttpStatus(403, _))));

            server_handle.abort();
        }
    }
    #[test]
    fn test_mole_world_request_carries_the_web_clients_query_and_headers() {
        let base = Url::parse("https://chat.google.com/").unwrap();
        let req = mole_world_request(
            &Client::new(),
            mole_world_url(&base).unwrap(),
            "UA",
            Some("SID=x".to_string()),
        )
        .build()
        .unwrap();

        assert_eq!(req.url().path(), "/u/0/mole/world");
        let query: std::collections::HashMap<String, String> =
            req.url().query_pairs().into_owned().collect();
        assert_eq!(query.get("origin").map(String::as_str), Some("https://mail.google.com"));
        assert_eq!(query.get("shell").map(String::as_str), Some("9"));
        assert_eq!(query.get("hl").map(String::as_str), Some("en"));
        assert_eq!(query.get("wfi").map(String::as_str), Some("gtn-roster-iframe-id"));
        assert_eq!(query.get("hs").map(String::as_str), Some(MOLE_WORLD_HS));
        assert_eq!(query.len(), 5);

        let headers = req.headers();
        assert_eq!(headers.get("authority").unwrap(), "chat.google.com");
        assert_eq!(headers.get("refer").unwrap(), "https://mail.google.com/");
        assert!(headers.get("referer").is_none());
        assert_eq!(headers.get("cookie").unwrap(), "SID=x");
        assert_eq!(headers.get("user-agent").unwrap(), "UA");
    }
}
