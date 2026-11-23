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

//! The app sign-in's public endpoints: the authorization server's metadata
//! and `POST /oauth/register`. Both answer 404 unless the feature is on.
//!
//! Registration stores nothing: the client id and secret are derived from the
//! redirect URIs' shared id (see [`super::clients`]), so the only thing an
//! open endpoint can cost is CPU, and that is held down by a per-address
//! limit.

use std::net::IpAddr;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use http::{header, HeaderValue, Method, Request, Response, StatusCode};
use hyper::body::Incoming;
use serde_json::{json, Value};

use super::clients::parse_registration;
use super::consent;
use crate::http::{header_str, json_response, not_found, read_body, text, App, Body};

/// The one scope an app asks for and the relay's tokens carry.
pub(crate) const SCOPE: &str = "mcp:tools";
/// Registration bodies are a few hundred bytes; anything bigger is not one.
const MAX_REGISTER_BODY: usize = 16 * 1024;
const GRANTS: [&str; 2] = ["authorization_code", "refresh_token"];
const AUTH_METHODS: [&str; 2] = ["client_secret_post", "client_secret_basic"];
const METADATA_PATH: &str = "/.well-known/oauth-authorization-server";
/// Where every address with no usable header lands.
const UNKNOWN_CLIENT: &str = "unknown";

#[derive(Clone, Copy)]
enum Route {
    Metadata,
    Register,
    Authorize,
    Callback,
    Consent,
    /// `/oauth/token`: built in a later task.
    NotYet,
}

fn route(path: &str) -> Option<Route> {
    match path {
        METADATA_PATH => Some(Route::Metadata),
        "/oauth/register" => Some(Route::Register),
        "/oauth/authorize" => Some(Route::Authorize),
        "/oauth/callback" => Some(Route::Callback),
        "/oauth/consent" => Some(Route::Consent),
        "/oauth/token" => Some(Route::NotYet),
        _ => None,
    }
}

/// True for the paths this module answers (whatever the method, and whether
/// or not the feature is on: [`handle`] says 404 when it is off).
pub fn wants(_method: &Method, path: &str) -> bool {
    route(path).is_some()
}

pub async fn handle(app: Arc<App>, req: Request<Incoming>) -> Response<Body> {
    if app.settings.app_signin.is_none() {
        return not_found();
    }
    let Some(route) = route(req.uri().path()) else {
        return not_found();
    };
    match (route, req.method()) {
        (Route::Metadata, &Method::GET) => {
            json_response(StatusCode::OK, &authorization_server_metadata(&app))
        }
        (Route::Metadata, _) => wrong_method("GET"),
        (Route::Register, &Method::POST) => register(&app, req).await,
        (Route::Register, _) => wrong_method("POST"),
        (Route::Authorize, &Method::GET) => consent::authorize(&app, &req).await,
        (Route::Authorize, _) => wrong_method("GET"),
        (Route::Callback, &Method::GET) => consent::callback(&app, &req).await,
        (Route::Callback, _) => wrong_method("GET"),
        (Route::Consent, &Method::GET) => consent::consent_page(&app, &req),
        (Route::Consent, &Method::POST) => consent::consent_decide(&app, req).await,
        (Route::Consent, _) => wrong_method("GET, POST"),
        (Route::NotYet, _) => text(StatusCode::NOT_IMPLEMENTED, "not implemented"),
    }
}

fn wrong_method(allow: &'static str) -> Response<Body> {
    let mut r = text(StatusCode::METHOD_NOT_ALLOWED, "wrong method");
    r.headers_mut()
        .insert(header::ALLOW, HeaderValue::from_static(allow));
    r
}

/// RFC 8414 metadata. The issuer is the public URL exactly, with no trailing
/// slash, as clients compare it to the one they fetched this from.
fn authorization_server_metadata(app: &App) -> Value {
    let base = &app.settings.public_url;
    json!({
        "issuer": base,
        "authorization_endpoint": format!("{base}/oauth/authorize"),
        "token_endpoint": format!("{base}/oauth/token"),
        "registration_endpoint": format!("{base}/oauth/register"),
        "response_types_supported": ["code"],
        "grant_types_supported": GRANTS,
        "code_challenge_methods_supported": ["S256"],
        "token_endpoint_auth_methods_supported": AUTH_METHODS,
        "scopes_supported": [SCOPE],
    })
}

/// The protected-resource document for an app's URL: the relay is its own
/// authorization server.
pub(crate) fn app_protected_resource_metadata(app: &App, device_id: &str) -> Value {
    json!({
        "resource": app.settings.app_mcp_url(device_id),
        "authorization_servers": [app.settings.public_url],
        "bearer_methods_supported": ["header"],
        "scopes_supported": [SCOPE],
    })
}

