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

//! `urllib.request.urlopen` for what rotate_access_token.py asks of it: one
//! request with the caller's headers and an optional body, the response body
//! back. `http://` URLs (a test server in PULUMI_API) go over a plain
//! socket; `https://` goes through curl, since the standard library has no
//! TLS. Failures come back sorted the way urllib raises them: an HTTPError
//! with its status, a URLError with its reason, or an exception urllib or
//! http.client raises before anything is sent. Redirects are not followed.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::process::{Command, Stdio};
use std::time::Duration;

#[derive(Debug, PartialEq)]
pub enum Error {
    /// urllib.error.HTTPError: a status that is not 2xx.
    Http(u16),
    /// urllib.error.URLError, as `str(e.reason)`.
    Url(String),
    /// An exception raised before the request goes out: (class, message).
    /// The script catches none of these.
    Invalid(&'static str, String),
}

pub struct Request<'a> {
    pub method: &'a str,
    pub url: &'a str,
    pub headers: &'a [(&'a str, String)],
    pub body: Option<&'a [u8]>,
    pub timeout: u64,
}

/// `urllib.parse._splittype`: the scheme before the first ':' when nothing
/// before it is '/' or ':'.
fn scheme(url: &str) -> Option<&str> {
    let i = url.find(':')?;
    let s = &url[..i];
    if s.is_empty() || s.contains('/') {
        None
    } else {
        Some(s)
    }
}

/// http.client's `_is_illegal_header_value`: a line break not followed by
/// folding whitespace.
fn illegal_header_value(v: &str) -> bool {
    let c: Vec<char> = v.chars().collect();
    c.iter().enumerate().any(|(i, ch)| match ch {
        '\n' => !matches!(c.get(i + 1), Some(' ' | '\t')),
        '\r' => !matches!(c.get(i + 1), Some(' ' | '\t' | '\n')),
        _ => false,
    })
}

pub fn send(req: &Request) -> Result<Vec<u8>, Error> {
    // Request() refuses a URL with no scheme; the opener then has no handler
    // for a scheme other than http(s) (this port does not do ftp:, file: or
    // data:).
    let kind = match scheme(req.url) {
        None => {
            return Err(Error::Invalid(
                "ValueError",
                format!("unknown url type: {}", crate::pystr::repr_str(req.url)),
            ))
        }
        Some(k) => k.to_ascii_lowercase(),
    };
    if kind != "http" && kind != "https" {
        return Err(Error::Url(format!("unknown url type: {}", kind)));
    }
    // urllib drops a #fragment; http.client then refuses a path with a
    // space or control character, and one that is not ASCII.
    let url = req.url.split('#').next().unwrap_or("");
    let rest = &url[kind.len() + 1..];
    let rest = match rest.strip_prefix("//") {
        Some(r) => r,
        None => return Err(Error::Url("no host given".into())),
    };
    let host_end = rest.find(['/', '?']).unwrap_or(rest.len());
    if host_end == 0 {
        return Err(Error::Url("no host given".into()));
    }
    if url.chars().any(|c| (c as u32) <= 0x20 || c == '\u{7f}') {
        return Err(Error::Invalid(
            "http.client.InvalidURL",
            format!(
                "URL can't contain control characters. {}",
                crate::pystr::repr_str(&rest[host_end..])
            ),
        ));
    }
    if !url.is_ascii() {
        return Err(Error::Invalid(
            "UnicodeEncodeError",
            "'ascii' codec can't encode characters in the request line".into(),
        ));
    }
    for (k, v) in req.headers {
        if v.chars().any(|c| (c as u32) > 0xFF) {
            return Err(Error::Invalid(
                "UnicodeEncodeError",
                "'latin-1' codec can't encode characters in a header".into(),
            ));
        }
        if illegal_header_value(v) {
            return Err(Error::Invalid(
                "ValueError",
                format!(
                    "Invalid header value b{} for {}",
                    crate::pystr::repr_str(v),
                    k
                ),
            ));
        }
    }
    let req = Request { url, ..*req };
    if kind == "http" {
        plain(&req, rest)
    } else {
        curl(&req)
    }
}

