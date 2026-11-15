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

//! Zero-dependency (std-only) HTTP/1.1 + SSE server, client, and test harness.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::Duration;

use vitruvian_remote_macagent_metrics::{JsonMap, JsonValue};

#[derive(Debug, Clone)]
pub struct CancelToken {
    flag: Arc<(Mutex<bool>, Condvar)>,
}

impl Default for CancelToken {
    fn default() -> Self {
        Self::new()
    }
}

impl CancelToken {
    pub fn new() -> Self {
        Self {
            flag: Arc::new((Mutex::new(false), Condvar::new())),
        }
    }

    pub fn cancel(&self) {
        let (lock, cvar) = &*self.flag;
        if let Ok(mut guard) = lock.lock() {
            *guard = true;
            cvar.notify_all();
        }
    }

    pub fn is_cancelled(&self) -> bool {
        let (lock, _) = &*self.flag;
        lock.lock().map(|g| *g).unwrap_or(true)
    }

    /// Waits up to `timeout` for cancellation; returns `true` if cancelled.
    pub fn wait_timeout(&self, timeout: Duration) -> bool {
        let (lock, cvar) = &*self.flag;
        let Ok(guard) = lock.lock() else {
            return true;
        };
        if *guard {
            return true;
        }
        let Ok((guard, _)) = cvar.wait_timeout(guard, timeout) else {
            return true;
        };
        *guard
    }

    pub fn inner_pair(&self) -> Arc<(Mutex<bool>, Condvar)> {
        Arc::clone(&self.flag)
    }
}

#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub method: String,
    pub path: String,
    pub raw_query: String,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
    pub remote_addr: String,
    pub host: String,
    pub cancel: CancelToken,
}

impl Default for HttpRequest {
    fn default() -> Self {
        Self {
            method: "GET".to_string(),
            path: "/".to_string(),
            raw_query: String::new(),
            headers: Vec::new(),
            body: Vec::new(),
            remote_addr: "127.0.0.1:50000".to_string(),
            host: "127.0.0.1:7411".to_string(),
            cancel: CancelToken::new(),
        }
    }
}

impl HttpRequest {
    pub fn new(
        method: impl Into<String>,
        target: impl Into<String>,
        body: impl Into<Vec<u8>>,
    ) -> Self {
        let target = target.into();
        let (path, raw_query) = match target.split_once('?') {
            Some((p, q)) => (p.to_string(), q.to_string()),
            None => (target, String::new()),
        };
        Self {
            method: method.into(),
            path,
            raw_query,
            headers: Vec::new(),
            body: body.into(),
            remote_addr: "127.0.0.1:50000".to_string(),
            host: "127.0.0.1:7411".to_string(),
            cancel: CancelToken::new(),
        }
    }

    pub fn new_test(
        method: impl Into<String>,
        target: impl Into<String>,
        body: impl AsRef<[u8]>,
    ) -> Self {
        Self::new(method, target, body.as_ref().to_vec())
    }

    pub fn with_header(mut self, name: impl Into<String>, val: impl Into<String>) -> Self {
        self.set_header(name, val);
        self
    }

    pub fn with_remote_addr(mut self, addr: impl Into<String>) -> Self {
        self.remote_addr = addr.into();
        self
    }

    pub fn set_header(&mut self, name: impl Into<String>, val: impl Into<String>) {
        let name = name.into();
        let val = val.into();
        if name.eq_ignore_ascii_case("host") {
            self.host = val.clone();
        }
        if let Some((_, existing)) = self
            .headers
            .iter_mut()
            .find(|(k, _)| k.eq_ignore_ascii_case(&name))
        {
            *existing = val;
        } else {
            self.headers.push((name, val));
        }
    }

    pub fn header(&self, name: &str) -> &str {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
            .unwrap_or("")
    }

    pub fn header_opt(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }

    pub fn body_str(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }

    pub fn body_string(&self) -> String {
        self.body_str()
    }

