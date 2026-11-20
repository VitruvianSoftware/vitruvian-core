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

//! The relay's HTTP side, on hyper 1 and tokio-tungstenite.
//!
//! Routes:
//!   GET    /healthz                                          liveness (not routed publicly)
//!   GET    /.well-known/oauth-protected-resource             RFC 9728 metadata for the relay
//!   GET    /.well-known/oauth-protected-resource/mcp/d/{id}  metadata for one device's URL
//!   POST   /mcp/d/{id}                                       MCP over Streamable HTTP (JSON answers)
//!                                                            (2026-07-28 requests stand alone; older ones use initialize + Mcp-Session-Id)
//!   GET    /mcp/d/{id}, DELETE /mcp/d/{id}                   405: no SSE stream or session delete in P1
//!   POST   /devices                                          register this person's device (connector token)
//!   GET    /connect                                          the connector's WebSocket (connector token)
//!
//! What it guards: an AI app's token only works on `/mcp`, the connector's
//! only on `/devices` and `/connect` (one verifier per side, each pinned to
//! its client ids, plus the subject allowlist). A device answers only its
//! owner: anyone else gets the same 404 as for a device that does not exist.
//! Nothing logged carries call arguments, output or a token.

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use http::{header, HeaderValue, Method, Request, Response, StatusCode};
use http_body_util::{BodyExt, Full, LengthLimitError, Limited};
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::{TokioIo, TokioTimer};
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::handshake::derive_accept_key;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;
use tokio_tungstenite::tungstenite::protocol::{CloseFrame, Message, Role, WebSocketConfig};
use tokio_tungstenite::WebSocketStream;
use vitruvian_mcp_auth::{
    extract_bearer, protected_resource_metadata, www_authenticate, AuthError, Caller, Verifier,
};
use vitruvian_relay_protocol::{
    decode_to_relay, encode, hello_message, Hello, ToConnector, ToRelay, CALL_BUDGET_SECS,
    MAX_FRAME_BYTES, PROTOCOL,
};

use crate::config::Settings;
use crate::devices::{DeviceRecord, DeviceStore};
use crate::mcp::{era, needs_session, Era, Mcp};
use crate::registry::{ConnectionId, Registry, ACK_TIMEOUT, RECONNECT_GRACE};
use crate::{hex, log_event, random_id, uuid_v4, LogSink};

pub type Body = Full<Bytes>;

/// Largest MCP request body. A call's arguments travel inside one frame to the
/// device, so the body stays under the frame cap with room for the frame's
/// own fields.
pub const MAX_MCP_BODY_BYTES: usize = MAX_FRAME_BYTES - 16 * 1024;
pub(crate) const MAX_DEVICES_BODY_BYTES: usize = 4 * 1024;
/// Sessions kept in memory; past this, the least recently used one ends (its
/// client gets a 404 and starts a new one).
const MAX_SESSIONS: usize = 1024;
/// Sessions one person may hold; past this, their own least recently used
/// one ends, so nobody can push out someone else's.
pub(crate) const MAX_SESSIONS_PER_SUBJECT: usize = 64;
const SESSION_HEADER: &str = "mcp-session-id";
/// Names the MCP revision on each request; must match `params._meta`'s.
const PROTOCOL_HEADER: &str = "mcp-protocol-version";
/// Frames queued for one connection before a caller waits for room.
const CONNECTION_QUEUE: usize = 64;

