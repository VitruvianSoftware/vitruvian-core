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

//! Asking a registry. The standard library has no TLS, so a live request
//! is made by `curl`, given everything on its standard input (`--config -`):
//! nothing, the cargo token least of all, is ever on a command line where
//! `ps` would show it. `-q` keeps a user's .curlrc out of it.
//!
//! Under `bazel test`, REGISTRY_TRUST_RECORDED names a file of recorded
//! answers, and nothing touches the network: the parity test gives the
//! port and the scripts the same answers. Outside a test it is refused, so
//! a recording can never stand in for a registry in a real run.

use std::io::Write;
use std::process::{Command, Stdio};

use crate::json::{self, Value};
use crate::py;

/// crates.io refuses a request that does not say who is asking.
pub const USER_AGENT: &str =
    "VitruvianSoftware/vitruvian-core registry-trust (github.com/VitruvianSoftware/vitruvian-core)";
pub const HOSTS: [&str; 3] = ["registry.npmjs.org", "crates.io", "pypi.org"];
pub const ATTEMPTS: u64 = 4;

/// A registry gave no usable answer. Never read as "nothing is wrong".
#[derive(Debug, Clone, PartialEq)]
pub struct RegistryError(pub String);

impl std::fmt::Display for RegistryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Request {
    pub method: String,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
    /// Whether a redirect is followed (urllib's opener follows them; the
    /// request that carries the cargo token never does).
    pub follow: bool,
}

