// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// SPDX-License-Identifier: MIT

//! A small MQTT 5 client over TLS: connect, subscribe, publish, keep alive.
//!
//! python-roborock 7.12.1 talks to the Roborock broker through aiomqtt
//! (`roborock/mqtt/roborock_session.py`): MQTT 5, a 45-second keepalive, QoS
//! 0 subscriptions to `rr/m/o/<u>/<user>/<duid>` and QoS 0 publishes to
//! `rr/m/i/...`. This is that subset and no more. One thread owns the
//! socket; callers queue packets to it, and it delivers incoming PUBLISH
//! payloads to per-topic callbacks. A dropped connection is re-established
//! with backoff and its subscriptions are restored, as the Python session
//! does. A CONNACK or DISCONNECT with reason 135 (not authorized) is fatal:
//! it calls the unauthorized hook and stops reconnecting.

use rustls::pki_types::ServerName;
use std::collections::HashMap;
use std::io::{ErrorKind, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicBool, AtomicU16, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub const KEEPALIVE: Duration = Duration::from_secs(45);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const POLL: Duration = Duration::from_millis(100);
const BACKOFF_MIN: Duration = Duration::from_secs(1);
const BACKOFF_MAX: Duration = Duration::from_secs(60);
/// MQTT 5 reason code "Not authorized"; Roborock also sends it when it is
/// rate limiting a login.
pub const RC_NOT_AUTHORIZED: u8 = 135;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MqttError(pub String);

impl std::fmt::Display for MqttError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for MqttError {}

#[derive(Debug, Clone)]
pub struct Options {
    pub host: String,
    pub port: u16,
    pub tls: bool,
    pub username: String,
    pub password: String,
    pub client_id: String,
}

pub type Callback = Arc<dyn Fn(&[u8]) + Send + Sync>;
pub type UnauthorizedHook = Arc<dyn Fn() + Send + Sync>;

enum Outgoing {
    Packet(Vec<u8>),
    Close,
}

struct Shared {
    listeners: Mutex<HashMap<String, Vec<(u64, Callback)>>>,
    suback: Mutex<HashMap<u16, Sender<bool>>>,
    connected: AtomicBool,
    closed: AtomicBool,
    unauthorized: AtomicBool,
    next_listener: AtomicU64,
    next_packet_id: AtomicU16,
    last_error: Mutex<Option<String>>,
}

pub struct Session {
    shared: Arc<Shared>,
    tx: Sender<Outgoing>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

trait Stream: Read + Write + Send {}
impl<T: Read + Write + Send> Stream for T {}

impl Session {
    /// Connect, waiting for the first CONNACK so a bad login fails here.
    pub fn connect(
        opts: Options,
        on_unauthorized: Option<UnauthorizedHook>,
    ) -> Result<Self, MqttError> {
        let shared = Arc::new(Shared {
            listeners: Mutex::new(HashMap::new()),
            suback: Mutex::new(HashMap::new()),
            connected: AtomicBool::new(false),
            closed: AtomicBool::new(false),
            unauthorized: AtomicBool::new(false),
            next_listener: AtomicU64::new(1),
            next_packet_id: AtomicU16::new(1),
            last_error: Mutex::new(None),
        });
        let first = open(&opts).map_err(|e| {
            if e.0.contains("reason 135") {
                if let Some(hook) = &on_unauthorized {
                    hook();
                }
            }
            e
        })?;
        shared.connected.store(true, Ordering::SeqCst);
        let (tx, rx) = mpsc::channel();
        let worker_shared = shared.clone();
        let handle = thread::Builder::new()
            .name("roborock-mqtt".into())
            .spawn(move || run(opts, first, rx, worker_shared, on_unauthorized))
            .map_err(|e| MqttError(format!("cannot start the MQTT thread: {e}")))?;
        Ok(Self {
            shared,
            tx,
            worker: Mutex::new(Some(handle)),
        })
    }

    pub fn is_connected(&self) -> bool {
        self.shared.connected.load(Ordering::SeqCst)
    }

    pub fn is_unauthorized(&self) -> bool {
        self.shared.unauthorized.load(Ordering::SeqCst)
    }

    fn require_connected(&self) -> Result<(), MqttError> {
        if self.is_connected() {
            return Ok(());
        }
        let why = self
            .shared
            .last_error
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
            .unwrap_or_else(|| "connection lost".into());
        Err(MqttError(format!(
            "Not connected to the Roborock MQTT broker: {why}"
        )))
    }

    /// Subscribe (QoS 0) and wait for the broker to accept it.
    pub fn subscribe(&self, topic: &str, callback: Callback) -> Result<u64, MqttError> {
        self.require_connected()?;
        let id = self.shared.next_listener.fetch_add(1, Ordering::SeqCst);
        let first = {
            let mut listeners = self
                .shared
                .listeners
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            let entry = listeners.entry(topic.to_string()).or_default();
            entry.push((id, callback));
            entry.len() == 1
        };
        if first {
            let pid = next_pid(&self.shared);
            let (ack_tx, ack_rx) = mpsc::channel();
            self.shared
                .suback
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .insert(pid, ack_tx);
            self.send(subscribe_packet(pid, topic))?;
            match ack_rx.recv_timeout(CONNECT_TIMEOUT) {
                Ok(true) => {}
                Ok(false) => {
                    self.unsubscribe(topic, id);
                    return Err(MqttError(format!(
                        "The broker refused the subscription to {}",
                        redact(topic)
                    )));
                }
                Err(_) => {
                    self.unsubscribe(topic, id);
                    return Err(MqttError("Timed out subscribing to the device".into()));
                }
            }
        }
        Ok(id)
    }

    pub fn unsubscribe(&self, topic: &str, id: u64) {
        let mut listeners = self
            .shared
            .listeners
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let Some(entry) = listeners.get_mut(topic) {
            entry.retain(|(i, _)| *i != id);
            if entry.is_empty() {
                listeners.remove(topic);
                let pid = next_pid(&self.shared);
                let _ = self
                    .tx
                    .send(Outgoing::Packet(unsubscribe_packet(pid, topic)));
            }
        }
    }

    /// Publish at QoS 0.
    pub fn publish(&self, topic: &str, payload: &[u8]) -> Result<(), MqttError> {
        self.require_connected()?;
        self.send(publish_packet(topic, payload))
    }

    fn send(&self, packet: Vec<u8>) -> Result<(), MqttError> {
        self.tx
            .send(Outgoing::Packet(packet))
            .map_err(|_| MqttError("The MQTT session is closed".into()))
    }

    pub fn close(&self) {
        self.shared.closed.store(true, Ordering::SeqCst);
        let _ = self.tx.send(Outgoing::Close);
        if let Some(handle) = self.worker.lock().unwrap_or_else(|e| e.into_inner()).take() {
            let _ = handle.join();
        }
        self.shared.connected.store(false, Ordering::SeqCst);
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.close();
    }
}

fn next_pid(shared: &Shared) -> u16 {
    loop {
        let pid = shared.next_packet_id.fetch_add(1, Ordering::SeqCst);
        if pid != 0 {
            return pid;
        }
    }
}

/// Topics carry the account and device ids; keep them out of messages.
fn redact(topic: &str) -> String {
    let parts: Vec<&str> = topic.split('/').collect();
    if parts.len() > 3 {
        format!("{}/***", parts[..3].join("/"))
    } else {
        topic.to_string()
    }
}

fn run(
    opts: Options,
    first: Box<dyn Stream>,
    rx: Receiver<Outgoing>,
    shared: Arc<Shared>,
    on_unauthorized: Option<UnauthorizedHook>,
) {
    let mut stream = Some(first);
    let mut backoff = BACKOFF_MIN;
    loop {
        if shared.closed.load(Ordering::SeqCst) {
            break;
        }
        let Some(mut conn) = stream.take() else {
            // Reconnect, then restore every subscription.
            if wait_or_closed(&rx, backoff) {
                break;
            }
            match open(&opts) {
                Ok(mut conn) => {
                    let topics: Vec<String> = shared
                        .listeners
                        .lock()
                        .unwrap_or_else(|e| e.into_inner())
                        .keys()
                        .cloned()
                        .collect();
                    let mut ok = true;
                    for topic in topics {
                        let pid = next_pid(&shared);
                        if conn.write_all(&subscribe_packet(pid, &topic)).is_err() {
                            ok = false;
                            break;
                        }
                    }
                    if ok {
                        backoff = BACKOFF_MIN;
                        shared.connected.store(true, Ordering::SeqCst);
                        stream = Some(conn);
                    }
                }
                Err(e) => {
                    record(&shared, &e.0);
                    if e.0.contains("reason 135") {
                        shared.unauthorized.store(true, Ordering::SeqCst);
                        if let Some(hook) = &on_unauthorized {
                            hook();
                        }
                        break;
                    }
                    backoff = (backoff.mul_f32(1.5)).min(BACKOFF_MAX);
                }
            }
            continue;
        };
        match serve(&mut conn, &rx, &shared) {
            Served::Closed => {
                let _ = conn.write_all(&[0xE0, 0x00]);
                break;
            }
            Served::Lost(why) => {
                shared.connected.store(false, Ordering::SeqCst);
                record(&shared, &why);
                if why.contains("reason 135") {
                    shared.unauthorized.store(true, Ordering::SeqCst);
                    if let Some(hook) = &on_unauthorized {
                        hook();
                    }
                    break;
                }
            }
        }
    }
    shared.connected.store(false, Ordering::SeqCst);
}

fn record(shared: &Shared, why: &str) {
    *shared.last_error.lock().unwrap_or_else(|e| e.into_inner()) = Some(why.to_string());
}

/// Sleep for `d` unless a Close arrives first. Packets queued while
/// disconnected are dropped: their callers time out, as they would in Python.
fn wait_or_closed(rx: &Receiver<Outgoing>, d: Duration) -> bool {
    let deadline = Instant::now() + d;
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return false;
        }
        match rx.recv_timeout(left) {
            Ok(Outgoing::Close) | Err(RecvTimeoutError::Disconnected) => return true,
            Ok(Outgoing::Packet(_)) => {}
            Err(RecvTimeoutError::Timeout) => return false,
        }
    }
}

