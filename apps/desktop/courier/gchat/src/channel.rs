// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::auth::XsrfTokenManager;
use crate::cookies::DomainCookieJar;
use crate::netguard::NetGuard;
use crate::pblite::{decode_pblite, encode_pblite};
use crate::{googlechat, pb, GChatError, DESCRIPTOR_POOL};
use prost::Message;
use reqwest::header::{CONTENT_TYPE, COOKIE, USER_AGENT};
use reqwest::Client;
use serde_json::Value;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::time::{Duration, Instant};
use url::Url;

pub trait ChannelClock: Send + Sync {
    fn now_ms(&self) -> u64;
    fn jitter_unit(&self, attempt: usize) -> f64;
    fn sleep(&self, dur: Duration) -> Pin<Box<dyn Future<Output = ()> + Send>>;
}

pub struct SystemChannelClock;

impl ChannelClock for SystemChannelClock {
    fn now_ms(&self) -> u64 {
        static EPOCH: OnceLock<Instant> = OnceLock::new();
        let start = EPOCH.get_or_init(Instant::now);
        start.elapsed().as_millis() as u64
    }

    fn jitter_unit(&self, attempt: usize) -> f64 {
        let mut x = self
            .now_ms()
            .wrapping_add((attempt as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15));
        x = (x ^ (x >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        x = (x ^ (x >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        x ^= x >> 31;
        ((x >> 11) as f64) / ((1u64 << 53) as f64)
    }

    fn sleep(&self, dur: Duration) -> Pin<Box<dyn Future<Output = ()> + Send>> {
        Box::pin(tokio::time::sleep(dur))
    }
}

pub struct ManualChannelClock {
    now_ms: AtomicU64,
    fixed_jitter: f64,
    sleepers: Mutex<Vec<(u64, tokio::sync::oneshot::Sender<()>)>>,
    recorded_sleeps: Mutex<Vec<Duration>>,
    sleeper_registered: tokio::sync::Notify,
}

impl ManualChannelClock {
    pub fn new(fixed_jitter: f64) -> Self {
        Self {
            now_ms: AtomicU64::new(0),
            fixed_jitter: fixed_jitter.clamp(0.0, 1.0),
            sleepers: Mutex::new(Vec::new()),
            recorded_sleeps: Mutex::new(Vec::new()),
            sleeper_registered: tokio::sync::Notify::new(),
        }
    }

    pub fn advance(&self, dur: Duration) {
        let delta = dur.as_millis() as u64;
        let new_now = self.now_ms.fetch_add(delta, Ordering::SeqCst) + delta;
        let mut sleepers = self.sleepers.lock().unwrap();
        let mut remaining = Vec::with_capacity(sleepers.len());
        for (deadline, tx) in sleepers.drain(..) {
            if deadline <= new_now {
                let _ = tx.send(());
            } else {
                remaining.push((deadline, tx));
            }
        }
        *sleepers = remaining;
    }

    pub fn sleeper_count(&self) -> usize {
        let mut sleepers = self.sleepers.lock().unwrap();
        sleepers.retain(|(_, tx)| !tx.is_closed());
        sleepers.len()
    }

    pub fn recorded_sleeps(&self) -> Vec<Duration> {
        self.recorded_sleeps.lock().unwrap().clone()
    }
}

crate::edition2021! {
    impl ManualChannelClock {
        pub async fn wait_for_sleeper(&self) {
            self.wait_for_sleep_count(1).await;
        }

        pub async fn wait_for_sleep_count(&self, count: usize) {
            loop {
                let notified = self.sleeper_registered.notified();
                if self.recorded_sleeps.lock().unwrap().len() >= count && self.sleeper_count() > 0 {
                    return;
                }
                notified.await;
            }
        }

        pub async fn wait_for_sleep_duration(&self, target: Duration) {
            loop {
                let notified = self.sleeper_registered.notified();
                if self.recorded_sleeps.lock().unwrap().contains(&target) && self.sleeper_count() > 0 {
                    return;
                }
                notified.await;
            }
        }
    }

    impl ChannelClock for ManualChannelClock {
        fn now_ms(&self) -> u64 {
            self.now_ms.load(Ordering::SeqCst)
        }

        fn jitter_unit(&self, _attempt: usize) -> f64 {
            self.fixed_jitter
        }

        fn sleep(&self, dur: Duration) -> Pin<Box<dyn Future<Output = ()> + Send>> {
            self.recorded_sleeps.lock().unwrap().push(dur);
            let deadline = self
                .now_ms
                .load(Ordering::SeqCst)
                .saturating_add(dur.as_millis() as u64);
            let (tx, rx) = tokio::sync::oneshot::channel();
            {
                let mut sleepers = self.sleepers.lock().unwrap();
                sleepers.push((deadline, tx));
            }
            self.sleeper_registered.notify_waiters();
            Box::pin(async move {
                let _ = rx.await;
            })
        }
    }
}

pub const MAX_CHUNK_UTF16_UNITS: usize = 16 * 1024 * 1024; // 16 MiB cap
pub const PING_INTERVAL: Duration = Duration::from_secs(60);
pub const READ_INACTIVITY_TIMEOUT: Duration = Duration::from_secs(35);
pub const SERVER_EVENT_TIMEOUT: Duration = Duration::from_secs(90);
pub const RECONNECT_BACKOFF_LADDER_MS: [u64; 6] = [1_000, 2_000, 4_000, 8_000, 15_000, 30_000];

pub const GCHAT_EVENT_KIND_EVENT_PROTO: i32 = 1;
pub const GCHAT_EVENT_KIND_AUTH_EXPIRED: i32 = 2;
pub const GCHAT_EVENT_KIND_RESYNC: i32 = 3;
pub const GCHAT_EVENT_KIND_CONNECTED: i32 = 4;
pub const GCHAT_EVENT_KIND_STREAM_ERROR: i32 = 5;

/// Formats a sanitized stream error summary containing only the step name and
/// error kind (plus HTTP status code when applicable). Never includes URLs,
/// query strings, SIDs, cookies, tokens, or response bodies.
pub fn format_stream_error_message(step: &str, err: &GChatError) -> String {
    let safe_step = match step {
        "step1_register"
        | "step2_bind_sid"
        | "step3_ack_and_ping"
        | "step2_bind_poll"
        | "step4_poll_events" => step,
        _ => "stream",
    };
    let kind = match err {
        GChatError::CookieValidation(_) => "cookie_validation".to_string(),
        GChatError::AuthExpired(_) => "auth_expired".to_string(),
        GChatError::SsrfBlocked(_) => "ssrf_blocked".to_string(),
        GChatError::RateLimited => "rate_limited".to_string(),
        GChatError::HttpStatus(status, _) => format!("http_status:{status}"),
        GChatError::Network(_) => "network".to_string(),
        GChatError::Proto(_) => "proto".to_string(),
        GChatError::Protocol(_) => "protocol".to_string(),
        GChatError::Internal(_) => "internal".to_string(),
    };
    format!("{safe_step}: {kind}")
}

const POISONED_LINE_SENTINEL: u16 = 0xFFFF;

#[allow(non_snake_case)]
#[derive(Default)]
pub struct ChunkParser {
    utf8_Carry: Vec<u8>,
    utf16_buf: Vec<u16>,
}

impl ChunkParser {
    pub fn new() -> Self {
        Self::default()
    }

    /// Feeds arbitrary network byte slices (including mid-codepoint splits),
    /// extracts complete `<len>\n<payload>` frames measured in UTF-16 code units,
    /// and resyncs in O(n) single-pass on desync without quadratic scanning.
    pub fn push_bytes(&mut self, bytes: &[u8]) -> Result<Vec<String>, GChatError> {
        if !bytes.is_empty() {
            self.utf8_Carry.extend_from_slice(bytes);
            self.drain_valid_utf8_into_utf16();
        }

        let mut frames = Vec::new();
        let mut pos = 0usize;
        let mut oversized_err: Option<GChatError> = None;

        while pos < self.utf16_buf.len() {
            // Skip leading newlines/CRs between frames.
            while pos < self.utf16_buf.len()
                && (self.utf16_buf[pos] == b'\n' as u16 || self.utf16_buf[pos] == b'\r' as u16)
            {
                pos += 1;
            }
            if pos >= self.utf16_buf.len() {
                break;
            }

            // Single-pass resync if current position does not start with an ASCII digit.
            let first = self.utf16_buf[pos];
            if !(b'0' as u16..=b'9' as u16).contains(&first) {
                if let Some(rel_nl) = self.utf16_buf[pos..]
                    .iter()
                    .position(|&u| u == b'\n' as u16)
                {
                    pos += rel_nl + 1;
                    continue;
                } else {
                    self.utf16_buf.clear();
                    self.utf16_buf.push(POISONED_LINE_SENTINEL);
                    pos = 0;
                    break;
                }
            }

            // Scan digits up to '\n'.
            let mut cursor = pos;
            let mut want_len: Option<usize> = Some(0);
            let mut valid_header = true;
            let mut found_newline = false;

            while cursor < self.utf16_buf.len() {
                let u = self.utf16_buf[cursor];
                if u == b'\n' as u16 {
                    found_newline = true;
                    break;
                }
                if u == b'\r' as u16 {
                    cursor += 1;
                    continue;
                }
                if (b'0' as u16..=b'9' as u16).contains(&u) {
                    let digit = (u - b'0' as u16) as usize;
                    want_len = want_len
                        .and_then(|acc| acc.checked_mul(10))
                        .and_then(|acc| acc.checked_add(digit));
                    cursor += 1;
                } else {
                    valid_header = false;
                    break;
                }
            }

            if !valid_header {
                // Single-pass resync to the next newline.
                if let Some(rel_nl) = self.utf16_buf[cursor..]
                    .iter()
                    .position(|&u| u == b'\n' as u16)
                {
                    pos = cursor + rel_nl + 1;
                    continue;
                } else {
                    self.utf16_buf.clear();
                    self.utf16_buf.push(POISONED_LINE_SENTINEL);
                    pos = 0;
                    break;
                }
            }

            if !found_newline {
                // Still waiting for the rest of the length header.
                if want_len.map_or(true, |n| n > MAX_CHUNK_UTF16_UNITS) {
                    self.utf16_buf.clear();
                    self.utf16_buf.push(POISONED_LINE_SENTINEL);
                    return Err(GChatError::Protocol(format!(
                        "WebChannel chunk length exceeds max {MAX_CHUNK_UTF16_UNITS} UTF-16 units"
                    )));
                }
                break;
            }

            let newline_pos = cursor;
            let Some(frame_units) = want_len.filter(|&n| n <= MAX_CHUNK_UTF16_UNITS) else {
                pos = newline_pos + 1;
                oversized_err = Some(GChatError::Protocol(format!(
                    "WebChannel chunk length exceeds max {MAX_CHUNK_UTF16_UNITS} UTF-16 units"
                )));
                break;
            };

            let payload_start = newline_pos + 1;
            let payload_end = payload_start.saturating_add(frame_units);
            if self.utf16_buf.len() < payload_end {
                // Incomplete payload; wait for more network bytes.
                break;
            }

            let payload_slice = &self.utf16_buf[payload_start..payload_end];
            frames.push(String::from_utf16_lossy(payload_slice));
            pos = payload_end;
        }

        if pos > 0 {
            self.utf16_buf.drain(..pos);
        }

        if let Some(err) = oversized_err {
            return Err(err);
        }

        Ok(frames)
    }

    fn drain_valid_utf8_into_utf16(&mut self) {
        let mut consumed = 0usize;
        while consumed < self.utf8_Carry.len() {
            match std::str::from_utf8(&self.utf8_Carry[consumed..]) {
                Ok(valid) => {
                    self.utf16_buf.extend(valid.encode_utf16());
                    consumed = self.utf8_Carry.len();
                }
                Err(err) => {
                    let valid_len = err.valid_up_to();
                    if valid_len > 0 {
                        let valid_str =
                            std::str::from_utf8(&self.utf8_Carry[consumed..consumed + valid_len])
                                .unwrap_or("");
                        self.utf16_buf.extend(valid_str.encode_utf16());
                        consumed += valid_len;
                    }
                    match err.error_len() {
                        Some(invalid_len) => {
                            // Corrupted UTF-8 sequence inside stream; emit replacement char and advance.
                            self.utf16_buf.push(0xFFFD);
                            consumed += invalid_len;
                        }
                        None => {
                            // Incomplete trailing multi-byte UTF-8 sequence (1..=3 bytes); hold back!
                            break;
                        }
                    }
                }
            }
        }
        if consumed > 0 {
            self.utf8_Carry.drain(..consumed);
        }
    }
}

/// Extracts all EventBody entries in order: singular `event.body` (field 4) first,
/// followed by all entries in repeated `event.bodies` (field 8).
pub fn extract_event_bodies(event: &googlechat::Event) -> Vec<googlechat::event::EventBody> {
    let mut bodies = Vec::with_capacity(usize::from(event.body.is_some()) + event.bodies.len());
    if let Some(first) = &event.body {
        bodies.push(first.clone());
    }
    bodies.extend(event.bodies.iter().cloned());
    bodies
}

/// Splits a parent `Event` into one `Event` per extracted `EventBody` (matching
/// `ref/pkg/gchatmeow/client.go:298-318`).
pub fn split_event_into_events(event: &googlechat::Event) -> Vec<googlechat::Event> {
    let bodies = extract_event_bodies(event);
    if bodies.is_empty() {
        return Vec::new();
    }
    let mut base = event.clone();
    base.body = None;
    base.bodies.clear();

    bodies
        .into_iter()
        .map(|body| {
            let mut single = base.clone();
            if body.event_type.is_some() {
                single.r#type = body.event_type;
            }
            single.body = Some(body);
            single
        })
        .collect()
}

/// Computes the reconnect backoff delay from the `1s -> 2s -> 4s -> 8s -> 15s -> 30s`
/// ladder with up to +25% positive jitter (`jitter_unit` in `[0.0, 1.0]`).
pub fn reconnect_backoff_delay(attempt: usize, jitter_unit: f64) -> Duration {
    let idx = attempt.min(RECONNECT_BACKOFF_LADDER_MS.len() - 1);
    let base_ms = RECONNECT_BACKOFF_LADDER_MS[idx];
    let clamped = jitter_unit.clamp(0.0, 1.0);
    let jitter_ms = ((base_ms as f64) * 0.25 * clamped).round() as u64;
    Duration::from_millis(base_ms + jitter_ms)
}

pub fn build_active_ping_request() -> pb::StreamEventsRequest {
    pb::StreamEventsRequest {
        ping_event: Some(pb::PingEvent {
            state: Some(pb::ping_event::State::Active as i32),
            application_focus_state: Some(
                pb::ping_event::ApplicationFocusState::FocusStateForeground as i32,
            ),
            client_interactive_state: Some(
                pb::ping_event::ClientInteractiveState::Interactive as i32,
            ),
            client_notifications_enabled: Some(true),
            ..Default::default()
        }),
        ..Default::default()
    }
}

/// Encodes a WebChannel forward-channel payload as `count=1&ofs=<ofs>&req0_data=<urlencoded JSON>`.
fn encode_req0_form_body(ofs: i64, req0_json: &str) -> String {
    url::form_urlencoded::Serializer::new(String::new())
        .append_pair("count", "1")
        .append_pair("ofs", &ofs.to_string())
        .append_pair("req0_data", req0_json)
        .finish()
}

pub struct WebChannelClient {
    http: Client,
    jar: DomainCookieJar,
    xsrf: Arc<XsrfTokenManager>,
    guard: NetGuard,
    user_agent: String,
    base_url: Url,
    clock: RwLock<Arc<dyn ChannelClock>>,
    aid: AtomicI64,
    rid: AtomicI64,
    ofs: AtomicI64,
}

crate::edition2021! {
    impl WebChannelClient {
        pub fn new(
            http: Client,
            jar: DomainCookieJar,
            xsrf: Arc<XsrfTokenManager>,
            guard: NetGuard,
            user_agent: String,
            base_url: Url,
        ) -> Self {
            Self::with_clock(
                http,
                jar,
                xsrf,
                guard,
                user_agent,
                base_url,
                Arc::new(SystemChannelClock),
            )
        }

        pub fn with_clock(
            http: Client,
            jar: DomainCookieJar,
            xsrf: Arc<XsrfTokenManager>,
            guard: NetGuard,
            user_agent: String,
            base_url: Url,
            clock: Arc<dyn ChannelClock>,
        ) -> Self {
            Self {
                http,
                jar,
                xsrf,
                guard,
                user_agent,
                base_url,
                clock: RwLock::new(clock),
                aid: AtomicI64::new(0),
                rid: AtomicI64::new(42000),
                ofs: AtomicI64::new(0),
            }
        }

        pub fn set_clock(&self, clock: Arc<dyn ChannelClock>) {
            *self.clock.write().unwrap() = clock;
        }

        fn clock(&self) -> Arc<dyn ChannelClock> {
            self.clock.read().unwrap().clone()
        }

        pub fn ofs(&self) -> i64 {
            self.ofs.load(Ordering::SeqCst)
        }

        pub fn aid(&self) -> i64 {
            self.aid.load(Ordering::SeqCst)
        }

        fn next_rid(&self) -> i64 {
            self.rid.fetch_add(1, Ordering::SeqCst)
        }

        fn next_ofs(&self) -> i64 {
            self.ofs.fetch_add(1, Ordering::SeqCst)
        }

        fn next_zx(&self) -> String {
            let seq = self.rid.load(Ordering::Relaxed) as u64;
            let now = self.clock().now_ms();
            let mut val = now
                .wrapping_mul(6364136223846793005)
                .wrapping_add(seq.wrapping_mul(1442695040888963407))
                ^ 0x9e3779b97f4a7c15;
            const ALPHABET: &[u8; 36] = b"0123456789abcdefghijklmnopqrstuvwxyz";
            let mut out = String::with_capacity(12);
            for _ in 0..12 {
                out.push(ALPHABET[(val % 36) as usize] as char);
                val /= 36;
                if val == 0 {
                    val = seq.wrapping_add(0x517cc1b727220a95);
                }
            }
            out
        }

        /// Executes the 4-step WebChannel handshake (spec §6.2) and drains one long-poll response stream:
        /// Step 1: `GET /u/0/webchannel/register?ignore_compass_cookie=1` (`Content-Type: application/x-protobuf`),
        ///         extracting and absorbing rotated `COMPASS=dynamite-ui=<csessionid>` from `Set-Cookie`.
        /// Step 2: `GET /u/0/webchannel/events?VER=8&RID=<rid>&t=1&zx=<zx>&CVER=22&$req=count%3D1%26ofs%3D0%26req0_data%3D%255B%255D&SID=null`
        ///         and parsing `<sid>` from `X-HTTP-Initial-Response`.
        /// Step 3: Ack `GET /u/0/webchannel/events?VER=8&RID=rpc&SID=<sid>&AID=0&CI=0&TYPE=xmlhttp&zx=<zx>&t=1`,
        ///         then `POST /u/0/webchannel/events?VER=8&RID=<rid>&t=1&SID=<sid>&AID=0` with `count=1&ofs=0&req0_data=<PingEvent>`.
        /// Step 4: Long-poll `GET /u/0/webchannel/events?VER=8&RID=rpc&t=1&zx=<zx>&CI=0&TYPE=xmlhttp&AID=<aid>&SID=<sid>`.
        pub async fn handshake_and_poll_once<F>(
            &self,
            mut on_event: F,
        ) -> Result<Vec<pb::Event>, GChatError>
        where
            F: FnMut(&pb::Event),
        {
            self.aid.store(0, Ordering::SeqCst);
            self.ofs.store(0, Ordering::SeqCst);

            // Step 1: GET /u/0/webchannel/register?ignore_compass_cookie=1
            let _csessionid = self.step1_register().await?;

            // Step 2: GET /u/0/webchannel/events?...&SID=null -> X-HTTP-Initial-Response
            let (sid, bind_resp) = self.step2_bind_sid().await?;

            // Step 3: Ack GET + initial PingEvent POST at ofs=0, AID=0
            self.step3_ack_and_ping(&sid).await?;

            // Read the bind GET response body as the first long-poll stream, then poll Step 4.
            let mut events = self.read_poll_response(bind_resp, &mut on_event).await?;
            if events.is_empty() {
                events.extend(self.step4_poll_events(&sid, &mut on_event).await?);
            }

            Ok(events)
        }

        pub async fn step1_register(&self) -> Result<String, GChatError> {
            // Reset AID and ofs on every fresh session registration (spec §6.2 Step 1).
            self.aid.store(0, Ordering::SeqCst);
            self.ofs.store(0, Ordering::SeqCst);

            let mut url = self
                .base_url
                .join("/u/0/webchannel/register")
                .map_err(|e| GChatError::Internal(format!("invalid register URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("ignore_compass_cookie", "1");
            }
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .get(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(CONTENT_TYPE, "application/x-protobuf");
            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header(COOKIE, cookie_hdr);
            }

            let resp = req
                .send()
                .await
                .map_err(|e| GChatError::Network(format!("webchannel register failed: {e}")))?;
            let status = resp.status().as_u16();
            if status == 401 || status == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "webchannel register returned HTTP {status}"
                )));
            }
            if !resp.status().is_success() {
                return Err(GChatError::HttpStatus(
                    status,
                    "webchannel register failed".to_string(),
                ));
            }

            let set_cookies: Vec<String> = resp
                .headers()
                .get_all(reqwest::header::SET_COOKIE)
                .iter()
                .filter_map(|v| v.to_str().ok().map(|s| s.to_owned()))
                .collect();

            let _ = resp
                .bytes()
                .await
                .map_err(|e| GChatError::Network(format!("register body read failed: {e}")))?;

            let Some(compass_val) = self.jar.absorb_set_cookies(&set_cookies) else {
                return Err(GChatError::Protocol(
                    "webchannel register missing COMPASS Set-Cookie".to_string(),
                ));
            };
            let csessionid = compass_val
                .strip_prefix("dynamite-ui=")
                .unwrap_or(compass_val.as_str())
                .trim()
                .to_string();
            if csessionid.is_empty() {
                return Err(GChatError::Protocol(
                    "webchannel register returned empty COMPASS csessionid".to_string(),
                ));
            }
            Ok(csessionid)
        }

        pub async fn step2_bind_sid(&self) -> Result<(String, reqwest::Response), GChatError> {
            let rid = self.next_rid();
            let zx = self.next_zx();
            let mut url = self
                .base_url
                .join("/u/0/webchannel/events")
                .map_err(|e| GChatError::Internal(format!("invalid events URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("VER", "8");
                qp.append_pair("RID", &rid.to_string());
                qp.append_pair("t", "1");
                qp.append_pair("zx", &zx);
                qp.append_pair("CVER", "22");
                qp.append_pair("$req", "count=1&ofs=0&req0_data=%5B%5D");
                qp.append_pair("SID", "null");
            }
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .get(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(reqwest::header::REFERER, "https://chat.google.com/");
            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header(COOKIE, cookie_hdr);
            }

            let resp = req
                .send()
                .await
                .map_err(|e| GChatError::Network(format!("webchannel SID bind failed: {e}")))?;
            let status = resp.status().as_u16();
            if status == 401 || status == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "webchannel SID bind returned HTTP {status}"
                )));
            }
            if !resp.status().is_success() {
                return Err(GChatError::HttpStatus(
                    status,
                    "webchannel SID bind failed".to_string(),
                ));
            }

            let set_cookies: Vec<String> = resp
                .headers()
                .get_all(reqwest::header::SET_COOKIE)
                .iter()
                .filter_map(|v| v.to_str().ok().map(|s| s.to_owned()))
                .collect();
            if !set_cookies.is_empty() {
                self.jar.absorb_set_cookies(&set_cookies);
            }

            let initial_hdr = resp
                .headers()
                .get("X-HTTP-Initial-Response")
                .or_else(|| resp.headers().get("x-http-initial-response"))
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_owned());

            if let Some(hdr) = initial_hdr {
                if let Some(sid) = parse_sid_from_json(&hdr) {
                    self.aid.store(0, Ordering::SeqCst);
                    self.ofs.store(0, Ordering::SeqCst);
                    return Ok((sid, resp));
                }
            }

            Err(GChatError::Protocol(
                "missing SID in WebChannel X-HTTP-Initial-Response header".to_string(),
            ))
        }

