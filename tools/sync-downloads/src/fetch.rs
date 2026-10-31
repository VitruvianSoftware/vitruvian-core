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

//! `fetch_json`: GitHub's API through `gh api` when `which gh` finds it,
//! else over HTTPS. The standard library has no TLS, so the HTTPS fallback
//! runs `curl` (headers on stdin, so a token never shows in `ps`); a failure
//! there is a warning and None, as urllib's is in the script.
//!
//! A blip on the network should not cost a release its catalog entry, so a
//! fetch is tried up to [`ATTEMPTS`] times. One attempt is one round: `gh
//! api`, then curl if gh failed. The round is what is retried, not each
//! program on its own, because curl is already gh's fallback: when gh fails
//! and curl works, the round succeeds at once with no wait. Only curl's
//! error decides whether to go again, since it is the round's last word:
//! a network error, a timeout, a 5xx, 408 or 429 is worth another round;
//! a 404, 401, 403 or any other 4xx is an answer, and is not asked again.
//! Retrying it would only slow the sync down: 404 is the normal reply for a
//! repo with no published release.
//!
//! When one fetch has used every attempt on a transient error, GitHub is
//! most likely down for this run, so the fetches after it get one attempt
//! each instead of waiting through the same backoff over and over.

use std::io::Write;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use crate::json::{self, Value};
use crate::pyerr::Crash;

/// How many rounds (gh, then curl) a fetch gets.
pub const ATTEMPTS: u32 = 3;

/// The wait before round `n + 1`, after round `n` (1-based) failed: 2s, 4s.
pub fn backoff(n: u32) -> Duration {
    Duration::from_secs(2u64.saturating_pow(n))
}

/// Set once a fetch has run out of attempts on a transient error.
static GAVE_UP: AtomicBool = AtomicBool::new(false);

/// Why a curl request failed.
#[derive(Debug, Clone, PartialEq)]
pub enum CurlError {
    /// No HTTP answer: curl exited `code` (None when it could not be
    /// started), with `msg` on stderr.
    Network { code: Option<i32>, msg: String },
    /// The server answered with a status outside 2xx.
    Http(u16),
    /// A 2xx whose body is not UTF-8 JSON.
    Body(String),
}

impl CurlError {
    /// Whether another round could get a different answer.
    pub fn is_transient(&self) -> bool {
        match self {
            // curl's exit codes for a request that never got an answer:
            // 5 proxy and 6 host not resolved, 7 could not connect, 18
            // partial transfer, 28 timed out, 35 TLS handshake, 52 empty
            // reply, 55 send and 56 receive failures, 16 and 92 HTTP/2
            // framing. The rest (a bad URL, a bad option, curl missing)
            // would fail the same way again.
            CurlError::Network { code, .. } => matches!(
                code,
                Some(5 | 6 | 7 | 16 | 18 | 28 | 35 | 52 | 55 | 56 | 92)
            ),
            CurlError::Http(code) => matches!(code, 408 | 429 | 500..=599),
            CurlError::Body(_) => false,
        }
    }
}

impl std::fmt::Display for CurlError {
    /// The error as urllib words it.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CurlError::Network { msg, .. } => write!(f, "<urlopen error {}>", msg),
            CurlError::Http(code) => write!(f, "HTTP Error {}: {}", code, reason(*code)),
            CurlError::Body(msg) => f.write_str(msg),
        }
    }
}

/// The programs a fetch runs. The real one runs them; tests script them.
pub trait Transport {
    /// `which gh` succeeded.
    fn has_gh(&mut self) -> Result<bool, Crash>;
    /// `gh api <endpoint>`: its stdout when it exits 0, else None.
    fn gh(&mut self, endpoint: &str) -> Result<Option<Vec<u8>>, Crash>;
    /// GET `url` with curl; the body on a 2xx.
    fn curl(&mut self, url: &str, headers: &[String], timeout: u32) -> Result<Vec<u8>, CurlError>;
}

/// The transport that runs `which`, `gh` and `curl`.
pub struct System;

