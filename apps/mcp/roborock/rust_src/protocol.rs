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

//! The Roborock "1.0"/"L01" message format and the V1 RPC envelope.
//!
//! A port of python-roborock 7.12.1's `roborock/protocol.py`,
//! `roborock/protocols/v1_protocol.py` and `roborock/roborock_message.py`.
//!
//! A frame is `version(3) seq(u32) random(u32) timestamp(u32) protocol(u16)`,
//! then, when there is a payload, `length(u16) encrypted-payload`, then a
//! CRC32 of everything before it. All integers are big-endian. Local TCP
//! frames carry a 4-byte length prefix; MQTT frames do not.
//!
//! Version "1.0" encrypts the payload with AES-128-ECB under
//! `md5(encode_timestamp(ts) + local_key + SALT)`. Version "L01" (newer local
//! firmware) uses AES-256-GCM with a key, IV and AAD derived from the same
//! inputs plus the hello nonces.

use crate::crypto::{self, CryptoError};
use serde_json::{json, Map, Value};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const SALT: &[u8] = b"TXdfu$jyZ#TZHsg4";

pub const HELLO_REQUEST: u16 = 0;
pub const HELLO_RESPONSE: u16 = 1;
pub const PING_REQUEST: u16 = 2;
pub const PING_RESPONSE: u16 = 3;
pub const GENERAL_REQUEST: u16 = 4;
pub const GENERAL_RESPONSE: u16 = 5;
pub const RPC_REQUEST: u16 = 101;
pub const RPC_RESPONSE: u16 = 102;
pub const MAP_RESPONSE: u16 = 301;

pub const V1: [u8; 3] = *b"1.0";
pub const L01: [u8; 3] = *b"L01";
const VALID_VERSIONS: [&[u8; 3]; 4] = [b"1.0", b"A01", b"B01", b"L01"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtocolError(pub String);

impl std::fmt::Display for ProtocolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ProtocolError {}

impl From<CryptoError> for ProtocolError {
    fn from(e: CryptoError) -> Self {
        Self(e.0)
    }
}

pub fn now_secs() -> u32 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as u32)
        .unwrap_or(0)
}

/// `util.get_next_int`: a counter that wraps inside `[min, max)`-ish, exactly
/// as python-roborock computes it (`counter % max + min`).
pub struct NextInt {
    min: u32,
    max: u32,
    counter: AtomicU32,
}

impl NextInt {
    pub const fn new(min: u32, max: u32) -> Self {
        Self {
            min,
            max,
            counter: AtomicU32::new(min),
        }
    }

    pub fn next(&self) -> u32 {
        let n = self.counter.fetch_add(1, Ordering::Relaxed).wrapping_add(1);
        n % self.max + self.min
    }
}

static MESSAGE_SEQ: NextInt = NextInt::new(100_000, 999_999);
static MESSAGE_RANDOM: NextInt = NextInt::new(10_000, 99_999);
static REQUEST_ID: NextInt = NextInt::new(10_000, 32_767);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub version: [u8; 3],
    pub seq: u32,
    pub random: u32,
    pub timestamp: u32,
    pub protocol: u16,
    pub payload: Option<Vec<u8>>,
}

impl Message {
    /// A message with python-roborock's defaults for seq, random and timestamp.
    pub fn new(protocol: u16, payload: Option<Vec<u8>>) -> Self {
        Self {
            version: V1,
            seq: MESSAGE_SEQ.next(),
            random: MESSAGE_RANDOM.next(),
            timestamp: now_secs(),
            protocol,
            payload,
        }
    }
}

/// `Utils.encode_timestamp`: the hex timestamp with its digits shuffled.
pub fn encode_timestamp(ts: u32) -> Vec<u8> {
    let hex = format!("{ts:08x}");
    let b = hex.as_bytes();
    [5, 6, 3, 7, 1, 2, 0, 4].iter().map(|&i| b[i]).collect()
}

/// The AES-128-ECB key for a "1.0" frame.
pub fn v1_key(timestamp: u32, local_key: &str) -> [u8; 16] {
    let mut input = encode_timestamp(timestamp);
    input.extend_from_slice(local_key.as_bytes());
    input.extend_from_slice(SALT);
    crypto::md5(&input)
}

/// The nonces an L01 local session agreed in its hello exchange.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Nonces {
    pub connect_nonce: u32,
    pub ack_nonce: Option<u32>,
}

fn l01_key(local_key: &str, timestamp: u32) -> [u8; 32] {
    let mut input = encode_timestamp(timestamp);
    input.extend_from_slice(local_key.as_bytes());
    input.extend_from_slice(SALT);
    crypto::sha256(&input)
}