/// Every timer and clock the server uses, so tests can shorten them.
#[derive(Debug, Clone)]
pub struct Timing {
    /// The connector's `hello` must arrive within this.
    pub hello_timeout: Duration,
    /// Ping interval while the device has nothing in flight.
    pub idle_ping: Duration,
    /// Ping interval while a call is in flight, so a silent drop fails the
    /// call in seconds (3 missed ≈ 6 s), not a minute.
    pub in_call_ping: Duration,
    pub max_missed_pings: u32,
    /// How long a tool call may take (`deadline_ms` to the device).
    pub call_budget: Duration,
    /// How long the relay waits for the connector's `Ack` after writing a `Call`.
    pub ack_timeout: Duration,
    /// How long a call whose connector's link dropped waits for it to
    /// reconnect with the result, before failing `Disconnected`.
    pub reconnect_grace: Duration,
    /// How far a `hello` timestamp may be from the relay's clock.
    pub max_clock_skew_secs: u64,
    /// How long a call frame is allowed to take to reach the device after
    /// the relay starts writing it, before its size is counted (see
    /// `call_margin`). It is the longest silence the relay accepts on a link
    /// with a call in flight (3 missed 2 s pings): a link slower than that
    /// is dropped anyway.
    pub transit_margin: Duration,
    /// Longest one frame may take to go out. Longer than the ping window, so a
    /// call frame near the 4 MiB cap on a slow uplink is not mistaken for a
    /// dead link; a silent drop is still caught by the pings, which are small.
    pub send_timeout: Duration,
    /// The first request's headers must arrive within this of the
    /// connection opening (a client that connects and trickles is cut off).
    pub first_header_timeout: Duration,
    /// Every later request's headers must arrive within this. hyper's timer
    /// also runs while a kept-alive connection sits idle between requests,
    /// so this is in effect the idle timeout: long enough that a proxy's
    /// pooled connection is not closed under it.
    pub header_read_timeout: Duration,
    /// A request's body must arrive within this (408 otherwise).
    pub body_timeout: Duration,
    /// Longest a `/connect` socket may stay open, whatever its token's `exp`.
    pub max_connection_lifetime: Duration,
    /// Seconds since the epoch.
    pub clock: fn() -> u64,
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl Default for Timing {
    fn default() -> Self {
        use vitruvian_relay_protocol::{IN_CALL_PING_SECS, MAX_MISSED_PINGS, PING_SECS};
        Timing {
            hello_timeout: Duration::from_secs(10),
            idle_ping: Duration::from_secs(PING_SECS),
            in_call_ping: Duration::from_secs(IN_CALL_PING_SECS),
            max_missed_pings: MAX_MISSED_PINGS,
            call_budget: Duration::from_secs(CALL_BUDGET_SECS),
            ack_timeout: ACK_TIMEOUT,
            reconnect_grace: RECONNECT_GRACE,
            max_clock_skew_secs: 60,
            transit_margin: Duration::from_secs(IN_CALL_PING_SECS) * MAX_MISSED_PINGS,
            send_timeout: Duration::from_secs(30),
            first_header_timeout: Duration::from_secs(10),
            header_read_timeout: Duration::from_secs(75),
            body_timeout: Duration::from_secs(30),
            max_connection_lifetime: Duration::from_secs(12 * 60 * 60),
            clock: unix_now,
        }
    }
}

/// An MCP session: which device and person it was opened for.
struct Session {
    device_id: String,
    subject: String,
    client_id: String,
    last_used: Instant,
}

pub struct App {
    settings: Settings,
    mcp_verifier: Arc<Verifier>,
    connector_verifier: Arc<Verifier>,
    store: Arc<dyn DeviceStore>,
    registry: Registry,
    mcp: Mcp,
    sessions: Mutex<HashMap<String, Session>>,
    /// One registration at a time, so two at once for the same person cannot
    /// both create a device.
    registering: tokio::sync::Mutex<()>,
    timing: Timing,
    log: LogSink,
    /// Tests: pause a connection between checking its hello and registering
    /// it (reached, release).
    #[cfg(test)]
    pub(crate) after_hello: Mutex<Option<(Arc<tokio::sync::Notify>, Arc<tokio::sync::Notify>)>>,
    /// Tests: pause a session with a frame taken off its queue and not yet
    /// sent, as a peer that has stopped reading does (reached, release).
    #[cfg(test)]
    pub(crate) hold_sends: Mutex<Option<(Arc<tokio::sync::Notify>, Arc<tokio::sync::Notify>)>>,
}

impl App {
    pub fn new(
        settings: Settings,
        mcp: Verifier,
        connector: Verifier,
        store: Arc<dyn DeviceStore>,
        timing: Timing,
        log: LogSink,
    ) -> Arc<App> {
        let registry = Registry::with_timeouts(timing.ack_timeout, timing.reconnect_grace);
        Arc::new(App {
            mcp: Mcp::new(registry.clone(), timing.call_budget, log.clone()),
            settings,
            mcp_verifier: Arc::new(mcp),
            connector_verifier: Arc::new(connector),
            store,
            registry,
            sessions: Mutex::new(HashMap::new()),
            registering: tokio::sync::Mutex::new(()),
            timing,
            log,
            #[cfg(test)]
            after_hello: Mutex::new(None),
            #[cfg(test)]
            hold_sends: Mutex::new(None),
        })
    }

    fn log(&self, event: &str, fields: Value) {
        log_event(&self.log, event, fields);
    }

    fn new_session(&self, device_id: &str, caller: &Caller) -> String {
        let id = random_id();
        let mut sessions = self.sessions.lock().unwrap();
        let oldest = |sessions: &HashMap<String, Session>, only: Option<&str>| {
            sessions
                .iter()
                .filter(|(_, s)| only.is_none_or(|sub| s.subject == sub))
                .min_by_key(|(_, s)| s.last_used)
                .map(|(k, _)| k.clone())
        };
        // A person's own oldest session makes room for their new one...
        let theirs = sessions
            .values()
            .filter(|s| s.subject == caller.subject)
            .count();
        if theirs >= MAX_SESSIONS_PER_SUBJECT {
            if let Some(k) = oldest(&sessions, Some(&caller.subject)) {
                sessions.remove(&k);
            }
        }
        // ...and the overall cap is a backstop, only reachable with many people.
        if sessions.len() >= MAX_SESSIONS {
            if let Some(k) = oldest(&sessions, None) {
                sessions.remove(&k);
            }
        }
        sessions.insert(
            id.clone(),
            Session {
                device_id: device_id.to_string(),
                subject: caller.subject.clone(),
                client_id: caller.client_id.clone(),
                last_used: Instant::now(),
            },
        );
        id
    }

    /// True if `id` is a live session for this device, person and client.
    fn touch_session(&self, id: &str, device_id: &str, caller: &Caller) -> bool {
        let mut sessions = self.sessions.lock().unwrap();
        match sessions.get_mut(id) {
            Some(s)
                if s.device_id == device_id
                    && s.subject == caller.subject
                    && s.client_id == caller.client_id =>
            {
                s.last_used = Instant::now();
                true
            }
            _ => false,
        }
    }
}

// ------------------------------------------------------------------ helpers

fn respond(status: StatusCode, content_type: &str, body: impl Into<Bytes>) -> Response<Body> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Full::new(body.into()))
        .expect("static response parts are valid")
}

fn json_response(status: StatusCode, v: &Value) -> Response<Body> {
    respond(status, "application/json", v.to_string())
}

fn text(status: StatusCode, msg: &'static str) -> Response<Body> {
    respond(status, "text/plain", msg)
}

fn not_found() -> Response<Body> {
    text(StatusCode::NOT_FOUND, "not found")
}

/// A device id in a path: what `uuid_v4` makes, or anything shaped like it.
/// Checked before it goes into a header or a log line.
fn valid_device_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

fn header_str(req: &Request<Incoming>, name: header::HeaderName) -> Option<&str> {
    req.headers().get(name).and_then(|v| v.to_str().ok())
}