enum Served {
    Closed,
    Lost(String),
}

fn serve(conn: &mut Box<dyn Stream>, rx: &Receiver<Outgoing>, shared: &Shared) -> Served {
    let mut buf = Vec::<u8>::new();
    let mut chunk = [0u8; 16 * 1024];
    let mut last_sent = Instant::now();
    let mut ping_sent: Option<Instant> = None;
    loop {
        // Outgoing first, so a request is never stuck behind a quiet socket.
        loop {
            match rx.try_recv() {
                Ok(Outgoing::Packet(p)) => {
                    if let Err(e) = conn.write_all(&p).and_then(|_| conn.flush()) {
                        return Served::Lost(format!("write failed: {e}"));
                    }
                    last_sent = Instant::now();
                }
                Ok(Outgoing::Close) | Err(mpsc::TryRecvError::Disconnected) => {
                    return Served::Closed
                }
                Err(mpsc::TryRecvError::Empty) => break,
            }
        }
        if let Some(sent) = ping_sent {
            if sent.elapsed() > KEEPALIVE {
                return Served::Lost("the broker stopped answering pings".into());
            }
        } else if last_sent.elapsed() >= KEEPALIVE - Duration::from_secs(5) {
            if let Err(e) = conn.write_all(&[0xC0, 0x00]).and_then(|_| conn.flush()) {
                return Served::Lost(format!("write failed: {e}"));
            }
            last_sent = Instant::now();
            ping_sent = Some(Instant::now());
        }
        match conn.read(&mut chunk) {
            Ok(0) => return Served::Lost("the broker closed the connection".into()),
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(e)
                if matches!(
                    e.kind(),
                    ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted
                ) => {}
            Err(e) => return Served::Lost(format!("read failed: {e}")),
        }
        while let Some((header, body, used)) = split_packet(&buf) {
            let result = handle(header, &body, conn, shared, &mut ping_sent);
            buf.drain(..used);
            if let Err(why) = result {
                return Served::Lost(why);
            }
        }
    }
}

