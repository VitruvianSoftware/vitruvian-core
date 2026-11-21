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

use std::time::Duration;

pub use vitruvian_pycompat::http::Response;
use vitruvian_pycompat::http::{send_with, Options, Request, TransportError};

/// POSTs `body` to `url`. Err is why it could not be reached, as the text
/// after Go's `Post "<url>": `.
pub fn post(
    url: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: Duration,
) -> Result<Response, String> {
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(format!(
            "unsupported protocol scheme {}",
            unitfile::gocompat::quote::quote(url.split(':').next().unwrap_or(""))
        ));
    }
    let req = Request {
        method: "POST",
        url,
        headers,
        body: Some(body),
        timeout: timeout.as_secs(),
    };
    let opts = Options {
        user_agent: "verified-run",
        timeout: Some(timeout),
    };
    send_with(&req, &opts).map_err(|e| match e {
        TransportError::NoHost => "dial tcp: no host".to_string(),
        TransportError::Resolve(e) => format!("dial tcp: {e}"),
        TransportError::NoAddress => "dial tcp: no address".to_string(),
        TransportError::Connect { addr, err } => format!(
            "dial tcp {addr}: connect: {}",
            unitfile::gocompat::oserr::errno_text(&err)
        ),
        TransportError::Io(e) => e.to_string(),
        TransportError::NoResponse => "malformed HTTP response".to_string(),
        TransportError::BadStatusLine(_) => "malformed HTTP status line".to_string(),
        TransportError::CurlSpawn(e) | TransportError::CurlWait(e) => format!("curl: {e}"),
        TransportError::CurlFailed { stderr, .. } => stderr,
        TransportError::NoStatus { .. } => "curl gave no status".to_string(),
        TransportError::InvalidScheme => format!(
            "unsupported protocol scheme {}",
            unitfile::gocompat::quote::quote(url.split(':').next().unwrap_or(""))
        ),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader, Read, Write};
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
        (format!("http://{addr}/path"), rx)
    }

    #[test]
    fn posts_body_headers_and_reads_length_and_chunked_responses() {
        let (url, rx) = serve(b"HTTP/1.1 201 Created\r\nContent-Length: 4\r\n\r\ndoneEXTRA");
        let headers = [
            ("Authorization", "Bearer secret".to_string()),
            ("X-Test", "1".to_string()),
        ];
        let resp = post(&url, &headers, b"{\"ok\":true}", Duration::from_secs(5)).unwrap();
        assert_eq!(resp.status, 201);
        assert_eq!(resp.body, b"done");
        let sent = String::from_utf8(rx.recv().unwrap()).unwrap();
        assert!(sent.starts_with("POST /path HTTP/1.1\r\n"), "{sent}");
        assert!(sent.contains("Authorization: Bearer secret\r\n"), "{sent}");
        assert!(sent.contains("X-Test: 1\r\n"), "{sent}");
        assert!(sent.contains("Content-Length: 11\r\n"), "{sent}");
        assert!(sent.ends_with("\r\n\r\n{\"ok\":true}"), "{sent}");

        let (url_chunked, _) = serve(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhi\r\n1\r\n!\r\n0\r\n\r\n",
        );
        let resp2 = post(&url_chunked, &[], b"", Duration::from_secs(5)).unwrap();
        assert_eq!(resp2.status, 200);
        assert_eq!(resp2.body, b"hi!");
    }

    #[test]
    fn returns_non_2xx_status_and_body() {
        let (url, _) = serve(b"HTTP/1.1 422 Unprocessable Entity\r\nContent-Length: 3\r\n\r\nbad");
        let resp = post(&url, &[], b"{}", Duration::from_secs(5)).unwrap();
        assert_eq!(resp.status, 422);
        assert_eq!(resp.body, b"bad");
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
        let url = format!("http://{addr}/slow");
        let res = post(&url, &[], b"{}", Duration::from_millis(200));
        drop(tx);
        let _ = handle.join();
        assert!(res.is_err(), "expected timeout error");
    }

    #[test]
    fn rejects_unsupported_scheme() {
        let err = post("ftp://example.com/x", &[], b"", Duration::from_secs(1))
            .err()
            .unwrap();
        assert!(err.contains("unsupported protocol scheme \"ftp\""), "{err}");
    }
}
