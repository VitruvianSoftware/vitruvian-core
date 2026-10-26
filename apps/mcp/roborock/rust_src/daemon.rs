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

//! Loopback HTTP daemon server and synchronous HTTP client.

use crate::config;
use crate::device::DeviceError;
use crate::state::{CommandError, StateStore, VacuumService};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::fmt;
use std::fs::OpenOptions;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::os::unix::fs::OpenOptionsExt;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

pub const SERVICE_NAME: &str = "vitruvian-roborock";
pub const DASHBOARD_CSP: &str = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' blob: data:; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const HEARTBEAT_DURATION: Duration = Duration::from_secs(15);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DaemonUnavailable(pub String);

impl DaemonUnavailable {
    pub fn new(msg: impl Into<String>) -> Self {
        Self(msg.into())
    }
}

impl fmt::Display for DaemonUnavailable {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for DaemonUnavailable {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DaemonRequestError {
    pub status: u16,
    pub payload: Map<String, Value>,
}

impl DaemonRequestError {
    pub fn new(status: u16, payload: Map<String, Value>) -> Self {
        Self { status, payload }
    }

    pub fn code(&self) -> String {
        self.payload
            .get("error")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or("error")
            .to_string()
    }

    pub fn message(&self) -> String {
        self.payload
            .get("message")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(ToString::to_string)
            .unwrap_or_else(|| format!("daemon returned HTTP {}", self.status))
    }
}

impl fmt::Display for DaemonRequestError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message())
    }
}

impl std::error::Error for DaemonRequestError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClientError {
    Unavailable(DaemonUnavailable),
    Request(DaemonRequestError),
}

impl fmt::Display for ClientError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unavailable(u) => write!(f, "{u}"),
            Self::Request(r) => write!(f, "{r}"),
        }
    }
}

impl std::error::Error for ClientError {}

#[derive(Debug, Clone)]
pub struct RawHttpResponse {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
}

impl RawHttpResponse {
    pub fn header(&self, name: &str) -> Option<&str> {
        let lower = name.to_ascii_lowercase();
        self.headers.get(&lower).map(String::as_str)
    }

    pub fn content_type(&self) -> &str {
        self.header("content-type")
            .and_then(|v| v.split(';').next())
            .unwrap_or("")
            .trim()
    }

    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }

    pub fn json(&self) -> Result<Value, String> {
        serde_json::from_slice(&self.body).map_err(|e| e.to_string())
    }
}

#[derive(Debug, Clone)]
pub struct DaemonClient {
    pub port: u16,
    token: Option<String>,
    timeout: Duration,
}

impl DaemonClient {
    pub fn new(
        port: Option<u16>,
        token: Option<String>,
        timeout: Option<Duration>,
    ) -> Result<Self, config::ConfigError> {
        let resolved_port = match port {
            Some(p) => p,
            None => config::daemon_port()?,
        };
        Ok(Self {
            port: resolved_port,
            token,
            timeout: timeout.unwrap_or_else(|| Duration::from_secs(15)),
        })
    }

    pub fn with_port(port: u16, token: Option<String>) -> Self {
        Self {
            port,
            token,
            timeout: Duration::from_secs(15),
        }
    }

    pub fn base_url(&self) -> String {
        format!("http://{}:{}", config::DAEMON_HOST, self.port)
    }

    pub fn raw_request(
        &self,
        method: &str,
        path: &str,
        extra_headers: &[(&str, &str)],
        body: Option<&[u8]>,
    ) -> Result<RawHttpResponse, DaemonUnavailable> {
        let mut stream = connect_loopback(self.port, self.timeout).map_err(|_| {
            DaemonUnavailable::new(format!(
                "The daemon is not reachable on {}.",
                self.base_url()
            ))
        })?;
        let _ = stream.set_read_timeout(Some(self.timeout));
        let _ = stream.set_write_timeout(Some(self.timeout));

        let mut has_host = false;
        for &(k, _) in extra_headers {
            if k.eq_ignore_ascii_case("host") {
                has_host = true;
            }
        }

        let mut req = format!("{method} {path} HTTP/1.1\r\n");
        if !has_host {
            req.push_str(&format!("Host: {}:{}\r\n", config::DAEMON_HOST, self.port));
        }
        req.push_str("Connection: close\r\n");
        for &(k, v) in extra_headers {
            req.push_str(&format!("{k}: {v}\r\n"));
        }
        let payload = body.unwrap_or(&[]);
        if method == "POST" || !payload.is_empty() {
            req.push_str(&format!("Content-Length: {}\r\n", payload.len()));
        }
        req.push_str("\r\n");

        stream
            .write_all(req.as_bytes())
            .and_then(|_| stream.write_all(payload))
            .and_then(|_| stream.flush())
            .map_err(|_| {
                DaemonUnavailable::new(format!(
                    "The daemon is not reachable on {}.",
                    self.base_url()
                ))
            })?;

        read_http_response(&mut stream).map_err(|_| {
            DaemonUnavailable::new(format!(
                "The daemon is not reachable on {}.",
                self.base_url()
            ))
        })
    }

