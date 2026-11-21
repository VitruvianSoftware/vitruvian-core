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

//! The dashboard against a real relay on a loopback port, with a stand-in
//! for the identity service's token endpoint (`http::tests::Harness`). Each
//! test signs in the way a browser does: `/auth/login`, then the callback with
//! the state it was given and the cookie it set.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use http::StatusCode;

use super::*;
use crate::http::tests::{
    call_body, ed25519, error_text, harness, harness_with, spawn_rpc, tool, within, Harness, Reply,
    ALICE, BOB, CONNECTOR_CLIENT, MCP_CLIENT, PUBLIC_URL,
};
use crate::http::Timing;
use crate::store::{ActivityRow, Store};
use ring::signature::KeyPair;
use serde_json::json;

const CSP_EXPECTED: &str = "default-src 'self'; frame-ancestors 'none'; form-action 'self'";

/// A signed-in browser: its session cookie and the form token on its pages.
struct Browser {
    cookie: String,
    csrf: String,
}

fn set_cookie(r: &Reply, name: &str) -> Option<String> {
    r.headers
        .get_all("set-cookie")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .find(|c| c.starts_with(&format!("{name}=")))
        .map(String::from)
}

/// `name=value`, the part of a `Set-Cookie` a browser sends back.
fn pair(set_cookie: &str) -> String {
    set_cookie.split(';').next().unwrap().to_string()
}

fn query_of(url: &str, key: &str) -> Option<String> {
    query_param(url.split_once('?').map(|(_, q)| q), key)
}

fn csrf_in(page: &str) -> String {
    let after = page
        .split("name=\"csrf\" value=\"")
        .nth(1)
        .expect("the page has a form with a CSRF token");
    after.split('"').next().unwrap().to_string()
}

/// Starts a sign-in and returns what the browser holds when it is sent to the
/// callback: the `state` it was given and the `vr_auth` cookie it was set.
async fn start_sign_in(h: &Harness) -> (String, String, Reply) {
    let r = h.get("/auth/login").await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let location = r.header("location").unwrap();
    let state = query_of(&location, "state").expect("state is sent");
    let auth = pair(&set_cookie(&r, "vr_auth").expect("the sign-in is remembered"));
    (state, auth, r)
}

/// A full sign-in as `sub`, the way a browser does it.
async fn sign_in(h: &Harness, sub: &str) -> Browser {
    let (state, auth, _) = start_sign_in(h).await;
    h.tokens.give_token(&h.dashboard_token(sub));
    let r = h
        .send(
            "GET",
            &format!("/auth/callback?code=the-code&state={state}"),
            &[("cookie", auth)],
            "",
        )
        .await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    assert_eq!(r.header("location").as_deref(), Some("/devices"));
    let cookie = pair(&set_cookie(&r, "vr_session").expect("signed in"));
    let page = h
        .send("GET", "/devices", &[("cookie", cookie.clone())], "")
        .await;
    assert_eq!(page.status, StatusCode::OK, "{}", page.body);
    Browser {
        csrf: csrf_in(&page.body),
        cookie,
    }
}

impl Browser {
    async fn get(&self, h: &Harness, path: &str) -> Reply {
        h.send("GET", path, &[("cookie", self.cookie.clone())], "")
            .await
    }

    /// A form post as a page would send it. `csrf` and `origin` are what the
    /// test chooses to send in place of the right ones.
    async fn post_as(
        &self,
        h: &Harness,
        path: &str,
        fields: &[(&str, &str)],
        csrf: Option<&str>,
        origin: Option<&str>,
    ) -> Reply {
        let mut body: Vec<String> = fields
            .iter()
            .map(|(k, v)| format!("{}={}", form_encode(k), form_encode(v)))
            .collect();
        if let Some(csrf) = csrf {
            body.push(format!("csrf={}", form_encode(csrf)));
        }
        let mut headers = vec![
            ("cookie", self.cookie.clone()),
            (
                "content-type",
                "application/x-www-form-urlencoded".to_string(),
            ),
        ];
        if let Some(origin) = origin {
            headers.push(("origin", origin.to_string()));
        }
        h.send("POST", path, &headers, &body.join("&")).await
    }

    async fn post(&self, h: &Harness, path: &str, fields: &[(&str, &str)]) -> Reply {
        self.post_as(h, path, fields, Some(&self.csrf), Some(PUBLIC_URL))
            .await
    }
}

