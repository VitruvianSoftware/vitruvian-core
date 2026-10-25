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

//! Fail-safe OTLP/HTTP transport (`http_client.py`, and the copies inlined in
//! `telemetry_hook.py` and `session_exporter.py`).
//!
//! `http://` goes over a `TcpStream` directly. std has no TLS, so `https://`,
//! and any request a proxy variable would route, goes through the system
//! `curl`. Python's `urlopen` behaviour is kept where it shows: one attempt,
//! no retries; a non-2xx status is an HTTP error; a socket timeout while
//! connecting is a URL error but one while reading the response is a bare
//! timeout; certificate failures retry once unverified, except in the session
//! exporter, which never verifies.
//!
//! Each Python module words its errors differently, so the error is kept
//! structured and [`Flavor`] renders it.

use crate::gzip;
use crate::json::{dumps, float_repr, J};
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

/// A response that made it back, whatever its status.
#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub reason: String,
    pub body: Vec<u8>,
}

#[derive(Debug, Clone)]
pub enum HttpError {
    /// `urllib.error.HTTPError`: the server answered with a non-2xx status.
    Status(HttpResponse),
    /// `urllib.error.URLError(reason)`: no usable answer (refused, DNS,
    /// connect timeout, TLS).
    Url(String),
    /// A bare `TimeoutError` while waiting for the response.
    Timeout,
}

impl HttpError {
    /// `str(e)` as Python prints the exception.
    pub fn py_str(&self) -> String {
        match self {
            HttpError::Status(r) => format!("HTTP Error {}: {}", r.status, r.reason),
            HttpError::Url(reason) => format!("<urlopen error {}>", reason),
            HttpError::Timeout => "timed out".to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Tls {
    /// Verify; on a certificate failure retry once without verification
    /// (`http_client.py`, `telemetry_hook.py`).
    VerifyThenInsecure,
    /// Never verify (`session_exporter.py`'s `_create_unverified_context`).
    Insecure,
}

struct Url {
    scheme: String,
    host: String,
    port: u16,
    target: String,
}

fn parse_url(url: &str) -> Result<Url, String> {
    let (scheme, rest) = url
        .split_once("://")
        .ok_or_else(|| format!("unknown url type: {}", url))?;
    let scheme = scheme.to_ascii_lowercase();
    let (authority, target) = match rest.find(['/', '?', '#']) {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, ""),
    };
    let target = target.split('#').next().unwrap_or("");
    let target = if target.is_empty() {
        "/".to_string()
    } else if target.starts_with('?') {
        format!("/{}", target)
    } else {
        target.to_string()
    };
    let authority = authority.rsplit('@').next().unwrap_or(authority);
    let default_port = if scheme == "https" { 443 } else { 80 };
    let (host, port) = if let Some(stripped) = authority.strip_prefix('[') {
        let end = stripped.find(']').ok_or("invalid IPv6 URL")?;
        let host = stripped[..end].to_string();
        let after = &stripped[end + 1..];
        let port = match after.strip_prefix(':') {
            Some(p) if !p.is_empty() => {
                p.parse().map_err(|_| format!("nonnumeric port: '{}'", p))?
            }
            _ => default_port,
        };
        (host, port)
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) if !p.is_empty() => (
                h.to_string(),
                p.parse().map_err(|_| format!("nonnumeric port: '{}'", p))?,
            ),
            Some((h, _)) => (h.to_string(), default_port),
            None => (authority.to_string(), default_port),
        }
    };
    if host.is_empty() {
        return Err("no host given".to_string());
    }
    Ok(Url {
        scheme,
        host,
        port,
        target,
    })
}

/// Python words an OSError as `[Errno 61] Connection refused`; Rust as
/// `Connection refused (os error 61)`.
fn os_error_reason(e: &std::io::Error) -> String {
    if e.kind() == std::io::ErrorKind::TimedOut || e.kind() == std::io::ErrorKind::WouldBlock {
        return "timed out".to_string();
    }
    let text = e.to_string();
    match e.raw_os_error() {
        Some(n) => {
            let msg = text.split(" (os error").next().unwrap_or(&text);
            format!("[Errno {}] {}", n, msg)
        }
        None => text
            .strip_prefix("failed to lookup address information: ")
            .map(|s| format!("[Errno 8] {}", s))
            .unwrap_or(text),
    }
}