    pub fn json(&self) -> Result<JsonValue, String> {
        if self.body.is_empty() {
            return Err("invalid JSON body: EOF".to_string());
        }
        let slice = if self.body.len() > MAX_REQUEST_BODY {
            &self.body[..MAX_REQUEST_BODY]
        } else {
            &self.body[..]
        };
        let s = std::str::from_utf8(slice).map_err(|e| format!("invalid JSON body: {}", e))?;
        JsonValue::parse(s).map_err(|e| format!("invalid JSON body: {}", e))
    }

    pub fn query_param(&self, key: &str) -> Option<String> {
        self.query_params().remove(key)
    }

    pub fn query_params(&self) -> HashMap<String, String> {
        let mut map = HashMap::new();
        if self.raw_query.is_empty() {
            return map;
        }
        for pair in self.raw_query.split('&') {
            if pair.is_empty() {
                continue;
            }
            let (k, v) = match pair.split_once('=') {
                Some((k, v)) => (url_decode(k), url_decode(v)),
                None => (url_decode(pair), String::new()),
            };
            map.insert(k, v);
        }
        map
    }
}

pub fn url_decode(s: &str) -> String {
    let mut out = Vec::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b'%' if i + 2 < bytes.len() => {
                if let (Some(h), Some(l)) = (from_hex(bytes[i + 1]), from_hex(bytes[i + 2])) {
                    out.push((h << 4) | l);
                    i += 3;
                    continue;
                }
                out.push(b'%');
                i += 1;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn url_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push_str(&format!("%{:02X}", b));
            }
        }
    }
    out
}

fn from_hex(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

pub const MAX_REQUEST_BODY: usize = 1 << 20;

pub trait SseSink {
    fn write_event(&mut self, event: &str, data: &str) -> std::io::Result<()>;
}

pub struct StreamSseSink<'a> {
    writer: &'a mut dyn Write,
}

impl<'a> StreamSseSink<'a> {
    pub fn new(writer: &'a mut dyn Write) -> Self {
        Self { writer }
    }
}

impl<'a> SseSink for StreamSseSink<'a> {
    fn write_event(&mut self, event: &str, data: &str) -> std::io::Result<()> {
        write!(self.writer, "event: {}\ndata: {}\n\n", event, data)?;
        self.writer.flush()
    }
}

pub enum HttpResponseBody {
    Bytes(Vec<u8>),
    Sse(Mutex<Option<Box<dyn FnOnce(&mut dyn SseSink, CancelToken) + Send>>>),
}

pub struct HttpResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: HttpResponseBody,
}

impl HttpResponse {
    pub fn new(status: u16, body: impl Into<Vec<u8>>) -> Self {
        Self {
            status,
            headers: Vec::new(),
            body: HttpResponseBody::Bytes(body.into()),
        }
    }

    pub fn json(status: u16, val: &JsonValue) -> Self {
        let mut resp = Self::new(status, format!("{}\n", val.to_json_string()).into_bytes());
        resp.set_header("Content-Type", "application/json");
        resp.set_header("Cache-Control", "no-store");
        resp
    }

    pub fn json_str(status: u16, raw_json: &str) -> Self {
        let mut s = raw_json.to_string();
        if !s.ends_with('\n') {
            s.push('\n');
        }
        let mut resp = Self::new(status, s.into_bytes());
        resp.set_header("Content-Type", "application/json");
        resp.set_header("Cache-Control", "no-store");
        resp
    }

    pub fn json_error(status: u16, msg: &str) -> Self {
        let mut m = JsonMap::new();
        m.insert("error", JsonValue::from_str_val(msg));
        Self::json(status, &JsonValue::Object(m))
    }

    pub fn error(status: u16, msg: &str) -> Self {
        Self::json_error(status, msg)
    }

    pub fn method_not_allowed(allow: &str) -> Self {
        let mut resp = Self::json_error(405, &format!("method not allowed; want {}", allow));
        resp.set_header("Allow", allow);
        resp
    }

    pub fn html(status: u16, html: &str) -> Self {
        let mut resp = Self::new(status, html.as_bytes().to_vec());
        resp.set_header("Content-Type", "text/html; charset=utf-8");
        resp.set_header("Cache-Control", "no-store");
        resp
    }

