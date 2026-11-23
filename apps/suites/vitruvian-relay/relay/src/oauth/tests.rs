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

//! The app sign-in's HTTP side: discovery, registration, the app URL, and
//! the sign-in and consent steps.

use http::StatusCode;
use serde_json::{json, Value};

use super::production_callback;
use crate::dashboard::form_encode;
use crate::dashboard::pages::esc;
use crate::dashboard::parse_pairs;
use crate::dashboard::session::challenge_for;
use crate::http::tests::{
    app_harness, app_harness_with, harness, mint_with_role, now_secs, Harness, Reply, ALICE,
    APPS_CLIENT, BOB, ISSUER, PUBLIC_URL,
};
use crate::http::Timing;
use ring::signature::KeyPair;

const ID: &str = "089fb14b828289a2178722b6";
const OTHER_ID: &str = "119fb14b828289a2178722b6";

fn json_ct() -> (&'static str, String) {
    ("content-type", "application/json".to_string())
}

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
    let mut headers = vec![json_ct()];
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
    let r = h.send("POST", "/mcp/app/dev-1", &[json_ct()], "{}").await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    let challenge = r.header("www-authenticate").expect("a challenge");
    assert!(
        challenge.contains(&format!(
            "resource_metadata=\"{PUBLIC_URL}/.well-known/oauth-protected-resource/mcp/app/dev-1\""
        )),
        "{challenge}"
    );
    // The device URL is unchanged: it still points at its own document.
    let d = h.send("POST", "/mcp/d/dev-1", &[json_ct()], "{}").await;
    let challenge = d.header("www-authenticate").unwrap();
    assert!(
        challenge.contains("/.well-known/oauth-protected-resource/mcp/d/dev-1\""),
        "{challenge}"
    );
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
    // A missing header, a made-up value and an empty one share one bucket:
    // ten requests in any mix get through and the 11th is the first refused.
    let junk = [None, Some("not-an-ip"), Some("")];
    for i in 1..=10 {
        let r = register(&h, junk[i % 3], &body).await;
        assert_eq!(r.status, StatusCode::CREATED, "unknown call {i}");
    }
    for (n, form) in junk.iter().enumerate() {
        let r = register(&h, *form, &body).await;
        assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS, "unknown form {n}");
    }
    // An IPv4-mapped IPv6 address shares the plain IPv4 address's bucket.
    for i in 1..=10 {
        let ip = if i % 2 == 0 {
            "192.0.2.7"
        } else {
            "::ffff:192.0.2.7"
        };
        let r = register(&h, Some(ip), &body).await;
        assert_eq!(r.status, StatusCode::CREATED, "mapped call {i}");
    }
    for ip in ["192.0.2.7", "::ffff:192.0.2.7"] {
        let r = register(&h, Some(ip), &body).await;
        assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS, "{ip}");
    }
}

#[tokio::test]
async fn register_always_answers_client_secret_post() {
    let h = app_harness().await;
    for (n, method) in [
        None,
        Some("client_secret_post"),
        Some("client_secret_basic"),
    ]
    .into_iter()
    .enumerate()
    {
        let mut body = gemini_body();
        match method {
            Some(m) => body["token_endpoint_auth_method"] = json!(m),
            None => {
                body.as_object_mut()
                    .unwrap()
                    .remove("token_endpoint_auth_method");
            }
        }
        let r = register(
            &h,
            Some(&format!("203.0.113.{}", 40 + n)),
            &body.to_string(),
        )
        .await;
        assert_eq!(r.status, StatusCode::CREATED, "{method:?}: {}", r.body);
        assert_eq!(
            r.json()["token_endpoint_auth_method"],
            "client_secret_post",
            "{method:?}"
        );
    }
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
        let r = h.send(method, path, &[json_ct()], &body).await;
        assert_eq!(r.status, StatusCode::NOT_FOUND, "{method} {path}");
        assert_eq!(r.body, "not found", "{method} {path}");
    }
}