/// What an answer is, minus the clock: status, headers and body.
fn shape(r: &Reply) -> (StatusCode, Vec<(String, String)>, String) {
    let mut headers: Vec<(String, String)> = r
        .headers
        .iter()
        .filter(|(k, _)| k.as_str() != "date")
        .map(|(k, v)| (k.to_string(), v.to_str().unwrap().to_string()))
        .collect();
    headers.sort();
    (r.status, headers, r.body.clone())
}

fn row(owner: &str, device: &str, tool: &str, at: SystemTime) -> ActivityRow {
    ActivityRow {
        at,
        owner_sub: owner.into(),
        device_id: device.into(),
        client_id: MCP_CLIENT.into(),
        tool: tool.into(),
        arg_bytes: Some(10),
        result_bytes: Some(20),
        duration_ms: Some(1500),
        outcome: "ok".into(),
    }
}

// ---------------------------------------------------------------- the tests

#[tokio::test]
async fn signed_out_pages_redirect_to_sign_in() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    for path in [
        "/devices".to_string(),
        format!("/devices/{device}"),
        "/activity".to_string(),
        format!("/activity?device={device}"),
    ] {
        let r = h.get(&path).await;
        assert_eq!(r.status, StatusCode::SEE_OTHER, "{path}");
        assert_eq!(r.header("location").as_deref(), Some("/"), "{path}");
    }
    // A form post with no session goes to the same place, and changes nothing.
    for path in [
        format!("/devices/{device}/rename"),
        format!("/devices/{device}/remove"),
        "/auth/logout".to_string(),
    ] {
        let r = h
            .send(
                "POST",
                &path,
                &[("origin", PUBLIC_URL.to_string())],
                "csrf=x&name=Mine",
            )
            .await;
        assert_eq!(r.status, StatusCode::SEE_OTHER, "{path}");
        assert_eq!(r.header("location").as_deref(), Some("/"), "{path}");
    }
    assert_eq!(
        h.store.device(&device).await.unwrap().unwrap().name,
        "My Mac"
    );

    // The front page says what this is and offers to sign in.
    let home = h.get("/").await;
    assert_eq!(home.status, StatusCode::OK);
    assert!(home.body.contains("Vitruvian Relay"));
    assert!(home.body.contains("href=\"/auth/login\""), "{}", home.body);
}

#[tokio::test]
async fn signing_in_follows_the_flow_and_makes_a_safe_session() {
    let h = harness().await;
    let (state, auth, login) = start_sign_in(&h).await;
    let location = login.header("location").unwrap();
    // Off to the identity service, with PKCE.
    assert!(
        location.starts_with("https://auth.example.test/oauth/v2/authorize?"),
        "{location}"
    );
    assert_eq!(
        query_of(&location, "response_type").as_deref(),
        Some("code")
    );
    assert_eq!(
        query_of(&location, "client_id").as_deref(),
        Some("dashboard-client")
    );
    assert_eq!(
        query_of(&location, "redirect_uri").as_deref(),
        Some("https://relay.example.test/auth/callback")
    );
    assert_eq!(
        query_of(&location, "code_challenge_method").as_deref(),
        Some("S256")
    );
    let scope = query_of(&location, "scope").unwrap();
    assert!(
        scope.contains("openid") && scope.contains("project:id:123456789:aud"),
        "{scope}"
    );
    // The state and verifier wait in a short-lived cookie.
    let auth_cookie = set_cookie(&login, "vr_auth").unwrap();
    for part in [
        "HttpOnly",
        "Secure",
        "SameSite=Lax",
        "Path=/auth",
        "Max-Age=600",
    ] {
        assert!(auth_cookie.contains(part), "{auth_cookie}");
    }
    let verifier = auth.split_once('.').unwrap().1.to_string();
    assert_eq!(
        query_of(&location, "code_challenge").unwrap(),
        session::challenge_for(&verifier)
    );
    assert_eq!(auth, format!("vr_auth={state}.{verifier}"));

    // The callback trades the code, with that verifier, for a token.
    h.tokens.give_token(&h.dashboard_token(ALICE));
    let r = h
        .send(
            "GET",
            &format!("/auth/callback?code=the-code&state={state}"),
            &[("cookie", auth)],
            "",
        )
        .await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    let sent = parse_pairs(&h.tokens.requests()[0]);
    assert_eq!(sent["grant_type"], "authorization_code");
    assert_eq!(sent["code"], "the-code");
    assert_eq!(sent["code_verifier"], verifier);
    assert_eq!(sent["client_id"], "dashboard-client");
    assert_eq!(
        sent["redirect_uri"],
        "https://relay.example.test/auth/callback"
    );
    // The session cookie is 32 random bytes with every protection; the
    // sign-in cookie is cleared.
    let session = set_cookie(&r, "vr_session").unwrap();
    assert!(
        session.ends_with("; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=43200"),
        "{session}"
    );
    assert_eq!(pair(&session).len(), "vr_session=".len() + 43);
    assert!(set_cookie(&r, "vr_auth").unwrap().contains("Max-Age=0"));

    // Signed in, the front page goes to the list; so does a second sign-in.
    let cookie = pair(&session);
    let home = h.send("GET", "/", &[("cookie", cookie.clone())], "").await;
    assert_eq!(home.header("location").as_deref(), Some("/devices"));
    let again = h
        .send("GET", "/auth/login", &[("cookie", cookie)], "")
        .await;
    assert_eq!(again.header("location").as_deref(), Some("/devices"));
}

