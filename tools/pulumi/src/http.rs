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

pub use vitruvian_pycompat::http::Request;
use vitruvian_pycompat::http::{os_error_reason, send_with, Options, TransportError};

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

    let inner = Request { url, ..*req };
    let opts = Options {
        user_agent: "rotate-access-token-rs",
        timeout: None,
    };
    let resp = send_with(&inner, &opts).map_err(|e| match e {
        TransportError::NoHost => Error::Url("no host given".into()),
        TransportError::Resolve(e)
        | TransportError::Connect { err: e, .. }
        | TransportError::Io(e)
        | TransportError::CurlSpawn(e)
        | TransportError::CurlWait(e) => Error::Url(os_error_reason(&e)),
        TransportError::NoAddress => Error::Url("no address".into()),
        TransportError::NoResponse => {
            Error::Url("Remote end closed connection without response".into())
        }
        TransportError::BadStatusLine(s) => Error::Url(format!("bad status line {:?}", s)),
        TransportError::CurlFailed { stderr, .. } | TransportError::NoStatus { stderr } => {
            Error::Url(stderr)
        }
        TransportError::InvalidScheme => Error::Url(format!("unknown url type: {}", kind)),
    })?;

    if !(200..300).contains(&resp.status) {
        return Err(Error::Http(resp.status));
    }
    Ok(resp.body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

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

    #[test]
    fn times_out_when_server_does_not_reply() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let (tx, rx) = mpsc::channel::<()>();
        let handle = thread::spawn(move || {
            let (_s, _) = listener.accept().unwrap();
            let _ = rx.recv_timeout(Duration::from_secs(5));
        });
        let res = send(&Request {
            method: "GET",
            url: &format!("http://{}/slow", addr),
            headers: &[],
            body: None,
            timeout: 1,
        });
        drop(tx);
        let _ = handle.join();
        assert!(matches!(res, Err(Error::Url(_))), "{res:?}");
    }
}