fn handle(
    header: u8,
    body: &[u8],
    conn: &mut Box<dyn Stream>,
    shared: &Shared,
    ping_sent: &mut Option<Instant>,
) -> Result<(), String> {
    match header >> 4 {
        3 => {
            let (topic, payload, qos_pid) = parse_publish(header, body)?;
            if let Some(pid) = qos_pid {
                // QoS 1: acknowledge (QoS 2 is never requested).
                let _ = conn.write_all(&[0x40, 0x02, (pid >> 8) as u8, pid as u8]);
            }
            let callbacks: Vec<Callback> = shared
                .listeners
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .get(&topic)
                .map(|v| v.iter().map(|(_, cb)| cb.clone()).collect())
                .unwrap_or_default();
            for cb in callbacks {
                cb(payload);
            }
        }
        9 => {
            // SUBACK: packet id, properties, then one reason code per filter.
            if body.len() >= 2 {
                let pid = u16::from_be_bytes([body[0], body[1]]);
                let (props, n) = read_varint(&body[2..]).ok_or("bad SUBACK")?;
                let codes = body.get(2 + n + props as usize..).unwrap_or(&[]);
                let ok = codes.first().map(|&c| c < 0x80).unwrap_or(false);
                if let Some(tx) = shared
                    .suback
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .remove(&pid)
                {
                    let _ = tx.send(ok);
                }
            }
        }
        13 => *ping_sent = None,
        14 => {
            let reason = body.first().copied().unwrap_or(0);
            return Err(format!("the broker disconnected (reason {reason})"));
        }
        _ => {}
    }
    Ok(())
}

