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

//! HTTP for the catalog's tools: `urllib.request.urlopen(url).read(n)` as
//! check_downloads.py uses it, and the little server rehearse.py runs.
//!
//! The client speaks plain http:// itself (with urllib's redirects) and
//! reads file:// from disk; https:// goes through `curl`, since the
//! standard library has no TLS. Any other scheme fails as urllib's unknown
//! handlers do (an OSError, so no bytes).

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

use crate::pyerr::{Crash, Res};

/// `urlopen(url, timeout=60).read(limit)`: the bytes, None where urlopen
/// raises an OSError, or the crash where it raises anything else.
pub fn fetch(url: &str, limit: usize) -> Res<Option<Vec<u8>>> {
    let url = url.trim();
    let scheme = match url.find(':') {
        Some(i) if i > 0 && !url[..i].contains('/') => url[..i].to_ascii_lowercase(),
        _ => {
            return Err(Crash::new(
                "ValueError",
                format!("unknown url type: {}", crate::pystr::repr_str(url)),
            ))
        }
    };
    let url = url.split('#').next().unwrap_or("");
    match scheme.as_str() {
        "http" => Ok(http_get(url, limit, 0)),
        "https" => Ok(curl(url, limit)),
        "file" => Ok(file(url, limit)),
        _ => Ok(None),
    }
}

fn file(url: &str, limit: usize) -> Option<Vec<u8>> {
    let rest = &url[5..];
    let path = if let Some(r) = rest.strip_prefix("//") {
        let slash = r.find('/').unwrap_or(r.len());
        let host = &r[..slash];
        if !host.is_empty() && host != "localhost" {
            return None;
        }
        &r[slash..]
    } else {
        rest
    };
    let data = std::fs::read(unquote(path)).ok()?;
    Some(data.into_iter().take(limit).collect())
}

fn unquote(text: &str) -> String {
    let b = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&text[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn curl(url: &str, limit: usize) -> Option<Vec<u8>> {
    let mut child = std::process::Command::new("curl")
        .args([
            "--silent",
            "--fail",
            "--location",
            "--max-redirs",
            "10",
            "--max-time",
            "60",
            "--",
            url,
        ])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()?;
    let mut out = Vec::new();
    let mut stdout = child.stdout.take()?;
    let mut buf = [0u8; 65536];
    let mut cut = false;
    loop {
        match stdout.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                let take = n.min(limit - out.len());
                out.extend_from_slice(&buf[..take]);
                if out.len() >= limit {
                    cut = true;
                    break;
                }
            }
            Err(_) => return None,
        }
    }
    if cut {
        let _ = child.kill();
        let _ = child.wait();
        return Some(out);
    }
    let status = child.wait().ok()?;
    if status.success() {
        Some(out)
    } else {
        None
    }
}

struct Url {
    host: String,
    port: u16,
    target: String,
}

fn parse_http(url: &str) -> Option<Url> {
    let rest = url.get(5..)?.strip_prefix("//")?;
    let slash = rest.find(['/', '?']).unwrap_or(rest.len());
    let authority = &rest[..slash];
    let authority = authority.rsplit('@').next().unwrap_or("");
    if authority.is_empty() {
        return None;
    }
    let (host, port) = match authority.rfind(':') {
        Some(i) if !authority[i + 1..].contains(']') => {
            let p = &authority[i + 1..];
            let port = if p.is_empty() { 80 } else { p.parse().ok()? };
            (authority[..i].to_string(), port)
        }
        _ => (authority.to_string(), 80),
    };
    let mut target = rest[slash..].to_string();
    if target.is_empty() || target.starts_with('?') {
        target = format!("/{}", target);
    }
    Some(Url { host, port, target })
}

