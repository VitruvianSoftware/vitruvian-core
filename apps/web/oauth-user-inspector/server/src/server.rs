// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use crate::api_endpoints::resolve_explore_target;
use crate::logger::{
    create_logger, create_request_logger, log_error, log_timing, now_epoch_ms, Logger,
};
use crate::oauth_error_guide::enhance_oauth_error;
use crate::rate_limit::{client_ip, RateLimitTier, RateLimiter};
use crate::safe_fetch::{
    safe_fetch, ParsedUrl, SafeFetchOptions, SafeFetchResponse, UpstreamError,
};
use crate::security_headers::default_security_headers;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const SECRET_CACHE_TTL_MS: u64 = 60_000;
pub const MAX_JSON_BODY_BYTES: usize = 64 * 1024;
pub const DEFAULT_ZITADEL_DOMAIN: &str = "auth.ipv1337.dev";

pub const SUPPORTED_PROVIDERS: &[&str] =
    &["github", "google", "gitlab", "auth0", "zitadel", "linkedin"];

/// Trait abstracting Google Cloud Secret Manager lookups so unit tests can
/// inject deterministic mocks and verify secret names / caching behavior.
pub trait SecretBackend: Send + Sync {
    fn access_secret_version(&self, name: &str) -> Result<Option<String>, String>;
}

pub struct DefaultSecretBackend;

fn fetch_metadata_access_token() -> Result<String, String> {
    let output = std::process::Command::new("curl")
        .args([
            "-sS",
            "-f",
            "--max-time",
            "5",
            "-H",
            "Metadata-Flavor: Google",
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        ])
        .output()
        .map_err(|e| format!("Failed to query GCE metadata server: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "Metadata server token request failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    let json_val: Value = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("Invalid metadata token JSON: {e}"))?;
    json_val
        .get("access_token")
        .and_then(Value::as_str)
        .map(|s| s.to_string())
        .ok_or_else(|| "Missing access_token in metadata response".to_string())
}

impl SecretBackend for DefaultSecretBackend {
    fn access_secret_version(&self, name: &str) -> Result<Option<String>, String> {
        let token = match std::env::var("GOOGLE_OAUTH_ACCESS_TOKEN") {
            Ok(t) if !t.trim().is_empty() => t.trim().to_string(),
            _ => fetch_metadata_access_token()?,
        };

        let url = format!("https://secretmanager.googleapis.com/v1/{name}:access");
        let output = std::process::Command::new("curl")
            .args([
                "-sS",
                "-f",
                "--max-time",
                "10",
                "-H",
                &format!("Authorization: Bearer {token}"),
                &url,
            ])
            .output()
            .map_err(|e| format!("Failed to invoke curl for Secret Manager: {e}"))?;

        if !output.status.success() {
            return Err(format!(
                "Secret Manager request failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ));
        }

        let json_val: Value = serde_json::from_slice(&output.stdout)
            .map_err(|e| format!("Invalid Secret Manager JSON response: {e}"))?;
        let Some(data_b64) = json_val
            .get("payload")
            .and_then(|p| p.get("data"))
            .and_then(Value::as_str)
        else {
            return Ok(None);
        };
        let decoded = base64_decode(data_b64)
            .ok_or_else(|| "Failed to decode base64 secret payload".to_string())?;
        let secret_str = String::from_utf8(decoded)
            .map_err(|e| format!("Secret payload is not valid UTF-8: {e}"))?;
        Ok(Some(secret_str))
    }
}

/// Trait abstracting outbound `safeFetch` calls so server tests can mock
/// provider responses or verify that SSRF/validation failures never reach the network.
pub trait HttpFetcher: Send + Sync {
    fn fetch(&self, url: &str, opts: &SafeFetchOptions)
        -> Result<SafeFetchResponse, UpstreamError>;
}

pub struct ProductionHttpFetcher;

impl HttpFetcher for ProductionHttpFetcher {
    fn fetch(
        &self,
        url: &str,
        opts: &SafeFetchOptions,
    ) -> Result<SafeFetchResponse, UpstreamError> {
        safe_fetch(url, opts)
    }
}

#[derive(Debug, Clone)]
struct SecretCacheEntry {
    value: String,
    expires_at: u64,
}

#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub method: String,
    pub path: String,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
    pub remote_ip: Option<String>,
}

impl HttpRequest {
    pub fn new(method: impl Into<String>, path: impl Into<String>) -> Self {
        Self {
            method: method.into(),
            path: path.into(),
            headers: HashMap::new(),
            body: Vec::new(),
            remote_ip: Some("127.0.0.1".to_string()),
        }
    }

    pub fn with_header(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.headers
            .insert(key.into().to_ascii_lowercase(), value.into());
        self
    }

    pub fn with_json(mut self, val: Value) -> Self {
        self.headers
            .insert("content-type".to_string(), "application/json".to_string());
        self.body = val.to_string().into_bytes();
        self
    }

    pub fn with_raw_body(mut self, content_type: &str, body: impl Into<Vec<u8>>) -> Self {
        self.headers
            .insert("content-type".to_string(), content_type.to_string());
        self.body = body.into();
        self
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        let lower = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| k.to_ascii_lowercase() == lower)
            .map(|(_, v)| v.as_str())
    }
}

#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

impl HttpResponse {
    pub fn header(&self, name: &str) -> Option<&str> {
        let lower = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| k.to_ascii_lowercase() == lower)
            .map(|(_, v)| v.as_str())
    }

    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).to_string()
    }

    pub fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or(Value::Null)
    }
}

/// URL-encode a string using `application/x-www-form-urlencoded` rules (matching
/// WHATWG `URLSearchParams`).
pub fn urlencode_form_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'*' | b'-' | b'.' | b'_' => {
                out.push(b as char);
            }
            b' ' => out.push('+'),
            _ => {
                out.push_str(&format!("%{:02X}", b));
            }
        }
    }
    out
}

pub fn build_form_urlencoded(pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .map(|(k, v)| {
            format!(
                "{}={}",
                urlencode_form_component(k),
                urlencode_form_component(v)
            )
        })
        .collect::<Vec<_>>()
        .join("&")
}