    fn request(
        &self,
        method: &str,
        path: &str,
        body: Option<&Map<String, Value>>,
        auth: bool,
    ) -> Result<Vec<u8>, ClientError> {
        let mut headers: Vec<(&str, String)> = Vec::new();
        if auth {
            let token = self
                .token
                .clone()
                .or_else(config::read_token)
                .ok_or_else(|| {
                    ClientError::Unavailable(DaemonUnavailable::new(
                        "No daemon token found. Start the daemon with `rrctl daemon start`.",
                    ))
                })?;
            headers.push(("Authorization", format!("Bearer {token}")));
        }
        let body_bytes = if method == "POST" {
            let empty = Map::new();
            let doc = body.unwrap_or(&empty);
            headers.push(("Content-Type", "application/json".to_string()));
            Some(serde_json::to_vec(doc).unwrap_or_else(|_| b"{}".to_vec()))
        } else {
            None
        };

        let header_refs: Vec<(&str, &str)> =
            headers.iter().map(|(k, v)| (*k, v.as_str())).collect();
        let resp = self
            .raw_request(method, path, &header_refs, body_bytes.as_deref())
            .map_err(ClientError::Unavailable)?;

        if resp.status >= 400 {
            let payload: Option<Map<String, Value>> = serde_json::from_slice(&resp.body).ok();
            match payload {
                Some(map) if map.contains_key("error") => {
                    return Err(ClientError::Request(DaemonRequestError::new(
                        resp.status,
                        map,
                    )));
                }
                _ => {
                    return Err(ClientError::Unavailable(DaemonUnavailable::new(format!(
                        "Port {} is answering, but not as the Roborock daemon.",
                        self.port
                    ))));
                }
            }
        }
        Ok(resp.body)
    }

    fn request_json(
        &self,
        method: &str,
        path: &str,
        body: Option<&Map<String, Value>>,
        auth: bool,
    ) -> Result<Map<String, Value>, ClientError> {
        let raw = self.request(method, path, body, auth)?;
        let val: Value = serde_json::from_slice(&raw).map_err(|_| {
            ClientError::Unavailable(DaemonUnavailable::new(format!(
                "Port {} is answering, but not as the Roborock daemon.",
                self.port
            )))
        })?;
        val.as_object().cloned().ok_or_else(|| {
            ClientError::Unavailable(DaemonUnavailable::new(format!(
                "Port {} is answering, but not as the Roborock daemon.",
                self.port
            )))
        })
    }

    pub fn health(&self) -> Option<Map<String, Value>> {
        let doc = self.request_json("GET", "/healthz", None, false).ok()?;
        if doc.get("service").and_then(|v| v.as_str()) == Some(SERVICE_NAME) {
            Some(doc)
        } else {
            None
        }
    }

    pub fn status(&self) -> Result<Map<String, Value>, ClientError> {
        self.request_json("GET", "/status", None, true)
    }

    pub fn map_png(&self) -> Result<Option<Vec<u8>>, ClientError> {
        match self.request("GET", "/map.png", None, true) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(ClientError::Request(err)) if err.code() == "no_map" => Ok(None),
            Err(other) => Err(other),
        }
    }

    pub fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Map<String, Value>, ClientError> {
        let mut body = Map::new();
        body.insert("command".to_string(), Value::String(action.to_string()));
        if let Some(p) = params {
            if !p.is_empty() {
                body.insert("params".to_string(), Value::Object(p.clone()));
            }
        }
        self.request_json("POST", "/command", Some(&body), true)
    }

    pub fn reload(&self) -> Result<Map<String, Value>, ClientError> {
        self.request_json("POST", "/reload", None, true)
    }

    pub fn shutdown(&self) -> Result<Map<String, Value>, ClientError> {
        self.request_json("POST", "/shutdown", None, true)
    }
}