fn l01_iv(timestamp: u32, nonce: u32, sequence: u32) -> [u8; 12] {
    let mut input = Vec::with_capacity(12);
    input.extend_from_slice(&sequence.to_be_bytes());
    input.extend_from_slice(&nonce.to_be_bytes());
    input.extend_from_slice(&timestamp.to_be_bytes());
    let digest = crypto::sha256(&input);
    let mut iv = [0u8; 12];
    iv.copy_from_slice(&digest[..12]);
    iv
}

fn l01_aad(timestamp: u32, nonce: u32, sequence: u32, nonces: Nonces) -> Vec<u8> {
    let mut aad = Vec::with_capacity(20);
    aad.extend_from_slice(&sequence.to_be_bytes());
    aad.extend_from_slice(&nonces.connect_nonce.to_be_bytes());
    if let Some(ack) = nonces.ack_nonce {
        aad.extend_from_slice(&ack.to_be_bytes());
    }
    aad.extend_from_slice(&nonce.to_be_bytes());
    aad.extend_from_slice(&timestamp.to_be_bytes());
    aad
}

fn encrypt_payload(
    msg: &Message,
    payload: &[u8],
    local_key: &str,
    nonces: Option<Nonces>,
) -> Result<Vec<u8>, ProtocolError> {
    match &msg.version {
        b"L01" => {
            let nonces = nonces
                .ok_or_else(|| ProtocolError("L01 frames need the hello nonces".to_string()))?;
            Ok(crypto::encrypt_gcm(
                &l01_key(local_key, msg.timestamp),
                &l01_iv(msg.timestamp, msg.random, msg.seq),
                &l01_aad(msg.timestamp, msg.random, msg.seq, nonces),
                payload,
            ))
        }
        b"1.0" => Ok(crypto::encrypt_ecb(
            payload,
            &v1_key(msg.timestamp, local_key),
        )?),
        other => Err(ProtocolError(format!(
            "unsupported protocol version {:?}",
            String::from_utf8_lossy(other)
        ))),
    }
}

fn decrypt_payload(
    version: &[u8; 3],
    seq: u32,
    random: u32,
    timestamp: u32,
    payload: &[u8],
    local_key: &str,
    nonces: Option<Nonces>,
) -> Result<Vec<u8>, ProtocolError> {
    match version {
        b"L01" => {
            let nonces = nonces
                .ok_or_else(|| ProtocolError("L01 frames need the hello nonces".to_string()))?;
            Ok(crypto::decrypt_gcm(
                &l01_key(local_key, timestamp),
                &l01_iv(timestamp, random, seq),
                &l01_aad(timestamp, random, seq, nonces),
                payload,
            )?)
        }
        b"1.0" => Ok(crypto::decrypt_ecb(payload, &v1_key(timestamp, local_key))?),
        other => Err(ProtocolError(format!(
            "unsupported protocol version {:?}",
            String::from_utf8_lossy(other)
        ))),
    }
}

/// Build one frame. `prefixed` adds the 4-byte length local TCP uses.
pub fn encode(
    msg: &Message,
    local_key: &str,
    prefixed: bool,
    nonces: Option<Nonces>,
) -> Result<Vec<u8>, ProtocolError> {
    let mut body = Vec::with_capacity(64);
    body.extend_from_slice(&msg.version);
    body.extend_from_slice(&msg.seq.to_be_bytes());
    body.extend_from_slice(&msg.random.to_be_bytes());
    body.extend_from_slice(&msg.timestamp.to_be_bytes());
    body.extend_from_slice(&msg.protocol.to_be_bytes());
    if let Some(payload) = &msg.payload {
        let encrypted = encrypt_payload(msg, payload, local_key, nonces)?;
        let len = u16::try_from(encrypted.len())
            .map_err(|_| ProtocolError("payload too large for one frame".to_string()))?;
        body.extend_from_slice(&len.to_be_bytes());
        body.extend_from_slice(&encrypted);
    }
    let crc = crypto::crc32(&body);
    body.extend_from_slice(&crc.to_be_bytes());
    if !prefixed {
        return Ok(body);
    }
    let mut out = Vec::with_capacity(body.len() + 4);
    out.extend_from_slice(&(body.len() as u32).to_be_bytes());
    out.extend_from_slice(&body);
    Ok(out)
}