#[tokio::test]
async fn callback_with_bad_state_is_refused() {
    let h = harness().await;
    let (state, auth, _) = start_sign_in(&h).await;
    h.tokens.give_token(&h.dashboard_token(ALICE));
    let other = Pkce::new();
    type Case = (&'static str, String, Vec<(&'static str, String)>);
    let cases: Vec<Case> = vec![
        ("no cookie", format!("state={state}&code=c"), vec![]),
        (
            "another browser's state",
            format!("state={}&code=c", other.state),
            vec![("cookie", auth.clone())],
        ),
        (
            "no state",
            "code=c".to_string(),
            vec![("cookie", auth.clone())],
        ),
        (
            "a mangled cookie",
            format!("state={state}&code=c"),
            vec![("cookie", "vr_auth=junk".to_string())],
        ),
        (
            "the person said no",
            format!("state={state}&error=access_denied"),
            vec![("cookie", auth.clone())],
        ),
        (
            "no code",
            format!("state={state}"),
            vec![("cookie", auth.clone())],
        ),
    ];
    for (why, query, headers) in cases {
        let r = h
            .send("GET", &format!("/auth/callback?{query}"), &headers, "")
            .await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{why}: {}", r.body);
        assert!(set_cookie(&r, "vr_session").is_none(), "{why}");
        assert!(
            r.body.contains("Sign in again"),
            "{why}: tells them what to do"
        );
    }
    assert!(
        h.tokens.requests().is_empty(),
        "no code was ever traded: {:?}",
        h.tokens.requests()
    );
}

#[tokio::test]
async fn a_failed_exchange_says_so_and_signs_nobody_in() {
    let h = harness().await;
    let (state, auth, _) = start_sign_in(&h).await;
    h.tokens.refuse();
    let r = h
        .send(
            "GET",
            &format!("/auth/callback?code=c&state={state}"),
            &[("cookie", auth)],
            "",
        )
        .await;
    assert_eq!(r.status, StatusCode::BAD_GATEWAY, "{}", r.body);
    assert!(set_cookie(&r, "vr_session").is_none());
    assert!(r.body.contains("Try again"), "{}", r.body);
    assert!(!h.logs().contains("the-code"));
}

#[tokio::test]
async fn post_without_csrf_is_403() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let b = sign_in(&h, ALICE).await;
    let rename = format!("/devices/{device}/rename");
    let remove = format!("/devices/{device}/remove");
    for (why, csrf) in [("missing", None), ("wrong", Some("not-the-token"))] {
        for (path, fields) in [
            (&rename, vec![("name", "Hijacked")]),
            (&remove, vec![]),
            (&"/auth/logout".to_string(), vec![]),
        ] {
            let r = b.post_as(&h, path, &fields, csrf, Some(PUBLIC_URL)).await;
            assert_eq!(r.status, StatusCode::FORBIDDEN, "{why} {path}: {}", r.body);
        }
    }
    let kept = h.store.device(&device).await.unwrap().expect("not removed");
    assert_eq!(kept.name, "My Mac", "not renamed");
    assert_eq!(
        b.get(&h, "/devices").await.status,
        StatusCode::OK,
        "still signed in"
    );
}

#[tokio::test]
async fn post_from_other_origin_is_403() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let b = sign_in(&h, ALICE).await;
    for (why, origin) in [
        ("another site", Some("https://evil.example")),
        (
            "a look-alike",
            Some("https://relay.example.test.evil.example"),
        ),
        ("plain http", Some("http://relay.example.test")),
        ("none at all", None),
    ] {
        let r = b
            .post_as(
                &h,
                &format!("/devices/{device}/remove"),
                &[],
                Some(&b.csrf),
                origin,
            )
            .await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{why}: {}", r.body);
        let r = b
            .post_as(
                &h,
                &format!("/devices/{device}/rename"),
                &[("name", "X")],
                Some(&b.csrf),
                origin,
            )
            .await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{why}: {}", r.body);
    }
    let kept = h.store.device(&device).await.unwrap().expect("not removed");
    assert_eq!(kept.name, "My Mac");
}