pub fn port_taken(port: u16) -> bool {
    connect_loopback(port, Duration::from_millis(500)).is_ok()
}

fn connect_loopback(port: u16, timeout: Duration) -> std::io::Result<TcpStream> {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&addr, timeout)
}

pub fn spawn_daemon(port: Option<u16>) -> Result<Child, DaemonUnavailable> {
    let log = config::log_path();
    if let Some(parent) = log.parent() {
        config::ensure_private_dir(parent).map_err(|e| DaemonUnavailable::new(e.to_string()))?;
    }
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .write(true)
        .mode(0o600)
        .open(&log)
        .map_err(|e| DaemonUnavailable::new(format!("cannot open {}: {e}", log.display())))?;
    let err_file = file
        .try_clone()
        .map_err(|e| DaemonUnavailable::new(format!("cannot clone log fd: {e}")))?;

    let exe = std::env::current_exe()
        .map_err(|e| DaemonUnavailable::new(format!("cannot locate executable: {e}")))?;
    let mut cmd = Command::new(exe);
    if let Some(p) = port {
        cmd.arg("--port").arg(p.to_string());
    }
    cmd.arg("daemon")
        .arg("run")
        .stdin(Stdio::null())
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(err_file));
    cmd.spawn()
        .map_err(|e| DaemonUnavailable::new(format!("cannot spawn daemon: {e}")))
}

pub fn ensure_running(
    port: Option<u16>,
    wait: Duration,
) -> Result<DaemonClient, DaemonUnavailable> {
    ensure_running_with_spawner(port, wait, |p| {
        let mut child = spawn_daemon(p)?;
        Ok(Box::new(move || child.try_wait().ok().flatten().is_some()))
    })
}

