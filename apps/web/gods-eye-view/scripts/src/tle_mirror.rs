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

use std::collections::BTreeSet;
use std::path::Path;
use std::process::Command;
use std::time::Duration;

pub const MIRRORED_GROUPS: &[&str] = &[
    "active",
    "stations",
    "visual",
    "gps-ops",
    "glo-ops",
    "galileo",
    "geo",
    "starlink",
];

pub const USER_AGENT: &str =
    "vitruvian-core-gods-eye-view-tle-mirror/1.0 (+https://github.com/VitruvianSoftware/vitruvian-core)";

fn url_encode_query_param(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'*' => {
                out.push(b as char);
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{:02X}", b)),
        }
    }
    out
}

/// CelesTrak's URL for a group, matching `celestrakGroupUrl(group)` and `celestrakTleUrl(group)`.
pub fn celestrak_group_url(group: &str) -> String {
    format!(
        "https://celestrak.org/NORAD/elements/gp.php?GROUP={}&FORMAT=tle",
        url_encode_query_param(group)
    )
}

/// Whether a body holds TLEs (`/^1 /m.test(body) && /^2 /m.test(body)`).
pub fn has_tle(body: &str) -> bool {
    let has_line1 = body.lines().any(|line| line.starts_with("1 "));
    let has_line2 = body.lines().any(|line| line.starts_with("2 "));
    has_line1 && has_line2
}

#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub body: String,
}

pub fn validate_group_response(resp: Result<HttpResponse, String>) -> Result<String, String> {
    let r = resp?;
    if !(200..300).contains(&r.status) {
        return Err(format!("HTTP {}", r.status));
    }
    if !has_tle(&r.body) {
        return Err("no TLE lines in the response".to_string());
    }
    Ok(r.body)
}

/// Fetches every group into `dir`, trying each twice. Returns `group: reason`
/// for each group that failed; their files, if any, are left as they were.
pub fn mirror_with_fetcher<F>(
    dir: &Path,
    groups: &[&str],
    retry_delay: Duration,
    mut fetch_fn: F,
) -> Result<Vec<String>, String>
where
    F: FnMut(&str) -> Result<HttpResponse, String>,
{
    std::fs::create_dir_all(dir)
        .map_err(|e| format!("failed to create mirror directory {}: {}", dir.display(), e))?;
    let mut failed = Vec::new();

    for &group in groups {
        let url = celestrak_group_url(group);
        let first_attempt = validate_group_response(fetch_fn(&url));
        let outcome = match first_attempt {
            Ok(body) => Ok(body),
            Err(_) => {
                if !retry_delay.is_zero() {
                    std::thread::sleep(retry_delay);
                }
                validate_group_response(fetch_fn(&url))
            }
        };

        match outcome {
            Ok(body) => {
                let target = dir.join(format!("{}.txt", group));
                if let Err(e) = std::fs::write(&target, body.as_bytes()) {
                    failed.push(format!("{}: {}", group, e));
                }
            }
            Err(reason) => {
                failed.push(format!("{}: {}", group, reason));
            }
        }
    }

    Ok(failed)
}