#[tokio::test]
async fn later_endpoints_answer_501_when_on() {
    let h = app_harness().await;
    for (method, path) in [("POST", "/oauth/token")] {
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

// ------------------------------------------------------ sign-in and consent

/// A PKCE verifier from RFC 7636 appendix B, and the app's own `state`.
const VERIFIER: &str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
const APP_STATE: &str = "gemini-state-123";
const ZITADEL_CODE: &str = "zitadel-code-1";
const ACCESS: &str = "ACCESS-TOKEN-VALUE";
const REFRESH: &str = "REFRESH-TOKEN-VALUE";

fn client_id(h: &Harness) -> String {
    h.app
        .settings
        .app_signin
        .as_ref()
        .unwrap()
        .keys
        .issue_client(ID)
        .0
}

/// What a well-formed `/oauth/authorize` carries, for `device`.
fn good_query(h: &Harness, device: &str) -> Vec<(&'static str, String)> {
    vec![
        ("client_id", client_id(h)),
        ("redirect_uri", production_callback(ID)),
        ("response_type", "code".into()),
        ("code_challenge", challenge_for(VERIFIER)),
        ("code_challenge_method", "S256".into()),
        ("resource", format!("{PUBLIC_URL}/mcp/app/{device}")),
        ("state", APP_STATE.into()),
        ("scope", "mcp:tools".into()),
    ]
}

/// `pairs` with `key` set to `value`, or removed when `None`.
fn with(
    mut pairs: Vec<(&'static str, String)>,
    key: &'static str,
    value: Option<&str>,
) -> Vec<(&'static str, String)> {
    pairs.retain(|(k, _)| *k != key);
    if let Some(v) = value {
        pairs.push((key, v.to_string()));
    }
    pairs
}

fn authorize_path(pairs: &[(&str, String)]) -> String {
    let q: Vec<String> = pairs
        .iter()
        .map(|(k, v)| format!("{k}={}", form_encode(v)))
        .collect();
    format!("/oauth/authorize?{}", q.join("&"))
}

fn param(url: &str, key: &str) -> Option<String> {
    parse_pairs(url.split_once('?').map_or("", |(_, q)| q)).remove(key)
}

/// `name=value` of the cookie a response sets.
fn set_cookie(r: &Reply, name: &str) -> Option<String> {
    r.headers
        .get_all("set-cookie")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .find(|c| c.starts_with(&format!("{name}=")))
        .map(String::from)
}

fn cookie_pair(set_cookie: &str) -> String {
    set_cookie.split(';').next().unwrap().to_string()
}

/// A browser part-way through: its `vr_oauth` cookie, and what it was sent
/// to the identity service with.
struct Started {
    cookie: String,
    state: String,
    challenge: String,
}

async fn start(h: &Harness, device: &str) -> Started {
    start_with(h, &good_query(h, device)).await
}

async fn start_with(h: &Harness, pairs: &[(&str, String)]) -> Started {
    let r = h.get(&authorize_path(pairs)).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let location = r.header("location").unwrap();
    Started {
        cookie: cookie_pair(&set_cookie(&r, "vr_oauth").expect("the sign-in is bound")),
        state: param(&location, "state").expect("state is sent"),
        challenge: param(&location, "code_challenge").expect("a challenge is sent"),
    }
}

fn app_token(h: &Harness, sub: &str, role: Option<&str>) -> String {
    mint_with_role(&h.rsa, APPS_CLIENT, sub, Some(now_secs() + 600), role)
}

/// The identity service sends the browser back to the callback.
async fn come_back(h: &Harness, st: &Started, token: &str) -> Reply {
    h.tokens.give_tokens(token, REFRESH);
    h.send(
        "GET",
        &format!(
            "/oauth/callback?code={ZITADEL_CODE}&state={}",
            form_encode(&st.state)
        ),
        &[("cookie", st.cookie.clone())],
        "",
    )
    .await
}

async fn consent_get(h: &Harness, cookie: &str) -> Reply {
    h.send(
        "GET",
        "/oauth/consent",
        &[("cookie", cookie.to_string())],
        "",
    )
    .await
}

fn csrf_in(page: &str) -> String {
    page.split("name=\"csrf\" value=\"")
        .nth(1)
        .expect("the page has a form with a token")
        .split('"')
        .next()
        .unwrap()
        .to_string()
}

/// A person who owns a computer goes through authorize and the callback and
/// is shown the consent page. Returns the browser and the page's form token.
async fn at_consent(h: &Harness, sub: &str, name: &str) -> (Started, String, String) {
    let reg = h
        .register_body(
            sub,
            &json!({"public_key": crate::http::tests::b64(crate::http::tests::ed25519().public_key().as_ref()), "name": name}).to_string(),
        )
        .await;
    assert_eq!(reg.status, StatusCode::OK, "{}", reg.body);
    let device = reg.json()["device_id"].as_str().unwrap().to_string();
    let st = start(h, &device).await;
    let r = come_back(h, &st, &app_token(h, sub, Some("relay-user"))).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    assert_eq!(r.header("location").as_deref(), Some("/oauth/consent"));
    let page = consent_get(h, &st.cookie).await;
    assert_eq!(page.status, StatusCode::OK, "{}", page.body);
    let csrf = csrf_in(&page.body);
    (st, csrf, device)
}

/// A post to the consent form. `None` leaves that part out.
async fn decide(
    h: &Harness,
    cookie: Option<&str>,
    origin: Option<&str>,
    csrf: Option<&str>,
    decision: &str,
) -> Reply {
    let mut headers = vec![(
        "content-type",
        "application/x-www-form-urlencoded".to_string(),
    )];
    if let Some(c) = cookie {
        headers.push(("cookie", c.to_string()));
    }
    if let Some(o) = origin {
        headers.push(("origin", o.to_string()));
    }
    let mut body = format!("decision={decision}");
    if let Some(t) = csrf {
        body.push_str(&format!("&csrf={}", form_encode(t)));
    }
    h.send("POST", "/oauth/consent", &headers, &body).await
}

fn codes_held(h: &Harness) -> usize {
    h.app.pending.counts().2
}

fn consents_held(h: &Harness) -> usize {
    h.app.pending.counts().1
}

fn no_redirect(r: &Reply) {
    assert!(
        r.header("location").is_none(),
        "redirected: {r:?}",
        r = r.headers
    );
    assert!(r.header("set-cookie").is_none(), "set a cookie");
}

#[tokio::test]
async fn authorize_redirects_to_zitadel_with_fixed_callback_and_own_pkce() {
    let h = app_harness().await;
    let r = h.get(&authorize_path(&good_query(&h, "dev-1"))).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let to = r.header("location").unwrap();
    assert!(
        to.starts_with(&format!("{ISSUER}/oauth/v2/authorize?")),
        "{to}"
    );
    assert_eq!(param(&to, "response_type").as_deref(), Some("code"));
    assert_eq!(param(&to, "client_id").as_deref(), Some(APPS_CLIENT));
    assert_eq!(
        param(&to, "redirect_uri").as_deref(),
        Some(format!("{PUBLIC_URL}/oauth/callback").as_str())
    );
    assert_eq!(
        param(&to, "scope").as_deref(),
        Some("openid offline_access urn:zitadel:iam:org:project:id:123456789:aud")
    );
    assert_eq!(param(&to, "prompt").as_deref(), Some("select_account"));
    assert_eq!(param(&to, "code_challenge_method").as_deref(), Some("S256"));
    // The relay's own PKCE and state, never the app's.
    assert_ne!(
        param(&to, "code_challenge"),
        Some(challenge_for(VERIFIER)),
        "the app's challenge went upstream"
    );
    assert_ne!(param(&to, "state").as_deref(), Some(APP_STATE));
    assert!(!to.contains(APP_STATE) && !to.contains(ID), "{to}");
    // Bound to this browser.
    let cookie = set_cookie(&r, "vr_oauth").expect("a binding cookie");
    assert!(
        cookie.ends_with("; HttpOnly; Secure; SameSite=Lax; Path=/oauth/; Max-Age=600"),
        "{cookie}"
    );
    let value = cookie_pair(&cookie);
    assert!(value.len() > "vr_oauth=".len() + 40, "{value}");
    // A second sign-in gets different secrets.
    let second = start(&h, "dev-1").await;
    assert_ne!(second.state, param(&to, "state").unwrap());
    assert_ne!(second.cookie, value);
    // Sent on in the identity service's own form.
    assert!(r.header("cache-control").as_deref() == Some("no-store"));
}

#[tokio::test]
async fn authorize_uses_the_relays_challenge_when_exchanging() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let st = start(&h, &device).await;
    let r = come_back(&h, &st, &app_token(&h, ALICE, Some("relay-user"))).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let sent = h.tokens.requests();
    assert_eq!(sent.len(), 1, "{sent:?}");
    let form = parse_pairs(&sent[0]);
    assert_eq!(form["grant_type"], "authorization_code");
    assert_eq!(form["code"], ZITADEL_CODE);
    assert_eq!(form["client_id"], APPS_CLIENT);
    assert_eq!(form["redirect_uri"], format!("{PUBLIC_URL}/oauth/callback"));
    // The verifier the relay holds is the one behind the challenge it sent.
    assert_eq!(challenge_for(&form["code_verifier"]), st.challenge);
    assert_ne!(form["code_verifier"], VERIFIER);
}

#[tokio::test]
async fn authorize_refuses_sandbox_callback_without_redirecting() {
    let h = app_harness().await;
    for uri in [
        "https://oauth-redirect-sandbox.googleusercontent.com/r/user_bound_custom-mcp-089fb14b828289a2178722b6",
        "https://oauth-redirect-test.googleusercontent.com/a/user_bound_custom-mcp-089fb14b828289a2178722b6",
        "https://oauth-redirect.googleusercontent.com/a/user_bound_custom-mcp-089fb14b828289a2178722b6",
        "https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-119fb14b828289a2178722b6",
        "https://evil.example/cb",
        "",
    ] {
        let q = with(good_query(&h, "dev-1"), "redirect_uri", Some(uri));
        let r = h.get(&authorize_path(&q)).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{uri}: {}", r.body);
        no_redirect(&r);
    }
    let q = with(good_query(&h, "dev-1"), "redirect_uri", None);
    let r = h.get(&authorize_path(&q)).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    no_redirect(&r);
    assert_eq!(h.app.pending.counts(), (0, 0, 0), "nothing was stored");
}

#[tokio::test]
async fn authorize_refuses_unknown_client_without_redirecting() {
    let h = app_harness().await;
    let real = client_id(&h);
    let forged = format!("{}x", real);
    let (head, _) = real.rsplit_once('.').unwrap();
    for id in [
        "no-such-client",
        forged.as_str(),
        &format!("{head}.AAAA"),
        "",
    ] {
        let q = with(good_query(&h, "dev-1"), "client_id", Some(id));
        let r = h.get(&authorize_path(&q)).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{id}: {}", r.body);
        no_redirect(&r);
    }
    let q = with(good_query(&h, "dev-1"), "client_id", None);
    let r = h.get(&authorize_path(&q)).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    no_redirect(&r);
    // The same request with the right client does start.
    assert_eq!(
        h.get(&authorize_path(&good_query(&h, "dev-1")))
            .await
            .status,
        StatusCode::SEE_OTHER
    );
    // A repeated name is ambiguous: refused, no redirect.
    let dup = format!(
        "{}&redirect_uri=https%3A%2F%2Fevil.example%2F",
        authorize_path(&good_query(&h, "dev-1"))
    );
    let r = h.get(&dup).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    no_redirect(&r);
}

#[tokio::test]
async fn authorize_refuses_plain_pkce() {
    let h = app_harness().await;
    let callback = production_callback(ID);
    let cases = [
        with(
            good_query(&h, "dev-1"),
            "code_challenge_method",
            Some("plain"),
        ),
        with(
            good_query(&h, "dev-1"),
            "code_challenge_method",
            Some("s256"),
        ),
        with(good_query(&h, "dev-1"), "code_challenge_method", None),
        with(good_query(&h, "dev-1"), "code_challenge", None),
        with(
            good_query(&h, "dev-1"),
            "code_challenge",
            Some(&"a".repeat(42)),
        ),
        with(
            good_query(&h, "dev-1"),
            "code_challenge",
            Some(&"a".repeat(129)),
        ),
        with(
            good_query(&h, "dev-1"),
            "code_challenge",
            Some(&format!("{}+/=", "a".repeat(43))),
        ),
    ];
    for q in cases {
        let r = h.get(&authorize_path(&q)).await;
        assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
        let to = r.header("location").unwrap();
        // Back to the app's own callback with an error and its state: never
        // on to the identity service, and no sign-in is bound.
        assert!(
            to.starts_with(&format!("{callback}?error=invalid_request")),
            "{to}"
        );
        assert_eq!(param(&to, "state").as_deref(), Some(APP_STATE));
        assert!(!to.contains("code="), "{to}");
        assert!(set_cookie(&r, "vr_oauth").is_none());
    }
    // The longest allowed challenge is fine.
    let ok = with(
        good_query(&h, "dev-1"),
        "code_challenge",
        Some(&"a".repeat(128)),
    );
    assert_eq!(
        h.get(&authorize_path(&ok))
            .await
            .header("location")
            .map(|l| l.starts_with(ISSUER)),
        Some(true)
    );
    assert_eq!(h.app.pending.counts().0, 1, "only the good one was stored");
}

#[tokio::test]
async fn authorize_refuses_resource_for_another_host() {
    let h = app_harness().await;
    let callback = production_callback(ID);
    for resource in [
        "https://evil.example/mcp/app/dev-1".to_string(),
        "https://relay.example.test.evil.example/mcp/app/dev-1".to_string(),
        // The device URL is for Claude, not for apps.
        format!("{PUBLIC_URL}/mcp/d/dev-1"),
        format!("{PUBLIC_URL}/mcp/app/dev-1/"),
        format!("{PUBLIC_URL}/mcp/app/dev-1?x=1"),
        format!("{PUBLIC_URL}/mcp/app/not%20an%20id"),
        format!("{PUBLIC_URL}/mcp/app/"),
        format!("{PUBLIC_URL}/mcp/app/{}", "d".repeat(65)),
        format!("{PUBLIC_URL}/mcp/app/dev-1#frag"),
        PUBLIC_URL.to_string(),
        "http://relay.example.test/mcp/app/dev-1".to_string(),
    ] {
        let q = with(good_query(&h, "dev-1"), "resource", Some(&resource));
        let r = h.get(&authorize_path(&q)).await;
        assert_eq!(r.status, StatusCode::SEE_OTHER, "{resource}: {}", r.body);
        let to = r.header("location").unwrap();
        assert!(
            to.starts_with(&format!("{callback}?error=invalid_target")),
            "{resource}: {to}"
        );
        assert!(set_cookie(&r, "vr_oauth").is_none());
    }
    let q = with(good_query(&h, "dev-1"), "resource", None);
    let r = h.get(&authorize_path(&q)).await;
    assert!(r
        .header("location")
        .unwrap()
        .contains("error=invalid_target"));
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
}

#[tokio::test]
async fn authorize_needs_code_response_type_and_a_reasonable_state() {
    let h = app_harness().await;
    let callback = production_callback(ID);
    let r = h
        .get(&authorize_path(&with(
            good_query(&h, "dev-1"),
            "response_type",
            Some("token"),
        )))
        .await;
    assert!(r
        .header("location")
        .unwrap()
        .starts_with(&format!("{callback}?error=unsupported_response_type")));
    // A missing or oversized state is refused and not echoed.
    for state in [None, Some(""), Some(&*"s".repeat(1025))] {
        let r = h
            .get(&authorize_path(&with(
                good_query(&h, "dev-1"),
                "state",
                state,
            )))
            .await;
        let to = r.header("location").unwrap();
        assert_eq!(to, format!("{callback}?error=invalid_request"), "{state:?}");
    }
    // The longest allowed state starts a sign-in.
    let long = "s".repeat(1024);
    let r = h
        .get(&authorize_path(&with(
            good_query(&h, "dev-1"),
            "state",
            Some(&long),
        )))
        .await;
    assert!(r.header("location").unwrap().starts_with(ISSUER));
}

#[tokio::test]
async fn authorize_is_rate_limited_per_ip() {
    let h = app_harness().await;
    let path = authorize_path(&good_query(&h, "dev-1"));
    let from = |ip: &str| vec![("cf-connecting-ip", ip.to_string())];
    for i in 1..=30 {
        let r = h.send("GET", &path, &from("198.51.100.20"), "").await;
        assert_eq!(r.status, StatusCode::SEE_OTHER, "call {i}");
    }
    let refused = h.send("GET", &path, &from("198.51.100.20"), "").await;
    assert_eq!(refused.status, StatusCode::TOO_MANY_REQUESTS);
    assert!(refused.header("retry-after").is_some());
    no_redirect_cookie_free(&refused);
    let other = h.send("GET", &path, &from("198.51.100.21"), "").await;
    assert_eq!(other.status, StatusCode::SEE_OTHER);
}

fn no_redirect_cookie_free(r: &Reply) {
    assert!(r.header("location").is_none());
    assert!(r.header("set-cookie").is_none());
}

#[tokio::test]
async fn only_get_starts_a_sign_in() {
    let h = app_harness().await;
    for (method, path) in [
        ("POST", "/oauth/authorize"),
        ("POST", "/oauth/callback"),
        ("PUT", "/oauth/consent"),
        ("DELETE", "/oauth/consent"),
    ] {
        let r = h.send(method, path, &[], "").await;
        assert_eq!(r.status, StatusCode::METHOD_NOT_ALLOWED, "{method} {path}");
    }
}

#[tokio::test]
async fn callback_without_role_never_shows_consent() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let st = start(&h, &device).await;
    // Signed in, but never invited: no `relay-user` role.
    let r = come_back(&h, &st, &app_token(&h, ALICE, None)).await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    assert!(r.body.contains("You do not have access yet"), "{}", r.body);
    assert!(r.header("location").is_none());
    assert!(!r.body.contains("Allow"), "{}", r.body);
    assert_eq!(h.app.pending.counts(), (0, 0, 0), "no consent, no code");
    let page = consent_get(&h, &st.cookie).await;
    assert_eq!(page.status, StatusCode::BAD_REQUEST);
    assert!(!page.body.contains("Allow"));
    // A token for a different client (Claude's) is not accepted either.
    let st = start(&h, &device).await;
    let claude = crate::http::tests::mint(&h.rsa, crate::http::tests::MCP_CLIENT, ALICE);
    let r = come_back(&h, &st, &claude).await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
    // A bad token is no better.
    let st = start(&h, &device).await;
    let r = come_back(&h, &st, "not-a-token").await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
}

#[tokio::test]
async fn callback_for_someone_elses_device_looks_like_missing() {
    let h = app_harness().await;
    let (bobs, _key) = h.new_device(BOB).await;
    let st = start(&h, &bobs).await;
    let theirs = come_back(&h, &st, &app_token(&h, ALICE, Some("relay-user"))).await;
    let st = start(&h, "no-such-device").await;
    let missing = come_back(&h, &st, &app_token(&h, ALICE, Some("relay-user"))).await;
    assert_eq!(theirs.status, StatusCode::NOT_FOUND, "{}", theirs.body);
    assert_eq!(theirs.status, missing.status);
    assert_eq!(theirs.body, missing.body, "the pages differ");
    assert!(theirs.header("location").is_none());
    assert!(!theirs.body.contains("Allow"));
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
    // A device that was removed is the same too.
    let (gone, _key) = h.new_device(ALICE).await;
    assert!(h.app.revoke(ALICE, &gone).await.unwrap());
    let st = start(&h, &gone).await;
    let removed = come_back(&h, &st, &app_token(&h, ALICE, Some("relay-user"))).await;
    assert_eq!(removed.body, missing.body);
}

#[tokio::test]
async fn callback_with_the_database_down_says_try_again_and_issues_nothing() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let st = start(&h, &device).await;
    h.store
        .fail_with(Some(crate::store::StoreError::Unavailable));
    let r = come_back(&h, &st, &app_token(&h, ALICE, Some("relay-user"))).await;
    assert_eq!(r.status, StatusCode::SERVICE_UNAVAILABLE, "{}", r.body);
    assert!(r.body.contains("try again"), "{}", r.body);
    assert!(r.header("location").is_none());
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
}