fn http_get(url: &str, limit: usize, hops: usize) -> Option<Vec<u8>> {
    let u = parse_http(url)?;
    let host = u
        .host
        .trim_start_matches('[')
        .trim_end_matches(']')
        .to_string();
    let mut stream = TcpStream::connect((host.as_str(), u.port)).ok()?;
    stream
        .set_read_timeout(Some(Duration::from_secs(60)))
        .ok()?;
    stream
        .set_write_timeout(Some(Duration::from_secs(60)))
        .ok()?;
    let host_header = if u.port == 80 {
        u.host.clone()
    } else {
        format!("{}:{}", u.host, u.port)
    };
    let request = format!(
        "GET {} HTTP/1.1\r\nAccept-Encoding: identity\r\nHost: {}\r\nUser-Agent: Python-urllib/3.12\r\nConnection: close\r\n\r\n",
        u.target, host_header
    );
    stream.write_all(request.as_bytes()).ok()?;
    let mut reader = BufReader::new(stream);
    let mut status_line = String::new();
    reader.read_line(&mut status_line).ok()?;
    let code: u16 = status_line.split_whitespace().nth(1)?.parse().ok()?;
    let mut headers: Vec<(String, String)> = Vec::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).ok()? == 0 {
            break;
        }
        let line = line.trim_end_matches(['\r', '\n']);
        if line.is_empty() {
            break;
        }
        if let Some((k, v)) = line.split_once(':') {
            headers.push((k.trim().to_ascii_lowercase(), v.trim().to_string()));
        }
    }
    let header = |name: &str| {
        headers
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.clone())
    };
    if matches!(code, 301 | 302 | 303 | 307 | 308) {
        let location = header("location").or_else(|| header("uri"))?;
        if hops >= 10 {
            return None;
        }
        let next = if location.contains("://") {
            location
        } else if location.starts_with('/') {
            format!("http://{}{}", host_header, location)
        } else {
            let base = match u.target.rfind('/') {
                Some(i) => &u.target[..=i],
                None => "/",
            };
            format!("http://{}{}{}", host_header, base, location)
        };
        return match next
            .split(':')
            .next()
            .map(|s| s.to_ascii_lowercase())
            .as_deref()
        {
            Some("http") => http_get(&next, limit, hops + 1),
            Some("https") => curl(&next, limit),
            _ => None,
        };
    }
    if !(200..300).contains(&code) {
        return None;
    }
    let mut body = Vec::new();
    if header("transfer-encoding").map_or(false, |t| t.to_ascii_lowercase().contains("chunked")) {
        loop {
            let mut size_line = String::new();
            reader.read_line(&mut size_line).ok()?;
            let size =
                usize::from_str_radix(size_line.trim().split(';').next()?.trim(), 16).ok()?;
            if size == 0 {
                break;
            }
            let mut chunk = vec![0u8; size];
            reader.read_exact(&mut chunk).ok()?;
            body.extend_from_slice(&chunk);
            let mut crlf = String::new();
            reader.read_line(&mut crlf).ok()?;
            if body.len() >= limit {
                break;
            }
        }
    } else if let Some(n) = header("content-length").and_then(|n| n.parse::<usize>().ok()) {
        let mut taken = reader.take(n.min(limit) as u64);
        taken.read_to_end(&mut body).ok()?;
    } else {
        let mut taken = reader.take(limit as u64);
        taken.read_to_end(&mut body).ok()?;
    }
    body.truncate(limit);
    Some(body)
}

// --- The server rehearse.py runs ------------------------------------------------

/// One request, as BaseHTTPRequestHandler parsed it.
pub struct Request {
    pub command: String,
    pub path: String,
    pub requestline: String,
    pub headers: Vec<(String, String)>,
}

impl Request {
    /// `self.headers.get(name)`: the first, matched without case.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

/// A response the handler writes.
pub struct Response {
    pub code: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

const ERROR_PAGE: &str = "<!DOCTYPE HTML>\n<html lang=\"en\">\n    <head>\n        <meta charset=\"utf-8\">\n        <title>Error response</title>\n    </head>\n    <body>\n        <h1>Error response</h1>\n        <p>Error code: %CODE%</p>\n        <p>Message: %MESSAGE%.</p>\n        <p>Error code explanation: %CODE% - %EXPLAIN%.</p>\n    </body>\n</html>\n";

fn reason(code: u16) -> (&'static str, &'static str) {
    match code {
        200 => ("OK", "Request fulfilled, document follows"),
        304 => ("Not Modified", "Document has not changed since given time"),
        400 => ("Bad Request", "Bad request syntax or unsupported method"),
        404 => ("Not Found", "Nothing matches the given URI"),
        501 => ("Not Implemented", "Server does not support this operation"),
        505 => ("HTTP Version Not Supported", "Cannot fulfill request."),
        _ => ("", ""),
    }
}

fn html_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn http_date() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let days = secs.div_euclid(86400);
    let weekday = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"][days.rem_euclid(7) as usize];
    let stamp = crate::timefmt::format(secs); // YYYY-MM-DDTHH:MM:SSZ
    let (y, m, d) = (&stamp[0..4], &stamp[5..7], &stamp[8..10]);
    let month = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ][m.parse::<usize>().unwrap_or(1) - 1];
    format!("{}, {} {} {} {} GMT", weekday, d, month, y, &stamp[11..19])
}

