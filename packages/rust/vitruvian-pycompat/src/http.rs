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

//! Standard-library-only HTTP transport for ported tools: plain `http://` over
//! [`TcpStream`] and `https://` through `curl` (`-q -sS -K -`), because the
//! Rust standard library has no TLS.
//!
//! Security model (from `tools/sentry/src/http.rs` and
//! `tools/registry-trust/src/http.rs`):
//! - Invokes `curl` with a static argv list (`["-q", "-sS", "-K", "-"]`),
//!   never through a shell. `-q` comes first so user `~/.curlrc` files cannot
//!   alter TLS verification or proxy settings.
//! - Passes URL, method, headers (including secrets/tokens), body, protocol
//!   pinning (`proto = "=https"` / `"=http"`), and `write-out` exclusively via
//!   `curl`'s stdin config (`-K -`), never on argv or in child env.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::process::{Command, Stdio};
use std::time::Duration;

const STATUS_MARKER: &str = "\n__vitruvian_pycompat_http_status__:";

#[derive(Debug, Clone, Copy)]
pub struct Request<'a> {
    pub method: &'a str,
    pub url: &'a str,
    pub headers: &'a [(&'a str, String)],
    pub body: Option<&'a [u8]>,
    pub timeout: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub reason: String,
    pub body: Vec<u8>,
}

#[derive(Debug, Clone, Copy)]
pub struct Options<'a> {
    pub user_agent: &'a str,
    pub timeout: Option<Duration>,
}

impl Default for Options<'static> {
    fn default() -> Self {
        Self {
            user_agent: "vitruvian-pycompat-http",
            timeout: None,
        }
    }
}

#[derive(Debug)]
pub enum TransportError {
    InvalidScheme,
    NoHost,
    Resolve(std::io::Error),
    NoAddress,
    Connect {
        addr: SocketAddr,
        err: std::io::Error,
    },
    Io(std::io::Error),
    NoResponse,
    BadStatusLine(String),
    CurlSpawn(std::io::Error),
    CurlWait(std::io::Error),
    CurlFailed {
        code: Option<i32>,
        stderr: String,
    },
    NoStatus {
        stderr: String,
    },
}

/// Format an `std::io::Error` as `[Errno N] text` (or `text` alone if no raw errno).
pub fn os_error_reason(e: &std::io::Error) -> String {
    let text = e.to_string();
    let text = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    match e.raw_os_error() {
        Some(code) => format!("[Errno {}] {}", code, text),
        None => text,
    }
}

/// Decode an HTTP/1.1 `Transfer-Encoding: chunked` body.
pub fn dechunk(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < data.len() {
        let Some(p) = data[i..].windows(2).position(|w| w == b"\r\n") else {
            break;
        };
        let size_text = String::from_utf8_lossy(&data[i..i + p]);
        let size_text = size_text.split(';').next().unwrap_or("").trim();
        let size = usize::from_str_radix(size_text, 16).unwrap_or(0);
        i += p + 2;
        if size == 0 {
            break;
        }
        let end = (i + size).min(data.len());
        out.extend_from_slice(&data[i..end]);
        i = end + 2;
    }
    out
}

/// Quote a string for a `curl -K` stdin config file, escaping `\`, `"`, `\n`, `\r`, `\t`.
pub fn config_quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn has_prefix_ignore_ascii_case(s: &str, prefix: &str) -> bool {
    s.len() >= prefix.len() && s[..prefix.len()].eq_ignore_ascii_case(prefix)
}

fn format_max_time(timeout: Duration) -> String {
    if timeout.subsec_nanos() == 0 {
        timeout.as_secs().to_string()
    } else {
        format!("{:.3}", timeout.as_secs_f64().max(0.001))
    }
}

