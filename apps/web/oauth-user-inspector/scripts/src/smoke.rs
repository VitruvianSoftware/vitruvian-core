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

use std::env;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

const CHROME_CANDIDATES: &[&str] = &["google-chrome-stable", "google-chrome", "chromium-browser"];

fn command_exists(name: &str) -> bool {
    let Some(path_var) = env::var_os("PATH") else {
        return false;
    };
    for dir in env::split_paths(&path_var) {
        let candidate = dir.join(name);
        if let Ok(meta) = fs::metadata(&candidate) {
            if meta.is_file() && (meta.permissions().mode() & 0o111 != 0) {
                return true;
            }
        }
    }
    false
}

pub fn find_chrome_binary<F: Fn(&str) -> bool>(exists: F) -> Option<String> {
    for candidate in CHROME_CANDIDATES {
        if exists(candidate) {
            return Some(candidate.to_string());
        }
    }
    None
}

pub fn run(_args: &[String]) -> i32 {
    let cand = env::var("CAND").unwrap_or_default();
    if cand.is_empty() {
        println!("Service is disabled or candidate URL is empty — skipping smoke check.");
        return 0;
    }

    let url = format!("{}/", cand);
    println!("Smoke-checking {}", url);

    let curl_ok = Command::new("curl")
        .args([
            "--fail",
            "--retry",
            "10",
            "--retry-delay",
            "5",
            "--retry-connrefused",
            &url,
        ])
        .stdout(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !curl_ok {
        return 1;
    }

    let chrome = match find_chrome_binary(command_exists) {
        Some(c) => c,
        None => {
            println!("::error::no headless Chrome available -- cannot verify the app mounts");
            return 1;
        }
    };

    let dom_output = Command::new(&chrome)
        .args([
            "--headless=new",
            "--no-sandbox",
            "--disable-gpu",
            "--virtual-time-budget=10000",
            "--dump-dom",
            &url,
        ])
        .stderr(std::process::Stdio::null())
        .output();

    let dom = match dom_output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).to_string(),
        Err(_) => String::new(),
    };

    if dom.contains("Select a provider") {
        println!("Smoke OK: React app mounted.");
        0
    } else {
        println!("::error::App did NOT mount -- served only the static fallback (broken frontend bundle).");
        let bytes = dom.as_bytes();
        let take = bytes.len().min(800);
        let _ = io::stdout().write_all(&bytes[..take]);
        let _ = io::stdout().flush();
        1
    }
}