/// `str(OSError)`: `[Errno N] text`.
fn os_reason(e: &std::io::Error) -> String {
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

fn plain(req: &Request, rest: &str) -> Result<Vec<u8>, Error> {
    let (authority, path) = match rest.find(['/', '?']) {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };
    let path = if path.starts_with('?') {
        format!("/{}", path)
    } else {
        path.to_string()
    };
    let hostport = if authority.contains(':') {
        authority.to_string()
    } else {
        format!("{}:80", authority)
    };
    let timeout = Duration::from_secs(req.timeout);
    let addrs: Vec<_> = hostport
        .to_socket_addrs()
        .map_err(|e| Error::Url(os_reason(&e)))?
        .collect();
    let mut last = None;
    let mut stream = None;
    for a in addrs {
        match TcpStream::connect_timeout(&a, timeout) {
            Ok(s) => {
                stream = Some(s);
                break;
            }
            Err(e) => last = Some(e),
        }
    }
    let mut stream = match stream {
        Some(s) => s,
        None => {
            let e = last
                .unwrap_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "no address"));
            return Err(Error::Url(os_reason(&e)));
        }
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let mut head = format!("{} {} HTTP/1.1\r\n", req.method, path);
    head.push_str("Accept-Encoding: identity\r\n");
    head.push_str(&format!("Host: {}\r\n", authority));
    head.push_str("User-Agent: rotate-access-token-rs\r\n");
    head.push_str("Connection: close\r\n");
    if let Some(body) = req.body {
        head.push_str(&format!("Content-Length: {}\r\n", body.len()));
    }
    let mut wire = head.into_bytes();
    // Header values go out as latin-1, as http.client encodes them.
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
    stream
        .write_all(&wire)
        .map_err(|e| Error::Url(os_reason(&e)))?;

    let mut raw = Vec::new();
    stream
        .read_to_end(&mut raw)
        .map_err(|e| Error::Url(os_reason(&e)))?;
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| Error::Url("Remote end closed connection without response".into()))?;
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let mut body = raw[split + 4..].to_vec();
    let mut lines = head.split("\r\n");
    let status = lines.next().unwrap_or("");
    let code: u16 = status
        .split(' ')
        .nth(1)
        .and_then(|c| c.parse().ok())
        .ok_or_else(|| Error::Url(format!("bad status line {:?}", status)))?;
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
    if !(200..300).contains(&code) {
        return Err(Error::Http(code));
    }
    Ok(body)
}

fn dechunk(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < data.len() {
        let line_end = match data[i..].windows(2).position(|w| w == b"\r\n") {
            Some(p) => i + p,
            None => break,
        };
        let size_text = String::from_utf8_lossy(&data[i..line_end]);
        let size_text = size_text.split(';').next().unwrap_or("").trim();
        let size = usize::from_str_radix(size_text, 16).unwrap_or(0);
        i = line_end + 2;
        if size == 0 {
            break;
        }
        let end = (i + size).min(data.len());
        out.extend_from_slice(&data[i..end]);
        i = end + 2;
    }
    out
}