        pub async fn step3_ack_and_ping(&self, sid: &str) -> Result<(), GChatError> {
            self.step3_ack_sid(sid).await?;
            self.step3_send_ping(sid).await
        }

        pub async fn step3_ack_sid(&self, sid: &str) -> Result<(), GChatError> {
            let zx = self.next_zx();
            let mut url = self
                .base_url
                .join("/u/0/webchannel/events")
                .map_err(|e| GChatError::Internal(format!("invalid events URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("VER", "8");
                qp.append_pair("RID", "rpc");
                qp.append_pair("SID", sid);
                qp.append_pair("AID", "0");
                qp.append_pair("CI", "0");
                qp.append_pair("TYPE", "xmlhttp");
                qp.append_pair("zx", &zx);
                qp.append_pair("t", "1");
            }
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .get(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(reqwest::header::REFERER, "https://chat.google.com/");
            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header(COOKIE, cookie_hdr);
            }

            let resp = req
                .send()
                .await
                .map_err(|e| GChatError::Network(format!("webchannel SID ack GET failed: {e}")))?;
            let status = resp.status().as_u16();
            if status == 401 || status == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "webchannel SID ack returned HTTP {status}"
                )));
            }
            if !resp.status().is_success() {
                return Err(GChatError::HttpStatus(
                    status,
                    "webchannel SID ack GET failed".to_string(),
                ));
            }
            let _ = resp.bytes().await;
            Ok(())
        }

        pub async fn step3_send_ping(&self, sid: &str) -> Result<(), GChatError> {
            let rid = self.next_rid();
            let ofs = self.next_ofs();
            let aid = self.aid();

            let req_proto = build_active_ping_request();
            let desc = DESCRIPTOR_POOL
                .get_message_by_name("googlechat.StreamEventsRequest")
                .ok_or_else(|| {
                    GChatError::Internal("missing StreamEventsRequest descriptor".to_string())
                })?;
            let pblite_val = encode_pblite(&desc, &req_proto)?;
            let json_str = serde_json::to_string(&pblite_val)
                .map_err(|e| GChatError::Protocol(format!("serialize PingEvent failed: {e}")))?;

            let mut url = self
                .base_url
                .join("/u/0/webchannel/events")
                .map_err(|e| GChatError::Internal(format!("invalid events URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("VER", "8");
                qp.append_pair("RID", &rid.to_string());
                qp.append_pair("t", "1");
                qp.append_pair("SID", sid);
                qp.append_pair("AID", &aid.to_string());
            }
            self.guard.validate_url(&url, false).await?;

            let form_body = encode_req0_form_body(ofs, &json_str);
            let mut req = self
                .http
                .post(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(reqwest::header::REFERER, "https://chat.google.com/")
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .body(form_body);
            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header(COOKIE, cookie_hdr);
            }

            let resp = req
                .send()
                .await
                .map_err(|e| GChatError::Network(format!("webchannel ping POST failed: {e}")))?;
            let status = resp.status().as_u16();
            if status == 401 || status == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "webchannel ping returned HTTP {status}"
                )));
            }
            if !resp.status().is_success() {
                return Err(GChatError::HttpStatus(
                    status,
                    "webchannel ping POST failed".to_string(),
                ));
            }
            Ok(())
        }

        pub async fn step4_open_poll(&self, sid: &str) -> Result<reqwest::Response, GChatError> {
            let aid = self.aid();
            let zx = self.next_zx();
            let mut url = self
                .base_url
                .join("/u/0/webchannel/events")
                .map_err(|e| GChatError::Internal(format!("invalid events URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("VER", "8");
                qp.append_pair("RID", "rpc");
                qp.append_pair("t", "1");
                qp.append_pair("zx", &zx);
                qp.append_pair("CI", "0");
                qp.append_pair("TYPE", "xmlhttp");
                qp.append_pair("AID", &aid.to_string());
                qp.append_pair("SID", sid);
            }
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .get(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(reqwest::header::REFERER, "https://chat.google.com/");
            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header(COOKIE, cookie_hdr);
            }

            let resp = req
                .send()
                .await
                .map_err(|e| GChatError::Network(format!("webchannel GET stream failed: {e}")))?;
            let status = resp.status().as_u16();
            if status == 401 || status == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "webchannel GET returned HTTP {status}"
                )));
            }
            if status == 400 {
                return Err(GChatError::HttpStatus(400, "Unknown SID".to_string()));
            }
            if !resp.status().is_success() {
                return Err(GChatError::HttpStatus(
                    status,
                    "webchannel GET failed".to_string(),
                ));
            }
            Ok(resp)
        }

        pub async fn read_poll_response<F>(
            &self,
            mut resp: reqwest::Response,
            on_event: &mut F,
        ) -> Result<Vec<pb::Event>, GChatError>
        where
            F: FnMut(&pb::Event),
        {
            let mut parser = ChunkParser::new();
            let mut emitted = Vec::new();
            let clock = self.clock();
            let mut last_event_at = clock.now_ms();
            let server_timeout_ms = SERVER_EVENT_TIMEOUT.as_millis() as u64;

            loop {
                let now = clock.now_ms();
                let elapsed_since_event = now.saturating_sub(last_event_at);
                if elapsed_since_event >= server_timeout_ms {
                    return Err(GChatError::Network(
                        "webchannel server-event 90s watchdog expired".to_string(),
                    ));
                }

                let rem_server = Duration::from_millis(server_timeout_ms - elapsed_since_event);
                let wait_dur = READ_INACTIVITY_TIMEOUT.min(rem_server);

                let next_chunk = tokio::select! {
                    _ = clock.sleep(wait_dur) => {
                        if clock.now_ms().saturating_sub(last_event_at) >= server_timeout_ms {
                            return Err(GChatError::Network(
                                "webchannel server-event 90s watchdog expired".to_string(),
                            ));
                        }
                        return Err(GChatError::Network(
                            "webchannel read-inactivity 35s watchdog expired".to_string(),
                        ));
                    }
                    res = resp.chunk() => {
                        res.map_err(|e| GChatError::Network(format!("webchannel stream read error: {e}")))?
                    }
                };

                let Some(chunk) = next_chunk else {
                    break;
                };

                let frames = parser.push_bytes(&chunk)?;
                for frame in frames {
                    let (parsed_events, saw_valid_frame) = self.process_chunk_frame(&frame)?;
                    if saw_valid_frame {
                        last_event_at = clock.now_ms();
                    }
                    for ev in parsed_events {
                        on_event(&ev);
                        emitted.push(ev);
                    }
                }
            }

            Ok(emitted)
        }

        pub async fn step4_poll_events<F>(
            &self,
            sid: &str,
            on_event: &mut F,
        ) -> Result<Vec<pb::Event>, GChatError>
        where
            F: FnMut(&pb::Event),
        {
            let resp = self.step4_open_poll(sid).await?;
            self.read_poll_response(resp, on_event).await
        }

        fn process_chunk_frame(&self, frame: &str) -> Result<(Vec<pb::Event>, bool), GChatError> {
            let outer: Value = serde_json::from_str(frame).map_err(|e| {
                GChatError::Protocol(format!("invalid WebChannel chunk JSON: {e}"))
            })?;
            let Some(entries) = outer.as_array() else {
                return Ok((Vec::new(), false));
            };

            let stream_resp_desc = DESCRIPTOR_POOL
                .get_message_by_name("googlechat.StreamEventsResponse")
                .ok_or_else(|| {
                    GChatError::Internal("missing StreamEventsResponse descriptor".to_string())
                })?;

            let mut out = Vec::new();
            let mut saw_valid_frame = false;
            for entry in entries {
                let Some(pair) = entry.as_array() else {
                    continue;
                };
                if pair.len() < 2 {
                    continue;
                }
                let array_id = pair[0]
                    .as_i64()
                    .or_else(|| pair[0].as_str().and_then(|s| s.parse::<i64>().ok()));
                if let Some(data_arr) = pair[1].as_array() {
                    if let Some(first) = data_arr.first() {
                        if first.as_str() == Some("noop") || first.as_str() == Some("c") {
                            saw_valid_frame = true;
                        } else if first.is_array() {
                            saw_valid_frame = true;
                            if let Ok(sr) = decode_pblite::<pb::StreamEventsResponse>(&stream_resp_desc, first) {
                                if let Some(ev) = sr.event {
                                    let split = split_event_into_events(&ev);
                                    if split.is_empty() {
                                        out.push(ev);
                                    } else {
                                        out.extend(split);
                                    }
                                }
                            }
                        }
                    }
                }
                if let Some(aid) = array_id {
                    self.aid.store(aid, Ordering::SeqCst);
                }
            }
            Ok((out, saw_valid_frame))
        }

        pub async fn run_forever<F>(
            self: Arc<Self>,
            mut cancel_rx: tokio::sync::watch::Receiver<bool>,
            mut emit: F,
        ) where
            F: FnMut(i32, &[u8]) + Send + 'static,
        {
            let mut attempt = 0usize;
            loop {
                if *cancel_rx.borrow() {
                    break;
                }

                let reg_res = tokio::select! {
                    _ = cancel_rx.changed() => break,
                    r = self.step1_register() => r,
                };
                if let Err(e) = reg_res {
                    if !self.handle_stream_error("step1_register", e, &mut attempt, &mut cancel_rx, &mut emit).await {
                        break;
                    }
                    continue;
                }

                let sid_res = tokio::select! {
                    _ = cancel_rx.changed() => break,
                    r = self.step2_bind_sid() => r,
                };
                let (sid, bind_resp) = match sid_res {
                    Ok(pair) => pair,
                    Err(e) => {
                        if !self.handle_stream_error("step2_bind_sid", e, &mut attempt, &mut cancel_rx, &mut emit).await {
                            break;
                        }
                        continue;
                    }
                };

                let ack_ping_res = tokio::select! {
                    _ = cancel_rx.changed() => break,
                    r = self.step3_ack_and_ping(&sid) => r,
                };
                if let Err(e) = ack_ping_res {
                    drop(bind_resp);
                    if !self.handle_stream_error("step3_ack_and_ping", e, &mut attempt, &mut cancel_rx, &mut emit).await {
                        break;
                    }
                    continue;
                }

                let cookies_json = self.jar.to_cookie_map_json();
                emit(GCHAT_EVENT_KIND_CONNECTED, cookies_json.as_bytes());
                if attempt > 0 {
                    emit(GCHAT_EVENT_KIND_RESYNC, &[]);
                }
                attempt = 0;

                // Read the bind GET response body as the first long-poll stream.
                {
                    let mut on_ev = |ev: &pb::Event| {
                        let bytes = ev.encode_to_vec();
                        emit(GCHAT_EVENT_KIND_EVENT_PROTO, &bytes);
                    };
                    let bind_poll_res = tokio::select! {
                        _ = cancel_rx.changed() => return,
                        r = self.read_poll_response(bind_resp, &mut on_ev) => r,
                    };
                    drop(on_ev);
                    if let Err(e) = bind_poll_res {
                        if !self.handle_stream_error("step2_bind_poll", e, &mut attempt, &mut cancel_rx, &mut emit).await {
                            return;
                        }
                        continue;
                    }
                }

                // Long-poll rotation loop preserving AID while SID remains valid.
                loop {
                    if *cancel_rx.borrow() {
                        return;
                    }
                    let mut on_ev = |ev: &pb::Event| {
                        let bytes = ev.encode_to_vec();
                        emit(GCHAT_EVENT_KIND_EVENT_PROTO, &bytes);
                    };
                    let poll_res = tokio::select! {
                        _ = cancel_rx.changed() => return,
                        r = self.step4_poll_events(&sid, &mut on_ev) => r,
                    };
                    drop(on_ev);
                    match poll_res {
                        Ok(_) => {
                            // Normal long-poll EOF rotation: preserve AID and re-open GET.
                            continue;
                        }
                        Err(e) => {
                            if !self.handle_stream_error("step4_poll_events", e, &mut attempt, &mut cancel_rx, &mut emit).await {
                                return;
                            }
                            break;
                        }
                    }
                }
            }
        }

        async fn handle_stream_error<F>(
            &self,
            step: &'static str,
            err: GChatError,
            attempt: &mut usize,
            cancel_rx: &mut tokio::sync::watch::Receiver<bool>,
            emit: &mut F,
        ) -> bool
        where
            F: FnMut(i32, &[u8]),
        {
            if matches!(err, GChatError::AuthExpired(_)) {
                if self.xsrf.refresh_if_generation(u64::MAX).await.is_err() {
                    let msg = err.to_string();
                    emit(GCHAT_EVENT_KIND_AUTH_EXPIRED, msg.as_bytes());
                    return false;
                }
            }
            let summary = format_stream_error_message(step, &err);
            emit(GCHAT_EVENT_KIND_STREAM_ERROR, summary.as_bytes());
            let clock = self.clock();
            let delay = reconnect_backoff_delay(*attempt, clock.jitter_unit(*attempt));
            *attempt = attempt.saturating_add(1);
            tokio::select! {
                _ = cancel_rx.changed() => false,
                _ = clock.sleep(delay) => true,
            }
        }
    }
}

