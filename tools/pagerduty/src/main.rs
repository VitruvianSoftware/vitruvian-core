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

//! `bazel run //tools/pagerduty:read -- <api-path>`: GET one PagerDuty API
//! path and print the JSON with contact details masked.

use std::io::Write;
use std::process::{exit, Command, Stdio};

fn token() -> Option<String> {
    for var in ["PAGERDUTY_TOKEN", "PAGERDUTY_API_KEY"] {
        if let Ok(t) = std::env::var(var) {
            if !t.trim().is_empty() {
                return Some(t.trim().to_string());
            }
        }
    }
    let home = std::env::var("HOME").ok()?;
    let t = std::fs::read_to_string(format!("{home}/.config/pagerduty/api-key")).ok()?;
    let t = t.trim().to_string();
    (!t.is_empty()).then_some(t)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [path] = args.as_slice() else {
        eprintln!("usage: bazel run //tools/pagerduty:read -- <api-path>   e.g. /schedules");
        exit(2);
    };
    let url = pagerduty::url_for(path).unwrap_or_else(|e| {
        eprintln!("pagerduty read: {e}");
        exit(2)
    });
    let Some(token) = token() else {
        eprintln!("pagerduty read: no token: set PAGERDUTY_TOKEN, or put a read key in ~/.config/pagerduty/api-key");
        exit(2);
    };

    // The token goes to curl on stdin (-K -), never on its command line, so
    // it does not show in the process list. -q first ignores any ~/.curlrc.
    let mut child = Command::new("curl")
        .args([
            "-q",
            "-sS",
            "--fail-with-body",
            "--max-time",
            "30",
            "-K",
            "-",
            "--url",
            &url,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| {
            eprintln!("pagerduty read: cannot run curl: {e}");
            exit(1)
        });
    let config = format!(
        "request = \"GET\"\nheader = \"Accept: application/json\"\nheader = \"Authorization: Token token={token}\"\n"
    );
    child
        .stdin
        .take()
        .unwrap()
        .write_all(config.as_bytes())
        .ok();
    let out = child.wait_with_output().unwrap_or_else(|e| {
        eprintln!("pagerduty read: curl failed: {e}");
        exit(1)
    });
    let mut body: serde_json::Value = match serde_json::from_slice(&out.stdout) {
        Ok(v) => v,
        Err(_) => {
            eprintln!(
                "pagerduty read: the API did not answer with JSON (curl exit {:?})",
                out.status.code()
            );
            exit(1)
        }
    };
    pagerduty::mask(&mut body);
    println!("{}", serde_json::to_string_pretty(&body).unwrap());
    if !out.status.success() {
        exit(1);
    }
}