fn tls_config() -> Arc<rustls::ClientConfig> {
    let mut roots = rustls::RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    Arc::new(
        rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .expect("ring supports the default TLS versions")
            .with_root_certificates(roots)
            .with_no_client_auth(),
    )
}

/// Open the socket, send CONNECT and wait for CONNACK.
fn open(opts: &Options) -> Result<Box<dyn Stream>, MqttError> {
    let addr = (opts.host.as_str(), opts.port)
        .to_socket_addrs()
        .map_err(|e| MqttError(format!("cannot resolve {}: {e}", opts.host)))?
        .next()
        .ok_or_else(|| MqttError(format!("cannot resolve {}", opts.host)))?;
    let tcp = TcpStream::connect_timeout(&addr, CONNECT_TIMEOUT)
        .map_err(|e| MqttError(format!("cannot reach {}:{}: {e}", opts.host, opts.port)))?;
    tcp.set_nodelay(true).ok();
    tcp.set_read_timeout(Some(CONNECT_TIMEOUT)).ok();
    let mut conn: Box<dyn Stream> = if opts.tls {
        let name = ServerName::try_from(opts.host.clone())
            .map_err(|e| MqttError(format!("invalid broker name {}: {e}", opts.host)))?;
        let client = rustls::ClientConnection::new(tls_config(), name)
            .map_err(|e| MqttError(format!("TLS setup failed: {e}")))?;
        Box::new(rustls::StreamOwned::new(
            client,
            tcp.try_clone().map_err(|e| MqttError(e.to_string()))?,
        ))
    } else {
        Box::new(tcp.try_clone().map_err(|e| MqttError(e.to_string()))?)
    };
    conn.write_all(&connect_packet(opts))
        .and_then(|_| conn.flush())
        .map_err(|e| MqttError(format!("cannot talk to {}: {e}", opts.host)))?;
    let mut buf = Vec::new();
    let mut chunk = [0u8; 1024];
    let deadline = Instant::now() + CONNECT_TIMEOUT;
    loop {
        if let Some((header, body, _)) = split_packet(&buf) {
            if header >> 4 != 2 || body.len() < 2 {
                return Err(MqttError(
                    "the broker did not answer CONNECT with CONNACK".into(),
                ));
            }
            let reason = body[1];
            if reason != 0 {
                return Err(MqttError(format!(
                    "the broker refused the connection (reason {reason})"
                )));
            }
            break;
        }
        if Instant::now() > deadline {
            return Err(MqttError("timed out waiting for the broker".into()));
        }
        match conn.read(&mut chunk) {
            Ok(0) => return Err(MqttError("the broker closed the connection".into())),
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(e)
                if matches!(
                    e.kind(),
                    ErrorKind::WouldBlock | ErrorKind::TimedOut | ErrorKind::Interrupted
                ) => {}
            Err(e) => {
                return Err(MqttError(format!(
                    "TLS/MQTT handshake with {} failed: {e}",
                    opts.host
                )))
            }
        }
    }
    tcp.set_read_timeout(Some(POLL)).ok();
    Ok(conn)
}

