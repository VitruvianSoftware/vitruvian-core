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

//! The app sign-in's browser steps: `GET /oauth/authorize` (start),
//! `GET /oauth/callback` (the identity service sends the person back) and
//! `/oauth/consent` (the page where the person says Allow or Deny).
//!
//! The one thing this module exists to stop: someone with their own Gemini
//! registers a client, sends an invited person a link to `/oauth/authorize`,
//! and gets a code at their own callback, which is control of that person's
//! computer. So **no code is ever issued without a real Allow**: pressed in
//! the same browser that started the sign-in (the `vr_oauth` cookie, which
//! is also what finds the waiting consent: a new value made when the person
//! comes back, so one planted beforehand finds nothing), on a page that says who is
//! signed in, which app and which computer, carrying a form token only that
//! page has, posted from the relay's own origin, and used once.
//!
//! The identity service's code is exchanged *before* the page is shown, so
//! the role (`relay-user`) and the ownership of the computer are checked
//! first: a person who fails either never sees consent. Nothing here logs a
//! token, a code, a `state` or a callback id.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::UNIX_EPOCH;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use http::{header, HeaderValue, Request, Response, StatusCode};
use hyper::body::Incoming;
use serde_json::json;
use vitruvian_mcp_auth::{audience_scope_for, AuthError};

use super::clients::production_callback;
use super::http::client_key;
use super::pending::{random_token, AuthRequest, Consent, IssuedCode};
use crate::dashboard::pages::{esc, message_page, page_shell, Ctx};
use crate::dashboard::session::{cookie, cookie_value};
use crate::dashboard::{form_encode, parse_pairs, percent_decode, ExchangeError};
use crate::http::{header_str, read_body, valid_device_id, App, Body};
use crate::store::{StoreError, UNAVAILABLE_MESSAGE};

/// The cookie that ties a sign-in to the browser that started it.
pub(crate) const BINDING_COOKIE: &str = "vr_oauth";
const BINDING_PATH: &str = "/oauth/";
const BINDING_SECS: u64 = 10 * 60;
/// The app's `state` may be this long (bytes, after decoding). Gemini's is
/// over 1 KiB, so this leaves it plenty of room.
const MAX_STATE_BYTES: usize = 8 * 1024;
/// RFC 7636: a challenge is 43 to 128 characters.
const CHALLENGE_LEN: std::ops::RangeInclusive<usize> = 43..=128;
/// Longest query string `/oauth/authorize` reads: room for the longest
/// `state`, percent-encoded, and the other parameters.
const MAX_QUERY_BYTES: usize = 16 * 1024;
/// Largest consent form (a token and a choice).
const MAX_FORM_BYTES: usize = 4 * 1024;
/// The name the consent page gives the app that registers itself.
const APP_NAME: &str = "Gemini";
/// What the page says, word for word.
pub(crate) const WARNING: &str = "Only allow this if you just started connecting Gemini yourself. Allowing it lets that Gemini account use every computer on your account, and see your name and email.";
/// The page's heading and title. An Allow is not about one computer: the
/// token the app gets works on every computer the person has.
const HEADING: &str = "Allow Gemini to use your computers on Vitruvian Relay?";

/// Nothing loads but the relay's own stylesheet. `form-action` names the
/// app's callback host as well as the relay: browsers apply it to the
/// redirect that follows a form post, so without it Allow and Deny would
/// be blocked on their way back to the app. Only the production callback
/// host is ever redirected to.
pub(crate) const CSP: &str = "default-src 'none'; style-src 'self'; \
    form-action 'self' https://oauth-redirect.googleusercontent.com; \
    base-uri 'none'; frame-ancestors 'none'";

const HOME: (&str, &str) = ("/", "Vitruvian Relay");

// ---------------------------------------------------------------- responses

fn secure(app: &App) -> bool {
    app.settings.public_url.starts_with("https://")
}

fn binding_cookie(value: &str, secure: bool) -> String {
    cookie(BINDING_COOKIE, value, BINDING_PATH, BINDING_SECS, secure)
}