/// True when an `Accept` header allows a JSON answer. Streamable HTTP clients
/// send `application/json, text/event-stream`; this server always answers JSON.
fn accepts_json(accept: Option<&str>) -> bool {
    match accept {
        None => true,
        Some(a) => a
            .split(',')
            .map(|p| p.split(';').next().unwrap_or("").trim())
            .any(|t| t == "application/json" || t == "application/*" || t == "*/*"),
    }
}

/// Reads a request body: 413 only when it is over `limit`, 408 when it does
/// not arrive in time, 400 for anything else wrong with it.
async fn read_body(
    body: Incoming,
    limit: usize,
    timeout: Duration,
) -> Result<Bytes, Box<Response<Body>>> {
    let refuse = |status, msg| Err(Box::new(text(status, msg)));
    match tokio::time::timeout(timeout, Limited::new(body, limit).collect()).await {
        Err(_) => refuse(
            StatusCode::REQUEST_TIMEOUT,
            "the request body took too long",
        ),
        Ok(Ok(b)) => Ok(b.to_bytes()),
        Ok(Err(e)) if e.downcast_ref::<LengthLimitError>().is_some() => {
            refuse(StatusCode::PAYLOAD_TOO_LARGE, "body too large")
        }
        Ok(Err(_)) => refuse(StatusCode::BAD_REQUEST, "could not read the request body"),
    }
}

enum Refused {
    /// No usable `Authorization: Bearer` header.
    NoToken,
    Token(AuthError),
    /// The blocking check panicked or was cancelled.
    Internal,
}

/// Checks the bearer token. Blocking (it may fetch the key set), so it runs
/// off the async threads. Returns the caller and the token itself (for the
/// hello signature's token hash; never logged).
async fn authenticate(
    verifier: &Arc<Verifier>,
    header_value: Option<&str>,
) -> Result<(Caller, String), Refused> {
    let token = extract_bearer(header_value)
        .ok_or(Refused::NoToken)?
        .to_string();
    let v = verifier.clone();
    let t = token.clone();
    let caller = tokio::task::spawn_blocking(move || v.verify(&t))
        .await
        .map_err(|_| Refused::Internal)?
        .map_err(Refused::Token)?;
    Ok((caller, token))
}

/// The refusal for a failed token check: 401 (pointing at the metadata so the
/// client can sign in), 403 or 503, as the token checker classifies it.
fn refusal(app: &App, route: &str, metadata_url: &str, r: Refused) -> Response<Body> {
    let (status, challenge, code) = match &r {
        Refused::NoToken => (
            StatusCode::UNAUTHORIZED,
            www_authenticate(metadata_url, None),
            "invalid_request",
        ),
        Refused::Token(e) => (
            StatusCode::from_u16(e.status()).unwrap_or(StatusCode::UNAUTHORIZED),
            www_authenticate(metadata_url, Some(e)),
            e.code(),
        ),
        Refused::Internal => {
            return text(StatusCode::INTERNAL_SERVER_ERROR, "token check failed");
        }
    };
    // The code only: the checker's message can name the subject.
    app.log("auth_refused", json!({"route": route, "code": code}));
    let mut resp = json_response(status, &json!({"error": code}));
    if let Ok(v) = HeaderValue::from_str(&challenge) {
        resp.headers_mut().insert(header::WWW_AUTHENTICATE, v);
    }
    resp
}

// ------------------------------------------------------------------ routing

pub async fn handle(app: Arc<App>, req: Request<Incoming>) -> Response<Body> {
    const PRM: &str = "/.well-known/oauth-protected-resource";
    let path = req.uri().path().to_string();
    let method = req.method().clone();

    if let Some(device_id) = path.strip_prefix("/mcp/d/") {
        if !valid_device_id(device_id) {
            return not_found();
        }
        let device_id = device_id.to_string();
        return match method {
            Method::POST => mcp_post(app, req, device_id).await,
            Method::GET | Method::DELETE => {
                let mut r = text(StatusCode::METHOD_NOT_ALLOWED, "POST only");
                r.headers_mut()
                    .insert(header::ALLOW, HeaderValue::from_static("POST"));
                r
            }
            _ => text(StatusCode::METHOD_NOT_ALLOWED, "POST only"),
        };
    }
    if let Some(device_id) = path
        .strip_prefix(PRM)
        .and_then(|p| p.strip_prefix("/mcp/d/"))
    {
        // Served for any well-formed id: whether a device exists is not public.
        return match (method, valid_device_id(device_id)) {
            (Method::GET, true) => json_response(
                StatusCode::OK,
                &protected_resource_metadata(
                    &app.settings.device_mcp_url(device_id),
                    &app.settings.issuer,
                    &app.settings.project_id,
                ),
            ),
            _ => not_found(),
        };
    }
    match (method, path.as_str()) {
        (Method::GET, "/healthz") => text(StatusCode::OK, "ok"),
        (Method::GET, PRM) => json_response(
            StatusCode::OK,
            &protected_resource_metadata(
                &app.settings.public_url,
                &app.settings.issuer,
                &app.settings.project_id,
            ),
        ),
        (Method::POST, "/devices") => register_device(app, req).await,
        (Method::GET, "/connect") => upgrade(app, req).await,
        (_, "/devices") | (_, "/connect") => text(StatusCode::METHOD_NOT_ALLOWED, "wrong method"),
        _ => not_found(),
    }
}

// ---------------------------------------------------------------------- MCP

