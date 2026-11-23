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

//! `POST /oauth/token`: an app redeems the one-time code it was sent, or
//! refreshes. Nothing is stored here either.
//!
//! The access token an app gets is the identity service's own, so the same
//! check that guards every other token guards it. The refresh token is not:
//! it is sealed with the server key and the client's id (see
//! [`super::seal`]), so another registered client cannot use it, and the
//! identity service's refresh token never leaves the relay.
//!
//! Every failure of a code is `invalid_grant`, and the code is spent first,
//! so a guess at the verifier, the callback or the resource costs the
//! guesser the code. Nothing here logs a token, a code, a verifier, a
//! secret, or what the identity service said: only the event and an outcome
//! code.

use std::collections::HashMap;
use std::sync::Arc;

use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD};
use base64::Engine;
use http::{header, HeaderMap, HeaderValue, Request, Response, StatusCode};
use hyper::body::Incoming;
use serde_json::{json, Value};
use vitruvian_mcp_auth::AuthError;

use super::consent::strict_pairs;
use super::http::client_key;
use crate::dashboard::session::{challenge_for, same_secret};
use crate::dashboard::{form_encode, percent_decode, ExchangeError};
use crate::http::{json_response, read_body, token_exp, App, Body};

/// A token request is a handful of short fields.
const MAX_BODY: usize = 16 * 1024;
/// What a 503 tells the app to wait, in seconds.
const RETRY_AFTER_SECS: u64 = 5;
/// Used if the identity service's answer did not say how long a token lives
/// and the token itself does not either.
const DEFAULT_EXPIRES_IN: u64 = 3600;

/// Why a request got no tokens, named as RFC 6749 section 5.2 names them.
enum Refusal {
    InvalidRequest,
    /// The client did not prove who it is. `basic` says it tried HTTP Basic,
    /// which the answer must then say how to retry.
    InvalidClient {
        basic: bool,
    },
    InvalidGrant,
    UnsupportedGrantType,
    /// The identity service or the database is not answering, or there is
    /// no room to ask: try again shortly.
    Unavailable,
    Server,
    /// The body could not be read (too big, too slow): already an answer.
    Body(Box<Response<Body>>),
}

impl Refusal {
    fn code(&self) -> &'static str {
        match self {
            Refusal::InvalidRequest => "invalid_request",
            Refusal::InvalidClient { .. } => "invalid_client",
            Refusal::InvalidGrant => "invalid_grant",
            Refusal::UnsupportedGrantType => "unsupported_grant_type",
            Refusal::Unavailable => "temporarily_unavailable",
            Refusal::Server => "server_error",
            Refusal::Body(_) => "body",
        }
    }

    fn into_response(self) -> Response<Body> {
        let status = match &self {
            Refusal::InvalidClient { .. } => StatusCode::UNAUTHORIZED,
            Refusal::Unavailable => StatusCode::SERVICE_UNAVAILABLE,
            Refusal::Server => StatusCode::INTERNAL_SERVER_ERROR,
            Refusal::Body(_) => StatusCode::BAD_REQUEST,
            _ => StatusCode::BAD_REQUEST,
        };
        let code = self.code();
        let mut resp = match self {
            Refusal::Body(resp) => return *resp,
            _ => json_response(status, &json!({"error": code})),
        };
        match self {
            Refusal::InvalidClient { basic: true } => {
                resp.headers_mut().insert(
                    header::WWW_AUTHENTICATE,
                    HeaderValue::from_static("Basic realm=\"oauth\""),
                );
            }
            Refusal::Unavailable => {
                resp.headers_mut()
                    .insert(header::RETRY_AFTER, HeaderValue::from(RETRY_AFTER_SECS));
            }
            _ => {}
        }
        resp
    }
}

/// Tokens are never cached, by the app or anything between.
pub(super) fn no_store(mut resp: Response<Body>) -> Response<Body> {
    let h = resp.headers_mut();
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    h.insert(header::PRAGMA, HeaderValue::from_static("no-cache"));
    resp
}

pub(super) async fn token(app: &Arc<App>, req: Request<Incoming>) -> Response<Body> {
    // Before anything is read: the limit is what keeps one address from
    // using up the identity service's few places.
    if let Err(retry) = app.token_limit.check(&client_key(&req)) {
        app.log(
            "app_token_refused",
            json!({"grant": "unknown", "code": "rate_limited"}),
        );
        let mut r = json_response(
            StatusCode::TOO_MANY_REQUESTS,
            &json!({"error": "rate_limited"}),
        );
        let secs = retry.after.as_secs_f64().ceil().max(1.0) as u64;
        r.headers_mut()
            .insert(header::RETRY_AFTER, HeaderValue::from(secs));
        return no_store(r);
    }
    let mut grant = "unknown";
    let resp = match issue(app, req, &mut grant).await {
        Ok(body) => {
            app.log("app_token_issued", json!({"grant": grant}));
            json_response(StatusCode::OK, &body)
        }
        Err(refusal) => {
            app.log(
                "app_token_refused",
                json!({"grant": grant, "code": refusal.code()}),
            );
            refusal.into_response()
        }
    };
    no_store(resp)
}

