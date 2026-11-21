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
use vitruvian_relay_protocol::{
    Call, ToolDef, APPROVAL_REPLY_SECS, PARKED_RESULT_SECS, REJOIN_WINDOW_SECS,
};

use crate::parked::{
    CallHandle, Delivery, Fetch, Outcome, Owned, ParkedCalls, RejoinKey, RequestId, UNKNOWN_REQUEST,
};
use crate::registry::{CallError, Registry};
use crate::store::{STORE_UNAVAILABLE_OUTCOME, UNAVAILABLE_MESSAGE};
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

/// The relay's own tool, added to every device's list: fetches the result of
/// a request that was waiting for approval on the computer.
pub const CHECK_REQUEST: &str = "check_request";

fn check_request_def() -> ToolDef {
    ToolDef {
        name: CHECK_REQUEST.into(),
        description: "Get the result of a request that was waiting for approval on the computer."
            .into(),
        input_schema: json!({
            "type": "object",
            "properties": {
                "request_id": {
                    "type": "string",
                    "description": "The request_id from the waiting reply.",
                },
            },
            "required": ["request_id"],
        }),
    }
}

/// The reply that says a request is waiting for approval. `device` is the
/// computer's id until devices have names.
fn waiting_text(device: &str, id: &RequestId) -> String {
    format!(
        "Waiting for you to allow this on \"{device}\". Call {CHECK_REQUEST} with \
         request_id \"{}\" to get the result. The request is cancelled if nobody \
         answers within 60 seconds.",
        id.as_str()
    )
}

/// The reply to a `check_request` for a call that has not reported a dialog:
/// the computer is still on it, and nobody is being asked.
fn still_working_text(device: &str, id: &RequestId) -> String {
    format!(
        "Still working on this on \"{device}\". Call {CHECK_REQUEST} with \
         request_id \"{}\" again to get the result.",
        id.as_str()
    )
}

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

/// A reply, and the delivery to commit once it has been written out (a
/// result for the AI app; see [`Delivery`]).
pub struct Answer {
    pub value: Value,
    pub delivery: Option<Delivery>,
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
    parked: ParkedCalls,
    /// How long a request waits for an approval dialog before it answers
    /// "waiting" (and how long each `check_request` waits).
    approval_reply: Duration,
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
/// was dropped mid-way is logged too (outcome `parked`: the call goes on).
/// Sizes and names only: never arguments or output (spec §7.2).
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
        CallError::Revoked => "revoked",
    }
}

impl Mcp {
    pub fn new(registry: Registry, call_budget: Duration, log: LogSink) -> Self {
        Mcp {
            registry,
            call_budget,
            log,
            in_flight: Mutex::new(HashMap::new()),
            parked: ParkedCalls::new(
                Duration::from_secs(REJOIN_WINDOW_SECS),
                Duration::from_secs(PARKED_RESULT_SECS),
            ),
            approval_reply: Duration::from_secs(APPROVAL_REPLY_SECS),
        }
    }

    /// The parking timers, shortened for tests: how long a request waits
    /// for an approval before it answers "waiting", how long an identical
    /// request can still join a call, and how long a result is kept.
    pub fn with_parking(
        mut self,
        approval_reply: Duration,
        rejoin_window: Duration,
        result_ttl: Duration,
    ) -> Self {
        self.approval_reply = approval_reply;
        self.parked = ParkedCalls::new(rejoin_window, result_ttl);
        self
    }

    /// Answers one JSON-RPC message for `device_id`, counting a result as
    /// handed over at once. For callers with no response to write.
    pub async fn handle(
        &self,
        req: &Value,
        device_id: &str,
        caller: &Caller,
        session: Option<&str>,
    ) -> Option<Value> {
        let answer = self.handle_tracked(req, device_id, caller, session).await?;
        if let Some(d) = answer.delivery {
            d.commit();
        }
        Some(answer.value)
    }

    /// Answers one JSON-RPC message for `device_id`. `None` for a notification
    /// (the HTTP layer answers 202 with no body). Batches are not supported:
    /// current MCP revisions removed them. A result carries a [`Delivery`]
    /// for the caller to commit once the response is written out.
    pub async fn handle_tracked(
        &self,
        req: &Value,
        device_id: &str,
        caller: &Caller,
        session: Option<&str>,
    ) -> Option<Answer> {
        let mut delivery = None;
        let value = self
            .answer(req, device_id, caller, session, &mut delivery)
            .await?;
        Some(Answer { value, delivery })
    }