fn clear_binding_cookie(secure: bool) -> String {
    cookie(BINDING_COOKIE, "", BINDING_PATH, 0, secure)
}

/// Every response of the sign-in carries these: never cached, not framed
/// (so nobody can lay a button over the Allow), no referrer to other sites.
///
/// `same-origin` and not `no-referrer`: under `no-referrer` a browser sends
/// `Origin: null` with a form post, which the origin check on
/// `POST /oauth/consent` would then refuse, so Allow would never work.
/// `same-origin` sends no referrer to any other site.
fn hardened(status: StatusCode, content_type: &str, body: String) -> Response<Body> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "no-store")
        .header(header::X_FRAME_OPTIONS, "DENY")
        .header(header::CONTENT_SECURITY_POLICY, CSP)
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .header(header::REFERRER_POLICY, "same-origin")
        .body(Body::new(body))
        .expect("static response parts are valid")
}

fn html(status: StatusCode, body: String) -> Response<Body> {
    hardened(status, "text/html; charset=utf-8", body)
}

/// A page that only says something, with a way on.
fn say(status: StatusCode, title: &str, text: &str, link: (&str, &str)) -> Response<Body> {
    let ctx = Ctx {
        csrf: None,
        now: UNIX_EPOCH,
    };
    html(status, message_page(ctx, title, text, link))
}

/// 303 to `location`, which the caller has built from encoded parts.
fn redirect(location: &str) -> Response<Body> {
    let mut resp = hardened(
        StatusCode::SEE_OTHER,
        "text/plain; charset=utf-8",
        String::new(),
    );
    match HeaderValue::from_str(location) {
        Ok(v) => {
            resp.headers_mut().insert(header::LOCATION, v);
            resp
        }
        Err(_) => say(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Something went wrong",
            "Something went wrong on our side. Go back to your AI app and try again.",
            HOME,
        ),
    }
}

fn with_cookie(mut resp: Response<Body>, cookie: &str) -> Response<Body> {
    if let Ok(v) = HeaderValue::from_str(cookie) {
        resp.headers_mut().append(header::SET_COOKIE, v);
    }
    resp
}

fn now(app: &App) -> u64 {
    (app.timing.clock)()
}

/// What a request says about the browser binding.
enum Binding<'a> {
    /// No `vr_oauth` cookie, or an empty one.
    Missing,
    One(&'a str),
    /// More than one `vr_oauth` cookie. A page on a sibling subdomain can
    /// plant its own with the same name and a wider scope ("cookie tossing"),
    /// and which one a server reads first is then up to the browser. So two
    /// are refused rather than one picked.
    Many,
}

fn binding_of(req: &Request<Incoming>) -> Binding<'_> {
    let headers = || {
        req.headers()
            .get_all(header::COOKIE)
            .iter()
            .filter_map(|v| v.to_str().ok())
    };
    let named = headers()
        .flat_map(|h| h.split(';'))
        .filter_map(|pair| pair.trim().split_once('='))
        .filter(|(k, _)| *k == BINDING_COOKIE)
        .count();
    match (named, cookie_value(headers(), BINDING_COOKIE)) {
        (0, _) | (1, None) => Binding::Missing,
        (1, Some(value)) => Binding::One(value),
        _ => Binding::Many,
    }
}

// ---------------------------------------------------------------- authorize

/// The query as pairs, or `None` if a name appears twice (which the OAuth
/// specs forbid, and which would otherwise let two readers of one request
/// disagree about it).
pub(super) fn strict_pairs(query: &str) -> Option<HashMap<String, String>> {
    let mut out = HashMap::new();
    for pair in query.split('&').filter(|p| !p.is_empty()) {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        if out.insert(percent_decode(k), percent_decode(v)).is_some() {
            return None;
        }
    }
    Some(out)
}