pub fn ensure_running_with_spawner<F>(
    port: Option<u16>,
    wait: Duration,
    spawner: F,
) -> Result<DaemonClient, DaemonUnavailable>
where
    F: FnOnce(Option<u16>) -> Result<Box<dyn FnMut() -> bool>, DaemonUnavailable>,
{
    let client =
        DaemonClient::new(port, None, None).map_err(|e| DaemonUnavailable::new(e.to_string()))?;
    if client.health().is_some() {
        return Ok(client);
    }
    if port_taken(client.port) {
        return Err(DaemonUnavailable::new(format!(
            "Port {} is in use by another program, so the daemon cannot start. Stop that program, or set {} to a free port.",
            client.port,
            config::PORT_ENV
        )));
    }
    let mut has_exited = spawner(port)?;
    let deadline = Instant::now() + wait;
    while Instant::now() < deadline {
        if client.health().is_some() {
            return Ok(client);
        }
        if has_exited() {
            if client.health().is_some() {
                return Ok(client);
            }
            break;
        }
        thread::sleep(Duration::from_millis(50));
    }
    Err(DaemonUnavailable::new(format!(
        "The daemon did not start on port {}. See {}.",
        client.port,
        config::log_path().display()
    )))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PortInUse(pub String);

impl fmt::Display for PortInUse {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for PortInUse {}

pub struct StopSignal {
    flag: AtomicBool,
    mu: Mutex<()>,
    cv: Condvar,
}

impl Default for StopSignal {
    fn default() -> Self {
        Self::new()
    }
}

impl StopSignal {
    pub fn new() -> Self {
        Self {
            flag: AtomicBool::new(false),
            mu: Mutex::new(()),
            cv: Condvar::new(),
        }
    }

    pub fn set(&self) {
        let _guard = self.mu.lock().unwrap_or_else(|e| e.into_inner());
        self.flag.store(true, Ordering::SeqCst);
        self.cv.notify_all();
    }

    pub fn is_set(&self) -> bool {
        self.flag.load(Ordering::SeqCst)
    }

    pub fn wait(&self) {
        let mut guard = self.mu.lock().unwrap_or_else(|e| e.into_inner());
        while !self.flag.load(Ordering::SeqCst) {
            guard = self.cv.wait(guard).unwrap_or_else(|e| e.into_inner());
        }
    }
}

pub struct DaemonServer {
    port: u16,
    stop_signal: Arc<StopSignal>,
    store: Arc<StateStore>,
    accept_thread: Option<JoinHandle<()>>,
}

impl DaemonServer {
    pub fn start(
        port: u16,
        store: Arc<StateStore>,
        service: Arc<VacuumService>,
        token: String,
        stop_signal: Option<Arc<StopSignal>>,
    ) -> Result<Self, PortInUse> {
        let addr = SocketAddr::from(([127, 0, 0, 1], port));
        let listener = TcpListener::bind(addr).map_err(|err| {
            PortInUse(format!(
                "Cannot listen on {}:{}: {}",
                config::DAEMON_HOST,
                port,
                err
            ))
        })?;
        let bound_port = listener.local_addr().map(|a| a.port()).unwrap_or(port);
        let _ = listener.set_nonblocking(true);

        let stop = stop_signal.unwrap_or_else(|| Arc::new(StopSignal::new()));
        let stop_for_loop = stop.clone();
        let store_for_loop = store.clone();
        let service_for_loop = service.clone();

        let accept_thread = thread::spawn(move || {
            while !stop_for_loop.is_set() {
                match listener.accept() {
                    Ok((stream, _peer)) => {
                        let _ = stream.set_nonblocking(false);
                        let store_conn = store_for_loop.clone();
                        let service_conn = service_for_loop.clone();
                        let token_conn = token.clone();
                        let stop_conn = stop_for_loop.clone();
                        thread::spawn(move || {
                            handle_connection(
                                stream,
                                bound_port,
                                &store_conn,
                                &service_conn,
                                &token_conn,
                                &stop_conn,
                            );
                        });
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(5));
                    }
                    Err(_) => break,
                }
            }
        });

        Ok(Self {
            port: bound_port,
            stop_signal: stop,
            store,
            accept_thread: Some(accept_thread),
        })
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn stop_signal(&self) -> Arc<StopSignal> {
        self.stop_signal.clone()
    }

    pub fn shutdown(&mut self) {
        self.stop_signal.set();
        self.store.close();
        if let Some(handle) = self.accept_thread.take() {
            let _ = handle.join();
        }
    }
}

impl Drop for DaemonServer {
    fn drop(&mut self) {
        self.shutdown();
    }
}

struct ParsedHttpRequest {
    method: String,
    path: String,
    headers: HashMap<String, String>,
    body: Vec<u8>,
}

impl ParsedHttpRequest {
    fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .get(&name.to_ascii_lowercase())
            .map(String::as_str)
    }

    fn content_type(&self) -> &str {
        self.header("content-type")
            .and_then(|v| v.split(';').next())
            .unwrap_or("")
            .trim()
    }
}

fn handle_connection(
    mut stream: TcpStream,
    port: u16,
    store: &Arc<StateStore>,
    service: &Arc<VacuumService>,
    token: &str,
    stop: &Arc<StopSignal>,
) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(5)));

    let Some(req) = parse_http_request(&mut stream) else {
        return;
    };

    let clean_path = req.path.split('?').next().unwrap_or(&req.path);

    // 1. Host header check (DNS rebinding guard)
    let host = req.header("host").unwrap_or("");
    let allowed_host_1 = format!("127.0.0.1:{port}");
    let allowed_host_2 = format!("localhost:{port}");
    if host != allowed_host_1 && host != allowed_host_2 {
        let _ = write_problem(
            &mut stream,
            403,
            "forbidden_host",
            "This daemon only answers on its loopback address.",
        );
        return;
    }

    // 2. Origin header check (cross-origin guard)
    if let Some(origin) = req.header("origin") {
        let allowed_origin_1 = format!("http://{allowed_host_1}");
        let allowed_origin_2 = format!("http://{allowed_host_2}");
        if origin != allowed_origin_1 && origin != allowed_origin_2 {
            let _ = write_problem(
                &mut stream,
                403,
                "forbidden_origin",
                "Cross-origin requests are not allowed.",
            );
            return;
        }
    }

    // 3. Bearer token check for non-public paths
    if clean_path != "/" && clean_path != "/healthz" {
        let auth_hdr = req.header("authorization").unwrap_or("");
        let (scheme, presented) = auth_hdr.split_once(' ').unwrap_or(("", ""));
        if !scheme.eq_ignore_ascii_case("bearer")
            || !constant_time_eq(presented.trim().as_bytes(), token.as_bytes())
        {
            let _ = write_problem(
                &mut stream,
                401,
                "unauthorized",
                "Missing or wrong daemon token.",
            );
            return;
        }
    }

    // 4. Content-Type check for POST requests
    if req.method == "POST" && !req.content_type().eq_ignore_ascii_case("application/json") {
        let _ = write_problem(
            &mut stream,
            415,
            "unsupported_media_type",
            "POST bodies must be application/json.",
        );
        return;
    }

    match (req.method.as_str(), clean_path) {
        ("GET", "/") => {
            let html = crate::dashboard_html();
            let _ = write_response(
                &mut stream,
                200,
                "text/html",
                &[
                    ("Content-Security-Policy", DASHBOARD_CSP),
                    ("X-Frame-Options", "DENY"),
                ],
                html.as_bytes(),
            );
        }
        ("GET", "/healthz") => {
            let body = json!({
                "ok": true,
                "service": SERVICE_NAME,
                "version": crate::VERSION,
                "pid": std::process::id(),
            });
            let _ = write_json_response(&mut stream, 200, &body);
        }
        ("GET", "/status") => {
            let body = Value::Object(store.status());
            let _ = write_json_response(&mut stream, 200, &body);
        }
        ("GET", "/map.png") => {
            let Some(png) = store.map_png() else {
                let _ = write_problem(
                    &mut stream,
                    404,
                    "no_map",
                    "No map has been received from the vacuum yet.",
                );
                return;
            };
            let etag = format!("\"{}\"", store.map_version());
            if req.header("if-none-match") == Some(etag.as_str()) {
                let _ = write_response(
                    &mut stream,
                    304,
                    "text/plain",
                    &[("ETag", etag.as_str())],
                    &[],
                );
                return;
            }
            let _ = write_response(
                &mut stream,
                200,
                "image/png",
                &[("ETag", etag.as_str())],
                &png,
            );
        }
        ("GET", "/events") => {
            handle_sse_events(stream, store, stop);
        }
        ("POST", "/command") => {
            let Ok(body) = serde_json::from_slice::<Value>(&req.body) else {
                let _ = write_problem(
                    &mut stream,
                    400,
                    "bad_request",
                    "The body is not valid JSON.",
                );
                return;
            };
            let Some(obj) = body.as_object() else {
                let _ = write_problem(
                    &mut stream,
                    400,
                    "bad_request",
                    "Give the action as a string in 'command'.",
                );
                return;
            };
            let Some(action) = obj
                .get("command")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
            else {
                let _ = write_problem(
                    &mut stream,
                    400,
                    "bad_request",
                    "Give the action as a string in 'command'.",
                );
                return;
            };
            let params = match obj.get("params") {
                None | Some(Value::Null) => None,
                Some(Value::Object(m)) => Some(m),
                Some(_) => {
                    let _ = write_problem(
                        &mut stream,
                        400,
                        "bad_request",
                        "'params' must be an object.",
                    );
                    return;
                }
            };
            match service.command(action, params) {
                Ok(result) => {
                    let resp = json!({
                        "ok": true,
                        "command": action,
                        "result": result,
                    });
                    let _ = write_json_response(&mut stream, 200, &resp);
                }
                Err(CommandError::Unavailable(su)) => {
                    let status = if su.code == "not_authenticated" {
                        409
                    } else {
                        503
                    };
                    let _ = write_problem(&mut stream, status, &su.code, &su.message);
                }
                Err(CommandError::Device(DeviceError::UnknownAction(msg))) => {
                    let _ = write_problem(&mut stream, 400, "unknown_command", &msg);
                }
                Err(CommandError::Device(DeviceError::Rejected(msg))) => {
                    let _ = write_problem(&mut stream, 502, "device_error", &msg);
                }
            }
        }
        ("POST", "/reload") => {
            service.reload();
            let _ = write_json_response(&mut stream, 200, &json!({"ok": true}));
        }
        ("POST", "/shutdown") => {
            stop.set();
            store.close();
            let _ = write_json_response(&mut stream, 200, &json!({"ok": true}));
        }
        _ => {
            let _ = write_problem(&mut stream, 404, "not_found", "Not found.");
        }
    }
}

