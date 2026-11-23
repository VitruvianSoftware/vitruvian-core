// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! The app sign-in's HTTP side: discovery, registration and the app URL.

use http::StatusCode;
use serde_json::{json, Value};

use crate::http::tests::{app_harness, harness, Harness, Reply, ALICE, BOB, PUBLIC_URL};

const ID: &str = "089fb14b828289a2178722b6";
const OTHER_ID: &str = "119fb14b828289a2178722b6";
const JSON_CT: (&str, &str) = ("content-type", "application/json");

fn six(id: &str) -> Vec<String> {
    let mut out = Vec::new();
    for host in [
        "oauth-redirect",
        "oauth-redirect-sandbox",
        "oauth-redirect-test",
    ] {
        for kind in ["r", "a"] {
            out.push(format!(
                "https://{host}.googleusercontent.com/{kind}/user_bound_custom-mcp-{id}"
            ));
        }
    }
    out
}

/// What Gemini sent in the real probe.
fn gemini_body() -> Value {
    json!({
        "client_name": "Google",
        "redirect_uris": six(ID),
        "token_endpoint_auth_method": "client_secret_post",
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
    })
}

async fn register(h: &Harness, ip: Option<&str>, body: &str) -> Reply {
    let mut headers = vec![(JSON_CT.0, JSON_CT.1.to_string())];
    if let Some(ip) = ip {
        headers.push(("cf-connecting-ip", ip.to_string()));
    }
    h.send("POST", "/oauth/register", &headers, body).await
}

#[tokio::test]
async fn app_prm_names_the_relay() {
    let h = app_harness().await;
    let r = h
        .get("/.well-known/oauth-protected-resource/mcp/app/dev-1")
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(
        r.json(),
        json!({
            "resource": format!("{PUBLIC_URL}/mcp/app/dev-1"),
            "authorization_servers": [PUBLIC_URL],
            "bearer_methods_supported": ["header"],
            "scopes_supported": ["mcp:tools"],
        })
    );
    // A malformed id is a plain 404, as for the device document.
    let bad = h
        .get("/.well-known/oauth-protected-resource/mcp/app/not%20an%20id")
        .await;
    assert_eq!(bad.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn device_prm_still_names_zitadel() {
    let h = app_harness().await;
    let r = h
        .get("/.well-known/oauth-protected-resource/mcp/d/dev-1")
        .await;
    assert_eq!(r.status, StatusCode::OK);
    let doc = r.json();
    assert_eq!(doc["resource"], format!("{PUBLIC_URL}/mcp/d/dev-1"));
    assert_eq!(
        doc["authorization_servers"],
        json!(["https://auth.example.test"])
    );
    assert!(doc.get("bearer_methods_supported").is_none());
}

#[tokio::test]
async fn as_metadata_lists_register_authorize_token_s256_and_client_secret_post() {
    let h = app_harness().await;
    let r = h.get("/.well-known/oauth-authorization-server").await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(
        r.json(),
        json!({
            "issuer": PUBLIC_URL,
            "authorization_endpoint": format!("{PUBLIC_URL}/oauth/authorize"),
            "token_endpoint": format!("{PUBLIC_URL}/oauth/token"),
            "registration_endpoint": format!("{PUBLIC_URL}/oauth/register"),
            "response_types_supported": ["code"],
            "grant_types_supported": ["authorization_code", "refresh_token"],
            "code_challenge_methods_supported": ["S256"],
            "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic"],
            "scopes_supported": ["mcp:tools"],
        })
    );
}

#[tokio::test]
async fn app_url_401_points_at_app_metadata() {
    let h = app_harness().await;
    let r = h
        .send("POST", "/mcp/app/dev-1", &[JSON_CT_OWNED()], "{}")
        .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    let challenge = r.header("www-authenticate").expect("a challenge");
    assert!(
        challenge.contains(&format!(
            "resource_metadata=\"{PUBLIC_URL}/.well-known/oauth-protected-resource/mcp/app/dev-1\""
        )),
        "{challenge}"
    );
    // The device URL is unchanged: it still points at its own document.
    let d = h
        .send("POST", "/mcp/d/dev-1", &[JSON_CT_OWNED()], "{}")
        .await;
    let challenge = d.header("www-authenticate").unwrap();
    assert!(
        challenge.contains("/.well-known/oauth-protected-resource/mcp/d/dev-1\""),
        "{challenge}"
    );
}

#[allow(non_snake_case)]
fn JSON_CT_OWNED() -> (&'static str, String) {
    (JSON_CT.0, JSON_CT.1.to_string())
}

#[tokio::test]
async fn app_url_serves_the_owner_and_hides_other_peoples_devices() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let init = json!({"jsonrpc": "2.0", "id": 1, "method": "initialize"}).to_string();
    let path = format!("/mcp/app/{device}");
    let mine = h
        .send("POST", &path, &h.mcp_headers(ALICE, None), &init)
        .await;
    assert_eq!(mine.status, StatusCode::OK, "{}", mine.body);
    assert!(mine.header("mcp-session-id").is_some());
    let theirs = h
        .send("POST", &path, &h.mcp_headers(BOB, None), &init)
        .await;
    assert_eq!(theirs.status, StatusCode::NOT_FOUND);
    let get = h.send("GET", &path, &[], "").await;
    assert_eq!(get.status, StatusCode::METHOD_NOT_ALLOWED);
}