#[tokio::test]
async fn callback_from_another_browser_fails_and_leaves_the_real_one_alone() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let st = start(&h, &device).await;
    let token = app_token(&h, ALICE, Some("relay-user"));
    h.tokens.give_tokens(&token, REFRESH);
    let path = format!("/oauth/callback?code={ZITADEL_CODE}&state={}", st.state);
    // No cookie at all, and somebody else's cookie: a link someone else built.
    let other = start(&h, &device).await;
    for cookie in [
        None,
        Some(other.cookie.clone()),
        Some("vr_oauth=forged".to_string()),
    ] {
        let headers: Vec<(&str, String)> = cookie.into_iter().map(|c| ("cookie", c)).collect();
        let r = h.send("GET", &path, &headers, "").await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{}", r.body);
        assert!(r.header("location").is_none());
    }
    assert!(h.tokens.requests().is_empty(), "no code was spent");
    assert_eq!(h.app.pending.counts().1, 0);
    // The browser that started it can still finish.
    let r = h
        .send("GET", &path, &[("cookie", st.cookie.clone())], "")
        .await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    // And only once.
    let again = h
        .send("GET", &path, &[("cookie", st.cookie.clone())], "")
        .await;
    assert_eq!(again.status, StatusCode::BAD_REQUEST);
    assert_eq!(h.tokens.requests().len(), 1);
}