/// A PKCE challenge: 43 to 128 of the characters RFC 7636 allows.
fn challenge_ok(c: &str) -> bool {
    CHALLENGE_LEN.contains(&c.len())
        && c.bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~'))
}

/// The app's `state`: present, short, and text that survives being decoded
/// (a lossy decode would change it, and it must come back unchanged).
fn state_ok(s: &str) -> bool {
    !s.is_empty() && s.len() <= MAX_STATE_BYTES && !s.contains('\u{FFFD}')
}

/// The device an app's `resource` names: exactly this relay's
/// `/mcp/app/<device id>` and nothing else.
fn device_of_resource(app: &App, resource: &str) -> Option<String> {
    let id = resource.strip_prefix(&format!("{}/mcp/app/", app.settings.public_url))?;
    (valid_device_id(id) && app.settings.app_mcp_url(id) == resource).then(|| id.to_string())
}

fn cannot_start() -> Response<Body> {
    say(
        StatusCode::BAD_REQUEST,
        "We could not start that sign-in",
        "The link from your AI app is not one Vitruvian Relay recognises. Go back to the app and start again.",
        HOME,
    )
}

/// An error sent back to the app's own callback, as RFC 6749 section 4.1.2.1
/// says to once the callback is known to be right. No code, no cookie.
fn error_to_app(callback: &str, error: &str, state: Option<&str>) -> Response<Body> {
    let mut url = format!("{callback}?error={error}");
    if let Some(s) = state.filter(|s| state_ok(s)) {
        url.push_str(&format!("&state={}", form_encode(s)));
    }
    redirect(&url)
}