/// URL-encode a string using RFC 3986 / JS `encodeURIComponent` rules.
pub fn encode_uri_component(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        match b {
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'-'
            | b'_'
            | b'.'
            | b'!'
            | b'~'
            | b'*'
            | b'\''
            | b'('
            | b')' => out.push(b as char),
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

/// Standard RFC 4648 Base64 encoder for HTTP Basic authentication headers.
pub fn base64_encode(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;

        out.push(TABLE[((triple >> 18) & 0x3f) as usize] as char);
        out.push(TABLE[((triple >> 12) & 0x3f) as usize] as char);
        if chunk.len() > 1 {
            out.push(TABLE[((triple >> 6) & 0x3f) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(TABLE[(triple & 0x3f) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

/// Standard RFC 4648 Base64 decoder (also accepts URL-safe `-` / `_` alphabet).
pub fn base64_decode(input: &str) -> Option<Vec<u8>> {
    fn val(b: u8) -> Option<u8> {
        match b {
            b'A'..=b'Z' => Some(b - b'A'),
            b'a'..=b'z' => Some(b - b'a' + 26),
            b'0'..=b'9' => Some(b - b'0' + 52),
            b'+' | b'-' => Some(62),
            b'/' | b'_' => Some(63),
            _ => None,
        }
    }
    let clean: Vec<u8> = input
        .bytes()
        .filter(|b| !b.is_ascii_whitespace() && *b != b'=')
        .collect();
    let mut out = Vec::with_capacity(clean.len() * 3 / 4);
    for chunk in clean.chunks(4) {
        if chunk.len() < 2 {
            return None;
        }
        let b0 = val(chunk[0])?;
        let b1 = val(chunk[1])?;
        out.push((b0 << 2) | (b1 >> 4));
        if chunk.len() >= 3 {
            let b2 = val(chunk[2])?;
            out.push((b1 << 4) | (b2 >> 2));
            if chunk.len() >= 4 {
                let b3 = val(chunk[3])?;
                out.push((b2 << 6) | b3);
            }
        }
    }
    Some(out)
}

/// Returns `true` if `path` matches common automated vulnerability-scanner probe
/// paths (`.env`, `.git`, `wp-admin`, `.php`, `.sql`, `.tar`, `.zip`, etc.).
///
/// Mirrors `PROBE_PATTERN`:
/// `/\.(php|asp|aspx|jsp|cgi|bak|zip|tar|gz|sql)(\/|$)|^\/(\.(env|git|svn|htaccess|htpasswd|DS_Store)|wp-admin|wp-login|wp-includes|phpmyadmin|cgi-bin|actuator|xmlrpc\.php|server-status|server-info)/i`
pub fn is_probe_path(raw_path: &str) -> bool {
    let path = raw_path.split('?').next().unwrap_or(raw_path);
    let lower = path.to_ascii_lowercase();

    const EXTENSIONS: &[&str] = &[
        ".php", ".asp", ".aspx", ".jsp", ".cgi", ".bak", ".zip", ".tar", ".gz", ".sql",
    ];
    for ext in EXTENSIONS {
        if lower.ends_with(ext) || lower.contains(&format!("{ext}/")) {
            return true;
        }
    }

    let trimmed = lower.strip_prefix('/').unwrap_or(&lower);
    const PREFIXES: &[&str] = &[
        ".env",
        ".git",
        ".svn",
        ".htaccess",
        ".htpasswd",
        ".ds_store",
        "wp-admin",
        "wp-login",
        "wp-includes",
        "phpmyadmin",
        "cgi-bin",
        "actuator",
        "xmlrpc.php",
        "server-status",
        "server-info",
    ];

    for prefix in PREFIXES {
        if trimmed.starts_with(prefix) {
            return true;
        }
    }
    false
}

struct RateLimiters {
    global_floor: RateLimiter,
    api_floor: RateLimiter,
    explore: RateLimiter,
    oauth_token: RateLimiter,
    oauth_hosted: RateLimiter,
}

impl RateLimiters {
    fn new(limit_override: Option<usize>) -> Self {
        Self {
            global_floor: RateLimiter::new(RateLimitTier::new(
                "global-floor",
                limit_override.unwrap_or(300),
                5 * 60_000,
            )),
            api_floor: RateLimiter::new(RateLimitTier::new(
                "api-floor",
                limit_override.unwrap_or(120),
                5 * 60_000,
            )),
            explore: RateLimiter::new(RateLimitTier::new(
                "explore",
                limit_override.unwrap_or(30),
                60_000,
            )),
            oauth_token: RateLimiter::new(RateLimitTier::new(
                "oauth-token",
                limit_override.unwrap_or(20),
                60_000,
            )),
            oauth_hosted: RateLimiter::new(RateLimitTier::new(
                "oauth-hosted",
                limit_override.unwrap_or(60),
                60_000,
            )),
        }
    }
}

pub struct App {
    pub logger: Logger,
    secret_backend: Arc<dyn SecretBackend>,
    http_fetcher: Arc<dyn HttpFetcher>,
    secret_cache: Mutex<HashMap<String, SecretCacheEntry>>,
    env_overrides: Mutex<HashMap<String, Option<String>>>,
    rate_limiters: Mutex<RateLimiters>,
    dist_dir: PathBuf,
    req_counter: Mutex<u64>,
}

impl Default for App {
    fn default() -> Self {
        Self::new()
    }
}

impl App {
    pub fn new() -> Self {
        Self {
            logger: create_logger(),
            secret_backend: Arc::new(DefaultSecretBackend),
            http_fetcher: Arc::new(ProductionHttpFetcher),
            secret_cache: Mutex::new(HashMap::new()),
            env_overrides: Mutex::new(HashMap::new()),
            rate_limiters: Mutex::new(RateLimiters::new(None)),
            dist_dir: PathBuf::from("dist"),
            req_counter: Mutex::new(0),
        }
    }

    pub fn with_backends(
        secret_backend: Arc<dyn SecretBackend>,
        http_fetcher: Arc<dyn HttpFetcher>,
    ) -> Self {
        Self {
            logger: create_logger(),
            secret_backend,
            http_fetcher,
            secret_cache: Mutex::new(HashMap::new()),
            env_overrides: Mutex::new(HashMap::new()),
            rate_limiters: Mutex::new(RateLimiters::new(None)),
            dist_dir: PathBuf::from("dist"),
            req_counter: Mutex::new(0),
        }
    }

    pub fn set_env(&self, key: impl Into<String>, value: Option<String>) {
        self.env_overrides.lock().unwrap().insert(key.into(), value);
    }

    pub fn get_env(&self, key: &str) -> Option<String> {
        if let Some(overridden) = self.env_overrides.lock().unwrap().get(key) {
            return overridden.clone();
        }
        std::env::var(key).ok()
    }

    pub fn clear_secret_cache(&self) {
        self.secret_cache.lock().unwrap().clear();
    }

    /// Retrieve a secret from Google Secret Manager (TTL-cached).
    /// `SECRET_PREFIX` (default `""`) is prepended to `secret_name` so co-tenant
    /// apps sharing one GCP project can namespace their secrets.
    pub fn get_secret(&self, secret_name: &str) -> Result<String, String> {
        let prefix = self.get_env("SECRET_PREFIX").unwrap_or_default();
        let full_name = format!("{prefix}{secret_name}");
        let now = now_epoch_ms();

        {
            let cache = self.secret_cache.lock().unwrap();
            if let Some(cached) = cache.get(&full_name) {
                if now < cached.expires_at {
                    return Ok(cached.value.clone());
                }
            }
        }

        let project_id = self
            .get_env("GOOGLE_CLOUD_PROJECT")
            .filter(|s| !s.is_empty())
            .or_else(|| self.get_env("GCP_PROJECT").filter(|s| !s.is_empty()))
            .ok_or_else(|| {
                "GOOGLE_CLOUD_PROJECT or GCP_PROJECT environment variable not set".to_string()
            })?;

        let name = format!("projects/{project_id}/secrets/{full_name}/versions/latest");
        match self.secret_backend.access_secret_version(&name) {
            Ok(Some(value)) if !value.is_empty() => {
                self.secret_cache.lock().unwrap().insert(
                    full_name,
                    SecretCacheEntry {
                        value: value.clone(),
                        expires_at: now + SECRET_CACHE_TTL_MS,
                    },
                );
                Ok(value)
            }
            Ok(_) => Err(format!("No payload data found for secret: {secret_name}")),
            Err(err) => Err(format!("Failed to retrieve secret {secret_name}: {err}")),
        }
    }

    pub fn resolve_zitadel_domain(&self, domain_from_body: Option<&str>) -> String {
        if let Some(d) = domain_from_body.filter(|s| !s.is_empty()) {
            return d.to_string();
        }
        if let Ok(secret_domain) = self.get_secret("ZITADEL_APP_OAUTH_DOMAIN") {
            if !secret_domain.is_empty() {
                return secret_domain;
            }
        }
        DEFAULT_ZITADEL_DOMAIN.to_string()
    }

    pub fn get_hosted_credentials(&self, provider: &str) -> Result<(String, String), String> {
        let (id_secret, sec_secret) = match provider {
            "github" => (
                "GITHUB_APP_OAUTH_CLIENT_ID",
                "GITHUB_APP_OAUTH_CLIENT_SECRET",
            ),
            "google" => (
                "GOOGLE_APP_OAUTH_CLIENT_ID",
                "GOOGLE_APP_OAUTH_CLIENT_SECRET",
            ),
            "gitlab" => (
                "GITLAB_APP_OAUTH_CLIENT_ID",
                "GITLAB_APP_OAUTH_CLIENT_SECRET",
            ),
            "auth0" => ("AUTH0_APP_OAUTH_CLIENT_ID", "AUTH0_APP_OAUTH_CLIENT_SECRET"),
            "zitadel" => (
                "ZITADEL_APP_OAUTH_CLIENT_ID",
                "ZITADEL_APP_OAUTH_CLIENT_SECRET",
            ),
            "linkedin" => (
                "LINKEDIN_APP_OAUTH_CLIENT_ID",
                "LINKEDIN_APP_OAUTH_CLIENT_SECRET",
            ),
            _ => return Err(format!("Unsupported provider: {provider}")),
        };
        let client_id = self.get_secret(id_secret)?;
        let client_secret = self.get_secret(sec_secret)?;
        Ok((client_id, client_secret))
    }

    fn validate_issuer_domain(&self, domain: &str) -> Result<(), UpstreamError> {
        let parsed = ParsedUrl::parse(&format!("https://{domain}/"))?;
        if parsed.protocol != "https:" || parsed.hostname.is_empty() {
            return Err(UpstreamError::new("Invalid issuer domain"));
        }
        Ok(())
    }

    fn collapse_upstream_error(&self, request_id: &str, err: &UpstreamError) -> HttpResponse {
        self.logger.warn(
            "Upstream request failed (collapsed)",
            Some(json!({
                "reason": err.reason,
                "requestId": request_id,
            })),
        );
        self.json_response(
            502,
            request_id,
            true,
            json!({
                "error": "Upstream request failed",
                "requestId": request_id,
            }),
        )
    }

    fn next_request_id(&self, incoming: Option<&str>) -> String {
        if let Some(id) = incoming.map(str::trim).filter(|s| !s.is_empty()) {
            return id.to_string();
        }
        let mut ctr = self.req_counter.lock().unwrap();
        *ctr += 1;
        format!("req-{}-{}", now_epoch_ms(), *ctr)
    }

    fn build_base_headers(&self, request_id: &str, is_api: bool) -> HashMap<String, String> {
        let mut headers = HashMap::new();
        for (k, v) in default_security_headers() {
            headers.insert(k, v);
        }
        headers.insert("X-Request-ID".to_string(), request_id.to_string());
        if is_api {
            headers.insert("Cache-Control".to_string(), "no-store".to_string());
        }
        headers
    }

    fn json_response(
        &self,
        status: u16,
        request_id: &str,
        is_api: bool,
        payload: Value,
    ) -> HttpResponse {
        let mut headers = self.build_base_headers(request_id, is_api);
        headers.insert(
            "Content-Type".to_string(),
            "application/json; charset=utf-8".to_string(),
        );
        HttpResponse {
            status,
            headers,
            body: payload.to_string().into_bytes(),
        }
    }

    fn check_rate_limit(
        &self,
        route_path: &str,
        ip: &str,
        request_id: &str,
    ) -> Option<HttpResponse> {
        let mut limiters = self.rate_limiters.lock().unwrap();
        let RateLimiters {
            global_floor,
            api_floor,
            explore,
            oauth_token,
            oauth_hosted,
        } = &mut *limiters;
        let is_api = route_path == "/api" || route_path.starts_with("/api/");

        let mut checks: Vec<&mut RateLimiter> = vec![global_floor];
        if is_api {
            checks.push(api_floor);
        }
        if route_path == "/api/explore" {
            checks.push(explore);
        } else if matches!(
            route_path,
            "/api/oauth/token" | "/api/oauth/refresh" | "/api/oauth/revoke"
        ) {
            checks.push(oauth_token);
        } else if route_path.starts_with("/api/oauth-hosted") {
            checks.push(oauth_hosted);
        }

        for limiter in checks {
            let result = limiter.hit(ip);
            if !result.allowed {
                let mut resp = self.json_response(
                    429,
                    request_id,
                    is_api,
                    json!({
                        "error": "Too many requests. Please slow down and try again shortly.",
                        "requestId": request_id,
                    }),
                );
                resp.headers.insert(
                    "Retry-After".to_string(),
                    result.retry_after_sec.to_string(),
                );
                return Some(resp);
            }
        }
        None
    }

    pub fn handle_request(&self, req: &HttpRequest) -> HttpResponse {
        let request_id = self.next_request_id(req.header("x-request-id"));
        let route_path = req.path.split('?').next().unwrap_or(&req.path);

        // 1. Scanner probe fast-drop (before body parsing or SPA fallback)
        if is_probe_path(route_path) {
            let mut headers = self.build_base_headers(&request_id, false);
            headers.insert("Content-Type".to_string(), "text/plain".to_string());
            return HttpResponse {
                status: 404,
                headers,
                body: b"Not Found".to_vec(),
            };
        }

        let is_api = route_path == "/api" || route_path.starts_with("/api/");

        // 2. Hard 64KB body cap
        if req.body.len() > MAX_JSON_BODY_BYTES {
            return self.json_response(
                413,
                &request_id,
                is_api,
                json!({
                    "error": "Request body too large.",
                    "requestId": request_id,
                }),
            );
        }

        // 3. Per-IP sliding-window rate limiting
        let effective_ip = client_ip(
            req.header("cf-connecting-ip"),
            req.remote_ip
                .as_deref()
                .or_else(|| req.header("x-forwarded-for")),
        );
        if let Some(rate_limited_resp) =
            self.check_rate_limit(route_path, &effective_ip, &request_id)
        {
            return rate_limited_resp;
        }

        // 4. Route dispatch
        match (req.method.as_str(), route_path) {
            ("GET", "/api/health") => self.json_response(
                200,
                &request_id,
                true,
                json!({
                    "status": "ok",
                    "uptime": 0.0,
                    "timestamp": now_epoch_ms(),
                    "node": "rust",
                }),
            ),
            ("POST", "/api/oauth/token") => self.handle_oauth_token(req, &request_id),
            ("POST", "/api/oauth/refresh") => self.handle_oauth_refresh(req, &request_id),
            ("POST", "/api/oauth/revoke") => self.handle_oauth_revoke(req, &request_id),
            ("POST", "/api/oauth-hosted/init") => self.handle_oauth_hosted_init(req, &request_id),
            ("GET", "/api/oauth-hosted/availability") => {
                self.handle_oauth_hosted_availability(&request_id)
            }
            ("POST", "/api/explore") => self.handle_explore(req, &request_id),
            ("GET", _) if !is_api => self.handle_static_or_spa(route_path, &request_id),
            _ => self.json_response(
                404,
                &request_id,
                is_api,
                json!({
                    "error": "Not Found",
                    "requestId": request_id,
                }),
            ),
        }
    }

    fn parse_json_body(&self, req: &HttpRequest) -> Value {
        if req.body.is_empty() {
            return Value::Object(Map::new());
        }
        serde_json::from_slice(&req.body).unwrap_or_else(|_| Value::Object(Map::new()))
    }

    fn handle_oauth_token(&self, req: &HttpRequest, request_id: &str) -> HttpResponse {
        let start_time = now_epoch_ms();
        let body = self.parse_json_body(req);
        let code = body.get("code").and_then(Value::as_str);
        let provider = body.get("provider").and_then(Value::as_str);
        let redirect_uri = body.get("redirectUri").and_then(Value::as_str);
        let is_hosted = body
            .get("isHosted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let body_client_id = body.get("clientId").and_then(Value::as_str);
        let body_client_secret = body.get("clientSecret").and_then(Value::as_str);
        let body_auth0_domain = body.get("auth0Domain").and_then(Value::as_str);
        let body_zitadel_domain = body.get("zitadelDomain").and_then(Value::as_str);

        let req_logger = create_request_logger(
            &self.logger,
            request_id,
            "/api/oauth/token",
            "POST",
            provider,
        );

        let (Some(code), Some(provider), Some(redirect_uri)) = (
            code.filter(|s| !s.is_empty()),
            provider.filter(|s| !s.is_empty()),
            redirect_uri.filter(|s| !s.is_empty()),
        ) else {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Missing required parameters: code, provider, redirectUri.",
                }),
            );
        };

        if !SUPPORTED_PROVIDERS.contains(&provider) {
            return self.json_response(
                400,
                request_id,
                true,
                json!({ "error": "Unsupported provider." }),
            );
        }

        if provider == "auth0"
            && body_auth0_domain.filter(|s| !s.is_empty()).is_none()
            && !is_hosted
        {
            return self.json_response(
                400,
                request_id,
                true,
                json!({ "error": "Auth0 domain is required for non-hosted auth." }),
            );
        }

        let mut auth0_domain = body_auth0_domain
            .filter(|s| !s.is_empty())
            .map(String::from);
        let mut zitadel_domain = body_zitadel_domain
            .filter(|s| !s.is_empty())
            .map(String::from);

        let (client_id, client_secret) = if is_hosted {
            let (cid, csec) = match self.get_hosted_credentials(provider) {
                Ok(creds) => creds,
                Err(err) => {
                    return self.json_response(
                        500,
                        request_id,
                        true,
                        json!({
                            "error": "Internal server error.",
                            "message": err,
                        }),
                    );
                }
            };
            if provider == "auth0" {
                if let Ok(d) = self.get_secret("AUTH0_APP_OAUTH_DOMAIN") {
                    auth0_domain = Some(d);
                }
            }
            if provider == "zitadel" {
                zitadel_domain = Some(self.resolve_zitadel_domain(zitadel_domain.as_deref()));
            }
            (cid, csec)
        } else {
            let (Some(cid), Some(csec)) = (
                body_client_id.filter(|s| !s.is_empty()),
                body_client_secret.filter(|s| !s.is_empty()),
            ) else {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({
                        "error": "Missing required parameters for non-hosted auth: clientId, clientSecret.",
                    }),
                );
            };
            (cid.to_string(), csec.to_string())
        };

        let mut headers = HashMap::new();
        headers.insert("Accept".to_string(), "application/json".to_string());

        let (token_url, req_body) = match provider {
            "github" => {
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                let body_str = build_form_urlencoded(&[
                    ("client_id", &client_id),
                    ("client_secret", &client_secret),
                    ("code", code),
                    ("redirect_uri", redirect_uri),
                ]);
                (
                    "https://github.com/login/oauth/access_token".to_string(),
                    body_str,
                )
            }
            "google" => {
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                let body_str = json!({
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "code": code,
                    "grant_type": "authorization_code",
                    "redirect_uri": redirect_uri,
                })
                .to_string();
                ("https://oauth2.googleapis.com/token".to_string(), body_str)
            }
            "gitlab" => {
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                let body_str = json!({
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "code": code,
                    "grant_type": "authorization_code",
                    "redirect_uri": redirect_uri,
                })
                .to_string();
                ("https://gitlab.com/oauth/token".to_string(), body_str)
            }
            "auth0" => {
                let Some(ref domain) = auth0_domain else {
                    return self.json_response(
                        400,
                        request_id,
                        true,
                        json!({ "error": "Auth0 domain is required." }),
                    );
                };
                if let Err(err) = self.validate_issuer_domain(domain) {
                    return self.collapse_upstream_error(request_id, &err);
                }
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                let body_str = json!({
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "code": code,
                    "grant_type": "authorization_code",
                    "redirect_uri": redirect_uri,
                })
                .to_string();
                (format!("https://{domain}/oauth/token"), body_str)
            }
            "zitadel" => {
                let domain = self.resolve_zitadel_domain(zitadel_domain.as_deref());
                zitadel_domain = Some(domain.clone());
                if let Err(err) = self.validate_issuer_domain(&domain) {
                    return self.collapse_upstream_error(request_id, &err);
                }
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                let body_str = build_form_urlencoded(&[
                    ("grant_type", "authorization_code"),
                    ("code", code),
                    ("redirect_uri", redirect_uri),
                    ("client_id", &client_id),
                    ("client_secret", &client_secret),
                ]);
                (format!("https://{domain}/oauth/v2/token"), body_str)
            }
            "linkedin" => {
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                let body_str = build_form_urlencoded(&[
                    ("grant_type", "authorization_code"),
                    ("code", code),
                    ("redirect_uri", redirect_uri),
                    ("client_id", &client_id),
                    ("client_secret", &client_secret),
                ]);
                (
                    "https://www.linkedin.com/oauth/v2/accessToken".to_string(),
                    body_str,
                )
            }
            _ => {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({ "error": "Unsupported provider." }),
                );
            }
        };

        let opts = SafeFetchOptions {
            method: "POST".to_string(),
            headers,
            body: Some(req_body),
            ..Default::default()
        };

        let token_response = match self.http_fetcher.fetch(&token_url, &opts) {
            Ok(r) => r,
            Err(err) => return self.collapse_upstream_error(request_id, &err),
        };

        if !token_response.ok() {
            let enhanced = enhance_oauth_error(
                &token_response.body,
                Some(token_response.status),
                Some(provider),
            );
            let payload = serde_json::to_value(enhanced).unwrap_or_else(|_| json!({}));
            return self.json_response(token_response.status, request_id, true, payload);
        }

        let mut token_data: Value = match serde_json::from_str(&token_response.body) {
            Ok(v) => v,
            Err(err) => {
                log_error(
                    &req_logger,
                    "OAuth token parse error",
                    &err.to_string(),
                    None,
                );
                return self.json_response(
                    500,
                    request_id,
                    true,
                    json!({
                        "error": "Internal server error.",
                        "message": err.to_string(),
                    }),
                );
            }
        };

        if let Value::Object(ref mut map) = token_data {
            if provider == "auth0" {
                if let Some(d) = auth0_domain {
                    map.insert("auth0_domain".to_string(), Value::String(d));
                }
            }
            if provider == "zitadel" {
                if let Some(d) = zitadel_domain {
                    map.insert("zitadel_domain".to_string(), Value::String(d));
                }
            }
        }

        log_timing(&req_logger, "oauth-token-exchange", start_time, None);
        self.json_response(200, request_id, true, token_data)
    }

    fn handle_oauth_refresh(&self, req: &HttpRequest, request_id: &str) -> HttpResponse {
        let start_time = now_epoch_ms();
        let body = self.parse_json_body(req);
        let provider = body.get("provider").and_then(Value::as_str);
        let refresh_token = body.get("refreshToken").and_then(Value::as_str);
        let is_hosted = body
            .get("isHosted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let body_client_id = body.get("clientId").and_then(Value::as_str);
        let body_client_secret = body.get("clientSecret").and_then(Value::as_str);
        let body_auth0_domain = body.get("auth0Domain").and_then(Value::as_str);
        let body_zitadel_domain = body.get("zitadelDomain").and_then(Value::as_str);

        let req_logger = create_request_logger(
            &self.logger,
            request_id,
            "/api/oauth/refresh",
            "POST",
            provider,
        );

        let (Some(refresh_token), Some(provider)) = (
            refresh_token.filter(|s| !s.is_empty()),
            provider.filter(|s| !s.is_empty()),
        ) else {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Missing required parameters: refreshToken, provider.",
                }),
            );
        };

        if !SUPPORTED_PROVIDERS.contains(&provider) {
            return self.json_response(
                400,
                request_id,
                true,
                json!({ "error": "Unsupported provider." }),
            );
        }

        let mut auth0_domain = body_auth0_domain
            .filter(|s| !s.is_empty())
            .map(String::from);
        let mut zitadel_domain = body_zitadel_domain
            .filter(|s| !s.is_empty())
            .map(String::from);

        let (client_id, client_secret) = if is_hosted {
            let (cid, csec) = match self.get_hosted_credentials(provider) {
                Ok(creds) => creds,
                Err(err) => {
                    return self.json_response(
                        500,
                        request_id,
                        true,
                        json!({
                            "error": "Internal server error.",
                            "message": err,
                        }),
                    );
                }
            };
            if provider == "auth0" {
                if let Ok(d) = self.get_secret("AUTH0_APP_OAUTH_DOMAIN") {
                    auth0_domain = Some(d);
                }
            }
            if provider == "zitadel" {
                zitadel_domain = Some(self.resolve_zitadel_domain(zitadel_domain.as_deref()));
            }
            (cid, csec)
        } else {
            let (Some(cid), Some(csec)) = (
                body_client_id.filter(|s| !s.is_empty()),
                body_client_secret.filter(|s| !s.is_empty()),
            ) else {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({
                        "error": "Missing required parameters for non-hosted auth: clientId, clientSecret.",
                    }),
                );
            };
            (cid.to_string(), csec.to_string())
        };

        if provider == "github" {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "GitHub OAuth Apps do not support refresh tokens. Only GitHub Apps support refresh tokens.",
                }),
            );
        }

        let mut headers = HashMap::new();
        headers.insert("Accept".to_string(), "application/json".to_string());

        let (refresh_url, req_body) = match provider {
            "google" => {
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                let body_str = json!({
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
                })
                .to_string();
                ("https://oauth2.googleapis.com/token".to_string(), body_str)
            }
            "gitlab" => {
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                let body_str = json!({
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
                })
                .to_string();
                ("https://gitlab.com/oauth/token".to_string(), body_str)
            }
            "auth0" => {
                let Some(ref domain) = auth0_domain else {
                    return self.json_response(
                        400,
                        request_id,
                        true,
                        json!({ "error": "Auth0 domain is required." }),
                    );
                };
                if let Err(err) = self.validate_issuer_domain(domain) {
                    return self.collapse_upstream_error(request_id, &err);
                }
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                let body_str = json!({
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
                })
                .to_string();
                (format!("https://{domain}/oauth/token"), body_str)
            }
            "zitadel" => {
                let domain = self.resolve_zitadel_domain(zitadel_domain.as_deref());
                if let Err(err) = self.validate_issuer_domain(&domain) {
                    return self.collapse_upstream_error(request_id, &err);
                }
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                let body_str = build_form_urlencoded(&[
                    ("grant_type", "refresh_token"),
                    ("refresh_token", refresh_token),
                    ("client_id", &client_id),
                    ("client_secret", &client_secret),
                ]);
                (format!("https://{domain}/oauth/v2/token"), body_str)
            }
            "linkedin" => {
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                let body_str = build_form_urlencoded(&[
                    ("grant_type", "refresh_token"),
                    ("refresh_token", refresh_token),
                    ("client_id", &client_id),
                    ("client_secret", &client_secret),
                ]);
                (
                    "https://www.linkedin.com/oauth/v2/accessToken".to_string(),
                    body_str,
                )
            }
            _ => {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({ "error": "Unsupported provider." }),
                );
            }
        };

        let opts = SafeFetchOptions {
            method: "POST".to_string(),
            headers,
            body: Some(req_body),
            ..Default::default()
        };

        let refresh_response = match self.http_fetcher.fetch(&refresh_url, &opts) {
            Ok(r) => r,
            Err(err) => return self.collapse_upstream_error(request_id, &err),
        };

        if !refresh_response.ok() {
            let enhanced = enhance_oauth_error(
                &refresh_response.body,
                Some(refresh_response.status),
                Some(provider),
            );
            let payload = serde_json::to_value(enhanced).unwrap_or_else(|_| json!({}));
            return self.json_response(refresh_response.status, request_id, true, payload);
        }

        let token_data: Value = match serde_json::from_str(&refresh_response.body) {
            Ok(v) => v,
            Err(err) => {
                log_error(
                    &req_logger,
                    "OAuth refresh parse error",
                    &err.to_string(),
                    None,
                );
                return self.json_response(
                    500,
                    request_id,
                    true,
                    json!({
                        "error": "Internal server error.",
                        "message": err.to_string(),
                    }),
                );
            }
        };

        log_timing(&req_logger, "oauth-token-refresh", start_time, None);
        self.json_response(200, request_id, true, token_data)
    }

    fn handle_oauth_revoke(&self, req: &HttpRequest, request_id: &str) -> HttpResponse {
        let start_time = now_epoch_ms();
        let body = self.parse_json_body(req);
        let provider = body.get("provider").and_then(Value::as_str);
        let token = body.get("token").and_then(Value::as_str);
        let token_type_hint = body.get("tokenTypeHint").and_then(Value::as_str);
        let is_hosted = body
            .get("isHosted")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let body_client_id = body.get("clientId").and_then(Value::as_str);
        let body_client_secret = body.get("clientSecret").and_then(Value::as_str);
        let body_auth0_domain = body.get("auth0Domain").and_then(Value::as_str);
        let body_zitadel_domain = body.get("zitadelDomain").and_then(Value::as_str);

        let req_logger = create_request_logger(
            &self.logger,
            request_id,
            "/api/oauth/revoke",
            "POST",
            provider,
        );

        let (Some(token), Some(provider)) = (
            token.filter(|s| !s.is_empty()),
            provider.filter(|s| !s.is_empty()),
        ) else {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Missing required parameters: token, provider.",
                }),
            );
        };

        if !SUPPORTED_PROVIDERS.contains(&provider) {
            return self.json_response(
                400,
                request_id,
                true,
                json!({ "error": "Unsupported provider." }),
            );
        }

        let mut auth0_domain = body_auth0_domain
            .filter(|s| !s.is_empty())
            .map(String::from);
        let mut zitadel_domain = body_zitadel_domain
            .filter(|s| !s.is_empty())
            .map(String::from);

        let (client_id, client_secret) = if is_hosted {
            let (cid, csec) = match self.get_hosted_credentials(provider) {
                Ok(creds) => creds,
                Err(err) => {
                    return self.json_response(
                        500,
                        request_id,
                        true,
                        json!({
                            "success": false,
                            "error": "Internal server error.",
                            "message": err,
                        }),
                    );
                }
            };
            if provider == "auth0" {
                if let Ok(d) = self.get_secret("AUTH0_APP_OAUTH_DOMAIN") {
                    auth0_domain = Some(d);
                }
            }
            if provider == "zitadel" {
                zitadel_domain = Some(self.resolve_zitadel_domain(zitadel_domain.as_deref()));
            }
            (cid, csec)
        } else {
            let (Some(cid), Some(csec)) = (
                body_client_id.filter(|s| !s.is_empty()),
                body_client_secret.filter(|s| !s.is_empty()),
            ) else {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({
                        "error": "Missing required parameters for non-hosted auth: clientId, clientSecret.",
                    }),
                );
            };
            (cid.to_string(), csec.to_string())
        };

        if provider == "linkedin" {
            return self.json_response(
                200,
                request_id,
                true,
                json!({
                    "success": true,
                    "message": "LinkedIn doesn't provide a token revocation endpoint. The token will expire naturally according to LinkedIn's token lifetime policy.",
                }),
            );
        }

        let mut headers = HashMap::new();
        let (revoke_url, method, req_body) = match provider {
            "github" => {
                headers.insert(
                    "Accept".to_string(),
                    "application/vnd.github.v3+json".to_string(),
                );
                let creds = format!("{client_id}:{client_secret}");
                headers.insert(
                    "Authorization".to_string(),
                    format!("Basic {}", base64_encode(creds.as_bytes())),
                );
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                (
                    format!("https://api.github.com/applications/{client_id}/token"),
                    "DELETE",
                    json!({ "access_token": token }).to_string(),
                )
            }
            "google" => {
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                let mut pairs = vec![("token", token)];
                if let Some(hint) = token_type_hint.filter(|s| !s.is_empty()) {
                    pairs.push(("token_type_hint", hint));
                }
                (
                    "https://oauth2.googleapis.com/revoke".to_string(),
                    "POST",
                    build_form_urlencoded(&pairs),
                )
            }
            "gitlab" => {
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                headers.insert("Accept".to_string(), "application/json".to_string());
                (
                    "https://gitlab.com/oauth/revoke".to_string(),
                    "POST",
                    json!({
                        "client_id": client_id,
                        "client_secret": client_secret,
                        "token": token,
                    })
                    .to_string(),
                )
            }
            "auth0" => {
                let Some(ref domain) = auth0_domain else {
                    return self.json_response(
                        400,
                        request_id,
                        true,
                        json!({ "error": "Auth0 domain is required." }),
                    );
                };
                if let Err(err) = self.validate_issuer_domain(domain) {
                    return self.collapse_upstream_error(request_id, &err);
                }
                headers.insert("Content-Type".to_string(), "application/json".to_string());
                headers.insert("Accept".to_string(), "application/json".to_string());
                (
                    format!("https://{domain}/oauth/revoke"),
                    "POST",
                    json!({
                        "client_id": client_id,
                        "client_secret": client_secret,
                        "token": token,
                        "token_type_hint": token_type_hint.unwrap_or("access_token"),
                    })
                    .to_string(),
                )
            }
            "zitadel" => {
                let domain = self.resolve_zitadel_domain(zitadel_domain.as_deref());
                if let Err(err) = self.validate_issuer_domain(&domain) {
                    return self.collapse_upstream_error(request_id, &err);
                }
                headers.insert(
                    "Content-Type".to_string(),
                    "application/x-www-form-urlencoded".to_string(),
                );
                headers.insert("Accept".to_string(), "application/json".to_string());
                let hint = token_type_hint.unwrap_or("access_token");
                (
                    format!("https://{domain}/oauth/v2/revoke"),
                    "POST",
                    build_form_urlencoded(&[
                        ("token", token),
                        ("client_id", &client_id),
                        ("client_secret", &client_secret),
                        ("token_type_hint", hint),
                    ]),
                )
            }
            _ => {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({ "error": "Unsupported provider." }),
                );
            }
        };

        let opts = SafeFetchOptions {
            method: method.to_string(),
            headers,
            body: Some(req_body),
            ..Default::default()
        };

        let revoke_response = match self.http_fetcher.fetch(&revoke_url, &opts) {
            Ok(r) => r,
            Err(err) => return self.collapse_upstream_error(request_id, &err),
        };

        let success = match provider {
            "github" => revoke_response.status == 204,
            "google" => revoke_response.status == 200,
            _ => revoke_response.ok(),
        };

        if !success {
            let response_data: Value =
                serde_json::from_str(&revoke_response.body).unwrap_or_else(|_| json!({}));
            let err_msg = response_data
                .get("error")
                .and_then(Value::as_str)
                .or_else(|| {
                    response_data
                        .get("error_description")
                        .and_then(Value::as_str)
                })
                .unwrap_or("Failed to revoke token.");
            return self.json_response(
                revoke_response.status,
                request_id,
                true,
                json!({
                    "success": false,
                    "error": err_msg,
                }),
            );
        }

        log_timing(&req_logger, "oauth-token-revocation", start_time, None);
        self.json_response(
            200,
            request_id,
            true,
            json!({
                "success": true,
                "message": "Token revoked successfully.",
            }),
        )
    }

    fn handle_oauth_hosted_init(&self, req: &HttpRequest, request_id: &str) -> HttpResponse {
        let start_time = now_epoch_ms();
        let body = self.parse_json_body(req);
        let provider = body.get("provider").and_then(Value::as_str);
        let redirect_uri = body.get("redirectUri").and_then(Value::as_str);
        let scopes = body.get("scopes").and_then(Value::as_str);

        let req_logger = create_request_logger(
            &self.logger,
            request_id,
            "/api/oauth-hosted/init",
            "POST",
            provider,
        );

        let (Some(provider), Some(redirect_uri)) = (
            provider.filter(|s| !s.is_empty()),
            redirect_uri.filter(|s| !s.is_empty()),
        ) else {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Missing required parameters: provider and redirectUri.",
                }),
            );
        };

        if !SUPPORTED_PROVIDERS.contains(&provider) {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Unsupported provider. Supported providers are: github, google, gitlab, auth0, zitadel, linkedin.",
                }),
            );
        }

        let (client_id, _) = match self.get_hosted_credentials(provider) {
            Ok(creds) => creds,
            Err(err) => {
                return self.json_response(
                    500,
                    request_id,
                    true,
                    json!({
                        "error": "Failed to initialize hosted OAuth.",
                        "message": err,
                    }),
                );
            }
        };

        let encoded_redirect_uri = encode_uri_component(redirect_uri);
        let auth_url = match provider {
            "github" => {
                let scope = "read:user,user:email";
                format!(
                    "https://github.com/login/oauth/authorize?client_id={client_id}&redirect_uri={encoded_redirect_uri}&scope={scope}&state=github-hosted"
                )
            }
            "google" => {
                let scope = "https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email";
                format!(
                    "https://accounts.google.com/o/oauth2/v2/auth?client_id={client_id}&redirect_uri={encoded_redirect_uri}&response_type=code&scope={scope}&state=google-hosted"
                )
            }
            "gitlab" => {
                let scope = "read_user";
                format!(
                    "https://gitlab.com/oauth/authorize?client_id={client_id}&redirect_uri={encoded_redirect_uri}&response_type=code&scope={scope}&state=gitlab-hosted"
                )
            }
            "auth0" => {
                let auth0_domain = self
                    .get_secret("AUTH0_APP_OAUTH_DOMAIN")
                    .unwrap_or_else(|_| "your-tenant.us.auth0.com".to_string());
                let scope = "openid profile email";
                format!(
                    "https://{auth0_domain}/authorize?client_id={client_id}&redirect_uri={encoded_redirect_uri}&response_type=code&scope={scope}&state=auth0-hosted"
                )
            }
            "zitadel" => {
                let zitadel_domain = self.resolve_zitadel_domain(None);
                let scope = scopes
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or("openid profile email offline_access");
                format!(
                    "https://{zitadel_domain}/oauth/v2/authorize?client_id={client_id}&redirect_uri={encoded_redirect_uri}&response_type=code&scope={}&state=zitadel-hosted",
                    encode_uri_component(scope)
                )
            }
            "linkedin" => {
                let scope = scopes
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .unwrap_or("openid profile email");
                format!(
                    "https://www.linkedin.com/oauth/v2/authorization?client_id={client_id}&redirect_uri={encoded_redirect_uri}&response_type=code&scope={}&state=linkedin-hosted",
                    encode_uri_component(scope)
                )
            }
            _ => String::new(),
        };

        log_timing(&req_logger, "oauth-hosted-init", start_time, None);
        self.json_response(200, request_id, true, json!({ "authUrl": auth_url }))
    }

    fn handle_oauth_hosted_availability(&self, request_id: &str) -> HttpResponse {
        let start_time = now_epoch_ms();
        let req_logger = create_request_logger(
            &self.logger,
            request_id,
            "/api/oauth-hosted/availability",
            "GET",
            None,
        );

        let secret_exists = |name: &str| self.get_secret(name).is_ok();

        let github = secret_exists("GITHUB_APP_OAUTH_CLIENT_ID")
            && secret_exists("GITHUB_APP_OAUTH_CLIENT_SECRET");
        let google = secret_exists("GOOGLE_APP_OAUTH_CLIENT_ID")
            && secret_exists("GOOGLE_APP_OAUTH_CLIENT_SECRET");
        let gitlab = secret_exists("GITLAB_APP_OAUTH_CLIENT_ID")
            && secret_exists("GITLAB_APP_OAUTH_CLIENT_SECRET");
        let auth0 = secret_exists("AUTH0_APP_OAUTH_CLIENT_ID")
            && secret_exists("AUTH0_APP_OAUTH_CLIENT_SECRET")
            && secret_exists("AUTH0_APP_OAUTH_DOMAIN");
        let zitadel = secret_exists("ZITADEL_APP_OAUTH_CLIENT_ID")
            && secret_exists("ZITADEL_APP_OAUTH_CLIENT_SECRET");
        let linkedin = secret_exists("LINKEDIN_APP_OAUTH_CLIENT_ID")
            && secret_exists("LINKEDIN_APP_OAUTH_CLIENT_SECRET");

        log_timing(&req_logger, "oauth-hosted-availability", start_time, None);
        self.json_response(
            200,
            request_id,
            true,
            json!({
                "availability": {
                    "github": github,
                    "google": google,
                    "gitlab": gitlab,
                    "auth0": auth0,
                    "zitadel": zitadel,
                    "linkedin": linkedin,
                }
            }),
        )
    }

    fn handle_explore(&self, req: &HttpRequest, request_id: &str) -> HttpResponse {
        let start_time = now_epoch_ms();
        let body = self.parse_json_body(req);
        let provider = body.get("provider").and_then(Value::as_str);
        let access_token = body.get("accessToken").and_then(Value::as_str);
        let endpoint = body.get("endpoint");

        let req_logger =
            create_request_logger(&self.logger, request_id, "/api/explore", "POST", provider);

        let (Some(provider), Some(access_token), Some(endpoint_obj)) = (
            provider.filter(|s| !s.is_empty()),
            access_token.filter(|s| !s.is_empty()),
            endpoint.and_then(Value::as_object),
        ) else {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Missing required fields: provider, accessToken, endpoint",
                }),
            );
        };

        let endpoint_id = endpoint_obj
            .get("id")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty());
        let endpoint_method = endpoint_obj
            .get("method")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty());

        let (Some(endpoint_id), Some(endpoint_method)) = (endpoint_id, endpoint_method) else {
            return self.json_response(
                400,
                request_id,
                true,
                json!({
                    "error": "Invalid endpoint: missing id or method",
                }),
            );
        };

        let issuer_domain: Option<String> = if provider == "auth0" {
            let Some(d) = body
                .get("auth0Domain")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
            else {
                return self.json_response(
                    400,
                    request_id,
                    true,
                    json!({
                        "error": "Auth0 domain required for Auth0 API calls",
                    }),
                );
            };
            Some(d.to_string())
        } else if provider == "zitadel" {
            Some(self.resolve_zitadel_domain(body.get("zitadelDomain").and_then(Value::as_str)))
        } else {
            None
        };

        let target_url =
            match resolve_explore_target(provider, endpoint_id, issuer_domain.as_deref()) {
                Ok(u) => u,
                Err(_) => {
                    return self.json_response(
                        400,
                        request_id,
                        true,
                        json!({ "error": "unknown endpoint" }),
                    );
                }
            };

        if let Some(ref domain) = issuer_domain {
            if let Err(err) = self.validate_issuer_domain(domain) {
                return self.collapse_upstream_error(request_id, &err);
            }
        }

        let mut headers = HashMap::new();
        headers.insert(
            "Authorization".to_string(),
            format!("Bearer {access_token}"),
        );
        headers.insert(
            "User-Agent".to_string(),
            "OAuth-User-Inspector/1.0".to_string(),
        );
        if provider == "github" {
            headers.insert("X-GitHub-Api-Version".to_string(), "2022-11-28".to_string());
            headers.insert(
                "Accept".to_string(),
                "application/vnd.github+json".to_string(),
            );
        }

        let opts = SafeFetchOptions {
            method: endpoint_method.to_string(),
            headers,
            body: None,
            ..Default::default()
        };

        let api_response = match self.http_fetcher.fetch(&target_url, &opts) {
            Ok(r) => r,
            Err(err) => return self.collapse_upstream_error(request_id, &err),
        };

        let api_ok = api_response.ok();
        let response_data: Value = if api_response.body.is_empty() {
            json!({})
        } else {
            serde_json::from_str(&api_response.body)
                .unwrap_or_else(|_| json!({ "raw": api_response.body }))
        };

        let mut out = Map::new();
        out.insert("success".to_string(), Value::Bool(api_ok));
        out.insert("status".to_string(), json!(api_response.status));
        out.insert("data".to_string(), response_data.clone());
        if !api_ok {
            let err_str = response_data
                .get("message")
                .and_then(Value::as_str)
                .or_else(|| response_data.get("error").and_then(Value::as_str))
                .unwrap_or("API call failed");
            out.insert("error".to_string(), Value::String(err_str.to_string()));
        }
        let hdr_map: Map<String, Value> = api_response
            .headers
            .into_iter()
            .map(|(k, v)| (k, Value::String(v)))
            .collect();
        out.insert("headers".to_string(), Value::Object(hdr_map));

        log_timing(&req_logger, "API Explore", start_time, None);
        self.json_response(200, request_id, true, Value::Object(out))
    }

    fn handle_static_or_spa(&self, route_path: &str, request_id: &str) -> HttpResponse {
        let mut headers = self.build_base_headers(request_id, false);
        let clean_rel = route_path.trim_start_matches('/');
        if !clean_rel.is_empty() && !clean_rel.contains("..") {
            let candidate = self.dist_dir.join(clean_rel);
            if candidate.is_file() {
                if let Ok(bytes) = fs::read(&candidate) {
                    headers.insert(
                        "Content-Type".to_string(),
                        guess_content_type(&candidate).to_string(),
                    );
                    if route_path.starts_with("/assets/") {
                        headers.insert(
                            "Cache-Control".to_string(),
                            "public, max-age=31536000, immutable".to_string(),
                        );
                    } else {
                        headers.insert("Cache-Control".to_string(), "no-cache".to_string());
                    }
                    return HttpResponse {
                        status: 200,
                        headers,
                        body: bytes,
                    };
                }
            }
        }

        let index_path = self.dist_dir.join("index.html");
        let body = fs::read(&index_path).unwrap_or_else(|_| {
            b"<!doctype html><html><head><title>OAuth User Inspector</title></head><body><div id=\"root\"></div></body></html>".to_vec()
        });
        headers.insert(
            "Content-Type".to_string(),
            "text/html; charset=utf-8".to_string(),
        );
        headers.insert(
            "Cache-Control".to_string(),
            "no-cache, no-store, must-revalidate".to_string(),
        );
        HttpResponse {
            status: 200,
            headers,
            body,
        }
    }
}

