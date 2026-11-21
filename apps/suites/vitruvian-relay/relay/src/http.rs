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
//!   GET    /, /auth/*, /devices, /devices/{id}, /activity    the dashboard (a signed-in browser, [`crate::dashboard`])
//!
//! What it guards: an AI app's token only works on `/mcp`, the connector's
//! only on `/devices` and `/connect`, the dashboard's only on `/auth/*` (one
//! verifier per side, each pinned to its client ids, and each asking for the
//! Zitadel role that marks an invited person). A device answers only its owner, and
//! [`App::owned_device`] is the one place that is decided: anyone else gets
//! the same answer as for a device that does not exist. Nothing logged
//! carries call arguments, output or a token.

use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
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
    decode_to_relay, encode, hello_message, Hello, ToConnector, ToRelay, APPROVAL_REPLY_SECS,
    CALL_BUDGET_SECS, MAX_FRAME_BYTES, PARKED_RESULT_SECS, PROTOCOL, REJOIN_WINDOW_SECS,
};

use crate::config::Settings;
use crate::dashboard::{self, Dashboard};
use crate::devices::{
    clean_device_name, DeviceRecord, NewDevice, DEFAULT_DEVICE_NAME, DEVICE_NAME_MAX,
};
use crate::mcp::{era, needs_session, Answer, Era, Mcp};
use crate::parked::Delivery;
use crate::ratelimit::{RateLimit, CALLS_PER_MINUTE_PER_USER, RATE_BURST};
use crate::registry::{ConnectionId, Registry, ACK_TIMEOUT, RECONNECT_GRACE};
use crate::store::{Store, StoreError, UNAVAILABLE_MESSAGE};
use crate::{hex, log_event, random_id, uuid_v4, LogSink};

/// A response body: one buffer, and (for an MCP result) the delivery to
/// commit once it has been written out.
///
/// The result counts as handed to the AI app only when the bytes carrying it
/// have been written to the socket and flushed ([`WriteTracker`]), not when
/// the relay produced it: if the socket turns out to be dead, the body is
/// dropped or the flush fails, the delivery is never committed, and the
/// AI app's retry finds the stored result instead of running the command
/// again. (What a proxy or tunnel does with bytes it has accepted is out of
/// reach; this closes the window on the relay's side.)
pub struct Body {
    inner: Full<Bytes>,
    /// Waiting for the end of the body.
    delivery: Option<(Delivery, Option<Arc<WriteTracker>>)>,
}

impl Body {
    pub fn new(data: impl Into<Bytes>) -> Self {
        Body {
            inner: Full::new(data.into()),
            delivery: None,
        }
    }

    fn with_delivery(mut self, d: Delivery, tracker: Option<Arc<WriteTracker>>) -> Self {
        self.delivery = Some((d, tracker));
        self
    }

    /// The body has been read to its end: hand the delivery to the
    /// connection to commit at its next flush (or, with no connection to
    /// watch, now).
    fn read_to_end(&mut self) {
        match self.delivery.take() {
            Some((d, Some(tracker))) => tracker.push(d),
            Some((d, None)) => d.commit(),
            None => {}
        }
    }
}

impl hyper::body::Body for Body {
    type Data = Bytes;
    type Error = Infallible;

    fn poll_frame(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Option<Result<hyper::body::Frame<Bytes>, Infallible>>> {
        use std::task::Poll;
        let polled = std::pin::Pin::new(&mut self.inner).poll_frame(cx);
        match &polled {
            Poll::Ready(None) => self.read_to_end(),
            // hyper does not poll again after the end of a sized body.
            Poll::Ready(Some(_)) if hyper::body::Body::is_end_stream(&self.inner) => {
                self.read_to_end()
            }
            _ => {}
        }
        polled
    }

    fn is_end_stream(&self) -> bool {
        hyper::body::Body::is_end_stream(&self.inner)
    }

    fn size_hint(&self) -> hyper::body::SizeHint {
        hyper::body::Body::size_hint(&self.inner)
    }
}

/// What a connection has read out of response bodies and not yet flushed:
/// the deliveries to commit when the socket's next flush succeeds.
#[derive(Default)]
pub struct WriteTracker {
    unflushed: Mutex<Vec<Delivery>>,
}

impl WriteTracker {
    fn push(&self, d: Delivery) {
        self.unflushed.lock().unwrap().push(d);
    }