    pub fn sse<F>(f: F) -> Self
    where
        F: FnOnce(&mut dyn SseSink, CancelToken) + Send + 'static,
    {
        let mut headers = Vec::new();
        headers.push(("Content-Type".to_string(), "text/event-stream".to_string()));
        headers.push(("Cache-Control".to_string(), "no-store".to_string()));
        headers.push(("X-Accel-Buffering".to_string(), "no".to_string()));
        Self {
            status: 200,
            headers,
            body: HttpResponseBody::Sse(Mutex::new(Some(Box::new(f)))),
        }
    }

    pub fn with_header(mut self, name: impl Into<String>, val: impl Into<String>) -> Self {
        self.set_header(name, val);
        self
    }

    pub fn set_header(&mut self, name: impl Into<String>, val: impl Into<String>) {
        let name = name.into();
        let val = val.into();
        if let Some((_, existing)) = self
            .headers
            .iter_mut()
            .find(|(k, _)| k.eq_ignore_ascii_case(&name))
        {
            *existing = val;
        } else {
            self.headers.push((name, val));
        }
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }

    pub fn body_bytes(&self) -> Vec<u8> {
        match &self.body {
            HttpResponseBody::Bytes(b) => b.clone(),
            HttpResponseBody::Sse(m) => {
                let mut buf = Vec::new();
                if let Ok(mut guard) = m.lock() {
                    if let Some(f) = guard.take() {
                        let mut sink = StreamSseSink::new(&mut buf);
                        f(&mut sink, CancelToken::new());
                    }
                }
                buf
            }
        }
    }

    pub fn body_string(&self) -> String {
        String::from_utf8_lossy(&self.body_bytes()).into_owned()
    }

    pub fn json_value(&self) -> Result<JsonValue, String> {
        let s = self.body_string();
        JsonValue::parse(&s)
    }
}

pub trait HttpHandler: Send + Sync + 'static {
    fn handle(&self, req: &HttpRequest) -> HttpResponse;
}

impl<F> HttpHandler for F
where
    F: Fn(&HttpRequest) -> HttpResponse + Send + Sync + 'static,
{
    fn handle(&self, req: &HttpRequest) -> HttpResponse {
        (self)(req)
    }
}

fn status_reason(code: u16) -> &'static str {
    match code {
        200 => "OK",
        202 => "Accepted",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        410 => "Gone",
        415 => "Unsupported Media Type",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        _ => "OK",
    }
}