fn write_varint(out: &mut Vec<u8>, mut n: usize) {
    loop {
        let mut byte = (n % 128) as u8;
        n /= 128;
        if n > 0 {
            byte |= 0x80;
        }
        out.push(byte);
        if n == 0 {
            break;
        }
    }
}

/// A variable byte integer and how many bytes it took.
fn read_varint(data: &[u8]) -> Option<(u32, usize)> {
    let mut value: u32 = 0;
    for (i, &b) in data.iter().enumerate().take(4) {
        value |= ((b & 0x7F) as u32) << (7 * i);
        if b & 0x80 == 0 {
            return Some((value, i + 1));
        }
    }
    None
}

fn write_str(out: &mut Vec<u8>, s: &[u8]) {
    out.extend_from_slice(&(s.len() as u16).to_be_bytes());
    out.extend_from_slice(s);
}

fn packet(header: u8, body: Vec<u8>) -> Vec<u8> {
    let mut out = vec![header];
    write_varint(&mut out, body.len());
    out.extend(body);
    out
}

pub fn connect_packet(opts: &Options) -> Vec<u8> {
    let mut body = Vec::new();
    write_str(&mut body, b"MQTT");
    body.push(5); // protocol level: MQTT 5
    body.push(0x80 | 0x40 | 0x02); // username, password, clean start
    body.extend_from_slice(&(KEEPALIVE.as_secs() as u16).to_be_bytes());
    body.push(0); // no properties
    write_str(&mut body, opts.client_id.as_bytes());
    write_str(&mut body, opts.username.as_bytes());
    write_str(&mut body, opts.password.as_bytes());
    packet(0x10, body)
}

pub fn subscribe_packet(pid: u16, topic: &str) -> Vec<u8> {
    let mut body = pid.to_be_bytes().to_vec();
    body.push(0); // no properties
    write_str(&mut body, topic.as_bytes());
    body.push(0); // QoS 0
    packet(0x82, body)
}

fn unsubscribe_packet(pid: u16, topic: &str) -> Vec<u8> {
    let mut body = pid.to_be_bytes().to_vec();
    body.push(0);
    write_str(&mut body, topic.as_bytes());
    packet(0xA2, body)
}

pub fn publish_packet(topic: &str, payload: &[u8]) -> Vec<u8> {
    let mut body = Vec::with_capacity(topic.len() + payload.len() + 3);
    write_str(&mut body, topic.as_bytes());
    body.push(0); // no properties
    body.extend_from_slice(payload);
    packet(0x30, body)
}

