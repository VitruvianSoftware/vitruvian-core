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

//! Streamable HTTP transport (MCP), served by hyper 1 on tokio.
//!
//! The spec is the TypeScript server this replaced (`httpTransport.ts` /
//! `index.ts` before #3985) running `@modelcontextprotocol/sdk` 1.32.1's
//! `StreamableHTTPServerTransport` in stateless mode with its defaults
//! (`enableJsonResponse: false`, 4 MiB body cap, 100-message batches, 15 s SSE
//! keep-alive) on Node's `http` server (16 KiB headers, 60 s header timeout,
//! 300 s request timeout). Status codes, headers, bodies and JSON-RPC error
//! codes/messages below were taken from a live probe of that SDK, not from
//! reading it alone.
//!
//! Blocking work — token verification (it may fetch the issuer's JWKS) and
//! tool handlers (HTTPS to Slack) — runs on tokio's blocking pool, never on a
//! reactor thread. Every request runs in its own task so a panic anywhere in
//! it becomes a 500 (or a JSON-RPC error once an SSE stream has started)
//! instead of a hung or leaked connection.

use crate::auth::{audience_scope_for, AuthError, TokenVerifier};
use crate::config::HttpConfig;
use crate::dispatch::dispatch;
use crate::json::JsonValue;
use crate::slack_client::SlackClient;
use crate::tools::ToolDefinition;
use bytes::Bytes;
use http::{HeaderMap, HeaderValue, Method, Request, Response, StatusCode, Uri};
use http_body_util::combinators::UnsyncBoxBody;
use http_body_util::{BodyExt, Empty, Full, LengthLimitError, Limited};
use hyper::body::{Body, Frame, Incoming};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::{TokioIo, TokioTimer};
use std::collections::{HashMap, HashSet};
use std::convert::Infallible;
use std::future::Future;
use std::io::Write;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::{Duration, Instant};
use tokio::net::TcpListener;
use tokio::sync::{mpsc, watch, Notify, Semaphore};

const MCP_PATH: &str = "/mcp";
const HEALTH_PATH: &str = "/health";
const OAUTH_PROTECTED_RESOURCE_PATH: &str = "/.well-known/oauth-protected-resource";

/// SDK `DEFAULT_MAX_REQUEST_BODY_SIZE`.
pub const MAX_REQUEST_BODY_SIZE: usize = 4 * 1024 * 1024;
/// SDK `MAX_BATCH_SIZE`.
pub const MAX_BATCH_SIZE: usize = 100;
/// SDK `LATEST_PROTOCOL_VERSION`.
pub const LATEST_PROTOCOL_VERSION: &str = "2025-11-25";
/// SDK `SUPPORTED_PROTOCOL_VERSIONS`, in the SDK's order (it appears in an error message).
pub const SUPPORTED_PROTOCOL_VERSIONS: [&str; 5] = [
    LATEST_PROTOCOL_VERSION,
    "2025-06-18",
    "2025-03-26",
    "2024-11-05",
    "2024-10-07",
];
/// What TS `close()` defaulted to; the chart overrides it via SHUTDOWN_GRACE_MS.
pub const DEFAULT_SHUTDOWN_GRACE_MS: u64 = 10_000;

/// The serverInfo the TS server hard-coded (index.ts).
pub const SERVER_NAME: &str = "mcp-slack";
pub const SERVER_VERSION: &str = "2.0.0";

static STDERR_SINKS: Mutex<Vec<Arc<Mutex<Vec<String>>>>> = Mutex::new(Vec::new());

pub struct StderrCaptureGuard {
    sink: Arc<Mutex<Vec<String>>>,
}

impl StderrCaptureGuard {
    pub fn lines(&self) -> Vec<String> {
        self.sink.lock().unwrap().clone()
    }
}

impl Drop for StderrCaptureGuard {
    fn drop(&mut self) {
        if let Ok(mut sinks) = STDERR_SINKS.lock() {
            sinks.retain(|s| !Arc::ptr_eq(s, &self.sink));
        }
    }
}

pub fn capture_stderr() -> StderrCaptureGuard {
    let sink = Arc::new(Mutex::new(Vec::new()));
    STDERR_SINKS.lock().unwrap().push(sink.clone());
    StderrCaptureGuard { sink }
}

fn write_stderr(line: &str) {
    let _ = std::io::stderr().write_all(line.as_bytes());
    if let Ok(sinks) = STDERR_SINKS.lock() {
        for sink in sinks.iter() {
            if let Ok(mut guard) = sink.lock() {
                guard.push(line.to_string());
            }
        }
    }
}

/// Makes a message safe to carry inside an RFC 7235 quoted-string.
pub fn header_safe(message: &str) -> String {
    let mut sanitized = String::with_capacity(message.len());
    let mut last_was_non_printable = false;
    for ch in message.chars() {
        if ch == '"' {
            sanitized.push('\'');
            last_was_non_printable = false;
        } else if ('\x20'..='\x7e').contains(&ch) {
            sanitized.push(ch);
            last_was_non_printable = false;
        } else if !last_was_non_printable {
            sanitized.push(' ');
            last_was_non_printable = true;
        }
    }
    let mut collapsed = String::with_capacity(sanitized.len());
    let mut prev_space = false;
    for ch in sanitized.chars() {
        if ch.is_whitespace() {
            if !prev_space {
                collapsed.push(' ');
                prev_space = true;
            }
        } else {
            collapsed.push(ch);
            prev_space = false;
        }
    }
    collapsed.trim().to_string()
}

pub fn get_request_origin(headers: &HashMap<String, String>, is_encrypted: bool) -> String {
    let raw_host = headers
        .get("x-forwarded-host")
        .filter(|s| !s.is_empty())
        .cloned()
        .or_else(|| headers.get("host").filter(|s| !s.is_empty()).cloned())
        .or_else(|| {
            std::env::var("MCP_PUBLIC_HOST")
                .ok()
                .filter(|s| !s.is_empty())
        })
        .unwrap_or_else(|| "localhost".to_string());

    let host = if let Some(stripped) = raw_host.strip_suffix(":80") {
        stripped.to_string()
    } else if let Some(stripped) = raw_host.strip_suffix(":443") {
        stripped.to_string()
    } else {
        raw_host
    };

    let is_local = host.starts_with("localhost")
        || host.starts_with("127.0.0.1")
        || host.starts_with("::1")
        || host.starts_with("0.0.0.0");

    let proto = if !is_local {
        "https".to_string()
    } else {
        headers
            .get("x-forwarded-proto")
            .filter(|s| !s.is_empty())
            .cloned()
            .unwrap_or_else(|| {
                if is_encrypted {
                    "https".to_string()
                } else {
                    "http".to_string()
                }
            })
    };

    format!("{proto}://{host}")
}

// ---------------------------------------------------------------------------
// Header views: Node's `req.headers` (what the TS code read) and WHATWG
// `Headers` (what the SDK read, via @hono/node-server).
// ---------------------------------------------------------------------------

/// Node decodes header bytes as latin1; so do we, so a non-ASCII byte is a
/// character to reject later, not a reason to drop the header.
fn latin1(value: &HeaderValue) -> String {
    value.as_bytes().iter().map(|&b| b as char).collect()
}

/// Headers whose duplicates Node discards, keeping the first (`matchKnownFields`).
const NODE_FIRST_WINS: [&str; 18] = [
    "age",
    "authorization",
    "content-length",
    "content-type",
    "etag",
    "expires",
    "from",
    "host",
    "if-modified-since",
    "if-unmodified-since",
    "last-modified",
    "location",
    "max-forwards",
    "proxy-authorization",
    "referer",
    "retry-after",
    "server",
    "user-agent",
];

/// Node's `req.headers`: first value for the discard list, `; `-joined
/// cookies, `, `-joined everything else.
pub fn node_headers(map: &HeaderMap) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for name in map.keys() {
        let key = name.as_str();
        let values: Vec<String> = map.get_all(name).iter().map(latin1).collect();
        let value = if NODE_FIRST_WINS.contains(&key) {
            values.into_iter().next().unwrap_or_default()
        } else if key == "cookie" {
            values.join("; ")
        } else {
            values.join(", ")
        };
        out.insert(key.to_string(), value);
    }
    out
}

/// WHATWG `Headers.get`: all values joined with `, `.
fn web_header(map: &HeaderMap, name: &str) -> Option<String> {
    let values: Vec<String> = map.get_all(name).iter().map(latin1).collect();
    if values.is_empty() {
        None
    } else {
        Some(values.join(", "))
    }
}

fn is_token_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || "!#$%&'*+.^_`|~-".contains(c)
}

fn is_token(s: &str) -> bool {
    !s.is_empty() && s.chars().all(is_token_char)
}

/// Whether the parameter section after the media type parses under the
/// `content-type` package's grammar (`; *token *= *(token|quoted) *`).
fn content_type_params_valid(rest: &str) -> bool {
    let b: Vec<char> = rest.chars().collect();
    let mut i = 0;
    let skip_spaces = |i: &mut usize| {
        while *i < b.len() && b[*i] == ' ' {
            *i += 1;
        }
    };
    while i < b.len() {
        if b[i] != ';' {
            return false;
        }
        i += 1;
        skip_spaces(&mut i);
        let start = i;
        while i < b.len() && is_token_char(b[i]) {
            i += 1;
        }
        if i == start {
            return false;
        }
        skip_spaces(&mut i);
        if i >= b.len() || b[i] != '=' {
            return false;
        }
        i += 1;
        skip_spaces(&mut i);
        if i < b.len() && b[i] == '"' {
            i += 1;
            loop {
                if i >= b.len() {
                    return false;
                }
                match b[i] {
                    '"' => {
                        i += 1;
                        break;
                    }
                    '\\' => i += 2,
                    _ => i += 1,
                }
            }
        } else {
            let vstart = i;
            while i < b.len() && is_token_char(b[i]) {
                i += 1;
            }
            if i == vstart {
                return false;
            }
        }
        skip_spaces(&mut i);
    }
    true
}

/// SDK `isJsonContentType` (shared/mediaType.js): the parsed media type, never
/// a substring match.
pub fn is_json_content_type(header: Option<&str>) -> bool {
    let header = match header {
        Some(h) if !h.is_empty() => h,
        _ => return false,
    };
    if header == "application/json" {
        return true;
    }
    let first = header.split(';').next().unwrap_or("");
    let essence = first.trim().to_ascii_lowercase();
    if essence != "application/json" {
        return false;
    }
    // Strict parse first; on a malformed parameter section the SDK falls back
    // to the bare essence unless a comma follows it.
    let rest = &header[first.len()..];
    let strict_ok = is_token_split(&essence) && content_type_params_valid(rest.trim_end());
    if strict_ok {
        return true;
    }
    let after = header.get(essence.len()..).unwrap_or("");
    !after.contains(',')
}

fn is_token_split(essence: &str) -> bool {
    match essence.split_once('/') {
        Some((t, s)) => is_token(t) && is_token(s),
        None => false,
    }
}

/// `new URL(req.url, base).pathname` for the shapes that can reach us:
/// absolute-form, `//authority` relative references, backslashes (a special
/// scheme treats them as `/`), and `.`/`..` segments including `%2e` spellings.
pub fn whatwg_pathname(uri: &Uri) -> String {
    let mut s = uri.path().replace('\\', "/");
    if uri.scheme().is_none() && s.starts_with("//") {
        let rest = &s[2..];
        s = match rest.find('/') {
            Some(i) => rest[i..].to_string(),
            None => "/".to_string(),
        };
    }
    if !s.starts_with('/') {
        s.insert(0, '/');
    }
    let segments: Vec<&str> = s[1..].split('/').collect();
    let mut out: Vec<&str> = Vec::new();
    for (i, seg) in segments.iter().enumerate() {
        let last = i + 1 == segments.len();
        let lower = seg.to_ascii_lowercase();
        if matches!(lower.as_str(), ".." | ".%2e" | "%2e." | "%2e%2e") {
            out.pop();
            if last {
                out.push("");
            }
        } else if matches!(lower.as_str(), "." | "%2e") {
            if last {
                out.push("");
            }
        } else {
            out.push(seg);
        }
    }
    format!("/{}", out.join("/"))
}