async fn mcp_post(app: Arc<App>, req: Request<Incoming>, device_id: String) -> Response<Body> {
    let metadata_url = app.settings.device_metadata_url(&device_id);
    let caller =
        match authenticate(&app.mcp_verifier, header_str(&req, header::AUTHORIZATION)).await {
            Ok((caller, _token)) => caller,
            Err(r) => return refusal(&app, "mcp", &metadata_url, r),
        };
    // Someone else's device answers exactly like a missing one.
    match app.store.get(&device_id) {
        Some(rec) if rec.owner_sub == caller.subject => {}
        _ => return not_found(),
    }
    if !accepts_json(header_str(&req, header::ACCEPT)) {
        return text(
            StatusCode::NOT_ACCEPTABLE,
            "this server answers application/json",
        );
    }
    let session = req
        .headers()
        .get(SESSION_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(String::from);
    let protocol_header = req
        .headers()
        .get(PROTOCOL_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(String::from);
    let bytes = match read_body(req.into_body(), MAX_MCP_BODY_BYTES, app.timing.body_timeout).await
    {
        Ok(b) => b,
        Err(resp) => return *resp,
    };
    let msg: Value = match serde_json::from_slice(&bytes) {
        Ok(v) => v,
        Err(_) => {
            return json_response(
                StatusCode::BAD_REQUEST,
                &json!({"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "Parse error"}}),
            )
        }
    };
    let method = msg.get("method").and_then(Value::as_str);
    let era = match era(&msg, protocol_header.as_deref()) {
        Ok(e) => e,
        Err(err) => return json_response(StatusCode::BAD_REQUEST, &err),
    };
    // A modern (2026-07-28) request stands alone: any session id an older
    // client left on it is ignored, and none is looked up or minted.
    let session = if era == Era::Modern {
        None
    } else if needs_session(method) {
        match session {
            None => return text(StatusCode::BAD_REQUEST, "Mcp-Session-Id header required"),
            // MCP's rule for an ended session: 404 tells the client to start
            // a new one.
            Some(s) if !app.touch_session(&s, &device_id, &caller) => {
                return text(StatusCode::NOT_FOUND, "session not found; initialize again")
            }
            Some(s) => Some(s),
        }
    } else {
        None
    };
    let is_initialize = era == Era::Legacy && method == Some("initialize");
    match app
        .mcp
        .handle(&msg, &device_id, &caller, session.as_deref())
        .await
    {
        None => respond(StatusCode::ACCEPTED, "text/plain", ""),
        Some(v) => {
            // The stateless revision answers an unknown method with 404; the
            // older ones keep 200 with the JSON-RPC error.
            let status = if era == Era::Modern && v["error"]["code"] == -32601 {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::OK
            };
            let mut resp = json_response(status, &v);
            if is_initialize && v.get("result").is_some() {
                let id = app.new_session(&device_id, &caller);
                resp.headers_mut().insert(
                    SESSION_HEADER,
                    HeaderValue::from_str(&id).expect("hex is a valid header"),
                );
            }
            resp
        }
    }
}

// ------------------------------------------------------- device registration

async fn register_device(app: Arc<App>, req: Request<Incoming>) -> Response<Body> {
    let metadata_url = app.settings.relay_metadata_url();
    let caller = match authenticate(
        &app.connector_verifier,
        header_str(&req, header::AUTHORIZATION),
    )
    .await
    {
        Ok((caller, _token)) => caller,
        Err(r) => return refusal(&app, "devices", &metadata_url, r),
    };
    let bytes = match read_body(
        req.into_body(),
        MAX_DEVICES_BODY_BYTES,
        app.timing.body_timeout,
    )
    .await
    {
        Ok(b) => b,
        Err(resp) => return *resp,
    };
    let key = serde_json::from_slice::<Value>(&bytes)
        .ok()
        .and_then(|v| v.get("public_key")?.as_str().map(String::from))
        .and_then(|k| base64::engine::general_purpose::STANDARD.decode(k).ok())
        .and_then(|k| <[u8; 32]>::try_from(k).ok());
    let Some(public_key_ed25519) = key else {
        return text(
            StatusCode::BAD_REQUEST,
            "body must be {\"public_key\": \"<base64 of a 32-byte Ed25519 key>\"}",
        );
    };

    let _one_at_a_time = app.registering.lock().await;
    // P1: one device per person. Registering again keeps the id, replaces
    // the key, and ends any session signed with the old one.
    let existing = app.store.find_by_owner(&caller.subject);
    let replacing = existing.is_some();
    let device_id = existing.map(|r| r.device_id).unwrap_or_else(uuid_v4);
    let rec = DeviceRecord {
        device_id: device_id.clone(),
        owner_sub: caller.subject.clone(),
        public_key_ed25519,
    };
    if let Err(e) = app.store.put(rec.clone()) {
        // `put` can fail after the new file is in place (the directory sync
        // failed): then the record is stored, just maybe not durable. Only a
        // record that is not there is a failure.
        if app.store.get(&device_id).as_ref() != Some(&rec) {
            app.log("device_store_failed", json!({"error": e.to_string()}));
            return text(
                StatusCode::INTERNAL_SERVER_ERROR,
                "could not store the device",
            );
        }
        app.log(
            "device_store_not_durable",
            json!({"device_id": device_id, "error": e.to_string()}),
        );
    }
    if replacing {
        app.registry.kick(&device_id);
    }
    app.log(
        "device_registered",
        json!({"device_id": device_id, "client_id": caller.client_id, "replaced_key": replacing}),
    );
    json_response(
        StatusCode::OK,
        &json!({"device_id": device_id, "mcp_url": app.settings.device_mcp_url(&device_id)}),
    )
}

// ------------------------------------------------------------------ /connect

fn ws_config() -> WebSocketConfig {
    WebSocketConfig {
        max_message_size: Some(MAX_FRAME_BYTES),
        max_frame_size: Some(MAX_FRAME_BYTES),
        ..Default::default()
    }
}

async fn upgrade(app: Arc<App>, mut req: Request<Incoming>) -> Response<Body> {
    let is_ws = header_str(&req, header::UPGRADE)
        .map(|v| v.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false);
    let accept = req
        .headers()
        .get(header::SEC_WEBSOCKET_KEY)
        .map(|k| derive_accept_key(k.as_bytes()));
    let (true, Some(accept)) = (is_ws, accept) else {
        return text(StatusCode::BAD_REQUEST, "WebSocket upgrade required");
    };
    // RFC 6455's only version.
    if header_str(&req, header::SEC_WEBSOCKET_VERSION).map(str::trim) != Some("13") {
        let mut r = text(StatusCode::BAD_REQUEST, "Sec-WebSocket-Version must be 13");
        r.headers_mut().insert(
            header::SEC_WEBSOCKET_VERSION,
            HeaderValue::from_static("13"),
        );
        return r;
    }
    let metadata_url = app.settings.relay_metadata_url();
    let (caller, token) = match authenticate(
        &app.connector_verifier,
        header_str(&req, header::AUTHORIZATION),
    )
    .await
    {
        Ok(ok) => ok,
        Err(r) => return refusal(&app, "connect", &metadata_url, r),
    };
    // The hello signature binds this token, so a signature cannot be replayed
    // with another one. Only the hash is kept.
    let token_hash = hex(ring::digest::digest(&ring::digest::SHA256, token.as_bytes()).as_ref());
    // The socket must not outlive its token, so a token without an expiry
    // cannot open one.
    let Some(exp) = token_exp(&token) else {
        let e = AuthError::InvalidToken {
            reason: "the token has no expiry (exp claim); /connect needs one".into(),
        };
        return refusal(&app, "connect", &metadata_url, Refused::Token(e));
    };
    drop(token);

    let on_upgrade = hyper::upgrade::on(&mut req);
    tokio::spawn(async move {
        let upgraded = match on_upgrade.await {
            Ok(u) => u,
            Err(e) => {
                app.log("ws_upgrade_failed", json!({"error": e.to_string()}));
                return;
            }
        };
        let seen = Arc::new(AtomicBool::new(false));
        let io = SeenIo {
            inner: TokioIo::new(upgraded),
            seen: seen.clone(),
        };
        let ws = WebSocketStream::from_raw_socket(io, Role::Server, Some(ws_config())).await;
        run_connection(app, ws, caller, token_hash, Some(exp), seen).await;
    });

    Response::builder()
        .status(StatusCode::SWITCHING_PROTOCOLS)
        .header(header::UPGRADE, "websocket")
        .header(header::CONNECTION, "Upgrade")
        .header(header::SEC_WEBSOCKET_ACCEPT, accept)
        .body(Full::new(Bytes::new()))
        .expect("static response parts are valid")
}

/// The first frame, if it is a text frame.
enum First {
    Text(String),
    Other,
    Closed,
}

async fn first_frame<S>(ws: &mut WebSocketStream<S>) -> First
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    loop {
        match ws.next().await {
            Some(Ok(Message::Text(t))) => return First::Text(t),
            // Control frames before hello are fine (tungstenite answers pings).
            Some(Ok(Message::Ping(_))) | Some(Ok(Message::Pong(_))) => {}
            Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return First::Closed,
            Some(Ok(_)) => return First::Other,
        }
    }
}

impl App {
    /// Checks a `hello` against the device record and the token it came with.
    /// The reason goes back to the connector in `reject`.
    fn check_hello(
        &self,
        hello: &Hello,
        caller: &Caller,
        token_hash: &str,
    ) -> Result<[u8; 32], String> {
        if hello.protocol != PROTOCOL {
            return Err(format!(
                "Update vrelay: this relay needs protocol {PROTOCOL}."
            ));
        }
        // Another person's device is "unknown", like one that does not exist.
        let rec = match self.store.get(&hello.device_id) {
            Some(r) if r.owner_sub == caller.subject => r,
            _ => return Err("unknown device; register it again".into()),
        };
        let now = (self.timing.clock)();
        if now.abs_diff(hello.ts) > self.timing.max_clock_skew_secs {
            return Err(format!(
                "hello timestamp is more than {} s from the relay's clock; check the computer's clock",
                self.timing.max_clock_skew_secs
            ));
        }
        let sig = base64::engine::general_purpose::STANDARD
            .decode(&hello.sig)
            .map_err(|_| "bad signature".to_string())?;
        let message = hello_message(&hello.device_id, hello.ts, token_hash);
        ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, rec.public_key_ed25519)
            .verify(message.as_bytes(), &sig)
            .map_err(|_| "bad signature".to_string())?;
        // The key that verified it: the session re-checks it after registering.
        Ok(rec.public_key_ed25519)
    }
}

async fn send_frame<S>(
    sink: &mut futures_util::stream::SplitSink<WebSocketStream<S>, Message>,
    frame: &ToConnector,
    timeout: Duration,
) -> Result<(), String>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    let text = encode(frame).map_err(|e| e.to_string())?;
    // A peer that stopped reading must not stall the session: the ping
    // checks run in the same loop.
    match tokio::time::timeout(timeout, sink.send(Message::Text(text))).await {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => Err(format!("send failed: {e}")),
        Err(_) => Err("send stalled".into()),
    }
}

/// The slowest link a call frame is sized for: the same floor as the
/// connector's `send_budget`.
const CALL_SEND_BYTES_PER_MS: usize = 64;

/// How long a call frame of `bytes` may take from the moment the relay
/// starts writing it until the device has it: `transit` plus the time to
/// push that many bytes down a slow link. The relay takes this off the
/// deadline it sends, and gives up on the link if the write alone takes
/// that long.
pub(crate) fn call_margin(transit: Duration, bytes: usize) -> Duration {
    transit + Duration::from_millis((bytes / CALL_SEND_BYTES_PER_MS) as u64)
}

/// Whether a ping is due, counting ticks of the in-call interval: every tick
/// while a call is in flight, every `idle_every` ticks otherwise.
fn ping_due(ticks_since_ping: u32, in_flight: bool, idle_every: u32) -> bool {
    ticks_since_ping >= if in_flight { 1 } else { idle_every }
}

/// Why a healthy socket is closed on a timer.
#[derive(Debug, Clone, Copy)]
enum Ending {
    TokenExpired,
    LifetimeCap,
}

impl Ending {
    fn reason(self) -> &'static str {
        match self {
            Ending::TokenExpired => "token expired; reconnect with a fresh token",
            Ending::LifetimeCap => "connection lifetime cap reached; reconnect",
        }
    }
}