#[tokio::test]
async fn callback_with_an_error_or_no_code_issues_nothing() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let st = start(&h, &device).await;
    let r = h
        .send(
            "GET",
            &format!("/oauth/callback?error=access_denied&state={}", st.state),
            &[("cookie", st.cookie.clone())],
            "",
        )
        .await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST, "{}", r.body);
    assert!(r.header("location").is_none());
    assert!(h.tokens.requests().is_empty());
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
    // A refused exchange is a plain failure too.
    let st = start(&h, &device).await;
    h.tokens.refuse();
    let r = h
        .send(
            "GET",
            &format!("/oauth/callback?code=x&state={}", st.state),
            &[("cookie", st.cookie.clone())],
            "",
        )
        .await;
    assert_eq!(r.status, StatusCode::BAD_GATEWAY, "{}", r.body);
    assert_eq!(h.app.pending.counts(), (0, 0, 0));
}

#[tokio::test]
async fn consent_names_person_app_and_computer() {
    let h = app_harness().await;
    let (st, _csrf, _device) = at_consent(&h, ALICE, "Alice's <b>Mac</b>").await;
    let page = consent_get(&h, &st.cookie).await;
    assert_eq!(page.status, StatusCode::OK);
    let body = &page.body;
    // Who is signed in, which app, which computer, which connection.
    assert!(body.contains("<strong>alice</strong>"), "{body}");
    assert!(body.contains("Gemini"), "{body}");
    assert!(body.contains(&esc("Alice's <b>Mac</b>")), "{body}");
    assert!(!body.contains("<b>Mac</b>"), "the name was not escaped");
    assert!(
        body.contains(&format!("<code>{}</code>", &ID[ID.len() - 8..])),
        "{body}"
    );
    assert!(
        body.contains("Only allow this if you just started connecting Gemini yourself. Allowing it lets that Gemini account use this computer."),
        "{body}"
    );
    // Allow and Deny are posts with a token, and nothing runs script.
    assert!(body.contains("method=\"post\" action=\"/oauth/consent\""));
    assert!(body.contains("value=\"allow\"") && body.contains("value=\"deny\""));
    assert!(!body.contains("<script") && !body.contains("javascript:"));
    // Nothing of the identity service's goes to the page.
    assert!(!body.contains(ACCESS) && !body.contains(REFRESH), "{body}");
    // Showing the page issues nothing.
    assert_eq!(codes_held(&h), 0);
    // Reloading it is fine.
    assert_eq!(consent_get(&h, &st.cookie).await.status, StatusCode::OK);
    // Without the browser's cookie there is no page.
    let nobody = h.get("/oauth/consent").await;
    assert_eq!(nobody.status, StatusCode::BAD_REQUEST);
    assert!(!nobody.body.contains("Allow"));
}