/// `GET /oauth/authorize`: checks everything the app sent, then sends the
/// person to the identity service with the relay's own PKCE and `state`.
pub(super) async fn authorize(app: &Arc<App>, req: &Request<Incoming>) -> Response<Body> {
    let key = client_key(req);
    if let Err(retry) = app.authorize_limit.check(&key) {
        app.log("app_authorize_refused", json!({"why": "rate_limited"}));
        let mut r = say(
            StatusCode::TOO_MANY_REQUESTS,
            "Too many tries",
            "Too many sign-ins were started from your network. Wait a minute, then start again from your AI app.",
            HOME,
        );
        let secs = retry.after.as_secs_f64().ceil().max(1.0) as u64;
        r.headers_mut()
            .insert(header::RETRY_AFTER, HeaderValue::from(secs));
        return r;
    }
    let Some(signin) = app.settings.app_signin.as_ref() else {
        return crate::http::not_found();
    };
    let query = req.uri().query().unwrap_or("");
    let pairs = Some(query)
        .filter(|q| q.len() <= MAX_QUERY_BYTES)
        .and_then(strict_pairs);
    let Some(p) = pairs else {
        app.log("app_authorize_refused", json!({"why": "query"}));
        return cannot_start();
    };
    let get = |k: &str| p.get(k).map(String::as_str);

    // The client and the callback come first and decide whether anything may
    // be sent to the callback at all: a wrong one gets a page, never a
    // redirect. Only the production callback of the client's own id is used.
    let callback_id = get("client_id").and_then(|c| signin.keys.client_callback_id(c));
    let callback = match callback_id {
        Some(id) => production_callback(&id),
        None => {
            app.log("app_authorize_refused", json!({"why": "client"}));
            return cannot_start();
        }
    };
    if get("redirect_uri") != Some(callback.as_str()) {
        app.log("app_authorize_refused", json!({"why": "redirect_uri"}));
        return cannot_start();
    }
    let client_id = get("client_id").unwrap_or_default().to_string();

    // From here the callback is the app's own, so a refusal goes back to it.
    let state = get("state");
    if get("response_type") != Some("code") {
        app.log("app_authorize_refused", json!({"why": "response_type"}));
        return error_to_app(&callback, "unsupported_response_type", state);
    }
    let Some(state) = state.filter(|s| state_ok(s)) else {
        // The length only: the value is the app's and stays out of the log.
        let state_bytes = get("state").map_or(0, str::len);
        app.log(
            "app_authorize_refused",
            json!({"why": "state", "state_bytes": state_bytes}),
        );
        return error_to_app(&callback, "invalid_request", None);
    };
    let challenge = get("code_challenge").filter(|c| challenge_ok(c));
    let Some(challenge) = challenge.filter(|_| get("code_challenge_method") == Some("S256")) else {
        app.log("app_authorize_refused", json!({"why": "pkce"}));
        return error_to_app(&callback, "invalid_request", Some(state));
    };
    let resource = get("resource");
    let device = resource.and_then(|r| device_of_resource(app, r));
    let (Some(resource), Some(device_id)) = (resource, device) else {
        app.log("app_authorize_refused", json!({"why": "resource"}));
        return error_to_app(&callback, "invalid_target", Some(state));
    };

    app.log("app_authorize_started", json!({"state_bytes": state.len()}));
    let started = app.pending.begin(
        AuthRequest {
            client_id,
            callback,
            challenge: challenge.to_string(),
            resource: resource.to_string(),
            state: state.to_string(),
            device_id,
        },
        &key,
        now(app),
    );
    // An address with this many sign-ins waiting is refused; it does not
    // get to push out other people's.
    let Some(started) = started else {
        app.log("app_authorize_refused", json!({"why": "too_many_waiting"}));
        let mut r = say(
            StatusCode::TOO_MANY_REQUESTS,
            "Too many sign-ins waiting",
            "Too many sign-ins from your network are waiting to finish. Finish one, or wait ten minutes, then start again from your AI app.",
            HOME,
        );
        r.headers_mut()
            .insert(header::RETRY_AFTER, HeaderValue::from(60));
        return r;
    };
    // The project's audience scope puts the project in the token's audience,
    // which the token check requires; the role comes with it.
    let scope = format!(
        "openid profile email offline_access {}",
        audience_scope_for(&app.settings.project_id)
    );
    let url = format!(
        "{}?response_type=code&client_id={}&redirect_uri={}&scope={}&state={}\
         &code_challenge={}&code_challenge_method=S256&prompt=select_account",
        app.settings.authorize_url(),
        form_encode(&signin.client_id),
        form_encode(&app.settings.apps_callback_url()),
        form_encode(&scope),
        form_encode(&started.pkce.state),
        form_encode(&started.pkce.challenge()),
    );
    app.log("app_authorize_started", json!({}));
    with_cookie(
        redirect(&url),
        &binding_cookie(&started.browser, secure(app)),
    )
}

// ----------------------------------------------------------------- callback

fn not_started() -> Response<Body> {
    say(
        StatusCode::BAD_REQUEST,
        "That sign-in did not start here",
        "The sign-in link expired, or it was not started in this browser. Go back to your AI app and connect again.",
        HOME,
    )
}

fn try_again(status: StatusCode, title: &str, text: &str) -> Response<Body> {
    say(status, title, text, HOME)
}

/// The page for a computer that is not the person's: the same for someone
/// else's, one that was removed and one that never existed.
fn computer_not_found(app: &App) -> Response<Body> {
    app.log("app_signin_refused", json!({"why": "device"}));
    say(
        StatusCode::NOT_FOUND,
        "We could not find that computer",
        "It may have been removed, or the link from your AI app may be wrong. Your computers are listed on your Vitruvian Relay page.",
        ("/devices", "Your computers"),
    )
}

fn store_down(app: &App, e: &StoreError) -> Response<Body> {
    app.log("app_signin_store_failed", json!({"error": e.to_string()}));
    try_again(
        StatusCode::SERVICE_UNAVAILABLE,
        "Vitruvian Relay is having trouble",
        UNAVAILABLE_MESSAGE,
    )
}

/// What a person's name is worth on the page: the longest shown.
const WHO_PART_MAX: usize = 100;

