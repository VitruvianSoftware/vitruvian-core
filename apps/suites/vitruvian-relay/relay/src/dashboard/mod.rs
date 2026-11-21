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

//! The dashboard: a few server-rendered pages where a signed-in person sees
//! their computers and what their AI apps did on them, and renames or
//! removes a computer. No JavaScript.
//!
//! Sign-in is the identity service's authorization-code flow with PKCE
//! (`/auth/login`, `/auth/callback`). The access token it returns is checked
//! by a third [`vitruvian_mcp_auth::Verifier`] pinned to the dashboard's own
//! client id and the relay-user role. The client id lists are disjoint, so a
//! dashboard token is refused at `/mcp`, `/devices` and `/connect`, and an AI
//! app's or the connector's token is refused here. A sign-in becomes a
//! session ([`session`]), kept in memory.
//!
//! Every route that names a computer goes through [`App::owned_device`] (or
//! [`App::revoke`], which does): somebody else's computer gets the very same
//! answer as one that does not exist. Every `POST` must come from the
//! relay's own origin and carry the session's CSRF token.

mod pages;
pub mod session;
#[cfg(test)]
mod tests;

use std::collections::HashMap;
use std::io::Read;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use http::{header, HeaderValue, Method, Request, Response, StatusCode};
use hyper::body::Incoming;
use serde_json::{json, Value};
use vitruvian_mcp_auth::{audience_scope_for, AuthError};

use crate::devices::{clean_device_name, DeviceRecord, DEVICE_NAME_MAX};
use crate::http::{header_str, read_body, valid_device_id, App, Body};
use crate::store::{StoreError, UNAVAILABLE_MESSAGE};
use pages::{ActivityView, Ctx, DeviceView, Flash};
use session::{Pkce, SessionView, AUTH_COOKIE, SESSION_COOKIE};

pub use session::{Sessions, DASHBOARD_SESSION_HOURS};

/// How many of a person's latest calls the activity page shows.
pub const ACTIVITY_PAGE: u32 = 200;

/// The stylesheet, served at `/static/relay.css`.
const RELAY_CSS: &str = include_str!("relay.css");

/// What every dashboard response may load and send.
const CSP: &str = "default-src 'self'; frame-ancestors 'none'; form-action 'self'";

/// Largest form a page sends (a name and a token).
const MAX_FORM_BYTES: usize = 4 * 1024;

/// How long the identity service has to answer the code exchange.
const EXCHANGE_TIMEOUT: Duration = Duration::from_secs(10);
/// Most of the token answer read; a real one is under 5 KiB.
const MAX_TOKEN_ANSWER_BYTES: u64 = 64 * 1024;

/// What the dashboard keeps in memory, beside the verifier.
pub struct Dashboard {
    pub sessions: Sessions,
    /// Calls the identity service to exchange a sign-in code.
    agent: ureq::Agent,
}

impl Dashboard {
    pub fn new(user_agent: &str) -> Dashboard {
        Dashboard {
            sessions: Sessions::default(),
            agent: ureq::AgentBuilder::new()
                .timeout(EXCHANGE_TIMEOUT)
                .redirects(0)
                .tls_config(vitruvian_mcp_auth::tls_client_config())
                .user_agent(user_agent)
                .build(),
        }
    }
}

// ------------------------------------------------------------------- routes

enum Route<'a> {
    Home,
    Login,
    Callback,
    Logout,
    Stylesheet,
    Devices,
    Device(&'a str),
    Rename(&'a str),
    Remove(&'a str),
    Activity,
}

fn route<'a>(method: &Method, path: &'a str) -> Option<Route<'a>> {
    match (method, path) {
        (&Method::GET, "/") => Some(Route::Home),
        (&Method::GET, "/auth/login") => Some(Route::Login),
        (&Method::GET, "/auth/callback") => Some(Route::Callback),
        (&Method::POST, "/auth/logout") => Some(Route::Logout),
        (&Method::GET, "/static/relay.css") => Some(Route::Stylesheet),
        (&Method::GET, "/devices") => Some(Route::Devices),
        (&Method::GET, "/activity") => Some(Route::Activity),
        _ => {
            let rest = path.strip_prefix("/devices/")?;
            match (method, rest.split_once('/')) {
                (&Method::GET, None) => Some(Route::Device(rest)),
                (&Method::POST, Some((id, "rename"))) => Some(Route::Rename(id)),
                (&Method::POST, Some((id, "remove"))) => Some(Route::Remove(id)),
                _ => None,
            }
        }
    }
}