#[tokio::test]
async fn rename_trims_and_caps() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let b = sign_in(&h, ALICE).await;
    let path = format!("/devices/{device}/rename");

    let r = b.post(&h, &path, &[("name", "  Work\u{7} Mac \n")]).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    assert_eq!(
        r.header("location").unwrap(),
        format!("/devices/{device}?done=renamed")
    );
    assert_eq!(
        h.store.device(&device).await.unwrap().unwrap().name,
        "Work Mac"
    );
    let page = b.get(&h, &r.header("location").unwrap()).await;
    assert!(page.body.contains("Name saved."), "{}", page.body);
    assert!(page.body.contains("Work Mac"));

    // Too long is cut to 64 characters (not bytes).
    let long = format!("  {} ", "é".repeat(80));
    assert_eq!(
        b.post(&h, &path, &[("name", &long)]).await.status,
        StatusCode::SEE_OTHER
    );
    let stored = h.store.device(&device).await.unwrap().unwrap().name;
    assert_eq!(stored, "é".repeat(DEVICE_NAME_MAX));

    // Nothing left after cleaning: told so, on the page, and nothing changes.
    let r = b.post(&h, &path, &[("name", " \u{7}\t ")]).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert!(r.body.contains("1 to 64 characters"), "{}", r.body);
    assert_eq!(h.store.device(&device).await.unwrap().unwrap().name, stored);

    // A name with markup is stored as typed and shown as text.
    b.post(&h, &path, &[("name", "<b>Mine</b> & \"yours\"")])
        .await;
    let page = b.get(&h, &format!("/devices/{device}")).await;
    assert!(
        page.body
            .contains("&lt;b&gt;Mine&lt;/b&gt; &amp; &quot;yours&quot;"),
        "{}",
        page.body
    );
    assert!(!page.body.contains("<b>Mine"), "{}", page.body);
}

#[tokio::test]
async fn remove_kicks_the_link() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let (kept, _) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let session = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &session,
        call_body(json!(1), "t", json!({})),
    );
    fake.next_call().await;
    let b = sign_in(&h, ALICE).await;

    // The page says it is online, and offers the removal.
    let page = b.get(&h, &format!("/devices/{device}")).await;
    assert!(page.body.contains("Online"), "{}", page.body);

    let r = b.post(&h, &format!("/devices/{device}/remove"), &[]).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    assert_eq!(
        r.header("location").as_deref(),
        Some("/devices?done=removed")
    );

    // The call in flight fails in plain words and the link closes.
    let failed = within(pending).await.unwrap();
    assert_eq!(
        error_text(&failed),
        "This computer was removed from your account."
    );
    fake.wait_closed().await;
    assert!(h.store.device(&device).await.unwrap().is_none());
    assert!(h.app.registry.tools(&device).is_none());

    // The list no longer has it, says what happened, and keeps the other.
    let list = b.get(&h, "/devices?done=removed").await;
    assert!(
        list.body.contains("That computer was removed."),
        "{}",
        list.body
    );
    assert!(!list.body.contains(&format!("/devices/{device}")));
    assert!(list.body.contains(&format!("/devices/{kept}")));

    // Removing it again is the same as removing one that never existed.
    let again = b.post(&h, &format!("/devices/{device}/remove"), &[]).await;
    let never = b
        .post(
            &h,
            "/devices/00000000-0000-4000-8000-000000000000/remove",
            &[],
        )
        .await;
    assert_eq!(again.status, StatusCode::NOT_FOUND);
    assert_eq!(shape(&again), shape(&never));
}