/// Characters that are no use in a name and can make one read as something
/// else (controls, and the ones that reverse or hide text).
fn shown_char(c: char) -> bool {
    !c.is_control()
        && !matches!(c, '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
}

fn clean_part(raw: &str) -> Option<String> {
    let kept: String = raw.chars().filter(|c| shown_char(*c)).collect();
    let cut: String = kept.trim().chars().take(WHO_PART_MAX).collect();
    let cut = cut.trim();
    (!cut.is_empty()).then(|| cut.to_string())
}

/// How the person is named on the consent page: "name (email)", or
/// whichever the ID token has, or their id. The ID token came straight from
/// the identity service over TLS, so it is read without checking its
/// signature. That is for display only: nothing here decides anything, and
/// the access token is what is checked.
fn who_is(id_token: Option<&str>, subject: &str) -> String {
    let claims = id_token
        .and_then(|t| t.split('.').nth(1))
        .and_then(|p| URL_SAFE_NO_PAD.decode(p.trim_end_matches('=')).ok())
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).ok());
    let claim = |k: &str| {
        claims
            .as_ref()
            .and_then(|c| c.get(k)?.as_str())
            .and_then(clean_part)
    };
    match (claim("name"), claim("email")) {
        (Some(n), Some(e)) => format!("{n} ({e})"),
        (Some(x), None) | (None, Some(x)) => x,
        (None, None) => subject.to_string(),
    }
}

fn refused_sign_in() -> Response<Body> {
    say(
        StatusCode::FORBIDDEN,
        "We could not confirm your sign-in",
        "Vitruvian Relay could not accept that sign-in. Go back to your AI app and connect again, and use the account you were invited with.",
        HOME,
    )
}

