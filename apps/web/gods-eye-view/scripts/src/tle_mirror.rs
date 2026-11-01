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

//! Mirrors the CelesTrak groups the app requests, for a server CelesTrak does
//! not answer. Connections from the homelab to celestrak.org time out
//! (CelesTrak throttles hosts that poll it too often, as the old uncached
//! server did), so .github/workflows/gods-eye-view-tle-mirror.yaml runs this
//! every 6 hours from GitHub's runners and publishes the files on the
//! gods-eye-view-tle branch; the server reads them through
//! CELESTRAK_TLE_MIRROR_URL (server/providers/space/celestrak.js) and falls
//! back to CelesTrak.
//!
//!   bazel run //apps/web/gods-eye-view:tle_mirror -- <dir>
//!
//! writes <dir>/<group>.txt for each group it fetches, and leaves the file a
//! failed group already had, so one bad fetch never empties the mirror.
//!
//! Standard library only (plus the `curl` binary), and included by path from
//! bin/tle_mirror.rs, so the workflow compiles it with plain `rustc`, without
//! Bazel.

use std::collections::BTreeSet;
use std::path::Path;
use std::process::Command;
use std::time::Duration;

/// The groups the client requests: the satellite catalog's (CATALOG_GROUPS in
/// src/layers/satellites/policy.js), the space tool's (GROUPS in
/// src/tools/queries/space.js) and every `/api/celestrak/<group>` literal.
/// [`verify_client_groups_mirrored`] holds this list to the client's code.
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

/// CelesTrak 403s bulk groups (`active`) without a descriptive User-Agent.
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

/// The arguments [`curl_fetch`] runs curl with, before the URL. `-q` has to be
/// first: it stops curl reading the user's ~/.curlrc. Every request and
/// redirect stays on HTTPS with TLS 1.2 or later, and a redirect loop stops
/// after 5 hops. [`curl_args`] ends them with `--`, so the URL can never be
/// read as an option.
pub const CURL_ARGS: &[&str] = &[
    "-q",
    "--proto",
    "=https",
    "--proto-redir",
    "=https",
    "--tlsv1.2",
    "-sS",
    "-L",
    "--max-redirs",
    "5",
    "--max-time",
    "60",
    "-A",
    USER_AGENT,
    "-w",
    "\n%{http_code}",
];

/// The full curl argument list for `url`: [`CURL_ARGS`], then `--`, then the URL.
pub fn curl_args(url: &str) -> Vec<String> {
    let mut args: Vec<String> = CURL_ARGS.iter().map(|a| a.to_string()).collect();
    args.push("--".to_string());
    args.push(url.to_string());
    args
}

pub fn curl_fetch(url: &str) -> Result<HttpResponse, String> {
    let output = Command::new("curl")
        .args(curl_args(url))
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

/// The URL `celestrakTleUrl(group)` in src/data/spaceProviderRequests.js builds,
/// read from that function's source. Lets the test hold [`celestrak_group_url`]
/// to the server's code, not to a copy of it.
///
/// The reading is strict, because a lenient one passes when the function
/// changes in a way it does not understand. Each line of the body must be one
/// of these, in this order, and anything else is an error:
///
///   const url = new URL('<base>');                         (exactly once, first)
///   url.searchParams.set('<KEY>', group | '<literal>');    (any number, distinct keys)
///   return url;                                            (exactly once, last)
///
/// Blank lines and `//` comment lines are skipped. The base must carry no
/// query or fragment, so the result is the whole URL: path plus every query
/// parameter, in order.
pub fn server_group_url(source: &str, group: &str) -> Result<String, String> {
    const HEAD: &str = "export function celestrakTleUrl(group) {";
    let start = source
        .find(HEAD)
        .ok_or_else(|| "celestrakTleUrl(group) is not declared".to_string())?;
    let rest = &source[start + HEAD.len()..];
    let body = &rest[..rest
        .find("\n}")
        .ok_or_else(|| "celestrakTleUrl has no end".to_string())?];

    /// `'<text>'` with nothing around it, and no quote or backslash inside.
    fn literal(s: &str) -> Option<&str> {
        let inner = s.strip_prefix('\'')?.strip_suffix('\'')?;
        (!inner.contains('\'') && !inner.contains('\\')).then_some(inner)
    }

    let mut base: Option<String> = None;
    let mut params: Vec<(String, String)> = Vec::new();
    let mut returned = false;
    for raw in body.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with("//") {
            continue;
        }
        let unrecognised = || format!("celestrakTleUrl: unrecognised statement `{line}`");
        if returned {
            return Err(format!("celestrakTleUrl: statement after return `{line}`"));
        }
        if let Some(arg) = line
            .strip_prefix("const url = new URL(")
            .and_then(|r| r.strip_suffix(");"))
        {
            if base.is_some() || !params.is_empty() {
                return Err(unrecognised());
            }
            let b = literal(arg).ok_or_else(unrecognised)?;
            if !b.starts_with("https://") || b.contains('?') || b.contains('#') {
                return Err(format!("celestrakTleUrl: unexpected base URL `{b}`"));
            }
            base = Some(b.to_string());
        } else if let Some(args) = line
            .strip_prefix("url.searchParams.set(")
            .and_then(|r| r.strip_suffix(");"))
        {
            if base.is_none() {
                return Err(unrecognised());
            }
            let (key, value) = args.split_once(", ").ok_or_else(unrecognised)?;
            let key = literal(key).ok_or_else(unrecognised)?.to_string();
            let value = match value {
                "group" => group.to_string(),
                v => literal(v).ok_or_else(unrecognised)?.to_string(),
            };
            if params.iter().any(|(k, _)| *k == key) {
                return Err(format!("celestrakTleUrl: {key} is set twice"));
            }
            params.push((key, value));
        } else if line == "return url;" {
            returned = true;
        } else {
            return Err(unrecognised());
        }
    }

    let base = base.ok_or_else(|| "celestrakTleUrl builds no URL".to_string())?;
    if !returned {
        return Err("celestrakTleUrl does not return its URL".to_string());
    }
    if params.is_empty() {
        return Err("celestrakTleUrl sets no query parameters".to_string());
    }
    let query: Vec<String> = params
        .iter()
        .map(|(k, v)| format!("{}={}", url_encode_query_param(k), url_encode_query_param(v)))
        .collect();
    Ok(format!("{}?{}", base, query.join("&")))
}

/// The quoted strings in the array literal that `const <name> = [` opens; with
/// `obj_key`, only the `<key>: '<value>'` values.
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
            eprintln!("usage: tle_mirror <dir>");
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
