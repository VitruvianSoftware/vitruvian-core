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

//! MCP for one device: JSON-RPC over Streamable HTTP, answered in JSON (no SSE
//! stream in P1). The HTTP layer has already checked the token, that the
//! caller owns the device, and the session; this module answers the message.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use tokio::sync::oneshot;
use vitruvian_mcp_auth::Caller;
use vitruvian_relay_protocol::Call;

use crate::registry::{CallError, Registry};
use crate::{log_event, random_id, LogSink};

/// The revisions `initialize` agrees to, newest first: the handshake-and-
/// session ones. The stateless revision is never agreed here; a client that
/// asks for it (or for anything unknown) is offered the newest of these.
pub const LEGACY_VERSIONS: &[&str] = &["2025-11-25", "2025-06-18", "2025-03-26"];
/// The stateless revisions (no initialize, no session): what `server/discover`
/// lists, and what a request's `_meta` may name.
pub const MODERN_VERSIONS: &[&str] = &["2026-07-28"];
const INSTRUCTIONS: &str =
    "Runs tools on the user's own computer through the Vitruvian Relay connector.";
/// How long a client may reuse a `server/discover` answer: it changes only
/// with a new relay release.
const DISCOVER_TTL_MS: u64 = 3_600_000;
pub const SERVER_NAME: &str = "vitruvian-relay";

/// Longest tool name written to the log; a name is not content, but it comes
/// from the caller, so it is capped.
const MAX_LOGGED_TOOL_CHARS: usize = 128;

fn server_info() -> Value {
    json!({"name": SERVER_NAME, "version": env!("CARGO_PKG_VERSION")})
}

/// No `listChanged`: P1 answers in JSON only, so there is no stream to push a
/// change on. AI apps see a new list on their next `tools/list`.
fn capabilities() -> Value {
    json!({"tools": {"listChanged": false}})
}

fn rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})
}

/// Every result says it is complete: MCP 2026-07-28 requires `resultType` on
/// all results, and older clients ignore a field they do not know.
fn rpc_result(id: Value, mut result: Value) -> Value {
    if let Some(r) = result.as_object_mut() {
        r.insert("resultType".into(), json!("complete"));
    }
    json!({"jsonrpc": "2.0", "id": id, "result": result})
}

/// Which way a request talks to the server.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Era {
    /// `initialize` first, then `Mcp-Session-Id` on each request.
    Legacy,
    /// MCP 2026-07-28: each request stands alone, naming its version in
    /// `params._meta` and the `MCP-Protocol-Version` header.
    Modern,
}

const META_VERSION: &str = "io.modelcontextprotocol/protocolVersion";

/// Sorts a request into its era from the version in `params._meta` and the
/// `MCP-Protocol-Version` header. Only modern requests carry the `_meta`
/// version, so its presence decides. `Err` is the JSON-RPC error to send with
/// a 400: `HeaderMismatch` (-32020) when the header names another version
/// (or names a modern one with no `_meta`), `UnsupportedProtocolVersion`
/// (-32022, with the versions served) for a modern version not served here.
/// A missing header with a valid `_meta` is accepted: the version is known
/// either way, and refusing it would only break a client that is lax.
pub fn era(req: &Value, header: Option<&str>) -> Result<Era, Value> {
    let id = req.get("id").cloned().unwrap_or(Value::Null);
    let meta = req
        .get("params")
        .and_then(|p| p.get("_meta"))
        .and_then(|m| m.get(META_VERSION))
        .and_then(Value::as_str);
    match (meta, header) {
        (None, Some(h)) if MODERN_VERSIONS.contains(&h) => Err(rpc_error(
            id,
            -32020,
            "Header mismatch: MCP-Protocol-Version names a version the request body does not",
        )),
        (None, _) => Ok(Era::Legacy),
        (Some(m), Some(h)) if m != h => Err(rpc_error(
            id,
            -32020,
            "Header mismatch: MCP-Protocol-Version differs from the version in _meta",
        )),
        (Some(m), _) if !MODERN_VERSIONS.contains(&m) => Err(json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": {
                "code": -32022,
                "message": format!("Unsupported protocol version: {m}"),
                "data": {"supported": MODERN_VERSIONS, "requested": m},
            },
        })),
        (Some(_), _) => Ok(Era::Modern),
    }
}

fn text_result(text: &str, is_error: bool) -> Value {
    json!({"content": [{"type": "text", "text": text}], "isError": is_error})
}

