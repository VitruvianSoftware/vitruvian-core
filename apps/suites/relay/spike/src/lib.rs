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

//! The relay P0 spike server: the parts that are pure logic, so they can be
//! tested without a network. `main.rs` wires them to HTTP and WebSockets.
//!
//! It answers two P0 questions (docs/superpowers/plans/2026-11-09-relay-p0-spikes.md):
//! - **A:** can Claude and ChatGPT add an OAuth-protected MCP server on our
//!   domain with Zitadel sign-in? `/mcp` is a minimal MCP server with two tools.
//! - **C:** does a WebSocket through the Cloudflare Tunnel stay up? `/connect`
//!   echoes messages and pings every 20 seconds.
//!
//! Not the relay. No device routing, no billing, no persistence.

pub mod client;

use serde_json::{json, Value};

/// MCP protocol revisions this server will agree to. The methods it serves
/// (initialize, ping, tools/list, tools/call) are the same in all of them.
pub const PROTOCOL_VERSIONS: &[&str] = &["2026-07-28", "2025-11-25", "2025-06-18", "2025-03-26"];

pub const SERVER_NAME: &str = "relay-spike";
pub const MAX_BODY_BYTES: usize = 1024 * 1024;

/// Seconds between server pings on `/connect`.
pub const PING_INTERVAL_SECS: u64 = 20;
/// Missed pongs before the server closes a `/connect` socket.
pub const MAX_MISSED_PONGS: u32 = 3;

/// Settings read from the environment once at start-up.
#[derive(Debug, Clone, PartialEq)]
pub struct Settings {
    pub port: u16,
    /// Public origin with no trailing slash, e.g. https://relay-spike.ipv1337.dev
    pub public_url: String,
    pub issuer: String,
    pub project_id: String,
    /// Client ids of AI apps allowed on `/mcp` (Claude, later ChatGPT).
    pub mcp_client_ids: Vec<String>,
    /// Client id of the connector, the only one allowed on `/connect`.
    pub connector_client_id: String,
    pub allowed_subjects: Vec<String>,
    /// Overrides where signing keys are fetched. Unset in production (keys come
    /// from `{issuer}/oauth/v2/keys`); set for local runs against test keys.
    pub jwks_uri: Option<String>,
}

fn csv(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect()
}

impl Settings {
    /// Reads settings from a key lookup (the environment in production).
    /// Every value is required: a missing client id or subject list would
    /// otherwise widen who can get in.
    pub fn from_lookup(get: impl Fn(&str) -> Option<String>) -> Result<Settings, String> {
        let req = |k: &str| -> Result<String, String> {
            get(k)
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
                .ok_or_else(|| format!("{k} is required"))
        };
        let port = match get("PORT").map(|v| v.trim().to_string()) {
            None => 3000,
            Some(v) if v.is_empty() => 3000,
            Some(v) => v
                .parse()
                .map_err(|_| format!("PORT={v:?} is not a port number"))?,
        };
        let public_url = req("PUBLIC_URL")?.trim_end_matches('/').to_string();
        if !public_url.starts_with("https://") && !public_url.starts_with("http://localhost") {
            return Err(format!(
                "PUBLIC_URL={public_url:?} must be https (or http://localhost for local runs)"
            ));
        }
        let mcp_client_ids = csv(&req("MCP_CLIENT_IDS")?);
        let allowed_subjects = csv(&req("ALLOWED_SUBJECTS")?);
        if mcp_client_ids.is_empty() || allowed_subjects.is_empty() {
            return Err(
                "MCP_CLIENT_IDS and ALLOWED_SUBJECTS must each name at least one id".into(),
            );
        }
        Ok(Settings {
            port,
            public_url,
            issuer: req("ISSUER")?.trim_end_matches('/').to_string(),
            project_id: req("PROJECT_ID")?,
            mcp_client_ids,
            connector_client_id: req("CONNECTOR_CLIENT_ID")?,
            allowed_subjects,
            jwks_uri: get("JWKS_URI")
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty()),
        })
    }

    pub fn mcp_url(&self) -> String {
        format!("{}/mcp", self.public_url)
    }

    pub fn resource_metadata_url(&self) -> String {
        format!(
            "{}/.well-known/oauth-protected-resource/mcp",
            self.public_url
        )
    }
}