#[tokio::test]
async fn activity_page_shows_no_arguments() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let session = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &session,
        call_body(
            json!(1),
            "read_file",
            json!({"path": "/Users/alice/SECRET-ARG-123"}),
        ),
    );
    let call = fake.next_call().await;
    fake.reply(&call.call_id, "RESULT-TEXT-456");
    within(pending).await.unwrap();
    // The row is written in the background.
    within(async {
        while h
            .store
            .activity_of(ALICE, None, 10)
            .await
            .unwrap()
            .is_empty()
        {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;

    // A tool name that tries to be markup, and someone else's call.
    let at = SystemTime::now();
    h.store
        .record_activity(&row(ALICE, &device, "<img src=x onerror=alert(1)>", at))
        .await
        .unwrap();
    let (bobs, _) = h.new_device(BOB).await;
    h.store
        .record_activity(&row(BOB, &bobs, "bobs_private_tool", at))
        .await
        .unwrap();

    let b = sign_in(&h, ALICE).await;
    let page = b.get(&h, "/activity").await;
    assert_eq!(page.status, StatusCode::OK, "{}", page.body);
    for shown in ["read_file", "Done", "Claude", "My Mac", "<time datetime=\""] {
        assert!(page.body.contains(shown), "{shown} in {}", page.body);
    }
    for never in [
        "SECRET-ARG-123",
        "RESULT-TEXT-456",
        "/Users/alice",
        "bobs_private_tool",
        "<img ",
    ] {
        assert!(!page.body.contains(never), "{never} in {}", page.body);
    }
    assert!(
        page.body.contains("&lt;img src=x onerror=alert(1)&gt;"),
        "{}",
        page.body
    );
    // The same one computer's view, and the whole thing in UTC.
    let one = b.get(&h, &format!("/activity?device={device}")).await;
    assert_eq!(one.status, StatusCode::OK);
    assert!(one.body.contains("read_file") && !one.body.contains("SECRET-ARG-123"));
    assert!(page.body.contains("UTC"));
}

#[tokio::test]
async fn activity_shows_the_last_200_calls_newest_first() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let base = SystemTime::now() - Duration::from_secs(10_000);
    for n in 0..(ACTIVITY_PAGE as u64 + 5) {
        h.store
            .record_activity(&row(
                ALICE,
                &device,
                &format!("tool_{n:03}"),
                base + Duration::from_secs(n),
            ))
            .await
            .unwrap();
    }
    let b = sign_in(&h, ALICE).await;
    let page = b.get(&h, "/activity").await;
    assert_eq!(page.body.matches("<td data-label=\"When\">").count(), 200);
    assert!(page.body.contains("tool_204") && page.body.contains("tool_005"));
    assert!(
        !page.body.contains("tool_004"),
        "the oldest five are not shown"
    );
    assert!(
        page.body.find("tool_204").unwrap() < page.body.find("tool_203").unwrap(),
        "newest first"
    );
    assert!(page.body.contains("most recent 200"));
    // A computer with no calls says so, and what happens next.
    let (quiet, _) = h.new_device(ALICE).await;
    let empty = b.get(&h, &format!("/activity?device={quiet}")).await;
    assert!(empty.body.contains("Nothing yet."), "{}", empty.body);
}

#[tokio::test]
async fn mcp_token_cannot_open_dashboard() {
    let h = harness().await;
    // An AI app's token, the connector's, and a person who holds the dashboard
    // client but was never invited: none gets in.
    let wrong_client = [
        ("an AI app's token", h.mcp_token(ALICE)),
        ("the connector's token", h.connector_token(ALICE)),
    ];
    for (why, token) in wrong_client {
        let (state, auth, _) = start_sign_in(&h).await;
        h.tokens.give_token(&token);
        let r = h
            .send(
                "GET",
                &format!("/auth/callback?code=c&state={state}"),
                &[("cookie", auth)],
                "",
            )
            .await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{why}: {}", r.body);
        assert!(set_cookie(&r, "vr_session").is_none(), "{why}");
        assert!(
            r.body.contains("could not accept that sign-in"),
            "{why}: {}",
            r.body
        );
        assert_eq!(h.app.dashboard.sessions.count(), 0);
    }
    // The token for the right client, but without the role.
    let (state, auth, _) = start_sign_in(&h).await;
    let uninvited = crate::http::tests::mint_with_role(
        &h.rsa,
        crate::http::tests::DASHBOARD_CLIENT,
        ALICE,
        Some(crate::http::tests::now_secs() + 600),
        None,
    );
    h.tokens.give_token(&uninvited);
    let r = h
        .send(
            "GET",
            &format!("/auth/callback?code=c&state={state}"),
            &[("cookie", auth)],
            "",
        )
        .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    assert!(r.body.contains("not been invited"), "{}", r.body);
    assert!(set_cookie(&r, "vr_session").is_none());
    // And an AI app's token is no use as a bearer on a dashboard page.
    let r = h
        .send(
            "GET",
            "/devices",
            &[("authorization", format!("Bearer {}", h.mcp_token(ALICE)))],
            "",
        )
        .await;
    assert_eq!(
        r.status,
        StatusCode::SEE_OTHER,
        "a bearer token is not a session"
    );
}

#[tokio::test]
async fn dashboard_token_cannot_call_tools() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let token = h.dashboard_token(ALICE);
    let list = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"});
    let r = h
        .send(
            "POST",
            &format!("/mcp/d/{device}"),
            &[
                ("authorization", format!("Bearer {token}")),
                ("accept", "application/json".to_string()),
                ("content-type", "application/json".to_string()),
            ],
            &list.to_string(),
        )
        .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    // Nor can it register a computer or open the connector's link.
    let r = h
        .send(
            "POST",
            "/devices",
            &[
                ("authorization", format!("Bearer {token}")),
                ("content-type", "application/json".to_string()),
            ],
            &json!({"public_key": crate::http::tests::b64(ed25519().public_key().as_ref())})
                .to_string(),
        )
        .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    assert!(h.ws(&token).await.is_err(), "/connect refuses it");
    assert_eq!(h.store.devices_of(ALICE).await.unwrap().len(), 1);
    // The connector's token and an AI app's are refused the other way round.
    assert_eq!(CONNECTOR_CLIENT, "connector-client");
}

