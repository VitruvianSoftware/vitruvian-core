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

//! The shared classifier for "the Go module proxy / network failed", as
//! distinct from "your code is wrong". It reaches every tool that shells a
//! `go` command, and a tool that cannot tell the two apart MISREPORTS: on
//! 2026-08-20 proxy.golang.org returned INTERNAL_ERROR mid-run and the gomod
//! check announced two modules out of sync when nothing was. One copy, used by
//! //tools/ci:go_test_with_retry and //tools/gomod, so one lane cannot stop
//! recognising what the other still does.
//!
//! It matches TRANSPORT failures only, so a genuine `go` error (a real diff, a
//! compile failure, a missing module) never matches and is never retried or
//! excused. The rule is the ERE the retired tools/ci/transient-lib.sh gave
//! `grep -qiE`, applied line by line and case-insensitively:
//!
//! ```text
//! stream error|connection reset|unexpected EOF|TLS handshake timeout|
//! i/o timeout|dial tcp.*(timeout|refused)|no such host|
//! Client\.Timeout exceeded while awaiting headers|server misbehaving|GOAWAY|
//! context deadline exceeded|proxy\.golang\.org.*\b5[0-9]{2}\b
//! ```
//!
//! Matched in-process rather than by piping into `grep -q`: grep exits at the
//! first match, and a writer still feeding it then gets EPIPE, which reads as
//! "no match" -- on exactly the long outputs a flaky download produces.
//! Standard library only, so CI jobs without Bazel can build it with a bare
//! `rustc` (see .github/workflows/ci.yaml).

/// The fixed alternatives, lower-cased.
const LITERALS: &[&[u8]] = &[
    b"stream error",
    b"connection reset",
    b"unexpected eof",
    b"tls handshake timeout",
    b"i/o timeout",
    b"no such host",
    b"client.timeout exceeded while awaiting headers",
    b"server misbehaving",
    b"goaway",
    b"context deadline exceeded",
];

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

/// `\w` for grep: an ASCII letter, digit or underscore.
fn is_word(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}

/// `\b5[0-9]{2}\b` somewhere in `s`.
fn has_5xx_word(s: &[u8]) -> bool {
    (0..s.len().saturating_sub(2)).any(|i| {
        s[i] == b'5'
            && s[i + 1].is_ascii_digit()
            && s[i + 2].is_ascii_digit()
            && (i == 0 || !is_word(s[i - 1]))
            && (i + 3 == s.len() || !is_word(s[i + 3]))
    })
}

/// One line, already lower-cased.
fn line_matches(l: &[u8]) -> bool {
    if LITERALS.iter().any(|lit| find(l, lit).is_some()) {
        return true;
    }
    // dial tcp.*(timeout|refused)
    if let Some(i) = find(l, b"dial tcp") {
        let rest = &l[i + b"dial tcp".len()..];
        if find(rest, b"timeout").is_some() || find(rest, b"refused").is_some() {
            return true;
        }
    }
    // proxy\.golang\.org.*\b5[0-9]{2}\b
    if let Some(i) = find(l, b"proxy.golang.org") {
        if has_5xx_word(&l[i + b"proxy.golang.org".len()..]) {
            return true;
        }
    }
    false
}

/// `is_transient_network_error` -- true when captured `go` output carries a
/// recognizable module-proxy / network transport failure.
pub fn is_transient_network_error(content: &[u8]) -> bool {
    content
        .split(|&c| c == b'\n')
        .any(|line| line_matches(&line.to_ascii_lowercase()))
}

/// The same, over a file of captured output. An unreadable file is not a
/// match (grep's exit 2 under `if`).
pub fn is_transient_network_error_file(path: &std::path::Path) -> bool {
    std::fs::read(path)
        .map(|c| is_transient_network_error(&c))
        .unwrap_or(false)
}

