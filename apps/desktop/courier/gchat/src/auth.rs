// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::cookies::DomainCookieJar;
use crate::netguard::NetGuard;
use crate::GChatError;
use reqwest::Client;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use url::Url;

const XSRF_TTL: Duration = Duration::from_secs(24 * 60 * 60);

pub fn extract_xsrf_token_from_mole_world_html(html: &str) -> Result<String, GChatError> {
    if html.contains("accounts.google.com/ServiceLogin")
        || html.contains("\"qwAQke\":\"AccountsSignInUi\"")
    {
        return Err(GChatError::AuthExpired(
            "session redirected to Google sign-in".to_string(),
        ));
    }

    for marker in ["\"xsrf_token\":\"", "\"SMqcke\":\""] {
        if let Some(start_idx) = html.find(marker) {
            let value_start = start_idx + marker.len();
            let rest = &html[value_start..];
            if let Some(end_idx) = rest.find('"') {
                let candidate = &rest[..end_idx];
                if !candidate.is_empty()
                    && !candidate
                        .chars()
                        .any(|c| (c as u32) < 0x20 || (c as u32) == 0x7f)
                {
                    return Ok(candidate.to_string());
                }
            }
        }
    }

    Err(GChatError::AuthExpired(
        "xsrf_token not found in /u/0/mole/world HTML".to_string(),
    ))
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
        self.guard.validate_url(&url, false).await?;

        let mut req = self
            .http
            .get(url.clone())
            .timeout(Duration::from_secs(15))
            .header("User-Agent", &self.user_agent)
            .header("authority", "chat.google.com")
            .header("Referer", "https://mail.google.com/");

        if let Some(cookie_hdr) = self
            .jar
            .cookie_header_for_request(&url, self.guard.is_loopback_test_allowed())
        {
            req = req.header("Cookie", cookie_hdr);
        }

        let resp = req
            .send()
            .await
            .map_err(|e| GChatError::Network(format!("GET /u/0/mole/world failed: {e}")))?;

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

        let html = resp
            .text()
            .await
            .map_err(|e| GChatError::Network(format!("reading /u/0/mole/world body: {e}")))?;
        extract_xsrf_token_from_mole_world_html(&html)
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