impl Request {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

/// `check.request_for`: a GET that says who is asking, and nothing else.
pub fn request_for(url: &str) -> Result<Request, String> {
    let (_, host) = py::split_url(url);
    if !host.as_deref().is_some_and(|h| HOSTS.contains(&h)) {
        return Err(format!("{url} is not one of the three registries"));
    }
    Ok(Request {
        method: "GET".into(),
        url: url.into(),
        headers: vec![
            ("User-Agent".into(), USER_AGENT.into()),
            ("Accept".into(), "application/json".into()),
        ],
        body: None,
        follow: true,
    })
}

pub type Answer = (u16, Vec<u8>);

/// `check.http_fetch`: (status, body). Asks again when the registry is
/// briefly down (5xx, 429, or no answer at all), so one blip is not a red
/// run; an answer of "not there" is an answer.
pub fn http_fetch_with(
    url: &str,
    opener: &mut dyn FnMut(&Request) -> Result<Answer, String>,
    sleep: &mut dyn FnMut(u64),
) -> Result<Answer, RegistryError> {
    let request = request_for(url).map_err(RegistryError)?;
    let mut status: Option<u16> = None;
    let mut body: Vec<u8> = Vec::new();
    for attempt in 0..ATTEMPTS {
        if attempt > 0 {
            sleep(2 * attempt);
        }
        match opener(&request) {
            Ok((code, text)) => {
                if code < 500 && code != 429 {
                    return Ok((code, text));
                }
                status = Some(code);
                body = text;
            }
            Err(message) => {
                status = None;
                body = message.into_bytes();
            }
        }
    }
    match status {
        None => Err(RegistryError(format!(
            "{url} could not be reached: {}",
            String::from_utf8_lossy(&body)
        ))),
        Some(code) => Ok((code, body)),
    }
}

/// A value inside double quotes in a curl config file.
fn config_quote(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
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

/// The curl config that makes one request: what goes on its stdin.
pub fn curl_config(request: &Request) -> String {
    let mut lines = vec![
        format!("url = {}", config_quote(&request.url)),
        "silent".to_string(),
        "show-error".to_string(),
        "proto = \"=https\"".to_string(),
        "connect-timeout = 30".to_string(),
        // urllib's timeout is per socket operation: give up when nothing
        // arrives for 30 seconds, not when a big answer takes longer.
        "speed-limit = 1".to_string(),
        "speed-time = 30".to_string(),
        "write-out = \"\\n%{http_code}\"".to_string(),
    ];
    if request.follow {
        lines.push("location".into());
        lines.push("proto-redir = \"=https\"".into());
        lines.push("max-redirs = 10".into());
    }
    if request.method != "GET" {
        lines.push(format!("request = {}", config_quote(&request.method)));
    }
    for (name, value) in &request.headers {
        lines.push(format!(
            "header = {}",
            config_quote(&format!("{name}: {value}"))
        ));
    }
    if let Some(body) = &request.body {
        lines.push(format!(
            "data-binary = {}",
            config_quote(&String::from_utf8_lossy(body))
        ));
    }
    lines.join("\n") + "\n"
}

/// One request, made by curl. Err is "no answer", with curl's reason.
pub fn curl_open(request: &Request) -> Result<Answer, String> {
    let mut child = Command::new("curl")
        .args(["-q", "--config", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("curl could not be run: {e}"))?;
    let config = curl_config(request);
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(config.as_bytes());
    }
    let output = child
        .wait_with_output()
        .map_err(|e| format!("curl failed: {e}"))?;
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if !output.status.success() {
        return Err(if stderr.is_empty() {
            format!("curl {}", output.status)
        } else {
            stderr
        });
    }
    let stdout = output.stdout;
    let cut = stdout
        .iter()
        .rposition(|&b| b == b'\n')
        .ok_or("curl gave no status")?;
    let code: u16 = std::str::from_utf8(&stdout[cut + 1..])
        .ok()
        .and_then(|c| c.trim().parse().ok())
        .filter(|&c| c != 0)
        .ok_or_else(|| {
            if stderr.is_empty() {
                "no HTTP status".to_string()
            } else {
                stderr.clone()
            }
        })?;
    Ok((code, stdout[..cut].to_vec()))
}

/// The real fetch: curl, retried, with real sleeps.
pub fn http_fetch(url: &str) -> Result<Answer, RegistryError> {
    http_fetch_with(url, &mut curl_open, &mut |s| {
        std::thread::sleep(std::time::Duration::from_secs(s))
    })
}

// --- recorded answers, for the parity test ----------------------------------

/// `{"fetch": {url: [status, body]}, "send": {"METHOD url": [status, body]},
///   "token": what the cargo token should be, "log": a file to append to}`
pub struct Recorded {
    data: Value,
}

impl Recorded {
    pub fn load(path: &str) -> Result<Recorded, String> {
        let text = py::read_text(path).map_err(|e| e.to_string())?;
        let data = json::loads(&text).map_err(|e| format!("{path}: {e}"))?;
        Ok(Recorded { data })
    }

    fn answer(&self, table: &str, key: &str) -> Answer {
        let Some(Value::List(pair)) = self.data.get(table).and_then(|t| t.get(key)) else {
            eprintln!("registry-trust: no recorded answer for {key}");
            std::process::exit(3);
        };
        let status = match pair.first() {
            Some(Value::Int(n)) => n.parse().unwrap_or(0),
            _ => 0,
        };
        let body = pair
            .get(1)
            .and_then(Value::as_str)
            .unwrap_or("")
            .as_bytes()
            .to_vec();
        (status, body)
    }

    fn log(&self, entry: Value) {
        let Some(path) = self.data.get("log").and_then(Value::as_str) else {
            return;
        };
        if let Ok(mut file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
        {
            let _ = writeln!(file, "{}", json::dumps(&entry));
        }
    }

    pub fn fetch(&self, url: &str) -> Result<Answer, RegistryError> {
        self.log(Value::List(vec![json::s("fetch"), json::s(url)]));
        Ok(self.answer("fetch", url))
    }

    /// The token is compared, never written: the log says only whether it
    /// was the expected one.
    pub fn send(&self, method: &str, url: &str, token: &str, body: Option<&Value>) -> Answer {
        let expected = self.data.get("token").and_then(Value::as_str);
        self.log(Value::List(vec![
            json::s("send"),
            json::s(method),
            json::s(url),
            Value::Bool(expected == Some(token)),
            body.cloned().unwrap_or(Value::Null),
        ]));
        self.answer("send", &format!("{method} {url}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_request_says_who_is_asking_and_carries_nothing_else() {
        let request =
            request_for("https://crates.io/api/v1/crates/x/versions?per_page=100").unwrap();
        let agent = request.header("user-agent").unwrap();
        assert!(agent.contains("VitruvianSoftware/vitruvian-core"));
        assert!(agent.contains("registry-trust"));
        assert_eq!(request.method, "GET");
        assert_eq!(request.header("Authorization"), None);
        assert!(request.body.is_none());
    }

    #[test]
    fn only_the_three_registries_are_ever_asked() {
        assert!(request_for("https://example.com/x").is_err());
        assert!(request_for("https://crates.io.example.com/x").is_err());
        assert!(request_for("https://pypi.org/pypi/x/json").is_ok());
    }

    fn fetch(statuses: &[Option<u16>]) -> (Result<Answer, RegistryError>, usize, Vec<u64>) {
        let mut asked = 0;
        let mut slept = Vec::new();
        let result = http_fetch_with(
            "https://registry.npmjs.org/x",
            &mut |_| {
                asked += 1;
                match statuses[asked - 1] {
                    None => Err("no route".into()),
                    Some(code) => Ok((code, b"{}".to_vec())),
                }
            },
            &mut |s| slept.push(s),
        );
        (result, asked, slept)
    }

    #[test]
    fn a_registry_that_is_briefly_down_is_asked_again() {
        let (result, asked, slept) = fetch(&[Some(503), None, Some(200)]);
        assert_eq!(result.unwrap().0, 200);
        assert_eq!(asked, 3);
        assert_eq!(slept, [2, 4]);
    }

    #[test]
    fn not_there_is_an_answer_and_is_not_asked_twice() {
        let (result, asked, _) = fetch(&[Some(404)]);
        assert_eq!((result.unwrap().0, asked), (404, 1));
        let (result, asked, _) = fetch(&[Some(429), Some(403)]);
        assert_eq!((result.unwrap().0, asked), (403, 2));
    }

    #[test]
    fn a_registry_that_stays_down_is_an_error_not_a_guess() {
        let (result, asked, _) = fetch(&[None, None, None, None]);
        assert_eq!(asked, 4);
        assert_eq!(
            result.unwrap_err().0,
            "https://registry.npmjs.org/x could not be reached: no route"
        );
        let (result, asked, _) = fetch(&[Some(503); 4]);
        assert_eq!((result.unwrap().0, asked), (503, 4));
    }

    #[test]
    fn the_token_goes_on_stdin_and_redirects_only_where_allowed() {
        let mut request = request_for("https://crates.io/api/v1/x").unwrap();
        request
            .headers
            .push(("Authorization".into(), "se\"cret".into()));
        request.method = "POST".into();
        request.body = Some(br#"{"a": "b\\c"}"#.to_vec());
        request.follow = false;
        let config = curl_config(&request);
        assert!(
            config.contains("header = \"Authorization: se\\\"cret\"\n"),
            "{config}"
        );
        assert!(
            config.contains("data-binary = \"{\\\"a\\\": \\\"b\\\\\\\\c\\\"}\"\n"),
            "{config}"
        );
        assert!(config.contains("request = \"POST\"\n"));
        assert!(!config.contains("location"));
        assert!(config.contains("proto = \"=https\""));
    }
}