pub fn curl_fetch(url: &str) -> Result<HttpResponse, String> {
    let output = Command::new("curl")
        .args([
            "-sS",
            "-L",
            "--max-time",
            "60",
            "-A",
            USER_AGENT,
            "-w",
            "\n%{http_code}",
            url,
        ])
        .output()
        .map_err(|e| format!("fetch failed: {}", e))?;

    if !output.status.success() {
        return Err("fetch failed".to_string());
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let last_nl = text.rfind('\n').ok_or_else(|| "invalid response".to_string())?;
    let body = text[..last_nl].to_string();
    let status_str = text[last_nl + 1..].trim();
    let status = status_str
        .parse::<u16>()
        .map_err(|_| "invalid HTTP status".to_string())?;
    Ok(HttpResponse { status, body })
}

/// Port of `arrayStrings(source, name, key)` from `tle-mirror/mirror.test.mjs`.
pub fn extract_array_strings(
    source: &str,
    const_name: &str,
    obj_key: Option<&str>,
) -> Result<Vec<String>, String> {
    let needle = format!("const {} = [", const_name);
    let start = source
        .find(&needle)
        .ok_or_else(|| format!("{} is not declared", const_name))?;
    let rest = &source[start..];
    let end_offset = rest
        .find("];")
        .ok_or_else(|| format!("{} array closing not found", const_name))?;
    let body = &rest[..end_offset];

    let mut results = Vec::new();
    if let Some(key) = obj_key {
        let key_prefix = format!("{}:", key);
        let mut search = body;
        while let Some(pos) = search.find(&key_prefix) {
            let after_key = &search[pos + key_prefix.len()..];
            let trimmed = after_key.trim_start();
            if let Some(stripped) = trimmed.strip_prefix('\'') {
                if let Some(end_q) = stripped.find('\'') {
                    results.push(stripped[..end_q].to_string());
                    search = &stripped[end_q + 1..];
                    continue;
                }
            }
            search = after_key;
        }
    } else {
        let mut chars = body.char_indices();
        while let Some((_, ch)) = chars.next() {
            if ch == '\'' {
                let mut val = String::new();
                for (_, c2) in chars.by_ref() {
                    if c2 == '\'' {
                        break;
                    }
                    val.push(c2);
                }
                results.push(val);
            }
        }
    }
    Ok(results)
}

/// Scans `dir` recursively for `/api/celestrak/<group>` literals in `.js`/`.mjs` non-test files.
pub fn scan_literal_celestrak_groups(dir: &Path) -> Vec<String> {
    let mut groups = Vec::new();
    let entries = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return groups,
    };
    let mut sorted_entries: Vec<_> = entries.flatten().collect();
    sorted_entries.sort_by_key(|e| e.file_name());

    for entry in sorted_entries {
        let p = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if p.is_dir() {
            groups.extend(scan_literal_celestrak_groups(&p));
        } else if (name.ends_with(".js") || name.ends_with(".mjs")) && !name.contains(".test.") {
            if let Ok(content) = std::fs::read_to_string(&p) {
                let marker = "/api/celestrak/";
                let mut search = content.as_str();
                while let Some(idx) = search.find(marker) {
                    if idx > 0 {
                        let quote = search.as_bytes()[idx - 1];
                        if quote == b'\'' || quote == b'"' || quote == b'`' {
                            let after = &search[idx + marker.len()..];
                            let end_len = after
                                .bytes()
                                .take_while(|&b| {
                                    b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-'
                                })
                                .count();
                            if end_len > 0 && after.as_bytes().get(end_len) == Some(&quote) {
                                groups.push(after[..end_len].to_string());
                            }
                        }
                    }
                    search = &search[idx + marker.len()..];
                }
            }
        }
    }
    groups
}

/// Verifies that `MIRRORED_GROUPS` includes every CelesTrak group requested across `app_root/src`.
pub fn verify_client_groups_mirrored(app_root: &Path) -> Result<Vec<String>, String> {
    let policy_src = std::fs::read_to_string(app_root.join("src/layers/satellites/policy.js"))
        .map_err(|e| format!("Cannot read src/layers/satellites/policy.js: {}", e))?;
    let space_src = std::fs::read_to_string(app_root.join("src/tools/queries/space.js"))
        .map_err(|e| format!("Cannot read src/tools/queries/space.js: {}", e))?;

    let mut requested = BTreeSet::new();
    for g in extract_array_strings(&policy_src, "CATALOG_GROUPS", Some("path"))? {
        requested.insert(g);
    }
    for g in extract_array_strings(&space_src, "GROUPS", None)? {
        requested.insert(g);
    }
    for g in scan_literal_celestrak_groups(&app_root.join("src")) {
        requested.insert(g);
    }

    if !requested.contains("stations") || !requested.contains("active") {
        return Err("client scan did not find stations and active".to_string());
    }

    let missing: Vec<String> = requested
        .iter()
        .filter(|g| !MIRRORED_GROUPS.contains(&g.as_str()))
        .cloned()
        .collect();
    if !missing.is_empty() {
        return Err(format!(
            "requested by the client but not mirrored: {}",
            missing.join(", ")
        ));
    }

    Ok(requested.into_iter().collect())
}

pub fn run(args: &[String]) -> Result<(), i32> {
    let dir = match args.first() {
        Some(d) if !d.is_empty() => Path::new(d),
        _ => {
            eprintln!("usage: mirror.mjs <dir>");
            return Err(2);
        }
    };

    let failed = match mirror_with_fetcher(
        dir,
        MIRRORED_GROUPS,
        Duration::from_secs(30),
        curl_fetch,
    ) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("{}", e);
            return Err(1);
        }
    };

    for line in &failed {
        eprintln!("::warning::{}", line);
    }
    if failed.len() == MIRRORED_GROUPS.len() {
        return Err(1);
    }
    Ok(())
}