#[tokio::test]
async fn register_returns_201_with_client_and_secret() {
    let h = app_harness().await;
    let r = register(&h, Some("203.0.113.9"), &gemini_body().to_string()).await;
    assert_eq!(r.status, StatusCode::CREATED, "{}", r.body);
    assert_eq!(r.header("cache-control").as_deref(), Some("no-store"));
    let doc = r.json();
    assert_eq!(doc["client_name"], "Google");
    assert_eq!(doc["redirect_uris"], json!(six(ID)));
    assert_eq!(
        doc["grant_types"],
        json!(["authorization_code", "refresh_token"])
    );
    assert_eq!(doc["response_types"], json!(["code"]));
    assert_eq!(doc["token_endpoint_auth_method"], "client_secret_post");
    assert_eq!(doc["client_secret_expires_at"], 0);
    assert!(doc["client_id_issued_at"].as_u64().unwrap() > 1_700_000_000);
    let client_id = doc["client_id"].as_str().unwrap();
    let secret = doc["client_secret"].as_str().unwrap();
    // The pair is the one the server key derives for that callback id.
    let keys = &h.app.settings.app_signin.as_ref().unwrap().keys;
    assert_eq!(keys.client_callback_id(client_id).as_deref(), Some(ID));
    assert!(keys.secret_ok(client_id, secret));
    // Nothing is stored: the same request gives the same pair.
    let again = register(&h, Some("203.0.113.9"), &gemini_body().to_string()).await;
    assert_eq!(again.json()["client_id"], client_id);
}

#[tokio::test]
async fn register_refuses_foreign_callback_with_invalid_redirect_uri() {
    let h = app_harness().await;
    let mut mixed = six(ID);
    mixed[1] = six(OTHER_ID)[1].clone();
    let cases = [
        json!({"redirect_uris": ["https://evil.example/cb"]}),
        json!({"redirect_uris": []}),
        json!({"client_name": "x"}),
        json!({"redirect_uris": mixed}),
    ];
    for body in cases {
        let r = register(&h, Some("203.0.113.10"), &body.to_string()).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{body}");
        assert_eq!(r.json(), json!({"error": "invalid_redirect_uri"}), "{body}");
    }
    // Wrong shapes are bad metadata, not a bad redirect.
    for body in [
        "not json".to_string(),
        "[1]".to_string(),
        json!({"redirect_uris": "https://x"}).to_string(),
        json!({"redirect_uris": [1]}).to_string(),
        json!({"redirect_uris": six(ID), "grant_types": ["implicit"]}).to_string(),
        json!({"redirect_uris": six(ID), "token_endpoint_auth_method": "none"}).to_string(),
        json!({"redirect_uris": six(ID), "client_name": 5}).to_string(),
    ] {
        let r = register(&h, Some("203.0.113.12"), &body).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{body}");
        assert_eq!(
            r.json(),
            json!({"error": "invalid_client_metadata"}),
            "{body}"
        );
    }
}

