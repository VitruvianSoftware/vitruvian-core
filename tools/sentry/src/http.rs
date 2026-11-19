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

//! HTTP transport over `curl` with stdin-only credentials and a private
//! cookie jar in a temporary directory cleaned up on drop.

use std::fs::{self, DirBuilder, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const DEFAULT_TIMEOUT_SECS: u64 = 30;
const STATUS_MARKER: &[u8] = b"\n__sentry_pagerduty_install_status__";

static TEMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
}

pub trait HttpClient {
    fn request(&mut self, method: &str, url: &str, body: Option<&str>) -> Result<Response, String>;
}

/// Signal guard so Ctrl-C / SIGTERM / SIGHUP unwind cleanly through `Drop`
/// rather than leaving the cookie jar directory behind.
pub mod signals {
    use std::sync::atomic::{AtomicBool, Ordering};

    static INTERRUPTED: AtomicBool = AtomicBool::new(false);
    const SIGHUP: i32 = 1;
    const SIGINT: i32 = 2;
    const SIGTERM: i32 = 15;

    extern "C" {
        fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
    }

    extern "C" fn record(_: i32) {
        INTERRUPTED.store(true, Ordering::SeqCst);
    }

    pub fn install() {
        for s in [SIGHUP, SIGINT, SIGTERM] {
            // SAFETY: `record` only writes an atomic bool, which is async-signal-safe.
            unsafe {
                signal(s, record);
            }
        }
    }

    pub fn interrupted() -> bool {
        INTERRUPTED.load(Ordering::SeqCst)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthHeader {
    Bearer(String),
    SentryAuth { public_key: String, client: String },
}

impl AuthHeader {
    pub fn header_line(&self) -> String {
        match self {
            Self::Bearer(token) => format!("Authorization: Bearer {token}"),
            Self::SentryAuth { public_key, client } => format!(
                "X-Sentry-Auth: Sentry sentry_version=7, sentry_key={public_key}, sentry_client={client}"
            ),
        }
    }

    pub fn secret(&self) -> &str {
        match self {
            Self::Bearer(token) => token,
            Self::SentryAuth { public_key, .. } => public_key,
        }
    }
}

pub struct CurlClient {
    curl_bin: String,
    auth: AuthHeader,
    content_type: String,
    extra_headers: Vec<String>,
    temp_dir: PathBuf,
    cookie_jar: PathBuf,
    timeout_secs: u64,
}

impl CurlClient {
    pub fn new(curl_bin: impl Into<String>, auth: AuthHeader) -> Result<Self, String> {
        signals::install();

        let base = safe_temp_base();
        let pid = std::process::id();
        let temp_dir = loop {
            let seq = TEMP_COUNTER.fetch_add(1, Ordering::SeqCst);
            let candidate = base.join(format!("sentry-pagerduty-install-{pid}-{seq}"));
            match DirBuilder::new()
                .recursive(false)
                .mode(0o700)
                .create(&candidate)
            {
                Ok(()) => break candidate,
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => {
                    return Err(format!(
                        "failed to create temp directory {}: {e}",
                        candidate.display()
                    ))
                }
            }
        };

        let cookie_jar = temp_dir.join("cookies.txt");
        if let Err(e) = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&cookie_jar)
        {
            let _ = fs::remove_dir_all(&temp_dir);
            return Err(format!(
                "failed to create cookie jar {}: {e}",
                cookie_jar.display()
            ));
        }

        Ok(Self {
            curl_bin: curl_bin.into(),
            auth,
            content_type: "application/json".into(),
            extra_headers: Vec::new(),
            temp_dir,
            cookie_jar,
            timeout_secs: DEFAULT_TIMEOUT_SECS,
        })
    }

    pub fn with_content_type(mut self, content_type: impl Into<String>) -> Self {
        self.content_type = content_type.into();
        self
    }

    pub fn with_header(mut self, header: impl Into<String>) -> Self {
        self.extra_headers.push(header.into());
        self
    }

    pub fn temp_dir(&self) -> &Path {
        &self.temp_dir
    }

    pub fn cookie_jar(&self) -> &Path {
        &self.cookie_jar
    }
}

impl Drop for CurlClient {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.temp_dir);
    }
}

/// `curl --cookie <arg>` treats any argument containing `'='` as a literal
/// `key=value` cookie rather than a filename, so reject temp roots with `'='`
/// or line breaks.
fn safe_temp_base() -> PathBuf {
    let candidate = std::env::temp_dir();
    let ok = candidate
        .to_str()
        .is_some_and(|s| !s.contains('=') && !s.contains('\n') && !s.contains('\r'));
    if ok {
        candidate
    } else {
        PathBuf::from("/tmp")
    }
}

/// Quote a string for a `curl -K` config file.
pub fn quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
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

pub fn redact(text: &str, token: &str) -> String {
    if token.is_empty() {
        text.to_string()
    } else {
        text.replace(token, "<redacted>")
    }
}

