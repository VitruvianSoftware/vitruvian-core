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

pub use vitruvian_pycompat::http::Request;
use vitruvian_pycompat::http::{os_error_reason, send_with, Options, TransportError};

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
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(Error::Value(format!(
            "unknown url type: {}",
            crate::pystr::repr_str(url)
        )));
    }

    let mut headers_buf;
    let headers: &[(&str, String)] = if req.body.is_some() {
        headers_buf = Vec::with_capacity(req.headers.len() + 1);
        headers_buf.push((
            "Content-Type",
            "application/x-www-form-urlencoded".to_string(),
        ));
        headers_buf.extend(req.headers.iter().cloned());
        &headers_buf
    } else {
        req.headers
    };

    let inner = Request {
        url,
        headers,
        ..*req
    };
    let opts = Options {
        user_agent: "merge-queue-stats-rs",
        timeout: None,
    };
    let resp = send_with(&inner, &opts).map_err(|e| match e {
        TransportError::NoHost => Error::Url("<urlopen error no host given>".into()),
        TransportError::Resolve(e)
        | TransportError::Connect { err: e, .. }
        | TransportError::Io(e)
        | TransportError::CurlSpawn(e)
        | TransportError::CurlWait(e) => {
            Error::Url(format!("<urlopen error {}>", os_error_reason(&e)))
        }
        TransportError::NoAddress => Error::Url("<urlopen error no address>".into()),
        TransportError::NoResponse => {
            Error::Url("<urlopen error Remote end closed connection without response>".into())
        }
        TransportError::BadStatusLine(s) => {
            Error::Url(format!("<urlopen error bad status line {:?}>", s))
        }
        TransportError::CurlFailed { stderr, .. } | TransportError::NoStatus { stderr } => {
            Error::Url(format!("<urlopen error {}>", stderr))
        }
        TransportError::InvalidScheme => {
            Error::Value(format!("unknown url type: {}", crate::pystr::repr_str(url)))
        }
    })?;

    if !(200..300).contains(&resp.status) {
        let phrase = if resp.reason.is_empty() {
            reason(resp.status)
        } else {
            resp.reason.as_str()
        };
        return Err(Error::Url(format!(
            "HTTP Error {}: {}",
            resp.status, phrase
        )));
    }
    Ok(resp.body)
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
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpListener;
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

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
        let (url, _) = serve(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n[]extra");
        assert_eq!(get(&url).unwrap(), b"[]");
        let (url, _) = serve(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n[1\r\n1\r\n]\r\n0\r\n\r\n",
        );
        assert_eq!(get(&url).unwrap(), b"[1]");
    }

    #[test]
    fn posts_body_with_headers_and_form_content_type() {
        let (url, rx) = serve(b"HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok");
        let headers = [
            ("Authorization", "Bearer tok".to_string()),
            ("X-Custom", "v".to_string()),
        ];
        let body = send(&Request {
            method: "POST",
            url: &url,
            headers: &headers,
            body: Some(b"{\"q\":1}"),
            timeout: 5,
        })
        .unwrap();
        assert_eq!(body, b"ok");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.starts_with("POST /x?y=1 HTTP/1.1\r\n"), "{}", sent);
        assert!(sent.contains("Authorization: Bearer tok\r\n"), "{}", sent);
        assert!(sent.contains("X-Custom: v\r\n"), "{}", sent);
        assert!(
            sent.contains("Content-Type: application/x-www-form-urlencoded\r\n"),
            "{}",
            sent
        );
        assert!(sent.contains("Content-Length: 7\r\n"), "{}", sent);
        assert!(sent.ends_with("\r\n\r\n{\"q\":1}"), "{}", sent);
    }

    #[test]
    fn errors_read_as_urllib_words_them() {
        let (url, _) = serve(b"HTTP/1.0 502 Bad Gateway\r\n\r\n");
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
        match res {
            Err(Error::Url(msg)) => assert!(msg.starts_with("<urlopen error "), "{msg}"),
            other => panic!("expected timeout Url error, got {other:?}"),
        }
    }
}