    /// The socket flushed: what was written before has gone out.
    fn flushed(&self) {
        let done = std::mem::take(&mut *self.unflushed.lock().unwrap());
        for d in done {
            d.commit();
        }
    }
}

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
    /// How long a request waits on an approval dialog before it answers
    /// "waiting" with a request id (and how long each `check_request`
    /// waits). Under the ~15 s after which Claude gives up on a call.
    pub approval_reply: Duration,
    /// How long an identical request can still join a call.
    pub rejoin_window: Duration,
    /// How long the result of a call nobody took is kept.
    pub parked_result: Duration,
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
    /// How long the relay remembers that a device's key was replaced, so a
    /// `/connect` that read the old key a moment earlier is turned away. Must
    /// be longer than a `/connect` takes from reading the key to registering
    /// (seconds); the rest is only memory.
    pub key_change_memory: Duration,
    /// How often a connected device's "last seen" is brought up to date
    /// (it is also set when the device connects and when it disconnects).
    pub seen_every: Duration,
    /// Calls one person may make in a minute, once their burst is used up.
    pub calls_per_minute: u32,
    /// Calls one person may make at once after being quiet.
    pub rate_burst: u32,
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
            approval_reply: Duration::from_secs(APPROVAL_REPLY_SECS),
            rejoin_window: Duration::from_secs(REJOIN_WINDOW_SECS),
            parked_result: Duration::from_secs(PARKED_RESULT_SECS),
            max_clock_skew_secs: 60,
            transit_margin: Duration::from_secs(IN_CALL_PING_SECS) * MAX_MISSED_PINGS,
            send_timeout: Duration::from_secs(30),
            first_header_timeout: Duration::from_secs(10),
            header_read_timeout: Duration::from_secs(75),
            body_timeout: Duration::from_secs(30),
            max_connection_lifetime: Duration::from_secs(12 * 60 * 60),
            key_change_memory: Duration::from_secs(5 * 60),
            seen_every: Duration::from_secs(5 * 60),
            calls_per_minute: CALLS_PER_MINUTE_PER_USER,
            rate_burst: RATE_BURST,
            clock: unix_now,
        }
    }
}

/// What happened to a device that a `/connect` already in flight must not
/// outlive.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Change {
    /// Its key was replaced (the person signed in again on that computer).
    KeyReplaced,
    /// It was removed from the person's account.
    Revoked,
}

/// What a connector is told when it connects as a computer the account does
/// not have. Said the same for someone else's device and for one that does
/// not exist, so it never tells them apart.
const UNKNOWN_DEVICE: &str =
    "This computer is not registered with your account. Run `vrelay login` here to register it again.";

/// What a connector is told when its computer was removed from the account
/// (and proves it is that computer, by its key).
const REMOVED_DEVICE: &str =
    "This computer was removed from your account. Run `vrelay login` to connect it again.";

/// An MCP session: which device and person it was opened for.
struct Session {
    device_id: String,
    subject: String,
    client_id: String,
    last_used: Instant,
}