fn handle_sse_events(mut stream: TcpStream, store: &Arc<StateStore>, stop: &Arc<StopSignal>) {
    let headers = concat!(
        "HTTP/1.1 200 OK\r\n",
        "Content-Type: text/event-stream\r\n",
        "X-Accel-Buffering: no\r\n",
        "Cache-Control: no-store\r\n",
        "X-Content-Type-Options: nosniff\r\n",
        "Connection: close\r\n",
        "\r\n"
    );
    if stream.write_all(headers.as_bytes()).is_err() || stream.flush().is_err() {
        return;
    }
    let queue = store.subscribe();
    let initial = format_sse("status", &store.status());
    if stream.write_all(initial.as_bytes()).is_err() || stream.flush().is_err() {
        store.unsubscribe(&queue);
        return;
    }
    while !stop.is_set() {
        match queue.get_timeout(HEARTBEAT_DURATION) {
            Ok(Some((event, data))) => {
                let frame = format_sse(&event, &data);
                if stream.write_all(frame.as_bytes()).is_err() || stream.flush().is_err() {
                    break;
                }
            }
            Ok(None) => break,
            Err(()) => {
                if stop.is_set() {
                    break;
                }
                if stream.write_all(b": keep-alive\n\n").is_err() || stream.flush().is_err() {
                    break;
                }
            }
        }
    }
    store.unsubscribe(&queue);
}