fn guess_content_type(path: &Path) -> &'static str {
    match path.extension().and_then(|s| s.to_str()) {
        Some("html") => "text/html; charset=utf-8",
        Some("js") | Some("mjs") => "application/javascript; charset=utf-8",
        Some("css") => "text/css; charset=utf-8",
        Some("json") => "application/json; charset=utf-8",
        Some("svg") => "image/svg+xml",
        Some("png") => "image/png",
        Some("ico") => "image/x-icon",
        _ => "application/octet-stream",
    }
}

/// Serve the HTTP application over a standard `TcpListener`.
pub fn serve_http(app: Arc<App>, port: u16) -> std::io::Result<()> {
    let listener = TcpListener::bind(("0.0.0.0", port))?;
    app.logger.info(
        "OAuth User Inspector server started",
        Some(json!({ "port": port })),
    );

    for stream_res in listener.incoming() {
        let Ok(mut stream) = stream_res else {
            continue;
        };
        let app_clone = Arc::clone(&app);
        std::thread::spawn(move || {
            let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
            let _ = stream.set_write_timeout(Some(Duration::from_secs(10)));
            let remote_ip = stream.peer_addr().ok().map(|a| a.ip().to_string());

            if let Some(req) = read_wire_request(&mut stream, remote_ip) {
                let resp = app_clone.handle_request(&req);
                let _ = write_wire_response(&mut stream, &resp);
            }
        });
    }
    Ok(())
}