/// Serves a single HTTP connection.
pub fn serve_http_connection(mut stream: TcpStream, handler: Arc<dyn HttpHandler>) {
    let remote_addr = stream
        .peer_addr()
        .map(|a| a.to_string())
        .unwrap_or_else(|_| "127.0.0.1:0".to_string());

    let Ok(reader_stream) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(reader_stream);

    let mut req_line = String::new();
    if reader.read_line(&mut req_line).unwrap_or(0) == 0 {
        return;
    }
    let parts: Vec<&str> = req_line.trim().split_whitespace().collect();
    if parts.len() < 2 {
        return;
    }
    let method = parts[0].to_string();
    let target = parts[1];
    let (path, raw_query) = match target.split_once('?') {
        Some((p, q)) => (p.to_string(), q.to_string()),
        None => (target.to_string(), String::new()),
    };

    let mut headers = Vec::new();
    let mut content_length: usize = 0;
    let mut host = String::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).unwrap_or(0) == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim().to_string();
            let val = v.trim().to_string();
            if key.eq_ignore_ascii_case("content-length") {
                content_length = val.parse::<usize>().unwrap_or(0);
            }
            if key.eq_ignore_ascii_case("host") {
                host = val.clone();
            }
            headers.push((key, val));
        }
    }

    let mut body = vec![0u8; content_length];
    if content_length > 0 && reader.read_exact(&mut body).is_err() {
        return;
    }

    let cancel = CancelToken::new();
    let done = Arc::new(AtomicBool::new(false));
    if let Ok(mut watch_stream) = stream.try_clone() {
        let cancel_clone = cancel.clone();
        let done_clone = Arc::clone(&done);
        thread::spawn(move || {
            let mut buf = [0u8; 1];
            let _ = watch_stream.read(&mut buf);
            if !done_clone.load(Ordering::SeqCst) {
                cancel_clone.cancel();
            }
        });
    }

    let req = HttpRequest {
        method,
        path,
        raw_query,
        headers,
        body,
        remote_addr,
        host,
        cancel: cancel.clone(),
    };

    let resp = handler.handle(&req);
    let reason = status_reason(resp.status);

    match resp.body {
        HttpResponseBody::Bytes(bytes) => {
            let mut header_str = format!(
                "HTTP/1.1 {} {}\r\nContent-Length: {}\r\nConnection: close\r\n",
                resp.status,
                reason,
                bytes.len()
            );
            for (k, v) in &resp.headers {
                header_str.push_str(&format!("{}: {}\r\n", k, v));
            }
            header_str.push_str("\r\n");
            let _ = stream.write_all(header_str.as_bytes());
            if req.method != "HEAD" && !bytes.is_empty() {
                let _ = stream.write_all(&bytes);
            }
            let _ = stream.flush();
        }
        HttpResponseBody::Sse(sse_mutex) => {
            let mut header_str = format!(
                "HTTP/1.1 {} {}\r\nConnection: close\r\n",
                resp.status, reason
            );
            for (k, v) in &resp.headers {
                header_str.push_str(&format!("{}: {}\r\n", k, v));
            }
            header_str.push_str("\r\n");
            if stream.write_all(header_str.as_bytes()).is_ok() && stream.flush().is_ok() {
                if let Ok(mut guard) = sse_mutex.lock() {
                    if let Some(sse_fn) = guard.take() {
                        let mut sink = StreamSseSink::new(&mut stream);
                        sse_fn(&mut sink, cancel.clone());
                    }
                }
            }
        }
    }

    done.store(true, Ordering::SeqCst);
    cancel.cancel();
    let _ = stream.shutdown(Shutdown::Both);
}

pub fn serve_listener(listener: TcpListener, handler: Arc<dyn HttpHandler>, cancel: CancelToken) {
    for incoming in listener.incoming() {
        if cancel.is_cancelled() {
            break;
        }
        match incoming {
            Ok(stream) => {
                let h = Arc::clone(&handler);
                thread::spawn(move || {
                    serve_http_connection(stream, h);
                });
            }
            Err(_) => break,
        }
    }
}

/// An in-process ephemeral HTTP server on `127.0.0.1:0` (equivalent to `httptest.Server`).
pub struct TestServer {
    pub url: String,
    pub addr: String,
    stop: Arc<AtomicBool>,
}

impl TestServer {
    pub fn start<H: HttpHandler>(handler: H) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind test server");
        let local_addr = listener.local_addr().expect("local_addr");
        let addr = local_addr.to_string();
        let url = format!("http://{}", addr);
        let stop = Arc::new(AtomicBool::new(false));
        let stop_clone = Arc::clone(&stop);
        let handler_arc: Arc<dyn HttpHandler> = Arc::new(handler);

        thread::spawn(move || {
            for incoming in listener.incoming() {
                if stop_clone.load(Ordering::SeqCst) {
                    break;
                }
                match incoming {
                    Ok(stream) => {
                        let h = Arc::clone(&handler_arc);
                        thread::spawn(move || {
                            serve_http_connection(stream, h);
                        });
                    }
                    Err(_) => break,
                }
            }
        });

        Self { url, addr, stop }
    }

    pub fn url(&self) -> &str {
        &self.url
    }

    pub fn close(&self) {
        if !self.stop.swap(true, Ordering::SeqCst) {
            let _ = TcpStream::connect(&self.addr);
        }
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.close();
    }
}

#[derive(Debug, Clone)]
pub struct ClientResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl ClientResponse {
    pub fn header(&self, name: &str) -> &str {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
            .unwrap_or("")
    }

    pub fn body_string(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }

    pub fn json(&self) -> Result<JsonValue, String> {
        JsonValue::parse(&self.body_string())
    }
}

pub fn parse_http_url(url: &str) -> Result<(String, String), String> {
    let without_scheme = url
        .strip_prefix("http://")
        .or_else(|| url.strip_prefix("https://"))
        .unwrap_or(url);
    match without_scheme.split_once('/') {
        Some((host_port, rest)) => Ok((host_port.to_string(), format!("/{}", rest))),
        None => Ok((without_scheme.to_string(), "/".to_string())),
    }
}