#[tokio::test]
async fn consent_page_sets_no_store_and_frame_deny() {
    let h = app_harness().await;
    let (st, _csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    let page = consent_get(&h, &st.cookie).await;
    assert_eq!(page.header("cache-control").as_deref(), Some("no-store"));
    assert_eq!(page.header("x-frame-options").as_deref(), Some("DENY"));
    assert_eq!(
        page.header("content-security-policy").as_deref(),
        Some("frame-ancestors 'none'")
    );
    // `same-origin`, not `no-referrer`: under `no-referrer` a browser sends
    // `Origin: null` with the form, and the origin check would refuse Allow.
    assert_eq!(
        page.header("referrer-policy").as_deref(),
        Some("same-origin")
    );
    assert_eq!(
        page.header("x-content-type-options").as_deref(),
        Some("nosniff")
    );
    // The error pages carry them too.
    let gone = h.get("/oauth/consent").await;
    assert_eq!(gone.header("x-frame-options").as_deref(), Some("DENY"));
    assert_eq!(gone.header("cache-control").as_deref(), Some("no-store"));
    assert_eq!(
        gone.header("content-security-policy").as_deref(),
        Some("frame-ancestors 'none'")
    );
}

#[tokio::test]
async fn deny_sends_access_denied_and_no_code() {
    let h = app_harness().await;
    let (st, csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    let r = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "deny").await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let to = r.header("location").unwrap();
    assert_eq!(
        to,
        format!(
            "{}?error=access_denied&state={APP_STATE}",
            production_callback(ID)
        )
    );
    assert!(!to.contains("code="));
    assert_eq!(
        h.app.pending.counts(),
        (0, 0, 0),
        "no code, nothing left over"
    );
    assert!(set_cookie(&r, "vr_oauth").unwrap().contains("Max-Age=0"));
    // The tokens went with it: Allow afterwards does nothing.
    let after = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "allow").await;
    assert_eq!(after.status, StatusCode::FORBIDDEN);
    assert_eq!(codes_held(&h), 0);
}