impl Transport for System {
    fn has_gh(&mut self) -> Result<bool, Crash> {
        let which = Command::new("which")
            .arg("gh")
            .stdin(Stdio::inherit())
            .output()
            .map_err(|e| Crash::os(&e, Some("which")))?;
        Ok(which.status.success())
    }

    fn gh(&mut self, endpoint: &str) -> Result<Option<Vec<u8>>, Crash> {
        let res = Command::new("gh")
            .args(["api", endpoint])
            .stdin(Stdio::inherit())
            .output()
            .map_err(|e| Crash::os(&e, Some("gh")))?;
        Ok(res.status.success().then_some(res.stdout))
    }

    fn curl(&mut self, url: &str, headers: &[String], timeout: u32) -> Result<Vec<u8>, CurlError> {
        curl_get(url, headers, timeout)
    }
}

/// What the script's `fetch_json` returns, or the exception it lets out.
pub fn fetch_json(endpoint: &str, token: Option<&str>) -> Result<Option<Value>, Crash> {
    let attempts = if GAVE_UP.load(Ordering::Relaxed) {
        1
    } else {
        ATTEMPTS
    };
    let (value, gave_up) = fetch_json_with(
        endpoint,
        token,
        &mut System,
        &mut std::thread::sleep,
        attempts,
    )?;
    if gave_up {
        GAVE_UP.store(true, Ordering::Relaxed);
    }
    Ok(value)
}

/// `fetch_json` over `transport`, sleeping with `sleep` between at most
/// `attempts` rounds. The bool is true when every round failed on a
/// transient error.
pub fn fetch_json_with(
    endpoint: &str,
    token: Option<&str>,
    transport: &mut dyn Transport,
    sleep: &mut dyn FnMut(Duration),
    attempts: u32,
) -> Result<(Option<Value>, bool), Crash> {
    let url = format!(
        "https://api.github.com/{}",
        endpoint.trim_start_matches('/')
    );
    let env_token = |name: &str| std::env::var(name).ok().filter(|v| !v.is_empty());
    let auth = token
        .filter(|t| !t.is_empty())
        .map(String::from)
        .or_else(|| env_token("GH_TOKEN"))
        .or_else(|| env_token("GITHUB_TOKEN"));
    let mut headers = vec!["User-Agent: vitruvian-sync-downloads".to_string()];
    if let Some(t) = auth {
        headers.push(format!("Authorization: token {}", t));
    }

    let has_gh = transport.has_gh()?;
    let attempts = attempts.max(1);
    let mut round = 1;
    loop {
        if has_gh {
            if let Some(stdout) = transport.gh(endpoint)? {
                return gh_json(stdout).map(|v| (Some(v), false));
            }
        }
        let err = match transport.curl(&url, &headers, 15).and_then(|body| {
            let text = String::from_utf8(body)
                .map_err(|e| CurlError::Body(format!("'utf-8' codec can't decode: {}", e)))?;
            json::loads(&text).map_err(|e| CurlError::Body(e.to_string()))
        }) {
            Ok(v) => return Ok((Some(v), false)),
            Err(e) => e,
        };
        if !err.is_transient() {
            eprintln!("Warning: Failed to fetch {}: {}", url, err);
            return Ok((None, false));
        }
        if round >= attempts {
            eprintln!(
                "Warning: Failed to fetch {}: {} (gave up after {} attempt{})",
                url,
                err,
                attempts,
                if attempts == 1 { "" } else { "s" }
            );
            return Ok((None, true));
        }
        let wait = backoff(round);
        eprintln!(
            "Warning: Failed to fetch {}: {} (attempt {} of {}; retrying in {}s)",
            url,
            err,
            round,
            attempts,
            wait.as_secs()
        );
        sleep(wait);
        round += 1;
    }
}

/// `gh api`'s output, decoded the way the script decodes it.
fn gh_json(stdout: Vec<u8>) -> Result<Value, Crash> {
    let text = String::from_utf8(stdout).map_err(|e| {
        Crash::new(
            "UnicodeDecodeError",
            format!("'utf-8' codec can't decode bytes: {}", e),
        )
    })?;
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    json::loads(&text).map_err(|e| Crash::new("json.decoder.JSONDecodeError", e.to_string()))
}