/// True for the methods that need no session: `initialize` makes one, and
/// `server/discover` describes the server without one.
pub fn needs_session(method: Option<&str>) -> bool {
    !matches!(method, Some("initialize") | Some("server/discover"))
}

/// A call in flight, found by (session id, JSON-RPC id): one chat can never
/// cancel another's call, even when both use the same JSON-RPC id.
struct InFlight {
    call_id: String,
    cancel: oneshot::Sender<()>,
}

type Key = (String, String);

pub struct Mcp {
    registry: Registry,
    call_budget: Duration,
    log: LogSink,
    in_flight: Mutex<HashMap<Key, InFlight>>,
}

/// Removes a call's entry when its request ends, however it ends.
struct InFlightEntry<'a> {
    map: &'a Mutex<HashMap<Key, InFlight>>,
    key: Option<Key>,
    call_id: String,
}

impl Drop for InFlightEntry<'_> {
    fn drop(&mut self) {
        if let Some(key) = &self.key {
            let mut map = self.map.lock().unwrap();
            // Only this call's entry: a cancel may already have taken it.
            if map.get(key).is_some_and(|f| f.call_id == self.call_id) {
                map.remove(key);
            }
        }
    }
}

/// The one log line per call. Written on drop, so a call whose HTTP request
/// was dropped mid-way is logged too (outcome `cancelled`). Sizes and names
/// only: never arguments or output (spec §7.2).
struct CallLog {
    log: LogSink,
    device_id: String,
    client_id: String,
    tool: String,
    arg_bytes: usize,
    result_bytes: usize,
    started: Instant,
    outcome: &'static str,
}

impl Drop for CallLog {
    fn drop(&mut self) {
        log_event(
            &self.log,
            "call",
            json!({
                "device_id": self.device_id,
                "client_id": self.client_id,
                "tool": self.tool,
                "arg_bytes": self.arg_bytes,
                "result_bytes": self.result_bytes,
                "duration_ms": self.started.elapsed().as_millis() as u64,
                "outcome": self.outcome,
            }),
        );
    }
}

fn outcome(e: CallError) -> &'static str {
    match e {
        CallError::Offline => "offline",
        CallError::Disconnected => "disconnected",
        CallError::NotReceived => "not_received",
        CallError::Deadline => "deadline",
        CallError::Duplicate => "duplicate",
    }
}

impl Mcp {
    pub fn new(registry: Registry, call_budget: Duration, log: LogSink) -> Self {
        Mcp {
            registry,
            call_budget,
            log,
            in_flight: Mutex::new(HashMap::new()),
        }
    }

    /// Answers one JSON-RPC message for `device_id`. `None` for a notification
    /// (the HTTP layer answers 202 with no body). Batches are not supported:
    /// current MCP revisions removed them.
    pub async fn handle(
        &self,
        req: &Value,
        device_id: &str,
        caller: &Caller,
        session: Option<&str>,
    ) -> Option<Value> {
        if !req.is_object() {
            return Some(rpc_error(
                Value::Null,
                -32600,
                "Invalid Request: send one JSON-RPC object",
            ));
        }
        let id = req.get("id").cloned();
        let params = req.get("params").cloned().unwrap_or(Value::Null);
        let Some(method) = req.get("method").and_then(Value::as_str) else {
            // A response from the client; nothing to answer.
            return id.map(|id| rpc_error(id, -32600, "Invalid Request: no method"));
        };
        let Some(id) = id else {
            if method == "notifications/cancelled" {
                self.cancel(session, params.get("requestId"));
            }
            return None;
        };
        Some(match method {
            "initialize" => {
                let asked = params
                    .get("protocolVersion")
                    .and_then(Value::as_str)
                    .unwrap_or("");
                let agreed = LEGACY_VERSIONS
                    .iter()
                    .find(|v| **v == asked)
                    .unwrap_or(&LEGACY_VERSIONS[0]);
                rpc_result(
                    id,
                    json!({
                        "protocolVersion": agreed,
                        "capabilities": capabilities(),
                        "serverInfo": server_info(),
                        "instructions": INSTRUCTIONS,
                    }),
                )
            }
            // Discover belongs to the stateless revision, so it lists only the
            // versions served that way; older ones are reached through
            // `initialize`. `serverInfo` is in `_meta`, where 2026-07-28 puts
            // it, and at the top level as before.
            "server/discover" => rpc_result(
                id,
                json!({
                    "supportedVersions": MODERN_VERSIONS,
                    "capabilities": capabilities(),
                    "serverInfo": server_info(),
                    "instructions": INSTRUCTIONS,
                    "_meta": {"io.modelcontextprotocol/serverInfo": server_info()},
                    "ttlMs": DISCOVER_TTL_MS,
                    "cacheScope": "public",
                }),
            ),
            "ping" => rpc_result(id, json!({})),
            "tools/list" => rpc_result(
                id,
                // The device's own tools: private to this person, and stale
                // as soon as the device reconnects with a different list.
                json!({
                    "tools": self.registry.tools(device_id).unwrap_or_default(),
                    "ttlMs": 0,
                    "cacheScope": "private",
                }),
            ),
            "tools/call" => self.call(id, &params, device_id, caller, session).await,
            _ => rpc_error(id, -32601, &format!("Method not found: {method}")),
        })
    }