pub struct App {
    pub(crate) settings: Settings,
    mcp_verifier: Arc<Verifier>,
    connector_verifier: Arc<Verifier>,
    /// Pinned to the dashboard's own client id: its token works only on
    /// `/auth/*`, and no other token works there.
    pub(crate) dashboard_verifier: Arc<Verifier>,
    /// Dashboard sessions, and the client that exchanges a sign-in code.
    pub(crate) dashboard: Dashboard,
    pub(crate) store: Arc<dyn Store>,
    /// A counter that goes up each time a device's key is replaced
    /// ([`App::key_changed`]). A `/connect` takes the number before it reads
    /// the device's key, and registers only if that device has not changed
    /// since ([`App::key_changed_since`]). The relay is one process, so this
    /// is enough.
    key_generation: AtomicU64,
    /// Which generation each recently changed device changed at, how, and
    /// when. Only a `/connect` still in flight needs this, and one is over
    /// within [`Timing::key_change_memory`], so older entries are dropped:
    /// the map holds only the changes of the last few minutes, never one per
    /// device ever changed.
    key_changes: Mutex<HashMap<String, (u64, Instant, Change)>>,
    pub(crate) registry: Registry,
    mcp: Mcp,
    sessions: Mutex<HashMap<String, Session>>,
    pub(crate) timing: Timing,
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
        dashboard_verifier: Verifier,
        store: Arc<dyn Store>,
        timing: Timing,
        log: LogSink,
    ) -> Arc<App> {
        let registry = Registry::with_timeouts(timing.ack_timeout, timing.reconnect_grace);
        Arc::new(App {
            mcp: Mcp::new(
                registry.clone(),
                timing.call_budget,
                log.clone(),
                store.clone(),
            )
            .with_rate_limit(RateLimit::new(timing.calls_per_minute, timing.rate_burst))
            .with_parking(
                timing.approval_reply,
                timing.rejoin_window,
                timing.parked_result,
            ),
            settings,
            mcp_verifier: Arc::new(mcp),
            connector_verifier: Arc::new(connector),
            dashboard_verifier: Arc::new(dashboard_verifier),
            dashboard: Dashboard::new(concat!("vitruvian-relay/", env!("CARGO_PKG_VERSION"))),
            store,
            key_generation: AtomicU64::new(0),
            key_changes: Mutex::new(HashMap::new()),
            registry,
            sessions: Mutex::new(HashMap::new()),
            timing,
            log,
            #[cfg(test)]
            after_hello: Mutex::new(None),
            #[cfg(test)]
            hold_sends: Mutex::new(None),
        })
    }

    pub(crate) fn log(&self, event: &str, fields: Value) {
        log_event(&self.log, event, fields);
    }

    /// Records that `device_id` is connected, or has just been: its "last
    /// seen", which the offline message and the device list show. Done in the
    /// background, so a slow database never holds up the link (whose pings
    /// share the loop); a failure is logged and the next one tries again.
    fn note_seen(self: &Arc<Self>, device_id: &str) {
        let (app, id, at) = (self.clone(), device_id.to_string(), SystemTime::now());
        tokio::spawn(async move {
            if let Err(e) = app.store.touch_seen(&id, at).await {
                app.log(
                    "touch_seen_failed",
                    json!({"device_id": id, "error": e.to_string()}),
                );
            }
        });
    }

    /// The key generation now: take it before reading a device's key.
    fn key_generation(&self) -> u64 {
        self.key_generation.load(Ordering::SeqCst)
    }

    /// How the device changed after `generation` was taken: `None` if it
    /// has not.
    fn change_since(&self, device_id: &str, generation: u64) -> Option<Change> {
        self.key_changes
            .lock()
            .unwrap()
            .get(device_id)
            .filter(|(at, _, _)| *at > generation)
            .map(|(_, _, change)| *change)
    }

    /// True if the device's key was replaced, or the device removed, after
    /// `generation` was taken.
    fn key_changed_since(&self, device_id: &str, generation: u64) -> bool {
        self.change_since(device_id, generation).is_some()
    }

    /// Takes a new generation and remembers that `device_id` changed at it.
    fn note_change(&self, device_id: &str, change: Change) {
        let generation = self.key_generation.fetch_add(1, Ordering::SeqCst) + 1;
        let now = Instant::now();
        let memory = self.timing.key_change_memory;
        let mut changes = self.key_changes.lock().unwrap();
        changes.retain(|_, (_, when, _)| now.duration_since(*when) < memory);
        changes.insert(device_id.to_string(), (generation, now, change));
    }

    /// The device's key was replaced: ends its connection. The generation
    /// moves first, so a connection that checked the old key and has not
    /// registered yet cannot register after the kick.
    fn key_changed(&self, device_id: &str) {
        self.note_change(device_id, Change::KeyReplaced);
        self.registry.kick(device_id);
    }

    /// The device was removed from its owner's account: the same ordering as
    /// [`App::key_changed`] (a `/connect` that read the device a moment
    /// earlier cannot register after this), then its link ends, its calls in
    /// flight fail with [`crate::registry::CallError::Revoked`], and its AI
    /// app sessions are forgotten.
    fn device_removed(&self, device_id: &str) {
        self.note_change(device_id, Change::Revoked);
        self.registry.revoke(device_id);
        self.sessions
            .lock()
            .unwrap()
            .retain(|_, s| s.device_id != device_id);
    }

    /// The device `device_id` if `subject` owns it and it is not removed.
    /// This is the only ownership check: every route that names a device
    /// goes through it, so someone else's device and one that does not exist
    /// are the same answer (`None`) everywhere.
    pub async fn owned_device(
        &self,
        subject: &str,
        device_id: &str,
    ) -> Result<Option<DeviceRecord>, StoreError> {
        Ok(self
            .store
            .device(device_id)
            .await?
            .filter(|rec| rec.owner_sub == subject))
    }

    /// Removes `device_id` from `subject`'s account: stored as revoked, its
    /// link closed, and its calls in flight failed with "This computer was
    /// removed from your account." `false` if `subject` has no such device
    /// (someone else's, one that does not exist, or one already removed).
    pub async fn revoke(&self, subject: &str, device_id: &str) -> Result<bool, StoreError> {
        if self.owned_device(subject, device_id).await?.is_none() {
            return Ok(false);
        }
        if !self.store.revoke(device_id, subject).await? {
            return Ok(false);
        }
        self.device_removed(device_id);
        self.log("device_revoked", json!({"device_id": device_id}));
        Ok(true)
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
        .body(Body::new(body))
        .expect("static response parts are valid")
}