/// Build the stdin config for `curl -q -sS -K -`.
pub fn curl_config(req: &Request<'_>, timeout: Duration) -> Result<String, TransportError> {
    let proto = if has_prefix_ignore_ascii_case(req.url, "https://") {
        "=https"
    } else if has_prefix_ignore_ascii_case(req.url, "http://") {
        "=http"
    } else {
        return Err(TransportError::InvalidScheme);
    };
    if req.url.contains('\0')
        || req.method.contains('\0')
        || req
            .headers
            .iter()
            .any(|(k, v)| k.contains('\0') || v.contains('\0'))
        || req.body.is_some_and(|b| b.contains(&0))
    {
        return Err(TransportError::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "NUL byte in curl config",
        )));
    }

    let mut config = String::new();
    config.push_str(&format!("proto = {}\n", config_quote(proto)));
    config.push_str(&format!("url = {}\n", config_quote(req.url)));
    config.push_str(&format!("request = {}\n", config_quote(req.method)));
    config.push_str(&format!("max-time = {}\n", format_max_time(timeout)));
    for (k, v) in req.headers {
        config.push_str(&format!(
            "header = {}\n",
            config_quote(&format!("{}: {}", k, v))
        ));
    }
    if let Some(body) = req.body {
        config.push_str(&format!(
            "data-raw = {}\n",
            config_quote(&String::from_utf8_lossy(body))
        ));
    }
    config.push_str(&format!(
        "write-out = {}\n",
        config_quote(&format!("{STATUS_MARKER}%{{http_code}}"))
    ));
    Ok(config)
}