// ---------------------------------------------------------------------------
// JSON-RPC message validation (SDK JSONRPCMessageSchema, all members strict)
// ---------------------------------------------------------------------------

/// JSON.parse keeps the last value of a duplicated key, at the first key's position.
fn dedup_keys(value: JsonValue) -> JsonValue {
    match value {
        JsonValue::Object(entries) => {
            let mut out: Vec<(String, JsonValue)> = Vec::with_capacity(entries.len());
            for (k, v) in entries {
                let v = dedup_keys(v);
                if let Some(existing) = out.iter_mut().find(|(ek, _)| *ek == k) {
                    existing.1 = v;
                } else {
                    out.push((k, v));
                }
            }
            JsonValue::Object(out)
        }
        JsonValue::Array(items) => JsonValue::Array(items.into_iter().map(dedup_keys).collect()),
        other => other,
    }
}

const MAX_SAFE_INTEGER: f64 = 9_007_199_254_740_991.0;

fn is_safe_int(v: &JsonValue) -> bool {
    match v {
        JsonValue::Number(n) => n.is_finite() && n.fract() == 0.0 && n.abs() <= MAX_SAFE_INTEGER,
        _ => false,
    }
}

/// `RequestIdSchema` / `ProgressTokenSchema`: string or integer.
fn is_request_id(v: &JsonValue) -> bool {
    matches!(v, JsonValue::String(_)) || is_safe_int(v)
}

/// `RequestMetaSchema`, the only constraint the envelope puts on `params`.
fn meta_valid(params: &JsonValue) -> bool {
    match params.get("_meta") {
        None => true,
        Some(meta @ JsonValue::Object(_)) => {
            let token_ok = meta.get("progressToken").map_or(true, is_request_id);
            let task_ok = match meta.get("io.modelcontextprotocol/related-task") {
                None => true,
                Some(t @ JsonValue::Object(_)) => {
                    matches!(t.get("taskId"), Some(JsonValue::String(_)))
                }
                Some(_) => false,
            };
            token_ok && task_ok
        }
        Some(_) => false,
    }
}

fn params_valid(params: Option<&JsonValue>) -> bool {
    match params {
        None => true,
        Some(p @ JsonValue::Object(_)) => meta_valid(p),
        Some(_) => false,
    }
}

/// One validated JSON-RPC message.
#[derive(Debug, Clone, PartialEq)]
pub enum JsonRpcMessage {
    Request {
        id: JsonValue,
        method: String,
        params: Option<JsonValue>,
    },
    Notification {
        method: String,
        params: Option<JsonValue>,
    },
    /// A result or error response from the client; nothing here ever awaits one.
    Response,
}

impl JsonRpcMessage {
    fn is_initialize(&self) -> bool {
        match self {
            JsonRpcMessage::Request { method, params, .. }
            | JsonRpcMessage::Notification { method, params } => {
                method == "initialize" && initialize_issues(params.as_ref()).is_empty()
            }
            JsonRpcMessage::Response => false,
        }
    }
}

fn keys_within(entries: &[(String, JsonValue)], allowed: &[&str]) -> bool {
    entries.iter().all(|(k, _)| allowed.contains(&k.as_str()))
}