#[tokio::test]
async fn someone_elses_computer_is_the_same_answer_as_one_that_does_not_exist() {
    let h = harness().await;
    let (bobs, _) = h.new_device(BOB).await;
    h.store
        .record_activity(&row(BOB, &bobs, "bobs_tool", SystemTime::now()))
        .await
        .unwrap();
    let a = sign_in(&h, ALICE).await;
    let never = "00000000-0000-4000-8000-000000000000";
    let not_an_id = "not%20an%20id";

    for (label, theirs, nothing) in [
        (
            "page",
            format!("/devices/{bobs}"),
            format!("/devices/{never}"),
        ),
        (
            "page, odd id",
            format!("/devices/{bobs}"),
            format!("/devices/{not_an_id}"),
        ),
        (
            "activity",
            format!("/activity?device={bobs}"),
            format!("/activity?device={never}"),
        ),
    ] {
        let (x, y) = (a.get(&h, &theirs).await, a.get(&h, &nothing).await);
        assert_eq!(x.status, StatusCode::NOT_FOUND, "{label}");
        assert_eq!(shape(&x), shape(&y), "{label}");
        assert!(!x.body.contains("bobs_tool"));
    }
    for action in ["rename", "remove"] {
        let fields = [("name", "Stolen")];
        let x = a
            .post(&h, &format!("/devices/{bobs}/{action}"), &fields)
            .await;
        let y = a
            .post(&h, &format!("/devices/{never}/{action}"), &fields)
            .await;
        assert_eq!(x.status, StatusCode::NOT_FOUND, "{action}");
        assert_eq!(shape(&x), shape(&y), "{action}");
    }
    // Bob's computer is as it was, and his calls are not on Alice's page.
    let kept = h.store.device(&bobs).await.unwrap().expect("still Bob's");
    assert_eq!(kept.name, "My Mac");
    assert!(!a.get(&h, "/activity").await.body.contains("bobs_tool"));
    assert!(!a.get(&h, "/devices").await.body.contains(&bobs));
}

#[tokio::test]
async fn the_list_shows_my_computers_with_their_address_and_status() {
    let h = harness().await;
    let (online, key) = h.new_device(ALICE).await;
    let (offline, _) = h.new_device(ALICE).await;
    let (bobs, _) = h.new_device(BOB).await;
    let _fake = h.connect(ALICE, &online, &key, vec![tool("t")]).await;
    let b = sign_in(&h, ALICE).await;

    let page = b.get(&h, "/devices").await;
    assert!(
        page.body.contains(&format!("{PUBLIC_URL}/mcp/d/{online}")),
        "{}",
        page.body
    );
    assert!(page.body.contains(&format!("{PUBLIC_URL}/mcp/d/{offline}")));
    assert!(page.body.contains("Online") && page.body.contains("Offline"));
    assert!(page.body.contains("Connected now."));
    assert!(page.body.contains("has not connected yet") || page.body.contains("Last seen"));
    assert!(
        !page.body.contains(&bobs),
        "someone else's computer is not listed"
    );

    // The computer's page: the steps for Claude (with the id the relay knows
    // Claude by) and for Gemini, the rename box and the removal.
    let one = b.get(&h, &format!("/devices/{online}")).await;
    for text in [
        "Add it to Claude",
        "Add it to Gemini",
        "Add custom connector",
        "claude-client",
        "Save name",
        "Remove this computer",
        &format!("{PUBLIC_URL}/mcp/d/{online}"),
    ] {
        assert!(one.body.contains(text), "{text} in {}", one.body);
    }
    // A person with no computers is told how to add one.
    let nobody = sign_in(&h, "carol").await;
    let empty = nobody.get(&h, "/devices").await;
    assert!(empty.body.contains("vrelay login"), "{}", empty.body);
}