/// RFC 9728 protected-resource metadata. `resource` must equal the MCP URL
/// exactly, and our issuer must be the first (only) authorization server:
/// Claude uses only the first entry.
pub fn protected_resource_metadata(s: &Settings) -> Value {
    json!({
        "resource": s.mcp_url(),
        "authorization_servers": [s.issuer],
        "scopes_supported": [
            "openid",
            "offline_access",
            format!("urn:zitadel:iam:org:project:id:{}:aud", s.project_id),
        ],
        "bearer_methods_supported": ["header"],
        "resource_name": "Relay spike",
    })
}

/// The `WWW-Authenticate` value on a 401, pointing clients at the metadata.
pub fn www_authenticate(s: &Settings, error: Option<&str>) -> String {
    match error {
        Some(e) => format!(
            "Bearer error=\"{e}\", resource_metadata=\"{}\"",
            s.resource_metadata_url()
        ),
        None => format!("Bearer resource_metadata=\"{}\"", s.resource_metadata_url()),
    }
}

/// Who a verified token belongs to, as the tools report it.
#[derive(Debug, Clone, PartialEq)]
pub struct Caller {
    pub subject: String,
    pub client_id: String,
}

fn tools() -> Value {
    json!([
        {
            "name": "echo",
            "description": "Returns the text you send. Proves a tool call reached the relay spike.",
            "inputSchema": {
                "type": "object",
                "properties": {"text": {"type": "string", "description": "Text to echo back"}},
                "required": ["text"],
                "additionalProperties": false
            },
            "annotations": {"readOnlyHint": true}
        },
        {
            "name": "whoami",
            "description": "Says which Zitadel user and OAuth client the call was made as.",
            "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false},
            "annotations": {"readOnlyHint": true}
        }
    ])
}

fn rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})
}

fn rpc_result(id: Value, result: Value) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "result": result})
}

fn text_result(text: String, is_error: bool) -> Value {
    json!({"content": [{"type": "text", "text": text}], "isError": is_error})
}

/// Handles one JSON-RPC message. Returns `None` for a notification (the HTTP
/// layer answers 202 with no body). Batches are not supported: current MCP
/// revisions removed them.
pub fn handle_rpc(body: &[u8], caller: &Caller) -> Option<Value> {
    let msg: Value = match serde_json::from_slice(body) {
        Ok(v) => v,
        Err(_) => return Some(rpc_error(Value::Null, -32700, "Parse error")),
    };
    if !msg.is_object() {
        return Some(rpc_error(
            Value::Null,
            -32600,
            "Invalid Request: send one JSON-RPC object",
        ));
    }
    let method = msg.get("method").and_then(Value::as_str);
    let id = msg.get("id").cloned();
    let Some(method) = method else {
        // A response or garbage from the client; nothing to answer.
        return id.map(|id| rpc_error(id, -32600, "Invalid Request: no method"));
    };
    let Some(id) = id else {
        // Notification (e.g. notifications/initialized): acknowledge, no body.
        return None;
    };
    let params = msg.get("params").cloned().unwrap_or(Value::Null);
    Some(match method {
        "initialize" => {
            let asked = params
                .get("protocolVersion")
                .and_then(Value::as_str)
                .unwrap_or("");
            let agreed = if PROTOCOL_VERSIONS.contains(&asked) {
                asked
            } else {
                PROTOCOL_VERSIONS[0]
            };
            rpc_result(
                id,
                json!({
                    "protocolVersion": agreed,
                    "capabilities": {"tools": {"listChanged": false}},
                    "serverInfo": {"name": SERVER_NAME, "version": env!("CARGO_PKG_VERSION")},
                    "instructions": "Relay P0 spike. Two read-only tools: echo and whoami."
                }),
            )
        }
        "ping" => rpc_result(id, json!({})),
        "tools/list" => rpc_result(id, json!({"tools": tools()})),
        "tools/call" => {
            let name = params.get("name").and_then(Value::as_str).unwrap_or("");
            let args = params.get("arguments").cloned().unwrap_or(json!({}));
            match name {
                "echo" => match args.get("text").and_then(Value::as_str) {
                    Some(t) => rpc_result(id, text_result(t.to_string(), false)),
                    None => rpc_result(id, text_result("echo needs a text argument".into(), true)),
                },
                "whoami" => rpc_result(
                    id,
                    text_result(
                        format!("subject {} via client {}", caller.subject, caller.client_id),
                        false,
                    ),
                ),
                _ => rpc_error(id, -32602, &format!("Unknown tool: {name}")),
            }
        }
        _ => rpc_error(id, -32601, &format!("Method not found: {method}")),
    })
}

