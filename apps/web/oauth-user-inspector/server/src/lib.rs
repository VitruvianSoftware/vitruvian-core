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

pub mod api_endpoints;
pub mod logger;
pub mod oauth_error_guide;
pub mod oauth_session;
pub mod rate_limit;
pub mod safe_fetch;
pub mod security_headers;
pub mod server;
pub mod userinfo_request;

#[cfg(test)]
mod tests {
    use crate::api_endpoints::{
        endpoints_for_provider, resolve_explore_target, ExploreEndpointKind, ExploreProvider,
        EXPLORE_ENDPOINTS,
    };
    use crate::oauth_error_guide::{
        enhance_oauth_error, get_all_error_guides, is_known_oauth_error,
    };
    use crate::oauth_session::{resolve_oauth_session, OAuthSessionInputs};
    use crate::rate_limit::{client_ip, RateLimitTier, RateLimiter};
    use crate::safe_fetch::{
        resolve_and_pin_with, vet_address, with_content_length, with_default_user_agent,
        LookupAddress, SafeFetchOptions, SafeFetchResponse, UpstreamError, SAFE_FETCH_USER_AGENT,
    };
    use crate::security_headers::CONTENT_SECURITY_POLICY;
    use crate::server::{encode_uri_component, App, HttpFetcher, HttpRequest, SecretBackend};
    use crate::userinfo_request::{
        build_userinfo_request, UserinfoFetchMode, UserinfoRequestOptions,
    };
    use serde_json::{json, Value};
    use std::collections::{BTreeMap, HashMap};
    use std::fs;
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};

    fn read_app_file(rel: &str) -> String {
        let mut candidates = vec![
            PathBuf::from("apps/web/oauth-user-inspector").join(rel),
            PathBuf::from(rel),
        ];
        if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
            candidates.push(
                PathBuf::from(&srcdir)
                    .join("_main/apps/web/oauth-user-inspector")
                    .join(rel),
            );
            candidates.push(
                PathBuf::from(&srcdir)
                    .join("vitruvian_core/apps/web/oauth-user-inspector")
                    .join(rel),
            );
        }
        for path in &candidates {
            if let Ok(content) = fs::read_to_string(path) {
                return content;
            }
        }
        panic!("Unable to read app file '{rel}' from any candidate path: {candidates:?}");
    }

    #[derive(Clone)]
    struct MockSecretBackend {
        calls: Arc<Mutex<Vec<String>>>,
        handler: Arc<dyn Fn(&str) -> Result<Option<String>, String> + Send + Sync>,
    }

    impl MockSecretBackend {
        fn new<F>(f: F) -> Self
        where
            F: Fn(&str) -> Result<Option<String>, String> + Send + Sync + 'static,
        {
            Self {
                calls: Arc::new(Mutex::new(Vec::new())),
                handler: Arc::new(f),
            }
        }

        fn standard_test_secrets() -> Self {
            Self::new(|name| {
                let val = if name.contains("GITHUB_APP_OAUTH_CLIENT_ID") {
                    "test-github-client-id"
                } else if name.contains("GITHUB_APP_OAUTH_CLIENT_SECRET") {
                    "test-github-client-secret"
                } else if name.contains("GOOGLE_APP_OAUTH_CLIENT_ID") {
                    "test-google-client-id"
                } else if name.contains("GOOGLE_APP_OAUTH_CLIENT_SECRET") {
                    "test-google-client-secret"
                } else if name.contains("GITLAB_APP_OAUTH_CLIENT_ID") {
                    "test-gitlab-client-id"
                } else if name.contains("GITLAB_APP_OAUTH_CLIENT_SECRET") {
                    "test-gitlab-client-secret"
                } else if name.contains("AUTH0_APP_OAUTH_CLIENT_ID") {
                    "test-auth0-client-id"
                } else if name.contains("AUTH0_APP_OAUTH_CLIENT_SECRET") {
                    "test-auth0-client-secret"
                } else if name.contains("AUTH0_APP_OAUTH_DOMAIN") {
                    "oauth-user-inspector.us.auth0.com"
                } else if name.contains("ZITADEL_APP_OAUTH_CLIENT_ID") {
                    "test-zitadel-client-id"
                } else if name.contains("ZITADEL_APP_OAUTH_CLIENT_SECRET") {
                    "test-zitadel-client-secret"
                } else if name.contains("LINKEDIN_APP_OAUTH_CLIENT_ID") {
                    "test-linkedin-client-id"
                } else if name.contains("LINKEDIN_APP_OAUTH_CLIENT_SECRET") {
                    "test-linkedin-client-secret"
                } else {
                    return Ok(None);
                };
                Ok(Some(val.to_string()))
            })
        }

        fn recorded_calls(&self) -> Vec<String> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl SecretBackend for MockSecretBackend {
        fn access_secret_version(&self, name: &str) -> Result<Option<String>, String> {
            self.calls.lock().unwrap().push(name.to_string());
            (self.handler)(name)
        }
    }

    #[derive(Debug, Clone)]
    struct RecordedFetchCall {
        url: String,
        opts: SafeFetchOptions,
    }

    #[derive(Clone)]
    struct MockHttpFetcher {
        calls: Arc<Mutex<Vec<RecordedFetchCall>>>,
        handler: Arc<
            dyn Fn(&str, &SafeFetchOptions) -> Result<SafeFetchResponse, UpstreamError>
                + Send
                + Sync,
        >,
    }

    impl MockHttpFetcher {
        fn new<F>(f: F) -> Self
        where
            F: Fn(&str, &SafeFetchOptions) -> Result<SafeFetchResponse, UpstreamError>
                + Send
                + Sync
                + 'static,
        {
            Self {
                calls: Arc::new(Mutex::new(Vec::new())),
                handler: Arc::new(f),
            }
        }

        fn recorded_calls(&self) -> Vec<RecordedFetchCall> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl HttpFetcher for MockHttpFetcher {
        fn fetch(
            &self,
            url: &str,
            opts: &SafeFetchOptions,
        ) -> Result<SafeFetchResponse, UpstreamError> {
            self.calls.lock().unwrap().push(RecordedFetchCall {
                url: url.to_string(),
                opts: opts.clone(),
            });
            (self.handler)(url, opts)
        }
    }

    fn mock_json_response(status: u16, payload: Value) -> SafeFetchResponse {
        let mut headers = HashMap::new();
        headers.insert("content-type".to_string(), "application/json".to_string());
        SafeFetchResponse {
            status,
            status_text: if (200..300).contains(&status) {
                "OK".to_string()
            } else {
                "Bad Request".to_string()
            },
            headers,
            body: payload.to_string(),
        }
    }

    // =========================================================================
    // 1. dependency-consistency.test.ts
    // =========================================================================
    #[test]
    fn dependency_consistency_react_and_types_share_major_version() {
        let content = read_app_file("package.json");
        let pkg: Value = serde_json::from_str(&content).expect("valid package.json");
        let deps = pkg.get("dependencies").expect("dependencies");
        let dev_deps = pkg.get("devDependencies").expect("devDependencies");

        fn major_of(spec: Option<&Value>) -> String {
            let s = spec
                .and_then(Value::as_str)
                .expect("version string must be defined");
            assert!(
                !s.starts_with("catalog:"),
                "package.json must not use catalog: specifiers (got {s})"
            );
            let stripped = s.trim_start_matches(['^', '~', '>', '=', '<', ' ']);
            stripped
                .split('.')
                .next()
                .expect("major version")
                .to_string()
        }

        let react_major = major_of(deps.get("react"));
        let react_dom_major = major_of(deps.get("react-dom"));
        let types_react_major = major_of(dev_deps.get("@types/react"));
        let types_react_dom_major = major_of(dev_deps.get("@types/react-dom"));

        assert_eq!(react_dom_major, react_major);
        assert_eq!(types_react_major, react_major);
        assert_eq!(types_react_dom_major, react_major);
    }

    // =========================================================================
    // 2. explore-endpoints-parity.test.ts
    // =========================================================================
    fn extract_frontend_endpoint_ids() -> BTreeMap<String, Vec<String>> {
        let src = read_app_file("frontend/utils/apiEndpoints.ts");
        let mut out: BTreeMap<String, Vec<String>> = BTreeMap::new();
        let mut current_provider: Option<String> = None;

        for line in src.lines() {
            let trimmed = line.trim();
            if let Some(rest) = trimmed.strip_prefix("case \"") {
                if let Some((provider, _)) = rest.split_once("\":") {
                    current_provider = Some(provider.to_string());
                    out.entry(provider.to_string()).or_default();
                    continue;
                }
            }
            if let Some(ref prov) = current_provider {
                if let Some(rest) = trimmed.strip_prefix("id: \"") {
                    if let Some((id, _)) = rest.split_once('"') {
                        out.entry(prov.clone()).or_default().push(id.to_string());
                    }
                }
            }
        }
        out
    }

    #[test]
    fn explore_endpoints_parity_matches_frontend_catalog() {
        let frontend = extract_frontend_endpoint_ids();
        assert!(!frontend.is_empty());

        let mut server_providers: Vec<String> = EXPLORE_ENDPOINTS
            .iter()
            .map(|(p, _)| p.as_str().to_string())
            .collect();
        server_providers.sort();
        let frontend_providers: Vec<String> = frontend.keys().cloned().collect();
        assert_eq!(server_providers, frontend_providers);

        for (provider, frontend_ids) in &frontend {
            let prov = ExploreProvider::parse(provider).expect("valid provider");
            let mut server_ids: Vec<String> = endpoints_for_provider(prov)
                .iter()
                .map(|e| e.id.to_string())
                .collect();
            server_ids.sort();
            let mut sorted_frontend = frontend_ids.clone();
            sorted_frontend.sort();
            assert_eq!(
                server_ids, sorted_frontend,
                "mismatch for provider {provider}"
            );
        }
    }

    #[test]
    fn explore_endpoints_resolve_to_https_and_reject_unknown() {
        for (prov, defs) in EXPLORE_ENDPOINTS {
            for def in *defs {
                let domain = match def.kind {
                    ExploreEndpointKind::Fixed => None,
                    ExploreEndpointKind::Issuer => Some("tenant.example.com"),
                };
                let resolved = resolve_explore_target(prov.as_str(), def.id, domain)
                    .expect("must resolve known endpoint");
                assert!(
                    resolved.starts_with("https://"),
                    "endpoint {} must start with https://",
                    def.id
                );
            }
        }

        assert!(resolve_explore_target("evil", "user", None).is_err());
        assert!(resolve_explore_target("google", "metadata_ssrf", None).is_err());
        assert!(
            resolve_explore_target("google", "http://169.254.169.254/latest/meta-data/", None)
                .is_err()
        );
        // Issuer endpoint without issuer_domain fails closed
        assert!(resolve_explore_target("auth0", "userinfo", None).is_err());
        assert!(resolve_explore_target("zitadel", "userinfo", None).is_err());
    }

    // =========================================================================
    // 3. hardening.test.ts
    // =========================================================================
    #[test]
    fn hardening_emits_security_headers_and_no_store_on_api() {
        let app = App::with_backends(
            Arc::new(MockSecretBackend::standard_test_secrets()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        let resp = app.handle_request(&HttpRequest::new("GET", "/api/health"));
        assert_eq!(resp.status, 200);
        assert_eq!(
            resp.header("content-security-policy"),
            Some(CONTENT_SECURITY_POLICY)
        );
        assert!(resp
            .header("content-security-policy")
            .unwrap()
            .contains("frame-ancestors 'none'"));
        assert!(resp
            .header("content-security-policy")
            .unwrap()
            .contains("script-src 'self'"));
        assert!(!resp
            .header("content-security-policy")
            .unwrap()
            .contains("script-src 'self' 'unsafe-inline'"));
        assert!(resp
            .header("content-security-policy")
            .unwrap()
            .contains("connect-src 'self' https:"));
        assert_eq!(
            resp.header("strict-transport-security"),
            Some("max-age=31536000; includeSubDomains")
        );
        assert_eq!(resp.header("x-content-type-options"), Some("nosniff"));
        assert_eq!(resp.header("referrer-policy"), Some("no-referrer"));
        assert_eq!(resp.header("x-frame-options"), Some("DENY"));
        assert_eq!(
            resp.header("cross-origin-opener-policy"),
            Some("same-origin")
        );
        assert_eq!(resp.header("x-powered-by"), None);
        assert_eq!(resp.header("cache-control"), Some("no-store"));
    }

    #[test]
    fn hardening_rate_limiter_allows_up_to_max_and_blocks_with_retry_after() {
        let mut limiter = RateLimiter::new(RateLimitTier::new("test", 3, 60_000));
        let t0 = 1_700_000_000_000u64;
        assert!(limiter.hit_at("203.0.113.10", t0).allowed);
        assert!(limiter.hit_at("203.0.113.10", t0 + 10).allowed);
        assert!(limiter.hit_at("203.0.113.10", t0 + 20).allowed);

        let blocked = limiter.hit_at("203.0.113.10", t0 + 30);
        assert!(!blocked.allowed);
        assert!(blocked.retry_after_sec >= 59);

        // Other IPs are unaffected
        assert!(limiter.hit_at("203.0.113.11", t0 + 30).allowed);

        // After the window elapses, requests succeed again
        assert!(limiter.hit_at("203.0.113.10", t0 + 60_001).allowed);
    }

    #[test]
    fn hardening_client_ip_prefers_cf_connecting_ip() {
        assert_eq!(
            client_ip(Some("203.0.113.7"), Some("10.0.0.1")),
            "203.0.113.7"
        );
        assert_eq!(client_ip(None, Some("198.51.100.8")), "198.51.100.8");
        assert_eq!(client_ip(None, None), "unknown");
    }

    #[test]
    fn hardening_returns_429_with_retry_after_when_rate_limit_exceeded() {
        let app = App::with_backends(
            Arc::new(MockSecretBackend::standard_test_secrets()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        app.set_env("GOOGLE_CLOUD_PROJECT", Some("test-project".to_string()));
        let test_ip = "198.51.100.42";
        let mut blocked = None;
        for _ in 0..70 {
            let req = HttpRequest::new("POST", "/api/oauth-hosted/init")
                .with_header("cf-connecting-ip", test_ip)
                .with_json(json!({}));
            let res = app.handle_request(&req);
            if res.status == 429 {
                blocked = Some(res);
                break;
            }
        }
        let blocked = blocked.expect("must trigger 429 within 70 requests");
        assert_eq!(blocked.status, 429);
        let retry_after: u64 = blocked
            .header("retry-after")
            .expect("Retry-After header")
            .parse()
            .expect("numeric Retry-After");
        assert!(retry_after > 0);
        assert!(blocked
            .json()
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("")
            .contains("Too many requests"));
    }

    #[test]
    fn hardening_secret_manager_ttl_cache_collapses_repeated_reads() {
        let secret_mock = MockSecretBackend::standard_test_secrets();
        let app = App::with_backends(
            Arc::new(secret_mock.clone()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        app.set_env("GOOGLE_CLOUD_PROJECT", Some("test-proj".to_string()));

        let body = json!({
            "provider": "github",
            "redirectUri": "https://example.com/callback",
        });
        let req = HttpRequest::new("POST", "/api/oauth-hosted/init").with_json(body);
        assert_eq!(app.handle_request(&req).status, 200);
        assert_eq!(app.handle_request(&req).status, 200);

        let github_id_reads = secret_mock
            .recorded_calls()
            .into_iter()
            .filter(|name| name.contains("GITHUB_APP_OAUTH_CLIENT_ID"))
            .count();
        assert_eq!(github_id_reads, 1);
    }

    #[test]
    fn hardening_rejects_json_body_larger_than_64kb_with_413() {
        let app = App::with_backends(
            Arc::new(MockSecretBackend::standard_test_secrets()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        let oversized = json!({
            "blob": "a".repeat(70 * 1024),
        });
        let req = HttpRequest::new("POST", "/api/oauth/token")
            .with_header("cf-connecting-ip", "198.51.100.99")
            .with_json(oversized);
        let res = app.handle_request(&req);
        assert_eq!(res.status, 413);
    }

    #[test]
    fn hardening_fast_drops_scanner_probe_paths_with_plain_404() {
        let app = App::with_backends(
            Arc::new(MockSecretBackend::standard_test_secrets()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        let blocked_paths = [
            "/term.php",
            "/12.php",
            "/wp-login.php",
            "/server.js.bak",
            "/database.sql",
            "/backup.tar",
            "/dump.zip",
            "/shell.asp",
            "/wp-admin/index.php",
            "/.env",
            "/.git/config",
            "/.svn/entries",
            "/.htaccess",
            "/phpmyadmin/index.php",
            "/cgi-bin/test",
            "/actuator/health",
            "/xmlrpc.php",
            "/server-status",
        ];
        for p in blocked_paths {
            let res = app.handle_request(&HttpRequest::new("GET", p));
            assert_eq!(res.status, 404, "expected 404 for probe path {p}");
            assert_eq!(res.text(), "Not Found");
            assert!(res
                .header("content-type")
                .unwrap_or("")
                .contains("text/plain"));
        }

        let allowed_paths = ["/", "/api/health", "/inspect", "/api/oauth/token"];
        for p in allowed_paths {
            let res = app.handle_request(&HttpRequest::new("GET", p));
            if res.status == 404 {
                assert!(
                    !res.header("content-type")
                        .unwrap_or("")
                        .contains("text/plain"),
                    "legitimate path {p} must not hit probe filter"
                );
            }
        }
    }

    // =========================================================================
    // 4. oauth-error-guide.test.ts
    // =========================================================================
    #[test]
    fn oauth_error_guide_enhances_known_and_unknown_errors() {
        let invalid_scope = enhance_oauth_error(
            &json!({
                "error": "invalid_scope",
                "error_description": "The requested scope is invalid",
            })
            .to_string(),
            Some(400),
            Some("github"),
        );
        assert_eq!(invalid_scope.error_code.as_deref(), Some("invalid_scope"));
        let guide = invalid_scope.guide.expect("guide must be present");
        assert_eq!(guide.title, "Invalid Scope");
        assert!(guide.troubleshooting.contains(
            &"Check that all requested scopes are supported by the OAuth provider".to_string()
        ));

        let unauth = enhance_oauth_error(
            &json!({
                "error": "unauthorized_client",
                "error_description": "Client authentication failed",
            })
            .to_string(),
            Some(401),
            Some("google"),
        );
        assert_eq!(unauth.error_code.as_deref(), Some("unauthorized_client"));
        assert_eq!(unauth.guide.as_ref().unwrap().title, "Unauthorized Client");
        assert!(unauth
            .guide
            .as_ref()
            .unwrap()
            .troubleshooting
            .contains(&"Verify your Client ID and Client Secret are correct".to_string()));

        let denied = enhance_oauth_error(
            &json!({
                "error": "access_denied",
                "error_description": "User denied the request",
            })
            .to_string(),
            Some(403),
            Some("google"),
        );
        assert_eq!(denied.error_code.as_deref(), Some("access_denied"));
        assert_eq!(denied.guide.as_ref().unwrap().title, "Access Denied");

        let url_encoded = enhance_oauth_error(
            "error=invalid_grant&error_description=The%20authorization%20code%20has%20expired",
            Some(400),
            Some("github"),
        );
        assert_eq!(url_encoded.error_code.as_deref(), Some("invalid_grant"));
        assert_eq!(url_encoded.guide.as_ref().unwrap().title, "Invalid Grant");

        let plain = enhance_oauth_error("server_error", Some(500), Some("auth0"));
        assert_eq!(plain.error_code.as_deref(), Some("server_error"));
        assert_eq!(plain.guide.as_ref().unwrap().title, "Server Error");

        let unknown = enhance_oauth_error(
            &json!({
                "error": "unknown_error",
                "error_description": "This is an unknown error",
            })
            .to_string(),
            Some(400),
            Some("github"),
        );
        assert_eq!(unknown.error_code.as_deref(), Some("unknown_error"));
        assert!(unknown.guide.is_none());
        assert_eq!(unknown.error, "This is an unknown error");

        let malformed = enhance_oauth_error("invalid json {", Some(400), Some("github"));
        assert_eq!(malformed.error, "invalid json {");
        assert!(malformed.guide.is_none());

        assert!(is_known_oauth_error("invalid_scope"));
        assert!(is_known_oauth_error("unauthorized_client"));
        assert!(is_known_oauth_error("access_denied"));
        assert!(is_known_oauth_error("invalid_grant"));
        assert!(is_known_oauth_error("INVALID_SCOPE"));
        assert!(is_known_oauth_error("Invalid_Scope"));
        assert!(!is_known_oauth_error("unknown_error"));
        assert!(!is_known_oauth_error(""));

        let all = get_all_error_guides();
        assert_eq!(all.len(), 8);
        assert!(all.contains_key("invalid_scope"));
        assert!(all.contains_key("temporarily_unavailable"));
    }

    // =========================================================================
    // 5. safefetch-useragent.test.ts
    // =========================================================================
    #[test]
    fn safefetch_user_agent_and_content_length_helpers() {
        let empty = HashMap::new();
        let with_ua = with_default_user_agent(&empty);
        assert_eq!(
            with_ua.get("User-Agent").map(String::as_str),
            Some(SAFE_FETCH_USER_AGENT)
        );

        let mut custom = HashMap::new();
        custom.insert("User-Agent".to_string(), "custom-agent/1.0".to_string());
        let preserved = with_default_user_agent(&custom);
        assert_eq!(
            preserved.get("User-Agent").map(String::as_str),
            Some("custom-agent/1.0")
        );

        let mut lower_custom = HashMap::new();
        lower_custom.insert("user-agent".to_string(), "lower-agent/2.0".to_string());
        let lower_preserved = with_default_user_agent(&lower_custom);
        assert_eq!(
            lower_preserved.get("user-agent").map(String::as_str),
            Some("lower-agent/2.0")
        );
        assert!(!lower_preserved.contains_key("User-Agent"));

        let body = "client_id=abc&code=123&grant_type=authorization_code";
        let with_cl = with_content_length(&empty, Some(body));
        assert_eq!(
            with_cl.get("Content-Length").map(String::as_str),
            Some(&body.len().to_string()[..])
        );

        let utf8_body = "state=café";
        let with_utf8_cl = with_content_length(&empty, Some(utf8_body));
        assert_eq!(
            with_utf8_cl.get("Content-Length").map(String::as_str),
            Some("11")
        );

        assert!(!with_content_length(&empty, None).contains_key("Content-Length"));
        assert!(!with_content_length(&empty, Some("")).contains_key("Content-Length"));

        let mut existing_cl = HashMap::new();
        existing_cl.insert("content-length".to_string(), "99".to_string());
        let preserved_cl = with_content_length(&existing_cl, Some("abc"));
        assert_eq!(
            preserved_cl.get("content-length").map(String::as_str),
            Some("99")
        );
        assert!(!preserved_cl.contains_key("Content-Length"));
    }

    // =========================================================================
    // 6. secret-prefix.test.ts
    // =========================================================================
    #[test]
    fn secret_prefix_prepends_when_set_and_uses_bare_id_when_unset() {
        let secret_mock = MockSecretBackend::new(|_| Ok(Some("secret-value".to_string())));
        let app = App::with_backends(
            Arc::new(secret_mock.clone()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        app.set_env("GOOGLE_CLOUD_PROJECT", Some("test-proj".to_string()));
        app.set_env("SECRET_PREFIX", Some("OAUTH_USER_INSPECTOR_".to_string()));

        let val = app
            .get_secret("GITHUB_APP_OAUTH_CLIENT_ID")
            .expect("must succeed");
        assert_eq!(val, "secret-value");
        assert_eq!(
            secret_mock.recorded_calls(),
            vec![
                "projects/test-proj/secrets/OAUTH_USER_INSPECTOR_GITHUB_APP_OAUTH_CLIENT_ID/versions/latest"
                    .to_string()
            ]
        );

        let secret_mock_bare = MockSecretBackend::new(|_| Ok(Some("secret-value".to_string())));
        let app_bare = App::with_backends(
            Arc::new(secret_mock_bare.clone()),
            Arc::new(MockHttpFetcher::new(|_, _| unreachable!())),
        );
        app_bare.set_env("GOOGLE_CLOUD_PROJECT", Some("test-proj".to_string()));
        app_bare.set_env("SECRET_PREFIX", None);

        let val_bare = app_bare
            .get_secret("GITHUB_APP_OAUTH_CLIENT_ID")
            .expect("must succeed");
        assert_eq!(val_bare, "secret-value");
        assert_eq!(
            secret_mock_bare.recorded_calls(),
            vec![
                "projects/test-proj/secrets/GITHUB_APP_OAUTH_CLIENT_ID/versions/latest".to_string()
            ]
        );
    }

    // =========================================================================
    // 7. server.test.ts
    // =========================================================================
    fn build_standard_test_app() -> (App, MockHttpFetcher) {
        let fetcher = MockHttpFetcher::new(|url, opts| {
            let body = opts.body.as_deref().unwrap_or("");
            let is_refresh = body.contains("\"grant_type\":\"refresh_token\"")
                || body.contains("grant_type=refresh_token");

            if opts.method == "POST" && url == "https://github.com/login/oauth/access_token" {
                return Ok(mock_json_response(
                    200,
                    json!({ "access_token": "test_access_token" }),
                ));
            }
            if opts.method == "POST" && url == "https://oauth2.googleapis.com/token" {
                return Ok(mock_json_response(
                    200,
                    json!({
                        "access_token": "new_google_access_token",
                        "refresh_token": "new_google_refresh_token",
                        "expires_in": 3600,
                        "token_type": "Bearer",
                    }),
                ));
            }
            if opts.method == "POST" && url == "https://gitlab.com/oauth/token" {
                if is_refresh {
                    return Ok(mock_json_response(
                        200,
                        json!({
                            "access_token": "new_gitlab_access_token",
                            "refresh_token": "new_gitlab_refresh_token",
                            "expires_in": 7200,
                        }),
                    ));
                }
                return Ok(mock_json_response(
                    200,
                    json!({ "access_token": "test_gitlab_access_token" }),
                ));
            }
            if opts.method == "POST"
                && url == "https://oauth-user-inspector.us.auth0.com/oauth/token"
            {
                if is_refresh {
                    return Ok(mock_json_response(
                        200,
                        json!({
                            "access_token": "new_auth0_access_token",
                            "refresh_token": "new_auth0_refresh_token",
                            "expires_in": 86400,
                        }),
                    ));
                }
                return Ok(mock_json_response(
                    200,
                    json!({ "access_token": "test_auth0_access_token" }),
                ));
            }
            if opts.method == "POST" && url == "https://www.linkedin.com/oauth/v2/accessToken" {
                if is_refresh {
                    return Ok(mock_json_response(
                        200,
                        json!({
                            "access_token": "new_linkedin_access_token",
                            "refresh_token": "new_linkedin_refresh_token",
                            "expires_in": 5184000,
                        }),
                    ));
                }
                return Ok(mock_json_response(
                    200,
                    json!({ "access_token": "test_linkedin_access_token" }),
                ));
            }
            if opts.method == "POST" && url == "https://auth.ipv1337.dev/oauth/v2/token" {
                if is_refresh {
                    return Ok(mock_json_response(
                        200,
                        json!({
                            "access_token": "new_zitadel_access_token",
                            "refresh_token": "new_zitadel_refresh_token",
                            "expires_in": 3600,
                        }),
                    ));
                }
                return Ok(mock_json_response(
                    200,
                    json!({ "access_token": "test_zitadel_access_token" }),
                ));
            }
            if opts.method == "POST" && url == "https://oauth2.googleapis.com/revoke" {
                return Ok(mock_json_response(200, json!({})));
            }
            if opts.method == "DELETE"
                && url.starts_with("https://api.github.com/applications/")
                && url.ends_with("/token")
            {
                return Ok(SafeFetchResponse {
                    status: 204,
                    status_text: "No Content".to_string(),
                    headers: HashMap::new(),
                    body: String::new(),
                });
            }
            if opts.method == "POST" && url == "https://gitlab.com/oauth/revoke" {
                return Ok(mock_json_response(200, json!({ "success": true })));
            }
            if opts.method == "POST"
                && url == "https://oauth-user-inspector.us.auth0.com/oauth/revoke"
            {
                return Ok(mock_json_response(200, json!({ "success": true })));
            }
            if opts.method == "POST" && url == "https://auth.ipv1337.dev/oauth/v2/revoke" {
                return Ok(mock_json_response(200, json!({})));
            }
            if opts.method == "GET" && url == "https://api.github.com/user" {
                return Ok(mock_json_response(
                    200,
                    json!({ "login": "testuser", "id": 123 }),
                ));
            }
            Err(UpstreamError::new(format!("unhandled mock URL: {url}")))
        });

        let app = App::with_backends(
            Arc::new(MockSecretBackend::standard_test_secrets()),
            Arc::new(fetcher.clone()),
        );
        app.set_env("GOOGLE_CLOUD_PROJECT", Some("test-project".to_string()));
        (app, fetcher)
    }

    #[test]
    fn server_token_exchange_across_all_providers() {
        let (app, _fetcher) = build_standard_test_app();

        // Non-hosted GitHub
        let gh = app.handle_request(&HttpRequest::new("POST", "/api/oauth/token").with_json(
            json!({
                "code": "valid_code",
                "provider": "github",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            }),
        ));
        assert_eq!(gh.status, 200);
        assert_eq!(
            gh.json().get("access_token").and_then(Value::as_str),
            Some("test_access_token")
        );

        // Hosted GitHub
        let gh_hosted = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/token").with_json(json!({
                "code": "valid_code",
                "provider": "github",
                "redirectUri": "http://localhost:3000",
                "isHosted": true,
            })),
        );
        assert_eq!(gh_hosted.status, 200);
        assert_eq!(
            gh_hosted.json().get("access_token").and_then(Value::as_str),
            Some("test_access_token")
        );

        // GitLab
        let gl = app.handle_request(&HttpRequest::new("POST", "/api/oauth/token").with_json(
            json!({
                "code": "valid_code",
                "provider": "gitlab",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            }),
        ));
        assert_eq!(gl.status, 200);
        assert_eq!(
            gl.json().get("access_token").and_then(Value::as_str),
            Some("test_gitlab_access_token")
        );

        // Google
        let goog = app.handle_request(&HttpRequest::new("POST", "/api/oauth/token").with_json(
            json!({
                "code": "valid_code",
                "provider": "google",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            }),
        ));
        assert_eq!(goog.status, 200);
        assert_eq!(
            goog.json().get("access_token").and_then(Value::as_str),
            Some("new_google_access_token")
        );

        // Auth0
        let auth0 = app.handle_request(&HttpRequest::new("POST", "/api/oauth/token").with_json(
            json!({
                "code": "valid_code",
                "provider": "auth0",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "auth0Domain": "oauth-user-inspector.us.auth0.com",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            }),
        ));
        assert_eq!(auth0.status, 200);
        assert_eq!(
            auth0.json().get("access_token").and_then(Value::as_str),
            Some("test_auth0_access_token")
        );

        // LinkedIn
        let li = app.handle_request(&HttpRequest::new("POST", "/api/oauth/token").with_json(
            json!({
                "code": "valid_code",
                "provider": "linkedin",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            }),
        ));
        assert_eq!(li.status, 200);
        assert_eq!(
            li.json().get("access_token").and_then(Value::as_str),
            Some("test_linkedin_access_token")
        );

        // Auth0 without domain -> 400
        let auth0_no_domain = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/token").with_json(json!({
                "code": "valid_code",
                "provider": "auth0",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            })),
        );
        assert_eq!(auth0_no_domain.status, 400);

        // Unsupported provider -> 400
        let unsupported = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/token").with_json(json!({
                "code": "valid_code",
                "provider": "facebook",
                "clientId": "test-client-id",
                "clientSecret": "test-client-secret",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            })),
        );
        assert_eq!(unsupported.status, 400);
    }

    #[test]
    fn server_byo_vs_hosted_credential_routing_regression() {
        let (app, fetcher) = build_standard_test_app();

        // 1. BYO Google refresh forwards user's own client credentials
        let res_byo = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/refresh").with_json(json!({
                "provider": "google",
                "refreshToken": "byo_refresh_token",
                "clientId": "byo-client-id",
                "clientSecret": "byo-client-secret",
                "isHosted": false,
            })),
        );
        assert_eq!(res_byo.status, 200);
        let calls = fetcher.recorded_calls();
        let parsed: Value = serde_json::from_str(calls[0].opts.body.as_deref().unwrap()).unwrap();
        assert_eq!(
            parsed.get("client_id").and_then(Value::as_str),
            Some("byo-client-id")
        );
        assert_eq!(
            parsed.get("client_secret").and_then(Value::as_str),
            Some("byo-client-secret")
        );

        // 2. Hosted Google refresh uses Secret Manager credentials
        let res_hosted = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/refresh").with_json(json!({
                "provider": "google",
                "refreshToken": "hosted_refresh_token",
                "isHosted": true,
            })),
        );
        assert_eq!(res_hosted.status, 200);
        let calls = fetcher.recorded_calls();
        let parsed_hosted: Value =
            serde_json::from_str(calls[1].opts.body.as_deref().unwrap()).unwrap();
        assert_eq!(
            parsed_hosted.get("client_id").and_then(Value::as_str),
            Some("test-google-client-id")
        );
        assert_eq!(
            parsed_hosted.get("client_secret").and_then(Value::as_str),
            Some("test-google-client-secret")
        );

        // 3. BYO Zitadel refresh forwards user's own client credentials
        let res_zit = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/refresh").with_json(json!({
                "provider": "zitadel",
                "refreshToken": "byo_zitadel_refresh_token",
                "clientId": "byo-zitadel-client-id",
                "clientSecret": "byo-zitadel-client-secret",
                "zitadelDomain": "auth.ipv1337.dev",
                "isHosted": false,
            })),
        );
        assert_eq!(res_zit.status, 200);
        let calls = fetcher.recorded_calls();
        let zit_body = calls[2].opts.body.as_deref().unwrap();
        assert!(zit_body.contains("grant_type=refresh_token"));
        assert!(zit_body.contains("client_id=byo-zitadel-client-id"));
        assert!(zit_body.contains("client_secret=byo-zitadel-client-secret"));

        // 4. BYO GitLab revoke forwards user's own client credentials
        let res_gl_rev = app.handle_request(
            &HttpRequest::new("POST", "/api/oauth/revoke").with_json(json!({
                "provider": "gitlab",
                "token": "byo_access_token",
                "clientId": "byo-gitlab-client-id",
                "clientSecret": "byo-gitlab-client-secret",
                "isHosted": false,
            })),
        );
        assert_eq!(res_gl_rev.status, 200);
        let calls = fetcher.recorded_calls();
        let parsed_gl: Value =
            serde_json::from_str(calls[3].opts.body.as_deref().unwrap()).unwrap();
        assert_eq!(
            parsed_gl.get("client_id").and_then(Value::as_str),
            Some("byo-gitlab-client-id")
        );
        assert_eq!(
            parsed_gl.get("client_secret").and_then(Value::as_str),
            Some("byo-gitlab-client-secret")
        );
    }

    #[test]
    fn server_zitadel_hosted_init_and_explore() {
        let (app, fetcher) = build_standard_test_app();

        // BYO Zitadel token exchange attaches zitadel_domain
        let zit_tok = app.handle_request(&HttpRequest::new("POST", "/api/oauth/token").with_json(
            json!({
                "code": "valid_code",
                "provider": "zitadel",
                "clientId": "byo-zitadel-client-id",
                "clientSecret": "byo-zitadel-client-secret",
                "zitadelDomain": "auth.ipv1337.dev",
                "redirectUri": "http://localhost:3000",
                "isHosted": false,
            }),
        ));
        assert_eq!(zit_tok.status, 200);
        assert_eq!(
            zit_tok.json().get("zitadel_domain").and_then(Value::as_str),
            Some("auth.ipv1337.dev")
        );

        // Hosted init percent-encodes redirect_uri for Zitadel and GitHub
        let redirect_uri = "https://oauth-inspector.ipv1337.dev/";
        for prov in ["zitadel", "github"] {
            let init_res = app.handle_request(
                &HttpRequest::new("POST", "/api/oauth-hosted/init").with_json(json!({
                    "provider": prov,
                    "redirectUri": redirect_uri,
                })),
            );
            assert_eq!(init_res.status, 200);
            let auth_url = init_res
                .json()
                .get("authUrl")
                .and_then(Value::as_str)
                .unwrap()
                .to_string();
            assert!(auth_url.contains(&format!(
                "redirect_uri={}",
                encode_uri_component(redirect_uri)
            )));
            assert!(!auth_url.contains(&format!("redirect_uri={redirect_uri}")));
        }

        // Explore validation & fail-closed behavior
        let exp_missing =
            app.handle_request(&HttpRequest::new("POST", "/api/explore").with_json(json!({})));
        assert_eq!(exp_missing.status, 400);
        assert_eq!(
            exp_missing.json().get("error").and_then(Value::as_str),
            Some("Missing required fields: provider, accessToken, endpoint")
        );

        let exp_no_method =
            app.handle_request(&HttpRequest::new("POST", "/api/explore").with_json(json!({
                "provider": "github",
                "accessToken": "test_token",
                "endpoint": { "id": "user" },
            })));
        assert_eq!(exp_no_method.status, 400);
        assert_eq!(
            exp_no_method.json().get("error").and_then(Value::as_str),
            Some("Invalid endpoint: missing id or method")
        );

        let before_calls = fetcher.recorded_calls().len();
        let exp_unknown =
            app.handle_request(&HttpRequest::new("POST", "/api/explore").with_json(json!({
                "provider": "github",
                "accessToken": "test_token",
                "endpoint": {
                    "id": "totally-made-up",
                    "method": "GET",
                    "url": "https://api.github.com/user",
                },
            })));
        assert_eq!(exp_unknown.status, 400);
        assert_eq!(
            exp_unknown.json().get("error").and_then(Value::as_str),
            Some("unknown endpoint")
        );
        assert_eq!(fetcher.recorded_calls().len(), before_calls);

        let exp_ok =
            app.handle_request(&HttpRequest::new("POST", "/api/explore").with_json(json!({
                "provider": "github",
                "accessToken": "test_access_token",
                "endpoint": {
                    "id": "user",
                    "name": "Current User",
                    "url": "https://api.github.com/user",
                    "method": "GET",
                },
            })));
        assert_eq!(exp_ok.status, 200);
        assert_eq!(exp_ok.json().get("success"), Some(&Value::Bool(true)));
        assert_eq!(
            exp_ok.json().pointer("/data/login").and_then(Value::as_str),
            Some("testuser")
        );
        assert_eq!(
            fetcher.recorded_calls().last().unwrap().url,
            "https://api.github.com/user"
        );
    }

    // =========================================================================
    // 8. ssrf.test.ts
    // =========================================================================
    #[test]
    fn ssrf_resolve_and_pin_blocks_all_14_private_and_metadata_vectors() {
        let cases: &[(&str, &str, Vec<LookupAddress>)] = &[
            (
                "AWS/GCP instance metadata IPv4 (169.254.169.254)",
                "https://metadata.google.internal/computeMetadata/v1/",
                vec![LookupAddress::v4("169.254.169.254")],
            ),
            (
                "IPv4 loopback (127.0.0.1)",
                "https://localhost/oauth/token",
                vec![LookupAddress::v4("127.0.0.1")],
            ),
            (
                "RFC1918 10/8",
                "https://internal.corp/oauth/token",
                vec![LookupAddress::v4("10.0.0.1")],
            ),
            (
                "RFC1918 172.16/12",
                "https://internal.corp/oauth/token",
                vec![LookupAddress::v4("172.20.0.5")],
            ),
            (
                "RFC1918 192.168/16",
                "https://router.local/oauth/token",
                vec![LookupAddress::v4("192.168.1.1")],
            ),
            (
                "CGNAT / Tailscale 100.64/10",
                "https://tailnet-host/oauth/token",
                vec![LookupAddress::v4("100.64.0.1")],
            ),
            (
                "nip.io / sslip.io wildcard DNS resolving to 127.0.0.1",
                "https://127.0.0.1.nip.io/oauth/token",
                vec![LookupAddress::v4("127.0.0.1")],
            ),
            (
                "nip.io wildcard DNS resolving to metadata 169.254.169.254",
                "https://169-254-169-254.sslip.io/latest/meta-data/",
                vec![LookupAddress::v4("169.254.169.254")],
            ),
            (
                "IPv4-mapped IPv6 metadata (::ffff:169.254.169.254)",
                "https://v6-mapped.attacker.example/token",
                vec![LookupAddress::v6("::ffff:169.254.169.254")],
            ),
            (
                "IPv4-mapped IPv6 loopback (::ffff:127.0.0.1)",
                "https://v6-loopback.attacker.example/token",
                vec![LookupAddress::v6("::ffff:127.0.0.1")],
            ),
            (
                "0.0.0.0/8 'this network'",
                "https://zero.attacker.example/token",
                vec![LookupAddress::v4("0.0.0.0")],
            ),
            (
                "IPv6 loopback ::1",
                "https://ip6-localhost/token",
                vec![LookupAddress::v6("::1")],
            ),
            (
                "IPv6 unique-local fc00::/7 (fd00::1)",
                "https://ula.internal/token",
                vec![LookupAddress::v6("fd00::1")],
            ),
            (
                "IPv6 link-local fe80::/10",
                "https://ll.internal/token",
                vec![LookupAddress::v6("fe80::1")],
            ),
            (
                "round-robin DNS mixing a public IP with 127.0.0.1",
                "https://rebind.attacker.example/token",
                vec![
                    LookupAddress::v4("93.184.216.34"),
                    LookupAddress::v4("127.0.0.1"),
                ],
            ),
        ];

        for (label, url, records) in cases {
            let recs = records.clone();
            let err = resolve_and_pin_with(url, move |_| Ok(recs))
                .expect_err(&format!("expected SSRF block for {label}"));
            assert_eq!(err.message(), "Upstream request failed");
            assert!(
                err.reason.contains("Blocked IP address"),
                "unexpected reason for {label}: {}",
                err.reason
            );
        }

        // Plain http:// rejected before DNS lookup
        let mut called = false;
        let err = resolve_and_pin_with("http://example.com/oauth/token", |_| {
            called = true;
            Ok(vec![LookupAddress::v4("93.184.216.34")])
        })
        .unwrap_err();
        assert!(!called);
        assert!(err
            .reason
            .contains("Only https:// upstream URLs are allowed"));

        // Empty DNS records rejected
        let empty_err =
            resolve_and_pin_with("https://empty.example/token", |_| Ok(vec![])).unwrap_err();
        assert!(empty_err
            .reason
            .contains("DNS lookup returned no addresses"));

        // Unparseable URL rejected
        let invalid_err = resolve_and_pin_with("not a url", |_| Ok(vec![])).unwrap_err();
        assert!(invalid_err.reason.contains("Invalid upstream URL"));

        // Public IPv4 & IPv6 accepted
        let pin_v4 = resolve_and_pin_with(
            "https://idp.example.com:8443/oauth/v2/token?foo=bar",
            |_| Ok(vec![LookupAddress::v4("93.184.216.34")]),
        )
        .unwrap();
        assert_eq!(pin_v4.hostname, "idp.example.com");
        assert_eq!(pin_v4.port, 8443);
        assert_eq!(pin_v4.path_with_query, "/oauth/v2/token?foo=bar");
        assert_eq!(pin_v4.address, "93.184.216.34");
        assert_eq!(pin_v4.family, 4);

        let pin_v6 = resolve_and_pin_with("https://idp.example.com/oauth/v2/token", |_| {
            Ok(vec![LookupAddress::v6("2606:4700:4700::1111")])
        })
        .unwrap();
        assert_eq!(pin_v6.port, 443);
        assert_eq!(pin_v6.address, "2606:4700:4700::1111");
        assert_eq!(pin_v6.family, 6);

        assert!(vet_address("8.8.8.8"));
        assert!(vet_address("2606:4700:4700::1111"));
        assert!(!vet_address("255.255.255.255"));
        assert!(!vet_address("224.0.0.1"));
        assert!(!vet_address("not-an-ip"));
    }

    // =========================================================================
    // 9. userinfoRequest.test.ts & oauthSession.test.ts
    // =========================================================================
    #[test]
    fn userinfo_request_routes_linkedin_via_explore_proxy_and_others_direct() {
        let li = build_userinfo_request("linkedin", "tok-abc", &UserinfoRequestOptions::default())
            .unwrap();
        assert_eq!(li.mode, UserinfoFetchMode::Proxy);
        assert_eq!(li.url, "/api/explore");
        assert!(!li.url.contains("api.linkedin.com"));
        assert_eq!(li.init.method.as_deref(), Some("POST"));
        assert_eq!(
            li.init.headers.get("Content-Type").map(String::as_str),
            Some("application/json")
        );
        assert!(!li.init.headers.contains_key("Authorization"));
        let parsed: Value = serde_json::from_str(li.init.body.as_deref().unwrap()).unwrap();
        assert_eq!(
            parsed,
            json!({
                "provider": "linkedin",
                "accessToken": "tok-abc",
                "endpoint": { "id": "userinfo", "method": "GET" },
            })
        );

        let gh = build_userinfo_request("github", "t", &UserinfoRequestOptions::default()).unwrap();
        assert_eq!(gh.mode, UserinfoFetchMode::Direct);
        assert_eq!(gh.url, "https://api.github.com/user");
        assert!(gh.init.method.is_none());
        assert_eq!(
            gh.init
                .headers
                .get("X-GitHub-Api-Version")
                .map(String::as_str),
            Some("2022-11-28")
        );

        let goog =
            build_userinfo_request("google", "t", &UserinfoRequestOptions::default()).unwrap();
        assert_eq!(
            goog.url,
            "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"
        );

        let gl = build_userinfo_request("gitlab", "t", &UserinfoRequestOptions::default()).unwrap();
        assert_eq!(gl.url, "https://gitlab.com/api/v4/user");

        let a0 = build_userinfo_request(
            "auth0",
            "t",
            &UserinfoRequestOptions {
                auth0_domain: Some("acme.us.auth0.com".to_string()),
                zitadel_domain: None,
            },
        )
        .unwrap();
        assert_eq!(a0.url, "https://acme.us.auth0.com/userinfo");

        let zit = build_userinfo_request(
            "zitadel",
            "t",
            &UserinfoRequestOptions {
                auth0_domain: None,
                zitadel_domain: Some("auth.ipv1337.dev".to_string()),
            },
        )
        .unwrap();
        assert_eq!(zit.url, "https://auth.ipv1337.dev/oidc/v1/userinfo");

        assert!(build_userinfo_request("auth0", "t", &UserinfoRequestOptions::default()).is_err());
        assert!(
            build_userinfo_request("zitadel", "t", &UserinfoRequestOptions::default()).is_err()
        );
    }

    #[test]
    fn oauth_session_resolves_callback_parameters_and_validates_state() {
        let resolved = resolve_oauth_session(OAuthSessionInputs {
            url_provider: None,
            saved_provider: Some("google".to_string()),
            pkce_code_verifier: Some("pkce-verifier-123".to_string()),
            explicit_redirect_uri: None,
            saved_redirect_uri: Some("https://inspector.example.com/callback".to_string()),
            origin: "https://inspector.example.com".to_string(),
            saved_client_id: Some("my-client-id".to_string()),
            saved_client_secret: Some("my-client-secret".to_string()),
            saved_zitadel_domain: Some("auth.example.zitadel.cloud".to_string()),
            returned_state: Some("state-abc".to_string()),
            expected_state: Some("state-abc".to_string()),
        });
        assert_eq!(resolved.provider.as_deref(), Some("google"));
        assert_eq!(resolved.code_verifier.as_deref(), Some("pkce-verifier-123"));
        assert_eq!(
            resolved.redirect_uri,
            "https://inspector.example.com/callback"
        );
        assert!(resolved.state_valid);

        let mismatch = resolve_oauth_session(OAuthSessionInputs {
            url_provider: Some("github".to_string()),
            saved_provider: Some("google".to_string()),
            pkce_code_verifier: None,
            explicit_redirect_uri: None,
            saved_redirect_uri: None,
            origin: "https://inspector.example.com".to_string(),
            saved_client_id: None,
            saved_client_secret: None,
            saved_zitadel_domain: None,
            returned_state: Some("forged".to_string()),
            expected_state: Some("expected".to_string()),
        });
        assert_eq!(mismatch.provider.as_deref(), Some("github"));
        assert_eq!(mismatch.redirect_uri, "https://inspector.example.com");
        assert!(!mismatch.state_valid);
    }
}
