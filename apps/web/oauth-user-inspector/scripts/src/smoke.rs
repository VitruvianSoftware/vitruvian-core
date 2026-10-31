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

//! Candidate smoke for oauth-user-inspector: reachable AND the React SPA
//! actually mounts. index.html is a static shell that 200s even when the
//! bundle throws on mount (how the 2026-06-27 react/react-dom mismatch reached
//! prod past an HTTP-200-only check), so a plain curl is not enough. `CAND` is
//! the candidate revision's dedicated URL, exported by //tools/deploy:cloud-run.
//!
//! Single source of truth for the oauth smoke: the local `:deploy` target
//! (infra/app/BUILD) and the delivery workflow both run
//! `bazel run //apps/web/oauth-user-inspector:smoke`.
//!
//! Replaced `infra/app/smoke.sh`, which //tools/deploy ran as `bash -c`
//! WITHOUT errexit, and keeps its exact behaviour:
//! - curl's result does not decide anything (it warms the revision up, with
//!   retries); the DOM check is the gate.
//! - Chrome is found the way bash's `command -v` finds it, including its
//!   fallback to a non-executable match, which then fails to start.
//! - The DOM is what `$(...)` captured: NUL bytes dropped, trailing newlines
//!   stripped, everything else byte for byte.

use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

const CHROME_CANDIDATES: &[&str] = &["google-chrome-stable", "google-chrome", "chromium-browser"];
const MOUNTED: &[u8] = b"Select a provider";

/// bash's PATH search for `command -v NAME`: the first executable regular file;
/// failing that, the first non-directory file it saw (bash reports it anyway).
pub fn command_v(name: &str, path_var: Option<OsString>) -> Option<PathBuf> {
    let path_var = path_var?;
    let mut fallback = None;
    for dir in env::split_paths(&path_var) {
        let dir = if dir.as_os_str().is_empty() {
            PathBuf::from(".")
        } else {
            dir
        };
        let candidate = dir.join(name);
        let Ok(meta) = fs::metadata(&candidate) else {
            continue;
        };
        if meta.is_dir() {
            continue;
        }
        if meta.permissions().mode() & 0o111 != 0 {
            return Some(candidate);
        }
        fallback.get_or_insert(candidate);
    }
    fallback
}

pub fn find_chrome_binary<F: Fn(&str) -> Option<PathBuf>>(lookup: F) -> Option<PathBuf> {
    CHROME_CANDIDATES.iter().find_map(|c| lookup(c))
}

/// `DOM="$(...)"`: NUL bytes dropped, trailing newlines stripped.
pub fn as_captured(mut raw: Vec<u8>) -> Vec<u8> {
    raw.retain(|&b| b != 0);
    while raw.last() == Some(&b'\n') {
        raw.pop();
    }
    raw
}

/// `printf '%s' "$DOM" | grep -q "Select a provider"`.
pub fn mounted(dom: &[u8]) -> bool {
    dom.windows(MOUNTED.len()).any(|w| w == MOUNTED)
}

pub fn run(_args: &[String]) -> i32 {
    let cand = env::var_os("CAND").unwrap_or_default();
    if cand.is_empty() {
        println!("Service is disabled or candidate URL is empty — skipping smoke check.");
        return 0;
    }
    let mut url = cand;
    url.push("/");

    println!("Smoke-checking {}", url.to_string_lossy());
    let _ = io::stdout().flush();
    let _ = Command::new("curl")
        .args([
            "--fail",
            "--retry",
            "10",
            "--retry-delay",
            "5",
            "--retry-connrefused",
        ])
        .arg(&url)
        .stdout(Stdio::null())
        .status();

    let Some(chrome) = find_chrome_binary(|c| command_v(c, env::var_os("PATH"))) else {
        println!("::error::no headless Chrome available -- cannot verify the app mounts");
        return 1;
    };

    let raw = Command::new(&chrome)
        .args([
            "--headless=new",
            "--no-sandbox",
            "--disable-gpu",
            "--virtual-time-budget=10000",
            "--dump-dom",
        ])
        .arg(&url)
        .stderr(Stdio::null())
        .output()
        .map(|o| o.stdout)
        .unwrap_or_default();
    let dom = as_captured(raw);

    let mut stdout = io::stdout().lock();
    if mounted(&dom) {
        let _ = stdout.write_all(b"Smoke OK: React app mounted.\n");
        0
    } else {
        let _ = stdout.write_all(
            b"::error::App did NOT mount -- served only the static fallback (broken frontend bundle).\n",
        );
        let _ = stdout.write_all(&dom[..dom.len().min(800)]);
        let _ = stdout.flush();
        1
    }
}