/// GET `url` with curl; the body on a 2xx, else why not.
fn curl_get(url: &str, headers: &[String], timeout: u32) -> Result<Vec<u8>, CurlError> {
    const MARK: &[u8] = b"\n__sync_downloads_status__";
    let mut child = Command::new("curl")
        .args(["-sS", "-L", "--max-time", &timeout.to_string(), "-H", "@-"])
        .arg("-w")
        .arg("\n__sync_downloads_status__%{http_code}")
        .arg("--")
        .arg(url)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| CurlError::Network {
            code: None,
            msg: e.to_string(),
        })?;
    {
        let mut stdin = child.stdin.take().unwrap();
        let _ = stdin.write_all(headers.join("\n").as_bytes());
        let _ = stdin.write_all(b"\n");
    }
    let out = child.wait_with_output().map_err(|e| CurlError::Network {
        code: None,
        msg: e.to_string(),
    })?;
    let pos = out.stdout.windows(MARK.len()).rposition(|w| w == MARK);
    if !out.status.success() || pos.is_none() {
        return Err(CurlError::Network {
            code: out.status.code(),
            msg: String::from_utf8_lossy(&out.stderr).trim().to_string(),
        });
    }
    let pos = pos.unwrap();
    let code: u16 = String::from_utf8_lossy(&out.stdout[pos + MARK.len()..])
        .trim()
        .parse()
        .unwrap_or(0);
    if !(200..300).contains(&code) {
        return Err(CurlError::Http(code));
    }
    Ok(out.stdout[..pos].to_vec())
}

