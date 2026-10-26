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

//! `urllib.request.urlopen` for the GETs permission_drift.py makes, failing
//! the way it fails. `http://` (GITHUB_API_URL pointing at a test server or
//! an Enterprise host) goes over a plain socket; `https://` goes through
//! curl, since the standard library has no TLS. Redirects are followed by
//! urllib's rules, here, for both, so its loop limits hold.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::pyerr::Crash;
use crate::pystr;

pub struct Response {
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Response {
    /// `response.headers.get(name)`: the first header of that name.
    pub fn header(&self, name: &str) -> Option<&str> {
        header(&self.headers, name)
    }
}

fn header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(name))
        .map(|(_, v)| v.as_str())
}

#[derive(Debug, PartialEq)]
pub enum Error {
    /// urllib.error.HTTPError: the status, and the body for `err.read()`.
    Http { code: u16, body: Vec<u8> },
    /// A URLError's reason, or an OSError, as `str()` gives it.
    Os(String),
    /// An exception the script does not catch.
    Crash(Crash),
}

struct Raw {
    status: u16,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

/// GET `url` with these headers, following redirects as urllib does.
pub fn get(url: &str, headers: &[(&str, String)], timeout: u64) -> Result<Response, Error> {
    let mut url = url.split('#').next().unwrap_or("").to_string();
    // urllib.request.Request: a URL needs a scheme.
    if scheme(&url).is_none() {
        return Err(Error::Crash(Crash::new(
            "ValueError",
            format!("unknown url type: {}", pystr::repr_str(&url)),
        )));
    }
    // HTTPRedirectHandler's loop guard: made on the first redirect, checked
    // from the second.
    let mut visited: Option<Vec<(String, u32)>> = None;
    loop {
        let raw = match scheme(&url).as_deref() {
            Some("http") => plain(&url, headers, timeout)?,
            Some("https") => curl(&url, headers, timeout)?,
            Some(other) => return Err(Error::Os(format!("unknown url type: {}", other))),
            None => unreachable!("checked above and by redirect_target"),
        };
        if (200..300).contains(&raw.status) {
            return Ok(Response {
                headers: raw.headers,
                body: raw.body,
            });
        }
        let location = header(&raw.headers, "location").or_else(|| header(&raw.headers, "uri"));
        let location = match (raw.status, location) {
            (301 | 302 | 303 | 307 | 308, Some(l)) => l.to_string(),
            _ => {
                return Err(Error::Http {
                    code: raw.status,
                    body: raw.body,
                })
            }
        };
        let next = match redirect_target(&url, &location)? {
            Some(n) => n,
            None => {
                return Err(Error::Http {
                    code: raw.status,
                    body: raw.body,
                })
            }
        };
        match visited.as_mut() {
            None => visited = Some(Vec::new()),
            Some(v) => {
                let seen = v.iter().find(|(u, _)| *u == next).map_or(0, |(_, n)| *n);
                if seen >= 4 || v.len() >= 10 {
                    return Err(Error::Http {
                        code: raw.status,
                        body: raw.body,
                    });
                }
            }
        }
        let v = visited.as_mut().unwrap();
        match v.iter_mut().find(|(u, _)| *u == next) {
            Some(slot) => slot.1 += 1,
            None => v.push((next.clone(), 1)),
        }
        url = next;
    }
}

/// urllib's `_splittype`: the scheme, lower-cased, if the URL has one.
fn scheme(url: &str) -> Option<String> {
    let end = url.find(|c| c == ':' || c == '/')?;
    if end == 0 || !url[end..].starts_with(':') {
        return None;
    }
    Some(url[..end].to_lowercase())
}

/// Where a redirect goes: None for a scheme urllib will not follow (it
/// then reports the redirect's own status), else the absolute URL.
fn redirect_target(base: &str, location: &str) -> Result<Option<String>, Error> {
    let loc_scheme = match location.find(|c| c == ':' || c == '/' || c == '?' || c == '#') {
        Some(i) if i > 0 && location[i..].starts_with(':') => {
            let s = &location[..i];
            if s.chars().next().unwrap().is_ascii_alphabetic()
                && s.chars()
                    .all(|c| c.is_ascii_alphanumeric() || "+-.".contains(c))
            {
                s.to_lowercase()
            } else {
                String::new()
            }
        }
        _ => String::new(),
    };
    if !["http", "https", "ftp", ""].contains(&loc_scheme.as_str()) {
        return Ok(None);
    }
    let quoted = quote(location)?;
    // urljoin(base, quoted), for the shapes a Location takes.
    let joined = if !loc_scheme.is_empty() {
        let rest = &quoted[loc_scheme.len() + 1..];
        if rest.starts_with("//") {
            let after = &rest[2..];
            if after.find(['/', '?', '#']).is_none() {
                format!("{}/", quoted)
            } else {
                quoted
            }
        } else {
            quoted
        }
    } else {
        let base_scheme = scheme(base).unwrap_or_default();
        let after = &base[base_scheme.len() + 1..];
        let (authority, path) = match after.strip_prefix("//") {
            Some(a) => match a.find(['/', '?']) {
                Some(i) => (format!("//{}", &a[..i]), a[i..].to_string()),
                None => (format!("//{}", a), String::new()),
            },
            None => (String::new(), after.to_string()),
        };
        if let Some(net) = quoted.strip_prefix("//") {
            format!("{}://{}", base_scheme, net)
        } else if quoted.starts_with('/') {
            format!("{}:{}{}", base_scheme, authority, quoted)
        } else if quoted.starts_with('?') {
            let p = path.split('?').next().unwrap_or("");
            format!("{}:{}{}{}", base_scheme, authority, p, quoted)
        } else {
            let p = path.split('?').next().unwrap_or("");
            let dir = match p.rfind('/') {
                Some(i) => &p[..=i],
                None => "/",
            };
            format!("{}:{}{}{}", base_scheme, authority, dir, quoted)
        }
    };
    Ok(Some(joined))
}

/// `quote(url, encoding="iso-8859-1", safe=string.punctuation)`.
fn quote(s: &str) -> Result<String, Error> {
    let mut out = String::new();
    for c in s.chars() {
        let cp = c as u32;
        if c.is_ascii_alphanumeric() || (c.is_ascii_punctuation()) {
            out.push(c);
        } else if cp <= 0xFF {
            out.push_str(&format!("%{:02X}", cp));
        } else {
            return Err(Error::Crash(Crash::new(
                "UnicodeEncodeError",
                "'latin-1' codec can't encode characters in the redirect URL",
            )));
        }
    }
    Ok(out)
}

/// str(OSError): `[Errno N] text`, or the text alone.
fn os_error(e: &std::io::Error) -> String {
    if e.kind() == std::io::ErrorKind::TimedOut || e.kind() == std::io::ErrorKind::WouldBlock {
        return "timed out".into();
    }
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

/// What http.client refuses before it sends: a path with a space or a
/// control character, a path that is not ASCII, a header value that is not
/// latin-1 or that would end the header early.
fn validate(path: &str, headers: &[(&str, String)]) -> Result<(), Error> {
    if path.chars().any(|c| (c as u32) <= 0x20 || c == '\u{7f}') {
        return Err(Error::Crash(Crash::new(
            "http.client.InvalidURL",
            format!(
                "URL can't contain control characters. {}",
                pystr::repr_str(path)
            ),
        )));
    }
    if !path.is_ascii() {
        return Err(Error::Crash(Crash::new(
            "UnicodeEncodeError",
            "'ascii' codec can't encode characters in the request line",
        )));
    }
    for (_, v) in headers {
        if v.chars().any(|c| (c as u32) > 0xFF) {
            return Err(Error::Crash(Crash::new(
                "UnicodeEncodeError",
                "'latin-1' codec can't encode characters in a header",
            )));
        }
        let b: Vec<char> = v.chars().collect();
        let illegal = b.iter().enumerate().any(|(i, c)| match c {
            '\n' => !matches!(b.get(i + 1), Some(' ' | '\t')),
            '\r' => !matches!(b.get(i + 1), Some(' ' | '\t' | '\n')),
            _ => false,
        });
        if illegal {
            return Err(Error::Crash(Crash::new(
                "ValueError",
                "Invalid header value",
            )));
        }
    }
    Ok(())
}

fn plain(url: &str, headers: &[(&str, String)], timeout: u64) -> Result<Raw, Error> {
    let rest = &url["http:".len()..];
    // _splithost: `//host` then the selector.
    let (host, selector) = match rest.strip_prefix("//") {
        Some(r) => match r.find(['/', '?', '#']) {
            Some(i) => (&r[..i], &r[i..]),
            None => (r, ""),
        },
        None => ("", rest),
    };
    if host.is_empty() {
        return Err(Error::Os("no host given".into()));
    }
    // http.client's _get_hostport.
    let (name, port) = match (host.rfind(':'), host.rfind(']')) {
        (Some(i), j) if j.map_or(true, |j| i > j) => {
            let p = &host[i + 1..];
            let port = if p.is_empty() {
                80
            } else {
                p.parse::<u16>().map_err(|_| {
                    Error::Crash(Crash::new(
                        "http.client.InvalidURL",
                        format!("nonnumeric port: '{}'", p),
                    ))
                })?
            };
            (&host[..i], port)
        }
        _ => (host, 80),
    };
    let name = name.trim_start_matches('[').trim_end_matches(']');
    let path = if selector.is_empty() { "/" } else { selector };
    validate(path, headers)?;

    let timeout = Duration::from_secs(timeout);
    let addrs: Vec<_> = (name, port)
        .to_socket_addrs()
        .map_err(|e| Error::Os(os_error(&e)))?
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
            let e = last.unwrap_or_else(|| std::io::Error::other("no address"));
            return Err(Error::Os(os_error(&e)));
        }
    };
    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let mut wire = format!("GET {} HTTP/1.1\r\n", path).into_bytes();
    wire.extend_from_slice(b"Accept-Encoding: identity\r\n");
    wire.extend_from_slice(format!("Host: {}\r\n", host).as_bytes());
    // Header values go out as latin-1, as http.client encodes them.
    for (k, v) in headers {
        wire.extend_from_slice(k.as_bytes());
        wire.extend_from_slice(b": ");
        wire.extend(v.chars().map(|c| c as u32 as u8));
        wire.extend_from_slice(b"\r\n");
    }
    wire.extend_from_slice(b"Connection: close\r\n\r\n");
    stream
        .write_all(&wire)
        .map_err(|e| Error::Os(os_error(&e)))?;

