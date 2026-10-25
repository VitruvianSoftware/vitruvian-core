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

//! `urllib.request.urlopen` for what merge_queue_stats.py asks of it: one
//! request, a JSON body or none, the response body back. `http://` URLs (a
//! GitHub Enterprise or test server in GITHUB_API_URL) go over a plain
//! socket; `https://` goes through curl, since the standard library has no
//! TLS. Errors read as urllib's do: `HTTP Error 404: Not Found` for a status
//! that is not 2xx, `<urlopen error ...>` for a connection that fails.
//! Redirects are not followed.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::process::{Command, Stdio};
use std::time::Duration;

/// Why a request failed: `Url` is urllib.error.URLError (HTTPError
/// included), which the script catches; `Value` is the ValueError urllib
/// raises for a URL it cannot use, which it does not.
#[derive(Debug, PartialEq)]
pub enum Error {
    Url(String),
    Value(String),
    /// An exception http.client raises before it sends: (class, message).
    Invalid(&'static str, String),
}

pub struct Request<'a> {
    pub method: &'a str,
    pub url: &'a str,
    pub headers: &'a [(&'a str, String)],
    pub body: Option<&'a [u8]>,
    pub timeout: u64,
}

pub fn send(req: &Request) -> Result<Vec<u8>, Error> {
    // urllib drops a #fragment; http.client then refuses a path with a
    // space or control character, and one that is not ASCII.
    let url = req.url.split('#').next().unwrap_or("");
    if url.chars().any(|c| (c as u32) <= 0x20 || c == '\u{7f}') {
        return Err(Error::Invalid(
            "http.client.InvalidURL",
            format!(
                "URL can't contain control characters. {}",
                crate::pystr::repr_str(url)
            ),
        ));
    }
    if !url.is_ascii() {
        return Err(Error::Invalid(
            "UnicodeEncodeError",
            "'ascii' codec can't encode characters in the request line".into(),
        ));
    }
    if req
        .headers
        .iter()
        .any(|(_, v)| v.chars().any(|c| (c as u32) > 0xFF))
    {
        return Err(Error::Invalid(
            "UnicodeEncodeError",
            "'latin-1' codec can't encode characters in a header".into(),
        ));
    }
    let req = Request { url, ..*req };
    let req = &req;
    if let Some(rest) = req.url.strip_prefix("http://") {
        plain(req, rest)
    } else if req.url.starts_with("https://") {
        curl(req)
    } else {
        Err(Error::Value(format!(
            "unknown url type: {}",
            crate::pystr::repr_str(req.url)
        )))
    }
}