fn format_sse(event: &str, data: &Map<String, Value>) -> String {
    let serialized = serde_json::to_string(data).unwrap_or_else(|_| "{}".to_string());
    format!("event: {event}\ndata: {serialized}\n\n")
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (&x, &y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

fn status_reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        415 => "Unsupported Media Type",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        _ => "Error",
    }
}

fn write_problem(
    stream: &mut TcpStream,
    status: u16,
    code: &str,
    message: &str,
) -> std::io::Result<()> {
    let body = json!({
        "ok": false,
        "error": code,
        "message": message,
    });
    write_json_response(stream, status, &body)
}

fn write_json_response(stream: &mut TcpStream, status: u16, body: &Value) -> std::io::Result<()> {
    let bytes = serde_json::to_vec(body).unwrap_or_default();
    write_response(stream, status, "application/json", &[], &bytes)
}

fn write_response(
    stream: &mut TcpStream,
    status: u16,
    content_type: &str,
    extra_headers: &[(&str, &str)],
    body: &[u8],
) -> std::io::Result<()> {
    let mut resp = format!(
        "HTTP/1.1 {status} {}\r\nContent-Type: {content_type}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Length: {}\r\nConnection: close\r\n",
        status_reason(status),
        body.len()
    );
    for &(k, v) in extra_headers {
        resp.push_str(&format!("{k}: {v}\r\n"));
    }
    resp.push_str("\r\n");
    stream.write_all(resp.as_bytes())?;
    if status != 304 && !body.is_empty() {
        stream.write_all(body)?;
    }
    stream.flush()
}

fn parse_http_request(stream: &mut TcpStream) -> Option<ParsedHttpRequest> {
    let mut reader = BufReader::new(stream);
    let mut req_line = String::new();
    if reader.read_line(&mut req_line).ok()? == 0 {
        return None;
    }
    let mut parts = req_line.split_whitespace();
    let method = parts.next()?.to_uppercase();
    let path = parts.next()?.to_string();

    let mut headers = HashMap::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).ok()? == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }

    let content_len = headers
        .get("content-length")
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(0);
    if content_len > 64 * 1024 {
        return None;
    }
    let mut body = vec![0u8; content_len];
    if content_len > 0 {
        reader.read_exact(&mut body).ok()?;
    }

    Some(ParsedHttpRequest {
        method,
        path,
        headers,
        body,
    })
}

fn read_http_response(stream: &mut TcpStream) -> std::io::Result<RawHttpResponse> {
    let mut reader = BufReader::new(stream);
    let mut status_line = String::new();
    if reader.read_line(&mut status_line)? == 0 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "empty response",
        ));
    }
    let mut parts = status_line.split_whitespace();
    let _http_ver = parts.next().unwrap_or("");
    let status: u16 = parts
        .next()
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "bad status"))?;

    let mut headers = HashMap::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }

    let mut body = Vec::new();
    if status != 304 {
        if let Some(len) = headers
            .get("content-length")
            .and_then(|v| v.parse::<usize>().ok())
        {
            body.resize(len, 0);
            reader.read_exact(&mut body)?;
        } else {
            reader.read_to_end(&mut body)?;
        }
    }

    Ok(RawHttpResponse {
        status,
        headers,
        body,
    })
}