#[tokio::test]
async fn signing_out_ends_the_session() {
    let h = harness().await;
    let b = sign_in(&h, ALICE).await;
    let r = b.post(&h, "/auth/logout", &[]).await;
    assert_eq!(r.status, StatusCode::SEE_OTHER, "{}", r.body);
    assert_eq!(r.header("location").as_deref(), Some("/?signed_out=1"));
    assert!(set_cookie(&r, "vr_session").unwrap().contains("Max-Age=0"));
    // The old cookie, replayed, is nobody.
    let after = b.get(&h, "/devices").await;
    assert_eq!(after.status, StatusCode::SEE_OTHER);
    let home = h.get("/?signed_out=1").await;
    assert!(home.body.contains("You are signed out"), "{}", home.body);
    assert!(home
        .body
        .contains("/oidc/v1/end_session?client_id=dashboard-client"));
}

/// Moves the clock the sessions use; only the test below reads it.
static SKEW_SECS: AtomicU64 = AtomicU64::new(0);

fn skewed_clock() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + SKEW_SECS.load(Ordering::SeqCst)
}

#[tokio::test]
async fn a_session_ends_after_twelve_hours() {
    let h = harness_with(Timing {
        clock: skewed_clock,
        ..Timing::default()
    })
    .await;
    let b = sign_in(&h, ALICE).await;
    SKEW_SECS.store(12 * 3600 - 60, Ordering::SeqCst);
    assert_eq!(b.get(&h, "/devices").await.status, StatusCode::OK);
    SKEW_SECS.store(12 * 3600 + 60, Ordering::SeqCst);
    let r = b.get(&h, "/devices").await;
    assert_eq!(r.status, StatusCode::SEE_OTHER);
    assert_eq!(r.header("location").as_deref(), Some("/"));
    SKEW_SECS.store(0, Ordering::SeqCst);
}

#[tokio::test]
async fn every_page_is_private_script_free_and_in_plain_words() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    h.store
        .record_activity(&row(ALICE, &device, "read_file", SystemTime::now()))
        .await
        .unwrap();
    let b = sign_in(&h, ALICE).await;
    let mut pages = vec![
        ("signed-out front page", h.get("/").await),
        ("css", h.get("/static/relay.css").await),
        ("refused callback", h.get("/auth/callback?state=x").await),
        ("not found", b.get(&h, "/devices/nope").await),
        ("list", b.get(&h, "/devices").await),
        ("computer", b.get(&h, &format!("/devices/{device}")).await),
        ("activity", b.get(&h, "/activity").await),
        (
            "forbidden",
            b.post_as(
                &h,
                &format!("/devices/{device}/remove"),
                &[],
                None,
                Some(PUBLIC_URL),
            )
            .await,
        ),
        ("login redirect", h.get("/auth/login").await),
        ("signed-out redirect", h.get("/devices").await),
        ("signed-in redirect", b.get(&h, "/").await),
    ];
    pages.push((
        "name refused",
        b.post(&h, &format!("/devices/{device}/rename"), &[("name", " ")])
            .await,
    ));
    for (label, r) in &pages {
        assert_eq!(
            r.header("cache-control").as_deref(),
            Some("no-store"),
            "{label}"
        );
        assert_eq!(
            r.header("content-security-policy").as_deref(),
            Some(CSP_EXPECTED),
            "{label}"
        );
        assert_eq!(
            r.header("x-content-type-options").as_deref(),
            Some("nosniff"),
            "{label}"
        );
        let lower = r.body.to_lowercase();
        assert!(
            !lower.contains("<script") && !lower.contains("javascript:"),
            "{label}"
        );
        assert!(
            !lower.contains(" style=") && !lower.contains("<style"),
            "{label}: inline style"
        );
        for attr in [" onclick=", " onerror=", " onload=", " onsubmit="] {
            assert!(!lower.contains(attr), "{label}: {attr}");
        }
        assert!(
            !lower.contains("desktop commander") && !lower.contains("desktop-commander"),
            "{label}"
        );
        if r.header("content-type")
            .unwrap_or_default()
            .starts_with("text/html")
        {
            assert!(
                lower.contains("name=\"viewport\""),
                "{label}: works at phone width"
            );
            assert!(
                lower.contains("<title>") && lower.contains("vitruvian relay"),
                "{label}"
            );
            assert!(lower.contains("href=\"/static/relay.css\""), "{label}");
        }
    }
    let css = &pages[1].1;
    assert_eq!(css.status, StatusCode::OK);
    assert!(css.header("content-type").unwrap().starts_with("text/css"));
    assert!(
        css.body.contains("@media (max-width: 40rem)"),
        "the phone layout is there"
    );
    assert!(css
        .body
        .starts_with("/*\n * Copyright (c) 2026 VitruvianSoftware"));
    // Every form says where it goes and carries the token.
    let list = &pages[4].1;
    assert!(list.body.contains("action=\"/auth/logout\""));
    assert_eq!(csrf_in(&list.body), b.csrf);
}