/// Retained name from the retired go-test-with-retry.sh, delegating to the shared
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

    // --- beyond the shell suite ----------------------------------------------

    #[test]
    fn a_match_early_in_long_output_still_matches() {
        // grep -q exits at the first match; a writer still feeding it read
        // that as "no match". 4 MiB after the marker is far past a pipe buffer.
        let mut big = b"go: downloading x\nhttp2: stream error: stream ID 5\n".to_vec();
        big.extend(std::iter::repeat(b'x').take(4 << 20));
        assert!(is_transient_network_error(&big));
    }

    #[test]
    fn patterns_do_not_span_lines() {
        assert!(!is_transient_network_error(
            b"dial tcp 1.2.3.4:443\nTestTimeout failed"
        ));
        assert!(!is_transient_network_error(b"proxy.golang.org\n503"));
    }

    #[test]
    fn proxy_5xx_needs_word_boundaries() {
        assert!(is_transient_network_error(
            b"proxy.golang.org/x: 502 Bad Gateway"
        ));
        assert!(is_transient_network_error(
            b"https://proxy.golang.org/x/@v/v1.info:599"
        ));
        assert!(!is_transient_network_error(
            b"proxy.golang.org/x 5031 bytes"
        ));
        assert!(
            is_transient_network_error(b"proxy.golang.org/x v1.503"),
            "'.' is a word boundary, so grep's \\b matches 503 here"
        );
    }

    #[test]
    fn a_5xx_before_the_proxy_name_does_not_count() {
        assert!(!is_transient_network_error(b"503 from proxy.golang.org"));
    }

    #[test]
    fn file_form_reads_the_file() {
        let d = std::env::temp_dir().join(format!("transient-lib-{}", std::process::id()));
        std::fs::write(&d, b"connection reset by peer\n").unwrap();
        assert!(is_transient_network_error_file(&d));
        std::fs::write(&d, b"FAIL TestFoo\n").unwrap();
        assert!(!is_transient_network_error_file(&d));
        let _ = std::fs::remove_file(&d);
        assert!(
            !is_transient_network_error_file(&d),
            "unreadable is not a match"
        );
    }

    /// Held to the retired script's actual rule: every case here gets the same
    /// verdict from `grep -qiE <ERE>` over a file.
    #[test]
    fn agrees_with_grep_on_the_ere() {
        const ERE: &str = "stream error|connection reset|unexpected EOF|TLS handshake timeout|i/o timeout|dial tcp.*(timeout|refused)|no such host|Client\\.Timeout exceeded while awaiting headers|server misbehaving|GOAWAY|context deadline exceeded|proxy\\.golang\\.org.*\\b5[0-9]{2}\\b";
        let cases: &[&[u8]] = &[
            b"http2: stream error: stream ID 5; INTERNAL_ERROR",
            b"read tcp: CONNECTION RESET by peer",
            b"unexpected eof",
            b"TLS Handshake Timeout",
            b"dial tcp: i/o timeout",
            b"dial tcp 127.0.0.1:443: connect: connection refused",
            b"dial tcp ... Timeout",
            b"DIAL TCP refused",
            b"tcp dial refused",
            b"lookup proxy.golang.org: no such host",
            b"Client.Timeout exceeded while awaiting headers",
            b"ClientXTimeout exceeded while awaiting headers",
            b"server misbehaving",
            b"server sent goaway",
            b"context deadline exceeded",
            b"proxy.golang.org: 503 Service Unavailable",
            b"proxy.golang.org/x 5031 bytes",
            b"proxy.golang.org/x v1.503",
            b"proxy.golang.org/x_503",
            b"proxyXgolangXorg 503",
            b"503 proxy.golang.org",
            b"--- FAIL: TestFoo (0.00s)",
            b"./foo.go:10:2: undefined: bar",
            b"unexpected end of JSON input: EOF",
            b"panic: runtime error: index out of range [3] with length 2",
            b"",
            b"dial tcp 1.2.3.4:443\nTestTimeout failed",
            b"first line\nconnection reset by peer\nlast",
        ];
        let f = std::env::temp_dir().join(format!("transient-lib-grep-{}", std::process::id()));
        for c in cases {
            std::fs::write(&f, c).unwrap();
            let grep = std::process::Command::new("grep")
                .args(["-qiE", ERE])
                .arg(&f)
                .env("LC_ALL", "C")
                .status()
                .expect("grep")
                .success();
            assert_eq!(
                is_transient_network_error(c),
                grep,
                "disagrees with grep -qiE on {:?}",
                String::from_utf8_lossy(c)
            );
        }
        let _ = std::fs::remove_file(&f);
    }
}