/// The upgraded socket with a flag set whenever bytes arrive from the
/// device, so liveness counts a large frame still on its way in.
struct SeenIo<S> {
    inner: S,
    seen: Arc<AtomicBool>,
}

impl<S: tokio::io::AsyncRead + Unpin> tokio::io::AsyncRead for SeenIo<S> {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        let r = std::pin::Pin::new(&mut self.inner).poll_read(cx, buf);
        if buf.filled().len() > before {
            self.seen.store(true, Ordering::Relaxed);
        }
        r
    }
}

impl<S: tokio::io::AsyncWrite + Unpin> tokio::io::AsyncWrite for SeenIo<S> {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        std::pin::Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }

    fn poll_write_vectored(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        bufs: &[std::io::IoSlice<'_>],
    ) -> std::task::Poll<std::io::Result<usize>> {
        std::pin::Pin::new(&mut self.inner).poll_write_vectored(cx, bufs)
    }

    fn is_write_vectored(&self) -> bool {
        self.inner.is_write_vectored()
    }
}

/// What the ping timer says to do on a tick.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Beat {
    Nothing,
    Ping(u64),
    Dead(u32),
}

/// Whether the connector is still there, counted in ticks of the in-call
/// ping interval. Each ping must be answered before the next tick (one
/// in-call interval, 2 s in production); a ping still unanswered then is
/// missed. After `max_missed` in a row the link is dead, at the moment the
/// last one's reply window ends: about 6 s once a call is in flight (a call
/// is pinged the moment it goes out), and about a minute when idle.
pub(crate) struct Liveness {
    idle_every: u32,
    max_missed: u32,
    since_ping: u32,
    awaiting: bool,
    missed: u32,
    n: u64,
}

