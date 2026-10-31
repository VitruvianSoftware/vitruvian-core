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

        /// Executes the 4-step WebChannel handshake and drains one long-poll response stream:
        /// Step 1: `POST /u/0/webchannel/register` with `X-Goog-Encode-Response-If-Executable: base64`
        /// Step 2: `POST /u/0/webchannel/events_encoded?...&RID=<rid>&CVER=22&X-HTTP-Session-Id=gsessionid`
        /// Step 3: `GET /u/0/webchannel/events_encoded?gsessionid=...&SID=<sid>&RID=rpc&AID=<aid>&CI=0&TYPE=xmlhttp`
        /// Step 4: Initial `POST` with `count=1&ofs=0&req0___data__=<json>` carrying `PingEvent`
        pub async fn handshake_and_poll_once<F>(
            &self,
            mut on_event: F,
        ) -> Result<Vec<pb::Event>, GChatError>
        where
            F: FnMut(&pb::Event),
        {
            self.aid.store(0, Ordering::SeqCst);
            self.ofs.store(0, Ordering::SeqCst);

            // Step 1: POST /u/0/webchannel/register
            let gsessionid = self.step1_register().await?;

            // Step 2: POST /u/0/webchannel/events_encoded?...&RID=<rid>&CVER=22&X-HTTP-Session-Id=gsessionid
            let sid = self.step2_bind_sid(&gsessionid).await?;

            // Step 4: Send initial active PingEvent at ofs=0
            self.step4_send_ping(&gsessionid, &sid).await?;

            // Step 3: GET /u/0/webchannel/events_encoded?gsessionid=...&SID=<sid>&RID=rpc&AID=0&CI=0&TYPE=xmlhttp
            let events = self.step3_poll_events(&gsessionid, &sid, &mut on_event).await?;

            Ok(events)
        }

        pub async fn step1_register(&self) -> Result<String, GChatError> {
            // Reset AID and ofs on every fresh session registration (matching ref/pkg/gchatmeow/channel.go:205-210).
            self.aid.store(0, Ordering::SeqCst);
            self.ofs.store(0, Ordering::SeqCst);

            let url = self
                .base_url
                .join("/u/0/webchannel/register")
                .map_err(|e| GChatError::Internal(format!("invalid register URL: {e}")))?;
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .post(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(CONTENT_TYPE, "application/x-protobuf")
                .header("X-Goog-Encode-Response-If-Executable", "base64");
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

            let hdr_gsession = resp
                .headers()
                .get("X-HTTP-Session-Id")
                .or_else(|| resp.headers().get("x-http-session-id"))
                .and_then(|v| v.to_str().ok())
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());

            let body_bytes = resp
                .bytes()
                .await
                .map_err(|e| GChatError::Network(format!("register body read failed: {e}")))?;
            let body_text = String::from_utf8_lossy(&body_bytes).trim().to_string();

            if let Some(gs) = hdr_gsession {
                return Ok(gs);
            }
            for sc in &set_cookies {
                if let Some(idx) = sc.find("dynamite-ui=") {
                    let rest = &sc[idx + "dynamite-ui=".len()..];
                    let token = rest.split(';').next().unwrap_or("").trim();
                    if !token.is_empty() {
                        return Ok(token.to_string());
                    }
                }
            }
            if !body_text.is_empty() {
                return Ok(body_text);
            }
            Ok("gsession_default".to_string())
        }

        pub async fn step2_bind_sid(&self, gsessionid: &str) -> Result<String, GChatError> {
            let rid = self.next_rid();
            let mut url = self
                .base_url
                .join("/u/0/webchannel/events_encoded")
                .map_err(|e| GChatError::Internal(format!("invalid events_encoded URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("VER", "8");
                qp.append_pair("gsessionid", gsessionid);
                qp.append_pair("RID", &rid.to_string());
                qp.append_pair("CVER", "22");
                qp.append_pair("X-HTTP-Session-Id", gsessionid);
                qp.append_pair("t", "1");
            }
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .post(url.clone())
                .header(USER_AGENT, &self.user_agent)
                .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
                .header("X-HTTP-Session-Id", gsessionid)
                .body("count=0");
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

            let initial_hdr = resp
                .headers()
                .get("X-HTTP-Initial-Response")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_owned());

            let body_bytes = resp
                .bytes()
                .await
                .map_err(|e| GChatError::Network(format!("SID bind body read failed: {e}")))?;

            if let Some(hdr) = initial_hdr {
                if let Some(sid) = parse_sid_from_json(&hdr) {
                    return Ok(sid);
                }
            }

            let body_str = String::from_utf8_lossy(&body_bytes);
            if let Some(sid) = parse_sid_from_json(&body_str) {
                return Ok(sid);
            }

            let mut parser = ChunkParser::new();
            for frame in parser.push_bytes(&body_bytes)? {
                if let Some(sid) = parse_sid_from_json(&frame) {
                    return Ok(sid);
                }
            }

            Err(GChatError::Protocol(
                "missing SID in WebChannel initial response".to_string(),
            ))
        }

        pub async fn step4_send_ping(
            &self,
            gsessionid: &str,
            sid: &str,
        ) -> Result<(), GChatError> {
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
                .join("/u/0/webchannel/events_encoded")
                .map_err(|e| GChatError::Internal(format!("invalid events_encoded URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("VER", "8");
                qp.append_pair("gsessionid", gsessionid);
                qp.append_pair("SID", sid);
                qp.append_pair("RID", &rid.to_string());
                qp.append_pair("AID", &aid.to_string());
                qp.append_pair("t", "1");
            }
            self.guard.validate_url(&url, false).await?;

            let form_body = format!("count=1&ofs={ofs}&req0___data__={json_str}");
            let mut req = self
                .http
                .post(url.clone())
                .header(USER_AGENT, &self.user_agent)
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

        pub async fn step3_poll_events<F>(
            &self,
            gsessionid: &str,
            sid: &str,
            on_event: &mut F,
        ) -> Result<Vec<pb::Event>, GChatError>
        where
            F: FnMut(&pb::Event),
        {
            let aid = self.aid();
            let mut url = self
                .base_url
                .join("/u/0/webchannel/events_encoded")
                .map_err(|e| GChatError::Internal(format!("invalid events_encoded URL: {e}")))?;
            {
                let mut qp = url.query_pairs_mut();
                qp.append_pair("gsessionid", gsessionid);
                qp.append_pair("SID", sid);
                qp.append_pair("RID", "rpc");
                qp.append_pair("AID", &aid.to_string());
                qp.append_pair("CI", "0");
                qp.append_pair("TYPE", "xmlhttp");
            }
            self.guard.validate_url(&url, false).await?;

            let mut req = self
                .http
                .get(url.clone())
                .header(USER_AGENT, &self.user_agent);
            if let Some(cookie_hdr) = self.jar.cookie_header_for_request(&url) {
                req = req.header(COOKIE, cookie_hdr);
            }

            let mut resp = req
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

        fn process_chunk_frame(&self, frame: &str) -> Result<(Vec<pb::Event>, bool), GChatError> {
            let outer: Value = serde_json::from_str(frame).map_err(|e| {
                GChatError::Protocol(format!("invalid WebChannel chunk JSON: {e}"))
            })?;
            let Some(entries) = outer.as_array() else {
                return Ok((Vec::new(), false));
            };

            let wc_desc = DESCRIPTOR_POOL
                .get_message_by_name("googlechat.WebChannelEvent")
                .ok_or_else(|| {
                    GChatError::Internal("missing WebChannelEvent descriptor".to_string())
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
                            if let Ok(wc) = decode_pblite::<pb::WebChannelEvent>(&wc_desc, first) {
                                if let Some(ev) = wc.event {
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

                let gsession_res = tokio::select! {
                    _ = cancel_rx.changed() => break,
                    r = self.step1_register() => r,
                };
                let gsessionid = match gsession_res {
                    Ok(id) => id,
                    Err(e) => {
                        if !self.handle_stream_error(e, &mut attempt, &mut cancel_rx, &mut emit).await {
                            break;
                        }
                        continue;
                    }
                };

                let sid_res = tokio::select! {
                    _ = cancel_rx.changed() => break,
                    r = self.step2_bind_sid(&gsessionid) => r,
                };
                let sid = match sid_res {
                    Ok(s) => s,
                    Err(e) => {
                        if !self.handle_stream_error(e, &mut attempt, &mut cancel_rx, &mut emit).await {
                            break;
                        }
                        continue;
                    }
                };

                if let Err(e) = self.step4_send_ping(&gsessionid, &sid).await {
                    if !self.handle_stream_error(e, &mut attempt, &mut cancel_rx, &mut emit).await {
                        break;
                    }
                    continue;
                }

                emit(GCHAT_EVENT_KIND_CONNECTED, &[]);
                if attempt > 0 {
                    emit(GCHAT_EVENT_KIND_RESYNC, &[]);
                }
                attempt = 0;

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
                        r = self.step3_poll_events(&gsessionid, &sid, &mut on_ev) => r,
                    };
                    drop(on_ev);
                    match poll_res {
                        Ok(_) => {
                            // Normal long-poll EOF rotation: preserve AID and re-open GET.
                            continue;
                        }
                        Err(e) => {
                            if !self.handle_stream_error(e, &mut attempt, &mut cancel_rx, &mut emit).await {
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
            // Step 1: POST /u/0/webchannel/register
            {
                let (mut stream, _) = listener.accept().expect("accept step 1");
                let (first_line, headers, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("POST /u/0/webchannel/register "),
                    "Step 1 unexpected request line: {first_line}"
                );
                let headers_lower = headers.to_ascii_lowercase();
                assert!(
                    headers_lower.contains("x-goog-encode-response-if-executable: base64"),
                    "Step 1 missing X-Goog-Encode-Response-If-Executable header: {headers}"
                );
                let resp = concat!(
                    "HTTP/1.1 200 OK\r\n",
                    "X-HTTP-Session-Id: gsession_abc\r\n",
                    "Content-Length: 12\r\n",
                    "Connection: close\r\n\r\n",
                    "gsession_abc"
                );
                stream.write_all(resp.as_bytes()).expect("write step 1");
            }

            // Step 2: POST /u/0/webchannel/events_encoded?...&RID=<rid>&CVER=22&X-HTTP-Session-Id=gsessionid
            {
                let (mut stream, _) = listener.accept().expect("accept step 2");
                let (first_line, _, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("POST /u/0/webchannel/events_encoded?"),
                    "Step 2 unexpected request line: {first_line}"
                );
                assert!(
                    first_line.contains("RID=")
                        && first_line.contains("CVER=22")
                        && first_line.contains("X-HTTP-Session-Id=gsession_abc"),
                    "Step 2 query missing required params: {first_line}"
                );
                let sid_frame = "[[0,[\"c\",\"sid_123\",\"\",8]]]";
                let body = format!("{}\n{}", sid_frame.encode_utf16().count(), sid_frame);
                let resp = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                );
                stream.write_all(resp.as_bytes()).expect("write step 2");
            }

            // Step 4: Initial POST with count=1&ofs=0&req0___data__=<json> carrying PingEvent
            {
                let (mut stream, _) = listener.accept().expect("accept step 4 ping");
                let (first_line, _, body) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("POST /u/0/webchannel/events_encoded?"),
                    "Step 4 unexpected request line: {first_line}"
                );
                assert!(
                    body.starts_with("count=1&ofs=0&req0___data__="),
                    "Step 4 unexpected form body: {body}"
                );
                let json_part = body.trim_start_matches("count=1&ofs=0&req0___data__=");
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
                stream.write_all(resp.as_bytes()).expect("write step 4");
            }

            // Step 3: GET /u/0/webchannel/events_encoded?gsessionid=...&SID=sid_123&RID=rpc&AID=0&CI=0&TYPE=xmlhttp
            {
                let (mut stream, _) = listener.accept().expect("accept step 3 GET");
                let (first_line, _, _) = read_http_request(&mut stream);
                assert!(
                    first_line.starts_with("GET /u/0/webchannel/events_encoded?"),
                    "Step 3 unexpected request line: {first_line}"
                );
                for needle in [
                    "gsessionid=gsession_abc",
                    "SID=sid_123",
                    "RID=rpc",
                    "AID=0",
                    "CI=0",
                    "TYPE=xmlhttp",
                ] {
                    assert!(
                        first_line.contains(needle),
                        "Step 3 missing `{needle}` in `{first_line}`"
                    );
                }

                // Chunk 1: [[1,["noop"]]]
                let chunk1 = "[[1,[\"noop\"]]]";
                // Chunk 2: [[2,[<WebChannelEvent with Event>]]]
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
                stream.write_all(resp.as_bytes()).expect("write step 3");
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
        let wc = WebChannelClient::new(http, jar, xsrf, guard, "Mozilla/5.0".to_string(), base_url);

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
    }

    crate::edition2021! {
    #[test]
    fn test_webchannel_reconnect_resets_aid_and_ofs() {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind loopback");
        let addr = listener.local_addr().expect("local addr");
        let clock = Arc::new(ManualChannelClock::new(0.2));
        let (c2_done_tx, c2_done_rx) = tokio::sync::oneshot::channel::<()>();

        let server_thread = std::thread::spawn(move || {
            // Connection 1: register -> bind SID -> ping (ofs=0, AID=0) -> GET (AID=0) -> emit AID=5, then 400 Unknown SID on rotation
            {
                let (mut s, _) = listener.accept().expect("c1 step1");
                let _ = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nX-HTTP-Session-Id: gs1\r\nContent-Length: 3\r\nConnection: close\r\n\r\ngs1").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step2");
                let _ = read_http_request(&mut s);
                let sid_frame = "[[0,[\"c\",\"sid_c1\",\"\",8]]]";
                let body = format!("{}\n{}", sid_frame.encode_utf16().count(), sid_frame);
                let resp = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                s.write_all(resp.as_bytes()).unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step4 ping");
                let (first_line, _, body) = read_http_request(&mut s);
                assert!(first_line.contains("AID=0"), "c1 ping expected AID=0, got {first_line}");
                assert!(body.starts_with("count=1&ofs=0&"), "c1 ping expected ofs=0, got {body}");
                s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step3 GET #1");
                let (first_line, _, _) = read_http_request(&mut s);
                assert!(first_line.contains("AID=0"), "c1 GET #1 expected AID=0, got {first_line}");
                let chunk = "[[5,[\"noop\"]]]";
                let body = format!("{}\n{}", chunk.encode_utf16().count(), chunk);
                let resp = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                s.write_all(resp.as_bytes()).unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c1 step3 GET #2 drops with 400");
                let (first_line, _, _) = read_http_request(&mut s);
                assert!(first_line.contains("AID=5"), "c1 GET #2 rotation expected AID=5, got {first_line}");
                s.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nConnection: close\r\n\r\nUnknown SID").unwrap();
            }

            // Connection 2 (after reconnect): register -> bind SID -> ping MUST have AID=0 & ofs=0 -> GET MUST have AID=0
            {
                let (mut s, _) = listener.accept().expect("c2 step1");
                let _ = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nX-HTTP-Session-Id: gs2\r\nContent-Length: 3\r\nConnection: close\r\n\r\ngs2").unwrap();
            }
            {
                let (mut s, _) = listener.accept().expect("c2 step2");
                let _ = read_http_request(&mut s);
                let sid_frame = "[[0,[\"c\",\"sid_c2\",\"\",8]]]";
                let body = format!("{}\n{}", sid_frame.encode_utf16().count(), sid_frame);
                let resp = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                s.write_all(resp.as_bytes()).unwrap();
            }
            let (c2_ping_line, _, c2_ping_body) = {
                let (mut s, _) = listener.accept().expect("c2 step4 ping");
                let req = read_http_request(&mut s);
                s.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").unwrap();
                req
            };
            let (c2_get_line, _, _) = {
                let (mut s, _) = listener.accept().expect("c2 step3 GET");
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
            c2_done_rx.await.expect("expected c2 step3 GET request");
            let _ = cancel_tx.send(true);
            let _ = wc_task.await;
            server_thread.join().expect("server thread finished")
        });

        assert!(
            c2_ping_line.contains("AID=0"),
            "reconnect step4 ping must reset AID=0, got: {c2_ping_line}"
        );
        assert!(
            c2_ping_body.starts_with("count=1&ofs=0&"),
            "reconnect step4 ping must reset ofs=0, got: {c2_ping_body}"
        );
        assert!(
            c2_get_line.contains("AID=0"),
            "reconnect step3 GET must reset AID=0, got: {c2_get_line}"
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
                wc_clone.step3_poll_events("gs1", "sid1", &mut noop).await
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
    }
}