/// The key a request is limited under. Traffic arrives through a Cloudflare
/// tunnel, which sets `CF-Connecting-IP` itself, so the header is the
/// caller's address. An IPv6 caller is limited by its /64 (a person holds a
/// whole one, so per-address would give one person endless buckets). A
/// missing or malformed header shares one bucket rather than getting a
/// fresh one per value.
pub(super) fn client_key(req: &Request<Incoming>) -> String {
    let ip = header_str(req, header::HeaderName::from_static("cf-connecting-ip"))
        .and_then(|v| v.trim().parse::<IpAddr>().ok());
    match ip {
        Some(IpAddr::V4(a)) => a.to_string(),
        Some(IpAddr::V6(a)) => match a.to_ipv4_mapped() {
            Some(v4) => v4.to_string(),
            None => {
                let s = a.segments();
                format!("{:x}:{:x}:{:x}:{:x}::/64", s[0], s[1], s[2], s[3])
            }
        },
        None => UNKNOWN_CLIENT.to_string(),
    }
}

fn error(code: &'static str) -> Response<Body> {
    json_response(StatusCode::BAD_REQUEST, &json!({"error": code}))
}

/// A list of strings from `v` (or `default` when absent), every one of
/// which must be in `allowed`.
fn allowed_list(v: Option<&Value>, default: &[&str], allowed: &[&str]) -> Option<Vec<String>> {
    let Some(v) = v else {
        return Some(default.iter().map(|s| s.to_string()).collect());
    };
    let items = v.as_array()?;
    let list: Option<Vec<String>> = items
        .iter()
        .map(|i| i.as_str().filter(|s| allowed.contains(s)).map(String::from))
        .collect();
    list.filter(|l| !l.is_empty())
}

async fn register(app: &App, req: Request<Incoming>) -> Response<Body> {
    let key = client_key(&req);
    if let Err(retry) = app.register_limit.check(&key) {
        app.log("app_register_refused", json!({"reason": "rate_limited"}));
        let mut r = json_response(
            StatusCode::TOO_MANY_REQUESTS,
            &json!({"error": "rate_limited"}),
        );
        let secs = retry.after.as_secs_f64().ceil().max(1.0) as u64;
        r.headers_mut()
            .insert(header::RETRY_AFTER, HeaderValue::from(secs));
        return r;
    }
    let bytes = match read_body(req.into_body(), MAX_REGISTER_BODY, app.timing.body_timeout).await {
        Ok(b) => b,
        Err(resp) => return *resp,
    };
    let Some(signin) = app.settings.app_signin.as_ref() else {
        return not_found();
    };
    let Ok(Value::Object(doc)) = serde_json::from_slice::<Value>(&bytes) else {
        return error("invalid_client_metadata");
    };
    // The redirect URIs decide everything: a shape other than Gemini's
    // six is a bad redirect URI, whatever else is wrong with the request.
    let uris: Vec<String> = match doc.get("redirect_uris") {
        None => Vec::new(),
        Some(Value::Array(items)) => {
            let strings: Option<Vec<String>> =
                items.iter().map(|i| i.as_str().map(String::from)).collect();
            match strings {
                Some(s) => s,
                None => return error("invalid_client_metadata"),
            }
        }
        Some(_) => return error("invalid_client_metadata"),
    };
    let id = match parse_registration(&uris) {
        Ok(id) => id,
        Err(_) => return error("invalid_redirect_uri"),
    };
    let grants = allowed_list(doc.get("grant_types"), &GRANTS[..1], &GRANTS);
    let responses = allowed_list(doc.get("response_types"), &["code"], &["code"]);
    // Either allowed method is accepted, and the answer is always
    // `client_secret_post` (RFC 7591 lets the server choose; the token
    // endpoint takes both).
    let method_ok = match doc.get("token_endpoint_auth_method") {
        None => true,
        Some(v) => v.as_str().is_some_and(|m| AUTH_METHODS.contains(&m)),
    };
    let name = match doc.get("client_name") {
        None => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return error("invalid_client_metadata"),
    };
    let (Some(grants), Some(responses), true) = (grants, responses, method_ok) else {
        return error("invalid_client_metadata");
    };
    let (client_id, client_secret) = signin.keys.issue_client(&id);
    let issued_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let mut out = json!({
        "client_id": client_id,
        "client_secret": client_secret,
        "client_id_issued_at": issued_at,
        "client_secret_expires_at": 0,
        "redirect_uris": uris,
        "grant_types": grants,
        "response_types": responses,
        "token_endpoint_auth_method": "client_secret_post",
    });
    if let Some(name) = name {
        out["client_name"] = json!(name);
    }
    app.log("app_registered", json!({}));
    let mut r = json_response(StatusCode::CREATED, &out);
    r.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    r
}