/// The standard reason phrase; HTTP/2 responses carry none, so urllib's
/// message would hold whatever the server sent, which curl does not expose.
pub fn reason(code: u16) -> &'static str {
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
    use std::collections::VecDeque;

    /// A transport that plays back scripted answers and counts the calls.
    struct Script {
        has_gh: bool,
        gh: VecDeque<Option<&'static str>>,
        curl: VecDeque<Result<&'static str, CurlError>>,
        gh_calls: u32,
        curl_calls: u32,
    }

    impl Script {
        fn curl_only(curl: Vec<Result<&'static str, CurlError>>) -> Script {
            Script {
                has_gh: false,
                gh: VecDeque::new(),
                curl: curl.into(),
                gh_calls: 0,
                curl_calls: 0,
            }
        }
    }

    impl Transport for Script {
        fn has_gh(&mut self) -> Result<bool, Crash> {
            Ok(self.has_gh)
        }
        fn gh(&mut self, _: &str) -> Result<Option<Vec<u8>>, Crash> {
            self.gh_calls += 1;
            Ok(self
                .gh
                .pop_front()
                .expect("gh called more often than scripted")
                .map(|s| s.as_bytes().to_vec()))
        }
        fn curl(&mut self, _: &str, _: &[String], _: u32) -> Result<Vec<u8>, CurlError> {
            self.curl_calls += 1;
            self.curl
                .pop_front()
                .expect("curl called more often than scripted")
                .map(|s| s.as_bytes().to_vec())
        }
    }

    fn reset() -> CurlError {
        CurlError::Network {
            code: Some(56),
            msg: "curl: (56) Recv failure: Connection reset by peer".into(),
        }
    }

    /// Runs a fetch with a sleeper that records instead of waiting.
    fn run(t: &mut Script, attempts: u32) -> (Option<Value>, bool, Vec<Duration>) {
        let mut slept = Vec::new();
        let (v, gave_up) = fetch_json_with(
            "repos/o/r/releases/latest",
            None,
            t,
            &mut |d| slept.push(d),
            attempts,
        )
        .unwrap();
        (v, gave_up, slept)
    }

    #[test]
    fn a_transient_failure_then_success_succeeds() {
        let mut t = Script::curl_only(vec![
            Err(CurlError::Http(502)),
            Err(reset()),
            Ok(r#"{"tag_name": "v1.2.3"}"#),
        ]);
        let (v, gave_up, slept) = run(&mut t, ATTEMPTS);
        assert_eq!(v, Some(json::loads(r#"{"tag_name": "v1.2.3"}"#).unwrap()));
        assert!(!gave_up);
        assert_eq!(t.curl_calls, 3);
        assert_eq!(slept, vec![Duration::from_secs(2), Duration::from_secs(4)]);
    }

    #[test]
    fn gh_and_curl_are_retried_together_as_one_round() {
        let mut t = Script {
            has_gh: true,
            gh: vec![None, Some(r#"{"ok": true}"#)].into(),
            curl: vec![Err(CurlError::Http(503))].into(),
            gh_calls: 0,
            curl_calls: 0,
        };
        let (v, _, slept) = run(&mut t, ATTEMPTS);
        assert_eq!(v, Some(json::loads(r#"{"ok": true}"#).unwrap()));
        assert_eq!((t.gh_calls, t.curl_calls), (2, 1));
        assert_eq!(slept.len(), 1);
    }

    #[test]
    fn curl_rescues_a_failed_gh_without_waiting() {
        let mut t = Script {
            has_gh: true,
            gh: vec![None].into(),
            curl: vec![Ok("[]")].into(),
            gh_calls: 0,
            curl_calls: 0,
        };
        let (v, _, slept) = run(&mut t, ATTEMPTS);
        assert_eq!(v, Some(json::loads("[]").unwrap()));
        assert!(slept.is_empty());
    }

    #[test]
    fn a_permanent_failure_is_not_retried() {
        for err in [
            CurlError::Http(404),
            CurlError::Http(401),
            CurlError::Http(403),
            CurlError::Http(422),
            CurlError::Network {
                code: Some(3),
                msg: "curl: (3) URL rejected".into(),
            },
            CurlError::Network {
                code: None,
                msg: "No such file or directory (os error 2)".into(),
            },
            CurlError::Body("Expecting value (char 0)".into()),
        ] {
            let mut t = Script::curl_only(vec![Err(err.clone())]);
            let (v, gave_up, slept) = run(&mut t, ATTEMPTS);
            assert_eq!(v, None, "{err}");
            assert!(!gave_up, "{err}");
            assert_eq!(t.curl_calls, 1, "{err} was retried");
            assert!(slept.is_empty(), "{err}");
        }
    }

    #[test]
    fn exhausted_retries_give_up_with_none() {
        let mut t = Script::curl_only(vec![
            Err(CurlError::Http(500)),
            Err(CurlError::Http(429)),
            Err(reset()),
        ]);
        let (v, gave_up, slept) = run(&mut t, ATTEMPTS);
        assert_eq!(v, None);
        assert!(gave_up);
        assert_eq!(t.curl_calls, 3);
        assert_eq!(slept.len(), 2);
    }

    #[test]
    fn after_giving_up_one_attempt_is_made() {
        let mut t = Script::curl_only(vec![Err(CurlError::Http(503))]);
        let (v, gave_up, slept) = run(&mut t, 1);
        assert_eq!((v, gave_up, slept.len(), t.curl_calls), (None, true, 0, 1));
    }

    #[test]
    fn transient_errors_are_classified() {
        for code in [408, 429, 500, 502, 503, 504, 599] {
            assert!(CurlError::Http(code).is_transient(), "{code}");
        }
        for code in [0, 400, 401, 403, 404, 410, 422] {
            assert!(!CurlError::Http(code).is_transient(), "{code}");
        }
        for code in [6, 7, 28, 35, 52, 56] {
            let e = CurlError::Network {
                code: Some(code),
                msg: String::new(),
            };
            assert!(e.is_transient(), "curl exit {code}");
        }
    }

    #[test]
    fn errors_read_the_way_urllib_words_them() {
        assert_eq!(
            CurlError::Http(404).to_string(),
            "HTTP Error 404: Not Found"
        );
        assert_eq!(
            reset().to_string(),
            "<urlopen error curl: (56) Recv failure: Connection reset by peer>"
        );
    }
}
