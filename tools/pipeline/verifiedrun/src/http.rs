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

//! One HTTP POST, for the commit status. `http://` (a test server) goes over
//! a plain socket; `https://` through curl, since the standard library has
//! no TLS. The token reaches curl through its config on stdin, never argv.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::process::{Command, Stdio};
use std::time::Duration;

/// A response: status and body.
pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
}

/// POSTs `body` to `url`. Err is why it could not be reached, as the text
/// after Go's `Post "<url>": `.
pub fn post(
    url: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: Duration,
) -> Result<Response, String> {
    if let Some(rest) = url.strip_prefix("http://") {
        plain(rest, headers, body, timeout)
    } else if url.starts_with("https://") {
        curl(url, headers, body, timeout)
    } else {
        Err(format!(
            "unsupported protocol scheme {}",
            unitfile::gocompat::quote::quote(url.split(':').next().unwrap_or(""))
        ))
    }
}

fn plain(
    rest: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: Duration,
) -> Result<Response, String> {
    let (authority, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };
    let hostport = if authority.contains(':') {
        authority.to_string()
    } else {
        format!("{authority}:80")
    };
    let addr = hostport
        .to_socket_addrs()
        .map_err(|e| format!("dial tcp: {e}"))?
        .next()
        .ok_or_else(|| "dial tcp: no address".to_string())?;
    let mut s = TcpStream::connect_timeout(&addr, timeout).map_err(|e| {
        format!(
            "dial tcp {addr}: connect: {}",
            unitfile::gocompat::oserr::errno_text(&e)
        )
    })?;
    let _ = s.set_read_timeout(Some(timeout));
    let _ = s.set_write_timeout(Some(timeout));
    let mut wire = format!(
        "POST {path} HTTP/1.1\r\nHost: {authority}\r\nUser-Agent: verified-run\r\nContent-Length: {}\r\nConnection: close\r\n",
        body.len()
    );
    for (k, v) in headers {
        wire.push_str(&format!("{k}: {v}\r\n"));
    }
    wire.push_str("\r\n");
    let mut bytes = wire.into_bytes();
    bytes.extend_from_slice(body);
    s.write_all(&bytes).map_err(|e| e.to_string())?;
    let mut raw = Vec::new();
    s.read_to_end(&mut raw).map_err(|e| e.to_string())?;
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| "malformed HTTP response".to_string())?;
    let head = String::from_utf8_lossy(&raw[..split]).into_owned();
    let mut lines = head.split("\r\n");
    let status: u16 = lines
        .next()
        .and_then(|l| l.split(' ').nth(1))
        .and_then(|c| c.parse().ok())
        .ok_or_else(|| "malformed HTTP status line".to_string())?;
    let mut body = raw[split + 4..].to_vec();
    let mut chunked = false;
    let mut length = None;
    for l in lines {
        if let Some((k, v)) = l.split_once(':') {
            let (k, v) = (k.trim().to_ascii_lowercase(), v.trim());
            if k == "transfer-encoding" && v.to_ascii_lowercase().contains("chunked") {
                chunked = true;
            } else if k == "content-length" {
                length = v.parse::<usize>().ok();
            }
        }
    }
    if chunked {
        body = dechunk(&body);
    } else if let Some(n) = length {
        body.truncate(n);
    }
    Ok(Response { status, body })
}

fn dechunk(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < data.len() {
        let Some(p) = data[i..].windows(2).position(|w| w == b"\r\n") else {
            break;
        };
        let size_text = String::from_utf8_lossy(&data[i..i + p]).into_owned();
        let size = usize::from_str_radix(size_text.split(';').next().unwrap_or("").trim(), 16)
            .unwrap_or(0);
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

fn config_quote(s: &str) -> String {
    let mut out = String::from("\"");
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

const STATUS_MARK: &str = "\n__verified_run_status__:";

fn curl(
    url: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: Duration,
) -> Result<Response, String> {
    let mut cfg = String::new();
    cfg.push_str(&format!("url = {}\n", config_quote(url)));
    cfg.push_str("request = \"POST\"\n");
    for (k, v) in headers {
        cfg.push_str(&format!(
            "header = {}\n",
            config_quote(&format!("{k}: {v}"))
        ));
    }
    cfg.push_str(&format!(
        "data-binary = {}\n",
        config_quote(&String::from_utf8_lossy(body))
    ));
    cfg.push_str(&format!("max-time = {}\n", timeout.as_secs()));
    cfg.push_str(&format!(
        "write-out = {}\n",
        config_quote(&format!("{STATUS_MARK}%{{http_code}}"))
    ));
    let mut child = Command::new("curl")
        .args(["--silent", "--show-error", "--config", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(cfg.as_bytes());
    }
    let out = child.wait_with_output().map_err(|e| format!("curl: {e}"))?;
    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).trim().to_string());
    }
    let raw = out.stdout;
    let mark = STATUS_MARK.as_bytes();
    let at = raw
        .windows(mark.len())
        .rposition(|w| w == mark)
        .ok_or_else(|| "curl gave no status".to_string())?;
    let status: u16 = String::from_utf8_lossy(&raw[at + mark.len()..])
        .trim()
        .parse()
        .map_err(|_| "curl gave no status".to_string())?;
    Ok(Response {
        status,
        body: raw[..at].to_vec(),
    })
}