/// Parse one unprefixed frame (an MQTT payload, or a local frame after its
/// length prefix). A frame without a payload may also omit its checksum.
pub fn decode_frame(
    frame: &[u8],
    local_key: &str,
    nonces: Option<Nonces>,
) -> Result<Message, ProtocolError> {
    if frame.len() < 17 {
        return Err(ProtocolError(format!(
            "frame too short ({} bytes)",
            frame.len()
        )));
    }
    let mut version = [0u8; 3];
    version.copy_from_slice(&frame[0..3]);
    if !VALID_VERSIONS.contains(&&version) {
        return Err(ProtocolError(format!(
            "unknown protocol version {:?}",
            String::from_utf8_lossy(&version)
        )));
    }
    let seq = u32::from_be_bytes(frame[3..7].try_into().unwrap());
    let random = u32::from_be_bytes(frame[7..11].try_into().unwrap());
    let timestamp = u32::from_be_bytes(frame[11..15].try_into().unwrap());
    let protocol = u16::from_be_bytes(frame[15..17].try_into().unwrap());
    let rest = &frame[17..];
    let mut payload = None;
    // A frame without a payload is the bare header, optionally followed by
    // the header's own checksum.
    let header_only = rest.len() < 2
        || (rest.len() == 4
            && u32::from_be_bytes(rest.try_into().unwrap()) == crypto::crc32(&frame[..17]));
    if !header_only {
        let len = u16::from_be_bytes([rest[0], rest[1]]) as usize;
        if len > 0 {
            let end = 17 + 2 + len;
            if frame.len() < end {
                return Err(ProtocolError(format!(
                    "truncated frame: payload of {len} bytes, {} present",
                    frame.len() - 19
                )));
            }
            // As in python-roborock's OptionalChecksum: a frame that carries a
            // payload must carry its checksum too.
            let crc = frame
                .get(end..end + 4)
                .ok_or_else(|| ProtocolError("missing checksum".into()))?;
            let want = u32::from_be_bytes(crc.try_into().unwrap());
            let got = crypto::crc32(&frame[..end]);
            if want != got {
                return Err(ProtocolError(format!(
                    "wrong checksum, read {want:08x}, computed {got:08x}"
                )));
            }
            payload = Some(decrypt_payload(
                &version,
                seq,
                random,
                timestamp,
                &rest[2..2 + len],
                local_key,
                nonces,
            )?);
        }
    }
    Ok(Message {
        version,
        seq,
        random,
        timestamp,
        protocol,
        payload,
    })
}

/// Splits a local TCP byte stream into frames, keeping any partial tail.
#[derive(Default)]
pub struct FrameBuffer {
    buf: Vec<u8>,
}

impl FrameBuffer {
    pub fn push(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(data);
    }

    /// The next complete frame (without its prefix), if one has arrived.
    ///
    /// Every pass either returns a frame, waits for more bytes, or drops at
    /// least one byte, so hostile or buggy input can never make this spin.
    pub fn next_frame(&mut self) -> Option<Vec<u8>> {
        loop {
            if self.buf.len() > MAX_BUFFER {
                // Nothing sane is this big; start over rather than grow.
                self.buf.clear();
                return None;
            }
            if self.buf.len() < 4 {
                return None;
            }
            let len = u32::from_be_bytes(self.buf[0..4].try_into().unwrap()) as usize;
            if (17..=MAX_FRAME).contains(&len) {
                if self.buf.len() < 4 + len {
                    return None;
                }
                let frame = self.buf[4..4 + len].to_vec();
                self.buf.drain(..4 + len);
                return Some(frame);
            }
            // A bad prefix. python-roborock ignores the prefix value and reads
            // the frame from the version marker, so do the same when the marker
            // sits right after the prefix and a whole frame with a valid
            // checksum is already here. Never wait on a bad prefix: that would
            // let noise hold the buffer hostage.
            if let Some(n) = structural_len(&self.buf[4..]) {
                let frame = self.buf[4..4 + n].to_vec();
                self.buf.drain(..4 + n);
                return Some(frame);
            }
            // Resynchronise on the next marker that has room for a prefix in
            // front of it, dropping at least one byte.
            match find_version(&self.buf[5..]) {
                Some(i) => {
                    self.buf.drain(..i + 1);
                }
                None => {
                    // Keep a possible partial prefix+marker at the tail.
                    let keep = 6.min(self.buf.len() - 1);
                    let cut = self.buf.len() - keep;
                    self.buf.drain(..cut);
                    return None;
                }
            }
        }
    }
}

/// Largest frame accepted (the device's frames are a few kilobytes).
const MAX_FRAME: usize = 1 << 20;
/// Largest amount of unparsed input held before giving up on it.
const MAX_BUFFER: usize = 4 << 20;

