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

    Err(GChatError::AuthExpired(
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
            let url = self
                .base_url
                .join("/u/0/mole/world")
                .map_err(|e| GChatError::Internal(format!("invalid mole/world URL: {e}")))?;
            self.guard.validate_host_and_scheme(&url, false)?;

            let mut req = self
                .http
                .get(url.clone())
                .timeout(Duration::from_secs(15))
                .header("User-Agent", &self.user_agent)
                .header("authority", "chat.google.com")
                .header("Referer", "https://mail.google.com/");

            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header("Cookie", cookie_hdr);
            }

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
                return Err(GChatError::AuthExpired(format!(
                    "unexpected redirect from /u/0/mole/world: {status}"
                )));
            }
            if status.as_u16() == 401 || status.as_u16() == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "/u/0/mole/world returned HTTP {}",
                    status.as_u16()
                )));
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

        let empty_html = r#"<html><body>No token here</body></html>"#;
        assert!(matches!(
            extract_xsrf_token_from_mole_world_html(empty_html),
            Err(GChatError::AuthExpired(_))
        ));
    }
}