/// True for the requests this module answers. (`POST /devices` is the
/// connector's registration, not this module's.)
pub fn wants(method: &Method, path: &str) -> bool {
    route(method, path).is_some()
}

pub async fn handle(app: Arc<App>, req: Request<Incoming>) -> Response<Body> {
    let method = req.method().clone();
    let path = req.uri().path().to_string();
    let Some(route) = route(&method, &path) else {
        return crate::http::not_found();
    };
    match route {
        Route::Stylesheet => styled(StatusCode::OK, "text/css; charset=utf-8", RELAY_CSS.into()),
        Route::Home => home(&app, &req),
        Route::Login => login(&app, &req),
        Route::Callback => callback(&app, &req).await,
        Route::Logout => logout(&app, req).await,
        Route::Devices => devices(&app, &req).await,
        Route::Device(id) => device(&app, &req, id).await,
        Route::Rename(id) => rename(&app, req, id).await,
        Route::Remove(id) => remove(&app, req, id).await,
        Route::Activity => activity(&app, &req).await,
    }
}

// ---------------------------------------------------------------- responses

/// A response with every header the dashboard sends: never cached, locked
/// to its own origin by the CSP, no sniffing, and the referrer kept inside
/// the site (`same-origin`, not `no-referrer`: a browser sends
/// `Origin: null` on a form post under `no-referrer`, which the origin check
/// would then refuse).
fn styled(status: StatusCode, content_type: &str, body: String) -> Response<Body> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "no-store")
        .header(header::CONTENT_SECURITY_POLICY, CSP)
        .header(header::X_CONTENT_TYPE_OPTIONS, "nosniff")
        .header(header::REFERRER_POLICY, "same-origin")
        .body(Body::new(body))
        .expect("static response parts are valid")
}

fn html(status: StatusCode, body: String) -> Response<Body> {
    styled(status, "text/html; charset=utf-8", body)
}

/// Sends the browser on (as a GET) to `location`.
fn redirect(location: &str) -> Response<Body> {
    let mut resp = styled(
        StatusCode::SEE_OTHER,
        "text/plain; charset=utf-8",
        String::new(),
    );
    match HeaderValue::from_str(location) {
        Ok(v) => {
            resp.headers_mut().insert(header::LOCATION, v);
            resp
        }
        Err(_) => styled(
            StatusCode::INTERNAL_SERVER_ERROR,
            "text/plain; charset=utf-8",
            "bad redirect".into(),
        ),
    }
}

fn with_cookie(mut resp: Response<Body>, cookie: &str) -> Response<Body> {
    if let Ok(v) = HeaderValue::from_str(cookie) {
        resp.headers_mut().append(header::SET_COOKIE, v);
    }
    resp
}

fn secure_cookies(app: &App) -> bool {
    app.settings.public_url.starts_with("https://")
}

fn now(app: &App) -> SystemTime {
    UNIX_EPOCH + Duration::from_secs((app.timing.clock)())
}

fn ctx<'a>(app: &App, session: Option<&'a SessionView>) -> Ctx<'a> {
    Ctx {
        csrf: session.map(|s| s.csrf.as_str()),
        now: now(app),
    }
}

fn session_of(app: &App, req: &Request<Incoming>) -> Option<SessionView> {
    let cookies = req
        .headers()
        .get_all(header::COOKIE)
        .iter()
        .filter_map(|v| v.to_str().ok());
    let id = session::cookie_value(cookies, SESSION_COOKIE)?;
    app.dashboard.sessions.get(id, (app.timing.clock)())
}

/// A page that only says something, for a signed-in person or not.
fn say(
    app: &App,
    session: Option<&SessionView>,
    status: StatusCode,
    title: &str,
    text: &str,
    link: (&str, &str),
) -> Response<Body> {
    html(
        status,
        pages::message_page(ctx(app, session), title, text, link),
    )
}

