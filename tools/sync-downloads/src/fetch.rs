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

use std::io::Write;
use std::process::{Command, Stdio};

use crate::json::{self, Value};
use crate::pyerr::Crash;

/// What the script's `fetch_json` returns, or the exception it lets out.
pub fn fetch_json(endpoint: &str, token: Option<&str>) -> Result<Option<Value>, Crash> {
    let which = Command::new("which")
        .arg("gh")
        .stdin(Stdio::inherit())
        .output()
        .map_err(|e| Crash::os(&e, Some("which")))?;
    if which.status.success() {
        let res = Command::new("gh")
            .args(["api", endpoint])
            .stdin(Stdio::inherit())
            .output()
            .map_err(|e| Crash::os(&e, Some("gh")))?;
        if res.status.success() {
            let text = String::from_utf8(res.stdout).map_err(|e| {
                Crash::new(
                    "UnicodeDecodeError",
                    format!("'utf-8' codec can't decode bytes: {}", e),
                )
            })?;
            let text = text.replace("\r\n", "\n").replace('\r', "\n");
            return json::loads(&text)
                .map(Some)
                .map_err(|e| Crash::new("json.decoder.JSONDecodeError", e.to_string()));
        }
    }

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
    let result = curl_get(&url, &headers, 15).and_then(|body| {
        let text =
            String::from_utf8(body).map_err(|e| format!("'utf-8' codec can't decode: {}", e))?;
        json::loads(&text).map_err(|e| e.to_string())
    });
    match result {
        Ok(v) => Ok(Some(v)),
        Err(e) => {
            eprintln!("Warning: Failed to fetch {}: {}", url, e);
            Ok(None)
        }
    }
}

/// GET `url` with curl; the body on a 2xx, else the error as urllib words it.
fn curl_get(url: &str, headers: &[String], timeout: u32) -> Result<Vec<u8>, String> {
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
        .map_err(|e| format!("<urlopen error {}>", e))?;
    {
        let mut stdin = child.stdin.take().unwrap();
        let _ = stdin.write_all(headers.join("\n").as_bytes());
        let _ = stdin.write_all(b"\n");
    }
    let out = child
        .wait_with_output()
        .map_err(|e| format!("<urlopen error {}>", e))?;
    let pos = out.stdout.windows(MARK.len()).rposition(|w| w == MARK);
    if !out.status.success() || pos.is_none() {
        let msg = String::from_utf8_lossy(&out.stderr).trim().to_string();
        return Err(format!("<urlopen error {}>", msg));
    }
    let pos = pos.unwrap();
    let code: u16 = String::from_utf8_lossy(&out.stdout[pos + MARK.len()..])
        .trim()
        .parse()
        .unwrap_or(0);
    if !(200..300).contains(&code) {
        return Err(format!("HTTP Error {}: {}", code, reason(code)));
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