fn proxy_configured(scheme: &str) -> bool {
    let names: &[&str] = if scheme == "https" {
        &["https_proxy", "HTTPS_PROXY", "all_proxy", "ALL_PROXY"]
    } else {
        &["http_proxy", "HTTP_PROXY", "all_proxy", "ALL_PROXY"]
    };
    names.iter().any(|n| {
        std::env::var(n)
            .map(|v| !v.trim().is_empty())
            .unwrap_or(false)
    })
}

fn find_header_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n").map(|i| i + 4)
}

fn parse_status_line(line: &str) -> Option<(u16, String)> {
    let mut parts = line.splitn(3, ' ');
    let proto = parts.next()?;
    if !proto.starts_with("HTTP/") {
        return None;
    }
    let status = parts.next()?.trim().parse().ok()?;
    let reason = parts.next().unwrap_or("").trim().to_string();
    Some((status, reason))
}

fn header_value<'a>(head: &'a str, name: &str) -> Option<&'a str> {
    head.lines().skip(1).find_map(|l| {
        let (k, v) = l.split_once(':')?;
        if k.trim().eq_ignore_ascii_case(name) {
            Some(v.trim())
        } else {
            None
        }
    })
}

fn decode_chunked(mut body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let Some(nl) = body.windows(2).position(|w| w == b"\r\n") else {
            break;
        };
        let size_line = String::from_utf8_lossy(&body[..nl]);
        let size_hex = size_line.split(';').next().unwrap_or("").trim();
        let Ok(size) = usize::from_str_radix(size_hex, 16) else {
            break;
        };
        body = &body[nl + 2..];
        if size == 0 || body.len() < size {
            out.extend_from_slice(&body[..size.min(body.len())]);
            break;
        }
        out.extend_from_slice(&body[..size]);
        body = &body[(size + 2).min(body.len())..];
    }
    out
}

/// Split a raw HTTP response (possibly preceded by `100 Continue` blocks or a
/// proxy's `Connection established`) into status, reason and body.
fn parse_response(raw: &[u8]) -> Option<HttpResponse> {
    let mut rest = raw;
    loop {
        let end = find_header_end(rest)?;
        let head = String::from_utf8_lossy(&rest[..end]).into_owned();
        let (status, reason) = parse_status_line(head.lines().next()?)?;
        let body = &rest[end..];
        let interim = (100..200).contains(&status)
            || (status == 200
                && reason
                    .to_ascii_lowercase()
                    .contains("connection established")
                && body.starts_with(b"HTTP/"));
        if interim {
            rest = body;
            continue;
        }
        let chunked = header_value(&head, "transfer-encoding")
            .map(|v| v.to_ascii_lowercase().contains("chunked"))
            .unwrap_or(false);
        let body = if chunked {
            decode_chunked(body)
        } else if let Some(n) =
            header_value(&head, "content-length").and_then(|v| v.parse::<usize>().ok())
        {
            body[..n.min(body.len())].to_vec()
        } else {
            body.to_vec()
        };
        return Some(HttpResponse {
            status,
            reason,
            body,
        });
    }
}

fn classify(resp: HttpResponse) -> Result<HttpResponse, HttpError> {
    if (200..300).contains(&resp.status) {
        Ok(resp)
    } else {
        Err(HttpError::Status(resp))
    }
}