fn parse_sid_from_json(raw: &str) -> Option<String> {
    let val: Value = serde_json::from_str(raw.trim()).ok()?;
    let outer = val.as_array()?;
    let first = outer.first()?.as_array()?;
    let cmd = first.get(1)?.as_array()?;
    if cmd.first()?.as_str() == Some("c") {
        let sid = cmd.get(1)?.as_str()?.trim();
        if !sid.is_empty() {
            return Some(sid.to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cookies::ScopedCookie;
    use serde_json::json;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    #[test]
    fn test_chunk_parser_counts_utf16_code_units_across_split_4byte_emojis() {
        let mut parser = ChunkParser::new();
        // Payload `[[1,["🔥🎉"]]]`:
        // `[[1,["` = 6 UTF-16 units
        // `🔥🎉` = 4 UTF-16 units (2 surrogate pairs, 8 UTF-8 bytes: \xF0\x9F\x94\xA5 \xF0\x9F\x8E\x89)
        // `"]]]` = 4 UTF-16 units
        // Total = 14 UTF-16 code units (18 UTF-8 bytes).
        let payload = "[[1,[\"🔥🎉\"]]]";
        assert_eq!(payload.encode_utf16().count(), 14);
        assert_eq!(payload.len(), 18);

        let full_frame = format!("14\n{payload}").into_bytes();
        // Split right in the middle of the first 4-byte emoji `\xF0\x9F` | `\x94\xA5`
        // "14\n[[1,[\"" is 9 bytes, so bytes 9..11 are \xF0\x9F and 11..13 are \x94\xA5.
        let split_at = 11;
        assert_eq!(&full_frame[9..11], &[0xF0, 0x9F]);
        assert_eq!(&full_frame[11..13], &[0x94, 0xA5]);

        let first = parser
            .push_bytes(&full_frame[..split_at])
            .expect("first push_bytes should hold back partial UTF-8");
        assert!(
            first.is_empty(),
            "expected no complete frame yet, got {first:?}"
        );

        let second = parser
            .push_bytes(&full_frame[split_at..])
            .expect("second push_bytes should complete emoji and frame");
        assert_eq!(second, vec![payload.to_string()]);
    }

    #[test]
    fn test_chunk_parser_rejects_oversized_frame_and_resyncs_in_single_pass() {
        let mut parser = ChunkParser::new();
        let err = parser
            .push_bytes(b"20000000\n[[1,[\"noop\"]]]")
            .expect_err("frame > 16M UTF-16 units must return GChatError::Protocol");
        assert!(
            matches!(err, GChatError::Protocol(_)),
            "expected GChatError::Protocol, got {err:?}"
        );

        let mut resync_parser = ChunkParser::new();
        let frames = resync_parser
            .push_bytes(b"corrupted_garbage_without_length\n14\n[[1,[\"noop\"]]]")
            .expect("single-pass resync after corrupted prefix");
        assert_eq!(frames, vec!["[[1,[\"noop\"]]]".to_string()]);
    }

    #[test]
    fn test_extract_event_bodies_emits_field_4_then_field_8_in_order() {
        let ev = pb::Event {
            body: Some(pb::event::EventBody {
                event_type: Some(pb::event::EventType::MessagePosted as i32),
                trace_id: Some(101),
                ..Default::default()
            }),
            bodies: vec![
                pb::event::EventBody {
                    event_type: Some(pb::event::EventType::MessageReacted as i32),
                    trace_id: Some(202),
                    ..Default::default()
                },
                pb::event::EventBody {
                    event_type: Some(pb::event::EventType::TypingStateChanged as i32),
                    trace_id: Some(303),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };

        let bodies = extract_event_bodies(&ev);
        let trace_ids: Vec<Option<i64>> = bodies.iter().map(|b| b.trace_id).collect();
        assert_eq!(trace_ids, vec![Some(101), Some(202), Some(303)]);
    }

    fn read_http_request(stream: &mut std::net::TcpStream) -> (String, String, String) {
        let mut buf = Vec::new();
        let mut temp = [0u8; 4096];
        let mut header_end = None;
        while header_end.is_none() {
            let n = stream.read(&mut temp).expect("read request headers");
            if n == 0 {
                break;
            }
            buf.extend_from_slice(&temp[..n]);
            header_end = buf.windows(4).position(|w| w == b"\r\n\r\n");
        }
        let hdr_idx = header_end.expect("found CRLFCRLF");
        let headers_str = String::from_utf8_lossy(&buf[..hdr_idx]).to_string();
        let first_line = headers_str.lines().next().unwrap_or("").to_string();
        let content_len = headers_str
            .lines()
            .find_map(|line| {
                let (k, v) = line.split_once(':')?;
                if k.trim().eq_ignore_ascii_case("content-length") {
                    v.trim().parse::<usize>().ok()
                } else {
                    None
                }
            })
            .unwrap_or(0);
        let body_start = hdr_idx + 4;
        while buf.len() < body_start + content_len {
            let n = stream.read(&mut temp).expect("read request body");
            if n == 0 {
                break;
            }
            buf.extend_from_slice(&temp[..n]);
        }
        let body_str =
            String::from_utf8_lossy(&buf[body_start..body_start + content_len]).to_string();
        (first_line, headers_str, body_str)
    }

    #[test]
    fn test_webchannel_four_step_handshake_and_aid_progression() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().expect("local addr");

        let server_thread = std::thread::spawn(move || {
            // Step 1: GET /u/0/webchannel/register?ignore_compass_cookie=1
            {
                let (mut stream, _) = listener.accept().expect("accept step 1");
                let (first_line, headers, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/register?ignore_compass_cookie=1 "),
                    "Step 1 unexpected request line: {first_line}"
                );
                let headers_lower = headers.to_ascii_lowercase();
                assert!(
                    headers_lower.contains("content-type: application/x-protobuf"),
                    "Step 1 missing Content-Type: application/x-protobuf header: {headers}"
                );
                let resp = concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "Set-Cookie: COMPASS=dynamite-ui=csession_abc; Path=/; Domain=chat.google.com; Secure; HttpOnly\r\n",
                    "Content-Length: 0\r\n",
                    "Connection: close\r\n\r\n"
                );
                stream.write_all(resp.as_bytes()).expect("write step 1");
            }

            // Step 2: GET /u/0/webchannel/events?VER=8&RID=<rid>&t=1&zx=<zx>&CVER=22&$req=count%3D1%26ofs%3D0%26req0_data%3D%255B%255D&SID=null
            {
                let (mut stream, _) = listener.accept().expect("accept step 2");
                let (first_line, headers, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/events?"),
                    "Step 2 unexpected request line: {first_line}"
                );
                for needle in [
                    "VER=8",
                    "RID=",
                    "t=1",
                    "zx=",
                    "CVER=22",
                    "%24req=count%3D1%26ofs%3D0%26req0_data%3D%255B%255D",
                    "SID=null",
                ] {
                    assert!(
                        first_line.contains(needle),
                        "Step 2 query missing `{needle}`: {first_line}"
                    );
                }
                let headers_lower = headers.to_ascii_lowercase();
                assert!(
                    headers_lower.contains("referer: https://chat.google.com/"),
                    "Step 2 missing referer header: {headers}"
                );
                assert!(
                    headers.contains("COMPASS=dynamite-ui=csession_abc"),
                    "Step 2 must send rotated COMPASS cookie from Step 1: {headers}"
                );
                let resp = concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "X-HTTP-Initial-Response: [[0,[\"c\",\"sid_123\",\"\",8,12]]]\r\n",
                    "Content-Length: 0\r\n",
                    "Connection: close\r\n\r\n"
                );
                stream.write_all(resp.as_bytes()).expect("write step 2");
            }

            // Step 3a: Ack GET /u/0/webchannel/events?VER=8&RID=rpc&SID=sid_123&AID=0&CI=0&TYPE=xmlhttp&zx=<zx>&t=1
            {
                let (mut stream, _) = listener.accept().expect("accept step 3a ack GET");
                let (first_line, _, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/events?"),
                    "Step 3a unexpected request line: {first_line}"
                );
                for needle in [
                    "VER=8",
                    "RID=rpc",
                    "SID=sid_123",
                    "AID=0",
                    "CI=0",
                    "TYPE=xmlhttp",
                    "zx=",
                    "t=1",
                ] {
                    assert!(
                        first_line.contains(needle),
                        "Step 3a ack GET missing `{needle}` in `{first_line}`"
                    );
                }
                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                stream.write_all(resp.as_bytes()).expect("write step 3a");
            }

            // Step 3b: Initial POST /u/0/webchannel/events?VER=8&RID=<rid>&t=1&SID=sid_123&AID=0 with count=1&ofs=0&req0_data=<json>
            {
                let (mut stream, _) = listener.accept().expect("accept step 3b ping POST");
                let (first_line, _, body) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("POST /u/0/webchannel/events?"),
                    "Step 3b unexpected request line: {first_line}"
                );
                for needle in ["VER=8", "RID=", "t=1", "SID=sid_123", "AID=0"] {
                    assert!(
                        first_line.contains(needle),
                        "Step 3b POST missing `{needle}` in `{first_line}`"
                    );
                }
                assert!(
                    body.starts_with("count=1&ofs=0&req0_data=%5B"),
                    "Step 3b form body req0_data must be URL-encoded: {body}"
                );
                let form_pairs: std::collections::HashMap<String, String> =
                    url::form_urlencoded::parse(body.as_bytes())
                        .into_owned()
                        .collect();
                assert_eq!(form_pairs.get("count").map(String::as_str), Some("1"));
                assert_eq!(form_pairs.get("ofs").map(String::as_str), Some("0"));
                let json_part = form_pairs.get("req0_data").expect("req0_data present");
                let val: Value = serde_json::from_str(json_part).expect("valid PingEvent pblite");
                let desc = DESCRIPTOR_POOL
                    .get_message_by_name("googlechat.StreamEventsRequest")
                    .expect("StreamEventsRequest descriptor");
                let req_proto: pb::StreamEventsRequest =
                    decode_pblite(&desc, &val).expect("decode StreamEventsRequest");
                let ping = req_proto.ping_event.expect("PingEvent present");
                assert_eq!(ping.state, Some(pb::ping_event::State::Active as i32));
                assert_eq!(
                    ping.application_focus_state,
                    Some(pb::ping_event::ApplicationFocusState::FocusStateForeground as i32)
                );
                assert_eq!(
                    ping.client_interactive_state,
                    Some(pb::ping_event::ClientInteractiveState::Interactive as i32)
                );
                assert_eq!(ping.client_notifications_enabled, Some(true));

                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                stream.write_all(resp.as_bytes()).expect("write step 3b");
            }

            // Step 4: Long-poll GET /u/0/webchannel/events?VER=8&RID=rpc&t=1&zx=<zx>&CI=0&TYPE=xmlhttp&AID=0&SID=sid_123
            {
                let (mut stream, _) = listener.accept().expect("accept step 4 GET");
                let (first_line, headers, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/events?"),
                    "Step 4 unexpected request line: {first_line}"
                );
                for needle in [
                    "VER=8",
                    "RID=rpc",
                    "t=1",
                    "zx=",
                    "CI=0",
                    "TYPE=xmlhttp",
                    "AID=0",
                    "SID=sid_123",
                ] {
                    assert!(
                        first_line.contains(needle),
                        "Step 4 missing `{needle}` in `{first_line}`"
                    );
                }
                assert!(
                    headers
                        .to_ascii_lowercase()
                        .contains("referer: https://chat.google.com/"),
                    "Step 4 missing referer header: {headers}"
                );

                // Chunk 1: [[1,["noop"]]]
                let chunk1 = "[[1,[\"noop\"]]]";
                // Chunk 2: [[2,[<StreamEventsResponse with Event>]]]
                let event_chunk = json!([[
                    2,
                    [[[
                        [["space-handshake"]],
                        null,
                        6,
                        [
                            null,
                            null,
                            null,
                            null,
                            null,
                            [[
                                null,
                                null,
                                "1711234567000099",
                                null,
                                null,
                                null,
                                null,
                                null,
                                null,
                                "Hello from WebChannel"
                            ]],
                            null,
                            null,
                            null,
                            null,
                            null,
                            6
                        ]
                    ]]]
                ]])
                .to_string();

                let body = format!(
                    "{}\n{}{}\n{}",
                    chunk1.encode_utf16().count(),
                    chunk1,
                    event_chunk.encode_utf16().count(),
                    event_chunk
                );
                let resp = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                stream.write_all(resp.as_bytes()).expect("write step 4");
            }
        });

        let guard = NetGuard::allow_loopback_for_test();
        let http = guard.build_http_client().expect("build http client");
        let jar = DomainCookieJar::from_scoped_cookies(vec![
            ScopedCookie {
                name: "COMPASS".into(),
                value: "c1".into(),
                domain: "chat.google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "OSID".into(),
                value: "o1".into(),
                domain: "chat.google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "SID".into(),
                value: "s1".into(),
                domain: ".google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "HSID".into(),
                value: "h1".into(),
                domain: ".google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "SSID".into(),
                value: "ss1".into(),
                domain: ".google.com".into(),
                path: "/".into(),
            },
        ])
        .expect("valid cookies")
        .with_loopback_for_test(true);

        let base_url = Url::parse(&format!("http://{addr}/")).expect("base url");
        let xsrf = Arc::new(XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            "Mozilla/5.0".to_string(),
            guard.clone(),
        ));
        let wc = WebChannelClient::new(
            http,
            jar.clone(),
            xsrf,
            guard,
            "Mozilla/5.0".to_string(),
            base_url,
        );

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");
        let events = rt
            .block_on(wc.handshake_and_poll_once(|_| {}))
            .expect("handshake and poll succeeded");

        server_thread.join().expect("server thread finished");
        assert_eq!(wc.aid(), 2, "AID must update to 2 after chunk [[2,[...]]]");
        assert_eq!(events.len(), 1);
        assert!(
            jar.to_cookie_map_json()
                .contains("\"COMPASS\":\"dynamite-ui=csession_abc\""),
            "rotated COMPASS must be absorbed into shared DomainCookieJar"
        );
    }

    #[test]
    fn test_webchannel_register_without_compass_cookie_fails_closed() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().expect("local addr");

        let server_thread = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept step 1");
            let _ = read_http_request(&mut stream);
            // Respond 200 OK without Set-Cookie: COMPASS=...
            let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
            stream.write_all(resp.as_bytes()).expect("write step 1");
        });

        let guard = NetGuard::allow_loopback_for_test();
        let http = guard.build_http_client().expect("build http client");
        let jar = DomainCookieJar::from_scoped_cookies(vec![
            ScopedCookie {
                name: "COMPASS".into(),
                value: "c1".into(),
                domain: "chat.google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "OSID".into(),
                value: "o1".into(),
                domain: "chat.google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "SID".into(),
                value: "s1".into(),
                domain: ".google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "HSID".into(),
                value: "h1".into(),
                domain: ".google.com".into(),
                path: "/".into(),
            },
            ScopedCookie {
                name: "SSID".into(),
                value: "ss1".into(),
                domain: ".google.com".into(),
                path: "/".into(),
            },
        ])
        .expect("valid cookies")
        .with_loopback_for_test(true);

        let base_url = Url::parse(&format!("http://{addr}/")).expect("base url");
        let xsrf = Arc::new(XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            "Mozilla/5.0".to_string(),
            guard.clone(),
        ));
        let wc = WebChannelClient::new(http, jar, xsrf, guard, "Mozilla/5.0".to_string(), base_url);

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");
        let err = rt.block_on(wc.step1_register()).expect_err(
            "register without COMPASS Set-Cookie must fail closed (no gsession_default fallback)",
        );
        server_thread.join().expect("server thread finished");
        assert!(
            matches!(err, GChatError::Protocol(_)),
            "expected GChatError::Protocol, got: {err:?}"
        );
    }

    crate::edition2021! {
    #[test]
    fn test_webchannel_reconnect_resets_aid_and_ofs() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().expect("local addr");
        let clock = Arc::new(ManualChannelClock::new(0.2));
        let (c2_done_tx, c2_done_rx) = tokio::sync::oneshot::channel::<()>();

        let server_thread = std::thread::spawn(move || {
            // Connection 1: register -> bind SID -> ack GET -> ping POST (ofs=0, AID=0) -> GET (AID=0) -> emit AID=5, then 400 Unknown SID on rotation
            {
                let (mut s, _) = listener.accept().expect("c1 step1");
                let _ = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nSet-Cookie: COMPASS=dynamite-ui=gs1; Path=/; Domain=chat.google.com\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step2");
                let _ = read_http_request(&mut s);
                let resp = "HTTP/1.1 200 OK\r\nX-HTTP-Initial-Response: [[0,[\"c\",\"sid_c1\",\"\",8,12]]]\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                s.write_all(resp.as_bytes()).unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step3a ack GET");
                let _ = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step3b ping POST");
                let (first_line, _, body) = read_http_request(&mut s);
                assert!(first_line.contains("AID=0"), "c1 ping expected AID=0, got {first_line}");
                assert!(body.starts_with("count=1&ofs=0&req0_data="), "c1 ping expected ofs=0, got {body}");
                s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step4 GET #1");
                let (first_line, _, _) = read_http_request(&mut s);
                assert!(first_line.contains("AID=0"), "c1 GET #1 expected AID=0, got {first_line}");
                let chunk = "[[5,[\"noop\"]]]";
                let body = format!("{}\n{}", chunk.encode_utf16().count(), chunk);
                let resp = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                s.write_all(resp.as_bytes()).unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step4 GET #2 drops with 400");
                let (first_line, _, _) = read_http_request(&mut s);
                assert!(first_line.contains("AID=5"), "c1 GET #2 rotation expected AID=5, got {first_line}");
                s.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nConnection: close\r\n\r\nUnknown SID").unwrap();
            }

            // Connection 2 (after reconnect): register -> bind SID -> ack GET -> ping MUST have AID=0 & ofs=0 -> GET MUST have AID=0
            {
                let (mut s, _) = listener.accept().expect("c2 step1");
                let _ = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nSet-Cookie: COMPASS=dynamite-ui=gs2; Path=/; Domain=chat.google.com\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c2 step2");
                let _ = read_http_request(&mut s);
                let resp = "HTTP/1.1 200 OK\r\nX-HTTP-Initial-Response: [[0,[\"c\",\"sid_c2\",\"\",8,12]]]\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                s.write_all(resp.as_bytes()).unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c2 step3a ack GET");
                let _ = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
            }
            let (c2_ping_line, _, c2_ping_body) = {
                let (mut s, _) = listener.accept().expect("c2 step3b ping");
                let req = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
                req
            };
            let (c2_get_line, _, _) = {
                let (mut s, _) = listener.accept().expect("c2 step4 GET");
                let req = read_http_request(&mut s);
                let _ = c2_done_tx.send(());
                let chunk = "[[1,[\"noop\"]]]";
                let body = format!("{}\n{}", chunk.encode_utf16().count(), chunk);
                let resp = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                s.write_all(resp.as_bytes()).unwrap();
                req
            };
            (c2_ping_line, c2_ping_body, c2_get_line)
        });

        let guard = NetGuard::allow_loopback_for_test();
        let http = guard.build_http_client().expect("build http client");
        let jar = DomainCookieJar::from_scoped_cookies(vec![
            ScopedCookie { name: "COMPASS".into(), value: "c1".into(), domain: "chat.google.com".into(), path: "/".into() },
            ScopedCookie { name: "OSID".into(), value: "o1".into(), domain: "chat.google.com".into(), path: "/".into() },
            ScopedCookie { name: "SID".into(), value: "s1".into(), domain: ".google.com".into(), path: "/".into() },
            ScopedCookie { name: "HSID".into(), value: "h1".into(), domain: ".google.com".into(), path: "/".into() },
            ScopedCookie { name: "SSID".into(), value: "ss1".into(), domain: ".google.com".into(), path: "/".into() },
        ])
        .expect("valid cookies")
        .with_loopback_for_test(true);

        let base_url = Url::parse(&format!("http://{addr}/")).expect("base url");
        let xsrf = Arc::new(XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            "Mozilla/5.0".to_string(),
            guard.clone(),
        ));
        let wc = Arc::new(WebChannelClient::with_clock(
            http,
            jar,
            xsrf,
            guard,
            "Mozilla/5.0".to_string(),
            base_url,
            clock.clone(),
        ));

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");

        let (c2_ping_line, c2_ping_body, c2_get_line) = rt.block_on(async {
            let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
            let (resync_tx, mut resync_rx) = tokio::sync::mpsc::unbounded_channel();
            let wc_task = tokio::spawn(wc.clone().run_forever(cancel_rx, move |kind, _| {
                if kind == GCHAT_EVENT_KIND_RESYNC {
                    let _ = resync_tx.send(());
                }
            }));

            // Wait until connection 1 drops and enters backoff sleep (1s + 5% jitter = 1050ms) on our injected clock.
            clock.wait_for_sleep_duration(Duration::from_millis(1050)).await;

            // Advance the injected clock past the 1050ms backoff so connection 2 proceeds.
            clock.advance(Duration::from_millis(1050));

            resync_rx.recv().await.expect("expected GCHAT_EVENT_KIND_RESYNC on reconnect");
            c2_done_rx.await.expect("expected c2 step4 GET request");
            let _ = cancel_tx.send(true);
            let _ = wc_task.await;
            server_thread.join().expect("server thread finished")
        });

        assert!(
            c2_ping_line.contains("AID=0"),
            "reconnect step3b ping must reset AID=0, got: {c2_ping_line}"
        );
        assert!(
            c2_ping_body.starts_with("count=1&ofs=0&req0_data="),
            "reconnect step3b ping must reset ofs=0, got: {c2_ping_body}"
        );
        assert!(
            c2_get_line.contains("AID=0"),
            "reconnect step4 GET must reset AID=0, got: {c2_get_line}"
        );
    }

    #[test]
    fn test_webchannel_server_event_90s_watchdog_fires_on_non_frame_trickle() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().expect("local addr");
        let clock = Arc::new(ManualChannelClock::new(0.0));
        let (trickle_tx, trickle_rx) = std::sync::mpsc::channel::<()>();

        let server_thread = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept GET");
            let _ = read_http_request(&mut stream);
            // Send chunked HTTP response headers, then trickle non-frame whitespace every time the test signals.
            let hdrs = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n";
            stream.write_all(hdrs.as_bytes()).expect("write headers");
            stream.flush().unwrap();

            for _ in 0..3 {
                if trickle_rx.recv().is_err() {
                    return;
                }
                // Send a 1-byte HTTP chunk containing "\n" (not a valid WebChannel frame).
                let _ = stream.write_all(b"1\r\n\n\r\n");
                let _ = stream.flush();
            }
            let _ = trickle_rx.recv();
        });

        let guard = NetGuard::allow_loopback_for_test();
        let http = guard.build_http_client().expect("build http client");
        let jar = DomainCookieJar::from_scoped_cookies(vec![
            ScopedCookie { name: "COMPASS".into(), value: "c1".into(), domain: "chat.google.com".into(), path: "/".into() },
            ScopedCookie { name: "OSID".into(), value: "o1".into(), domain: "chat.google.com".into(), path: "/".into() },
            ScopedCookie { name: "SID".into(), value: "s1".into(), domain: ".google.com".into(), path: "/".into() },
            ScopedCookie { name: "HSID".into(), value: "h1".into(), domain: ".google.com".into(), path: "/".into() },
            ScopedCookie { name: "SSID".into(), value: "ss1".into(), domain: ".google.com".into(), path: "/".into() },
        ])
        .expect("valid cookies")
        .with_loopback_for_test(true);

        let base_url = Url::parse(&format!("http://{addr}/")).expect("base url");
        let xsrf = Arc::new(XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            "Mozilla/5.0".to_string(),
            guard.clone(),
        ));
        let wc = Arc::new(WebChannelClient::with_clock(
            http,
            jar,
            xsrf,
            guard,
            "Mozilla/5.0".to_string(),
            base_url,
            clock.clone(),
        ));

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");

        let err = rt.block_on(async {
            let wc_clone = wc.clone();
            let poll_task = tokio::spawn(async move {
                let mut noop = |_: &pb::Event| {};
                wc_clone.step4_poll_events("sid1", &mut noop).await
            });

            // 3 trickles at 25s intervals (25s, 50s, 75s) keep read inactivity < 35s,
            // then advancing to 95s must trigger the 90s server-event watchdog!
            for i in 1..=3 {
                clock.wait_for_sleep_count(i).await;
                clock.advance(Duration::from_secs(25));
                let _ = trickle_tx.send(());
            }
            clock.wait_for_sleep_count(4).await;
            clock.advance(Duration::from_secs(20)); // total elapsed = 95s > 90s SERVER_EVENT_TIMEOUT
            for _ in 0..10 {
                tokio::task::yield_now().await;
            }
            drop(trickle_tx);
            if !poll_task.is_finished() {
                poll_task.abort();
                panic!("90s server-event watchdog failed to fire at 95s when non-frame bytes trickled in");
            }
            let res = poll_task.await.expect("poll_task join");
            res.expect_err("expected 90s server-event watchdog error")
        });

        server_thread.join().expect("server thread finished");
        assert!(
            err.to_string().contains("90s watchdog"),
            "expected 90s server-event watchdog error, got: {err}"
        );
    }

    #[test]
    fn test_webchannel_bind_get_held_open_until_ping_emits_connected_and_event() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().expect("local addr");

        let server_thread = std::thread::spawn(move || {
            // Step 1: GET /u/0/webchannel/register?ignore_compass_cookie=1
            {
                let (mut stream, _) = listener.accept().expect("accept step 1");
                let (first_line, _, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/register?ignore_compass_cookie=1 "),
                    "Step 1 unexpected request line: {first_line}"
                );
                let resp = concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "Set-Cookie: COMPASS=dynamite-ui=csession_bind; Path=/; Domain=chat.google.com; Secure; HttpOnly\r\n",
                    "Content-Length: 0\r\n",
                    "Connection: close\r\n\r\n"
                );
                stream.write_all(resp.as_bytes()).expect("write step 1");
            }

            // Step 2: GET /u/0/webchannel/events?...&SID=null
            // Return 200 with X-HTTP-Initial-Response and hold the body open until Ping POST arrives.
            let (mut bind_stream, _) = listener.accept().expect("accept step 2 bind GET");
            {
                let (first_line, _, _) = read_http_request(&mut bind_stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/events?") && first_line.contains("SID=null"),
                    "Step 2 unexpected request line: {first_line}"
                );
                let hdrs = concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "X-HTTP-Initial-Response: [[0,[\"c\",\"sid_bind_open\",\"\",8,12]]]\r\n",
                    "Transfer-Encoding: chunked\r\n",
                    "Connection: close\r\n\r\n"
                );
                bind_stream
                    .write_all(hdrs.as_bytes())
                    .expect("write step 2 headers");
                bind_stream.flush().expect("flush step 2 headers");
            }

            // Step 3a: Ack GET while bind_stream is still open.
            {
                let (mut ack_stream, _) = listener.accept().expect("accept step 3a ack GET");
                let (first_line, _, _) = read_http_request(&mut ack_stream);
                assert!(
                    first_line.contains("RID=rpc") && first_line.contains("SID=sid_bind_open"),
                    "Step 3a unexpected request line: {first_line}"
                );
                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                ack_stream.write_all(resp.as_bytes()).expect("write step 3a");
            }

            // Step 3b: Ping POST while bind_stream is still open.
            {
                let (mut ping_stream, _) = listener.accept().expect("accept step 3b ping POST");
                let (first_line, _, body) = read_http_request(&mut ping_stream);
                assert!(
                    first_line.starts_with("POST /u/0/webchannel/events?")
                        && first_line.contains("SID=sid_bind_open"),
                    "Step 3b unexpected request line: {first_line}"
                );
                assert!(
                    body.starts_with("count=1&ofs=0&req0_data="),
                    "Step 3b unexpected ping body: {body}"
                );
                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                ping_stream.write_all(resp.as_bytes()).expect("write step 3b");
            }

            // Only after receiving Ping POST, stream one valid chunk carrying an event on bind_stream and close.
            let event_chunk = json!([[
                1,
                [[[
                    [["space-bind-open"]],
                    null,
                    6,
                    [
                        null,
                        null,
                        null,
                        null,
                        null,
                        [[
                            null,
                            null,
                            "1711234567000099",
                            null,
                            null,
                            null,
                            null,
                            null,
                            null,
                            "Hello from held-open bind stream"
                        ]],
                        null,
                        null,
                        null,
                        null,
                        null,
                        6
                    ]
                ]]]
            ]])
            .to_string();
            let frame = format!("{}\n{}", event_chunk.encode_utf16().count(), event_chunk);
            let http_chunk = format!("{:x}\r\n{}\r\n0\r\n\r\n", frame.len(), frame);
            bind_stream
                .write_all(http_chunk.as_bytes())
                .expect("write bind stream event chunk");
            bind_stream.flush().expect("flush bind stream event chunk");
            drop(bind_stream);
        });

        let guard = NetGuard::allow_loopback_for_test();
        let http = guard.build_http_client().expect("build http client");
        let jar = DomainCookieJar::from_scoped_cookies(vec![
            ScopedCookie { name: "COMPASS".into(), value: "c1".into(), domain: "chat.google.com".into(), path: "/".into() },
            ScopedCookie { name: "OSID".into(), value: "o1".into(), domain: "chat.google.com".into(), path: "/".into() },
            ScopedCookie { name: "SID".into(), value: "s1".into(), domain: ".google.com".into(), path: "/".into() },
            ScopedCookie { name: "HSID".into(), value: "h1".into(), domain: ".google.com".into(), path: "/".into() },
            ScopedCookie { name: "SSID".into(), value: "ss1".into(), domain: ".google.com".into(), path: "/".into() },
        ])
        .expect("valid cookies")
        .with_loopback_for_test(true);

        let base_url = Url::parse(&format!("http://{addr}/")).expect("base url");
        let xsrf = Arc::new(XsrfTokenManager::new(
            http.clone(),
            jar.clone(),
            base_url.clone(),
            "Mozilla/5.0".to_string(),
            guard.clone(),
        ));
        let wc = Arc::new(WebChannelClient::new(
            http,
            jar,
            xsrf,
            guard,
            "Mozilla/5.0".to_string(),
            base_url,
        ));

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("tokio runtime");

        let (got_connected, got_event) = rt.block_on(async {
            let (cancel_tx, cancel_rx) = tokio::sync::watch::channel(false);
            let (ev_tx, mut ev_rx) = tokio::sync::mpsc::unbounded_channel::<(i32, Vec<u8>)>();
            let wc_task = tokio::spawn(wc.clone().run_forever(cancel_rx, move |kind, payload| {
                let _ = ev_tx.send((kind, payload.to_vec()));
            }));

            let res = tokio::time::timeout(Duration::from_secs(5), async {
                let mut saw_connected = false;
                let mut decoded_event: Option<pb::Event> = None;
                while let Some((kind, payload)) = ev_rx.recv().await {
                    if kind == GCHAT_EVENT_KIND_CONNECTED {
                        saw_connected = true;
                    } else if kind == GCHAT_EVENT_KIND_EVENT_PROTO {
                        decoded_event = Some(
                            pb::Event::decode(payload.as_slice()).expect("decode emitted pb::Event"),
                        );
                    }
                    if saw_connected && decoded_event.is_some() {
                        break;
                    }
                }
                (saw_connected, decoded_event)
            })
            .await;

            let _ = cancel_tx.send(true);
            let _ = wc_task.await;
            res.expect("timed out waiting 5s for CONNECTED and event on held-open bind response")
        });

        server_thread.join().expect("server thread finished");
        assert!(got_connected, "expected GCHAT_EVENT_KIND_CONNECTED");
        let ev = got_event.expect("expected GCHAT_EVENT_KIND_EVENT_PROTO");
        assert_eq!(wc.aid(), 1, "AID must advance to 1 from bind stream chunk");
        let msg_text = ev
            .body
            .and_then(|b| match b.r#type {
                Some(pb::event::event_body::Type::MessagePosted(mp)) => mp.message,
                _ => None,
            })
            .and_then(|m| m.text_body);
        assert_eq!(msg_text.as_deref(), Some("Hello from held-open bind stream"));
    }
    }

    #[test]
    fn test_encode_req0_form_body_url_encodes_pblite_json() {
        let body = encode_req0_form_body(3, r#"[1,"a&b=c"]"#);
        assert_eq!(body, "count=1&ofs=3&req0_data=%5B1%2C%22a%26b%3Dc%22%5D");
    }

    #[test]
    fn test_format_stream_error_message_never_echoes_sid_cookie_token_url_or_body() {
        let sensitive_payload = "https://chat.google.com/u/0/webchannel/events?SID=sid_val_999&zx=abc Cookie: COMPASS=dynamite-ui=compass_val; OSID=osid_val xsrf=xsrf_val body=resp_body_val"; // gitleaks:allow
        let cases = [
            (
                "step1_register",
                GChatError::HttpStatus(503, sensitive_payload.to_string()),
                "step1_register: http_status:503",
            ),
            (
                "step2_bind_sid",
                GChatError::Network(sensitive_payload.to_string()),
                "step2_bind_sid: network",
            ),
            (
                "step3_ack_and_ping",
                GChatError::Protocol(sensitive_payload.to_string()),
                "step3_ack_and_ping: protocol",
            ),
            (
                "step2_bind_poll",
                GChatError::AuthExpired(sensitive_payload.to_string()),
                "step2_bind_poll: auth_expired",
            ),
            (
                "step4_poll_events",
                GChatError::HttpStatus(400, sensitive_payload.to_string()),
                "step4_poll_events: http_status:400",
            ),
            (
                sensitive_payload,
                GChatError::Internal(sensitive_payload.to_string()),
                "stream: internal",
            ),
        ];

        for (step, err, expected) in cases {
            let formatted = format_stream_error_message(step, &err);
            assert_eq!(formatted, expected);
            for forbidden in [
                "https://",
                "chat.google.com",
                "SID=",
                "sid_val_999",
                "COMPASS",
                "compass_val",
                "OSID",
                "osid_val",
                "xsrf_val",
                "resp_body_val",
            ] {
                assert!(
                    !formatted.contains(forbidden),
                    "stream error summary leaked `{forbidden}` in `{formatted}`"
                );
            }
        }
    }
}