impl Liveness {
    pub(crate) fn new(idle_every: u32, max_missed: u32) -> Self {
        Liveness {
            idle_every,
            max_missed: max_missed.max(1),
            since_ping: 0,
            awaiting: false,
            missed: 0,
            n: 0,
        }
    }

    pub(crate) fn tick(&mut self, in_flight: bool) -> Beat {
        if self.awaiting {
            self.awaiting = false;
            self.missed += 1;
            if self.missed >= self.max_missed {
                return Beat::Dead(self.missed);
            }
        }
        self.since_ping += 1;
        if ping_due(self.since_ping, in_flight, self.idle_every) {
            return self.ping();
        }
        Beat::Nothing
    }

    /// A call just went to the device: ping now (unless a ping is already
    /// out), so the drop count starts with the call. The caller restarts the
    /// tick timer so this ping gets a full reply window.
    pub(crate) fn call_started(&mut self) -> Beat {
        if self.awaiting {
            Beat::Nothing
        } else {
            self.ping()
        }
    }

    /// Any frame from the device (result, tools_changed, ping, pong) is a
    /// sign of life. Passes the read through.
    fn note<T, E>(&mut self, msg: Option<Result<T, E>>) -> Option<Result<T, E>> {
        if let Some(Ok(_)) = &msg {
            self.heard();
        }
        msg
    }

    pub(crate) fn heard(&mut self) {
        self.missed = 0;
        self.awaiting = false;
    }

    fn ping(&mut self) -> Beat {
        self.since_ping = 0;
        self.awaiting = true;
        self.n += 1;
        Beat::Ping(self.n)
    }
}

/// The `exp` claim of a token the checker has already verified (so its
/// payload can be trusted). `None` if it has none.
pub(crate) fn token_exp(token: &str) -> Option<u64> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .ok()?;
    let exp = serde_json::from_slice::<Value>(&bytes)
        .ok()?
        .get("exp")?
        .as_f64()?;
    (exp.is_finite() && exp >= 0.0).then_some(exp as u64)
}

