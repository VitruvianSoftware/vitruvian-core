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

//! transient-lib.sh — shared classifier for transient Go module-proxy /
//! network transport failures, as distinct from real code errors.

use std::process::Command;

const PATTERN: &str = "stream error|connection reset|unexpected EOF|TLS handshake timeout|i/o timeout|dial tcp.*(timeout|refused)|no such host|Client\\.Timeout exceeded while awaiting headers|server misbehaving|GOAWAY|context deadline exceeded|proxy\\.golang\\.org.*\\b5[0-9]{2}\\b";

/// `is_transient_network_error` — true when the content carries a
/// recognizable module-proxy / network transport failure signature.
pub fn is_transient_network_error(content: &[u8]) -> bool {
    let mut cmd = Command::new("grep");
    cmd.arg("-qiE").arg(PATTERN);
    shell_compat::status_with_input(0, &mut cmd, content, true) == 0
}

/// Retained name from go-test-with-retry.sh, delegating to the shared
/// classifier so existing callers keep working.
pub fn is_transient_go_test_error(content: &[u8]) -> bool {
    is_transient_network_error(content)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stream_error() {
        assert!(is_transient_network_error(
            b"go: downloading github.com/foo v1.2.3\nhttp2: stream error: stream ID 5; INTERNAL_ERROR"
        ));
    }

    #[test]
    fn connection_reset() {
        assert!(is_transient_network_error(
            b"read tcp 10.0.0.1:443: connection reset by peer"
        ));
    }

    #[test]
    fn unexpected_eof() {
        assert!(is_transient_network_error(
            b"go: github.com/foo@v1.2.3: unexpected EOF"
        ));
    }

    #[test]
    fn tls_handshake_timeout() {
        assert!(is_transient_network_error(
            b"Get \"https://proxy.golang.org/...\": net/http: TLS handshake timeout"
        ));
    }

    #[test]
    fn io_timeout() {
        assert!(is_transient_network_error(b"dial tcp: i/o timeout"));
    }

    #[test]
    fn dial_tcp_timeout() {
        assert!(is_transient_network_error(
            b"dial tcp 142.250.0.1:443: i/o timeout"
        ));
    }

    #[test]
    fn dial_tcp_refused() {
        assert!(is_transient_network_error(
            b"dial tcp 127.0.0.1:443: connect: connection refused"
        ));
    }

    #[test]
    fn no_such_host() {
        assert!(is_transient_network_error(
            b"dial tcp: lookup proxy.golang.org: no such host"
        ));
    }

    #[test]
    fn client_timeout() {
        assert!(is_transient_network_error(
            b"Get \"https://proxy.golang.org/x\": net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)"
        ));
    }

    #[test]
    fn server_misbehaving() {
        assert!(is_transient_network_error(
            b"lookup proxy.golang.org: server misbehaving"
        ));
    }

    #[test]
    fn goaway() {
        assert!(is_transient_network_error(
            b"http2: server sent GOAWAY and closed the connection"
        ));
    }

    #[test]
    fn context_deadline_exceeded() {
        assert!(is_transient_network_error(b"context deadline exceeded"));
    }

    #[test]
    fn proxy_5xx() {
        assert!(is_transient_network_error(
            b"go: github.com/foo@v1.2.3: reading https://proxy.golang.org/github.com/foo/@v/v1.2.3.info: 503 Service Unavailable"
        ));
    }

    #[test]
    fn case_insensitive_match() {
        assert!(is_transient_network_error(
            b"GOT A Connection Reset BY peer"
        ));
    }

    #[test]
    fn assertion_failure_not_transient() {
        assert!(!is_transient_network_error(
            b"--- FAIL: TestFoo (0.00s)\n    foo_test.go:42: expected 1, got 2\nFAIL"
        ));
    }

    #[test]
    fn compile_error_not_transient() {
        assert!(!is_transient_network_error(
            b"./foo.go:10:2: undefined: bar"
        ));
    }

    #[test]
    fn bare_eof_not_transient() {
        assert!(!is_transient_network_error(
            b"unexpected end of JSON input: EOF"
        ));
    }

    #[test]
    fn panic_not_transient() {
        assert!(!is_transient_network_error(
            b"panic: runtime error: index out of range [3] with length 2"
        ));
    }

    #[test]
    fn empty_not_transient() {
        assert!(!is_transient_network_error(b""));
    }

    #[test]
    fn alias_works() {
        assert!(is_transient_go_test_error(b"connection reset by peer"));
        assert!(!is_transient_go_test_error(b"FAIL TestFoo"));
    }
}