/// The answer for a computer that is not the person's: the same bytes for
/// somebody else's, one that was removed, one that never existed and an id
/// that is not an id.
fn computer_not_found(app: &App, session: &SessionView) -> Response<Body> {
    say(
        app,
        Some(session),
        StatusCode::NOT_FOUND,
        "We could not find that computer",
        "It may have been removed, or the link may be wrong. Your computers are listed on the next page.",
        ("/devices", "Your computers"),
    )
}

fn unavailable(app: &App, session: Option<&SessionView>) -> Response<Body> {
    say(
        app,
        session,
        StatusCode::SERVICE_UNAVAILABLE,
        "Vitruvian Relay is having trouble",
        UNAVAILABLE_MESSAGE,
        ("/devices", "Try again"),
    )
}

fn forbidden(app: &App, session: &SessionView) -> Response<Body> {
    say(
        app,
        Some(session),
        StatusCode::FORBIDDEN,
        "That did not work",
        "Vitruvian Relay could not tell that this request came from its own page. Go back, reload the page and try again.",
        ("/devices", "Your computers"),
    )
}

fn store_down(app: &App, session: &SessionView, e: &StoreError) -> Response<Body> {
    app.log("dashboard_store_failed", json!({"error": e.to_string()}));
    unavailable(app, Some(session))
}

// -------------------------------------------------------------- small parsers

/// Percent-encodes for a query string or a form body.
pub fn form_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[i + 1..i + 3])
                    .ok()
                    .and_then(|h| u8::from_str_radix(h, 16).ok());
                match hex {
                    Some(b) => {
                        out.push(b);
                        i += 2;
                    }
                    None => out.push(b'%'),
                }
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `a=1&b=2`, the shape of a query string and of a form body. The first
/// value of a repeated key wins.
fn parse_pairs(raw: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for pair in raw.split('&').filter(|p| !p.is_empty()) {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        out.entry(percent_decode(k))
            .or_insert_with(|| percent_decode(v));
    }
    out
}

fn query_param(query: Option<&str>, key: &str) -> Option<String> {
    parse_pairs(query.unwrap_or("")).remove(key)
}

// --------------------------------------------------------------------- views

fn device_view(app: &App, d: &DeviceRecord) -> DeviceView {
    DeviceView {
        id: d.device_id.clone(),
        name: d.name.clone(),
        online: app.registry.tools(&d.device_id).is_some(),
        last_seen: d.last_seen,
        mcp_url: app.settings.device_mcp_url(&d.device_id),
    }
}

/// The client id to type into Claude: the one the relay knows Claude by, or
/// the app's name when none was labelled.
fn claude_client_id(app: &App) -> String {
    app.settings
        .mcp_client_id_of("Claude")
        .unwrap_or("relay-claude")
        .to_string()
}

/// The computer `id` if the signed-in person has it, else the page to send.
async fn owned(
    app: &App,
    session: &SessionView,
    id: &str,
) -> Result<DeviceRecord, Box<Response<Body>>> {
    if !valid_device_id(id) {
        return Err(Box::new(computer_not_found(app, session)));
    }
    match app.owned_device(&session.subject, id).await {
        Ok(Some(d)) => Ok(d),
        Ok(None) => Err(Box::new(computer_not_found(app, session))),
        Err(e) => Err(Box::new(store_down(app, session, &e))),
    }
}

// ------------------------------------------------------------------ the pages

fn home(app: &App, req: &Request<Incoming>) -> Response<Body> {
    if session_of(app, req).is_some() {
        return redirect("/devices");
    }
    let signed_out = query_param(req.uri().query(), "signed_out").is_some();
    html(
        StatusCode::OK,
        pages::sign_in_page(ctx(app, None), signed_out, &app.settings.end_session_url()),
    )
}

async fn devices(app: &App, req: &Request<Incoming>) -> Response<Body> {
    let Some(session) = session_of(app, req) else {
        return redirect("/");
    };
    let records = match app.store.devices_of(&session.subject).await {
        Ok(r) => r,
        Err(e) => return store_down(app, &session, &e),
    };
    let views: Vec<DeviceView> = records.iter().map(|d| device_view(app, d)).collect();
    let flash = Flash::from_query(req.uri().query());
    html(
        StatusCode::OK,
        pages::devices_page(ctx(app, Some(&session)), &views, flash),
    )
}