async fn run_connection<S>(
    app: Arc<App>,
    mut ws: WebSocketStream<S>,
    caller: Caller,
    token_hash: String,
    token_exp: Option<u64>,
    seen: Arc<AtomicBool>,
) where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    let t = app.timing.clone();
    let reject = |reason: String| ToConnector::Reject { reason };
    let hello = match tokio::time::timeout(t.hello_timeout, first_frame(&mut ws)).await {
        Ok(First::Closed) => return,
        Err(_) => Err(format!(
            "no hello within {} s",
            t.hello_timeout.as_secs_f32()
        )),
        Ok(First::Other) => Err("the first frame must be hello".to_string()),
        Ok(First::Text(text)) => match decode_to_relay(&text) {
            Ok(ToRelay::Hello(h)) => Ok(h),
            _ => Err("the first frame must be hello".to_string()),
        },
    }
    .and_then(|h| {
        app.check_hello(&h, &caller, &token_hash)
            .map(|key| (h, key))
    })
    .and_then(|hk| match token_exp {
        Some(exp) if exp <= (t.clock)() => {
            Err("the token has expired; sign in again and reconnect".to_string())
        }
        _ => Ok(hk),
    });
    let (hello, verified_key) = match hello {
        Ok(hk) => hk,
        Err(reason) => {
            app.log("connect_rejected", json!({"reason": reason}));
            if let Ok(f) = encode(&reject(reason)) {
                let _ = tokio::time::timeout(t.hello_timeout, ws.send(Message::Text(f))).await;
            }
            let _ = tokio::time::timeout(t.hello_timeout, ws.close(None)).await;
            return;
        }
    };
    #[cfg(test)]
    {
        let hook = app.after_hello.lock().unwrap().clone();
        if let Some((reached, release)) = hook {
            reached.notify_one();
            release.notified().await;
        }
    }

    let device_id = hello.device_id.clone();
    let send_timeout = t.send_timeout;
    let (mut sink, mut stream) = ws.split();
    let (tx, mut rx) = mpsc::channel(CONNECTION_QUEUE);
    // Check the key again before registering, atomically with it: a
    // connection checked with a key that has since been replaced must not
    // take the place of one made with the new key.
    let key_still_current = || {
        app.store
            .get(&device_id)
            .is_some_and(|r| r.owner_sub == caller.subject && r.public_key_ed25519 == verified_key)
    };
    // The closer is set when a cancel could not be queued: end at once,
    // sending nothing more, so the device treats it as a drop (and never runs
    // the call).
    let Some((conn, closer)) =
        app.registry
            .connect_if(&device_id, hello.tools, tx, key_still_current)
    else {
        app.log(
            "connect_rejected",
            json!({"device_id": device_id, "reason": "device registered again"}),
        );
        let _ = send_frame(
            &mut sink,
            &reject("this device was registered again; reconnect with its new key".into()),
            send_timeout,
        )
        .await;
        let _ = tokio::time::timeout(send_timeout, sink.close()).await;
        return;
    };
    let conn: ConnectionId = conn;
    // Welcomed only once registered: a connector told "welcome" is never
    // then rejected (it would write "connected" and send `tools_changed`
    // to a link about to close). A call queued meanwhile waits in `rx`
    // until the welcome is out.
    if send_frame(
        &mut sink,
        &ToConnector::Welcome {
            device_id: device_id.clone(),
        },
        send_timeout,
    )
    .await
    .is_err()
    {
        app.registry.disconnect(&device_id, conn);
        return;
    }
    let started = Instant::now();
    app.log(
        "connect",
        json!({"device_id": device_id, "connector_version": hello.connector_version.chars().take(32).collect::<String>()}),
    );

    let tick = t.in_call_ping.max(Duration::from_millis(1));
    let idle_every = (t.idle_ping.as_millis() / tick.as_millis()).max(1) as u32;
    let mut ticker = tokio::time::interval(tick);
    ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    ticker.tick().await; // the first tick is immediate
    let mut live = Liveness::new(idle_every, t.max_missed_pings);
    // The socket must not outlive its token: the connector reconnects with a
    // fresh one.
    // ...and no socket lives past the lifetime cap, however far off its exp.
    let until_exp = token_exp.map(|exp| Duration::from_secs(exp.saturating_sub((t.clock)())));
    let (limit, ending) = match until_exp {
        Some(d) if d < t.max_connection_lifetime => (d, Ending::TokenExpired),
        _ => (t.max_connection_lifetime, Ending::LifetimeCap),
    };
    let expires = tokio::time::sleep(limit);
    tokio::pin!(expires);
    let mut ended: Option<Ending> = None;

    let reason: String = loop {
        tokio::select! {
            _ = ticker.tick() => {
                // Any bytes from the device since the last tick are a sign of
                // life, even mid-way through a large frame on a slow link.
                if seen.swap(false, Ordering::Relaxed) {
                    live.heard();
                }
                match live.tick(app.registry.in_flight(&device_id)) {
                    Beat::Nothing => {}
                    Beat::Dead(missed) => break format!("{missed} pings unanswered"),
                    Beat::Ping(n) => {
                        if let Err(e) = send_frame(&mut sink, &ToConnector::Ping { n }, send_timeout).await {
                            break e;
                        }
                    }
                }
            }
            _ = closer.closed() => break "closed: a cancel could not be queued".into(),
            _ = &mut expires => {
                ended = Some(ending);
                break ending.reason().into();
            }
            frame = rx.recv() => {
                #[cfg(test)]
                {
                    let hook = app.hold_sends.lock().unwrap().clone();
                    if let Some((reached, release)) = hook {
                        reached.notify_one();
                        release.notified().await;
                    }
                }
                match frame {
                    // The registry dropped this connection: a newer one
                    // replaced it, or the device was registered again.
                    None => break "replaced".into(),
                    // Closed while this frame waited: it is never sent.
                    Some(_) if closer.is_closed() => break "closed: a cancel could not be queued".into(),
                    Some(mut f) => {
                        let mut timeout = send_timeout;
                        let is_call = matches!(f, ToConnector::Call(_));
                        // (A call is encoded twice, once here for its size.)
                        let bytes = match encode(&f) {
                            Ok(text) if is_call => text.len(),
                            Ok(_) => 0,
                            Err(e) => break e.to_string(),
                        };
                        if let ToConnector::Call(call) = &mut f {
                            // This frame may have waited in the queue behind
                            // slow sends. The decision to send it is made
                            // here, at the socket, not when it was queued.
                            let margin = call_margin(t.transit_margin, bytes);
                            if !app.registry.release(conn, call, margin) {
                                // The relay gave up on it (or is about to):
                                // the device must never see it.
                                continue;
                            }
                            // A write that outlasts the margin would make the
                            // device's deadline end after the relay's: drop
                            // the link instead (a cut frame is never run).
                            timeout = timeout.min(margin);
                        }
                        if let Err(e) = send_frame(&mut sink, &f, timeout).await {
                            break e;
                        }
                        if let ToConnector::Call(call) = &f {
                            app.registry.call_written(conn, &call.call_id);
                            if let Beat::Ping(n) = live.call_started() {
                                ticker.reset();
                                if let Err(e) = send_frame(&mut sink, &ToConnector::Ping { n }, send_timeout).await {
                                    break e;
                                }
                            }
                        }
                    }
                }
            },
            msg = stream.next() => match live.note(msg) {
                None => break "connector went away".into(),
                Some(Err(e)) => break format!("read error: {e}"),
                Some(Ok(Message::Text(text))) => match decode_to_relay(&text) {
                    Ok(ToRelay::Result(r)) => {
                        let call_id = r.call_id.clone();
                        if app.registry.complete(&device_id, conn, r) {
                            if let Err(e) = send_frame(
                                &mut sink,
                                &ToConnector::ResultAck { call_id },
                                send_timeout,
                            )
                            .await
                            {
                                break e;
                            }
                        }
                    }
                    Ok(ToRelay::Ack { call_id }) => {
                        if app.registry.ack(conn, &call_id) {
                            if let Err(e) =
                                send_frame(&mut sink, &ToConnector::Start { call_id }, send_timeout)
                                    .await
                            {
                                break e;
                            }
                        }
                    }
                    Ok(ToRelay::ToolsChanged { tools }) => app.registry.update_tools(&device_id, conn, tools),
                    Ok(ToRelay::Ping { n }) => {
                        if let Err(e) = send_frame(&mut sink, &ToConnector::Pong { n }, send_timeout).await {
                            break e;
                        }
                    }
                    Ok(ToRelay::Pong { .. }) => live.heard(),
                    Ok(ToRelay::Hello(_) | ToRelay::Pending { .. }) => {}
                    // Size only: a bad frame may still hold call output.
                    Err(_) => app.log("bad_frame", json!({"device_id": device_id, "bytes": text.len()})),
                },
                Some(Ok(Message::Pong(_))) => live.heard(),
                Some(Ok(Message::Close(_))) => break "connector closed".into(),
                Some(Ok(_)) => {}
            },
        }
    };
    app.registry.disconnect(&device_id, conn);
    if let Some(ending) = ended {
        // A reason the connector can log; it then reconnects (with a
        // refreshed token if that was the reason).
        let frame = CloseFrame {
            code: CloseCode::Policy,
            reason: ending.reason().into(),
        };
        let _ = tokio::time::timeout(send_timeout, sink.send(Message::Close(Some(frame)))).await;
    }
    let _ = tokio::time::timeout(send_timeout, sink.close()).await;
    app.log(
        "disconnect",
        json!({"device_id": device_id, "seconds": started.elapsed().as_secs(), "reason": reason}),
    );
}