/// True when an `Accept` header allows a JSON answer. Streamable HTTP clients
/// send `application/json, text/event-stream`; this server always answers JSON.
pub fn accepts_json(accept: Option<&str>) -> bool {
    match accept {
        None => true,
        Some(a) => a
            .split(',')
            .map(|p| p.split(';').next().unwrap_or("").trim())
            .any(|t| t == "application/json" || t == "application/*" || t == "*/*"),
    }
}

/// Picks which of several token checks applies, from the token's own
/// `client_id` claim, without trusting it: the chosen check still verifies
/// the signature and pins that same client id. Reads the unverified payload
/// only to route; returns None if it can't.
pub fn unverified_client_id(token: &str) -> Option<String> {
    let payload = token.split('.').nth(1)?;
    let bytes = b64url(payload)?;
    let v: Value = serde_json::from_slice(&bytes).ok()?;
    v.get("client_id").and_then(Value::as_str).map(String::from)
}

fn b64url(input: &str) -> Option<Vec<u8>> {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf: u32 = 0;
    let mut bits = 0u32;
    for c in input.bytes() {
        if c == b'=' {
            break;
        }
        let v = ALPHABET.iter().position(|&a| a == c)? as u32;
        buf = (buf << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn settings() -> Settings {
        let env: HashMap<&str, &str> = [
            ("PUBLIC_URL", "https://relay-spike.example.dev/"),
            ("ISSUER", "https://auth.example.dev/"),
            ("PROJECT_ID", "123"),
            ("MCP_CLIENT_IDS", "claude-id, ,chatgpt-id"),
            ("CONNECTOR_CLIENT_ID", "conn-id"),
            ("ALLOWED_SUBJECTS", "sub-1"),
        ]
        .into_iter()
        .collect();
        Settings::from_lookup(|k| env.get(k).map(|v| v.to_string())).unwrap()
    }

    fn caller() -> Caller {
        Caller {
            subject: "sub-1".into(),
            client_id: "claude-id".into(),
        }
    }

    #[test]
    fn settings_trim_and_default() {
        let s = settings();
        assert_eq!(s.port, 3000);
        assert_eq!(s.public_url, "https://relay-spike.example.dev");
        assert_eq!(s.issuer, "https://auth.example.dev");
        assert_eq!(s.mcp_client_ids, vec!["claude-id", "chatgpt-id"]);
    }

    #[test]
    fn settings_refuse_missing_or_unsafe_values() {
        let base: HashMap<&str, &str> = [
            ("PUBLIC_URL", "https://x.dev"),
            ("ISSUER", "https://auth.dev"),
            ("PROJECT_ID", "1"),
            ("MCP_CLIENT_IDS", "a"),
            ("CONNECTOR_CLIENT_ID", "c"),
            ("ALLOWED_SUBJECTS", "s"),
        ]
        .into_iter()
        .collect();
        for drop in [
            "PUBLIC_URL",
            "ISSUER",
            "PROJECT_ID",
            "MCP_CLIENT_IDS",
            "CONNECTOR_CLIENT_ID",
            "ALLOWED_SUBJECTS",
        ] {
            let r = Settings::from_lookup(|k| {
                if k == drop {
                    None
                } else {
                    base.get(k).map(|v| v.to_string())
                }
            });
            assert!(r.is_err(), "missing {drop} must be refused");
        }
        let r = Settings::from_lookup(|k| match k {
            "ALLOWED_SUBJECTS" => Some(" , ".into()),
            _ => base.get(k).map(|v| v.to_string()),
        });
        assert!(r.is_err(), "separators-only subject list must be refused");
        let r = Settings::from_lookup(|k| match k {
            "PUBLIC_URL" => Some("http://relay.example.dev".into()),
            _ => base.get(k).map(|v| v.to_string()),
        });
        assert!(r.is_err(), "plain http public URL must be refused");
    }

    #[test]
    fn metadata_matches_what_claude_requires() {
        let s = settings();
        let m = protected_resource_metadata(&s);
        assert_eq!(m["resource"], "https://relay-spike.example.dev/mcp");
        assert_eq!(m["authorization_servers"][0], "https://auth.example.dev");
        assert_eq!(m["authorization_servers"].as_array().unwrap().len(), 1);
        assert_eq!(
            www_authenticate(&s, None),
            "Bearer resource_metadata=\"https://relay-spike.example.dev/.well-known/oauth-protected-resource/mcp\""
        );
        assert!(www_authenticate(&s, Some("invalid_token"))
            .starts_with("Bearer error=\"invalid_token\", "));
    }

    #[test]
    fn initialize_agrees_a_known_version_or_offers_ours() {
        let r = handle_rpc(br#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#, &caller()).unwrap();
        assert_eq!(r["result"]["protocolVersion"], "2025-06-18");
        let r = handle_rpc(br#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#, &caller()).unwrap();
        assert_eq!(r["result"]["protocolVersion"], PROTOCOL_VERSIONS[0]);
        assert!(r["result"]["capabilities"]["tools"].is_object());
    }

    #[test]
    fn notifications_get_no_body() {
        assert!(handle_rpc(
            br#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            &caller()
        )
        .is_none());
    }

    #[test]
    fn tools_list_and_calls() {
        let r = handle_rpc(
            br#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#,
            &caller(),
        )
        .unwrap();
        let names: Vec<&str> = r["result"]["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["echo", "whoami"]);

        let r = handle_rpc(br#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#, &caller()).unwrap();
        assert_eq!(r["result"]["content"][0]["text"], "hi");
        assert_eq!(r["result"]["isError"], false);

        let r = handle_rpc(
            br#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whoami"}}"#,
            &caller(),
        )
        .unwrap();
        assert_eq!(
            r["result"]["content"][0]["text"],
            "subject sub-1 via client claude-id"
        );

        let r = handle_rpc(br#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo","arguments":{}}}"#, &caller()).unwrap();
        assert_eq!(r["result"]["isError"], true);

        let r = handle_rpc(
            br#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"rm"}}"#,
            &caller(),
        )
        .unwrap();
        assert_eq!(r["error"]["code"], -32602);
    }

    #[test]
    fn bad_input_gets_jsonrpc_errors() {
        assert_eq!(
            handle_rpc(b"not json", &caller()).unwrap()["error"]["code"],
            -32700
        );
        assert_eq!(
            handle_rpc(b"[1,2]", &caller()).unwrap()["error"]["code"],
            -32600
        );
        assert_eq!(
            handle_rpc(br#"{"jsonrpc":"2.0","id":1,"method":"nope"}"#, &caller()).unwrap()["error"]
                ["code"],
            -32601
        );
    }

    #[test]
    fn accept_header() {
        assert!(accepts_json(Some("application/json, text/event-stream")));
        assert!(accepts_json(Some("*/*")));
        assert!(accepts_json(None));
        assert!(!accepts_json(Some("text/event-stream")));
    }

    #[test]
    fn routes_on_unverified_client_id() {
        // header.payload.sig, payload = {"client_id":"claude-id","sub":"x"}
        let payload = "eyJjbGllbnRfaWQiOiJjbGF1ZGUtaWQiLCJzdWIiOiJ4In0";
        assert_eq!(
            unverified_client_id(&format!("e30.{payload}.sig")).as_deref(),
            Some("claude-id")
        );
        assert_eq!(unverified_client_id("garbage"), None);
        assert_eq!(unverified_client_id("a.!!!.c"), None);
    }
}
