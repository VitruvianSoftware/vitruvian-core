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

//! `bazel run //tools/pagerduty:resolve-incident -- <incident-id> --from <email>`:
//! resolve one PagerDuty incident, for example a test page. Long-lived
//! account configuration still belongs to the PagerDuty Pulumi stack.

use std::io::Write;
use std::process::{exit, Command, Stdio};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (id, from) = match args.as_slice() {
        [id, flag, from] if flag == "--from" => (id.clone(), from.clone()),
        _ => {
            eprintln!("usage: bazel run //tools/pagerduty:resolve-incident -- <incident-id> --from <email>");
            exit(2);
        }
    };
    if !pagerduty::is_object_id(&id) {
        eprintln!("pagerduty resolve: {id:?} is not a PagerDuty incident id (upper-case letters and digits)");
        exit(2);
    }
    if !pagerduty::is_from_email(&from) {
        eprintln!("pagerduty resolve: --from must be the email of a PagerDuty user (PagerDuty requires it)");
        exit(2);
    }
    // A write: only an explicitly exported key, never the read-key file.
    let token = match std::env::var("PAGERDUTY_TOKEN") {
        Ok(t) if !t.trim().is_empty() => t.trim().to_string(),
        _ => {
            eprintln!("pagerduty resolve: set PAGERDUTY_TOKEN to a key that can write incidents (Bitwarden item vitruviansoftware.pagerduty.com)");
            exit(2);
        }
    };
    let url = format!("{}/incidents/{id}", pagerduty::API_BASE);

    // Token and body go to curl on stdin (-K -), never on its command line;
    // -q ignores ~/.curlrc; the child gets no PAGERDUTY_TOKEN in its env.
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
        .env_remove("PAGERDUTY_TOKEN")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| {
            eprintln!("pagerduty resolve: cannot run curl: {e}");
            exit(1)
        });
    let body = pagerduty::resolve_body()
        .replace('\\', "\\\\")
        .replace('"', "\\\"");
    let config = format!(
        "request = \"PUT\"\nheader = \"Accept: application/json\"\nheader = \"Content-Type: application/json\"\nheader = \"From: {from}\"\nheader = \"Authorization: Token token={token}\"\ndata = \"{body}\"\n"
    );
    child
        .stdin
        .take()
        .unwrap()
        .write_all(config.as_bytes())
        .ok();
    let out = child.wait_with_output().unwrap_or_else(|e| {
        eprintln!("pagerduty resolve: curl failed: {e}");
        exit(1)
    });
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap_or_default();
    if !out.status.success() {
        let msg = v["error"]["message"].as_str().unwrap_or("request failed");
        eprintln!(
            "pagerduty resolve: {msg} (curl exit {:?})",
            out.status.code()
        );
        exit(1);
    }
    let inc = &v["incident"];
    println!(
        "resolved: #{} {} status={}",
        inc["incident_number"],
        inc["id"].as_str().unwrap_or(&id),
        inc["status"].as_str().unwrap_or("?")
    );
}