    let mut raw = Vec::new();
    if let Err(e) = stream.read_to_end(&mut raw) {
        if raw.is_empty() {
            return Err(Error::Os(os_error(&e)));
        }
    }
    let split = match raw.windows(4).position(|w| w == b"\r\n\r\n") {
        Some(s) => s,
        None if raw.is_empty() => {
            return Err(Error::Os(
                "Remote end closed connection without response".into(),
            ))
        }
        None => {
            return Err(Error::Crash(Crash::new(
                "http.client.BadStatusLine",
                pystr::repr_str(&String::from_utf8_lossy(&raw)),
            )))
        }
    };
    let (status, headers) = parse_head(&raw[..split])?;
    let mut body = raw[split + 4..].to_vec();
    if header(&headers, "transfer-encoding")
        .is_some_and(|v| v.to_ascii_lowercase().contains("chunked"))
    {
        body = dechunk(&body);
    } else if let Some(n) =
        header(&headers, "content-length").and_then(|v| v.trim().parse::<usize>().ok())
    {
        body.truncate(n);
    }
    Ok(Raw {
        status,
        headers,
        body,
    })
}

fn parse_head(head: &[u8]) -> Result<(u16, Vec<(String, String)>), Error> {
    // Header bytes are latin-1 to http.client.
    let head: String = head.iter().map(|b| *b as char).collect();
    let mut lines = head.split("\r\n");
    let status_line = lines.next().unwrap_or("");
    let mut parts = status_line.splitn(3, ' ');
    let version = parts.next().unwrap_or("");
    let code = parts.next().and_then(|c| c.parse::<u16>().ok());
    let code = match code {
        Some(c) if version.starts_with("HTTP/") && (100..=999).contains(&c) => c,
        _ => {
            return Err(Error::Crash(Crash::new(
                "http.client.BadStatusLine",
                pystr::repr_str(status_line),
            )))
        }
    };
    let mut headers = Vec::new();
    for line in lines {
        if let Some((k, v)) = line.split_once(':') {
            headers.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    Ok((code, headers))
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
fn curl_quote(s: &str) -> String {
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

fn curl(url: &str, headers: &[(&str, String)], timeout: u64) -> Result<Raw, Error> {
    let after = &url["https://".len().min(url.len())..];
    let path = match after.find(['/', '?']) {
        Some(i) => &after[i..],
        None => "/",
    };
    if after.split(['/', '?']).next().unwrap_or("").is_empty() {
        return Err(Error::Os("no host given".into()));
    }
    validate(path, headers)?;
    // Everything goes in a config on stdin, so the token stays out of `ps`.
    let mut config = String::new();
    config.push_str(&format!("url = {}\n", curl_quote(url)));
    config.push_str(&format!("max-time = {}\n", timeout));
    config.push_str("include\n");
    config.push_str("header = \"Accept-Encoding: identity\"\n");
    for (k, v) in headers {
        config.push_str(&format!(
            "header = {}\n",
            curl_quote(&format!("{}: {}", k, v))
        ));
    }
    let mut child = Command::new("curl")
        .args(["-sS", "-K", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Error::Os(os_error(&e)))?;
    {
        let mut stdin = child.stdin.take().unwrap();
        let _ = stdin.write_all(config.as_bytes());
    }
    let out = child
        .wait_with_output()
        .map_err(|e| Error::Os(os_error(&e)))?;
    if !out.status.success() {
        return Err(Error::Os(
            String::from_utf8_lossy(&out.stderr).trim().to_string(),
        ));
    }
    // Skip interim responses (100 Continue, a proxy's 200 for CONNECT).
    let mut rest: &[u8] = &out.stdout;
    loop {
        let split = rest
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .ok_or_else(|| Error::Os("Remote end closed connection without response".into()))?;
        let (status, headers) = parse_head(&rest[..split])?;
        let body = &rest[split + 4..];
        if (status < 200 || status == 200 && headers.is_empty()) && body.starts_with(b"HTTP/") {
            rest = body;
            continue;
        }
        return Ok(Raw {
            status,
            headers,
            body: body.to_vec(),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;

    /// A server that answers each connection with the next response.
    fn serve(responses: Vec<&'static [u8]>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        thread::spawn(move || {
            for response in responses {
                let (mut s, _) = listener.accept().unwrap();
                let mut buf = [0u8; 4096];
                let _ = s.read(&mut buf);
                s.write_all(response).unwrap();
            }
        });
        format!("http://{}", addr)
    }

    #[test]
    fn reads_length_and_chunked_bodies_and_headers() {
        let base = serve(vec![
            b"HTTP/1.0 200 OK\r\nLink: <x>; rel=\"next\"\r\nContent-Length: 2\r\n\r\n[]extra",
        ]);
        let r = get(&format!("{}/a", base), &[], 5).unwrap();
        assert_eq!(r.body, b"[]");
        assert_eq!(r.header("link"), Some("<x>; rel=\"next\""));
        let base = serve(vec![
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n[1\r\n1\r\n]\r\n0\r\n\r\n",
        ]);
        assert_eq!(get(&format!("{}/a", base), &[], 5).unwrap().body, b"[1]");
    }

    #[test]
    fn errors_read_as_urllib_words_them() {
        let base = serve(vec![b"HTTP/1.0 403 Forbidden\r\n\r\n{\"message\": \"no\"}"]);
        assert_eq!(
            get(&format!("{}/a", base), &[], 5).err(),
            Some(Error::Http {
                code: 403,
                body: b"{\"message\": \"no\"}".to_vec()
            })
        );
        assert!(matches!(get("nope", &[], 5), Err(Error::Crash(c)) if c.class == "ValueError"));
        assert_eq!(
            get("gopher://x/", &[], 5).err(),
            Some(Error::Os("unknown url type: gopher".into()))
        );
        assert_eq!(
            get("http:///x", &[], 5).err(),
            Some(Error::Os("no host given".into()))
        );
        match get("http://127.0.0.1:1/", &[], 5) {
            Err(Error::Os(m)) => assert!(m.starts_with("[Errno "), "{}", m),
            other => panic!("{:?}", other.err()),
        }
        assert!(matches!(
            get("http://127.0.0.1:x/", &[], 5),
            Err(Error::Crash(c)) if c.class == "http.client.InvalidURL"
        ));
        assert!(matches!(
            get("http://127.0.0.1:1/a b", &[], 5),
            Err(Error::Crash(c)) if c.class == "http.client.InvalidURL"
        ));
        assert!(matches!(
            get("http://127.0.0.1:1/", &[("Authorization", "Bearer a\nb".into())], 5),
            Err(Error::Crash(c)) if c.class == "ValueError"
        ));
    }

    #[test]
    fn follows_redirects_and_stops_a_loop() {
        let base = serve(vec![
            b"HTTP/1.0 301 Moved\r\nLocation: /b\r\n\r\n",
            b"HTTP/1.0 200 OK\r\n\r\nok",
        ]);
        assert_eq!(get(&format!("{}/a", base), &[], 5).unwrap().body, b"ok");
        // The same URL a fifth time is a loop: urllib gives up with the 302.
        let loop_ = b"HTTP/1.0 302 Found\r\nLocation: /a\r\n\r\nloop" as &'static [u8];
        let base = serve(vec![loop_; 6]);
        assert_eq!(
            get(&format!("{}/a", base), &[], 5).err(),
            Some(Error::Http {
                code: 302,
                body: b"loop".to_vec()
            })
        );
        // A redirect to a scheme urllib will not follow reports the redirect.
        let base = serve(vec![
            b"HTTP/1.0 302 Found\r\nLocation: file:///etc/passwd\r\n\r\n",
        ]);
        assert!(matches!(
            get(&format!("{}/a", base), &[], 5),
            Err(Error::Http { code: 302, .. })
        ));
    }

    #[test]
    fn joins_locations() {
        let j = |b: &str, l: &str| redirect_target(b, l).unwrap().unwrap();
        assert_eq!(j("http://h:1/a/b?x", "c"), "http://h:1/a/c");
        assert_eq!(j("http://h:1/a/b?x", "/c?d"), "http://h:1/c?d");
        assert_eq!(j("http://h:1/a/b", "?q"), "http://h:1/a/b?q");
        assert_eq!(j("http://h:1/a", "//g/x"), "http://g/x");
        assert_eq!(j("http://h:1/a", "https://g"), "https://g/");
        assert_eq!(j("http://h:1/a", "/a b"), "http://h:1/a%20b");
    }
}