/// SDK `JSONRPCMessageSchema.parse`; `None` where it would throw.
pub fn classify_message(value: &JsonValue) -> Option<JsonRpcMessage> {
    let entries = value.as_object()?;
    if value.get("jsonrpc").and_then(|v| v.as_str()) != Some("2.0") {
        return None;
    }
    let method = value.get("method");
    let params = value.get("params");
    let id = value.get("id");

    // JSONRPCRequestSchema (strict)
    if let (Some(JsonValue::String(m)), Some(id)) = (method, id) {
        if keys_within(entries, &["jsonrpc", "id", "method", "params"])
            && is_request_id(id)
            && params_valid(params)
        {
            return Some(JsonRpcMessage::Request {
                id: id.clone(),
                method: m.clone(),
                params: params.cloned(),
            });
        }
    }
    // JSONRPCNotificationSchema (strict)
    if let Some(JsonValue::String(m)) = method {
        if keys_within(entries, &["jsonrpc", "method", "params"]) && params_valid(params) {
            return Some(JsonRpcMessage::Notification {
                method: m.clone(),
                params: params.cloned(),
            });
        }
    }
    // JSONRPCResultResponseSchema (strict)
    if let (Some(result @ JsonValue::Object(_)), Some(id)) = (value.get("result"), id) {
        if keys_within(entries, &["jsonrpc", "id", "result"])
            && is_request_id(id)
            && meta_valid(result)
        {
            return Some(JsonRpcMessage::Response);
        }
    }
    // JSONRPCErrorResponseSchema (strict, id optional)
    if let Some(err @ JsonValue::Object(_)) = value.get("error") {
        let id_ok = id.map_or(true, is_request_id);
        let code_ok = err.get("code").map_or(false, is_safe_int);
        let msg_ok = matches!(err.get("message"), Some(JsonValue::String(_)));
        if keys_within(entries, &["jsonrpc", "id", "error"]) && id_ok && code_ok && msg_ok {
            return Some(JsonRpcMessage::Response);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Handler-level validation. The SDK parses each request with zod before the
// handler runs; a failure is a ZodError with no numeric `code`, which the
// SDK answers as -32603 with the ZodError's message: JSON.stringify(issues,
// null, 2). Reproduced for the fields our handlers read.
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
struct Issue {
    expected: &'static str,
    path: Vec<&'static str>,
    received: &'static str,
}

fn zod_type(v: Option<&JsonValue>) -> &'static str {
    match v {
        None => "undefined",
        Some(JsonValue::Null) => "null",
        Some(JsonValue::Bool(_)) => "boolean",
        Some(JsonValue::Number(_)) => "number",
        Some(JsonValue::String(_)) => "string",
        Some(JsonValue::Array(_)) => "array",
        Some(JsonValue::Object(_)) => "object",
    }
}

fn zod_message(issues: &[Issue]) -> String {
    let mut s = String::from("[\n");
    for (i, issue) in issues.iter().enumerate() {
        s.push_str("  {\n");
        s.push_str(&format!("    \"expected\": \"{}\",\n", issue.expected));
        s.push_str("    \"code\": \"invalid_type\",\n");
        s.push_str("    \"path\": [\n");
        for (j, seg) in issue.path.iter().enumerate() {
            s.push_str(&format!("      \"{seg}\""));
            if j + 1 < issue.path.len() {
                s.push(',');
            }
            s.push('\n');
        }
        s.push_str("    ],\n");
        s.push_str(&format!(
            "    \"message\": \"Invalid input: expected {}, received {}\"\n",
            issue.expected, issue.received
        ));
        s.push_str("  }");
        if i + 1 < issues.len() {
            s.push(',');
        }
        s.push('\n');
    }
    s.push(']');
    s
}

#[derive(Clone, Copy)]
enum Kind {
    String,
    Object,
    Array,
    Record,
}

impl Kind {
    fn name(self) -> &'static str {
        match self {
            Kind::String => "string",
            Kind::Object => "object",
            Kind::Array => "array",
            Kind::Record => "record",
        }
    }

    fn accepts(self, v: &JsonValue) -> bool {
        match self {
            Kind::String => matches!(v, JsonValue::String(_)),
            Kind::Object | Kind::Record => matches!(v, JsonValue::Object(_)),
            Kind::Array => matches!(v, JsonValue::Array(_)),
        }
    }
}

/// Checks one field; returns whether the value is present and of the kind.
fn check(
    issues: &mut Vec<Issue>,
    value: Option<&JsonValue>,
    kind: Kind,
    required: bool,
    path: Vec<&'static str>,
) -> bool {
    match value {
        None if !required => false,
        Some(v) if kind.accepts(v) => true,
        other => {
            issues.push(Issue {
                expected: kind.name(),
                path,
                received: zod_type(other),
            });
            false
        }
    }
}

/// `InitializeRequestSchema.params`. ClientCapabilities is checked as an
/// object only; its optional sub-fields are not validated.
fn initialize_issues(params: Option<&JsonValue>) -> Vec<Issue> {
    let mut issues = Vec::new();
    if !check(&mut issues, params, Kind::Object, true, vec!["params"]) {
        return issues;
    }
    let p = params.unwrap();
    check(
        &mut issues,
        p.get("protocolVersion"),
        Kind::String,
        true,
        vec!["params", "protocolVersion"],
    );
    check(
        &mut issues,
        p.get("capabilities"),
        Kind::Object,
        true,
        vec!["params", "capabilities"],
    );
    let info = p.get("clientInfo");
    if check(
        &mut issues,
        info,
        Kind::Object,
        true,
        vec!["params", "clientInfo"],
    ) {
        let info = info.unwrap();
        let fields: [(&'static str, Kind, bool); 6] = [
            ("name", Kind::String, true),
            ("title", Kind::String, false),
            ("icons", Kind::Array, false),
            ("version", Kind::String, true),
            ("websiteUrl", Kind::String, false),
            ("description", Kind::String, false),
        ];
        for (field, kind, required) in fields {
            check(
                &mut issues,
                info.get(field),
                kind,
                required,
                vec!["params", "clientInfo", field],
            );
        }
    }
    issues
}

/// `CallToolRequestSchema.params` (`name`, `arguments`; `task` not handled).
fn tools_call_issues(params: Option<&JsonValue>) -> Vec<Issue> {
    let mut issues = Vec::new();
    if !check(&mut issues, params, Kind::Object, true, vec!["params"]) {
        return issues;
    }
    let p = params.unwrap();
    check(
        &mut issues,
        p.get("name"),
        Kind::String,
        true,
        vec!["params", "name"],
    );
    check(
        &mut issues,
        p.get("arguments"),
        Kind::Record,
        false,
        vec!["params", "arguments"],
    );
    issues
}

/// `ListToolsRequestSchema.params` (`cursor`).
fn tools_list_issues(params: Option<&JsonValue>) -> Vec<Issue> {
    let mut issues = Vec::new();
    if let Some(p) = params {
        check(
            &mut issues,
            p.get("cursor"),
            Kind::String,
            false,
            vec!["params", "cursor"],
        );
    }
    issues
}

fn result_message(id: &JsonValue, result: JsonValue) -> JsonValue {
    // Key order is the SDK's: {result, jsonrpc, id}.
    JsonValue::object(vec![
        ("result", result),
        ("jsonrpc", JsonValue::str("2.0")),
        ("id", id.clone()),
    ])
}

fn error_message(id: &JsonValue, code: i64, message: &str) -> JsonValue {
    // Key order is the SDK's: {jsonrpc, id, error}.
    JsonValue::object(vec![
        ("jsonrpc", JsonValue::str("2.0")),
        ("id", id.clone()),
        (
            "error",
            JsonValue::object(vec![
                ("code", JsonValue::Number(code as f64)),
                ("message", JsonValue::str(message)),
            ]),
        ),
    ])
}

/// A stateless MCP server: one per HTTP request, like the TS factory built.
pub struct McpServer {
    name: String,
    version: String,
    client: Option<Arc<SlackClient>>,
    advertised_tools: Vec<ToolDefinition>,
    advertised_names: HashSet<String>,
    has_handled_request: AtomicBool,
}

impl McpServer {
    pub fn new(name: &str, version: &str) -> Self {
        Self {
            name: name.to_string(),
            version: version.to_string(),
            client: None,
            advertised_tools: Vec::new(),
            advertised_names: HashSet::new(),
            has_handled_request: AtomicBool::new(false),
        }
    }

    pub fn with_slack(
        name: &str,
        version: &str,
        client: Arc<SlackClient>,
        advertised_tools: Vec<ToolDefinition>,
    ) -> Self {
        let advertised_names = advertised_tools
            .iter()
            .map(|t| t.name.to_string())
            .collect();
        Self {
            name: name.to_string(),
            version: version.to_string(),
            client: Some(client),
            advertised_tools,
            advertised_names,
            has_handled_request: AtomicBool::new(false),
        }
    }

    /// The stateless transport's single-use guard (SDK `_hasHandledRequest`).
    pub fn begin_stateless_request(&self) -> Result<(), String> {
        if self.has_handled_request.swap(true, Ordering::SeqCst) {
            return Err(
                "Stateless transport cannot be reused across requests. Create a new transport per request."
                    .to_string(),
            );
        }
        Ok(())
    }

    /// stdio: one line in, at most one response out. Invalid JSON or an
    /// invalid JSON-RPC message is `Err` (the SDK's stdio transport reports it
    /// to `onerror`, which this server never set, and writes nothing).
    /// Notifications and responses are `Ok(None)`: nothing is written.
    pub fn handle_jsonrpc_message(&self, line: &str) -> Result<Option<JsonValue>, String> {
        let parsed = JsonValue::parse(line).map_err(|e| format!("Invalid JSON: {e}"))?;
        let parsed = dedup_keys(parsed);
        match classify_message(&parsed) {
            Some(JsonRpcMessage::Request { id, method, params }) => {
                Ok(Some(self.handle_request(&id, &method, params.as_ref())))
            }
            Some(_) => Ok(None),
            None => Err("Invalid JSON-RPC message".to_string()),
        }
    }

    /// Answers one JSON-RPC request with a full response message. Blocking:
    /// `tools/call` makes HTTPS calls to Slack.
    pub fn handle_request(
        &self,
        id: &JsonValue,
        method: &str,
        params: Option<&JsonValue>,
    ) -> JsonValue {
        match method {
            "initialize" => {
                let issues = initialize_issues(params);
                if !issues.is_empty() {
                    return error_message(id, -32603, &zod_message(&issues));
                }
                let requested = params
                    .and_then(|p| p.get("protocolVersion"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let negotiated = if SUPPORTED_PROTOCOL_VERSIONS.contains(&requested) {
                    requested
                } else {
                    LATEST_PROTOCOL_VERSION
                };
                result_message(
                    id,
                    JsonValue::object(vec![
                        ("protocolVersion", JsonValue::str(negotiated)),
                        (
                            "capabilities",
                            JsonValue::object(vec![("tools", JsonValue::object(vec![]))]),
                        ),
                        (
                            "serverInfo",
                            JsonValue::object(vec![
                                ("name", JsonValue::str(&self.name)),
                                ("version", JsonValue::str(&self.version)),
                            ]),
                        ),
                    ]),
                )
            }
            "ping" => result_message(id, JsonValue::object(vec![])),
            "tools/list" => {
                let issues = tools_list_issues(params);
                if !issues.is_empty() {
                    return error_message(id, -32603, &zod_message(&issues));
                }
                let tools: Vec<JsonValue> =
                    self.advertised_tools.iter().map(|t| t.to_json()).collect();
                result_message(
                    id,
                    JsonValue::object(vec![("tools", JsonValue::Array(tools))]),
                )
            }
            "tools/call" => {
                let issues = tools_call_issues(params);
                if !issues.is_empty() {
                    return error_message(id, -32603, &zod_message(&issues));
                }
                let params = params.expect("validated above");
                let tool_name = params.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let args = params
                    .get("arguments")
                    .cloned()
                    .unwrap_or_else(|| JsonValue::object(vec![]));

                let call_result = if !self.advertised_names.contains(tool_name) {
                    Err(format!(
                        "Tool {tool_name} is not available on this transport."
                    ))
                } else if let Some(ref client) = self.client {
                    dispatch(client, tool_name, &args).map_err(|e| e.to_string())
                } else {
                    Err("No SlackClient configured".to_string())
                };

                let text = match call_result {
                    Ok(val) => val.to_string_pretty(),
                    Err(err_msg) => {
                        JsonValue::object(vec![("error", JsonValue::str(&err_msg))]).to_string()
                    }
                };
                result_message(
                    id,
                    JsonValue::object(vec![(
                        "content",
                        JsonValue::Array(vec![JsonValue::object(vec![
                            ("type", JsonValue::str("text")),
                            ("text", JsonValue::str(&text)),
                        ])]),
                    )]),
                )
            }
            _ => error_message(id, -32601, "Method not found"),
        }
    }
}

// ---------------------------------------------------------------------------
// Responses
// ---------------------------------------------------------------------------

type RespBody = UnsyncBoxBody<Bytes, Infallible>;

fn full(body: impl Into<Bytes>) -> RespBody {
    Full::new(body.into()).boxed_unsync()
}

fn empty() -> RespBody {
    Empty::<Bytes>::new().boxed_unsync()
}

fn json_response(status: u16, body: String, extra: &[(&str, &str)]) -> Response<RespBody> {
    let mut builder = Response::builder()
        .status(status)
        .header("content-type", "application/json");
    for (k, v) in extra {
        builder = builder.header(*k, *v);
    }
    builder.body(full(body)).expect("static response parts")
}

/// SDK `createJsonErrorResponse`: `{jsonrpc, error:{code,message}, id:null}`.
fn jsonrpc_http_error(
    status: u16,
    code: i64,
    message: &str,
    extra: &[(&str, &str)],
) -> Response<RespBody> {
    let body = JsonValue::object(vec![
        ("jsonrpc", JsonValue::str("2.0")),
        (
            "error",
            JsonValue::object(vec![
                ("code", JsonValue::Number(code as f64)),
                ("message", JsonValue::str(message)),
            ]),
        ),
        ("id", JsonValue::Null),
    ])
    .to_string();
    json_response(status, body, extra)
}

fn internal_error(method: &Method, target: &str, detail: &str) -> Response<RespBody> {
    write_stderr(&format!(
        "mcp-slack: unhandled error serving {method} {target}: {detail}\n"
    ));
    jsonrpc_http_error(500, -32603, "Internal server error", &[])
}

fn auth_failure(error: &AuthError, metadata_url: &str) -> Response<RespBody> {
    let status = error.status();
    let code = error.code();
    let msg = error.message();

    if status == 403 {
        let presented_part = match error.presented() {
            Some(p) => {
                let label = error.presented_label().unwrap_or("presented");
                format!(" {label}={}", header_safe(p))
            }
            None => String::new(),
        };
        write_stderr(&format!(
            "mcp-slack: refused {code}{presented_part}: {}\n",
            header_safe(&msg)
        ));
    }

    let body = JsonValue::object(vec![
        ("jsonrpc", JsonValue::str("2.0")),
        (
            "error",
            JsonValue::object(vec![
                ("code", JsonValue::Number(-32001.0)),
                ("message", JsonValue::str(&msg)),
            ]),
        ),
        ("id", JsonValue::Null),
    ])
    .to_string();

    if status == 503 {
        return json_response(503, body, &[("retry-after", "30")]);
    }
    let challenge = if status == 401 {
        format!(
            "Bearer error=\"{code}\", error_description=\"{}\", resource_metadata=\"{metadata_url}\"",
            header_safe(&msg)
        )
    } else {
        format!(
            "Bearer error=\"{code}\", error_description=\"{}\"",
            header_safe(&msg)
        )
    };
    // header_safe output is printable ASCII, but never let a header value
    // that fails validation turn into a panic.
    match HeaderValue::from_str(&challenge) {
        Ok(_) => json_response(status, body, &[("www-authenticate", &challenge)]),
        Err(_) => json_response(status, body, &[]),
    }
}

fn panic_message(err: tokio::task::JoinError) -> String {
    if err.is_cancelled() {
        return "task cancelled".to_string();
    }
    let payload = err.into_panic();
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "panic".to_string()
    }
}

const SSE_HEADERS: [(&str, &str); 4] = [
    ("content-type", "text/event-stream"),
    ("cache-control", "no-cache, no-transform"),
    ("connection", "keep-alive"),
    ("x-accel-buffering", "no"),
];

/// An SSE body: events from `rx`, `: keepalive` comments while waiting, and
/// (for the standalone GET stream) an end when `stop` resolves.
struct SseBody {
    rx: Option<mpsc::UnboundedReceiver<Bytes>>,
    keepalive: tokio::time::Interval,
    stop: Option<Pin<Box<dyn Future<Output = ()> + Send>>>,
    done: bool,
}

impl Body for SseBody {
    type Data = Bytes;
    type Error = Infallible;

    fn poll_frame(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Bytes>, Infallible>>> {
        let this = &mut *self;
        if this.done {
            return Poll::Ready(None);
        }
        if let Some(stop) = this.stop.as_mut() {
            if stop.as_mut().poll(cx).is_ready() {
                this.done = true;
                return Poll::Ready(None);
            }
        }
        if let Some(rx) = this.rx.as_mut() {
            match rx.poll_recv(cx) {
                Poll::Ready(Some(event)) => return Poll::Ready(Some(Ok(Frame::data(event)))),
                Poll::Ready(None) => {
                    this.done = true;
                    return Poll::Ready(None);
                }
                Poll::Pending => {}
            }
        }
        if this.keepalive.poll_tick(cx).is_ready() {
            return Poll::Ready(Some(Ok(Frame::data(Bytes::from_static(
                b": keepalive\n\n",
            )))));
        }
        Poll::Pending
    }

    fn is_end_stream(&self) -> bool {
        self.done
    }
}

fn keepalive_interval(period: Duration) -> tokio::time::Interval {
    let mut interval = tokio::time::interval_at(tokio::time::Instant::now() + period, period);
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    interval
}

fn sse_response(body: SseBody) -> Response<RespBody> {
    let mut builder = Response::builder().status(200);
    for (k, v) in SSE_HEADERS {
        builder = builder.header(k, v);
    }
    builder
        .body(body.boxed_unsync())
        .expect("static response parts")
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

/// Socket-level limits, defaulting to Node's `http` server defaults.
#[derive(Clone, Debug)]
pub struct TransportLimits {
    /// Node `headersTimeout` (60 s). Also bounds idle keep-alive connections.
    pub header_read_timeout: Duration,
    /// Node `requestTimeout` (300 s): the whole request body must arrive in it.
    pub request_timeout: Duration,
    /// Node `--max-http-header-size` (16 KiB); over it is a 431.
    pub max_header_bytes: usize,
    /// Node keeps up to 2000 headers; hyper answers 431 beyond the bound.
    pub max_headers: usize,
    /// Connections served at once; further ones wait in the listen backlog.
    pub max_connections: usize,
    /// SDK `DEFAULT_SSE_KEEP_ALIVE_MS` (15 s).
    pub sse_keep_alive: Duration,
    /// Node `listen(port)` takes every interface.
    pub bind_ip: IpAddr,
}

impl Default for TransportLimits {
    fn default() -> Self {
        Self {
            header_read_timeout: Duration::from_secs(60),
            request_timeout: Duration::from_secs(300),
            max_header_bytes: 16 * 1024,
            max_headers: 2000,
            max_connections: 1024,
            sse_keep_alive: Duration::from_millis(15_000),
            bind_ip: IpAddr::V4(Ipv4Addr::UNSPECIFIED),
        }
    }
}

type ServerFactory = Arc<dyn Fn() -> McpServer + Send + Sync>;

struct Ctx {
    create_server: ServerFactory,
    config: HttpConfig,
    verifier: Arc<dyn TokenVerifier>,
    limits: TransportLimits,
    shutdown: watch::Receiver<bool>,
}

struct ConnTracker {
    active: AtomicUsize,
    idle: Notify,
}

impl ConnTracker {
    async fn wait_idle(&self) {
        loop {
            let notified = self.idle.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if self.active.load(Ordering::SeqCst) == 0 {
                return;
            }
            notified.await;
        }
    }
}

struct ConnGuard(Arc<ConnTracker>);

impl Drop for ConnGuard {
    fn drop(&mut self) {
        if self.0.active.fetch_sub(1, Ordering::SeqCst) == 1 {
            self.0.idle.notify_waiters();
        }
    }
}

async fn wait_true(rx: &mut watch::Receiver<bool>) {
    // A dropped sender also means "stop".
    let _ = rx.wait_for(|v| *v).await;
}

pub struct HttpTransportHandle {
    addr: SocketAddr,
    runtime: Option<tokio::runtime::Runtime>,
    shutdown_tx: watch::Sender<bool>,
    force_tx: watch::Sender<bool>,
    tracker: Arc<ConnTracker>,
    accept_task: Option<tokio::task::JoinHandle<()>>,
}

impl HttpTransportHandle {
    pub fn address(&self) -> SocketAddr {
        self.addr
    }

    /// Stops accepting, lets in-flight requests finish for up to
    /// `grace_period_ms`, then closes whatever is left. Idle keep-alive
    /// connections close at once.
    pub fn close(&mut self, grace_period_ms: u64) -> Result<(), String> {
        let rt = match self.runtime.take() {
            Some(rt) => rt,
            None => return Ok(()),
        };
        let _ = self.shutdown_tx.send(true);
        let accept = self.accept_task.take();
        let tracker = self.tracker.clone();
        let force_tx = self.force_tx.clone();
        rt.block_on(async move {
            if let Some(task) = accept {
                let _ = task.await;
            }
            let grace = Duration::from_millis(grace_period_ms);
            if tokio::time::timeout(grace, tracker.wait_idle())
                .await
                .is_err()
            {
                let _ = force_tx.send(true);
                let _ = tokio::time::timeout(Duration::from_secs(1), tracker.wait_idle()).await;
            }
        });
        // Blocking-pool threads (a wedged verifier or Slack call) cannot be
        // cancelled; don't wait for them.
        rt.shutdown_background();
        Ok(())
    }
}

impl Drop for HttpTransportHandle {
    fn drop(&mut self) {
        if let Some(rt) = self.runtime.take() {
            let _ = self.shutdown_tx.send(true);
            let _ = self.force_tx.send(true);
            rt.shutdown_background();
        }
    }
}

pub fn start_http_transport<F>(
    create_server: F,
    config: HttpConfig,
    verifier: Arc<dyn TokenVerifier>,
) -> Result<HttpTransportHandle, String>
where
    F: Fn() -> McpServer + Send + Sync + 'static,
{
    start_http_transport_with_limits(create_server, config, verifier, TransportLimits::default())
}

pub fn start_http_transport_with_limits<F>(
    create_server: F,
    config: HttpConfig,
    verifier: Arc<dyn TokenVerifier>,
    limits: TransportLimits,
) -> Result<HttpTransportHandle, String>
where
    F: Fn() -> McpServer + Send + Sync + 'static,
{
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .thread_name("mcp-slack-http")
        .build()
        .map_err(|e| format!("Failed to start the HTTP runtime: {e}"))?;

    let bind_addr = SocketAddr::new(limits.bind_ip, config.port);
    let listener = runtime
        .block_on(TcpListener::bind(bind_addr))
        .map_err(|e| format!("Failed to bind HTTP transport port {}: {e}", config.port))?;
    let addr = listener
        .local_addr()
        .map_err(|e| format!("Failed to read bound local address: {e}"))?;

    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let (force_tx, force_rx) = watch::channel(false);
    let tracker = Arc::new(ConnTracker {
        active: AtomicUsize::new(0),
        idle: Notify::new(),
    });
    let ctx = Arc::new(Ctx {
        create_server: Arc::new(create_server),
        config,
        verifier,
        limits: limits.clone(),
        shutdown: shutdown_rx.clone(),
    });

    let accept_task = runtime.spawn(accept_loop(
        listener,
        ctx,
        tracker.clone(),
        shutdown_rx,
        force_rx,
    ));

    Ok(HttpTransportHandle {
        addr,
        runtime: Some(runtime),
        shutdown_tx,
        force_tx,
        tracker,
        accept_task: Some(accept_task),
    })
}

async fn accept_loop(
    listener: TcpListener,
    ctx: Arc<Ctx>,
    tracker: Arc<ConnTracker>,
    mut shutdown: watch::Receiver<bool>,
    force: watch::Receiver<bool>,
) {
    let permits = Arc::new(Semaphore::new(ctx.limits.max_connections));
    loop {
        let permit = tokio::select! {
            p = permits.clone().acquire_owned() => match p { Ok(p) => p, Err(_) => break },
            _ = wait_true(&mut shutdown) => break,
        };
        let (stream, _peer) = tokio::select! {
            r = listener.accept() => match r {
                Ok(pair) => pair,
                Err(_) => {
                    // EMFILE and friends: back off rather than spin.
                    tokio::time::sleep(Duration::from_millis(50)).await;
                    continue;
                }
            },
            _ = wait_true(&mut shutdown) => break,
        };
        tracker.active.fetch_add(1, Ordering::SeqCst);
        let guard = ConnGuard(tracker.clone());
        let ctx = ctx.clone();
        let shutdown = shutdown.clone();
        let force = force.clone();
        tokio::spawn(async move {
            let _guard = guard;
            let _permit = permit;
            serve_connection(stream, ctx, shutdown, force).await;
        });
    }
    // Dropping the listener here refuses new connections.
}

async fn serve_connection(
    stream: tokio::net::TcpStream,
    ctx: Arc<Ctx>,
    mut shutdown: watch::Receiver<bool>,
    mut force: watch::Receiver<bool>,
) {
    let io = TokioIo::new(stream);
    let svc_ctx = ctx.clone();
    let service = service_fn(move |req: Request<Incoming>| {
        let ctx = svc_ctx.clone();
        async move { Ok::<_, Infallible>(handle_guarded(req, ctx).await) }
    });
    let mut builder = http1::Builder::new();
    builder
        .timer(TokioTimer::new())
        .header_read_timeout(ctx.limits.header_read_timeout)
        .max_buf_size(ctx.limits.max_header_bytes.max(8192))
        .max_headers(ctx.limits.max_headers);
    let conn = builder.serve_connection(io, service);
    tokio::pin!(conn);
    let mut draining = false;
    loop {
        tokio::select! {
            _ = conn.as_mut() => break,
            _ = wait_true(&mut shutdown), if !draining => {
                conn.as_mut().graceful_shutdown();
                draining = true;
            }
            _ = wait_true(&mut force) => break,
        }
    }
}

/// Runs the request in its own task so a panic is a 500, not a dead connection.
async fn handle_guarded(req: Request<Incoming>, ctx: Arc<Ctx>) -> Response<RespBody> {
    let method = req.method().clone();
    let target = req.uri().to_string();
    match tokio::spawn(route(req, ctx)).await {
        Ok(resp) => resp,
        Err(err) => internal_error(&method, &target, &panic_message(err)),
    }
}

async fn route(req: Request<Incoming>, ctx: Arc<Ctx>) -> Response<RespBody> {
    let started = Instant::now();
    let (parts, body) = req.into_parts();

    // Node answers any expectation other than 100-continue with a bare 417
    // before the handler runs.
    if let Some(expect) = parts.headers.get("expect") {
        if !latin1(expect).eq_ignore_ascii_case("100-continue") {
            return Response::builder()
                .status(StatusCode::EXPECTATION_FAILED)
                .body(empty())
                .expect("static response parts");
        }
    }

    let pathname = whatwg_pathname(&parts.uri);

    if pathname == HEALTH_PATH {
        let body = JsonValue::object(vec![("status", JsonValue::str("ok"))]).to_string();
        return json_response(200, body, &[]);
    }

    let headers = node_headers(&parts.headers);
    let origin = get_request_origin(&headers, false);
    let metadata_url = format!("{origin}{OAUTH_PROTECTED_RESOURCE_PATH}{MCP_PATH}");

    if pathname == OAUTH_PROTECTED_RESOURCE_PATH
        || pathname == format!("{OAUTH_PROTECTED_RESOURCE_PATH}{MCP_PATH}")
    {
        let body = JsonValue::object(vec![
            ("resource", JsonValue::str(&format!("{origin}{MCP_PATH}"))),
            (
                "authorization_servers",
                JsonValue::Array(vec![JsonValue::str(&ctx.config.issuer)]),
            ),
            (
                "scopes_supported",
                JsonValue::Array(vec![
                    JsonValue::str("openid"),
                    JsonValue::str("offline_access"),
                    JsonValue::str(&audience_scope_for(&ctx.config.project_id)),
                ]),
            ),
        ])
        .to_string();
        return json_response(200, body, &[]);
    }

    if pathname != MCP_PATH {
        let body = JsonValue::object(vec![("error", JsonValue::str("not_found"))]).to_string();
        return json_response(404, body, &[]);
    }

    let target = parts.uri.to_string();
    let authorization = headers.get("authorization").cloned();
    let verifier = ctx.verifier.clone();
    let verdict = tokio::task::spawn_blocking(move || {
        verifier.verify_authorization_header(authorization.as_deref())
    })
    .await;
    match verdict {
        Ok(Ok(_)) => {}
        Ok(Err(Ok(auth_err))) => return auth_failure(&auth_err, &metadata_url),
        Ok(Err(Err(unexpected))) => return internal_error(&parts.method, &target, &unexpected),
        Err(join) => return internal_error(&parts.method, &target, &panic_message(join)),
    }

    // A fresh server per request (stateless mode; #1491 / GHSA-345p-7cg4-v4c7).
    let server = Arc::new((ctx.create_server)());
    if let Err(e) = server.begin_stateless_request() {
        return internal_error(&parts.method, &target, &e);
    }

    match parts.method {
        Method::POST => handle_post(&parts.headers, body, server, &ctx, started).await,
        Method::GET => handle_get(&parts.headers, &ctx),
        Method::DELETE => match validate_protocol_version(&parts.headers) {
            Some(resp) => resp,
            None => Response::builder()
                .status(200)
                .body(empty())
                .expect("static response parts"),
        },
        _ => jsonrpc_http_error(
            405,
            -32000,
            "Method not allowed.",
            &[("allow", "GET, POST, DELETE")],
        ),
    }
}

/// SDK `validateProtocolVersion`: an absent header is fine, an unknown one is 400.
fn validate_protocol_version(headers: &HeaderMap) -> Option<Response<RespBody>> {
    let version = web_header(headers, "mcp-protocol-version")?;
    if SUPPORTED_PROTOCOL_VERSIONS.contains(&version.as_str()) {
        return None;
    }
    let message = format!(
        "Bad Request: Unsupported protocol version: {version} (supported versions: {})",
        SUPPORTED_PROTOCOL_VERSIONS.join(", ")
    );
    Some(jsonrpc_http_error(400, -32000, &message, &[]))
}

fn handle_get(headers: &HeaderMap, ctx: &Ctx) -> Response<RespBody> {
    let accept = web_header(headers, "accept").unwrap_or_default();
    if !accept.contains("text/event-stream") {
        return jsonrpc_http_error(
            406,
            -32000,
            "Not Acceptable: Client must accept text/event-stream",
            &[],
        );
    }
    if let Some(resp) = validate_protocol_version(headers) {
        return resp;
    }
    // Stateless: nothing is ever sent on the standalone stream, so it only
    // carries keep-alives. Unlike the SDK it ends when the server starts
    // draining, so an idle listener does not hold a rollout for the full grace.
    let mut shutdown = ctx.shutdown.clone();
    let stop: Pin<Box<dyn Future<Output = ()> + Send>> =
        Box::pin(async move { wait_true(&mut shutdown).await });
    sse_response(SseBody {
        rx: None,
        keepalive: keepalive_interval(ctx.limits.sse_keep_alive),
        stop: Some(stop),
        done: false,
    })
}

const PARSE_ERROR_INVALID_JSON: &str = "Parse error: Invalid JSON";

async fn handle_post(
    headers: &HeaderMap,
    body: Incoming,
    server: Arc<McpServer>,
    ctx: &Ctx,
    started: Instant,
) -> Response<RespBody> {
    let accept = web_header(headers, "accept").unwrap_or_default();
    if !accept.contains("application/json") || !accept.contains("text/event-stream") {
        return jsonrpc_http_error(
            406,
            -32000,
            "Not Acceptable: Client must accept both application/json and text/event-stream",
            &[],
        );
    }
    if !is_json_content_type(web_header(headers, "content-type").as_deref()) {
        return jsonrpc_http_error(
            415,
            -32000,
            "Unsupported Media Type: Content-Type must be application/json",
            &[],
        );
    }

    let too_large = || {
        jsonrpc_http_error(
            413,
            -32000,
            &format!(
                "Payload Too Large: Request body must not exceed {MAX_REQUEST_BODY_SIZE} bytes"
            ),
            &[],
        )
    };
    // A declared length over the cap is refused without reading anything.
    if let Some(cl) = web_header(headers, "content-length") {
        if cl
            .trim()
            .parse::<f64>()
            .map_or(false, |n| n > MAX_REQUEST_BODY_SIZE as f64)
        {
            return too_large();
        }
    }
    let remaining = ctx.limits.request_timeout.saturating_sub(started.elapsed());
    let read = tokio::time::timeout(
        remaining,
        Limited::new(body, MAX_REQUEST_BODY_SIZE).collect(),
    )
    .await;
    let bytes = match read {
        Err(_) => {
            // Node's requestTimeout answer.
            return Response::builder()
                .status(StatusCode::REQUEST_TIMEOUT)
                .header("connection", "close")
                .body(empty())
                .expect("static response parts");
        }
        Ok(Err(e)) => {
            if e.downcast_ref::<LengthLimitError>().is_some() {
                return too_large();
            }
            return jsonrpc_http_error(400, -32700, PARSE_ERROR_INVALID_JSON, &[]);
        }
        Ok(Ok(collected)) => collected.to_bytes(),
    };

    // TextDecoder: lossy UTF-8, leading BOM dropped.
    let raw: &[u8] = bytes.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(&bytes);
    let text = String::from_utf8_lossy(raw);
    let parsed = match JsonValue::parse(&text) {
        Ok(v) => dedup_keys(v),
        Err(_) => return jsonrpc_http_error(400, -32700, PARSE_ERROR_INVALID_JSON, &[]),
    };

    if let JsonValue::Array(items) = &parsed {
        if items.len() > MAX_BATCH_SIZE {
            return jsonrpc_http_error(
                400,
                -32600,
                &format!("Invalid Request: Batch must not exceed {MAX_BATCH_SIZE} messages"),
                &[],
            );
        }
    }
    let raw_messages: Vec<&JsonValue> = match &parsed {
        JsonValue::Array(items) => items.iter().collect(),
        single => vec![single],
    };
    let mut messages = Vec::with_capacity(raw_messages.len());
    for raw in raw_messages {
        match classify_message(raw) {
            Some(m) => messages.push(m),
            None => {
                return jsonrpc_http_error(
                    400,
                    -32700,
                    "Parse error: Invalid JSON-RPC message",
                    &[],
                )
            }
        }
    }

    let is_initialization = messages.iter().any(|m| m.is_initialize());
    if is_initialization {
        if messages.len() > 1 {
            return jsonrpc_http_error(
                400,
                -32600,
                "Invalid Request: Only one initialization request is allowed",
                &[],
            );
        }
    } else if let Some(resp) = validate_protocol_version(headers) {
        return resp;
    }

    // Notifications are acknowledged and otherwise ignored (the only ones the
    // SDK server handles — initialized, cancelled, progress — change nothing
    // a stateless request can observe); responses have nothing waiting.
    let requests: Vec<(JsonValue, String, Option<JsonValue>)> = messages
        .into_iter()
        .filter_map(|m| match m {
            JsonRpcMessage::Request { id, method, params } => Some((id, method, params)),
            _ => None,
        })
        .collect();
    if requests.is_empty() {
        return Response::builder()
            .status(StatusCode::ACCEPTED)
            .body(empty())
            .expect("static response parts");
    }

    // One SSE event per response, in completion order; the stream ends when
    // every request in the batch has answered.
    let (tx, rx) = mpsc::unbounded_channel::<Bytes>();
    for (id, method, params) in requests {
        let tx = tx.clone();
        let server = server.clone();
        tokio::spawn(async move {
            let id_for_error = id.clone();
            let outcome = tokio::task::spawn_blocking(move || {
                server.handle_request(&id, &method, params.as_ref())
            })
            .await;
            let message = match outcome {
                Ok(message) => message,
                Err(join) => {
                    let detail = panic_message(join);
                    write_stderr(&format!("mcp-slack: request handler panicked: {detail}\n"));
                    error_message(&id_for_error, -32603, &detail)
                }
            };
            let event = format!("event: message\ndata: {}\n\n", message.to_json_string());
            let _ = tx.send(Bytes::from(event));
        });
    }
    drop(tx);
    sse_response(SseBody {
        rx: Some(rx),
        keepalive: keepalive_interval(ctx.limits.sse_keep_alive),
        stop: None,
        done: false,
    })
}

/// Blocks until SIGTERM or SIGINT and returns its name. tokio never uninstalls
/// the OS-level handlers it registers, so a second signal during the drain is
/// swallowed rather than killing the process: the drain happens once.
pub fn wait_for_shutdown_signal() -> Result<&'static str, String> {
    use tokio::signal::unix::{signal, SignalKind};
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| format!("signal runtime: {e}"))?;
    rt.block_on(async {
        let mut term = signal(SignalKind::terminate()).map_err(|e| format!("SIGTERM: {e}"))?;
        let mut int = signal(SignalKind::interrupt()).map_err(|e| format!("SIGINT: {e}"))?;
        let name = tokio::select! {
            _ = term.recv() => "SIGTERM",
            _ = int.recv() => "SIGINT",
        };
        Ok(name)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::VerifiedCaller;
    use std::io::Read;
    use std::net::TcpStream;

    fn test_config() -> HttpConfig {
        HttpConfig {
            port: 0,
            issuer: "https://auth.example.test".to_string(),
            project_id: "123456789".to_string(),
            allowed_subjects: vec!["user-42".to_string()],
            allowed_client_id: "111222333".to_string(),
        }
    }

    struct ClosureVerifier<F>
    where
        F: Fn(Option<&str>) -> Result<VerifiedCaller, Result<AuthError, String>> + Send + Sync,
    {
        f: F,
    }

    impl<F> TokenVerifier for ClosureVerifier<F>
    where
        F: Fn(Option<&str>) -> Result<VerifiedCaller, Result<AuthError, String>> + Send + Sync,
    {
        fn verify(&self, token: &str) -> Result<VerifiedCaller, Result<AuthError, String>> {
            (self.f)(Some(token))
        }

        fn verify_authorization_header(
            &self,
            header: Option<&str>,
        ) -> Result<VerifiedCaller, Result<AuthError, String>> {
            (self.f)(header)
        }
    }

    fn caller() -> VerifiedCaller {
        VerifiedCaller {
            subject: "user-42".to_string(),
            claims: JsonValue::object(vec![]),
        }
    }

    fn verifier_with_header<F>(f: F) -> Arc<dyn TokenVerifier>
    where
        F: Fn(Option<&str>) -> Result<(), Result<AuthError, String>> + Send + Sync + 'static,
    {
        Arc::new(ClosureVerifier {
            f: move |h: Option<&str>| {
                f(h)?;
                Ok(caller())
            },
        })
    }

    fn verifier_that<F>(f: F) -> Arc<dyn TokenVerifier>
    where
        F: Fn() -> Result<(), Result<AuthError, String>> + Send + Sync + 'static,
    {
        verifier_with_header(move |_| f())
    }

    fn ok_verifier() -> Arc<dyn TokenVerifier> {
        verifier_that(|| Ok(()))
    }

    #[derive(Debug)]
    struct RawHttpResponse {
        status: u16,
        headers: HashMap<String, String>,
        body: String,
    }

    fn local(addr: SocketAddr) -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), addr.port())
    }

    fn dechunk(body: &[u8]) -> Vec<u8> {
        let mut out = Vec::new();
        let mut rest = body;
        loop {
            let line_end = match rest.windows(2).position(|w| w == b"\r\n") {
                Some(i) => i,
                None => return out,
            };
            let size_str = String::from_utf8_lossy(&rest[..line_end]).to_string();
            let size =
                usize::from_str_radix(size_str.split(';').next().unwrap().trim(), 16).unwrap_or(0);
            rest = &rest[line_end + 2..];
            if size == 0 || rest.len() < size {
                return out;
            }
            out.extend_from_slice(&rest[..size]);
            rest = &rest[(size + 2).min(rest.len())..];
        }
    }

    fn parse_response(raw: &[u8]) -> RawHttpResponse {
        let split = raw
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .unwrap_or(raw.len());
        let head = String::from_utf8_lossy(&raw[..split]).to_string();
        let body_bytes = if split + 4 <= raw.len() {
            &raw[split + 4..]
        } else {
            &[][..]
        };
        let mut lines = head.lines();
        let status = lines
            .next()
            .unwrap_or("")
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse::<u16>().ok())
            .unwrap_or(0);
        let mut headers = HashMap::new();
        for line in lines {
            if let Some((k, v)) = line.split_once(':') {
                headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
            }
        }
        let body = if headers.get("transfer-encoding").map(|s| s.as_str()) == Some("chunked") {
            dechunk(body_bytes)
        } else {
            body_bytes.to_vec()
        };
        RawHttpResponse {
            status,
            headers,
            body: String::from_utf8_lossy(&body).to_string(),
        }
    }

    /// Writes raw bytes, reads until the server closes (or 5 s pass).
    fn send_raw(addr: SocketAddr, request: &[u8]) -> RawHttpResponse {
        let mut stream = TcpStream::connect(local(addr)).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let _ = stream.write_all(request);
        let mut raw = Vec::new();
        let _ = stream.read_to_end(&mut raw);
        parse_response(&raw)
    }

    fn raw_http_request(
        addr: SocketAddr,
        method: &str,
        path: &str,
        headers: &[(&str, &str)],
        body: &str,
    ) -> std::io::Result<RawHttpResponse> {
        let mut req = format!(
            "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nContent-Length: {}\r\nConnection: close\r\n",
            addr.port(),
            body.len()
        );
        for (k, v) in headers {
            req.push_str(&format!("{k}: {v}\r\n"));
        }
        req.push_str("\r\n");
        req.push_str(body);
        Ok(send_raw(addr, req.as_bytes()))
    }

    const MCP_HEADERS: [(&str, &str); 3] = [
        ("Authorization", "Bearer t"),
        ("Content-Type", "application/json"),
        ("Accept", "application/json, text/event-stream"),
    ];

    fn post_mcp(addr: SocketAddr, body: &str) -> RawHttpResponse {
        raw_http_request(addr, "POST", "/mcp", &MCP_HEADERS, body).unwrap()
    }

    fn with_server<F>(verifier: Arc<dyn TokenVerifier>, assertions: F)
    where
        F: FnOnce(SocketAddr),
    {
        let mut handle = start_http_transport(
            || McpServer::new(SERVER_NAME, SERVER_VERSION),
            test_config(),
            verifier,
        )
        .unwrap();
        let addr = handle.address();
        assertions(addr);
        handle.close(1_000).unwrap();
    }

    fn sdk_error_body(code: i64, message: &str) -> String {
        JsonValue::object(vec![
            ("jsonrpc", JsonValue::str("2.0")),
            (
                "error",
                JsonValue::object(vec![
                    ("code", JsonValue::Number(code as f64)),
                    ("message", JsonValue::str(message)),
                ]),
            ),
            ("id", JsonValue::Null),
        ])
        .to_string()
    }

    /// The `data:` payloads of an SSE body.
    fn sse_events(body: &str) -> Vec<JsonValue> {
        body.split("\n\n")
            .filter_map(|block| {
                let mut lines = block.lines();
                if lines.next()? != "event: message" {
                    return None;
                }
                let data = lines.next()?.strip_prefix("data: ")?;
                Some(JsonValue::parse(data).unwrap())
            })
            .collect()
    }

    // ----- kept from the original suite (TS parity) -----

    #[test]
    fn serves_health_without_authentication() {
        with_server(
            verifier_that(|| Err(Err("verifier must not be consulted for /health".to_string()))),
            |addr| {
                for method in ["GET", "POST", "DELETE"] {
                    let res = raw_http_request(addr, method, "/health", &[], "").unwrap();
                    assert_eq!(res.status, 200);
                    assert_eq!(res.body, r#"{"status":"ok"}"#);
                }
            },
        );
    }

    #[test]
    fn serves_oauth_protected_resource_without_authentication() {
        with_server(
            verifier_that(|| {
                Err(Err(
                    "verifier must not be consulted for /.well-known/oauth-protected-resource"
                        .to_string(),
                ))
            }),
            |addr| {
                let res = raw_http_request(
                    addr,
                    "GET",
                    "/.well-known/oauth-protected-resource",
                    &[],
                    "",
                )
                .unwrap();
                assert_eq!(res.status, 200);
                let data = JsonValue::parse(&res.body).unwrap();
                let base_url = format!("http://127.0.0.1:{}", addr.port());
                assert_eq!(
                    data.get("resource").and_then(|v| v.as_str()),
                    Some(format!("{base_url}/mcp").as_str())
                );
                let auth_servers = data
                    .get("authorization_servers")
                    .and_then(|v| v.as_array())
                    .unwrap();
                assert_eq!(auth_servers.len(), 1);
                assert_eq!(auth_servers[0].as_str(), Some("https://auth.example.test"));
                let scopes = data
                    .get("scopes_supported")
                    .and_then(|v| v.as_array())
                    .unwrap();
                let scope_strs: Vec<&str> = scopes.iter().filter_map(|v| v.as_str()).collect();
                assert_eq!(
                    scope_strs,
                    vec![
                        "openid",
                        "offline_access",
                        "urn:zitadel:iam:org:project:id:123456789:aud"
                    ]
                );
            },
        );
    }

    #[test]
    fn serves_oauth_protected_resource_mcp_with_https_for_public_domains() {
        with_server(ok_verifier(), |addr| {
            let res = raw_http_request(
                addr,
                "GET",
                "/.well-known/oauth-protected-resource/mcp",
                &[
                    ("x-forwarded-host", "mcp-slack.ipv1337.dev"),
                    ("cf-visitor", "{\"scheme\":\"https\"}"),
                ],
                "",
            )
            .unwrap();
            assert_eq!(res.status, 200);
            let data = JsonValue::parse(&res.body).unwrap();
            assert_eq!(
                data.get("resource").and_then(|v| v.as_str()),
                Some("https://mcp-slack.ipv1337.dev/mcp")
            );
        });
    }

    #[test]
    fn rejects_unauthenticated_mcp_request_with_status_and_resource_metadata_challenge() {
        with_server(verifier_that(|| Err(Ok(AuthError::MissingToken))), |addr| {
            let res = raw_http_request(addr, "POST", "/mcp", &[], "").unwrap();
            assert_eq!(res.status, 401);
            let auth_header = res.headers.get("www-authenticate").unwrap();
            let base_url = format!("http://127.0.0.1:{}", addr.port());
            assert!(auth_header.contains("error=\"invalid_request\""));
            assert!(auth_header.contains(&format!(
                "resource_metadata=\"{base_url}/.well-known/oauth-protected-resource/mcp\""
            )));
            let body = JsonValue::parse(&res.body).unwrap();
            assert_eq!(
                body.get("error")
                    .and_then(|e| e.get("code"))
                    .and_then(|c| c.as_i64()),
                Some(-32001)
            );
        });
    }

    #[test]
    fn returns_500_for_unexpected_verifier_failure_rather_than_hanging() {
        with_server(
            verifier_that(|| Err(Err("fetch failed: JWKS endpoint unreachable".to_string()))),
            |addr| {
                let res = raw_http_request(addr, "POST", "/mcp", &[], "").unwrap();
                assert_eq!(res.status, 500);
                assert_eq!(res.body, sdk_error_body(-32603, "Internal server error"));
            },
        );
    }

    #[test]
    fn answers_idp_outage_with_503_retry_after_and_no_auth_challenge() {
        with_server(
            verifier_that(|| {
                Err(Ok(AuthError::IdpUnavailable {
                    reason: "fetch failed".to_string(),
                }))
            }),
            |addr| {
                let res = raw_http_request(addr, "POST", "/mcp", &[], "").unwrap();
                assert_eq!(res.status, 503);
                assert_eq!(
                    res.headers.get("retry-after").map(|s| s.as_str()),
                    Some("30")
                );
                assert!(!res.headers.contains_key("www-authenticate"));
            },
        );
    }

    #[test]
    fn stays_up_and_serves_next_request_after_unexpected_failure() {
        let should_fail = Arc::new(AtomicBool::new(true));
        let sf = should_fail.clone();
        let flaky = verifier_that(move || {
            if sf.load(Ordering::SeqCst) {
                Err(Err("transient JWKS failure".to_string()))
            } else {
                Ok(())
            }
        });

        with_server(flaky, |addr| {
            let first = raw_http_request(addr, "POST", "/mcp", &[], "").unwrap();
            assert_eq!(first.status, 500);
            should_fail.store(false, Ordering::SeqCst);
            let second = raw_http_request(addr, "GET", "/health", &[], "").unwrap();
            assert_eq!(second.status, 200);
        });
    }

    #[test]
    fn header_safe_sanitizes_control_chars_and_double_quotes() {
        assert_eq!(header_safe("aud\r\nX-Injected: yes"), "aud X-Injected: yes");
        assert_eq!(header_safe("aud\nvalue"), "aud value");
        assert_eq!(header_safe("aud\0value"), "aud value");
        assert_eq!(header_safe("aud\"quoted"), "aud'quoted");
        let msg = "Token audience does not include this server's project (999).";
        assert_eq!(header_safe(msg), msg);
    }

    #[test]
    fn close_bounds_the_wait_on_an_active_request() {
        let release = Arc::new((Mutex::new(false), std::sync::Condvar::new()));
        let release_clone = release.clone();
        let mut listener = start_http_transport(
            || McpServer::new(SERVER_NAME, SERVER_VERSION),
            test_config(),
            verifier_that(move || {
                // A handler wedged on a hung upstream call until released after close().
                let (lock, cvar) = &*release_clone;
                let mut done = lock.lock().unwrap();
                while !*done {
                    let (guard, timeout) =
                        cvar.wait_timeout(done, Duration::from_secs(10)).unwrap();
                    done = guard;
                    if timeout.timed_out() {
                        break;
                    }
                }
                Ok(())
            }),
        )
        .unwrap();

        let addr = listener.address();
        let in_flight = std::thread::spawn(move || post_mcp(addr, "{}"));

        std::thread::sleep(Duration::from_millis(100));

        let started = Instant::now();
        listener.close(300).unwrap();
        let elapsed_ms = started.elapsed().as_millis();

        assert!(elapsed_ms >= 250, "Expected >= 250ms, got {elapsed_ms}ms");
        assert!(elapsed_ms < 5_000, "Expected < 5000ms, got {elapsed_ms}ms");
        // The forced connection is closed without a response.
        let res = in_flight.join().unwrap();
        assert_eq!(res.status, 0);

        let (lock, cvar) = &*release;
        *lock.lock().unwrap() = true;
        cvar.notify_all();
    }

    #[test]
    fn refusals_are_recorded_not_only_answered() {
        {
            let capture = capture_stderr();
            with_server(
                verifier_that(|| {
                    Err(Ok(AuthError::SubjectNotAllowed {
                        subject: "379361013981513322".to_string(),
                    }))
                }),
                |addr| {
                    assert_eq!(post_mcp(addr, "{}").status, 403);
                },
            );
            let lines = capture.lines();
            let refusal = lines.iter().find(|l| l.contains("refused")).unwrap();
            assert!(refusal.contains("sub=379361013981513322"));
        }
        {
            let capture = capture_stderr();
            with_server(
                verifier_that(|| {
                    Err(Ok(AuthError::ClientNotAllowed {
                        client_id: Some("777777777".to_string()),
                    }))
                }),
                |addr| {
                    let res = post_mcp(addr, "{}");
                    assert_eq!(res.status, 403);
                    assert!(!res
                        .headers
                        .get("www-authenticate")
                        .unwrap()
                        .contains("resource_metadata"));
                },
            );
            let lines = capture.lines();
            let refusal = lines.iter().find(|l| l.contains("refused")).unwrap();
            assert!(refusal.contains("client_id=777777777"));
            assert!(!refusal.contains("sub=777777777"));
        }
        {
            let capture = capture_stderr();
            with_server(verifier_that(|| Err(Ok(AuthError::MissingToken))), |addr| {
                let res = raw_http_request(addr, "POST", "/mcp", &[], "{}").unwrap();
                assert_eq!(res.status, 401);
            });
            let lines = capture.lines();
            assert!(lines.iter().all(|l| !l.contains("refused")));
        }
    }

    fn initialize_body(version: &str) -> String {
        format!(
            r#"{{"jsonrpc":"2.0","id":1,"method":"initialize","params":{{"protocolVersion":"{version}","capabilities":{{}},"clientInfo":{{"name":"regression-test-client","version":"0.0.0"}}}}}}"#
        )
    }

    #[test]
    fn fresh_server_and_transport_are_used_per_request_1491() {
        with_server(ok_verifier(), |addr| {
            for _ in 0..2 {
                let res = post_mcp(addr, &initialize_body("2025-11-25"));
                assert_eq!(res.status, 200);
                assert_eq!(
                    res.body,
                    "event: message\ndata: {\"result\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"mcp-slack\",\"version\":\"2.0.0\"}},\"jsonrpc\":\"2.0\",\"id\":1}\n\n"
                );
            }
        });
    }

    #[test]
    fn a_server_instance_refuses_a_second_stateless_request() {
        let server = McpServer::new(SERVER_NAME, SERVER_VERSION);
        assert!(server.begin_stateless_request().is_ok());
        assert!(server.begin_stateless_request().is_err());
    }

    // ----- deployment contract -----

    #[test]
    fn binds_every_interface_not_loopback() {
        let mut handle =
            start_http_transport(|| McpServer::new("t", "0"), test_config(), ok_verifier())
                .unwrap();
        assert!(
            handle.address().ip().is_unspecified(),
            "{}",
            handle.address()
        );
        handle.close(100).unwrap();
    }

    #[test]
    fn graceful_close_drains_an_in_flight_request_then_refuses_new_ones() {
        // SIGTERM path: main.rs calls close(SHUTDOWN_GRACE_MS).
        let mut handle = start_http_transport(
            || McpServer::new(SERVER_NAME, SERVER_VERSION),
            test_config(),
            verifier_that(|| {
                std::thread::sleep(Duration::from_millis(400));
                Ok(())
            }),
        )
        .unwrap();
        let addr = handle.address();
        let in_flight = std::thread::spawn(move || {
            post_mcp(addr, r#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        });
        std::thread::sleep(Duration::from_millis(100));
        let started = Instant::now();
        handle.close(5_000).unwrap();
        let elapsed = started.elapsed();
        let res = in_flight.join().unwrap();
        assert_eq!(res.status, 200, "{res:?}");
        assert_eq!(
            sse_events(&res.body),
            vec![JsonValue::parse(r#"{"result":{},"jsonrpc":"2.0","id":7}"#).unwrap()]
        );
        assert!(elapsed < Duration::from_secs(4), "{elapsed:?}");
        assert!(TcpStream::connect(local(addr)).is_err());
    }

    #[test]
    fn close_ends_an_open_get_stream_instead_of_waiting_out_the_grace() {
        let mut handle =
            start_http_transport(|| McpServer::new("t", "0"), test_config(), ok_verifier())
                .unwrap();
        let addr = handle.address();
        let reader = std::thread::spawn(move || {
            let mut s = TcpStream::connect(local(addr)).unwrap();
            s.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
            s.write_all(
                b"GET /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nAccept: text/event-stream\r\n\r\n",
            )
            .unwrap();
            let mut raw = Vec::new();
            let _ = s.read_to_end(&mut raw);
            parse_response(&raw)
        });
        std::thread::sleep(Duration::from_millis(200));
        let started = Instant::now();
        handle.close(8_000).unwrap();
        assert!(started.elapsed() < Duration::from_secs(3));
        let res = reader.join().unwrap();
        assert_eq!(res.status, 200);
        assert_eq!(
            res.headers.get("content-type").map(|s| s.as_str()),
            Some("text/event-stream")
        );
    }

    // ----- SDK wire behaviour (expected values from a live probe of 1.32.1) -----

    #[test]
    fn post_replies_as_server_sent_events_with_the_sdk_headers() {
        with_server(ok_verifier(), |addr| {
            let res = post_mcp(addr, r#"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#);
            assert_eq!(res.status, 200);
            assert_eq!(res.headers["content-type"], "text/event-stream");
            assert_eq!(res.headers["cache-control"], "no-cache, no-transform");
            assert_eq!(res.headers["x-accel-buffering"], "no");
            assert_eq!(
                res.body,
                "event: message\ndata: {\"result\":{},\"jsonrpc\":\"2.0\",\"id\":\"abc\"}\n\n"
            );
        });
    }

    #[test]
    fn rejects_bad_accept_with_406_and_bad_content_type_with_415() {
        with_server(ok_verifier(), |addr| {
            let ping = r#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#;
            let not_acceptable = sdk_error_body(
                -32000,
                "Not Acceptable: Client must accept both application/json and text/event-stream",
            );
            for accept in [None, Some("application/json"), Some("text/event-stream")] {
                let mut headers = vec![
                    ("Authorization", "Bearer t"),
                    ("Content-Type", "application/json"),
                ];
                if let Some(a) = accept {
                    headers.push(("Accept", a));
                }
                let res = raw_http_request(addr, "POST", "/mcp", &headers, ping).unwrap();
                assert_eq!(res.status, 406);
                assert_eq!(res.body, not_acceptable);
            }
            let unsupported = sdk_error_body(
                -32000,
                "Unsupported Media Type: Content-Type must be application/json",
            );
            for ct in ["text/plain", "text/plain; a=application/json"] {
                let res = raw_http_request(
                    addr,
                    "POST",
                    "/mcp",
                    &[
                        ("Authorization", "Bearer t"),
                        ("Accept", "application/json, text/event-stream"),
                        ("Content-Type", ct),
                    ],
                    ping,
                )
                .unwrap();
                assert_eq!(res.status, 415, "{ct}");
                assert_eq!(res.body, unsupported);
            }
            // Duplicate Content-Type headers are joined, as WHATWG Headers does.
            let res = raw_http_request(
                addr,
                "POST",
                "/mcp",
                &[
                    ("Authorization", "Bearer t"),
                    ("Accept", "application/json, text/event-stream"),
                    ("Content-Type", "application/json"),
                    ("Content-Type", "text/plain"),
                ],
                ping,
            )
            .unwrap();
            assert_eq!(res.status, 415);
            let res = raw_http_request(
                addr,
                "POST",
                "/mcp",
                &[
                    ("Authorization", "Bearer t"),
                    ("Accept", "application/json, text/event-stream"),
                    ("Content-Type", "Application/JSON; charset=utf-8"),
                ],
                ping,
            )
            .unwrap();
            assert_eq!(res.status, 200);
        });
    }

    #[test]
    fn malformed_bodies_get_400_parse_errors_not_500() {
        with_server(ok_verifier(), |addr| {
            let invalid_json = sdk_error_body(-32700, "Parse error: Invalid JSON");
            for body in [
                "{not json",
                "",
                "   ",
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"} x",
            ] {
                let res = post_mcp(addr, body);
                assert_eq!(res.status, 400, "{body:?}");
                assert_eq!(res.body, invalid_json);
            }
            let invalid_message = sdk_error_body(-32700, "Parse error: Invalid JSON-RPC message");
            for body in [
                r#"{"hello":1}"#,
                r#"42"#,
                r#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#,
                r#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#,
                r#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#,
                r#"{"jsonrpc":"2.0","id":1.5,"method":"ping"}"#,
                r#"{"jsonrpc":"2.0","id":1,"method":5}"#,
                r#"{"jsonrpc":"2.0","id":1,"method":"ping","params":[1]}"#,
                r#"{"jsonrpc":"2.0","id":1,"method":"ping","extra":1}"#,
                r#"{"jsonrpc":"2.0","id":1,"result":{},"error":{"code":1,"message":"m"}}"#,
                r#"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"foo":1}]"#,
            ] {
                let res = post_mcp(addr, body);
                assert_eq!(res.status, 400, "{body}");
                assert_eq!(res.body, invalid_message, "{body}");
            }
        });
    }

    #[test]
    fn chunked_request_bodies_are_read() {
        with_server(ok_verifier(), |addr| {
            let body = r#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#;
            let req = format!(
                "POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n{:x}\r\n{body}\r\n0\r\n\r\n",
                body.len()
            );
            let res = send_raw(addr, req.as_bytes());
            assert_eq!(res.status, 200);
            assert_eq!(
                res.body,
                "event: message\ndata: {\"result\":{},\"jsonrpc\":\"2.0\",\"id\":7}\n\n"
            );
            // An empty chunked body is a parse error, like an empty fixed one.
            let req = "POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n0\r\n\r\n";
            let res = send_raw(addr, req.as_bytes());
            assert_eq!(res.status, 400);
            assert_eq!(
                res.body,
                sdk_error_body(-32700, "Parse error: Invalid JSON")
            );
        });
    }

    #[test]
    fn notifications_and_responses_get_202_with_no_body() {
        with_server(ok_verifier(), |addr| {
            for body in [
                r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                r#"{"jsonrpc":"2.0","method":"notifications/whatever"}"#,
                r#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"slack_post_message"}}"#,
                r#"{"jsonrpc":"2.0","id":9,"result":{}}"#,
                r#"{"jsonrpc":"2.0","id":9,"error":{"code":-1,"message":"x"}}"#,
                r#"[]"#,
            ] {
                let res = post_mcp(addr, body);
                assert_eq!(res.status, 202, "{body}");
                assert_eq!(res.body, "", "{body}");
                assert!(!res.headers.contains_key("content-type"));
            }
        });
    }

    #[test]
    fn batches_answer_every_request_and_cap_at_100() {
        with_server(ok_verifier(), |addr| {
            let res = post_mcp(
                addr,
                r#"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":2,"method":"tools/list"}]"#,
            );
            assert_eq!(res.status, 200);
            let mut events: Vec<String> = sse_events(&res.body)
                .iter()
                .map(|e| e.to_string())
                .collect();
            events.sort();
            assert_eq!(
                events,
                vec![
                    r#"{"result":{"tools":[]},"jsonrpc":"2.0","id":2}"#.to_string(),
                    r#"{"result":{},"jsonrpc":"2.0","id":1}"#.to_string(),
                ]
            );

            let batch: Vec<String> = (0..101)
                .map(|i| format!(r#"{{"jsonrpc":"2.0","method":"notifications/x{i}"}}"#))
                .collect();
            let res = post_mcp(addr, &format!("[{}]", batch.join(",")));
            assert_eq!(res.status, 400);
            assert_eq!(
                res.body,
                sdk_error_body(
                    -32600,
                    "Invalid Request: Batch must not exceed 100 messages"
                )
            );

            let res = post_mcp(
                addr,
                &format!(
                    "[{},{}]",
                    initialize_body("2025-06-18"),
                    r#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#
                ),
            );
            assert_eq!(res.status, 400);
            assert_eq!(
                res.body,
                sdk_error_body(
                    -32600,
                    "Invalid Request: Only one initialization request is allowed"
                )
            );
        });
    }

    #[test]
    fn protocol_version_header_is_validated_except_on_initialize() {
        with_server(ok_verifier(), |addr| {
            let ping = r#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#;
            let mut headers = MCP_HEADERS.to_vec();
            headers.push(("mcp-protocol-version", "1999-01-01"));
            let res = raw_http_request(addr, "POST", "/mcp", &headers, ping).unwrap();
            assert_eq!(res.status, 400);
            assert_eq!(
                res.body,
                sdk_error_body(-32000, "Bad Request: Unsupported protocol version: 1999-01-01 (supported versions: 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05, 2024-10-07)")
            );
            let res = raw_http_request(
                addr,
                "POST",
                "/mcp",
                &headers,
                &initialize_body("2025-06-18"),
            )
            .unwrap();
            assert_eq!(res.status, 200);
            let mut ok = MCP_HEADERS.to_vec();
            ok.push(("mcp-protocol-version", "2024-11-05"));
            assert_eq!(
                raw_http_request(addr, "POST", "/mcp", &ok, ping)
                    .unwrap()
                    .status,
                200
            );
        });
    }

    #[test]
    fn other_methods_match_the_stateless_sdk() {
        with_server(ok_verifier(), |addr| {
            let auth = [("Authorization", "Bearer t")];
            let res = raw_http_request(addr, "GET", "/mcp", &auth, "").unwrap();
            assert_eq!(res.status, 406);
            assert_eq!(
                res.body,
                sdk_error_body(
                    -32000,
                    "Not Acceptable: Client must accept text/event-stream"
                )
            );
            let res = raw_http_request(
                addr,
                "GET",
                "/mcp",
                &[
                    ("Authorization", "Bearer t"),
                    ("Accept", "text/event-stream"),
                    ("mcp-protocol-version", "x"),
                ],
                "",
            )
            .unwrap();
            assert_eq!(res.status, 400);

            let res = raw_http_request(addr, "DELETE", "/mcp", &auth, "").unwrap();
            assert_eq!(res.status, 200);
            assert_eq!(res.body, "");

            for method in ["PUT", "PATCH", "OPTIONS"] {
                let res = raw_http_request(addr, method, "/mcp", &auth, "").unwrap();
                assert_eq!(res.status, 405, "{method}");
                assert_eq!(res.headers["allow"], "GET, POST, DELETE");
                assert_eq!(res.body, sdk_error_body(-32000, "Method not allowed."));
            }
            let res = raw_http_request(addr, "HEAD", "/mcp", &auth, "").unwrap();
            assert_eq!(res.status, 405);
            assert_eq!(res.body, "");
        });
    }

    #[test]
    fn get_opens_an_event_stream() {
        with_server(ok_verifier(), |addr| {
            let mut s = TcpStream::connect(local(addr)).unwrap();
            s.set_read_timeout(Some(Duration::from_millis(500)))
                .unwrap();
            s.write_all(b"GET /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nAccept: text/event-stream\r\n\r\n")
                .unwrap();
            let mut buf = [0u8; 1024];
            let n = s.read(&mut buf).unwrap();
            let head = String::from_utf8_lossy(&buf[..n]).to_string();
            assert!(head.starts_with("HTTP/1.1 200"), "{head}");
            assert!(head.contains("content-type: text/event-stream"), "{head}");
        });
    }

    #[test]
    fn caps_request_bodies_at_4_mib_with_413() {
        with_server(ok_verifier(), |addr| {
            let expected = sdk_error_body(
                -32000,
                "Payload Too Large: Request body must not exceed 4194304 bytes",
            );
            // Declared too large: refused before reading (and before allocating).
            let req = "POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nContent-Length: 999999999999\r\nConnection: close\r\n\r\n";
            let res = send_raw(addr, req.as_bytes());
            assert_eq!(res.status, 413);
            assert_eq!(res.body, expected);

            // Streamed too large: refused once the cap is crossed.
            let mut s = TcpStream::connect(local(addr)).unwrap();
            s.set_read_timeout(Some(Duration::from_secs(10))).unwrap();
            let mut writer = s.try_clone().unwrap();
            let sender = std::thread::spawn(move || {
                let _ = writer.write_all(b"POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n");
                let chunk = vec![b' '; 64 * 1024];
                for _ in 0..80 {
                    if writer
                        .write_all(format!("{:x}\r\n", chunk.len()).as_bytes())
                        .is_err()
                        || writer.write_all(&chunk).is_err()
                        || writer.write_all(b"\r\n").is_err()
                    {
                        return;
                    }
                }
                let _ = writer.write_all(b"0\r\n\r\n");
            });
            let mut raw = Vec::new();
            let _ = s.read_to_end(&mut raw);
            let res = parse_response(&raw);
            assert_eq!(res.status, 413);
            assert_eq!(res.body, expected);
            let _ = sender.join();
        });
    }

    #[test]
    fn oversized_headers_get_431() {
        with_server(ok_verifier(), |addr| {
            let big = "a".repeat(20 * 1024);
            let req = format!("GET /health HTTP/1.1\r\nHost: x\r\nX-Big: {big}\r\n\r\n");
            let res = send_raw(addr, req.as_bytes());
            assert_eq!(res.status, 431);
            // Under the limit is fine.
            let ok = format!(
                "GET /health HTTP/1.1\r\nHost: x\r\nX-Big: {}\r\nConnection: close\r\n\r\n",
                "a".repeat(8 * 1024)
            );
            assert_eq!(send_raw(addr, ok.as_bytes()).status, 200);
        });
    }

    #[test]
    fn slow_clients_are_timed_out() {
        let limits = TransportLimits {
            header_read_timeout: Duration::from_millis(300),
            request_timeout: Duration::from_millis(500),
            ..TransportLimits::default()
        };
        let mut handle = start_http_transport_with_limits(
            || McpServer::new("t", "0"),
            test_config(),
            ok_verifier(),
            limits,
        )
        .unwrap();
        let addr = handle.address();

        // Headers never finish: the connection is closed.
        let started = Instant::now();
        let res = send_raw(addr, b"GET /health HTTP/1.1\r\nHost: x\r\n");
        assert_eq!(res.status, 0);
        assert!(started.elapsed() < Duration::from_secs(3));

        // Body never finishes: 408, like Node's requestTimeout.
        let res = send_raw(
            addr,
            b"POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nContent-Length: 100\r\n\r\n{\"js",
        );
        assert_eq!(res.status, 408);
        handle.close(100).unwrap();
    }

    #[test]
    fn a_panicking_handler_is_a_500_and_the_server_stays_up() {
        let capture = capture_stderr();
        with_server(
            verifier_that(|| panic!("byte index 6 is not a char boundary")),
            |addr| {
                let res = post_mcp(addr, "{}");
                assert_eq!(res.status, 500);
                assert_eq!(res.body, sdk_error_body(-32603, "Internal server error"));
                assert_eq!(
                    raw_http_request(addr, "GET", "/health", &[], "")
                        .unwrap()
                        .status,
                    200
                );
            },
        );
        assert!(capture
            .lines()
            .iter()
            .any(|l| l.contains("unhandled error serving POST /mcp")));
    }

    #[test]
    fn non_ascii_authorization_reaches_the_verifier_as_latin1_and_never_hangs() {
        let seen = Arc::new(Mutex::new(None::<String>));
        let seen2 = seen.clone();
        with_server(
            verifier_with_header(move |h| {
                *seen2.lock().unwrap() = h.map(|s| s.to_string());
                Err(Ok(AuthError::InvalidToken {
                    reason: "bad".to_string(),
                }))
            }),
            |addr| {
                let req = b"POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bear\xe9r t\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                let res = send_raw(addr, req);
                assert_eq!(res.status, 401);
            },
        );
        assert_eq!(seen.lock().unwrap().as_deref(), Some("Bear\u{e9}r t"));
    }

    #[test]
    fn duplicate_authorization_headers_use_the_first_like_node() {
        let seen = Arc::new(Mutex::new(None::<String>));
        let seen2 = seen.clone();
        with_server(
            verifier_with_header(move |h| {
                *seen2.lock().unwrap() = h.map(|s| s.to_string());
                Ok(())
            }),
            |addr| {
                let res = raw_http_request(
                    addr,
                    "DELETE",
                    "/mcp",
                    &[
                        ("Authorization", "Bearer first"),
                        ("Authorization", "Bearer second"),
                    ],
                    "",
                )
                .unwrap();
                assert_eq!(res.status, 200);
            },
        );
        assert_eq!(seen.lock().unwrap().as_deref(), Some("Bearer first"));
    }

    #[test]
    fn expect_100_continue_is_honoured_and_other_expectations_get_417() {
        with_server(ok_verifier(), |addr| {
            let body = r#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#;
            let mut s = TcpStream::connect(local(addr)).unwrap();
            s.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
            s.write_all(format!("POST /mcp HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer t\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream\r\nExpect: 100-continue\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len()).as_bytes()).unwrap();
            let mut buf = [0u8; 256];
            let n = s.read(&mut buf).unwrap();
            assert!(String::from_utf8_lossy(&buf[..n]).starts_with("HTTP/1.1 100 Continue"));
            s.write_all(body.as_bytes()).unwrap();
            let mut raw = Vec::new();
            let _ = s.read_to_end(&mut raw);
            let res = parse_response(&raw);
            assert_eq!(res.status, 200);

            let res = raw_http_request(addr, "GET", "/health", &[("Expect", "something-else")], "")
                .unwrap();
            assert_eq!(res.status, 417);
        });
    }

    #[test]
    fn paths_are_normalised_like_whatwg_url() {
        let p = |s: &str| whatwg_pathname(&s.parse::<Uri>().unwrap());
        assert_eq!(p("/mcp"), "/mcp");
        assert_eq!(p("/mcp?x=1"), "/mcp");
        assert_eq!(p("/x/../mcp"), "/mcp");
        assert_eq!(p("/./health"), "/health");
        assert_eq!(p("/x/%2E%2e/mcp"), "/mcp");
        assert_eq!(p("/mcp/."), "/mcp/");
        assert_eq!(p("/mcp/.."), "/");
        assert_eq!(p("//health"), "/");
        assert_eq!(p("//host/mcp"), "/mcp");
        assert_eq!(p("http://example.com/mcp"), "/mcp");
        assert_eq!(p("*"), "/*");

        with_server(verifier_that(|| Err(Ok(AuthError::MissingToken))), |addr| {
            assert_eq!(
                raw_http_request(addr, "POST", "/x/../mcp", &[], "")
                    .unwrap()
                    .status,
                401
            );
            assert_eq!(
                raw_http_request(addr, "GET", "/./health", &[], "")
                    .unwrap()
                    .status,
                200
            );
            assert_eq!(
                raw_http_request(addr, "GET", "/health/", &[], "")
                    .unwrap()
                    .status,
                404
            );
        });
    }

    #[test]
    fn malformed_request_lines_get_400() {
        with_server(ok_verifier(), |addr| {
            let res = send_raw(addr, b"THIS IS NOT HTTP\r\n\r\n");
            assert_eq!(res.status, 400);
        });
    }

    // ----- protocol layer -----

    #[test]
    fn initialize_negotiates_like_the_sdk() {
        let server = McpServer::new(SERVER_NAME, SERVER_VERSION);
        let id = JsonValue::Number(1.0);
        for (requested, negotiated) in [
            ("2025-06-18", "2025-06-18"),
            ("2024-10-07", "2024-10-07"),
            ("1999-01-01", LATEST_PROTOCOL_VERSION),
        ] {
            let params = JsonValue::parse(&format!(
                r#"{{"protocolVersion":"{requested}","capabilities":{{}},"clientInfo":{{"name":"c","version":"1"}}}}"#
            ))
            .unwrap();
            let resp = server.handle_request(&id, "initialize", Some(&params));
            assert_eq!(
                resp.get("result")
                    .and_then(|r| r.get("protocolVersion"))
                    .and_then(|v| v.as_str()),
                Some(negotiated)
            );
        }
    }

    #[test]
    fn invalid_params_get_the_sdks_zod_error() {
        let server = McpServer::new(SERVER_NAME, SERVER_VERSION);
        let id = JsonValue::Number(1.0);
        let call = |method: &str, params: Option<&str>| {
            let params = params.map(|p| JsonValue::parse(p).unwrap());
            server
                .handle_request(&id, method, params.as_ref())
                .to_string()
        };
        // Literal SDK 1.32.1 output.
        assert_eq!(
            call("tools/call", Some(r#"{"name":123}"#)),
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"[\n  {\n    \"expected\": \"string\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"params\",\n      \"name\"\n    ],\n    \"message\": \"Invalid input: expected string, received number\"\n  }\n]"}}"#
        );
        assert_eq!(
            call("tools/call", Some(r#"{"name":"x","arguments":"s"}"#)),
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"[\n  {\n    \"expected\": \"record\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"params\",\n      \"arguments\"\n    ],\n    \"message\": \"Invalid input: expected record, received string\"\n  }\n]"}}"#
        );
        assert_eq!(
            call("tools/call", None),
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"[\n  {\n    \"expected\": \"object\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"params\"\n    ],\n    \"message\": \"Invalid input: expected object, received undefined\"\n  }\n]"}}"#
        );
        assert_eq!(
            call("initialize", Some("{}")),
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603,"message":"[\n  {\n    \"expected\": \"string\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"params\",\n      \"protocolVersion\"\n    ],\n    \"message\": \"Invalid input: expected string, received undefined\"\n  },\n  {\n    \"expected\": \"object\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"params\",\n      \"capabilities\"\n    ],\n    \"message\": \"Invalid input: expected object, received undefined\"\n  },\n  {\n    \"expected\": \"object\",\n    \"code\": \"invalid_type\",\n    \"path\": [\n      \"params\",\n      \"clientInfo\"\n    ],\n    \"message\": \"Invalid input: expected object, received undefined\"\n  }\n]"}}"#
        );
        assert_eq!(
            call("tools/call", Some(r#"{"name":"x"}"#)),
            r#"{"result":{"content":[{"type":"text","text":"{\"error\":\"Tool x is not available on this transport.\"}"}]},"jsonrpc":"2.0","id":1}"#
        );
        assert_eq!(
            call("nope", None),
            r#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}"#
        );
    }

    #[test]
    fn stdio_answers_requests_only() {
        let server = McpServer::new(SERVER_NAME, SERVER_VERSION);
        assert_eq!(
            server
                .handle_jsonrpc_message(r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
                .unwrap(),
            None
        );
        // No id: never dispatched, nothing written.
        assert_eq!(
            server
                .handle_jsonrpc_message(
                    r#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"slack_post_message"}}"#
                )
                .unwrap(),
            None
        );
        assert!(server.handle_jsonrpc_message("{oops").is_err());
        assert!(server
            .handle_jsonrpc_message(r#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)
            .is_err());
        assert_eq!(
            server
                .handle_jsonrpc_message(r#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)
                .unwrap()
                .unwrap()
                .to_string(),
            r#"{"result":{},"jsonrpc":"2.0","id":3}"#
        );
    }

    #[test]
    fn json_content_type_matches_the_sdk_parser() {
        assert!(is_json_content_type(Some("application/json")));
        assert!(is_json_content_type(Some(
            "application/json; charset=utf-8"
        )));
        assert!(is_json_content_type(Some("APPLICATION/JSON")));
        assert!(is_json_content_type(Some("application/json;")));
        assert!(!is_json_content_type(Some(
            "text/plain; a=application/json"
        )));
        assert!(!is_json_content_type(Some("application/json, text/plain")));
        assert!(!is_json_content_type(None));
        assert!(!is_json_content_type(Some("")));
    }
}