#[tokio::test]
async fn allow_redirects_with_code_and_original_state() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    // A state with characters that need encoding comes back unchanged.
    let state = "a b/c+d=e&f?g#h\u{e9}\u{1f600}~";
    let q = with(good_query(&h, &device), "state", Some(state));
    let st = start_with(&h, &q).await;
    let token = app_token(&h, ALICE, Some("relay-user"));
    let r = come_back(&h, &st, &token).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let csrf = csrf_in(&consent_get(&h, &st.cookie).await.body);
    let r = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "allow").await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let to = r.header("location").unwrap();
    assert!(
        to.starts_with(&format!("{}?code=", production_callback(ID))),
        "{to}"
    );
    assert_eq!(param(&to, "state").as_deref(), Some(state));
    let code = param(&to, "code").unwrap();
    assert_eq!(code.len(), 43, "32 bytes as base64url: {code}");
    assert!(code
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_'));
    assert!(set_cookie(&r, "vr_oauth").unwrap().contains("Max-Age=0"));
    assert_eq!(r.header("cache-control").as_deref(), Some("no-store"));
    assert_eq!(h.app.pending.counts(), (0, 0, 1));
    // What the code stands for.
    let now = now_secs();
    let issued = h
        .app
        .pending
        .take_code(&code, now)
        .expect("the code is held");
    assert_eq!(issued.client_id, client_id(&h));
    assert_eq!(issued.callback, production_callback(ID));
    assert_eq!(issued.challenge, challenge_for(VERIFIER));
    assert_eq!(issued.resource, format!("{PUBLIC_URL}/mcp/app/{device}"));
    assert_eq!(issued.access_token, token);
    assert_eq!(issued.refresh_token.as_deref(), Some(REFRESH));
    assert_eq!(issued.expires_in, 3600);
    assert_eq!(issued.subject, ALICE);
    assert_eq!(issued.device_id, device);
    assert!(h.app.pending.take_code(&code, now).is_none(), "once");
}