#[tokio::test]
async fn register_body_over_16k_is_refused() {
    let h = app_harness().await;
    let big = json!({"redirect_uris": six(ID), "client_name": "x".repeat(17 * 1024)});
    let r = register(&h, Some("203.0.113.11"), &big.to_string()).await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE, "{}", r.body);
    // Just under the limit still reads (and is then judged on its content).
    let ok = json!({"redirect_uris": six(ID), "client_name": "x".repeat(15 * 1024)});
    let r = register(&h, Some("203.0.113.11"), &ok.to_string()).await;
    assert_eq!(r.status, StatusCode::CREATED, "{}", r.body);
}

#[tokio::test]
async fn register_is_rate_limited_per_ip() {
    let h = app_harness().await;
    let body = gemini_body().to_string();
    for i in 1..=10 {
        let r = register(&h, Some("198.51.100.1"), &body).await;
        assert_eq!(r.status, StatusCode::CREATED, "call {i}");
    }
    let refused = register(&h, Some("198.51.100.1"), &body).await;
    assert_eq!(refused.status, StatusCode::TOO_MANY_REQUESTS);
    assert!(refused.header("retry-after").is_some());
    // Someone else is not held up.
    let other = register(&h, Some("198.51.100.2"), &body).await;
    assert_eq!(other.status, StatusCode::CREATED);
    // Two addresses in one IPv6 /64 share a bucket.
    for i in 1..=10 {
        let r = register(&h, Some(&format!("2001:db8:1:2::{i}")), &body).await;
        assert_eq!(r.status, StatusCode::CREATED, "v6 call {i}");
    }
    let v6 = register(&h, Some("2001:db8:1:2:ffff::1"), &body).await;
    assert_eq!(v6.status, StatusCode::TOO_MANY_REQUESTS);
    // No usable address (or a made-up one) all land in one shared bucket.
    for junk in [None, Some("not-an-ip"), Some("")] {
        let _ = register(&h, junk, &body).await;
    }
    let mut refused_unknown = false;
    for _ in 0..10 {
        let r = register(&h, None, &body).await;
        refused_unknown |= r.status == StatusCode::TOO_MANY_REQUESTS;
    }
    assert!(refused_unknown, "the unknown bucket runs out");
}

#[tokio::test]
async fn feature_off_every_new_path_is_404() {
    let h = harness().await;
    let body = gemini_body().to_string();
    for (method, path) in [
        ("GET", "/.well-known/oauth-authorization-server"),
        ("GET", "/.well-known/oauth-protected-resource/mcp/app/dev-1"),
        ("POST", "/mcp/app/dev-1"),
        ("GET", "/mcp/app/dev-1"),
        ("POST", "/oauth/register"),
        ("GET", "/oauth/authorize"),
        ("GET", "/oauth/callback"),
        ("POST", "/oauth/consent"),
        ("POST", "/oauth/token"),
    ] {
        let r = h.send(method, path, &[JSON_CT_OWNED()], &body).await;
        assert_eq!(r.status, StatusCode::NOT_FOUND, "{method} {path}");
        assert_eq!(r.body, "not found", "{method} {path}");
    }
}

#[tokio::test]
async fn later_endpoints_answer_501_when_on() {
    let h = app_harness().await;
    for (method, path) in [
        ("GET", "/oauth/authorize"),
        ("GET", "/oauth/callback"),
        ("POST", "/oauth/consent"),
        ("POST", "/oauth/token"),
    ] {
        let r = h.send(method, path, &[], "").await;
        assert_eq!(r.status, StatusCode::NOT_IMPLEMENTED, "{method} {path}");
    }
    let wrong = h.send("GET", "/oauth/register", &[], "").await;
    assert_eq!(wrong.status, StatusCode::METHOD_NOT_ALLOWED);
    let wrong = h
        .send("POST", "/.well-known/oauth-authorization-server", &[], "")
        .await;
    assert_eq!(wrong.status, StatusCode::METHOD_NOT_ALLOWED);
}