/// `GET /oauth/callback`: the identity service sends the person back with a
/// code. The code is exchanged, the token checked (role included) and the
/// computer checked to be theirs, and only then does the person get a
/// consent page. Nothing is issued here.
pub(super) async fn callback(app: &Arc<App>, req: &Request<Incoming>) -> Response<Body> {
    let Some(signin) = app.settings.app_signin.as_ref() else {
        return crate::http::not_found();
    };
    let query = parse_pairs(req.uri().query().unwrap_or(""));
    let browser = match binding_of(req) {
        Binding::One(b) => b,
        Binding::Missing => {
            app.log("app_signin_refused", json!({"why": "state"}));
            return not_started();
        }
        Binding::Many => {
            app.log("app_signin_refused", json!({"why": "cookie"}));
            return not_started();
        }
    };
    let Some(state) = query.get("state") else {
        app.log("app_signin_refused", json!({"why": "state"}));
        return not_started();
    };
    // Once, and only to the browser that started it: another browser's
    // callback (a link someone else built) finds nothing and leaves the
    // real sign-in alone.
    let Some((request, verifier)) = app.pending.take_for_callback(state, browser, now(app)) else {
        app.log("app_signin_refused", json!({"why": "state"}));
        return not_started();
    };
    let Some(code) = query.get("code").filter(|c| !c.is_empty()) else {
        // The person said no, or the identity service could not go on.
        app.log("app_signin_refused", json!({"why": "no_code"}));
        return try_again(
            StatusCode::BAD_REQUEST,
            "Sign-in did not finish",
            "Nothing was changed. Go back to your AI app and connect again when you are ready.",
        );
    };

    let form = [
        ("grant_type", "authorization_code"),
        ("code", code.as_str()),
        ("redirect_uri", &app.settings.apps_callback_url()),
        ("client_id", &signin.client_id),
        ("code_verifier", &verifier),
    ]
    .iter()
    .map(|(k, v)| format!("{k}={}", form_encode(v)))
    .collect::<Vec<_>>()
    .join("&");
    let tokens = match app.dashboard.exchange(app.settings.token_url(), form).await {
        Ok(t) => t,
        Err(ExchangeError::Busy) => {
            app.log("app_signin_refused", json!({"why": "busy"}));
            return try_again(
                StatusCode::SERVICE_UNAVAILABLE,
                "Signing in is busy",
                "Signing in is busy right now. Go back to your AI app and connect again in a minute.",
            );
        }
        Err(ExchangeError::Failed(why) | ExchangeError::Refused(why)) => {
            app.log("app_signin_failed", json!({"why": why}));
            return try_again(
                StatusCode::BAD_GATEWAY,
                "Sign-in could not finish",
                "The sign-in service did not give Vitruvian Relay what it needed. Go back to your AI app and connect again in a minute.",
            );
        }
        Err(ExchangeError::Internal) => {
            return try_again(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Sign-in could not finish",
                "Something went wrong on our side. Go back to your AI app and connect again in a minute.",
            )
        }
    };

    // The token is checked as an AI app's token is, role included: a person
    // who signed in but was never invited stops here.
    let checker = app.mcp_verifier.clone();
    let access = tokens.access_token.clone();
    let caller = match tokio::task::spawn_blocking(move || checker.verify(&access)).await {
        Ok(Ok(caller)) if caller.client_id == signin.client_id => caller,
        Ok(Ok(_)) => {
            app.log(
                "auth_refused",
                json!({"route": "oauth_callback", "code": "client_not_allowed"}),
            );
            return refused_sign_in();
        }
        Ok(Err(e)) => {
            // The code only: the checker's message can name the subject.
            app.log(
                "auth_refused",
                json!({"route": "oauth_callback", "code": e.log_code()}),
            );
            return match e {
                AuthError::RoleMissing { .. } => say(
                    StatusCode::FORBIDDEN,
                    "You do not have access yet",
                    "Your account signed in, but it has not been invited to Vitruvian Relay. Ask the person who runs it to invite you, then connect again.",
                    HOME,
                ),
                AuthError::IdpUnavailable { .. } => try_again(
                    StatusCode::SERVICE_UNAVAILABLE,
                    "Sign-in is not answering",
                    "The sign-in service is not answering right now. Go back to your AI app and connect again in a minute.",
                ),
                _ => refused_sign_in(),
            };
        }
        Err(_) => {
            return try_again(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Sign-in could not finish",
                "Something went wrong on our side. Go back to your AI app and connect again in a minute.",
            )
        }
    };

    // The computer must be this person's. Someone else's and one that does
    // not exist get the same page.
    let device = match app.owned_device(&caller.subject, &request.device_id).await {
        Ok(Some(d)) => d,
        Ok(None) => return computer_not_found(app),
        Err(e) => return store_down(app, &e),
    };

    // A new binding, made now: the one the browser sent was set (or planted
    // by a page on a sibling subdomain, "cookie tossing") before the person
    // signed in, so it cannot be the one that reaches the consent page.
    // Without this, whoever planted a value could post Allow with it.
    let bound = random_token();
    app.pending.put_consent(
        &bound,
        Consent {
            request,
            who: who_is(tokens.id_token.as_deref(), &caller.subject),
            subject: caller.subject,
            device_name: device.name,
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            expires_in: tokens.expires_in.unwrap_or(3600),
            csrf: random_token(),
        },
        now(app),
    );
    // Off the address that carries the sign-in code, so reloading cannot
    // replay it.
    with_cookie(
        redirect("/oauth/consent"),
        &binding_cookie(&bound, secure(app)),
    )
}

// ------------------------------------------------------------------ consent

fn expired() -> Response<Body> {
    say(
        StatusCode::BAD_REQUEST,
        "This request has expired",
        "It was not started in this browser, or it took too long. Go back to your AI app and connect again.",
        HOME,
    )
}

/// What the page shows about a waiting consent.
struct View {
    who: String,
    device_name: String,
    /// The last 8 characters of the app's callback id.
    callback_tail: String,
    csrf: String,
}