async fn device(app: &App, req: &Request<Incoming>, id: &str) -> Response<Body> {
    let Some(session) = session_of(app, req) else {
        return redirect("/");
    };
    let rec = match owned(app, &session, id).await {
        Ok(d) => d,
        Err(resp) => return *resp,
    };
    let flash = Flash::from_query(req.uri().query());
    html(
        StatusCode::OK,
        pages::device_page(
            ctx(app, Some(&session)),
            &device_view(app, &rec),
            &claude_client_id(app),
            flash,
            None,
        ),
    )
}

async fn activity(app: &App, req: &Request<Incoming>) -> Response<Body> {
    let Some(session) = session_of(app, req) else {
        return redirect("/");
    };
    let wanted = query_param(req.uri().query(), "device").filter(|d| !d.is_empty());
    let filter = match &wanted {
        Some(id) => match owned(app, &session, id).await {
            Ok(d) => Some(d),
            Err(resp) => return *resp,
        },
        None => None,
    };
    let records = match app.store.devices_of(&session.subject).await {
        Ok(r) => r,
        Err(e) => return store_down(app, &session, &e),
    };
    let rows = match app
        .store
        .activity_of(
            &session.subject,
            filter.as_ref().map(|d| d.device_id.as_str()),
            ACTIVITY_PAGE,
        )
        .await
    {
        Ok(r) => r,
        Err(e) => return store_down(app, &session, &e),
    };
    let names: HashMap<&str, &str> = records
        .iter()
        .map(|d| (d.device_id.as_str(), d.name.as_str()))
        .collect();
    let rows: Vec<ActivityView> = rows
        .into_iter()
        .map(|r| ActivityView {
            at: r.at,
            computer: names
                .get(r.device_id.as_str())
                .map_or("A computer you removed", |n| n)
                .to_string(),
            app: app
                .settings
                .mcp_client_label(&r.client_id)
                .unwrap_or("An AI app")
                .to_string(),
            tool: r.tool,
            outcome: r.outcome,
            duration_ms: r.duration_ms,
        })
        .collect();
    let views: Vec<DeviceView> = records.iter().map(|d| device_view(app, d)).collect();
    let filter_view = filter.as_ref().map(|d| device_view(app, d));
    html(
        StatusCode::OK,
        pages::activity_page(
            ctx(app, Some(&session)),
            filter_view.as_ref(),
            &views,
            &rows,
        ),
    )
}

// ----------------------------------------------------------------- forms (POST)

/// What a form post must be before anything in it is looked at: from the
/// relay's own origin, and carrying the session's CSRF token. `403` otherwise.
async fn checked_form(
    app: &App,
    req: Request<Incoming>,
    session: &SessionView,
) -> Result<HashMap<String, String>, Box<Response<Body>>> {
    if header_str(&req, header::ORIGIN) != Some(app.settings.public_url.as_str()) {
        app.log("dashboard_post_refused", json!({"why": "origin"}));
        return Err(Box::new(forbidden(app, session)));
    }
    let bytes = read_body(req.into_body(), MAX_FORM_BYTES, app.timing.body_timeout).await?;
    let form = parse_pairs(&String::from_utf8_lossy(&bytes));
    match form.get("csrf") {
        Some(token) if session::same_secret(token, &session.csrf) => Ok(form),
        _ => {
            app.log("dashboard_post_refused", json!({"why": "csrf"}));
            Err(Box::new(forbidden(app, session)))
        }
    }
}

async fn logout(app: &App, req: Request<Incoming>) -> Response<Body> {
    let Some(session) = session_of(app, &req) else {
        return redirect("/");
    };
    let id = session::cookie_value(
        req.headers()
            .get_all(header::COOKIE)
            .iter()
            .filter_map(|v| v.to_str().ok()),
        SESSION_COOKIE,
    )
    .map(String::from);
    if let Err(resp) = checked_form(app, req, &session).await {
        return *resp;
    }
    if let Some(id) = id {
        app.dashboard.sessions.end(&id);
    }
    with_cookie(
        redirect("/?signed_out=1"),
        &session::clear_session_cookie(secure_cookies(app)),
    )
}