/// One whole packet from the front of `buf`: (first byte, body, bytes used).
pub fn split_packet(buf: &[u8]) -> Option<(u8, Vec<u8>, usize)> {
    let header = *buf.first()?;
    let (len, n) = read_varint(&buf[1..])?;
    let start = 1 + n;
    let end = start + len as usize;
    if buf.len() < end {
        return None;
    }
    Some((header, buf[start..end].to_vec(), end))
}

/// (topic, payload, packet id when QoS > 0) of an MQTT 5 PUBLISH body.
pub fn parse_publish(header: u8, body: &[u8]) -> Result<(String, &[u8], Option<u16>), String> {
    let bad = || "malformed PUBLISH".to_string();
    let tlen = u16::from_be_bytes([
        *body.first().ok_or_else(bad)?,
        *body.get(1).ok_or_else(bad)?,
    ]) as usize;
    let topic = std::str::from_utf8(body.get(2..2 + tlen).ok_or_else(bad)?)
        .map_err(|_| bad())?
        .to_string();
    let mut pos = 2 + tlen;
    let qos = (header >> 1) & 0x03;
    let mut pid = None;
    if qos > 0 {
        let b = body.get(pos..pos + 2).ok_or_else(bad)?;
        pid = Some(u16::from_be_bytes([b[0], b[1]]));
        pos += 2;
    }
    let (plen, n) = read_varint(body.get(pos..).ok_or_else(bad)?).ok_or_else(bad)?;
    pos += n + plen as usize;
    Ok((topic, body.get(pos..).ok_or_else(bad)?, pid))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn varints_round_trip_at_the_byte_boundaries() {
        for n in [0usize, 127, 128, 16_383, 16_384, 2_097_151] {
            let mut out = Vec::new();
            write_varint(&mut out, n);
            assert_eq!(read_varint(&out), Some((n as u32, out.len())));
        }
    }

    #[test]
    fn connect_is_mqtt_5_with_credentials_and_keepalive() {
        let p = connect_packet(&Options {
            host: "h".into(),
            port: 1,
            tls: true,
            username: "user".into(),
            password: "pw".into(),
            client_id: "cid".into(),
        });
        let (header, body, used) = split_packet(&p).unwrap();
        assert_eq!(header, 0x10);
        assert_eq!(used, p.len());
        assert_eq!(&body[0..6], b"\x00\x04MQTT");
        assert_eq!(body[6], 5);
        assert_eq!(body[7], 0xC2);
        assert_eq!(u16::from_be_bytes([body[8], body[9]]), 45);
        assert!(body.ends_with(b"\x00\x03cid\x00\x04user\x00\x02pw"));
    }

    #[test]
    fn publish_packets_parse_back_to_topic_and_payload() {
        let p = publish_packet("rr/m/o/a/b/c", b"\x01\x02payload");
        let (header, body, _) = split_packet(&p).unwrap();
        let (topic, payload, pid) = parse_publish(header, &body).unwrap();
        assert_eq!(topic, "rr/m/o/a/b/c");
        assert_eq!(payload, b"\x01\x02payload");
        assert_eq!(pid, None);
    }

    #[test]
    fn a_qos1_publish_carries_its_packet_id() {
        let mut body = Vec::new();
        write_str(&mut body, b"t");
        body.extend_from_slice(&7u16.to_be_bytes());
        body.push(0);
        body.extend_from_slice(b"x");
        let (topic, payload, pid) = parse_publish(0x32, &body).unwrap();
        assert_eq!((topic.as_str(), payload, pid), ("t", &b"x"[..], Some(7)));
    }

    #[test]
    fn split_packet_waits_for_the_whole_body() {
        let p = publish_packet("t", &[0u8; 300]);
        assert!(split_packet(&p[..p.len() - 1]).is_none());
        assert!(split_packet(&p).is_some());
    }

    #[test]
    fn topics_are_redacted_in_errors() {
        assert_eq!(redact("rr/m/o/user/hash/duid"), "rr/m/o/***");
    }
}
