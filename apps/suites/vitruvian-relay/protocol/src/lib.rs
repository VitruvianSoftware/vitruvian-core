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

//! JSON frames spoken between the relay server and the `vrelay` connector.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Protocol version spoken on `/connect`. Both ends must match.
pub const PROTOCOL: u32 = 2;
/// Largest frame either side will send or accept. Both ends also set
/// tokio-tungstenite's `max_message_size` and `max_frame_size` to this.
pub const MAX_FRAME_BYTES: usize = 4 * 1024 * 1024;
/// Each side pings this often when idle.
pub const PING_SECS: u64 = 20;
/// Ping interval while a call is in flight.
pub const IN_CALL_PING_SECS: u64 = 2;
/// This many unanswered pings means the link is dead.
pub const MAX_MISSED_PINGS: u32 = 3;
/// The longest a tool call may take (the `deadline_ms` the relay sends). The
/// connector never waits longer for one, whatever a frame says. Under the
/// ~100 s a Cloudflare tunnel holds a request whose answer has not started
/// (the relay answers `tools/call` as one JSON body), so a slow call fails
/// with the relay's own message, not a 524; the 60 s "ask first" dialog
/// fits inside (ruling R16; streamed answers with keep-alives would lift it).
pub const CALL_BUDGET_SECS: u64 = 90;
/// How long the relay waits for the connector's `ack` after sending a `call`.
pub const ACK_SECS: u64 = 5;
/// How long the relay waits on an approval dialog (`pending`) before
/// replying with a `check_request` handle (and how long each `check_request`
/// waits).
pub const APPROVAL_REPLY_SECS: u64 = 10;
/// How long in-flight calls and open approval dialogs survive a dropped
/// link while the connector reconnects.
pub const RECONNECT_GRACE_SECS: u64 = 10;

#[derive(Debug)]
pub enum FrameError {
    /// The frame is over `MAX_FRAME_BYTES` (carries its size).
    TooLarge(usize),
    Json(serde_json::Error),
}

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FrameError::TooLarge(n) => {
                write!(
                    f,
                    "frame of {n} bytes is over the {MAX_FRAME_BYTES} byte limit"
                )
            }
            FrameError::Json(e) => write!(f, "bad frame: {e}"),
        }
    }
}

impl std::error::Error for FrameError {}

impl From<serde_json::Error> for FrameError {
    fn from(e: serde_json::Error) -> Self {
        FrameError::Json(e)
    }
}

/// A tool as MCP names it, so a `desktop-commander` tool passes through unchanged.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolDef {
    pub name: String,
    pub description: String,
    #[serde(rename = "inputSchema")]
    pub input_schema: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Hello {
    pub device_id: String,
    pub connector_version: String,
    pub protocol: u32,
    pub ts: u64,
    pub sig: String,
    pub tools: Vec<ToolDef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Call {
    pub call_id: String,
    pub tool: String,
    pub arguments: Value,
    /// A duration from when the frame is sent, not a clock time (the two
    /// machines' clocks may differ). The relay sets it as it writes the
    /// frame: what is left of its own wait, less an allowance for the frame
    /// to arrive, so the device stops waiting before the relay does.
    pub deadline_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CallResult {
    pub call_id: String,
    pub content: Value,
    pub is_error: bool,
    pub truncated: bool,
}

/// Connector to relay.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ToRelay {
    Hello(Hello),
    /// Received the call frame; waiting for `Start` before running it.
    Ack { call_id: String },
    /// An approval dialog is open on the computer for this call.
    Pending { call_id: String },
    Result(CallResult),
    ToolsChanged { tools: Vec<ToolDef> },
    Ping { n: u64 },
    Pong { n: u64 },
}

/// Relay to connector.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ToConnector {
    Welcome { device_id: String },
    Reject { reason: String },
    Call(Call),
    /// The relay is still waiting; the connector may start the call.
    Start { call_id: String },
    Cancel { call_id: String },
    /// The relay has accepted the call's result; the connector may drop it.
    ResultAck { call_id: String },
    Ping { n: u64 },
    Pong { n: u64 },
}

/// Lowercase hex, two digits a byte: ids, digests, keys on disk.
pub fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        let _ = write!(s, "{b:02x}");
    }
    s
}

/// The bytes the device key signs. Binding the token hash stops a signature
/// being replayed with a different token.
pub fn hello_message(device_id: &str, ts: u64, token_sha256_hex: &str) -> String {
    format!("vrelay-hello-v2\n{device_id}\n{ts}\n{token_sha256_hex}")
}

/// Serialise a frame; refuses one whose encoded form is over `MAX_FRAME_BYTES`.
///
/// The whole frame is serialised before its size is checked, so a frame
/// far over the limit costs its full size in memory once before it is
/// refused. Callers keep what they send near the limit first (the
/// connector cuts tool output to fit, `bridge::fit_to_frame`; the relay
/// caps an MCP body at `MAX_MCP_BODY_BYTES`).
pub fn encode<T: Serialize>(frame: &T) -> Result<String, FrameError> {
    let s = serde_json::to_string(frame)?;
    if s.len() > MAX_FRAME_BYTES {
        return Err(FrameError::TooLarge(s.len()));
    }
    Ok(s)
}