/// `name`'s value if the request has it and it is not empty.
fn required<'a>(form: &'a HashMap<String, String>, name: &str) -> Result<&'a str, Refusal> {
    form.get(name)
        .map(String::as_str)
        .filter(|v| !v.is_empty())
        .ok_or(Refusal::InvalidRequest)
}

/// The id and secret of an `Authorization: Basic` header (RFC 6749 section
/// 2.3.1: each is form-encoded before the two are joined).
fn parse_basic(value: &HeaderValue) -> Option<(String, String)> {
    let (scheme, rest) = value.to_str().ok()?.trim().split_once(' ')?;
    if !scheme.eq_ignore_ascii_case("basic") {
        return None;
    }
    let rest = rest.trim();
    let raw = STANDARD
        .decode(rest)
        .or_else(|_| STANDARD_NO_PAD.decode(rest))
        .ok()?;
    let (id, secret) = std::str::from_utf8(&raw).ok()?.split_once(':')?;
    Some((percent_decode(id), percent_decode(secret)))
}

/// Who is calling, proved by their secret. Basic or the body, never both.
fn authenticate(
    app: &App,
    headers: &HeaderMap,
    form: &HashMap<String, String>,
) -> Result<String, Refusal> {
    let signin = app.settings.app_signin.as_ref().ok_or(Refusal::Server)?;
    let mut given = headers.get_all(header::AUTHORIZATION).iter();
    let basic = given.next();
    if given.next().is_some() {
        return Err(Refusal::InvalidRequest);
    }
    let (id, secret, by_basic) = match basic {
        Some(value) => {
            let (id, secret) = parse_basic(value).ok_or(Refusal::InvalidClient { basic: true })?;
            if form.contains_key("client_secret") {
                return Err(Refusal::InvalidRequest);
            }
            if form.get("client_id").is_some_and(|body_id| *body_id != id) {
                return Err(Refusal::InvalidRequest);
            }
            (id, secret, true)
        }
        None => {
            let none = Refusal::InvalidClient { basic: false };
            let id =
                required(form, "client_id").map_err(|_| Refusal::InvalidClient { basic: false })?;
            let secret = required(form, "client_secret").map_err(|_| none)?;
            (id.to_string(), secret.to_string(), false)
        }
    };
    if signin.keys.secret_ok(&id, &secret) {
        Ok(id)
    } else {
        Err(Refusal::InvalidClient { basic: by_basic })
    }
}

/// Checks the request and gives the answer's body.
async fn issue(
    app: &Arc<App>,
    req: Request<Incoming>,
    grant: &mut &'static str,
) -> Result<Value, Refusal> {
    let headers = req.headers().clone();
    let bytes = read_body(req.into_body(), MAX_BODY, app.timing.body_timeout)
        .await
        .map_err(Refusal::Body)?;
    let form = std::str::from_utf8(&bytes)
        .ok()
        .and_then(strict_pairs)
        .ok_or(Refusal::InvalidRequest)?;
    // Who is asking comes first: a caller that cannot prove it is a
    // registered client touches no code and no token.
    let client_id = authenticate(app, &headers, &form)?;
    match required(&form, "grant_type")? {
        "authorization_code" => {
            *grant = "authorization_code";
            redeem(app, &client_id, &form).await
        }
        "refresh_token" => {
            *grant = "refresh_token";
            refresh(app, &client_id, &form).await
        }
        _ => Err(Refusal::UnsupportedGrantType),
    }
}

/// The success body. `expires_in` is counted from the token's own expiry
/// when it has one: a code can wait a few minutes for the app to redeem it,
/// and the identity service's figure is from when it was issued.
fn success(
    app: &App,
    access_token: &str,
    given_expires_in: Option<u64>,
    refresh_token: Option<String>,
) -> Value {
    let now = (app.timing.clock)();
    let expires_in = token_exp(access_token)
        .map(|exp| exp.saturating_sub(now).max(1))
        .or(given_expires_in)
        .unwrap_or(DEFAULT_EXPIRES_IN);
    let mut out = json!({
        "access_token": access_token,
        "token_type": "Bearer",
        "expires_in": expires_in,
    });
    if let Some(r) = refresh_token {
        out["refresh_token"] = json!(r);
    }
    out
}