// ------------------------------------------------------------------- server

/// A new connection whose first request head (up to the blank line) must
/// arrive within a time limit; after that it reads as the plain socket.
/// hyper's own header timer is per request and also covers idle time, so it
/// is set long for kept-alive connections; this keeps the short limit for
/// the first request, where a slow-header client would otherwise get the
/// long one.
struct FirstHead<S> {
    inner: S,
    /// `None` once the first head is in.
    limit: Option<std::pin::Pin<Box<tokio::time::Sleep>>>,
    /// How much of "\r\n\r\n" the bytes so far end with.
    matched: usize,
}

impl<S> FirstHead<S> {
    fn new(inner: S, limit: Duration) -> Self {
        FirstHead {
            inner,
            limit: Some(Box::pin(tokio::time::sleep(limit))),
            matched: 0,
        }
    }
}

impl<S: tokio::io::AsyncRead + Unpin> tokio::io::AsyncRead for FirstHead<S> {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        if let Some(limit) = self.limit.as_mut() {
            if std::future::Future::poll(limit.as_mut(), cx).is_ready() {
                return std::task::Poll::Ready(Err(std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    "the first request's headers took too long",
                )));
            }
        }
        let before = buf.filled().len();
        let r = std::pin::Pin::new(&mut self.inner).poll_read(cx, buf);
        if self.limit.is_some() {
            const END: &[u8] = b"\r\n\r\n";
            let mut matched = self.matched;
            for &b in &buf.filled()[before..] {
                matched = if b == END[matched] {
                    matched + 1
                } else if b == END[0] {
                    1
                } else {
                    0
                };
                if matched == END.len() {
                    break;
                }
            }
            if matched == END.len() {
                self.limit = None;
            } else {
                self.matched = matched;
            }
        }
        r
    }
}

impl<S: tokio::io::AsyncWrite + Unpin> tokio::io::AsyncWrite for FirstHead<S> {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        std::pin::Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

/// Accepts connections until the listener fails for good.
pub async fn serve(listener: TcpListener, app: Arc<App>) {
    loop {
        let (stream, _) = match listener.accept().await {
            Ok(s) => s,
            Err(e) => {
                app.log("accept_failed", json!({"error": e.to_string()}));
                tokio::time::sleep(Duration::from_millis(100)).await;
                continue;
            }
        };
        let app = app.clone();
        let header_timeout = app.timing.header_read_timeout;
        let first = FirstHead::new(stream, app.timing.first_header_timeout);
        tokio::spawn(async move {
            let svc = service_fn(move |req| {
                let app = app.clone();
                async move { Ok::<_, Infallible>(handle(app, req).await) }
            });
            let _ = http1::Builder::new()
                .timer(TokioTimer::new())
                .header_read_timeout(header_timeout)
                .serve_connection(TokioIo::new(first), svc)
                .with_upgrades()
                .await;
        });
    }
}

#[cfg(test)]
#[path = "http_tests.rs"]
mod tests;