async fn rename(app: &App, req: Request<Incoming>, id: &str) -> Response<Body> {
    let Some(session) = session_of(app, &req) else {
        return redirect("/");
    };
    let form = match checked_form(app, req, &session).await {
        Ok(f) => f,
        Err(resp) => return *resp,
    };
    let rec = match owned(app, &session, id).await {
        Ok(d) => d,
        Err(resp) => return *resp,
    };
    let Some(name) = clean_device_name(form.get("name").map_or("", String::as_str)) else {
        // A mistake the person can fix: say so, on the same page.
        let msg = format!(
            "Give this computer a name of 1 to {DEVICE_NAME_MAX} characters, then try again."
        );
        return html(
            StatusCode::BAD_REQUEST,
            pages::device_page(
                ctx(app, Some(&session)),
                &device_view(app, &rec),
                &claude_client_id(app),
                None,
                Some(&msg),
            ),
        );
    };
    match app
        .store
        .rename(&rec.device_id, &session.subject, &name)
        .await
    {
        Ok(true) => {
            app.log("device_renamed", json!({"device_id": rec.device_id}));
            redirect(&format!("/devices/{}?done=renamed", rec.device_id))
        }
        // Removed a moment ago.
        Ok(false) => computer_not_found(app, &session),
        Err(e) => store_down(app, &session, &e),
    }
}

async fn remove(app: &App, req: Request<Incoming>, id: &str) -> Response<Body> {
    let Some(session) = session_of(app, &req) else {
        return redirect("/");
    };
    if let Err(resp) = checked_form(app, req, &session).await {
        return *resp;
    }
    if !valid_device_id(id) {
        return computer_not_found(app, &session);
    }
    match app.revoke(&session.subject, id).await {
        Ok(true) => redirect("/devices?done=removed"),
        Ok(false) => computer_not_found(app, &session),
        Err(e) => store_down(app, &session, &e),
    }
}

// ---------------------------------------------------------------- signing in

fn authorize_url(app: &App, pkce: &Pkce) -> String {
    let s = &app.settings;
    // The project's audience scope puts the project in the token's audience,
    // which the token check requires; the role comes with it.
    let scope = format!("openid {}", audience_scope_for(&s.project_id));
    format!(
        "{}?response_type=code&client_id={}&redirect_uri={}&scope={}&state={}\
         &code_challenge={}&code_challenge_method=S256",
        s.authorize_url(),
        form_encode(&s.dashboard_client_id),
        form_encode(&s.dashboard_callback_url()),
        form_encode(&scope),
        form_encode(&pkce.state),
        form_encode(&pkce.challenge()),
    )
}

fn login(app: &App, req: &Request<Incoming>) -> Response<Body> {
    if session_of(app, req).is_some() {
        return redirect("/devices");
    }
    let pkce = Pkce::new();
    with_cookie(
        redirect(&authorize_url(app, &pkce)),
        &session::auth_cookie(&pkce, secure_cookies(app)),
    )
}

/// Trades the sign-in code for the access token. Blocking.
fn exchange_code(agent: &ureq::Agent, url: &str, form: &str) -> Result<String, String> {
    let response = agent
        .post(url)
        .set("Content-Type", "application/x-www-form-urlencoded")
        .set("Accept", "application/json")
        .send_string(form)
        .map_err(|e| match e {
            ureq::Error::Status(code, _) => format!("the token endpoint answered {code}"),
            ureq::Error::Transport(_) => "the token endpoint did not answer".to_string(),
        })?;
    let mut body = String::new();
    response
        .into_reader()
        .take(MAX_TOKEN_ANSWER_BYTES)
        .read_to_string(&mut body)
        .map_err(|_| "the token answer could not be read".to_string())?;
    serde_json::from_str::<Value>(&body)
        .ok()
        .and_then(|v| v.get("access_token")?.as_str().map(String::from))
        .filter(|t| !t.is_empty())
        .ok_or_else(|| "the token answer had no access token".to_string())
}