/// Send `req` through `curl -q -sS -K -` with everything (including secrets) on stdin.
pub fn send_curl(req: &Request<'_>, timeout: Option<Duration>) -> Result<Response, TransportError> {
    let timeout = timeout.unwrap_or_else(|| Duration::from_secs(req.timeout));
    let config = curl_config(req, timeout)?;
    let mut child = Command::new("curl")
        .args(["-q", "-sS", "-K", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(TransportError::CurlSpawn)?;

    if let Some(mut stdin) = child.stdin.take() {
        if let Err(e) = stdin.write_all(config.as_bytes()) {
            if e.kind() != std::io::ErrorKind::BrokenPipe {
                let _ = child.wait();
                return Err(TransportError::Io(e));
            }
        }
    }

    let out = child.wait_with_output().map_err(TransportError::CurlWait)?;
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    if !out.status.success() {
        return Err(TransportError::CurlFailed {
            code: out.status.code(),
            stderr,
        });
    }

    let mark = STATUS_MARKER.as_bytes();
    let Some(pos) = out.stdout.windows(mark.len()).rposition(|w| w == mark) else {
        return Err(TransportError::NoStatus { stderr });
    };
    let status = std::str::from_utf8(&out.stdout[pos + mark.len()..])
        .ok()
        .and_then(|s| s.trim().parse::<u16>().ok())
        .filter(|&c| c != 0)
        .ok_or(TransportError::NoStatus { stderr })?;

    Ok(Response {
        status,
        reason: String::new(),
        body: out.stdout[..pos].to_vec(),
    })
}

/// Send `req` over a plain `TcpStream` (`http://` URLs only).
pub fn send_plain(req: &Request<'_>, opts: &Options<'_>) -> Result<Response, TransportError> {
    if !has_prefix_ignore_ascii_case(req.url, "http://") {
        return Err(TransportError::InvalidScheme);
    }
    let rest = &req.url["http://".len()..];
    let (authority, raw_path) = match rest.find(['/', '?']) {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };
    if authority.is_empty() {
        return Err(TransportError::NoHost);
    }
    let path = if raw_path.starts_with('?') {
        format!("/{}", raw_path)
    } else {
        raw_path.to_string()
    };

    let has_port = match (authority.rfind(':'), authority.rfind(']')) {
        (Some(i), j) => j.map_or(true, |j| i > j),
        _ => false,
    };
    let hostport = if has_port {
        authority.to_string()
    } else {
        format!("{}:80", authority)
    };

    let timeout = opts
        .timeout
        .unwrap_or_else(|| Duration::from_secs(req.timeout));
    let addrs: Vec<SocketAddr> = hostport
        .to_socket_addrs()
        .map_err(TransportError::Resolve)?
        .collect();
    let mut last = None;
    let mut stream = None;
    for a in addrs {
        match TcpStream::connect_timeout(&a, timeout) {
            Ok(s) => {
                stream = Some(s);
                break;
            }
            Err(e) => last = Some((a, e)),
        }
    }
    let mut stream = match stream {
        Some(s) => s,
        None => {
            return Err(match last {
                Some((addr, err)) => TransportError::Connect { addr, err },
                None => TransportError::NoAddress,
            });
        }
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let mut head = format!("{} {} HTTP/1.1\r\n", req.method, path);
    head.push_str("Accept-Encoding: identity\r\n");
    head.push_str(&format!("Host: {}\r\n", authority));
    if !opts.user_agent.is_empty() {
        head.push_str(&format!("User-Agent: {}\r\n", opts.user_agent));
    }
    head.push_str("Connection: close\r\n");
    if let Some(body) = req.body {
        head.push_str(&format!("Content-Length: {}\r\n", body.len()));
    }
    let mut wire = head.into_bytes();
    // Header values go out as latin-1, as Python's http.client encodes them.
    for (k, v) in req.headers {
        wire.extend_from_slice(k.as_bytes());
        wire.extend_from_slice(b": ");
        wire.extend(v.chars().map(|c| c as u32 as u8));
        wire.extend_from_slice(b"\r\n");
    }
    wire.extend_from_slice(b"\r\n");
    if let Some(body) = req.body {
        wire.extend_from_slice(body);
    }
    stream.write_all(&wire).map_err(TransportError::Io)?;

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).map_err(TransportError::Io)?;
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or(TransportError::NoResponse)?;
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let mut body = raw[split + 4..].to_vec();
    let mut lines = head.split("\r\n");
    let status_line = lines.next().unwrap_or("");
    let mut parts = status_line.splitn(3, ' ');
    let _version = parts.next();
    let code: u16 = parts
        .next()
        .and_then(|c| c.parse().ok())
        .ok_or_else(|| TransportError::BadStatusLine(status_line.to_string()))?;
    let reason = parts.next().unwrap_or("").to_string();
    let mut chunked = false;
    let mut length: Option<usize> = None;
    for line in lines {
        if let Some((k, v)) = line.split_once(':') {
            let k = k.trim().to_ascii_lowercase();
            let v = v.trim();
            if k == "transfer-encoding" && v.to_ascii_lowercase().contains("chunked") {
                chunked = true;
            } else if k == "content-length" {
                length = v.parse().ok();
            }
        }
    }
    if chunked {
        body = dechunk(&body);
    } else if let Some(n) = length {
        body.truncate(n);
    }
    Ok(Response {
        status: code,
        reason,
        body,
    })
}

/// Send `req`: `http://` over a plain socket, `https://` through `curl`.
pub fn send_with(req: &Request<'_>, opts: &Options<'_>) -> Result<Response, TransportError> {
    if has_prefix_ignore_ascii_case(req.url, "http://") {
        send_plain(req, opts)
    } else if has_prefix_ignore_ascii_case(req.url, "https://") {
        send_curl(req, opts.timeout)
    } else {
        Err(TransportError::InvalidScheme)
    }
}

/// Send `req` with [`Options::default()`].
pub fn send(req: &Request<'_>) -> Result<Response, TransportError> {
    send_with(req, &Options::default())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::net::TcpListener;
    use std::sync::mpsc;
    use std::thread;

    fn serve(response: &'static [u8]) -> (String, mpsc::Receiver<Vec<u8>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut r = BufReader::new(s.try_clone().unwrap());
            let mut req = Vec::new();
            let mut len = 0usize;
            loop {
                let mut line = String::new();
                let n = r.read_line(&mut line).unwrap_or(0);
                if n == 0 {
                    break;
                }
                req.extend_from_slice(line.as_bytes());
                let trimmed = line.trim_end_matches(['\r', '\n']);
                if trimmed.is_empty() {
                    break;
                }
                if let Some(v) = trimmed.to_ascii_lowercase().strip_prefix("content-length:") {
                    len = v.trim().parse().unwrap_or(0);
                }
            }
            if len > 0 {
                let mut body = vec![0u8; len];
                let _ = r.read_exact(&mut body);
                req.extend_from_slice(&body);
            }
            let _ = tx.send(req);
            s.write_all(response).unwrap();
        });
        (format!("http://{}/x?y=1", addr), rx)
    }

    #[test]
    fn config_quote_escapes_special_chars() {
        assert_eq!(config_quote(r#"a"b\c"#), r#""a\"b\\c""#);
        assert_eq!(config_quote("x\ny\rz\tw"), r#""x\ny\rz\tw""#);
    }

    #[test]
    fn curl_config_pins_protocol_and_rejects_non_http_schemes() {
        let headers = [("Authorization", "Bearer se\"cret".to_string())];
        let req = Request {
            method: "POST",
            url: "https://api.example/v1",
            headers: &headers,
            body: Some(br#"{"a": "b\c"}"#),
            timeout: 15,
        };
        let cfg = curl_config(&req, Duration::from_secs(15)).unwrap();
        assert!(cfg.contains("proto = \"=https\"\n"), "{cfg}");
        assert!(cfg.contains("url = \"https://api.example/v1\"\n"), "{cfg}");
        assert!(cfg.contains("request = \"POST\"\n"), "{cfg}");
        assert!(cfg.contains("max-time = 15\n"), "{cfg}");
        assert!(
            cfg.contains("header = \"Authorization: Bearer se\\\"cret\"\n"),
            "{cfg}"
        );
        assert!(
            cfg.contains("data-raw = \"{\\\"a\\\": \\\"b\\\\c\\\"}\"\n"),
            "{cfg}"
        );

        let nul_body_req = Request {
            body: Some(b"a\0b"),
            ..req
        };
        assert!(matches!(
            curl_config(&nul_body_req, Duration::from_secs(1)),
            Err(TransportError::Io(_))
        ));

        let http_req = Request {
            url: "http://127.0.0.1:8080/x",
            ..req
        };
        let http_cfg = curl_config(&http_req, Duration::from_millis(250)).unwrap();
        assert!(http_cfg.contains("proto = \"=http\"\n"), "{http_cfg}");
        assert!(http_cfg.contains("max-time = 0.250\n"), "{http_cfg}");

        for bad in ["file:///etc/passwd", "gopher://x/", "nope"] {
            let bad_req = Request { url: bad, ..req };
            assert!(matches!(
                curl_config(&bad_req, Duration::from_secs(1)),
                Err(TransportError::InvalidScheme)
            ));
        }
    }

    #[test]
    fn plain_get_post_headers_non_2xx_chunked_and_timeout() {
        let (url, _) = serve(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n[]extra");
        let resp = send(&Request {
            method: "GET",
            url: &url,
            headers: &[],
            body: None,
            timeout: 5,
        })
        .unwrap();
        assert_eq!(resp.status, 200);
        assert_eq!(resp.body, b"[]");

        let (url, rx) = serve(
            b"HTTP/1.1 201 Created\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nok\r\n1\r\n!\r\n0\r\n\r\n",
        );
        let headers = [
            ("Authorization", "Bearer tok".to_string()),
            ("Content-Type", "application/json".to_string()),
        ];
        let resp = send(&Request {
            method: "POST",
            url: &url,
            headers: &headers,
            body: Some(b"{\"a\":1}"),
            timeout: 5,
        })
        .unwrap();
        assert_eq!(resp.status, 201);
        assert_eq!(resp.body, b"ok!");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.starts_with("POST /x?y=1 HTTP/1.1\r\n"), "{sent}");
        assert!(sent.contains("Authorization: Bearer tok\r\n"), "{sent}");
        assert!(
            sent.contains("Content-Type: application/json\r\n"),
            "{sent}"
        );
        assert!(sent.contains("Content-Length: 7\r\n"), "{sent}");
        assert!(sent.ends_with("\r\n\r\n{\"a\":1}"), "{sent}");

        let (url, _) = serve(b"HTTP/1.0 502 Bad Gateway\r\nContent-Length: 4\r\n\r\ndown");
        let resp = send(&Request {
            method: "GET",
            url: &url,
            headers: &[],
            body: None,
            timeout: 5,
        })
        .unwrap();
        assert_eq!(resp.status, 502);
        assert_eq!(resp.reason, "Bad Gateway");
        assert_eq!(resp.body, b"down");

        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let (tx, rx) = mpsc::channel::<()>();
        let handle = thread::spawn(move || {
            let (_s, _) = listener.accept().unwrap();
            let _ = rx.recv_timeout(Duration::from_secs(5));
        });
        let res = send_with(
            &Request {
                method: "GET",
                url: &format!("http://{}/slow", addr),
                headers: &[],
                body: None,
                timeout: 1,
            },
            &Options {
                user_agent: "test-agent",
                timeout: Some(Duration::from_millis(150)),
            },
        );
        drop(tx);
        let _ = handle.join();
        assert!(matches!(res, Err(TransportError::Io(_))), "{res:?}");
    }

    #[test]
    fn curl_get_post_headers_non_2xx_and_timeout() {
        let (url, rx) = serve(b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello");
        let resp = send_curl(
            &Request {
                method: "GET",
                url: &url,
                headers: &[("X-Test", "get".to_string())],
                body: None,
                timeout: 5,
            },
            None,
        )
        .unwrap();
        assert_eq!(resp.status, 200);
        assert_eq!(resp.body, b"hello");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.starts_with("GET /x?y=1 HTTP/1.1\r\n"), "{sent}");
        assert!(sent.contains("X-Test: get\r\n"), "{sent}");

        let (url, rx) = serve(b"HTTP/1.1 201 Created\r\nContent-Length: 7\r\n\r\ncreated");
        let resp = send_curl(
            &Request {
                method: "POST",
                url: &url,
                headers: &[
                    ("Authorization", "Bearer curl-secret".to_string()),
                    ("Content-Type", "application/json".to_string()),
                ],
                body: Some(b"{\"k\":2}"),
                timeout: 5,
            },
            None,
        )
        .unwrap();
        assert_eq!(resp.status, 201);
        assert_eq!(resp.body, b"created");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.starts_with("POST /x?y=1 HTTP/1.1\r\n"), "{sent}");
        assert!(
            sent.contains("Authorization: Bearer curl-secret\r\n"),
            "{sent}"
        );
        assert!(
            sent.contains("Content-Type: application/json\r\n"),
            "{sent}"
        );
        assert!(sent.ends_with("\r\n\r\n{\"k\":2}"), "{sent}");

        let (url, rx) = serve(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok");
        let resp = send_curl(
            &Request {
                method: "POST",
                url: &url,
                headers: &[],
                body: Some(b"@literal\nline2"),
                timeout: 5,
            },
            None,
        )
        .unwrap();
        assert_eq!(resp.status, 200);
        assert_eq!(resp.body, b"ok");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.ends_with("\r\n\r\n@literal\nline2"), "{sent}");

        let (url, _) = serve(b"HTTP/1.1 404 Not Found\r\nContent-Length: 7\r\n\r\nmissing");
        let resp = send_curl(
            &Request {
                method: "GET",
                url: &url,
                headers: &[],
                body: None,
                timeout: 5,
            },
            None,
        )
        .unwrap();
        assert_eq!(resp.status, 404);
        assert_eq!(resp.body, b"missing");

        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let (tx, rx) = mpsc::channel::<()>();
        let handle = thread::spawn(move || {
            let (_s, _) = listener.accept().unwrap();
            let _ = rx.recv_timeout(Duration::from_secs(5));
        });
        let res = send_curl(
            &Request {
                method: "GET",
                url: &format!("http://{}/slow", addr),
                headers: &[],
                body: None,
                timeout: 1,
            },
            Some(Duration::from_millis(200)),
        );
        drop(tx);
        let _ = handle.join();
        assert!(
            matches!(res, Err(TransportError::CurlFailed { code: Some(28), .. })),
            "{res:?}"
        );
    }
}