fn os_error(e: &std::io::Error) -> String {
    let text = e.to_string();
    let text = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    match e.raw_os_error() {
        Some(code) => format!("<urlopen error [Errno {}] {}>", code, text),
        None => format!("<urlopen error {}>", text),
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
    if authority.is_empty() {
        return Err(Error::Url("<urlopen error no host given>".into()));
    }
    let hostport = if authority.contains(':') {
        authority.to_string()
    } else {
        format!("{}:80", authority)
    };
    let timeout = Duration::from_secs(req.timeout);
    let addrs: Vec<_> = hostport
        .to_socket_addrs()
        .map_err(|e| Error::Url(os_error(&e)))?
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
            return Err(Error::Url(os_error(&e)));
        }
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let mut head = format!("{} {} HTTP/1.1\r\n", req.method, path);
    head.push_str("Accept-Encoding: identity\r\n");
    head.push_str(&format!("Host: {}\r\n", authority));
    head.push_str("User-Agent: merge-queue-stats-rs\r\n");
    head.push_str("Connection: close\r\n");
    if let Some(body) = req.body {
        head.push_str("Content-Type: application/x-www-form-urlencoded\r\n");
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
        .map_err(|e| Error::Url(os_error(&e)))?;

    let mut raw = Vec::new();
    stream
        .read_to_end(&mut raw)
        .map_err(|e| Error::Url(os_error(&e)))?;
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| {
            Error::Url("<urlopen error Remote end closed connection without response>".into())
        })?;
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let mut body = raw[split + 4..].to_vec();
    let mut lines = head.split("\r\n");
    let status = lines.next().unwrap_or("");
    let mut parts = status.splitn(3, ' ');
    let _version = parts.next();
    let code: u16 = parts
        .next()
        .and_then(|c| c.parse().ok())
        .ok_or_else(|| Error::Url(format!("<urlopen error bad status line {:?}>", status)))?;
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
    if !(200..300).contains(&code) {
        return Err(Error::Url(format!("HTTP Error {}: {}", code, reason)));
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
    const MARK: &[u8] = b"\n__merge_queue_stats_status__";
    // Everything goes in a config on stdin, so the token stays out of `ps`.
    let mut config = String::new();
    config.push_str(&format!("url = {}\n", quote(req.url)));
    config.push_str(&format!("request = {}\n", quote(req.method)));
    config.push_str(&format!("max-time = {}\n", req.timeout));
    for (k, v) in req.headers {
        config.push_str(&format!("header = {}\n", quote(&format!("{}: {}", k, v))));
    }
    if let Some(body) = req.body {
        config.push_str("header = \"Content-Type: application/x-www-form-urlencoded\"\n");
        config.push_str(&format!(
            "data-binary = {}\n",
            quote(&String::from_utf8_lossy(body))
        ));
    }
    config.push_str("write-out = \"\\n__merge_queue_stats_status__%{http_code}\"\n");
    let mut child = Command::new("curl")
        .args(["-sS", "-K", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Error::Url(os_error(&e)))?;
    {
        let mut stdin = child.stdin.take().unwrap();
        let _ = stdin.write_all(config.as_bytes());
    }
    let out = child
        .wait_with_output()
        .map_err(|e| Error::Url(os_error(&e)))?;
    let pos = out.stdout.windows(MARK.len()).rposition(|w| w == MARK);
    let pos = match (out.status.success(), pos) {
        (true, Some(p)) => p,
        _ => {
            let msg = String::from_utf8_lossy(&out.stderr).trim().to_string();
            return Err(Error::Url(format!("<urlopen error {}>", msg)));
        }
    };
    let code: u16 = String::from_utf8_lossy(&out.stdout[pos + MARK.len()..])
        .trim()
        .parse()
        .unwrap_or(0);
    if !(200..300).contains(&code) {
        return Err(Error::Url(format!("HTTP Error {}: {}", code, reason(code))));
    }
    Ok(out.stdout[..pos].to_vec())
}

/// The standard reason phrase: curl does not pass the server's on.
fn reason(code: u16) -> &'static str {
    match code {
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;

    fn serve(response: &'static [u8]) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut buf = [0u8; 4096];
            let _ = s.read(&mut buf);
            s.write_all(response).unwrap();
        });
        format!("http://{}/x?y=1", addr)
    }

    fn get(url: &str) -> Result<Vec<u8>, Error> {
        send(&Request {
            method: "GET",
            url,
            headers: &[],
            body: None,
            timeout: 5,
        })
    }

    #[test]
    fn reads_length_and_chunked_bodies() {
        let url = serve(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n[]extra");
        assert_eq!(get(&url).unwrap(), b"[]");
        let url = serve(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n[1\r\n1\r\n]\r\n0\r\n\r\n",
        );
        assert_eq!(get(&url).unwrap(), b"[1]");
    }

    #[test]
    fn errors_read_as_urllib_words_them() {
        let url = serve(b"HTTP/1.0 502 Bad Gateway\r\n\r\n");
        assert_eq!(
            get(&url),
            Err(Error::Url("HTTP Error 502: Bad Gateway".into()))
        );
        assert!(matches!(get("ftp://x"), Err(Error::Value(_))));
        // Nothing listens on port 9 here; the error names the errno.
        match get("http://127.0.0.1:9/") {
            Err(Error::Url(m)) => assert!(m.starts_with("<urlopen error [Errno "), "{}", m),
            other => panic!("{:?}", other),
        }
    }
}