/// What the app's refresh token holds. Sealed with the client's id, so only
/// that client can hand it back.
fn seal_refresh(
    app: &App,
    client_id: &str,
    zitadel: &str,
    device_id: &str,
    subject: &str,
) -> Result<String, Refusal> {
    let keys = &app
        .settings
        .app_signin
        .as_ref()
        .ok_or(Refusal::Server)?
        .keys;
    let payload = json!({
        "refresh_token": zitadel,
        "device_id": device_id,
        "subject": subject,
    });
    Ok(keys.seal(client_id, payload.to_string().as_bytes()))
}

/// The computer must still be the person's: it may have been removed since
/// the code was issued, or since the last refresh.
async fn still_theirs(app: &App, subject: &str, device_id: &str) -> Result<(), Refusal> {
    match app.owned_device(subject, device_id).await {
        Ok(Some(_)) => Ok(()),
        Ok(None) => Err(Refusal::InvalidGrant),
        Err(_) => Err(Refusal::Unavailable),
    }
}

async fn redeem(
    app: &Arc<App>,
    client_id: &str,
    form: &HashMap<String, String>,
) -> Result<Value, Refusal> {
    let code = required(form, "code")?;
    let redirect_uri = required(form, "redirect_uri")?;
    let verifier = required(form, "code_verifier")?;
    // Spent here, whatever follows.
    let issued = app
        .pending
        .take_code(code, (app.timing.clock)())
        .ok_or(Refusal::InvalidGrant)?;
    // Every check runs, so none of them tells the caller which one failed.
    let same_client = issued.client_id == client_id;
    let same_callback = issued.callback == redirect_uri;
    let same_resource = form.get("resource").is_none_or(|r| *r == issued.resource);
    let proven = same_secret(&challenge_for(verifier), &issued.challenge);
    if !(same_client && same_callback && same_resource && proven) {
        return Err(Refusal::InvalidGrant);
    }
    still_theirs(app, &issued.subject, &issued.device_id).await?;
    let refresh_token = match &issued.refresh_token {
        Some(z) => Some(seal_refresh(
            app,
            client_id,
            z,
            &issued.device_id,
            &issued.subject,
        )?),
        None => None,
    };
    Ok(success(
        app,
        &issued.access_token,
        Some(issued.expires_in),
        refresh_token,
    ))
}

async fn refresh(
    app: &Arc<App>,
    client_id: &str,
    form: &HashMap<String, String>,
) -> Result<Value, Refusal> {
    let signin = app.settings.app_signin.as_ref().ok_or(Refusal::Server)?;
    let presented = required(form, "refresh_token")?;
    let sealed: Value = signin
        .keys
        .open(client_id, presented)
        .and_then(|plain| serde_json::from_slice(&plain).ok())
        .ok_or(Refusal::InvalidGrant)?;
    let field = |name: &str| sealed.get(name).and_then(Value::as_str).map(String::from);
    let (Some(zitadel), Some(device_id), Some(subject)) =
        (field("refresh_token"), field("device_id"), field("subject"))
    else {
        return Err(Refusal::InvalidGrant);
    };

    // Zitadel is asked as the apps' public client, within the same few
    // places every sign-in shares.
    let ask = [
        ("grant_type", "refresh_token"),
        ("refresh_token", zitadel.as_str()),
        ("client_id", signin.client_id.as_str()),
    ]
    .iter()
    .map(|(k, v)| format!("{k}={}", form_encode(v)))
    .collect::<Vec<_>>()
    .join("&");
    let tokens = match app.dashboard.exchange(app.settings.token_url(), ask).await {
        Ok(t) => t,
        Err(ExchangeError::Refused(_)) => return Err(Refusal::InvalidGrant),
        Err(ExchangeError::Busy | ExchangeError::Failed(_)) => return Err(Refusal::Unavailable),
        Err(ExchangeError::Internal) => return Err(Refusal::Server),
    };

    // The new token is checked as every app token is, role included, so a
    // person whose role was removed stops refreshing here, and it must be
    // the same person the app was given.
    let checker = app.mcp_verifier.clone();
    let access = tokens.access_token.clone();
    match tokio::task::spawn_blocking(move || checker.verify(&access)).await {
        Ok(Ok(caller)) if caller.client_id == signin.client_id && caller.subject == subject => {}
        Ok(Ok(_)) => return Err(Refusal::InvalidGrant),
        Ok(Err(AuthError::IdpUnavailable { .. })) => return Err(Refusal::Unavailable),
        Ok(Err(_)) => return Err(Refusal::InvalidGrant),
        Err(_) => return Err(Refusal::Server),
    }
    still_theirs(app, &subject, &device_id).await?;

    // If the identity service did not rotate its refresh token, the old one
    // is sealed again.
    let next = tokens.refresh_token.as_deref().unwrap_or(&zitadel);
    let sealed = seal_refresh(app, client_id, next, &device_id, &subject)?;
    Ok(success(
        app,
        &tokens.access_token,
        tokens.expires_in,
        Some(sealed),
    ))
}