async fn callback(app: &Arc<App>, req: &Request<Incoming>) -> Response<Body> {
    let secure = secure_cookies(app);
    let start_again = ("/auth/login", "Sign in again");
    let refused = |status: StatusCode, title: &str, text: &str| {
        with_cookie(
            say(app, None, status, title, text, start_again),
            &session::clear_auth_cookie(secure),
        )
    };
    let query = req.uri().query();
    let pkce = session::cookie_value(
        req.headers()
            .get_all(header::COOKIE)
            .iter()
            .filter_map(|v| v.to_str().ok()),
        AUTH_COOKIE,
    )
    .and_then(Pkce::from_cookie);
    // The state sent out comes back unchanged, and only to the browser that
    // asked: a callback anyone else built has no matching cookie.
    let state_ok = match (&pkce, query_param(query, "state")) {
        (Some(p), Some(s)) => session::same_secret(&p.state, &s),
        _ => false,
    };
    let (true, Some(pkce)) = (state_ok, pkce) else {
        app.log("dashboard_signin_refused", json!({"why": "state"}));
        return refused(
            StatusCode::BAD_REQUEST,
            "That sign-in did not start here",
            "The sign-in link expired or was not started on this page. Start again.",
        );
    };
    let Some(code) = query_param(query, "code").filter(|c| !c.is_empty()) else {
        // The person said no, or the identity service could not go on.
        app.log("dashboard_signin_refused", json!({"why": "no_code"}));
        return refused(
            StatusCode::BAD_REQUEST,
            "Sign-in did not finish",
            "Nothing was changed. Sign in again when you are ready.",
        );
    };

    let form = [
        ("grant_type", "authorization_code"),
        ("code", code.as_str()),
        ("redirect_uri", &app.settings.dashboard_callback_url()),
        ("client_id", &app.settings.dashboard_client_id),
        ("code_verifier", &pkce.verifier),
    ]
    .iter()
    .map(|(k, v)| format!("{k}={}", form_encode(v)))
    .collect::<Vec<_>>()
    .join("&");
    let (agent, url) = (app.dashboard.agent.clone(), app.settings.token_url());
    let token = match tokio::task::spawn_blocking(move || exchange_code(&agent, &url, &form)).await
    {
        Ok(Ok(token)) => token,
        Ok(Err(why)) => {
            app.log("dashboard_signin_failed", json!({"why": why}));
            return refused(
                StatusCode::BAD_GATEWAY,
                "Sign-in could not finish",
                "The sign-in service did not give Vitruvian Relay what it needed. Try again in a minute.",
            );
        }
        Err(_) => {
            return refused(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Sign-in could not finish",
                "Something went wrong on our side. Try again in a minute.",
            )
        }
    };

    let verifier = app.dashboard_verifier.clone();
    let caller = match tokio::task::spawn_blocking(move || verifier.verify(&token)).await {
        Ok(Ok(caller)) => caller,
        Ok(Err(e)) => {
            // The code only: the checker's message can name the subject.
            app.log(
                "auth_refused",
                json!({"route": "auth_callback", "code": e.log_code()}),
            );
            return match e {
                AuthError::RoleMissing { .. } => refused(
                    StatusCode::FORBIDDEN,
                    "You do not have access yet",
                    "Your account signed in, but it has not been invited to Vitruvian Relay. Ask the person who runs it to invite you, then sign in again.",
                ),
                AuthError::IdpUnavailable { .. } => refused(
                    StatusCode::SERVICE_UNAVAILABLE,
                    "Sign-in is not answering",
                    "The sign-in service is not answering right now. Try again in a minute.",
                ),
                _ => refused(
                    StatusCode::FORBIDDEN,
                    "We could not confirm your sign-in",
                    "Vitruvian Relay could not accept that sign-in. Start again, and use the account you were invited with.",
                ),
            };
        }
        Err(_) => {
            return refused(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Sign-in could not finish",
                "Something went wrong on our side. Try again in a minute.",
            )
        }
    };

    let id = app
        .dashboard
        .sessions
        .start(&caller.subject, (app.timing.clock)());
    app.log("dashboard_signin", json!({}));
    with_cookie(
        with_cookie(redirect("/devices"), &session::session_cookie(&id, secure)),
        &session::clear_auth_cookie(secure),
    )
}