    async fn answer(
        &self,
        req: &Value,
        device_id: &str,
        caller: &Caller,
        session: Option<&str>,
        delivery: &mut Option<Delivery>,
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
                // The device's own tools, and the relay's: private to this
                // person, and stale as soon as the device reconnects with a
                // different list.
                json!({
                    "tools": self.tools(device_id),
                    "ttlMs": 0,
                    "cacheScope": "private",
                }),
            ),
            "tools/call" => {
                self.call(id, &params, device_id, caller, session, delivery)
                    .await
            }
            _ => rpc_error(id, -32601, &format!("Method not found: {method}")),
        })
    }

    /// The answer to a request the relay could not even start because the
    /// database is not answering. A `tools/call` gets a normal tool result,
    /// marked as an error, that says what to do (the AI app shows it to the
    /// person), and is logged like any call with the outcome
    /// `store_unavailable`. Anything else gets `None`, and the HTTP layer
    /// answers 503 with the same words.
    pub fn store_unavailable_call(
        &self,
        req: &Value,
        device_id: &str,
        caller: &Caller,
    ) -> Option<Value> {
        if req.get("method").and_then(Value::as_str) != Some("tools/call") {
            return None;
        }
        let id = req.get("id").cloned()?;
        let params = req.get("params").cloned().unwrap_or(Value::Null);
        let tool = params.get("name").and_then(Value::as_str).unwrap_or("");
        let arg_bytes = params.get("arguments").map_or(0, |a| a.to_string().len());
        let result = text_result(UNAVAILABLE_MESSAGE, true);
        // Written when this drops, at the end of the function.
        let _log = CallLog {
            log: self.log.clone(),
            device_id: device_id.to_string(),
            client_id: caller.client_id.clone(),
            tool: tool.chars().take(MAX_LOGGED_TOOL_CHARS).collect(),
            arg_bytes,
            result_bytes: result["content"].to_string().len(),
            started: Instant::now(),
            outcome: STORE_UNAVAILABLE_OUTCOME,
        };
        Some(rpc_result(id, result))
    }

    /// The device's tools with the relay's `check_request` after them. A
    /// device tool of the same name is dropped (and the drop logged): the
    /// relay answers that name itself.
    fn tools(&self, device_id: &str) -> Vec<ToolDef> {
        let mut tools = self.registry.tools(device_id).unwrap_or_default();
        let before = tools.len();
        tools.retain(|t| t.name != CHECK_REQUEST);
        if tools.len() != before {
            log_event(
                &self.log,
                "tool_dropped",
                json!({"device_id": device_id, "tool": CHECK_REQUEST,
                       "reason": "the relay's own tool has that name"}),
            );
        }
        tools.push(check_request_def());
        tools
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
        delivery: &mut Option<Delivery>,
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
        let mut log = CallLog {
            log: self.log.clone(),
            device_id: device_id.to_string(),
            client_id: caller.client_id.clone(),
            tool: tool.chars().take(MAX_LOGGED_TOOL_CHARS).collect(),
            arg_bytes: arguments.to_string().len(),
            result_bytes: 0,
            started: Instant::now(),
            // A request that ends without an answer left its call running:
            // it is parked, for the retry to find.
            outcome: "parked",
        };
        if tool == CHECK_REQUEST {
            return self
                .check_request(id, &arguments, caller, &mut log, delivery)
                .await;
        }
        let (cancel_tx, mut cancel_rx) = oneshot::channel();
        let key = session.map(|s| (s.to_string(), id.to_string()));
        let rejoin_key = RejoinKey::new(&caller.subject, device_id, tool, &arguments);
        let started = log.started;
        let call_id = random_id();
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
        // One call per (person, device, tool, arguments) at a time: an
        // identical request joins the call that is open (or finished and not
        // yet handed over) instead of starting another. This holds for the
        // sessionless revision too, which has no request id to check.
        let joined = self
            .parked
            .join_or_park(rejoin_key, &caller.subject, device_id, || {
                CallHandle::start(
                    &self.registry,
                    device_id,
                    Call {
                        call_id,
                        tool: tool.to_string(),
                        arguments,
                        deadline_ms: self.call_budget.as_millis() as u64,
                    },
                )
            });
        let mut waiting = Waiting {
            parked: &self.parked,
            id: joined.request_id.clone(),
            handle: joined.handle.clone(),
            settled: false,
        };
        // The call has its own task: if this request is dropped (the AI app
        // gave up), the call goes on, parked. Only a cancel stops it.
        let reply_at = tokio::time::Instant::from_std(started + self.approval_reply);
        enum Ended {
            Cancelled,
            Finished(Outcome),
            // A dialog is open and the AI app's patience is running out.
            Approval,
        }
        let ended = tokio::select! {
            biased;
            Ok(()) = &mut cancel_rx => Ended::Cancelled,
            f = joined.handle.finished() => Ended::Finished(f.result.clone()),
            () = async {
                tokio::time::sleep_until(reply_at).await;
                joined.handle.approval_open().await;
            } => Ended::Approval,
        };
        match ended {
            Ended::Cancelled => {
                log.outcome = "cancelled";
                waiting.cancel();
                rpc_error(id, -32800, "Request cancelled")
            }
            Ended::Approval => {
                // A request that joined another's call says so, whatever
                // it was then told.
                log.outcome = if joined.rejoined {
                    "rejoined"
                } else {
                    "waiting_approval"
                };
                waiting.park();
                rpc_result(
                    id,
                    text_result(&waiting_text(device_id, &joined.request_id), false),
                )
            }
            Ended::Finished(outcome_) => {
                *delivery = Some(waiting.deliver());
                match outcome_ {
                    Ok(r) => {
                        log.result_bytes = r.content.to_string().len();
                        log.outcome = if r.is_error { "tool_error" } else { "ok" };
                        if joined.rejoined {
                            log.outcome = "rejoined";
                        }
                        rpc_result(id, json!({"content": r.content, "isError": r.is_error}))
                    }
                    Err(e) => {
                        log.outcome = if joined.rejoined {
                            "rejoined"
                        } else {
                            outcome(e)
                        };
                        rpc_result(id, text_result(e.user_message(), true))
                    }
                }
            }
        }
    }

    /// The relay's own `check_request` tool: the result of a request that
    /// was waiting for approval. Waits up to `approval_reply` for it.
    async fn check_request(
        &self,
        id: Value,
        arguments: &Value,
        caller: &Caller,
        log: &mut CallLog,
        delivery: &mut Option<Delivery>,
    ) -> Value {
        let Some(request_id) = arguments.get("request_id").and_then(Value::as_str) else {
            return rpc_error(
                id,
                -32602,
                "Invalid params: check_request needs a request_id",
            );
        };
        let request_id = RequestId::parse(request_id);
        // An id that is not this person's gets the answer for an id that
        // never was.
        let Some(owned) = self.owned_request(&caller.subject, &request_id) else {
            log.outcome = "unknown_request";
            return rpc_result(id, text_result(UNKNOWN_REQUEST, true));
        };
        match self
            .parked
            .take(&caller.subject, &request_id, self.approval_reply)
            .await
        {
            Fetch::Done(done) => {
                *delivery = Some(self.parked.delivery(&request_id));
                match done {
                    Ok(r) => {
                        log.result_bytes = r.content.to_string().len();
                        log.outcome = if r.is_error { "tool_error" } else { "ok" };
                        rpc_result(id, json!({"content": r.content, "isError": r.is_error}))
                    }
                    Err(e) => {
                        log.outcome = outcome(e);
                        rpc_result(id, text_result(e.user_message(), true))
                    }
                }
            }
            Fetch::Waiting => {
                // Only a call whose device reported a dialog is "waiting for
                // you": one that never did is still being worked on.
                let text = if owned.handle().approval_reported() {
                    log.outcome = "waiting_approval";
                    waiting_text(&owned.device_id, &request_id)
                } else {
                    log.outcome = "still_working";
                    still_working_text(&owned.device_id, &request_id)
                };
                rpc_result(id, text_result(&text, false))
            }
            // Expired while it was waited for.
            Fetch::Unknown => {
                log.outcome = "unknown_request";
                rpc_result(id, text_result(UNKNOWN_REQUEST, true))
            }
        }
    }

    /// The single check that a request id is `subject`'s. Everything that
    /// names a request by id (`check_request`, the device in its waiting
    /// text) goes through it, so none can answer for someone else's.
    fn owned_request(&self, subject: &str, request_id: &RequestId) -> Option<Owned> {
        self.parked.owned(subject, request_id)
    }
}