/// `send_error(code, message)`'s response.
pub fn error_response(code: u16, message: Option<&str>) -> Response {
    let (short, explain) = reason(code);
    let message = message.unwrap_or(short);
    let body = ERROR_PAGE
        .replace("%CODE%", &code.to_string())
        .replace("%MESSAGE%", &html_escape(message))
        .replace("%EXPLAIN%", &html_escape(explain))
        .into_bytes();
    Response {
        code,
        headers: vec![
            ("Connection".into(), "close".into()),
            ("Content-Type".into(), "text/html;charset=utf-8".into()),
            ("Content-Length".into(), body.len().to_string()),
        ],
        body,
    }
}

/// Serves `handle` on `listener`, one thread a connection, one request a
/// connection (HTTP/1.0, as BaseHTTPRequestHandler answers by default).
/// `log` gets each line BaseHTTPRequestHandler would log.
pub fn serve<H, L>(listener: TcpListener, handle: H, log: L)
where
    H: Fn(&Request) -> Response + Send + Sync + 'static,
    L: Fn(String) + Send + Sync + 'static,
{
    let handle = std::sync::Arc::new(handle);
    let log = std::sync::Arc::new(log);
    for stream in listener.incoming().flatten() {
        let handle = handle.clone();
        let log = log.clone();
        std::thread::spawn(move || {
            let _ = one(stream, &*handle, &*log);
        });
    }
}

fn one(
    stream: TcpStream,
    handle: &dyn Fn(&Request) -> Response,
    log: &dyn Fn(String),
) -> std::io::Result<()> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut raw = Vec::new();
    reader.by_ref().take(65537).read_until(b'\n', &mut raw)?;
    let line = String::from_utf8_lossy(&raw).into_owned();
    let requestline = line.trim_end_matches(['\r', '\n']).to_string();
    let words: Vec<&str> = requestline.split_whitespace().collect();
    if words.is_empty() {
        return Ok(());
    }
    let mut out = stream;
    let send = |out: &mut TcpStream,
                req_line: &str,
                r: Response,
                error: Option<&str>|
     -> std::io::Result<()> {
        let (short, _) = reason(r.code);
        if let Some(msg) = error {
            log(format!("code {}, message {}", r.code, msg));
        }
        log(format!("\"{}\" {} -", req_line, r.code));
        let mut head = format!(
            "HTTP/1.0 {} {}\r\nServer: BaseHTTP/0.6 Rust\r\nDate: {}\r\n",
            r.code,
            error.unwrap_or(short),
            http_date()
        );
        for (k, v) in &r.headers {
            head.push_str(&format!("{}: {}\r\n", k, v));
        }
        head.push_str("\r\n");
        out.write_all(head.as_bytes())?;
        out.write_all(&r.body)?;
        out.flush()
    };
    if !(2..=3).contains(&words.len()) {
        let msg = format!(
            "Bad request syntax ({})",
            crate::pystr::repr_str(&requestline)
        );
        return send(
            &mut out,
            &requestline,
            error_response(400, Some(&msg)),
            Some(&msg),
        );
    }
    let mut headers = Vec::new();
    loop {
        let mut h = String::new();
        if reader.read_line(&mut h)? == 0 {
            break;
        }
        let h = h.trim_end_matches(['\r', '\n']);
        if h.is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            headers.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    let mut path = words[1].to_string();
    if path.starts_with("//") {
        path = format!("/{}", path.trim_start_matches('/'));
    }
    let request = Request {
        command: words[0].to_string(),
        path,
        requestline: requestline.clone(),
        headers,
    };
    if request.command != "GET" {
        let msg = format!(
            "Unsupported method ({})",
            crate::pystr::repr_str(&request.command)
        );
        return send(
            &mut out,
            &requestline,
            error_response(501, Some(&msg)),
            Some(&msg),
        );
    }
    let response = handle(&request);
    let error = if response.code == 404 {
        Some("Not Found")
    } else {
        None
    };
    send(&mut out, &requestline, response, error)
}