fn decode<T: for<'a> Deserialize<'a>>(s: &str) -> Result<T, FrameError> {
    if s.len() > MAX_FRAME_BYTES {
        return Err(FrameError::TooLarge(s.len()));
    }
    Ok(serde_json::from_str(s)?)
}

pub fn decode_to_relay(s: &str) -> Result<ToRelay, FrameError> {
    decode(s)
}

pub fn decode_to_connector(s: &str) -> Result<ToConnector, FrameError> {
    decode(s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn tool() -> ToolDef {
        ToolDef {
            name: "read_file".into(),
            description: "Read a file".into(),
            input_schema: json!({"type": "object", "properties": {"path": {"type": "string"}}}),
        }
    }

    #[test]
    fn round_trips_every_frame() {
        let to_relay = vec![
            ToRelay::Hello(Hello {
                device_id: "d1".into(),
                connector_version: "0.1.0".into(),
                protocol: PROTOCOL,
                ts: 1_700_000_000,
                sig: "abcd".into(),
                tools: vec![tool()],
            }),
            ToRelay::Result(CallResult {
                call_id: "c1".into(),
                content: json!([{"type": "text", "text": "hi"}]),
                is_error: false,
                truncated: true,
            }),
            ToRelay::ToolsChanged {
                tools: vec![tool()],
            },
            ToRelay::Ack {
                call_id: "c1".into(),
            },
            ToRelay::Pending {
                call_id: "c1".into(),
            },
            ToRelay::Ping { n: 1 },
            ToRelay::Pong { n: 2 },
        ];
        for f in to_relay {
            let s = encode(&f).unwrap();
            assert_eq!(decode_to_relay(&s).unwrap(), f);
        }
        let to_connector = vec![
            ToConnector::Welcome {
                device_id: "d1".into(),
            },
            ToConnector::Reject {
                reason: "bad sig".into(),
            },
            ToConnector::Call(Call {
                call_id: "c1".into(),
                tool: "read_file".into(),
                arguments: json!({"path": "/tmp/x"}),
                deadline_ms: 90_000,
            }),
            ToConnector::Cancel {
                call_id: "c1".into(),
            },
            ToConnector::Start {
                call_id: "c1".into(),
            },
            ToConnector::ResultAck {
                call_id: "c1".into(),
            },
            ToConnector::Ping { n: 3 },
            ToConnector::Pong { n: 4 },
        ];
        for f in to_connector {
            let s = encode(&f).unwrap();
            assert_eq!(decode_to_connector(&s).unwrap(), f);
        }
    }

    #[test]
    fn v2_frames_round_trip() {
        for (frame, wire) in [
            (
                ToRelay::Ack {
                    call_id: "c1".into(),
                },
                r#"{"type":"ack","call_id":"c1"}"#,
            ),
            (
                ToRelay::Pending {
                    call_id: "c1".into(),
                },
                r#"{"type":"pending","call_id":"c1"}"#,
            ),
        ] {
            let encoded = encode(&frame).unwrap();
            assert_eq!(encoded, wire);
            assert_eq!(decode_to_relay(&encoded).unwrap(), frame);
        }

        for (frame, wire) in [
            (
                ToConnector::Start {
                    call_id: "c1".into(),
                },
                r#"{"type":"start","call_id":"c1"}"#,
            ),
            (
                ToConnector::ResultAck {
                    call_id: "c1".into(),
                },
                r#"{"type":"result_ack","call_id":"c1"}"#,
            ),
        ] {
            let encoded = encode(&frame).unwrap();
            assert_eq!(encoded, wire);
            assert_eq!(decode_to_connector(&encoded).unwrap(), frame);
        }
    }

    #[test]
    fn frames_carry_a_snake_case_type_tag() {
        let s = encode(&ToRelay::ToolsChanged { tools: vec![] }).unwrap();
        assert!(s.contains(r#""type":"tools_changed""#), "{s}");
    }

    #[test]
    fn rejects_unknown_type() {
        assert!(decode_to_relay(r#"{"type":"nope"}"#).is_err());
        assert!(decode_to_connector(r#"{"type":"nope"}"#).is_err());
        assert!(decode_to_relay("not json").is_err());
    }

    #[test]
    fn encode_refuses_oversized_frame() {
        // The input is shorter than the limit; the encoded frame (with the
        // type tag and field names) is not.
        let text = "x".repeat(MAX_FRAME_BYTES - 10);
        let frame = ToRelay::Result(CallResult {
            call_id: "c".into(),
            content: json!(text),
            is_error: false,
            truncated: false,
        });
        assert!(matches!(encode(&frame), Err(FrameError::TooLarge(_))));
    }

    #[test]
    fn decode_refuses_oversized_frame() {
        let big = format!(
            r#"{{"type":"ping","n":1,"pad":"{}"}}"#,
            "x".repeat(MAX_FRAME_BYTES)
        );
        assert!(matches!(
            decode_to_relay(&big),
            Err(FrameError::TooLarge(_))
        ));
        assert!(matches!(
            decode_to_connector(&big),
            Err(FrameError::TooLarge(_))
        ));
    }

    #[test]
    fn tool_def_uses_input_schema_wire_name() {
        let t: ToolDef = serde_json::from_str(
            r#"{"name":"n","description":"d","inputSchema":{"type":"object"}}"#,
        )
        .unwrap();
        assert_eq!(t.input_schema, json!({"type": "object"}));
        let out = serde_json::to_string(&t).unwrap();
        assert!(
            out.contains("inputSchema") && !out.contains("input_schema"),
            "{out}"
        );
    }

    #[test]
    fn hex_is_two_lowercase_digits_a_byte() {
        assert_eq!(hex(&[0x00, 0x0f, 0xa0, 0xff]), "000fa0ff");
        assert_eq!(hex(&[]), "");
    }

    #[test]
    fn hello_message_is_stable() {
        assert_eq!(
            hello_message("dev-1", 1700000000, "ab12"),
            "vrelay-hello-v2\ndev-1\n1700000000\nab12"
        );
    }

    #[test]
    fn hello_message_names_v2() {
        assert!(hello_message("dev-1", 1_700_000_000, "ab12").starts_with("vrelay-hello-v2\n"));
    }

    #[test]
    fn constants_match_the_spec() {
        assert_eq!(PROTOCOL, 2);
        assert_eq!(MAX_FRAME_BYTES, 4 * 1024 * 1024);
        assert_eq!((PING_SECS, IN_CALL_PING_SECS, MAX_MISSED_PINGS), (20, 2, 3));
        // Ruling R16: under the ~100 s Cloudflare gives an origin that sends
        // nothing (the answer is one JSON body, sent at the end), with the
        // connector's 60 s dialog inside it.
        assert_eq!(CALL_BUDGET_SECS, 90);
    }

    #[test]
    fn protocol_constants_are_pinned() {
        assert_eq!(PROTOCOL, 2);
        assert_eq!(ACK_SECS, 5);
        assert_eq!(APPROVAL_REPLY_SECS, 10);
        assert_eq!(RECONNECT_GRACE_SECS, 10);
        assert_eq!(MAX_FRAME_BYTES, 4 * 1024 * 1024);
        assert_eq!(PING_SECS, 20);
        assert_eq!(IN_CALL_PING_SECS, 2);
        assert_eq!(MAX_MISSED_PINGS, 3);
        assert_eq!(CALL_BUDGET_SECS, 90);
    }

    #[test]
    fn unknown_fields_are_ignored() {
        let f = decode_to_connector(
            r#"{"type":"call","call_id":"c","tool":"t","arguments":{},"deadline_ms":5,"extra":1}"#,
        )
        .unwrap();
        assert_eq!(
            f,
            ToConnector::Call(Call {
                call_id: "c".into(),
                tool: "t".into(),
                arguments: json!({}),
                deadline_ms: 5,
            })
        );
        assert!(!encode(&f).unwrap().contains("extra"));
    }

    // A ping frame padded with whitespace to an exact byte length.
    fn ping_of_len(n: usize) -> String {
        let base = r#"{"type":"ping","n":1}"#;
        format!("{base}{}", " ".repeat(n - base.len()))
    }

    #[test]
    fn decode_accepts_exactly_max_and_refuses_one_over() {
        assert!(decode_to_relay(&ping_of_len(MAX_FRAME_BYTES)).is_ok());
        assert!(decode_to_connector(&ping_of_len(MAX_FRAME_BYTES)).is_ok());
        assert!(matches!(
            decode_to_relay(&ping_of_len(MAX_FRAME_BYTES + 1)),
            Err(FrameError::TooLarge(_))
        ));
        assert!(matches!(
            decode_to_connector(&ping_of_len(MAX_FRAME_BYTES + 1)),
            Err(FrameError::TooLarge(_))
        ));
    }

    #[test]
    fn encode_accepts_exactly_max_and_refuses_one_over() {
        // Encoded size is the empty-text frame plus the text length.
        let frame = |len: usize| {
            ToRelay::Result(CallResult {
                call_id: "c".into(),
                content: json!("x".repeat(len)),
                is_error: false,
                truncated: false,
            })
        };
        let overhead = encode(&frame(0)).unwrap().len();
        let at_max = encode(&frame(MAX_FRAME_BYTES - overhead)).unwrap();
        assert_eq!(at_max.len(), MAX_FRAME_BYTES);
        assert!(matches!(
            encode(&frame(MAX_FRAME_BYTES - overhead + 1)),
            Err(FrameError::TooLarge(n)) if n == MAX_FRAME_BYTES + 1
        ));
    }
}