/// Performs a synchronous HTTP request over `TcpStream`.
pub fn http_do(
    method: &str,
    url: &str,
    headers: &[(&str, &str)],
    body: &[u8],
    timeout: Option<Duration>,
) -> Result<ClientResponse, String> {
    let (host_port, path_and_query) = parse_http_url(url)?;
    let connect_addr = if host_port.contains(':') {
        host_port.clone()
    } else {
        format!("{}:80", host_port)
    };
    let mut stream = TcpStream::connect(&connect_addr).map_err(|e| e.to_string())?;
    if let Some(d) = timeout {
        let _ = stream.set_read_timeout(Some(d));
        let _ = stream.set_write_timeout(Some(d));
    }

    let mut req_str = format!(
        "{} {} HTTP/1.1\r\nHost: {}\r\nContent-Length: {}\r\nConnection: close\r\n",
        method,
        path_and_query,
        host_port,
        body.len()
    );
    for (k, v) in headers {
        req_str.push_str(&format!("{}: {}\r\n", k, v));
    }
    req_str.push_str("\r\n");

    stream
        .write_all(req_str.as_bytes())
        .map_err(|e| e.to_string())?;
    if !body.is_empty() {
        stream.write_all(body).map_err(|e| e.to_string())?;
    }
    stream.flush().map_err(|e| e.to_string())?;

    read_client_response(stream)
}

/// Opens a cancellable HTTP connection and returns `(status, headers, BufReader<TcpStream>, TcpStream)`
/// so the caller can read an SSE stream or cancel an in-flight request by shutting down the stream.
pub fn http_open_stream(
    method: &str,
    url: &str,
    headers: &[(&str, &str)],
    body: &[u8],
) -> Result<(u16, Vec<(String, String)>, BufReader<TcpStream>, TcpStream), String> {
    let (host_port, path_and_query) = parse_http_url(url)?;
    let connect_addr = if host_port.contains(':') {
        host_port.clone()
    } else {
        format!("{}:80", host_port)
    };
    let mut stream = TcpStream::connect(&connect_addr).map_err(|e| e.to_string())?;
    let mut req_str = format!(
        "{} {} HTTP/1.1\r\nHost: {}\r\nContent-Length: {}\r\nConnection: close\r\n",
        method,
        path_and_query,
        host_port,
        body.len()
    );
    for (k, v) in headers {
        req_str.push_str(&format!("{}: {}\r\n", k, v));
    }
    req_str.push_str("\r\n");
    stream
        .write_all(req_str.as_bytes())
        .map_err(|e| e.to_string())?;
    if !body.is_empty() {
        stream.write_all(body).map_err(|e| e.to_string())?;
    }
    stream.flush().map_err(|e| e.to_string())?;

    let ctrl = stream.try_clone().map_err(|e| e.to_string())?;
    let mut reader = BufReader::new(stream);
    let mut status_line = String::new();
    if reader
        .read_line(&mut status_line)
        .map_err(|e| e.to_string())?
        == 0
    {
        return Err("EOF reading status line".to_string());
    }
    let parts: Vec<&str> = status_line.trim().split_whitespace().collect();
    if parts.len() < 2 {
        return Err(format!("invalid status line: {}", status_line));
    }
    let status = parts[1].parse::<u16>().map_err(|e| e.to_string())?;
    let mut resp_headers = Vec::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).map_err(|e| e.to_string())? == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            resp_headers.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    Ok((status, resp_headers, reader, ctrl))
}

