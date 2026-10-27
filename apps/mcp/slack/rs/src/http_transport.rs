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

use crate::auth::{audience_scope_for, AuthError, TokenVerifier};
use crate::config::HttpConfig;
use crate::dispatch::dispatch;
use crate::json::JsonValue;
use crate::slack_client::SlackClient;
use crate::tools::ToolDefinition;
use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

const MCP_PATH: &str = "/mcp";
const HEALTH_PATH: &str = "/health";
const OAUTH_PROTECTED_RESOURCE_PATH: &str = "/.well-known/oauth-protected-resource";

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

/// Stateless single-request MCP server instance.
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

    /// Processes a single stateless HTTP MCP request, failing if reused across requests.
    pub fn handle_stateless_http(&self, body: &str) -> Result<Option<JsonValue>, String> {
        if self.has_handled_request.swap(true, Ordering::SeqCst) {
            return Err(
                "Stateless StreamableHTTPServerTransport cannot handle more than one request"
                    .to_string(),
            );
        }
        self.handle_jsonrpc_message(body)
    }

    pub fn handle_jsonrpc_message(&self, body: &str) -> Result<Option<JsonValue>, String> {
        let parsed = JsonValue::parse(body).map_err(|e| format!("Invalid JSON: {e}"))?;
        let method = parsed.get("method").and_then(|v| v.as_str()).unwrap_or("");
        let id = parsed.get("id").cloned().unwrap_or(JsonValue::Null);

        match method {
            "initialize" => {
                let protocol_version = parsed
                    .get("params")
                    .and_then(|p| p.get("protocolVersion"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("2024-11-05");
                Ok(Some(JsonValue::object(vec![
                    ("jsonrpc", JsonValue::str("2.0")),
                    ("id", id),
                    (
                        "result",
                        JsonValue::object(vec![
                            ("protocolVersion", JsonValue::str(protocol_version)),
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
                    ),
                ])))
            }
            "notifications/initialized" => Ok(None),
            "ping" => Ok(Some(JsonValue::object(vec![
                ("jsonrpc", JsonValue::str("2.0")),
                ("id", id),
                ("result", JsonValue::object(vec![])),
            ]))),
            "tools/list" => {
                let tools_json: Vec<JsonValue> =
                    self.advertised_tools.iter().map(|t| t.to_json()).collect();
                Ok(Some(JsonValue::object(vec![
                    ("jsonrpc", JsonValue::str("2.0")),
                    ("id", id),
                    (
                        "result",
                        JsonValue::object(vec![("tools", JsonValue::Array(tools_json))]),
                    ),
                ])))
            }
            "tools/call" => {
                let params = parsed
                    .get("params")
                    .cloned()
                    .unwrap_or_else(|| JsonValue::object(vec![]));
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

                Ok(Some(JsonValue::object(vec![
                    ("jsonrpc", JsonValue::str("2.0")),
                    ("id", id),
                    (
                        "result",
                        JsonValue::object(vec![(
                            "content",
                            JsonValue::Array(vec![JsonValue::object(vec![
                                ("type", JsonValue::str("text")),
                                ("text", JsonValue::str(&text)),
                            ])]),
                        )]),
                    ),
                ])))
            }
            _ => Ok(Some(JsonValue::object(vec![
                ("jsonrpc", JsonValue::str("2.0")),
                ("id", id),
                (
                    "error",
                    JsonValue::object(vec![
                        ("code", JsonValue::Number(-32601.0)),
                        ("message", JsonValue::str("Method not found")),
                    ]),
                ),
            ]))),
        }
    }
}

pub struct HttpTransportHandle {
    addr: SocketAddr,
    shutting_down: Arc<AtomicBool>,
    active_streams: Arc<Mutex<HashMap<u64, TcpStream>>>,
    in_flight: Arc<(Mutex<usize>, Condvar)>,
    accept_thread: Option<std::thread::JoinHandle<()>>,
}

impl HttpTransportHandle {
    pub fn address(&self) -> SocketAddr {
        self.addr
    }

    pub fn close(&mut self, grace_period_ms: u64) -> Result<(), String> {
        if self.shutting_down.swap(true, Ordering::SeqCst) {
            return Ok(());
        }
        // Wake the blocking accept() call by connecting once to the listener address.
        let _ = TcpStream::connect_timeout(&self.addr, Duration::from_millis(50));

        if let Some(handle) = self.accept_thread.take() {
            let _ = handle.join();
        }

        // Wait up to grace_period_ms for active requests to finish.
        let deadline = Instant::now() + Duration::from_millis(grace_period_ms);
        let (lock, cvar) = &*self.in_flight;
        let mut active = lock.lock().unwrap();
        while *active > 0 {
            let now = Instant::now();
            if now >= deadline {
                break;
            }
            let remaining = deadline - now;
            let (guard, timeout_res) = cvar.wait_timeout(active, remaining).unwrap();
            active = guard;
            if timeout_res.timed_out() {
                break;
            }
        }
        drop(active);

        // Force close any remaining connections.
        if let Ok(mut streams) = self.active_streams.lock() {
            for (_, stream) in streams.drain() {
                let _ = stream.shutdown(Shutdown::Both);
            }
        }

        Ok(())
    }
}

impl Drop for HttpTransportHandle {
    fn drop(&mut self) {
        let _ = self.close(100);
    }
}

fn write_http_response(
    stream: &mut TcpStream,
    status: u16,
    reason: &str,
    headers: &[(&str, &str)],
    body: &str,
) {
    let mut resp = format!(
        "HTTP/1.1 {status} {reason}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    );
    for (k, v) in headers {
        resp.push_str(&format!("{k}: {v}\r\n"));
    }
    resp.push_str("\r\n");
    resp.push_str(body);
    let _ = stream.write_all(resp.as_bytes());
    let _ = stream.flush();
    let _ = stream.shutdown(Shutdown::Both);
}

fn write_auth_failure(stream: &mut TcpStream, error: &AuthError, metadata_url: Option<&str>) {
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
        write_http_response(
            stream,
            503,
            "Service Unavailable",
            &[("Retry-After", "30")],
            &body,
        );
        return;
    }

    let auth_header = if status == 401 {
        if let Some(meta) = metadata_url {
            format!(
                "Bearer error=\"{code}\", error_description=\"{}\", resource_metadata=\"{meta}\"",
                header_safe(&msg)
            )
        } else {
            format!(
                "Bearer error=\"{code}\", error_description=\"{}\"",
                header_safe(&msg)
            )
        }
    } else {
        format!(
            "Bearer error=\"{code}\", error_description=\"{}\"",
            header_safe(&msg)
        )
    };

    let reason = match status {
        401 => "Unauthorized",
        403 => "Forbidden",
        _ => "Error",
    };

    write_http_response(
        stream,
        status,
        reason,
        &[("WWW-Authenticate", &auth_header)],
        &body,
    );
}

fn handle_connection<F>(
    mut stream: TcpStream,
    create_server: &F,
    config: &HttpConfig,
    verifier: &dyn TokenVerifier,
) where
    F: Fn() -> McpServer + Send + Sync + 'static,
{
    let mut reader = match stream.try_clone() {
        Ok(s) => BufReader::new(s),
        Err(_) => return,
    };

    let mut request_line = String::new();
    if reader.read_line(&mut request_line).unwrap_or(0) == 0 {
        return;
    }
    let parts: Vec<&str> = request_line.trim_end().split_whitespace().collect();
    if parts.len() < 2 {
        return;
    }
    let method = parts[0].to_uppercase();
    let raw_target = parts[1];
    let pathname = raw_target.split('?').next().unwrap_or("/");

    let mut headers = HashMap::new();
    let mut content_length = 0usize;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim().to_ascii_lowercase();
            let val = v.trim().to_string();
            if key == "content-length" {
                content_length = val.parse::<usize>().unwrap_or(0);
            }
            headers.insert(key, val);
        }
    }

    let mut body_bytes = vec![0u8; content_length];
    if content_length > 0 {
        let _ = reader.read_exact(&mut body_bytes);
    }
    let body_str = String::from_utf8_lossy(&body_bytes).to_string();

    if pathname == HEALTH_PATH {
        let body = JsonValue::object(vec![("status", JsonValue::str("ok"))]).to_string();
        write_http_response(&mut stream, 200, "OK", &[], &body);
        return;
    }

    let origin = get_request_origin(&headers, false);
    let metadata_url = format!("{origin}{OAUTH_PROTECTED_RESOURCE_PATH}{MCP_PATH}");

    if pathname == OAUTH_PROTECTED_RESOURCE_PATH
        || pathname == format!("{OAUTH_PROTECTED_RESOURCE_PATH}{MCP_PATH}")
    {
        let body = JsonValue::object(vec![
            ("resource", JsonValue::str(&format!("{origin}{MCP_PATH}"))),
            (
                "authorization_servers",
                JsonValue::Array(vec![JsonValue::str(&config.issuer)]),
            ),
            (
                "scopes_supported",
                JsonValue::Array(vec![
                    JsonValue::str("openid"),
                    JsonValue::str("offline_access"),
                    JsonValue::str(&audience_scope_for(&config.project_id)),
                ]),
            ),
        ])
        .to_string();
        write_http_response(&mut stream, 200, "OK", &[], &body);
        return;
    }

    if pathname != MCP_PATH {
        let body = JsonValue::object(vec![("error", JsonValue::str("not_found"))]).to_string();
        write_http_response(&mut stream, 404, "Not Found", &[], &body);
        return;
    }

    let auth_header = headers.get("authorization").map(|s| s.as_str());
    match verifier.verify_authorization_header(auth_header) {
        Ok(_) => {}
        Err(Ok(auth_err)) => {
            write_auth_failure(&mut stream, &auth_err, Some(&metadata_url));
            return;
        }
        Err(Err(unexpected_msg)) => {
            write_stderr(&format!(
                "mcp-slack: unhandled error serving {method} {raw_target}: {unexpected_msg}\n"
            ));
            let err_body = JsonValue::object(vec![
                ("jsonrpc", JsonValue::str("2.0")),
                (
                    "error",
                    JsonValue::object(vec![
                        ("code", JsonValue::Number(-32603.0)),
                        ("message", JsonValue::str("Internal server error")),
                    ]),
                ),
                ("id", JsonValue::Null),
            ])
            .to_string();
            write_http_response(&mut stream, 500, "Internal Server Error", &[], &err_body);
            return;
        }
    }

    // Create a fresh McpServer per request (stateless mode #1491 / GHSA-345p-7cg4-v4c7).
    let request_server = create_server();
    let body_trimmed = body_str.trim();
    if body_trimmed.is_empty() {
        let ok_body = JsonValue::object(vec![
            ("jsonrpc", JsonValue::str("2.0")),
            ("result", JsonValue::object(vec![])),
            ("id", JsonValue::Null),
        ])
        .to_string();
        write_http_response(&mut stream, 200, "OK", &[], &ok_body);
        return;
    }

    match request_server.handle_stateless_http(body_trimmed) {
        Ok(Some(resp_json)) => {
            write_http_response(&mut stream, 200, "OK", &[], &resp_json.to_string());
        }
        Ok(None) => {
            write_http_response(&mut stream, 202, "Accepted", &[], "");
        }
        Err(err) => {
            write_stderr(&format!(
                "mcp-slack: unhandled error serving {method} {raw_target}: {err}\n"
            ));
            let err_body = JsonValue::object(vec![
                ("jsonrpc", JsonValue::str("2.0")),
                (
                    "error",
                    JsonValue::object(vec![
                        ("code", JsonValue::Number(-32603.0)),
                        ("message", JsonValue::str("Internal server error")),
                    ]),
                ),
                ("id", JsonValue::Null),
            ])
            .to_string();
            write_http_response(&mut stream, 500, "Internal Server Error", &[], &err_body);
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
    let listener = TcpListener::bind(("127.0.0.1", config.port))
        .map_err(|e| format!("Failed to bind HTTP transport port {}: {e}", config.port))?;
    let addr = listener
        .local_addr()
        .map_err(|e| format!("Failed to read bound local address: {e}"))?;

    let shutting_down = Arc::new(AtomicBool::new(false));
    let active_streams: Arc<Mutex<HashMap<u64, TcpStream>>> = Arc::new(Mutex::new(HashMap::new()));
    let in_flight = Arc::new((Mutex::new(0usize), Condvar::new()));
    let next_conn_id = Arc::new(AtomicU64::new(1));
    let create_server = Arc::new(create_server);

    let shutting_down_clone = shutting_down.clone();
    let active_streams_clone = active_streams.clone();
    let in_flight_clone = in_flight.clone();

    let accept_thread = std::thread::spawn(move || {
        for incoming in listener.incoming() {
            if shutting_down_clone.load(Ordering::SeqCst) {
                break;
            }
            let stream = match incoming {
                Ok(s) => s,
                Err(_) => {
                    if shutting_down_clone.load(Ordering::SeqCst) {
                        break;
                    }
                    continue;
                }
            };
            if shutting_down_clone.load(Ordering::SeqCst) {
                let _ = stream.shutdown(Shutdown::Both);
                break;
            }

            let conn_id = next_conn_id.fetch_add(1, Ordering::SeqCst);
            if let Ok(cloned) = stream.try_clone() {
                active_streams_clone.lock().unwrap().insert(conn_id, cloned);
            }
            {
                let (lock, _) = &*in_flight_clone;
                *lock.lock().unwrap() += 1;
            }

            let create_server_req = create_server.clone();
            let config_req = config.clone();
            let verifier_req = verifier.clone();
            let active_streams_req = active_streams_clone.clone();
            let in_flight_req = in_flight_clone.clone();

            std::thread::spawn(move || {
                handle_connection(stream, &*create_server_req, &config_req, &*verifier_req);
                active_streams_req.lock().unwrap().remove(&conn_id);
                let (lock, cvar) = &*in_flight_req;
                let mut count = lock.lock().unwrap();
                *count = count.saturating_sub(1);
                if *count == 0 {
                    cvar.notify_all();
                }
            });
        }
    });

    Ok(HttpTransportHandle {
        addr,
        shutting_down,
        active_streams,
        in_flight,
        accept_thread: Some(accept_thread),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::VerifiedCaller;

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
        F: Fn() -> Result<VerifiedCaller, Result<AuthError, String>> + Send + Sync,
    {
        f: F,
    }

    impl<F> TokenVerifier for ClosureVerifier<F>
    where
        F: Fn() -> Result<VerifiedCaller, Result<AuthError, String>> + Send + Sync,
    {
        fn verify(&self, _token: &str) -> Result<VerifiedCaller, Result<AuthError, String>> {
            (self.f)()
        }

        fn verify_authorization_header(
            &self,
            _header: Option<&str>,
        ) -> Result<VerifiedCaller, Result<AuthError, String>> {
            (self.f)()
        }
    }

    fn verifier_that<F>(f: F) -> Arc<dyn TokenVerifier>
    where
        F: Fn() -> Result<(), Result<AuthError, String>> + Send + Sync + 'static,
    {
        Arc::new(ClosureVerifier {
            f: move || {
                f()?;
                Ok(VerifiedCaller {
                    subject: "user-42".to_string(),
                    claims: JsonValue::object(vec![]),
                })
            },
        })
    }

    fn ok_verifier() -> Arc<dyn TokenVerifier> {
        verifier_that(|| Ok(()))
    }

    struct RawHttpResponse {
        status: u16,
        headers: HashMap<String, String>,
        body: String,
    }

    fn raw_http_request(
        addr: SocketAddr,
        method: &str,
        path: &str,
        headers: &[(&str, &str)],
        body: &str,
    ) -> std::io::Result<RawHttpResponse> {
        let mut stream = TcpStream::connect(addr)?;
        stream.set_read_timeout(Some(Duration::from_secs(5)))?;
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
        stream.write_all(req.as_bytes())?;
        stream.flush()?;

        let mut raw = String::new();
        let _ = stream.read_to_string(&mut raw);
        let (head, resp_body) = raw.split_once("\r\n\r\n").unwrap_or((&raw, ""));
        let mut lines = head.lines();
        let status_line = lines.next().unwrap_or("");
        let status = status_line
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse::<u16>().ok())
            .unwrap_or(0);
        let mut resp_headers = HashMap::new();
        for line in lines {
            if let Some((k, v)) = line.split_once(':') {
                resp_headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
            }
        }
        Ok(RawHttpResponse {
            status,
            headers: resp_headers,
            body: resp_body.to_string(),
        })
    }

    fn with_server<F>(verifier: Arc<dyn TokenVerifier>, assertions: F)
    where
        F: FnOnce(SocketAddr),
    {
        let mut handle = start_http_transport(
            || McpServer::new("mcp-slack-test", "0.0.0"),
            test_config(),
            verifier,
        )
        .unwrap();
        let addr = handle.address();
        assertions(addr);
        handle.close(1_000).unwrap();
    }

    #[test]
    fn serves_health_without_authentication() {
        with_server(
            verifier_that(|| Err(Err("verifier must not be consulted for /health".to_string()))),
            |addr| {
                let res = raw_http_request(addr, "GET", "/health", &[], "").unwrap();
                assert_eq!(res.status, 200);
                let body = JsonValue::parse(&res.body).unwrap();
                assert_eq!(body.get("status").and_then(|v| v.as_str()), Some("ok"));
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
        });
    }

    #[test]
    fn returns_500_for_unexpected_verifier_failure_rather_than_hanging() {
        with_server(
            verifier_that(|| Err(Err("fetch failed: JWKS endpoint unreachable".to_string()))),
            |addr| {
                let res = raw_http_request(addr, "POST", "/mcp", &[], "").unwrap();
                assert_eq!(res.status, 500);
                let body = JsonValue::parse(&res.body).unwrap();
                assert_eq!(
                    body.get("error")
                        .and_then(|e| e.get("message"))
                        .and_then(|m| m.as_str()),
                    Some("Internal server error")
                );
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
        let release = Arc::new((Mutex::new(false), Condvar::new()));
        let release_clone = release.clone();
        let mut listener = start_http_transport(
            || McpServer::new("mcp-slack-test", "0.0.0"),
            test_config(),
            verifier_that(move || {
                // Model a handler wedged on a hung upstream call until released after close().
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
        let in_flight = std::thread::spawn(move || {
            let _ = raw_http_request(
                addr,
                "POST",
                "/mcp",
                &[
                    ("Authorization", "Bearer wedged"),
                    ("Content-Type", "application/json"),
                ],
                "{}",
            );
        });

        std::thread::sleep(Duration::from_millis(100));

        let started = Instant::now();
        listener.close(300).unwrap();
        let elapsed_ms = started.elapsed().as_millis();

        assert!(elapsed_ms >= 250, "Expected >= 250ms, got {elapsed_ms}ms");
        assert!(elapsed_ms < 5_000, "Expected < 5000ms, got {elapsed_ms}ms");

        let (lock, cvar) = &*release;
        *lock.lock().unwrap() = true;
        cvar.notify_all();
        let _ = in_flight.join();
    }

    #[test]
    fn refusals_are_recorded_not_only_answered() {
        // 1. Logs the presented subject when a caller is refused
        {
            let capture = capture_stderr();
            with_server(
                verifier_that(|| {
                    Err(Ok(AuthError::SubjectNotAllowed {
                        subject: "379361013981513322".to_string(),
                    }))
                }),
                |addr| {
                    let res = raw_http_request(
                        addr,
                        "POST",
                        "/mcp",
                        &[
                            ("Authorization", "Bearer t"),
                            ("Content-Type", "application/json"),
                        ],
                        "{}",
                    )
                    .unwrap();
                    assert_eq!(res.status, 403);
                },
            );
            let lines = capture.lines();
            let refusal = lines.iter().find(|l| l.contains("refused")).unwrap();
            assert!(refusal.contains("sub=379361013981513322"));
        }

        // 2. Labels a client-pinning refusal by client_id, not sub
        {
            let capture = capture_stderr();
            with_server(
                verifier_that(|| {
                    Err(Ok(AuthError::ClientNotAllowed {
                        client_id: Some("777777777".to_string()),
                    }))
                }),
                |addr| {
                    let res = raw_http_request(
                        addr,
                        "POST",
                        "/mcp",
                        &[
                            ("Authorization", "Bearer t"),
                            ("Content-Type", "application/json"),
                        ],
                        "{}",
                    )
                    .unwrap();
                    assert_eq!(res.status, 403);
                },
            );
            let lines = capture.lines();
            let refusal = lines.iter().find(|l| l.contains("refused")).unwrap();
            assert!(refusal.contains("client_id=777777777"));
            assert!(!refusal.contains("sub=777777777"));
        }

        // 3. Does not log 401s
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

    #[test]
    fn fresh_server_and_transport_are_used_per_request_1491() {
        let initialize_body = JsonValue::object(vec![
            ("jsonrpc", JsonValue::str("2.0")),
            ("id", JsonValue::Number(1.0)),
            ("method", JsonValue::str("initialize")),
            (
                "params",
                JsonValue::object(vec![
                    ("protocolVersion", JsonValue::str("2025-11-25")),
                    ("capabilities", JsonValue::object(vec![])),
                    (
                        "clientInfo",
                        JsonValue::object(vec![
                            ("name", JsonValue::str("regression-test-client")),
                            ("version", JsonValue::str("0.0.0")),
                        ]),
                    ),
                ]),
            ),
        ])
        .to_string();

        with_server(ok_verifier(), |addr| {
            let first = raw_http_request(
                addr,
                "POST",
                "/mcp",
                &[
                    ("Authorization", "Bearer t"),
                    ("Content-Type", "application/json"),
                    ("Accept", "application/json, text/event-stream"),
                ],
                &initialize_body,
            )
            .unwrap();
            assert_eq!(first.status, 200);

            let second = raw_http_request(
                addr,
                "POST",
                "/mcp",
                &[
                    ("Authorization", "Bearer t"),
                    ("Content-Type", "application/json"),
                    ("Accept", "application/json, text/event-stream"),
                ],
                &initialize_body,
            )
            .unwrap();
            assert_eq!(second.status, 200);
        });
    }
}