fn post_tcp(
    url: &Url,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: f64,
) -> Result<HttpResponse, HttpError> {
    let t = Duration::from_secs_f64(timeout.max(0.001));
    let addrs = (url.host.as_str(), url.port)
        .to_socket_addrs()
        .map_err(|e| HttpError::Url(os_error_reason(&e)))?;
    let mut last_err: Option<std::io::Error> = None;
    let mut stream = None;
    for addr in addrs {
        match TcpStream::connect_timeout(&addr, t) {
            Ok(s) => {
                stream = Some(s);
                break;
            }
            Err(e) => last_err = Some(e),
        }
    }
    let mut stream = match stream {
        Some(s) => s,
        None => {
            let reason = last_err.map(|e| os_error_reason(&e)).unwrap_or_else(|| {
                "[Errno 8] nodename nor servname provided, or not known".to_string()
            });
            return Err(HttpError::Url(reason));
        }
    };
    let _ = stream.set_read_timeout(Some(t));
    let _ = stream.set_write_timeout(Some(t));

    let host_header = match (url.scheme.as_str(), url.port) {
        ("http", 80) => url.host.clone(),
        _ if url.host.contains(':') => format!("[{}]:{}", url.host, url.port),
        _ => format!("{}:{}", url.host, url.port),
    };
    let mut req = format!(
        "POST {} HTTP/1.1\r\nHost: {}\r\nAccept-Encoding: identity\r\n",
        url.target, host_header
    );
    for (k, v) in headers {
        req.push_str(&format!("{}: {}\r\n", k, v));
    }
    req.push_str(&format!(
        "Content-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    ));
    let mut wire = req.into_bytes();
    wire.extend_from_slice(body);
    stream
        .write_all(&wire)
        .map_err(|e| HttpError::Url(os_error_reason(&e)))?;

    let mut raw = Vec::new();
    let mut buf = [0u8; 8192];
    loop {
        match stream.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                raw.extend_from_slice(&buf[..n]);
                // Stop once a complete Content-Length body is in, rather than
                // waiting for a server that ignores `Connection: close`.
                if let Some(end) = find_header_end(&raw) {
                    let head = String::from_utf8_lossy(&raw[..end]);
                    let status = head.lines().next().and_then(parse_status_line).map(|s| s.0);
                    if status.map(|s| s >= 200).unwrap_or(false) {
                        if let Some(n) = header_value(&head, "content-length")
                            .and_then(|v| v.parse::<usize>().ok())
                        {
                            if raw.len() >= end + n {
                                break;
                            }
                        }
                    }
                }
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
            {
                return Err(HttpError::Timeout)
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => {
                if raw.is_empty() {
                    return Err(HttpError::Url(os_error_reason(&e)));
                }
                break;
            }
        }
    }
    match parse_response(&raw) {
        Some(resp) => classify(resp),
        None => Err(HttpError::Url(
            "Remote end closed connection without response".to_string(),
        )),
    }
}

fn post_curl(
    url: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: f64,
    insecure: bool,
) -> Result<HttpResponse, (HttpError, bool)> {
    let secs = format!("{}", timeout.max(0.001));
    let mut argv: Vec<String> = vec![
        "curl".into(),
        "-sS".into(),
        "--http1.1".into(),
        "-i".into(),
        "-X".into(),
        "POST".into(),
        "--data-binary".into(),
        "@-".into(),
        "-m".into(),
        secs.clone(),
        "--connect-timeout".into(),
        secs,
        "-H".into(),
        "Expect:".into(),
    ];
    for (k, v) in headers {
        argv.push("-H".into());
        argv.push(format!("{}: {}", k, v));
    }
    if insecure {
        argv.push("-k".into());
    }
    argv.push(url.to_string());
    let refs: Vec<&str> = argv.iter().map(String::as_str).collect();
    let out = match crate::sys::run(&refs, Some(body), Some(timeout + 5.0)) {
        Ok(o) => o,
        Err(crate::sys::CmdError::Timeout) => return Err((HttpError::Timeout, false)),
        Err(crate::sys::CmdError::Spawn(e)) => {
            return Err((
                HttpError::Url(format!("curl unavailable for {}: {}", url, e)),
                false,
            ))
        }
    };
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    let stderr = stderr.strip_prefix("curl: ").unwrap_or(&stderr).to_string();
    match out.code {
        0 => match parse_response(&out.stdout) {
            Some(resp) => classify(resp).map_err(|e| (e, false)),
            None => Err((
                HttpError::Url("Remote end closed connection without response".into()),
                false,
            )),
        },
        28 => Err((HttpError::Timeout, false)),
        // Peer certificate cannot be authenticated with known CA certificates.
        60 => Err((
            HttpError::Url(format!(
                "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed ({})",
                stderr
            )),
            true,
        )),
        _ => Err((HttpError::Url(stderr), false)),
    }
}

/// POST `body` to `url`: one attempt, plus the unverified retry `tls` allows.
pub fn post(
    url: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: f64,
    tls: Tls,
) -> Result<HttpResponse, HttpError> {
    let parsed = parse_url(url).map_err(HttpError::Url)?;
    match parsed.scheme.as_str() {
        "http" if !proxy_configured("http") => post_tcp(&parsed, headers, body, timeout),
        "http" | "https" => {
            let insecure = tls == Tls::Insecure;
            match post_curl(url, headers, body, timeout, insecure) {
                Ok(r) => Ok(r),
                Err((_, true)) if !insecure => {
                    post_curl(url, headers, body, timeout, true).map_err(|(e, _)| e)
                }
                Err((e, _)) => Err(e),
            }
        }
        other => Err(HttpError::Url(format!("unknown url type: '{}'", other))),
    }
}

/// Which Python module's client this is: they differ in the gzip threshold
/// and in how they word a failure.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Flavor {
    /// `http_client.TelemetryHttpClient` (used by `antigravity_telemetry.py`).
    Builder,
    /// The copy inlined in `telemetry_hook.py`.
    Hook,
}

pub struct TelemetryHttpClient {
    pub base_url: String,
    pub timeout: f64,
    pub user_agent: String,
    pub flavor: Flavor,
}

pub const USER_AGENT: &str = "antigravity-telemetry/1.0.0";

impl TelemetryHttpClient {
    pub fn new(base_url: &str, timeout: f64, flavor: Flavor) -> Self {
        TelemetryHttpClient {
            base_url: base_url.trim_end_matches('/').to_string(),
            timeout,
            user_agent: USER_AGENT.to_string(),
            flavor,
        }
    }

    pub fn resolve_url(&self, path_or_url: &str) -> String {
        if path_or_url.starts_with("http://") || path_or_url.starts_with("https://") {
            return path_or_url.to_string();
        }
        let p = path_or_url.trim_start_matches('/');
        if self.base_url.ends_with(p) {
            return self.base_url.clone();
        }
        format!("{}/{}", self.base_url, p)
    }

    /// `post_json(...) -> (success, status_code, response_or_error)`.
    pub fn post_json(
        &self,
        path_or_url: &str,
        payload: &J,
        compress: bool,
        silent: bool,
    ) -> (bool, u16, String) {
        let url = self.resolve_url(path_or_url);
        let mut raw = dumps(payload, None, false).into_bytes();
        let mut headers: Vec<(&str, String)> = vec![
            ("Content-Type", "application/json".to_string()),
            ("User-Agent", self.user_agent.clone()),
            ("Accept", "application/json".to_string()),
        ];
        let threshold = match self.flavor {
            Flavor::Builder => 1024,
            Flavor::Hook => 256,
        };
        if compress && raw.len() > threshold {
            raw = gzip::compress(&raw);
            headers.push(("Content-Encoding", "gzip".to_string()));
        }
        let (ok, code, msg) =
            match post(&url, &headers, &raw, self.timeout, Tls::VerifyThenInsecure) {
                Ok(resp) => {
                    return (
                        true,
                        resp.status,
                        String::from_utf8_lossy(&resp.body).into_owned(),
                    );
                }
                Err(HttpError::Status(r)) => {
                    (false, r.status, format!("HTTP {}: {}", r.status, r.reason))
                }
                Err(e) => {
                    let msg = match (self.flavor, &e) {
                        (Flavor::Builder, HttpError::Url(reason)) => {
                            format!("URLError: {}", reason)
                        }
                        (Flavor::Builder, HttpError::Timeout) => {
                            format!(
                                "Timeout ({}s) connecting to {}",
                                float_repr(self.timeout),
                                url
                            )
                        }
                        _ => format!("Error: {}", e.py_str()),
                    };
                    (false, 0, msg)
                }
            };
        if !silent {
            eprintln!("[TelemetryHttpClient] {}", msg);
        }
        (ok, code, msg)
    }

    /// Probe the collector with an empty metrics export.
    pub fn check_health(&self) -> (bool, String) {
        let probe = J::obj(vec![("resourceMetrics", J::Arr(vec![]))]);
        let (ok, code, msg) = self.post_json("v1/metrics", &probe, false, true);
        if ok || code == 200 || code == 202 {
            return (
                true,
                format!(
                    "OpenTelemetry Collector reachable at {} (HTTP {})",
                    self.base_url, code
                ),
            );
        }
        (
            false,
            format!(
                "OpenTelemetry Collector unreachable at {}: {}",
                self.base_url, msg
            ),
        )
    }
}

/// `session_exporter.TranscriptScanner._send_payload`: gzip above 256 bytes,
/// never verify TLS, 3 s timeout, failures logged to stderr.
pub fn send_exporter_payload(url: &str, payload: &J) {
    let mut raw = dumps(payload, None, true).into_bytes();
    let mut headers: Vec<(&str, String)> = vec![("Content-Type", "application/json".to_string())];
    if raw.len() > 256 {
        raw = gzip::compress(&raw);
        headers.push(("Content-Encoding", "gzip".to_string()));
    }
    if let Err(e) = post(url, &headers, &raw, 3.0, Tls::Insecure) {
        eprintln!(
            "[session_exporter] Export to {} failed: {}",
            url,
            e.py_str()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_parsing() {
        let u = parse_url("http://127.0.0.1:4318/v1/metrics").unwrap();
        assert_eq!(
            (u.host.as_str(), u.port, u.target.as_str()),
            ("127.0.0.1", 4318, "/v1/metrics")
        );
        let u = parse_url("https://otel.lab.ipv1337.dev").unwrap();
        assert_eq!((u.port, u.target.as_str()), (443, "/"));
        let u = parse_url("http://[::1]:9/x?y=1").unwrap();
        assert_eq!(
            (u.host.as_str(), u.port, u.target.as_str()),
            ("::1", 9, "/x?y=1")
        );
    }

    #[test]
    fn resolve_url_matches_python() {
        let c = TelemetryHttpClient::new("http://h:1/", 2.0, Flavor::Builder);
        assert_eq!(c.resolve_url("v1/metrics"), "http://h:1/v1/metrics");
        assert_eq!(c.resolve_url("/v1/traces"), "http://h:1/v1/traces");
        assert_eq!(c.resolve_url("https://x/y"), "https://x/y");
        let c = TelemetryHttpClient::new("http://h:1/v1/metrics", 2.0, Flavor::Builder);
        assert_eq!(c.resolve_url("v1/metrics"), "http://h:1/v1/metrics");
    }

    #[test]
    fn response_parsing_skips_continue_and_dechunks() {
        let raw = b"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nabcd\r\n2\r\nef\r\n0\r\n\r\n";
        let r = parse_response(raw).unwrap();
        assert_eq!(
            (r.status, r.reason.as_str(), r.body.as_slice()),
            (200, "OK", &b"abcdef"[..])
        );
        let raw = b"HTTP/1.0 500 Internal Server Error\r\nContent-Length: 2\r\n\r\nno";
        let r = parse_response(raw).unwrap();
        assert_eq!((r.status, r.body.as_slice()), (500, &b"no"[..]));
    }

    #[test]
    fn refused_connection_is_a_url_error() {
        // Bind then drop to find a port nothing listens on.
        let port = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let c =
            TelemetryHttpClient::new(&format!("http://127.0.0.1:{}", port), 1.0, Flavor::Builder);
        let (ok, code, msg) = c.post_json("v1/metrics", &J::empty_obj(), false, true);
        assert!(!ok);
        assert_eq!(code, 0);
        assert!(msg.starts_with("URLError: [Errno "), "{}", msg);
        assert!(msg.contains("refused"), "{}", msg);
    }

    #[test]
    fn round_trip_against_local_server() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut buf = Vec::new();
            let mut chunk = [0u8; 4096];
            loop {
                let n = s.read(&mut chunk).unwrap();
                buf.extend_from_slice(&chunk[..n]);
                if let Some(end) = find_header_end(&buf) {
                    let head = String::from_utf8_lossy(&buf[..end]).into_owned();
                    let len: usize = header_value(&head, "content-length")
                        .unwrap()
                        .parse()
                        .unwrap();
                    if buf.len() >= end + len {
                        break;
                    }
                }
            }
            s.write_all(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n")
                .unwrap();
            String::from_utf8_lossy(&buf).into_owned()
        });
        let c = TelemetryHttpClient::new(&format!("http://127.0.0.1:{}", port), 2.0, Flavor::Hook);
        let (ok, code, msg) =
            c.post_json("v1/metrics", &J::obj(vec![("a", J::Int(1))]), true, true);
        let req = server.join().unwrap();
        assert_eq!(
            (ok, code, msg.as_str()),
            (false, 503, "HTTP 503: Service Unavailable")
        );
        assert!(req.starts_with("POST /v1/metrics HTTP/1.1\r\n"));
        assert!(req.ends_with("{\"a\": 1}"));
    }
}