fn consent_html(v: &View) -> String {
    page_shell(
        HEADING,
        &format!(
            "<section class=\"message\"><h1>{heading}</h1>\
             <ul class=\"cards\"><li class=\"card\">\
             <p class=\"meta\">Signed in as</p><p><strong>{who}</strong></p>\
             <p class=\"meta\">App</p><p><strong>{app}</strong>, connection ending in <code>{tail}</code></p>\
             <p class=\"meta\">Computer being connected</p><p><strong>{computer}</strong></p>\
             </li></ul>\
             <p class=\"note bad\" role=\"alert\">{warning}</p>\
             <form method=\"post\" action=\"/oauth/consent\">\
             <input type=\"hidden\" name=\"csrf\" value=\"{csrf}\">\
             <p class=\"actions\">\
             <button type=\"submit\" name=\"decision\" value=\"allow\">Allow</button> \
             <button type=\"submit\" name=\"decision\" value=\"deny\">Deny</button></p>\
             </form></section>",
            heading = esc(HEADING),
            app = APP_NAME,
            who = esc(&v.who),
            tail = esc(&v.callback_tail),
            computer = esc(&v.device_name),
            warning = esc(WARNING),
            csrf = esc(&v.csrf),
        ),
    )
}

/// `GET /oauth/consent`: the page, for the sign-in waiting in this browser.
pub(super) fn consent_page(app: &Arc<App>, req: &Request<Incoming>) -> Response<Body> {
    let Binding::One(browser) = binding_of(req) else {
        return expired();
    };
    let view = app.pending.view_consent(browser, now(app), |c| View {
        who: c.who.clone(),
        device_name: c.device_name.clone(),
        callback_tail: {
            let mut last: Vec<char> = c.request.callback.chars().rev().take(8).collect();
            last.reverse();
            last.into_iter().collect()
        },
        csrf: c.csrf.clone(),
    });
    match view {
        Some(v) => html(StatusCode::OK, consent_html(&v)),
        None => expired(),
    }
}

fn consent_refused(app: &App, why: &str) -> Response<Body> {
    app.log("app_consent_refused", json!({"why": why}));
    say(
        StatusCode::FORBIDDEN,
        "That did not work",
        "Vitruvian Relay could not tell that this answer came from its own page, or the request has expired. Nothing was allowed. Go back to your AI app and connect again.",
        HOME,
    )
}