fn is_version(data: &[u8]) -> bool {
    data.len() >= 3 && VALID_VERSIONS.iter().any(|v| &v[..] == &data[..3])
}

/// The length of a whole, checksum-valid frame at the front of `data`, read
/// from its own fields, or None.
fn structural_len(data: &[u8]) -> Option<usize> {
    if !is_version(data) || data.len() < 19 {
        return None;
    }
    let len = u16::from_be_bytes([data[17], data[18]]) as usize;
    let n = 17 + 2 + len + 4;
    if len == 0 || data.len() < n {
        return None;
    }
    let want = u32::from_be_bytes(data[n - 4..n].try_into().unwrap());
    (crypto::crc32(&data[..n - 4]) == want).then_some(n)
}

fn find_version(data: &[u8]) -> Option<usize> {
    data.windows(3)
        .position(|w| VALID_VERSIONS.iter().any(|v| &v[..] == w))
}

/// The MQTT broker and login derived from the user's `rriot` block.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MqttParams {
    pub host: String,
    pub port: u16,
    pub tls: bool,
    pub username: String,
    pub password: String,
}

pub fn mqtt_params(rriot: &Rriot) -> Result<MqttParams, ProtocolError> {
    let url = &rriot.mqtt_url;
    let (scheme, rest) = url.split_once("://").ok_or_else(|| {
        ProtocolError(format!("Url parsing '{url}' returned an invalid hostname"))
    })?;
    let authority = rest.split('/').next().unwrap_or("");
    let (host, port) = authority
        .rsplit_once(':')
        .ok_or_else(|| ProtocolError(format!("Url parsing '{url}' returned an invalid port")))?;
    let port: u16 = port
        .parse()
        .map_err(|_| ProtocolError(format!("Url parsing '{url}' returned an invalid port")))?;
    if host.is_empty() {
        return Err(ProtocolError(format!(
            "Url parsing '{url}' returned an invalid hostname"
        )));
    }
    let user_hash = crypto::md5_hex(format!("{}:{}", rriot.u, rriot.k).as_bytes());
    let pass_hash = crypto::md5_hex(format!("{}:{}", rriot.s, rriot.k).as_bytes());
    Ok(MqttParams {
        host: host.to_string(),
        port,
        tls: scheme == "ssl",
        username: user_hash[2..10].to_string(),
        password: pass_hash[16..].to_string(),
    })
}

/// The `rriot` block of the stored login: the IoT identity and its endpoints.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rriot {
    pub u: String,
    pub s: String,
    pub h: String,
    pub k: String,
    pub api_url: String,
    pub mqtt_url: String,
}

impl Rriot {
    pub fn from_user_data(user_data: &Map<String, Value>) -> Result<Self, ProtocolError> {
        let rriot = user_data
            .get("rriot")
            .and_then(Value::as_object)
            .ok_or_else(|| ProtocolError("Your userdata is missing critical attributes.".into()))?;
        let field = |name: &str| -> Result<String, ProtocolError> {
            rriot
                .get(name)
                .and_then(Value::as_str)
                .map(str::to_string)
                .ok_or_else(|| ProtocolError(format!("rriot is missing '{name}'")))
        };
        let r = rriot
            .get("r")
            .and_then(Value::as_object)
            .ok_or_else(|| ProtocolError("rriot is missing 'r'".into()))?;
        let endpoint = |name: &str| -> Result<String, ProtocolError> {
            r.get(name)
                .and_then(Value::as_str)
                .map(str::to_string)
                .ok_or_else(|| ProtocolError(format!("Missing field '{name}' in rriot reference")))
        };
        Ok(Self {
            u: field("u")?,
            s: field("s")?,
            h: field("h")?,
            k: field("k")?,
            api_url: endpoint("a")?,
            mqtt_url: endpoint("m")?,
        })
    }
}

/// The `security` envelope MQTT requests carry, whose nonce is the key the
/// device encrypts map responses with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SecurityData {
    pub endpoint: String,
    pub nonce: [u8; 16],
}

impl SecurityData {
    pub fn new(rriot_k: &str) -> Self {
        let digest = crypto::md5(rriot_k.as_bytes());
        let mut nonce = [0u8; 16];
        nonce.copy_from_slice(&crypto::random_bytes(16));
        Self {
            endpoint: crypto::b64(&digest[8..14]),
            nonce,
        }
    }
}

/// A V1 RPC request.
#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    pub id: u32,
    pub method: String,
    pub params: Value,
    pub timestamp: u32,
}