    /// `notifications/cancelled`: stops that session's call with that id.
    fn cancel(&self, session: Option<&str>, request_id: Option<&Value>) {
        let (Some(session), Some(request_id)) = (session, request_id) else {
            return;
        };
        let key = (session.to_string(), request_id.to_string());
        if let Some(f) = self.in_flight.lock().unwrap().remove(&key) {
            // Ends the call's wait; dropping its registry future sends
            // `cancel { call_id }` to the device.
            let _ = f.cancel.send(());
        }
    }

    async fn call(
        &self,
        id: Value,
        params: &Value,
        device_id: &str,
        caller: &Caller,
        session: Option<&str>,
    ) -> Value {
        let Some(tool) = params
            .get("name")
            .and_then(Value::as_str)
            .filter(|n| !n.is_empty())
        else {
            return rpc_error(id, -32602, "Invalid params: tools/call needs a tool name");
        };
        let arguments = match params.get("arguments") {
            None | Some(Value::Null) => json!({}),
            Some(v @ Value::Object(_)) => v.clone(),
            Some(_) => return rpc_error(id, -32602, "Invalid params: arguments must be an object"),
        };
        let call_id = random_id();
        let (cancel_tx, mut cancel_rx) = oneshot::channel();
        let key = session.map(|s| (s.to_string(), id.to_string()));
        if let Some(key) = &key {
            let mut map = self.in_flight.lock().unwrap();
            if map.contains_key(key) {
                return rpc_error(id, -32600, "Invalid Request: this id is already running");
            }
            map.insert(
                key.clone(),
                InFlight {
                    call_id: call_id.clone(),
                    cancel: cancel_tx,
                },
            );
        }
        let _entry = InFlightEntry {
            map: &self.in_flight,
            key,
            call_id: call_id.clone(),
        };
        let mut log = CallLog {
            log: self.log.clone(),
            device_id: device_id.to_string(),
            client_id: caller.client_id.clone(),
            tool: tool.chars().take(MAX_LOGGED_TOOL_CHARS).collect(),
            arg_bytes: arguments.to_string().len(),
            result_bytes: 0,
            started: Instant::now(),
            outcome: "cancelled",
        };
        let call = Call {
            call_id,
            tool: tool.to_string(),
            arguments,
            deadline_ms: self.call_budget.as_millis() as u64,
        };
        // If the cancel wins, the registry's future is dropped here, which
        // sends `cancel` to the device. The same happens if this whole future
        // is dropped because the HTTP request went away.
        let outcome_ = tokio::select! {
            r = self.registry.call(device_id, call) => Some(r),
            Ok(()) = &mut cancel_rx => None,
        };
        match outcome_ {
            None => rpc_error(id, -32800, "Request cancelled"),
            Some(Ok(r)) => {
                log.result_bytes = r.content.to_string().len();
                log.outcome = if r.is_error { "tool_error" } else { "ok" };
                rpc_result(id, json!({"content": r.content, "isError": r.is_error}))
            }
            Some(Err(e)) => {
                log.outcome = outcome(e);
                rpc_result(id, text_result(e.user_message(), true))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use tokio::sync::mpsc;
    use vitruvian_relay_protocol::{CallResult, ToConnector, ToolDef};

    fn caller() -> Caller {
        Caller {
            subject: "alice".into(),
            client_id: "claude".into(),
        }
    }

    fn mcp() -> (Mcp, Registry) {
        let reg = Registry::new();
        let log: LogSink = Arc::new(|_| {});
        (
            Mcp::new(
                reg.clone(),
                Duration::from_secs(vitruvian_relay_protocol::CALL_BUDGET_SECS),
                log,
            ),
            reg,
        )
    }

    async fn ask(m: &Mcp, body: Value) -> Value {
        m.handle(&body, "d1", &caller(), Some("s1")).await.unwrap()
    }

    #[tokio::test]
    async fn initialize_agrees_a_known_version_or_offers_ours() {
        let (m, _) = mcp();
        for (asked, agreed) in [
            ("2025-06-18", "2025-06-18"),
            ("1999-01-01", LEGACY_VERSIONS[0]),
            // The handshake is the older revisions' way in; agreeing to the
            // stateless one here would leave a session whose every request
            // fails the header check.
            ("2026-07-28", LEGACY_VERSIONS[0]),
        ] {
            let r = ask(
                &m,
                json!({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                   "params": {"protocolVersion": asked}}),
            )
            .await;
            assert_eq!(r["result"]["protocolVersion"], agreed);
            assert_eq!(r["result"]["serverInfo"]["name"], SERVER_NAME);
        }
    }

    #[tokio::test]
    async fn bad_input_gets_jsonrpc_errors() {
        let (m, _) = mcp();
        assert_eq!(ask(&m, json!([1, 2])).await["error"]["code"], -32600);
        assert_eq!(
            ask(&m, json!({"jsonrpc": "2.0", "id": 1, "method": "nope"})).await["error"]["code"],
            -32601
        );
        assert_eq!(
            ask(
                &m,
                json!({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {}})
            )
            .await["error"]["code"],
            -32602
        );
        assert_eq!(
            ask(
                &m,
                json!({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                           "params": {"name": "t", "arguments": [1]}})
            )
            .await["error"]["code"],
            -32602
        );
        // A client's response (no method, no id) and notifications get no answer.
        assert!(m
            .handle(
                &json!({"jsonrpc": "2.0", "result": {}}),
                "d1",
                &caller(),
                None
            )
            .await
            .is_none());
        assert!(m
            .handle(
                &json!({"jsonrpc": "2.0", "method": "notifications/initialized"}),
                "d1",
                &caller(),
                None
            )
            .await
            .is_none());
    }

    #[test]
    fn only_initialize_and_discover_skip_the_session() {
        assert!(!needs_session(Some("initialize")));
        assert!(!needs_session(Some("server/discover")));
        for m in [
            Some("tools/list"),
            Some("tools/call"),
            Some("ping"),
            Some("notifications/cancelled"),
            None,
        ] {
            assert!(needs_session(m), "{m:?}");
        }
    }

    #[tokio::test]
    async fn a_reused_running_id_is_refused_and_the_tool_error_flag_passes_through() {
        let (m, reg) = mcp();
        let m = Arc::new(m);
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect(
            "d1",
            vec![ToolDef {
                name: "t".into(),
                description: "".into(),
                input_schema: json!({}),
            }],
            tx,
        );
        let body =
            json!({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "t"}});
        let first = {
            let (m, body) = (m.clone(), body.clone());
            tokio::spawn(async move { m.handle(&body, "d1", &caller(), Some("s1")).await.unwrap() })
        };
        let ToConnector::Call(call) = rx.recv().await.unwrap() else {
            panic!()
        };
        assert_eq!(call.arguments, json!({}));
        let again = ask(&m, body.clone()).await;
        assert_eq!(again["error"]["code"], -32600);
        // The same id in another session is fine (and goes to the device).
        let other = {
            let (m, body) = (m.clone(), body.clone());
            tokio::spawn(async move { m.handle(&body, "d1", &caller(), Some("s2")).await.unwrap() })
        };
        let ToConnector::Call(call2) = rx.recv().await.unwrap() else {
            panic!()
        };
        reg.complete(
            "d1",
            conn,
            CallResult {
                call_id: call.call_id,
                content: json!([]),
                is_error: true,
                truncated: false,
            },
        );
        reg.complete(
            "d1",
            conn,
            CallResult {
                call_id: call2.call_id,
                content: json!([]),
                is_error: false,
                truncated: false,
            },
        );
        assert_eq!(first.await.unwrap()["result"]["isError"], true);
        assert_eq!(other.await.unwrap()["result"]["isError"], false);
        // Finished calls leave nothing behind.
        assert!(m.in_flight.lock().unwrap().is_empty());
    }
}