impl HttpClient for CurlClient {
    fn request(&mut self, method: &str, url: &str, body: Option<&str>) -> Result<Response, String> {
        if signals::interrupted() {
            return Err("interrupted".into());
        }
        if !url.starts_with("https://") || url.chars().any(|c| c.is_control() || c.is_whitespace())
        {
            return Err("refusing non-https or malformed URL".into());
        }

        let jar = self.cookie_jar.to_string_lossy();
        let mut config = String::new();
        config.push_str(&format!("url = {}\n", quote(url)));
        config.push_str(&format!("request = {}\n", quote(method)));
        config.push_str(&format!("max-time = {}\n", self.timeout_secs));
        config.push_str(&format!("cookie = {}\n", quote(&jar)));
        config.push_str(&format!("cookie-jar = {}\n", quote(&jar)));
        config.push_str(&format!("header = {}\n", quote(&self.auth.header_line())));
        config.push_str("header = \"Accept: application/json\"\n");
        for h in &self.extra_headers {
            config.push_str(&format!("header = {}\n", quote(h)));
        }
        if let Some(b) = body {
            config.push_str(&format!(
                "header = {}\n",
                quote(&format!("Content-Type: {}", self.content_type))
            ));
            config.push_str(&format!("data-binary = {}\n", quote(b)));
        }
        config.push_str("write-out = \"\\n__sentry_pagerduty_install_status__%{http_code}\"\n");

        let mut child = Command::new(&self.curl_bin)
            // -q first: ignore ~/.curlrc, so no personal config can turn off
            // TLS checks or add a proxy for a request that carries credentials.
            .args(["-q", "-sS", "-K", "-"])
            // Credentials reach curl only through the stdin config; keep them
            // out of the child's environment (readable via ps eww).
            .env_remove("SENTRY_TOKEN")
            .env_remove("SENTRY_CI_TOKEN")
            .env_remove("SENTRY_DSN")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| {
                redact(
                    &format!("failed to start {}: {e}", self.curl_bin),
                    self.auth.secret(),
                )
            })?;

        if let Some(mut stdin) = child.stdin.take() {
            if let Err(e) = stdin.write_all(config.as_bytes()) {
                if e.kind() != std::io::ErrorKind::BrokenPipe {
                    return Err(redact(
                        &format!("failed to write curl config to stdin: {e}"),
                        self.auth.secret(),
                    ));
                }
            }
        }

        let out = child
            .wait_with_output()
            .map_err(|e| redact(&format!("curl wait failed: {e}"), self.auth.secret()))?;

        if self.cookie_jar.exists() {
            let _ = fs::set_permissions(&self.cookie_jar, fs::Permissions::from_mode(0o600));
        }

        let pos = out
            .stdout
            .windows(STATUS_MARKER.len())
            .rposition(|w| w == STATUS_MARKER);

        let pos = match (out.status.success(), pos) {
            (true, Some(p)) => p,
            _ => {
                let err_msg = String::from_utf8_lossy(&out.stderr);
                let trimmed = err_msg.trim();
                let msg = if trimmed.is_empty() {
                    format!("curl failed (exit {})", out.status.code().unwrap_or(1))
                } else {
                    trimmed.to_string()
                };
                return Err(redact(&msg, self.auth.secret()));
            }
        };

        let status: u16 = String::from_utf8_lossy(&out.stdout[pos + STATUS_MARKER.len()..])
            .trim()
            .parse()
            .unwrap_or(0);
        if status == 0 {
            return Err("curl returned HTTP status 0".into());
        }

        Ok(Response {
            status,
            body: out.stdout[..pos].to_vec(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::MetadataExt;

    #[test]
    fn quote_escapes_special_chars() {
        assert_eq!(quote(r#"a"b\c"#), r#""a\"b\\c""#);
        assert_eq!(quote("x\ny\rz\tw"), r#""x\ny\rz\tw""#);
    }

    #[test]
    fn redact_scrubs_token() {
        assert_eq!(
            redact("bad header sntryu_secret123 failed", "sntryu_secret123"),
            "bad header <redacted> failed"
        );
    }

    #[test]
    fn auth_header_formats_bearer_and_sentry_auth() {
        let bearer = AuthHeader::Bearer("sntryu_abc".into());
        assert_eq!(bearer.header_line(), "Authorization: Bearer sntryu_abc");
        assert_eq!(bearer.secret(), "sntryu_abc");

        let sentry = AuthHeader::SentryAuth {
            public_key: "pub123".into(),
            client: "vitruvian-send-test-event/1.0".into(),
        };
        assert_eq!(
            sentry.header_line(),
            "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=pub123, sentry_client=vitruvian-send-test-event/1.0"
        );
        assert_eq!(sentry.secret(), "pub123");
    }

    #[test]
    fn curl_client_rejects_non_https_urls_without_invoking_curl() {
        let mut client = CurlClient::new(
            "/nonexistent/curl",
            AuthHeader::SentryAuth {
                public_key: "pub123".into(),
                client: "vitruvian-send-test-event/1.0".into(),
            },
        )
        .unwrap();

        let err = client
            .request("POST", "http://sentry.example/api/1/envelope/", Some("{}"))
            .unwrap_err();
        assert!(err.contains("non-https"), "{err}");

        let err_ws = client
            .request(
                "POST",
                "https://sentry.example/api/1/envelope/ bad",
                Some("{}"),
            )
            .unwrap_err();
        assert!(err_ws.contains("malformed"), "{err_ws}");
    }

    #[test]
    fn curl_client_creates_0600_cookie_jar_and_cleans_up_on_drop() {
        let client = CurlClient::new("curl", AuthHeader::Bearer("sntryu_test".into())).unwrap();
        let dir = client.temp_dir().to_path_buf();
        let jar = client.cookie_jar().to_path_buf();

        assert!(dir.is_dir());
        assert!(jar.is_file());
        assert_eq!(fs::metadata(&dir).unwrap().mode() & 0o777, 0o700);
        assert_eq!(fs::metadata(&jar).unwrap().mode() & 0o777, 0o600);

        drop(client);
        assert!(!dir.exists());
        assert!(!jar.exists());
    }
}