impl Request {
    pub fn new(method: impl Into<String>, params: Option<Value>) -> Self {
        Self {
            id: REQUEST_ID.next(),
            method: method.into(),
            params: params.unwrap_or_else(|| json!([])),
            timestamp: now_secs(),
        }
    }

    /// `RequestMessage._as_payload`: the inner call is JSON inside JSON.
    pub fn payload(&self, security: Option<&SecurityData>) -> Vec<u8> {
        let params = match &self.params {
            Value::Null => json!([]),
            Value::Array(a) if a.is_empty() => json!([]),
            Value::Object(o) if o.is_empty() => json!([]),
            other => other.clone(),
        };
        let mut inner = Map::new();
        inner.insert("id".into(), json!(self.id));
        inner.insert("method".into(), json!(self.method));
        inner.insert("params".into(), params);
        if let Some(sec) = security {
            inner.insert(
                "security".into(),
                json!({"endpoint": sec.endpoint, "nonce": crypto::hex(&sec.nonce)}),
            );
        }
        let inner = serde_json::to_string(&Value::Object(inner)).expect("JSON values serialise");
        serde_json::to_vec(&json!({"dps": {"101": inner}, "t": self.timestamp}))
            .expect("JSON values serialise")
    }

    /// The message for MQTT (RPC_REQUEST, with the security envelope) or a
    /// local channel (GENERAL_REQUEST in the session's version).
    pub fn to_message(
        &self,
        protocol: u16,
        version: [u8; 3],
        security: Option<&SecurityData>,
    ) -> Message {
        let mut msg = Message::new(protocol, Some(self.payload(security)));
        msg.timestamp = self.timestamp;
        msg.version = version;
        msg
    }
}

/// What a device said back to an RPC.
#[derive(Debug, Clone, PartialEq)]
pub struct Response {
    pub id: Option<u64>,
    pub result: Result<Value, String>,
}

fn decode_dps(payload: &[u8]) -> Result<Option<Map<String, Value>>, ProtocolError> {
    let doc: Value = serde_json::from_slice(payload).map_err(|e| {
        ProtocolError(format!(
            "Invalid V1 message payload: {e} for {}",
            String::from_utf8_lossy(payload)
        ))
    })?;
    Ok(doc.get("dps").and_then(Value::as_object).cloned())
}

/// `decode_rpc_response`.
pub fn decode_rpc_response(msg: &Message) -> Result<Response, ProtocolError> {
    let Some(payload) = msg.payload.as_deref().filter(|p| !p.is_empty()) else {
        return Ok(Response {
            id: Some(msg.seq as u64),
            result: Ok(json!({})),
        });
    };
    let dps = decode_dps(payload)?.ok_or_else(|| {
        ProtocolError("Invalid V1 message format: missing or invalid 'dps' in payload".into())
    })?;
    let point = dps.get("102").and_then(Value::as_str).ok_or_else(|| {
        ProtocolError("Invalid V1 message format: missing '102' data point".into())
    })?;
    let point: Value = serde_json::from_str(point)
        .map_err(|e| ProtocolError(format!("Invalid V1 message data point '102': {e}")))?;
    let id = point.get("id").and_then(Value::as_u64);
    let mut error = point
        .get("error")
        .filter(|e| !e.is_null())
        .map(|e| match e {
            Value::Object(o) => o
                .get("message")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| e.to_string()),
            other => other.to_string(),
        });
    let mut data = json!({});
    match point.get("result") {
        None | Some(Value::Null) => {
            if error.is_none() {
                error = Some("Invalid V1 message format: missing 'result' in data point".into());
            }
        }
        Some(Value::String(s)) => {
            if s == "unknown_method" {
                error = Some("The method called is not recognized by the device.".into());
            } else if s != "ok" {
                error = Some(format!("Unexpected API Result: {s}"));
            }
        }
        Some(v @ (Value::Object(_) | Value::Array(_) | Value::Number(_))) => data = v.clone(),
        Some(other) => {
            if error.is_none() {
                return Err(ProtocolError(format!(
                    "Invalid V1 message format: 'result' was unexpected type {other}"
                )));
            }
        }
    }
    if id.unwrap_or(0) == 0 {
        if let Some(e) = error {
            return Err(ProtocolError(e));
        }
    }
    Ok(Response {
        id,
        result: match error {
            Some(e) => Err(e),
            None => Ok(data),
        },
    })
}