/// `POST /oauth/consent`: Allow or Deny. Every check below must pass, and
/// any that fails does nothing at all and issues no code.
pub(super) async fn consent_decide(app: &Arc<App>, req: Request<Incoming>) -> Response<Body> {
    if header_str(&req, header::ORIGIN) != Some(app.settings.public_url.as_str()) {
        return consent_refused(app, "origin");
    }
    let Binding::One(browser) = binding_of(&req) else {
        return consent_refused(app, "cookie");
    };
    let browser = browser.to_string();
    let bytes = match read_body(req.into_body(), MAX_FORM_BYTES, app.timing.body_timeout).await {
        Ok(b) => b,
        Err(resp) => return *resp,
    };
    let form = parse_pairs(&String::from_utf8_lossy(&bytes));
    let allow = match form.get("decision").map(String::as_str) {
        Some("allow") => true,
        Some("deny") => false,
        _ => return consent_refused(app, "decision"),
    };
    let Some(csrf) = form.get("csrf") else {
        return consent_refused(app, "csrf");
    };
    // The check of the form token and the removal are one step: the same
    // consent is never decided twice.
    let Some(c) = app.pending.take_consent(&browser, csrf, now(app)) else {
        return consent_refused(app, "csrf_or_expired");
    };
    let r = c.request;
    // Allow: the computer must still be this person's. It may have been
    // removed since the page was shown, or the database may not answer, and
    // either way no code is issued.
    if allow {
        match app.owned_device(&c.subject, &r.device_id).await {
            Ok(Some(_)) => {}
            Ok(None) => return computer_not_found(app),
            Err(e) => return store_down(app, &e),
        }
    }
    let to_app = if allow {
        let code = random_token();
        let url = format!(
            "{}?code={}&state={}",
            r.callback,
            form_encode(&code),
            form_encode(&r.state)
        );
        app.pending.put_code(
            &code,
            IssuedCode {
                client_id: r.client_id,
                callback: r.callback,
                challenge: r.challenge,
                resource: r.resource,
                access_token: c.access_token,
                refresh_token: c.refresh_token,
                expires_in: c.expires_in,
                subject: c.subject,
                device_id: r.device_id.clone(),
            },
            now(app),
        );
        app.log("app_consent_allowed", json!({"device_id": r.device_id}));
        url
    } else {
        app.log("app_consent_denied", json!({"device_id": r.device_id}));
        format!(
            "{}?error=access_denied&state={}",
            r.callback,
            form_encode(&r.state)
        )
    };
    with_cookie(redirect(&to_app), &clear_binding_cookie(secure(app)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_binding_cookie_has_every_protection() {
        assert_eq!(
            binding_cookie("abc", true),
            "vr_oauth=abc; HttpOnly; Secure; SameSite=Lax; Path=/oauth/; Max-Age=600"
        );
        // Only a relay on plain local http drops Secure.
        assert_eq!(
            binding_cookie("abc", false),
            "vr_oauth=abc; HttpOnly; SameSite=Lax; Path=/oauth/; Max-Age=600"
        );
        assert!(clear_binding_cookie(true).contains("Max-Age=0"));
    }

    #[test]
    fn challenges_are_43_to_128_url_safe_characters() {
        assert!(challenge_ok(&"a".repeat(43)));
        assert!(challenge_ok(&"A-_.~9".repeat(22)[..128]));
        assert!(!challenge_ok(&"a".repeat(42)));
        assert!(!challenge_ok(&"a".repeat(129)));
        assert!(!challenge_ok(&format!("{}+", "a".repeat(43))));
        assert!(!challenge_ok(&format!("{}=", "a".repeat(43))));
        assert!(!challenge_ok(&format!("{} ", "a".repeat(43))));
    }

    #[test]
    fn state_is_present_short_and_survives_decoding() {
        assert!(state_ok("abc"));
        assert!(state_ok(&"s".repeat(MAX_STATE_BYTES)));
        assert!(!state_ok(""));
        assert!(!state_ok(&"s".repeat(MAX_STATE_BYTES + 1)));
        assert!(!state_ok("bad\u{FFFD}"));
    }

    #[test]
    fn a_repeated_name_refuses_the_whole_query() {
        assert!(strict_pairs("a=1&b=2").is_some());
        assert!(strict_pairs("a=1&a=2").is_none());
        assert!(strict_pairs("a=1&%61=2").is_none());
    }

    #[test]
    fn the_person_is_named_from_the_id_token_or_their_id() {
        let token = |claims: &str| format!("h.{}.s", URL_SAFE_NO_PAD.encode(claims.as_bytes()));
        assert_eq!(
            who_is(Some(&token(r#"{"name":"A B","email":"a@b.c"}"#)), "sub-1"),
            "A B (a@b.c)"
        );
        assert_eq!(who_is(Some(&token(r#"{"name":"A B"}"#)), "sub-1"), "A B");
        assert_eq!(
            who_is(Some(&token(r#"{"email":"a@b.c"}"#)), "sub-1"),
            "a@b.c"
        );
        for bad in [None, Some("x"), Some("a.b.c"), Some("a..c"), Some("")] {
            assert_eq!(who_is(bad, "sub-1"), "sub-1", "{bad:?}");
        }
        assert_eq!(who_is(Some(&token(r#"{"name":5}"#)), "sub-1"), "sub-1");
        // Text that can reverse or hide what is around it is dropped, and
        // a long name is cut.
        assert_eq!(
            who_is(Some(&token(r#"{"name":"A\u202eB\u0007"}"#)), "s"),
            "AB"
        );
        let long = format!(r#"{{"name":"{}"}}"#, "x".repeat(500));
        assert_eq!(
            who_is(Some(&token(&long)), "s").chars().count(),
            WHO_PART_MAX
        );
    }
}
