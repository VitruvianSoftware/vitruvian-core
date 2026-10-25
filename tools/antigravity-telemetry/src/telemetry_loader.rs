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

//! Self-updating loader shim (`telemetry_loader.py`).
//!
//! Runs a cached copy of the Python hook engine (`~/.gemini/hooks/.engine.py`),
//! fetching it from GitHub on first use and refreshing it in the background
//! once it is a day old. Whatever happens, the agent gets an answer:
//! the engine's own output, or `{"decision": "allow"}`.
//!
//! Python ran the engine with its own interpreter (`sys.executable`); this
//! runs `$ANTIGRAVITY_TELEMETRY_PYTHON`, else `python3` from `PATH`. The three
//! download attempts (urllib verified, urllib unverified, curl) become curl
//! verified, curl unverified, plain curl, since std has no TLS.

use crate::sys;
use std::io::{Read, Write};

pub const DEFAULT_HOOK_SOURCE_URL: &str =
    "https://raw.githubusercontent.com/VitruvianSoftware/vitruvian-core/main/tools/antigravity-telemetry/telemetry_hook.py";
const USER_AGENT: &str = "antigravity-telemetry-loader/1.0.0";
pub const CACHE_TTL_SECONDS: f64 = 86400.0;
const MARKER: &[u8] = b"process_event";

pub fn raw_hook_url() -> String {
    std::env::var("ANTIGRAVITY_HOOK_SOURCE_URL")
        .unwrap_or_else(|_| DEFAULT_HOOK_SOURCE_URL.to_string())
}

pub fn cache_file() -> String {
    sys::join(&sys::expanduser("~/.gemini/hooks"), ".engine.py")
}

fn python() -> String {
    std::env::var("ANTIGRAVITY_TELEMETRY_PYTHON")
        .ok()
        .filter(|p| !p.is_empty())
        .unwrap_or_else(|| "python3".to_string())
}

fn curl(url: &str, timeout: f64, extra: &[&str]) -> Option<Vec<u8>> {
    let secs = format!("{}", timeout as i64);
    let mut argv = vec!["curl", "-sSL", "-m", secs.as_str(), "-A", USER_AGENT];
    argv.extend_from_slice(extra);
    argv.push(url);
    match sys::run(&argv, None, Some(timeout)) {
        Ok(o) if o.code == 0 && !o.stdout.is_empty() => Some(o.stdout),
        _ => None,
    }
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// Download the hook engine and atomically replace the cache. Only content
/// that looks like the engine (mentions `process_event`) is accepted.
pub fn download_engine(target_path: &str, timeout: f64) -> bool {
    let url = raw_hook_url();
    let tmp_path = format!("{}.tmp.{}", target_path, std::process::id());
    let good = |c: &Option<Vec<u8>>| c.as_ref().map(|b| contains(b, MARKER)).unwrap_or(false);

    // Attempt 1: verified, success status only.
    let mut content = curl(&url, timeout, &["-f"]);
    // Attempt 2: unverified.
    if !good(&content) {
        if let Some(c) = curl(&url, timeout, &["-f", "-k"]) {
            content = Some(c);
        }
    }
    // Attempt 3: plain curl, whatever the status.
    if !good(&content) {
        if let Some(c) = curl(&url, timeout, &[]) {
            content = Some(c);
        }
    }

    let Some(content) = content.filter(|c| contains(c, MARKER)) else {
        return false;
    };
    let write = || -> std::io::Result<()> {
        use std::os::unix::fs::PermissionsExt;
        std::fs::create_dir_all(sys::dirname(target_path))?;
        std::fs::write(&tmp_path, &content)?;
        std::fs::set_permissions(&tmp_path, std::fs::Permissions::from_mode(0o755))?;
        std::fs::rename(&tmp_path, target_path)
    };
    let ok = write().is_ok();
    if std::path::Path::new(&tmp_path).exists() {
        let _ = std::fs::remove_file(&tmp_path);
    }
    ok
}

fn non_empty_file(path: &str) -> bool {
    std::fs::metadata(path)
        .map(|m| m.len() > 0)
        .unwrap_or(false)
}

/// Exit status as Python's `sys.exit(returncode)` reports it: a negative
/// (signal) return code wraps modulo 256.
fn exit_code(code: i32) -> i32 {
    code.rem_euclid(256)
}

pub fn main() -> i32 {
    let mut raw_input = Vec::new();
    let _ = std::io::stdin().read_to_end(&mut raw_input);

    let cache = cache_file();
    if !non_empty_file(&cache) {
        // First use: fetch synchronously.
        download_engine(&cache, 2.0);
    } else if sys::mtime(&cache)
        .map(|m| sys::now_secs() - m > CACHE_TTL_SECONDS)
        .unwrap_or(false)
    {
        // Stale: refresh in the background. Like Python's daemon thread, it
        // only finishes if the engine run below takes long enough.
        let target = cache.clone();
        std::thread::spawn(move || {
            download_engine(&target, 3.0);
        });
    }

    if non_empty_file(&cache) {
        let py = python();
        if let Ok(out) = sys::run(&[py.as_str(), cache.as_str()], Some(&raw_input), Some(5.0)) {
            if !out.stdout.is_empty() {
                let mut stdout = std::io::stdout();
                let _ = stdout.write_all(&out.stdout);
                let _ = stdout.flush();
                return exit_code(out.code);
            }
        }
    }

    let mut stdout = std::io::stdout();
    let _ = stdout.write_all(b"{\"decision\": \"allow\"}\n");
    let _ = stdout.flush();
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exit_codes_wrap_like_python() {
        assert_eq!(exit_code(0), 0);
        assert_eq!(exit_code(3), 3);
        assert_eq!(exit_code(-9), 247);
    }

    #[test]
    fn marker_search() {
        assert!(contains(b"def process_event(data):", MARKER));
        assert!(!contains(b"404: Not Found", MARKER));
    }
}