/// `decode_data_protocol_message`: unsolicited status pushes (121 = state, ...).
pub fn decode_dps_push(msg: &Message) -> Option<Map<String, Value>> {
    let payload = msg.payload.as_deref()?;
    let dps = decode_dps(payload).ok()??;
    let pushed: Map<String, Value> = dps
        .into_iter()
        .filter(|(k, _)| {
            k.parse::<u32>()
                .map(|c| (120..=135).contains(&c))
                .unwrap_or(false)
        })
        .collect();
    (!pushed.is_empty()).then_some(pushed)
}

/// `create_map_response_decoder`: a protocol-301 frame answering `get_map_v1`.
/// `Ok(None)` means the frame belongs to another requester.
pub fn decode_map_response(
    msg: &Message,
    security: &SecurityData,
) -> Result<Option<(u16, Vec<u8>)>, ProtocolError> {
    let payload = msg
        .payload
        .as_deref()
        .filter(|p| p.len() >= 24)
        .ok_or_else(|| ProtocolError("Invalid V1 map response format: missing payload".into()))?;
    let (header, body) = payload.split_at(24);
    let endpoint = String::from_utf8_lossy(&header[0..8]);
    if !endpoint.starts_with(&security.endpoint) {
        return Ok(None);
    }
    let request_id = u16::from_le_bytes([header[16], header[17]]);
    let decrypted = crypto::decrypt_cbc(body, &security.nonce)
        .map_err(|_| ProtocolError("Failed to decode map message payload".into()))?;
    let data = crypto::gunzip(&decrypted)?;
    Ok(Some((request_id, data)))
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &str = "abcdefghijklmnop";

    #[test]
    fn timestamp_digits_are_shuffled_like_python() {
        // f"{0x12345678:x}" = "12345678" -> indices [5,6,3,7,1,2,0,4] -> "67482315"
        assert_eq!(encode_timestamp(0x1234_5678), b"67482315");
        assert_eq!(encode_timestamp(1), b"00010000");
    }

    #[test]
    fn v1_frame_round_trips_through_encode_and_decode() {
        let mut msg = Message::new(RPC_REQUEST, Some(b"{\"dps\":{}}".to_vec()));
        msg.timestamp = 1_700_000_000;
        let wire = encode(&msg, KEY, false, None).unwrap();
        assert_eq!(&wire[0..3], b"1.0");
        let back = decode_frame(&wire, KEY, None).unwrap();
        assert_eq!(back, msg);
    }

    #[test]
    fn a_corrupted_frame_fails_its_checksum() {
        let msg = Message::new(RPC_REQUEST, Some(b"x".to_vec()));
        let mut wire = encode(&msg, KEY, false, None).unwrap();
        wire[4] ^= 0x01; // flip a bit in the sequence number
        let err = decode_frame(&wire, KEY, None).unwrap_err();
        assert!(err.0.contains("checksum"), "{err}");
    }

    #[test]
    fn l01_frame_round_trips_with_the_session_nonces() {
        let nonces = Nonces {
            connect_nonce: 12_345,
            ack_nonce: Some(54_321),
        };
        let mut msg = Message::new(GENERAL_REQUEST, Some(b"hello".to_vec()));
        msg.version = L01;
        let wire = encode(&msg, KEY, true, Some(nonces)).unwrap();
        let mut buf = FrameBuffer::default();
        buf.push(&wire);
        let frame = buf.next_frame().unwrap();
        assert_eq!(decode_frame(&frame, KEY, Some(nonces)).unwrap(), msg);
        let wrong = Nonces {
            ack_nonce: Some(1),
            ..nonces
        };
        assert!(decode_frame(&frame, KEY, Some(wrong)).is_err());
    }

    /// Reference frames for python-roborock 7.12.1: seq 123456, random 23456,
    /// ts 1700000000, key "abcdefghijklmnop", RPC_REQUEST, prefixed. aegis
    /// produced them with python-roborock itself; they were reproduced
    /// independently with pycryptodome from protocol.py's formulas.
    const KAT_PAYLOAD: &[u8] = br#"{"dps":{"101":"x"},"t":1700000000}"#;
    const KAT_V1: &str = "00000047312e300001e24000005ba06553f100006500301e75ac7f20dff947ebf5cfecdaa3d507aa0f76eb2b6cafd1e0ccb043326425973f138e626cacf875bf28d0c4a2472bc73625b860";
    const KAT_L01: &str = "000000494c30310001e24000005ba06553f10000650032d0f01ab2bcf4ffc82203d53358665027f1e0213980cb2073ac633cbb069353174718b7f95051c624332664aa9c1b3fa065e999189aea";

    fn kat_message(version: [u8; 3]) -> Message {
        Message {
            version,
            seq: 123_456,
            random: 23_456,
            timestamp: 1_700_000_000,
            protocol: RPC_REQUEST,
            payload: Some(KAT_PAYLOAD.to_vec()),
        }
    }

    #[test]
    fn v1_frames_match_python_roborock_byte_for_byte() {
        let wire = encode(&kat_message(V1), "abcdefghijklmnop", true, None).unwrap();
        assert_eq!(crypto::hex(&wire), KAT_V1);
    }

    #[test]
    fn l01_frames_match_python_roborock_byte_for_byte() {
        let nonces = Nonces {
            connect_nonce: 12_345,
            ack_nonce: Some(54_321),
        };
        let wire = encode(&kat_message(L01), "abcdefghijklmnop", true, Some(nonces)).unwrap();
        assert_eq!(crypto::hex(&wire), KAT_L01);
    }

    #[test]
    fn a_payload_without_its_checksum_is_rejected() {
        let wire = encode(&kat_message(V1), "abcdefghijklmnop", false, None).unwrap();
        let err = decode_frame(&wire[..wire.len() - 4], "abcdefghijklmnop", None).unwrap_err();
        assert!(err.0.contains("missing checksum"), "{err}");
        // A bare header, with or without its checksum, is still fine.
        let hello = encode(&Message::new(HELLO_REQUEST, None), KEY, false, None).unwrap();
        assert!(decode_frame(&hello, KEY, None).unwrap().payload.is_none());
        assert!(decode_frame(&hello[..17], KEY, None)
            .unwrap()
            .payload
            .is_none());
    }

    /// Runs `f` on another thread and fails, instead of hanging, if it spins.
    fn within_a_second<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> T {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(f());
        });
        rx.recv_timeout(std::time::Duration::from_secs(1))
            .expect("next_frame did not return: it is looping")
    }

    #[test]
    fn a_zero_prefix_before_a_version_marker_cannot_hang_the_reader() {
        // aegis's input: four zero bytes then "1.0".
        let got = within_a_second(|| {
            let mut buf = FrameBuffer::default();
            buf.push(b"\x00\x00\x00\x001.0");
            buf.next_frame()
        });
        assert_eq!(got, None);
        // The same bad prefix in front of a whole frame: read it from the
        // marker, as python-roborock does.
        let frames = within_a_second(|| {
            let body = encode(&kat_message(V1), "abcdefghijklmnop", false, None).unwrap();
            let mut stream = vec![0u8; 4];
            stream.extend_from_slice(&body);
            stream.extend(encode(&Message::new(PING_REQUEST, None), KEY, true, None).unwrap());
            let mut buf = FrameBuffer::default();
            buf.push(&stream);
            let mut out = Vec::new();
            while let Some(f) = buf.next_frame() {
                out.push(f);
            }
            out
        });
        assert_eq!(frames.len(), 2);
        assert_eq!(
            decode_frame(&frames[0], "abcdefghijklmnop", None)
                .unwrap()
                .payload
                .unwrap(),
            KAT_PAYLOAD
        );
        assert_eq!(
            decode_frame(&frames[1], KEY, None).unwrap().protocol,
            PING_REQUEST
        );
    }

    #[test]
    fn garbage_is_dropped_and_the_buffer_stays_bounded() {
        let (most, junk_frames) = within_a_second(|| {
            let mut buf = FrameBuffer::default();
            let mut most = 0;
            let mut junk = 0;
            // Markers everywhere and impossible prefixes.
            for _ in 0..20_000 {
                buf.push(b"\xff\xff\xff\xff1.0L01");
                while buf.next_frame().is_some() {
                    junk += 1;
                }
                most = most.max(buf.buf.len());
            }
            // Plain noise with no marker at all must be dropped too.
            for _ in 0..20_000 {
                buf.push(&[0xEE; 10]);
                while buf.next_frame().is_some() {
                    junk += 1;
                }
                most = most.max(buf.buf.len());
            }
            (most, junk)
        });
        assert_eq!(junk_frames, 0);
        assert!(most <= 16, "held {most} bytes of garbage");
        // After a short burst of noise, a real frame still comes through.
        let mut buf = FrameBuffer::default();
        buf.push(b"\x00\x00\x00\x02junk");
        buf.push(&encode(&Message::new(PING_REQUEST, None), KEY, true, None).unwrap());
        let frame = within_a_second(move || buf.next_frame());
        assert_eq!(
            decode_frame(&frame.unwrap(), KEY, None).unwrap().protocol,
            PING_REQUEST
        );
    }

    #[test]
    fn frame_buffer_waits_for_a_whole_frame_and_keeps_the_rest() {
        let a = encode(&Message::new(PING_REQUEST, None), KEY, true, None).unwrap();
        let b = encode(&Message::new(HELLO_REQUEST, None), KEY, true, None).unwrap();
        let mut stream = a.clone();
        stream.extend_from_slice(&b);
        let mut buf = FrameBuffer::default();
        buf.push(&stream[..5]);
        assert!(buf.next_frame().is_none());
        buf.push(&stream[5..]);
        assert_eq!(
            decode_frame(&buf.next_frame().unwrap(), KEY, None)
                .unwrap()
                .protocol,
            PING_REQUEST
        );
        assert_eq!(
            decode_frame(&buf.next_frame().unwrap(), KEY, None)
                .unwrap()
                .protocol,
            HELLO_REQUEST
        );
        assert!(buf.next_frame().is_none());
    }

    #[test]
    fn request_payload_nests_the_call_inside_dps_101() {
        let sec = SecurityData {
            endpoint: "abcdefgh".into(),
            nonce: [0xab; 16],
        };
        let req = Request {
            id: 12_345,
            method: "get_status".into(),
            params: Value::Null,
            timestamp: 7,
        };
        let doc: Value = serde_json::from_slice(&req.payload(Some(&sec))).unwrap();
        assert_eq!(doc["t"], 7);
        let inner: Value = serde_json::from_str(doc["dps"]["101"].as_str().unwrap()).unwrap();
        assert_eq!(
            inner,
            json!({"id": 12345, "method": "get_status", "params": [],
                   "security": {"endpoint": "abcdefgh", "nonce": "ab".repeat(16)}})
        );
    }

    fn response(point: Value) -> Message {
        let payload = json!({"dps": {"102": point.to_string()}, "t": 1});
        Message::new(RPC_RESPONSE, Some(serde_json::to_vec(&payload).unwrap()))
    }

    #[test]
    fn rpc_responses_decode_results_and_errors() {
        let ok =
            decode_rpc_response(&response(json!({"id": 5, "result": [{"state": 8}]}))).unwrap();
        assert_eq!(ok.id, Some(5));
        assert_eq!(ok.result, Ok(json!([{"state": 8}])));

        let plain_ok = decode_rpc_response(&response(json!({"id": 6, "result": ["ok"]}))).unwrap();
        assert_eq!(plain_ok.result, Ok(json!(["ok"])));

        let unknown =
            decode_rpc_response(&response(json!({"id": 7, "result": "unknown_method"}))).unwrap();
        assert!(unknown.result.unwrap_err().contains("not recognized"));

        let err = decode_rpc_response(&response(
            json!({"id": 8, "error": {"code": -10007, "message": "invalid status"}}),
        ))
        .unwrap();
        assert_eq!(err.result, Err("invalid status".to_string()));
    }

    #[test]
    fn mqtt_params_hash_the_rriot_identity() {
        let rriot = Rriot {
            u: "user".into(),
            s: "secret".into(),
            h: "h".into(),
            k: "key".into(),
            api_url: "https://api-us.roborock.com".into(),
            mqtt_url: "ssl://mqtt-us-3.roborock.com:8883".into(),
        };
        let p = mqtt_params(&rriot).unwrap();
        assert_eq!(p.host, "mqtt-us-3.roborock.com");
        assert_eq!(p.port, 8883);
        assert!(p.tls);
        // Reference values from Python's hashlib.
        assert_eq!(p.username, "c6d6afb9");
        assert_eq!(p.password, "938f62d6603bde9c");
        assert_eq!(SecurityData::new("kkk").endpoint, "on/KYigJ");
    }

    #[test]
    fn map_responses_decrypt_with_the_request_nonce() {
        let sec = SecurityData {
            endpoint: "ENDPNT".into(),
            nonce: [9u8; 16],
        };
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        std::io::Write::write_all(&mut gz, b"map bytes").unwrap();
        let body = crypto::encrypt_cbc(&gz.finish().unwrap(), &sec.nonce).unwrap();
        let mut header = [0u8; 24];
        header[..6].copy_from_slice(b"ENDPNT");
        header[16..18].copy_from_slice(&4242u16.to_le_bytes());
        let mut payload = header.to_vec();
        payload.extend_from_slice(&body);
        let msg = Message::new(MAP_RESPONSE, Some(payload.clone()));
        assert_eq!(
            decode_map_response(&msg, &sec).unwrap(),
            Some((4242, b"map bytes".to_vec()))
        );
        payload[0] = b'X';
        let other = Message::new(MAP_RESPONSE, Some(payload));
        assert_eq!(decode_map_response(&other, &sec).unwrap(), None);
    }
}