pub fn read_client_response(stream: TcpStream) -> Result<ClientResponse, String> {
    let mut reader = BufReader::new(stream);
    let mut status_line = String::new();
    if reader
        .read_line(&mut status_line)
        .map_err(|e| e.to_string())?
        == 0
    {
        return Err("EOF reading status line".to_string());
    }
    let parts: Vec<&str> = status_line.trim().split_whitespace().collect();
    if parts.len() < 2 {
        return Err(format!("invalid status line: {}", status_line));
    }
    let status = parts[1].parse::<u16>().map_err(|e| e.to_string())?;
    let mut headers = Vec::new();
    let mut content_length: Option<usize> = None;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).map_err(|e| e.to_string())? == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim().to_string();
            let val = v.trim().to_string();
            if key.eq_ignore_ascii_case("content-length") {
                content_length = val.parse::<usize>().ok();
            }
            headers.push((key, val));
        }
    }

    let mut body = Vec::new();
    if let Some(len) = content_length {
        body.resize(len, 0);
        reader.read_exact(&mut body).map_err(|e| e.to_string())?;
    } else {
        reader.read_to_end(&mut body).map_err(|e| e.to_string())?;
    }

    Ok(ClientResponse {
        status,
        headers,
        body,
    })
}

pub fn http_get(url: &str) -> Result<ClientResponse, String> {
    http_do("GET", url, &[], &[], None)
}

pub fn http_post_json(url: &str, token: &str, json_body: &str) -> Result<ClientResponse, String> {
    let mut hdrs = vec![("Content-Type", "application/json")];
    let auth_header;
    if !token.is_empty() {
        auth_header = format!("Bearer {}", token);
        hdrs.push(("Authorization", &auth_header));
    }
    http_do("POST", url, &hdrs, json_body.as_bytes(), None)
}

/// Thread-safe log buffer for unit tests that assert on agent audit log lines.
static TEST_LOG_SINK: Mutex<Option<Arc<Mutex<String>>>> = Mutex::new(None);

pub fn agent_log(msg: &str) {
    if let Ok(guard) = TEST_LOG_SINK.lock() {
        if let Some(sink) = &*guard {
            if let Ok(mut buf) = sink.lock() {
                buf.push_str(msg);
                buf.push('\n');
            }
        }
    }
    eprintln!("{}", msg);
}

pub struct LogCapture {
    buf: Arc<Mutex<String>>,
}

impl LogCapture {
    pub fn start() -> Self {
        let buf = Arc::new(Mutex::new(String::new()));
        if let Ok(mut guard) = TEST_LOG_SINK.lock() {
            *guard = Some(Arc::clone(&buf));
        }
        Self { buf }
    }

    pub fn new() -> Self {
        Self::start()
    }

    pub fn contents(&self) -> String {
        self.buf.lock().map(|g| g.clone()).unwrap_or_default()
    }

    pub fn text(&self) -> String {
        self.contents()
    }
}

pub fn http_request(
    method: &str,
    url: &str,
    headers: &[(&str, &str)],
    body: Option<&[u8]>,
    timeout: Duration,
) -> Result<(u16, Vec<(String, String)>, Vec<u8>), String> {
    let resp = http_do(method, url, headers, body.unwrap_or(&[]), Some(timeout))?;
    Ok((resp.status, resp.headers, resp.body))
}

pub fn log_line(msg: &str) {
    agent_log(msg);
}

pub fn log_act(kind: &str, command: &str) {
    const N: usize = 80;
    let c = command.trim().replace('\n', " ");
    let truncated = if c.len() > N {
        format!("{}...", &c[..N])
    } else {
        c
    };
    agent_log(&format!("act {}: {}", kind, truncated));
}

pub fn parse_bearer(req: &HttpRequest) -> Option<String> {
    let h = req.header("Authorization");
    let tok = h.strip_prefix("Bearer ")?.trim();
    if tok.is_empty() {
        None
    } else {
        Some(tok.to_string())
    }
}

pub fn is_loopback_addr(remote_addr: &str) -> bool {
    crate::mcp::is_loopback(remote_addr)
}

pub fn write_sse_headers(stream: &mut dyn Write) -> std::io::Result<()> {
    stream.write_all(
        b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nX-Accel-Buffering: no\r\nConnection: close\r\n\r\n",
    )?;
    stream.flush()
}

pub fn write_sse_json(stream: &mut dyn Write, event: &str, val: &JsonValue) -> std::io::Result<()> {
    write!(
        stream,
        "event: {}\ndata: {}\n\n",
        event,
        val.to_json_string()
    )?;
    stream.flush()
}