/// A string for a curl config file: quoted, with \ and " escaped.
fn quote(s: &str) -> String {
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

fn curl(req: &Request) -> Result<Vec<u8>, Error> {
    const MARK: &[u8] = b"\n__rotate_access_token_status__";
    // Everything goes in a config on stdin, so the token stays out of `ps`.
    let mut config = String::new();
    config.push_str(&format!("url = {}\n", quote(req.url)));
    config.push_str(&format!("request = {}\n", quote(req.method)));
    config.push_str(&format!("max-time = {}\n", req.timeout));
    for (k, v) in req.headers {
        config.push_str(&format!("header = {}\n", quote(&format!("{}: {}", k, v))));
    }
    if let Some(body) = req.body {
        config.push_str(&format!(
            "data-binary = {}\n",
            quote(&String::from_utf8_lossy(body))
        ));
    }
    config.push_str("write-out = \"\\n__rotate_access_token_status__%{http_code}\"\n");
    let mut child = Command::new("curl")
        .args(["-sS", "-K", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Error::Url(os_reason(&e)))?;
    {
        let mut stdin = child.stdin.take().unwrap();
        let _ = stdin.write_all(config.as_bytes());
    }
    let out = child
        .wait_with_output()
        .map_err(|e| Error::Url(os_reason(&e)))?;
    let pos = out.stdout.windows(MARK.len()).rposition(|w| w == MARK);
    let pos = match (out.status.success(), pos) {
        (true, Some(p)) => p,
        _ => {
            return Err(Error::Url(
                String::from_utf8_lossy(&out.stderr).trim().to_string(),
            ))
        }
    };
    let code: u16 = String::from_utf8_lossy(&out.stdout[pos + MARK.len()..])
        .trim()
        .parse()
        .unwrap_or(0);
    if !(200..300).contains(&code) {
        return Err(Error::Http(code));
    }
    Ok(out.stdout[..pos].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::sync::mpsc;
    use std::thread;

    /// One response, and the request that got it.
    fn serve(response: &'static [u8]) -> (String, mpsc::Receiver<Vec<u8>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut buf = [0u8; 4096];
            let n = s.read(&mut buf).unwrap_or(0);
            let _ = tx.send(buf[..n].to_vec());
            s.write_all(response).unwrap();
        });
        (format!("http://{}/x?y=1", addr), rx)
    }

    fn call(method: &str, url: &str, body: Option<&[u8]>) -> Result<Vec<u8>, Error> {
        let headers = [("Content-Type", "application/json".to_string())];
        send(&Request {
            method,
            url,
            headers: &headers,
            body,
            timeout: 5,
        })
    }

    #[test]
    fn reads_length_and_chunked_bodies() {
        let (url, _) = serve(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n{}extra");
        assert_eq!(call("GET", &url, None).unwrap(), b"{}");
        let (url, _) = serve(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n[1\r\n1\r\n]\r\n0\r\n\r\n",
        );
        assert_eq!(call("GET", &url, None).unwrap(), b"[1]");
    }

    #[test]
    fn sends_the_body_with_its_length_and_the_callers_content_type() {
        let (url, rx) = serve(b"HTTP/1.0 204 No Content\r\n\r\n");
        assert_eq!(call("POST", &url, Some(b"{\"a\": 1}")).unwrap(), b"");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.starts_with("POST /x?y=1 HTTP/1.1\r\n"), "{}", sent);
        assert!(sent.contains("Content-Length: 8\r\n"), "{}", sent);
        assert!(
            sent.contains("Content-Type: application/json\r\n"),
            "{}",
            sent
        );
        assert!(!sent.contains("x-www-form-urlencoded"), "{}", sent);
        assert!(sent.ends_with("\r\n\r\n{\"a\": 1}"), "{}", sent);
    }

    #[test]
    fn failures_are_sorted_as_urllib_raises_them() {
        let (url, _) = serve(b"HTTP/1.0 401 Unauthorized\r\n\r\n");
        assert_eq!(call("GET", &url, None), Err(Error::Http(401)));
        assert!(matches!(
            call("GET", "api.example/x", None),
            Err(Error::Invalid("ValueError", _))
        ));
        assert_eq!(
            call("GET", "Gopher://x", None),
            Err(Error::Url("unknown url type: gopher".into()))
        );
        assert_eq!(
            call("GET", "http:///x", None),
            Err(Error::Url("no host given".into()))
        );
        // Nothing listens on port 1 here; the reason names the errno.
        match call("GET", "http://127.0.0.1:1/", None) {
            Err(Error::Url(m)) => assert!(m.starts_with("[Errno "), "{}", m),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn header_values_are_checked_as_http_client_checks_them() {
        assert!(illegal_header_value("a\nb"));
        assert!(illegal_header_value("a\r"));
        assert!(!illegal_header_value("a\r\n b"));
        assert!(!illegal_header_value("token abc"));
        let headers = [("Authorization", "token a\nb".to_string())];
        let r = send(&Request {
            method: "GET",
            url: "http://127.0.0.1:1/",
            headers: &headers,
            body: None,
            timeout: 1,
        });
        assert!(matches!(r, Err(Error::Invalid("ValueError", _))));
    }
}