fn find_header_end(buf: &[u8]) -> Option<(usize, usize)> {
    buf.windows(4)
        .position(|w| w == b"\r\n\r\n")
        .map(|p| (p, p + 4))
        .or_else(|| {
            buf.windows(2)
                .position(|w| w == b"\n\n")
                .map(|p| (p, p + 2))
        })
}

fn read_wire_request(stream: &mut impl Read, remote_ip: Option<String>) -> Option<HttpRequest> {
    let max_total = MAX_JSON_BODY_BYTES + 32 * 1024;
    let mut buf = Vec::with_capacity(8192);
    let mut chunk = [0u8; 8192];

    let header_end = loop {
        if let Some(pos) = find_header_end(&buf) {
            break pos;
        }
        if buf.len() >= max_total {
            break (buf.len(), buf.len());
        }
        let n = stream.read(&mut chunk).ok()?;
        if n == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..n]);
    };

    let header_str = String::from_utf8_lossy(&buf[..header_end.0]).to_string();
    let mut lines = header_str.lines();
    let req_line = lines.next()?;
    let mut parts = req_line.split_whitespace();
    let method = parts.next()?.to_uppercase();
    let path = parts.next()?.to_string();

    let mut headers = HashMap::new();
    for line in lines {
        if let Some((k, v)) = line.split_once(':') {
            headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }

    let expected_body_len = headers
        .get("content-length")
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(0)
        .min(MAX_JSON_BODY_BYTES + 4096);

    while buf.len().saturating_sub(header_end.1) < expected_body_len && buf.len() < max_total {
        let Ok(n) = stream.read(&mut chunk) else {
            break;
        };
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&chunk[..n]);
    }

    let body = if header_end.1 <= buf.len() {
        buf[header_end.1..].to_vec()
    } else {
        Vec::new()
    };

    Some(HttpRequest {
        method,
        path,
        headers,
        body,
        remote_ip,
    })
}

fn write_wire_response(stream: &mut impl Write, resp: &HttpResponse) -> std::io::Result<()> {
    let reason = match resp.status {
        200 => "OK",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        404 => "Not Found",
        413 => "Payload Too Large",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        _ => "OK",
    };
    write!(stream, "HTTP/1.1 {} {}\r\n", resp.status, reason)?;
    for (k, v) in &resp.headers {
        write!(stream, "{}: {}\r\n", k, v)?;
    }
    write!(stream, "Connection: close\r\n")?;
    write!(stream, "Content-Length: {}\r\n\r\n", resp.body.len())?;
    stream.write_all(&resp.body)?;
    stream.flush()
}