/// One request's hold on a call. If the request ends without an answer (the
/// AI app dropped it) the call is parked, for an identical request or
/// `check_request` to pick up.
struct Waiting<'a> {
    parked: &'a ParkedCalls,
    id: RequestId,
    handle: CallHandle,
    settled: bool,
}

impl Waiting<'_> {
    /// The answer is going to the request. It counts as handed over when
    /// the returned [`Delivery`] is committed (the response written out),
    /// not before: a response that never gets out leaves the result for the
    /// retry.
    fn deliver(&mut self) -> Delivery {
        self.settled = true;
        self.handle.detach();
        self.parked.delivery(&self.id)
    }

    /// The request answers "waiting" and lets go; the id is out, so the
    /// call stays for `check_request`.
    fn park(&mut self) {
        self.settled = true;
        self.parked.keep(&self.id);
        self.handle.detach();
    }

    /// The AI app cancelled: the call stops (unless another request is on it).
    fn cancel(&mut self) {
        self.settled = true;
        self.parked.cancel(&self.id, &self.handle);
    }
}

impl Drop for Waiting<'_> {
    fn drop(&mut self) {
        if !self.settled {
            self.park();
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
        // The same id in another session is fine (and goes to the device: it
        // asks for something else, since an identical call would join the
        // one running).
        let other = {
            let body = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                              "params": {"name": "t", "arguments": {"other": true}}});
            let m = m.clone();
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

    /// Final review, Minor 4: `check_request` says "waiting for you" only
    /// for a call whose device reported a dialog.
    #[tokio::test]
    async fn check_request_says_still_working_for_a_call_with_no_dialog() {
        let reg = Registry::new();
        let log: LogSink = Arc::new(|_| {});
        let m = Mcp::new(reg.clone(), Duration::from_secs(60), log).with_parking(
            Duration::from_millis(50),
            Duration::from_secs(30),
            Duration::from_secs(30),
        );
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        // Two calls the relay holds for alice, as parked ones are.
        let mut ids = Vec::new();
        let mut call_ids = Vec::new();
        for (n, tool) in ["a", "b"].into_iter().enumerate() {
            let args = json!({"n": n});
            let handle = CallHandle::start(
                &reg,
                "d1",
                Call {
                    call_id: format!("c{n}"),
                    tool: tool.into(),
                    arguments: args.clone(),
                    deadline_ms: 60_000,
                },
            );
            let ToConnector::Call(c) = rx.recv().await.unwrap() else {
                panic!()
            };
            call_ids.push(c.call_id);
            ids.push(m.parked.park(
                RejoinKey::new("alice", "d1", tool, &args),
                "alice",
                "d1",
                handle,
            ));
        }
        // The second one's device reports a dialog.
        assert!(reg.pending(conn, &call_ids[1]));
        let check = |id: &RequestId| {
            json!({"jsonrpc": "2.0", "id": 9, "method": "tools/call",
                   "params": {"name": CHECK_REQUEST, "arguments": {"request_id": id.as_str()}}})
        };
        let r = ask(&m, check(&ids[0])).await;
        assert_eq!(r["result"]["isError"], false);
        assert_eq!(
            r["result"]["content"][0]["text"],
            format!(
                "Still working on this on \"d1\". Call check_request with request_id \"{}\" \
                 again to get the result.",
                ids[0].as_str()
            )
        );
        let r = ask(&m, check(&ids[1])).await;
        let text = r["result"]["content"][0]["text"].as_str().unwrap();
        assert!(
            text.starts_with("Waiting for you to allow this on \"d1\"."),
            "{text}"
        );
    }
}