#[tokio::test]
async fn allow_without_csrf_does_nothing() {
    let h = app_harness().await;
    let (st, csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    let origin = Some(PUBLIC_URL);
    let wrong = format!("{csrf}x");
    for (cookie, csrf) in [
        (Some(st.cookie.as_str()), None),
        (Some(st.cookie.as_str()), Some("")),
        (Some(st.cookie.as_str()), Some("wrong")),
        (Some(st.cookie.as_str()), Some(wrong.as_str())),
        (Some(st.cookie.as_str()), Some(&csrf[..csrf.len() - 1])),
        // The right token without the browser it belongs to.
        (None, Some(csrf.as_str())),
        (Some("vr_oauth=someone-else"), Some(csrf.as_str())),
    ] {
        let r = decide(&h, cookie, origin, csrf, "allow").await;
        assert_eq!(
            r.status,
            StatusCode::FORBIDDEN,
            "{cookie:?} {csrf:?}: {}",
            r.body
        );
        assert!(r.header("location").is_none());
        assert_eq!(codes_held(&h), 0, "{cookie:?} {csrf:?}");
    }
    // Neither is a made-up decision.
    for decision in ["", "maybe", "ALLOW"] {
        let r = decide(&h, Some(&st.cookie), origin, Some(&csrf), decision).await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{decision}");
    }
    assert_eq!(codes_held(&h), 0);
    // Nothing was used up: the page's own Allow still works.
    assert_eq!(consents_held(&h), 1);
    let ok = decide(&h, Some(&st.cookie), origin, Some(&csrf), "allow").await;
    assert_eq!(ok.status, StatusCode::SEE_OTHER);
    assert_eq!(codes_held(&h), 1);
}

#[tokio::test]
async fn allow_from_other_origin_does_nothing() {
    let h = app_harness().await;
    let (st, csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    for origin in [
        None,
        Some("null"),
        Some("https://evil.example"),
        Some("https://relay.example.test.evil.example"),
        Some("http://relay.example.test"),
        Some("https://relay.example.test/"),
        Some(""),
    ] {
        let r = decide(&h, Some(&st.cookie), origin, Some(&csrf), "allow").await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{origin:?}: {}", r.body);
        assert!(r.header("location").is_none());
        assert_eq!(codes_held(&h), 0, "{origin:?}");
        let r = decide(&h, Some(&st.cookie), origin, Some(&csrf), "deny").await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "deny {origin:?}");
    }
    assert_eq!(consents_held(&h), 1, "a forged post uses nothing up");
}

#[tokio::test]
async fn allow_replayed_does_nothing() {
    let h = app_harness().await;
    let (st, csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    let first = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "allow").await;
    assert_eq!(first.status, StatusCode::SEE_OTHER, "{}", first.body);
    assert_eq!(codes_held(&h), 1);
    let again = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "allow").await;
    assert_eq!(again.status, StatusCode::FORBIDDEN, "{}", again.body);
    assert!(again.header("location").is_none());
    assert_eq!(codes_held(&h), 1, "no second code");
    // Nor does the page come back.
    assert_eq!(
        consent_get(&h, &st.cookie).await.status,
        StatusCode::BAD_REQUEST
    );
}