fn json_response(status: StatusCode, v: &Value) -> Response<Body> {
    respond(status, "application/json", v.to_string())
}

fn text(status: StatusCode, msg: &'static str) -> Response<Body> {
    respond(status, "text/plain", msg)
}

pub(crate) fn not_found() -> Response<Body> {
    text(StatusCode::NOT_FOUND, "not found")
}

/// A device id in a path: what `uuid_v4` makes, or anything shaped like it.
/// Checked before it goes into a header or a log line.
pub(crate) fn valid_device_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

pub(crate) fn header_str(req: &Request<Incoming>, name: header::HeaderName) -> Option<&str> {
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
pub(crate) async fn read_body(
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
    // The code only: the checker's message can name the subject. A person
    // who signed in but was never invited is logged as `role_missing`, which
    // the client sees as the `insufficient_scope` every 403 carries.
    let logged = match &r {
        Refused::Token(e) => e.log_code(),
        _ => code,
    };
    app.log("auth_refused", json!({"route": route, "code": logged}));
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
    if dashboard::wants(&method, &path) {
        return dashboard::handle(app, req).await;
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
    let tracker = req.extensions().get::<Arc<WriteTracker>>().cloned();
    let metadata_url = app.settings.device_metadata_url(&device_id);
    let caller =
        match authenticate(&app.mcp_verifier, header_str(&req, header::AUTHORIZATION)).await {
            Ok((caller, _token)) => caller,
            Err(r) => return refusal(&app, "mcp", &metadata_url, r),
        };
    // Someone else's device answers exactly like a missing one.
    let found = app.owned_device(&caller.subject, &device_id).await;
    match &found {
        Ok(Some(_)) => {}
        Ok(None) => return not_found(),
        // The database is not answering: say so plainly (below, once the
        // request is read, so a call can be answered as a call).
        Err(StoreError::Unavailable) => {}
        Err(_) => return not_found(),
    }
    let store_down = found.is_err();
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
    if store_down {
        app.log(
            "mcp_refused",
            json!({"device_id": device_id, "reason": "store_unavailable"}),
        );
        return match app.mcp.store_unavailable_call(&msg, &device_id, &caller) {
            Some(answer) => json_response(StatusCode::OK, &answer),
            None => text(StatusCode::SERVICE_UNAVAILABLE, UNAVAILABLE_MESSAGE),
        };
    }
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
        .handle_tracked(&msg, &device_id, &caller, session.as_deref())
        .await
    {
        None => respond(StatusCode::ACCEPTED, "text/plain", ""),
        Some(Answer { value: v, delivery }) => {
            // The stateless revision answers an unknown method with 404; the
            // older ones keep 200 with the JSON-RPC error.
            let status = if era == Era::Modern && v["error"]["code"] == -32601 {
                StatusCode::NOT_FOUND
            } else {
                StatusCode::OK
            };
            let mut resp = json_response(status, &v);
            if let Some(d) = delivery {
                resp = resp.map(|b| b.with_delivery(d, tracker));
            }
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
    let body = serde_json::from_slice::<Value>(&bytes).ok();
    let key = body
        .as_ref()
        .and_then(|v| v.get("public_key")?.as_str().map(String::from))
        .and_then(|k| base64::engine::general_purpose::STANDARD.decode(k).ok())
        .and_then(|k| <[u8; 32]>::try_from(k).ok());
    let (Some(body), Some(public_key_ed25519)) = (body, key) else {
        return text(
            StatusCode::BAD_REQUEST,
            "body must be {\"public_key\": \"<base64 of a 32-byte Ed25519 key>\", \"name\": \"<optional>\", \"device_id\": \"<optional>\"}",
        );
    };
    // The name is optional; one that is nothing once cleaned is a mistake
    // the person can fix.
    let name = match body.get("name") {
        None | Some(Value::Null) => None,
        Some(Value::String(raw)) => match clean_device_name(raw) {
            Some(name) => Some(name),
            None => {
                return json_response(
                    StatusCode::BAD_REQUEST,
                    &json!({"error": format!(
                        "Give this computer a name of 1 to {DEVICE_NAME_MAX} characters, then try again."
                    )}),
                )
            }
        },
        Some(_) => {
            return json_response(
                StatusCode::BAD_REQUEST,
                &json!({"error": "The computer's name must be text. Try again with a name."}),
            )
        }
    };
    // Only a person who asked for a new name (`vrelay login --name`) renames
    // a computer the relay already has; otherwise the name sent is only what
    // a new computer is called.
    let rename = match body.get("rename") {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => {
            return json_response(
                StatusCode::BAD_REQUEST,
                &json!({"error": "`rename` must be true or false."}),
            )
        }
    };
    let wanted = match body.get("device_id") {
        None | Some(Value::Null) => None,
        Some(Value::String(id)) => Some(id.as_str()),
        Some(_) => {
            return json_response(
                StatusCode::BAD_REQUEST,
                &json!({"error": "The device id must be text. Run `vrelay login` again."}),
            )
        }
    };

    // Signing in again on a computer this person already has keeps its id and
    // replaces its key (which ends the link made with the old one). An id that
    // is not theirs (someone else's, unknown, or removed) is not told apart
    // from one another: it just registers a new computer.
    if let Some(id) = wanted {
        match app.owned_device(&caller.subject, id).await {
            Ok(Some(rec)) => match app
                .store
                .replace_key(&rec.device_id, &caller.subject, public_key_ed25519)
                .await
            {
                Ok(true) => {
                    app.key_changed(&rec.device_id);
                    if let Some(name) = name.as_ref().filter(|_| rename) {
                        if let Err(e) = app
                            .store
                            .rename(&rec.device_id, &caller.subject, name)
                            .await
                        {
                            return store_failure(&app, "device_store_failed", &e);
                        }
                    }
                    app.log(
                        "device_registered",
                        json!({"device_id": rec.device_id, "client_id": caller.client_id, "replaced_key": true}),
                    );
                    return registered(&app, &rec.device_id);
                }
                // Removed in the meantime: register a new one instead.
                Ok(false) => {}
                Err(e) => return store_failure(&app, "device_store_failed", &e),
            },
            Ok(None) => {}
            Err(e) => return store_failure(&app, "device_store_failed", &e),
        }
    }

    // A new computer. The store counts this person's computers and refuses
    // the sixth atomically, so concurrent registrations cannot outrun it.
    let device_id = uuid_v4();
    let new = NewDevice {
        device_id: device_id.clone(),
        owner_sub: caller.subject.clone(),
        name: name.unwrap_or_else(|| DEFAULT_DEVICE_NAME.to_string()),
        public_key_ed25519,
    };
    if let Err(e) = app.store.insert_device(&new).await {
        return store_failure(&app, "device_store_failed", &e);
    }
    app.log(
        "device_registered",
        json!({"device_id": device_id, "client_id": caller.client_id, "replaced_key": false}),
    );
    registered(&app, &device_id)
}

fn registered(app: &App, device_id: &str) -> Response<Body> {
    json_response(
        StatusCode::OK,
        &json!({"device_id": device_id, "mcp_url": app.settings.device_mcp_url(device_id)}),
    )
}

/// The answer when the store could not do what a request needed: the
/// database being down is a 503 that says what to do; anything else (too many
/// computers) is a 409, `{"error": ...}`, that says the same.
fn store_failure(app: &App, event: &str, e: &StoreError) -> Response<Body> {
    app.log(event, json!({"error": e.to_string()}));
    match e {
        StoreError::Unavailable => text(StatusCode::SERVICE_UNAVAILABLE, UNAVAILABLE_MESSAGE),
        StoreError::TooManyDevices | StoreError::DuplicateId => {
            json_response(StatusCode::CONFLICT, &json!({"error": e.to_string()}))
        }
    }
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
        .body(Body::new(Bytes::new()))
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
    /// The reason goes back to the connector in `reject`. Returns the key
    /// generation from before the device's key was read (see
    /// [`App::key_changed`]): the session registers only if the device has
    /// not changed since.
    async fn check_hello(
        &self,
        hello: &Hello,
        caller: &Caller,
        token_hash: &str,
    ) -> Result<u64, String> {
        if hello.protocol != PROTOCOL {
            return Err(format!(
                "Update vrelay: this relay needs protocol {PROTOCOL}."
            ));
        }
        // Another person's device is "unknown", like one that does not exist.
        let generation = self.key_generation();
        let rec = match self.owned_device(&caller.subject, &hello.device_id).await {
            Ok(Some(r)) => r,
            Ok(None) => return Err(self.unknown_or_removed(hello, caller, token_hash).await),
            Err(e) => {
                self.log(
                    "connect_store_failed",
                    json!({"device_id": hello.device_id, "error": e.to_string()}),
                );
                return Err(e.to_string());
            }
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
        Ok(generation)
    }
}

impl App {
    /// What to tell a connector whose hello names a device that is not
    /// registered to this person. Nearly always [`UNKNOWN_DEVICE`], the same
    /// words for someone else's device and for one that never existed. The
    /// one exception: the device was this person's and was removed, and the
    /// hello is signed with that device's own key (for this token), so only
    /// that computer can be hearing it. Then it is told it was removed. A bad
    /// signature, someone else's id, a hello stamped too far from the relay's
    /// clock (the check every hello gets, so an old one that was captured
    /// cannot be replayed to ask), or any failure of the lookup gets the
    /// unknown answer.
    async fn unknown_or_removed(&self, hello: &Hello, caller: &Caller, token_hash: &str) -> String {
        if (self.timing.clock)().abs_diff(hello.ts) > self.timing.max_clock_skew_secs {
            return UNKNOWN_DEVICE.into();
        }
        let Ok(Some(rec)) = self.store.revoked_device(&hello.device_id).await else {
            return UNKNOWN_DEVICE.into();
        };
        let signed = base64::engine::general_purpose::STANDARD
            .decode(&hello.sig)
            .ok()
            .is_some_and(|sig| {
                let message = hello_message(&hello.device_id, hello.ts, token_hash);
                ring::signature::UnparsedPublicKey::new(
                    &ring::signature::ED25519,
                    rec.public_key_ed25519,
                )
                .verify(message.as_bytes(), &sig)
                .is_ok()
            });
        if rec.owner_sub == caller.subject && signed {
            REMOVED_DEVICE.into()
        } else {
            UNKNOWN_DEVICE.into()
        }
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
    let hello = async {
        let h = match tokio::time::timeout(t.hello_timeout, first_frame(&mut ws)).await {
            Ok(First::Closed) => return None,
            Err(_) => Err(format!(
                "no hello within {} s",
                t.hello_timeout.as_secs_f32()
            )),
            Ok(First::Other) => Err("the first frame must be hello".to_string()),
            Ok(First::Text(text)) => match decode_to_relay(&text) {
                Ok(ToRelay::Hello(h)) => Ok(h),
                _ => Err("the first frame must be hello".to_string()),
            },
        };
        Some(match h {
            Ok(h) => match app.check_hello(&h, &caller, &token_hash).await {
                Ok(generation) => match token_exp {
                    Some(exp) if exp <= (t.clock)() => {
                        Err("the token has expired; sign in again and reconnect".to_string())
                    }
                    _ => Ok((h, generation)),
                },
                Err(reason) => Err(reason),
            },
            Err(reason) => Err(reason),
        })
    }
    .await;
    let Some(hello) = hello else { return };
    let (hello, generation) = match hello {
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
    // Check the key has not changed since it was read, atomically with
    // registering: a connection checked with a key that has since been
    // replaced must not take the place of one made with the new key.
    let key_still_current = || !app.key_changed_since(&device_id, generation);
    // The closer is set when a cancel could not be queued: end at once,
    // sending nothing more, so the device treats it as a drop (and never runs
    // the call).
    let Some((conn, closer)) =
        app.registry
            .connect_if(&device_id, hello.tools, tx, key_still_current)
    else {
        app.log(
            "connect_rejected",
            json!({"device_id": device_id, "reason": "device registered again or removed"}),
        );
        let why = match app.change_since(&device_id, generation) {
            Some(Change::Revoked) => REMOVED_DEVICE,
            _ => "this device was registered again; reconnect with its new key",
        };
        let _ = send_frame(&mut sink, &reject(why.into()), send_timeout).await;
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
    app.note_seen(&device_id);
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
    // "Last seen" is brought up to date while the device stays connected, so
    // a computer that drops without a goodbye is still seen as of a few
    // minutes ago, not as of when it connected.
    let seen_every = t.seen_every.max(Duration::from_millis(1));
    let mut seen_ticker =
        tokio::time::interval_at(tokio::time::Instant::now() + seen_every, seen_every);
    seen_ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

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
            _ = seen_ticker.tick() => app.note_seen(&device_id),
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
                    Ok(ToRelay::Pending { call_id }) => {
                        app.registry.pending(conn, &call_id);
                    }
                    Ok(ToRelay::Hello(_)) => {}
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
    app.note_seen(&device_id);
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
    /// Told whenever the socket flushes.
    tracker: Option<Arc<WriteTracker>>,
}

impl<S> FirstHead<S> {
    fn new(inner: S, limit: Duration) -> Self {
        FirstHead {
            inner,
            limit: Some(Box::pin(tokio::time::sleep(limit))),
            matched: 0,
            tracker: None,
        }
    }

    fn tracking(mut self, tracker: Arc<WriteTracker>) -> Self {
        self.tracker = Some(tracker);
        self
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
        let r = std::pin::Pin::new(&mut self.inner).poll_flush(cx);
        if let (std::task::Poll::Ready(Ok(())), Some(t)) = (&r, &self.tracker) {
            t.flushed();
        }
        r
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
        tokio::spawn(serve_stream(app.clone(), stream));
    }
}

/// Serves one connection until it ends.
pub async fn serve_stream<S>(app: Arc<App>, stream: S)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
{
    let header_timeout = app.timing.header_read_timeout;
    let tracker = Arc::new(WriteTracker::default());
    let first = FirstHead::new(stream, app.timing.first_header_timeout).tracking(tracker.clone());
    let svc = service_fn(move |mut req: Request<Incoming>| {
        let app = app.clone();
        req.extensions_mut().insert(tracker.clone());
        async move { Ok::<_, Infallible>(handle(app, req).await) }
    });
    let _ = http1::Builder::new()
        .timer(TokioTimer::new())
        .header_read_timeout(header_timeout)
        .serve_connection(TokioIo::new(first), svc)
        .with_upgrades()
        .await;
}

#[cfg(test)]
#[path = "http_tests.rs"]
pub(crate) mod tests;