/// Writes every page, with realistic content, to `$DASHBOARD_PAGES_DIR` so
/// they can be opened in a browser at desktop and phone width. Run by hand:
/// `DASHBOARD_PAGES_DIR=/some/dir <test binary> --ignored write_pages_for_a_look`.
/// (The stylesheet link is made relative so the files open from disk.)
#[tokio::test]
#[ignore = "writes the pages to $DASHBOARD_PAGES_DIR for a look; not a check"]
async fn write_pages_for_a_look() {
    let Some(dir) = std::env::var_os("DASHBOARD_PAGES_DIR") else {
        return;
    };
    let dir = std::path::PathBuf::from(dir);
    std::fs::create_dir_all(dir.join("static")).unwrap();
    let h = harness().await;
    let (online, key) = h.new_device(ALICE).await;
    let _fake = h.connect(ALICE, &online, &key, vec![tool("t")]).await;
    let (offline, _) = h.new_device(ALICE).await;
    let (never, _) = h.new_device(ALICE).await;
    h.store
        .touch_seen(
            &offline,
            SystemTime::now() - Duration::from_secs(3 * 3600 + 120),
        )
        .await
        .unwrap();
    let b = sign_in(&h, ALICE).await;
    for (id, name) in [
        (&online, "James's MacBook Pro"),
        (
            &offline,
            "Studio Mac mini in the garage with a very long name to wrap",
        ),
        (&never, "Spare"),
    ] {
        b.post(&h, &format!("/devices/{id}/rename"), &[("name", name)])
            .await;
    }
    let now = SystemTime::now();
    let outcomes = [
        ("ok", "read_file", 120),
        ("ok", "list_directory", 40),
        ("waiting_approval", "start_process", 15_000),
        ("tool_error", "read_file", 310),
        ("rate_limited", "read_file", 0),
        ("offline", "read_file", 5),
        ("deadline", "start_process", 600_000),
        ("disconnected", "write_file", 2_300),
    ];
    for (n, (outcome, tool, ms)) in outcomes.iter().enumerate() {
        let mut r = row(
            ALICE,
            if n % 3 == 0 { &offline } else { &online },
            tool,
            now - Duration::from_secs(90 * n as u64 + 30),
        );
        r.outcome = outcome.to_string();
        r.duration_ms = Some(*ms);
        if n == 3 {
            r.client_id = "some-other-app".into();
        }
        h.store.record_activity(&r).await.unwrap();
    }
    let carol = sign_in(&h, "carol").await;
    let pages: Vec<(&str, Reply)> = vec![
        ("sign-in", h.get("/").await),
        ("signed-out", h.get("/?signed_out=1").await),
        ("devices", b.get(&h, "/devices").await),
        ("devices-removed", b.get(&h, "/devices?done=removed").await),
        ("devices-empty", carol.get(&h, "/devices").await),
        ("device", b.get(&h, &format!("/devices/{online}")).await),
        (
            "device-name-refused",
            b.post(&h, &format!("/devices/{online}/rename"), &[("name", "  ")])
                .await,
        ),
        ("activity", b.get(&h, "/activity").await),
        (
            "activity-one",
            b.get(&h, &format!("/activity?device={online}")).await,
        ),
        ("activity-empty", carol.get(&h, "/activity").await),
        ("not-found", b.get(&h, "/devices/nope").await),
        (
            "forbidden",
            b.post_as(
                &h,
                &format!("/devices/{online}/remove"),
                &[],
                None,
                Some(PUBLIC_URL),
            )
            .await,
        ),
        ("no-access", {
            let (state, auth, _) = start_sign_in(&h).await;
            h.tokens.give_token(&crate::http::tests::mint_with_role(
                &h.rsa,
                crate::http::tests::DASHBOARD_CLIENT,
                "dave",
                Some(crate::http::tests::now_secs() + 600),
                None,
            ));
            h.send(
                "GET",
                &format!("/auth/callback?code=c&state={state}"),
                &[("cookie", auth)],
                "",
            )
            .await
        }),
    ];
    for (name, r) in pages {
        let page = r
            .body
            .replace("href=\"/static/relay.css\"", "href=\"static/relay.css\"");
        std::fs::write(dir.join(format!("{name}.html")), page).unwrap();
    }
    std::fs::write(dir.join("static/relay.css"), RELAY_CSS).unwrap();
}