#[tokio::test]
async fn racing_allows_issue_one_code() {
    let h = std::sync::Arc::new(app_harness().await);
    let (st, csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    let mut tasks = Vec::new();
    for _ in 0..8 {
        let (h, cookie, csrf) = (h.clone(), st.cookie.clone(), csrf.clone());
        tasks.push(tokio::spawn(async move {
            decide(&h, Some(&cookie), Some(PUBLIC_URL), Some(&csrf), "allow")
                .await
                .status
        }));
    }
    let mut won = 0;
    for t in tasks {
        if t.await.unwrap() == StatusCode::SEE_OTHER {
            won += 1;
        }
    }
    assert_eq!(won, 1);
    assert_eq!(codes_held(&h), 1);
}

#[tokio::test]
async fn another_browsers_consent_cannot_be_decided_by_a_different_one() {
    // Two people at once: each decides only their own.
    let h = app_harness().await;
    let (alice, a_csrf, _) = at_consent(&h, ALICE, "Alice Mac").await;
    let (bob, b_csrf, _) = at_consent(&h, BOB, "Bob Mac").await;
    // Bob's cookie with Alice's token, and the reverse.
    let r = decide(
        &h,
        Some(&bob.cookie),
        Some(PUBLIC_URL),
        Some(&a_csrf),
        "allow",
    )
    .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    let r = decide(
        &h,
        Some(&alice.cookie),
        Some(PUBLIC_URL),
        Some(&b_csrf),
        "allow",
    )
    .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    assert_eq!(codes_held(&h), 0);
    let page = consent_get(&h, &alice.cookie).await;
    assert!(page.body.contains("Alice Mac") && !page.body.contains("Bob Mac"));
}

#[tokio::test]
async fn consent_expires_after_five_minutes() {
    static SKEW: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    fn skewed() -> u64 {
        now_secs() + SKEW.load(std::sync::atomic::Ordering::SeqCst)
    }
    let h = app_harness_with(Timing {
        clock: skewed,
        ..Timing::default()
    })
    .await;
    let (st, csrf, _device) = at_consent(&h, ALICE, "Mac").await;
    SKEW.store(5 * 60 + 1, std::sync::atomic::Ordering::SeqCst);
    let r = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "allow").await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    assert_eq!(codes_held(&h), 0);
    assert_eq!(
        consent_get(&h, &st.cookie).await.status,
        StatusCode::BAD_REQUEST
    );
    SKEW.store(0, std::sync::atomic::Ordering::SeqCst);
}

#[tokio::test]
async fn the_sign_in_leaves_no_secret_in_the_logs() {
    let h = app_harness().await;
    let (device, _key) = h.new_device(ALICE).await;
    let q = with(
        good_query(&h, &device),
        "state",
        Some("the-apps-private-state"),
    );
    let st = start_with(&h, &q).await;
    let token = app_token(&h, ALICE, Some("relay-user"));
    let r = come_back(&h, &st, &token).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER);
    let csrf = csrf_in(&consent_get(&h, &st.cookie).await.body);
    let done = decide(&h, Some(&st.cookie), Some(PUBLIC_URL), Some(&csrf), "allow").await;
    let code = param(&done.header("location").unwrap(), "code").unwrap();
    // A refused attempt too.
    let _ = come_back(&h, &st, &token).await;
    let logs = h.logs();
    assert!(logs.contains("app_consent_allowed"), "{logs}");
    for secret in [
        token.as_str(),
        REFRESH,
        ZITADEL_CODE,
        code.as_str(),
        st.state.as_str(),
        st.cookie.split_once('=').unwrap().1,
        "the-apps-private-state",
        csrf.as_str(),
        ID,
        &challenge_for(VERIFIER),
        ALICE,
    ] {
        assert!(!logs.contains(secret), "{secret} is in the logs:\n{logs}");
    }
}
