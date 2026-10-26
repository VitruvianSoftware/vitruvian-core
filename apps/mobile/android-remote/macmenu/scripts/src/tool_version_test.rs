// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Rust port of `apps/mobile/android-remote/macmenu/tool/version_test.py`.
//!
//! Verifies that the Vitruvian Remote extension version in `tool/vitruvian-tool.json`
//! matches `Version.swift`, `Resources/Info.plist`, and `apps/mobile/android-remote/BUILD`,
//! that `vitruvian-tool.json` is formatted in release-please's 2-space JSON layout,
//! and that `release-please-config.json` lists all four versioned files in `extra-files`.

use conformance_rs_lib::json::{self, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const REQUIRED_EXTRA_FILES: &[&str] = &[
    "BUILD",
    "macmenu/Sources/RemoteMenuCore/Version.swift",
    "macmenu/tool/vitruvian-tool.json",
    "macmenu/Resources/Info.plist",
];

pub fn parse_semver(text: &str) -> Option<(u32, u32, u32)> {
    let parts: Vec<&str> = text.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    for p in &parts {
        if p.is_empty() || !p.chars().all(|c| c.is_ascii_digit()) {
            return None;
        }
    }
    Some((
        parts[0].parse().ok()?,
        parts[1].parse().ok()?,
        parts[2].parse().ok()?,
    ))
}

pub fn swift_version_line(text: &str) -> Option<String> {
    let marker = "// x-release-please-version";
    for line in text.lines() {
        if let Some(pos) = line.find(marker) {
            let before = line[..pos].trim_end();
            if let Some(end_q) = before.rfind('"') {
                let prefix = &before[..end_q];
                if let Some(start_q) = prefix.rfind('"') {
                    return Some(prefix[start_q + 1..].to_string());
                }
            }
        }
    }
    None
}

pub fn build_version_line(text: &str) -> Option<String> {
    let marker = "# x-release-please-version";
    for line in text.lines() {
        if let Some(pos) = line.find(marker) {
            let before = line[..pos].trim_end();
            if let Some(stripped) = before.strip_suffix(',') {
                let trimmed = stripped.trim_end();
                if let Some(end_q) = trimmed.rfind('"') {
                    let prefix = &trimmed[..end_q];
                    if let Some(start_q) = prefix.rfind('"') {
                        return Some(prefix[start_q + 1..].to_string());
                    }
                }
            }
        }
    }
    None
}

pub fn extract_plist_key(plist_xml: &str, key: &str) -> Option<String> {
    let key_tag = format!("<key>{key}</key>");
    let pos = plist_xml.find(&key_tag)?;
    let rest = &plist_xml[pos + key_tag.len()..];
    let s_pos = rest.find("<string>")?;
    let after_s = &rest[s_pos + "<string>".len()..];
    let e_pos = after_s.find("</string>")?;
    Some(after_s[..e_pos].to_string())
}

fn format_json_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn format_value_pretty(val: &Value, indent: usize) -> String {
    let pad = " ".repeat(indent);
    let inner_pad = " ".repeat(indent + 2);
    match val {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true" } else { "false" }.to_string(),
        Value::Int(n) => n.to_string(),
        Value::Float(f) => format!("{f}"),
        Value::Str(s) => format_json_string(s),
        Value::Arr(items) => {
            if items.is_empty() {
                "[]".to_string()
            } else {
                let rendered: Vec<String> = items
                    .iter()
                    .map(|item| format!("{inner_pad}{}", format_value_pretty(item, indent + 2)))
                    .collect();
                format!("[\n{}\n{pad}]", rendered.join(",\n"))
            }
        }
        Value::Obj(entries) => {
            if entries.is_empty() {
                "{}".to_string()
            } else {
                let rendered: Vec<String> = entries
                    .iter()
                    .map(|(k, v)| {
                        format!(
                            "{inner_pad}{}: {}",
                            format_json_string(k),
                            format_value_pretty(v, indent + 2)
                        )
                    })
                    .collect();
                format!("{{\n{}\n{pad}}}", rendered.join(",\n"))
            }
        }
    }
}

pub fn release_please_layout(text: &str) -> Result<String, String> {
    let parsed = json::loads(text).map_err(|e| format!("invalid json: {e:?}"))?;
    Ok(format!("{}\n", format_value_pretty(&parsed, 0)))
}

pub fn check_all_versions(
    manifest_text: &str,
    swift_text: &str,
    build_text: &str,
    plist_text: &str,
    rp_config_text: &str,
) -> Vec<String> {
    let mut problems = Vec::new();

    let parsed_manifest = match json::loads(manifest_text) {
        Ok(v) => v,
        Err(e) => {
            problems.push(format!("failed to parse vitruvian-tool.json: {e:?}"));
            return problems;
        }
    };

    let manifest_version = parsed_manifest
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match release_please_layout(manifest_text) {
        Ok(expected) if expected != manifest_text => {
            problems.push(
                "vitruvian-tool.json is not in the layout release-please writes (every array one item a line); the release PR would fail tidy-check".to_string(),
            );
        }
        Err(e) => problems.push(e),
        _ => {}
    }

    if parse_semver(manifest_version).is_none() {
        problems.push(format!(
            "vitruvian-tool.json's version '{manifest_version}' is not X.Y.Z"
        ));
    }

    let swift_ver = swift_version_line(swift_text);
    if swift_ver.as_deref() != Some(manifest_version) {
        problems.push(format!(
            "RemoteMenuCore/Version.swift says {:?}, vitruvian-tool.json says {manifest_version}",
            swift_ver
        ));
    }

    let build_ver = build_version_line(build_text);
    if build_ver.as_deref() != Some(manifest_version) {
        problems.push(format!(
            "android-remote/BUILD says {:?}, vitruvian-tool.json says {manifest_version}",
            build_ver
        ));
    }

    for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
        let got = extract_plist_key(plist_text, key);
        if got.as_deref() != Some(manifest_version) {
            problems.push(format!(
                "Resources/Info.plist {key} says {:?}, vitruvian-tool.json says {manifest_version}",
                got
            ));
        }
    }

    if let Ok(rp_val) = json::loads(rp_config_text) {
        let mut extra_paths = Vec::new();
        if let Some(pkgs) = rp_val.get("packages").and_then(|v| v.as_obj()) {
            if let Some((_, pkg)) = pkgs.first() {
                if let Some(arr) = pkg.get("extra-files").and_then(|v| v.as_arr()) {
                    for entry in arr {
                        if let Some(s) = entry.as_str() {
                            extra_paths.push(s.to_string());
                        } else if let Some(p) = entry.get("path").and_then(|v| v.as_str()) {
                            extra_paths.push(p.to_string());
                        }
                    }
                }
            }
        }
        for needed in REQUIRED_EXTRA_FILES {
            if !extra_paths.iter().any(|p| p == needed) {
                problems.push(format!(
                    "release-please-config.json does not write the version into {needed}"
                ));
            }
        }
    } else {
        problems.push("failed to parse release-please-config.json".to_string());
    }

    problems
}

fn find_runfile(rel: &str) -> PathBuf {
    let direct = PathBuf::from(rel);
    if direct.is_file() {
        return direct;
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(base) = env::var(var) {
            let candidate = Path::new(&base).join("_main").join(rel);
            if candidate.is_file() {
                return candidate;
            }
        }
    }
    direct
}

#[test]
fn live_tool_versions_and_release_please_config_in_sync() {
    let manifest = fs::read_to_string(find_runfile(
        "apps/mobile/android-remote/macmenu/tool/vitruvian-tool.json",
    ))
    .unwrap();
    let swift = fs::read_to_string(find_runfile(
        "apps/mobile/android-remote/macmenu/Sources/RemoteMenuCore/Version.swift",
    ))
    .unwrap();
    let build = fs::read_to_string(find_runfile("apps/mobile/android-remote/BUILD")).unwrap();
    let plist = fs::read_to_string(find_runfile(
        "apps/mobile/android-remote/macmenu/Resources/Info.plist",
    ))
    .unwrap();
    let rp_config = fs::read_to_string(find_runfile(
        "apps/mobile/android-remote/release-please-config.json",
    ))
    .unwrap();

    let problems = check_all_versions(&manifest, &swift, &build, &plist, &rp_config);
    assert!(
        problems.is_empty(),
        "version check failed:\n{}",
        problems.join("\n")
    );
}

#[test]
fn semver_parsing_accepts_only_three_numeric_components() {
    assert_eq!(parse_semver("0.1.21"), Some((0, 1, 21)));
    assert_eq!(parse_semver("1.0.0"), Some((1, 0, 0)));
    assert!(parse_semver("").is_none());
    assert!(parse_semver("0.1").is_none());
    assert!(parse_semver("0.1.21-beta.1").is_none());
    assert!(parse_semver("v0.1.21").is_none());
}

#[test]
fn detects_mismatch_across_files() {
    let manifest = "{\n  \"version\": \"0.1.21\"\n}\n";
    let swift = "public static let current = \"0.1.20\" // x-release-please-version\n";
    let build = "        \"versionName\": \"0.1.19\",  # x-release-please-version\n";
    let plist = "<plist><dict><key>CFBundleShortVersionString</key><string>0.1.18</string><key>CFBundleVersion</key><string>0.1.21</string></dict></plist>";
    let rp = "{\"packages\": {\"apps/mobile/android-remote\": {\"extra-files\": []}}}";

    let problems = check_all_versions(manifest, swift, build, plist, rp);
    assert!(problems.iter().any(|p| p.contains("Version.swift")));
    assert!(problems.iter().any(|p| p.contains("android-remote/BUILD")));
    assert!(problems
        .iter()
        .any(|p| p.contains("CFBundleShortVersionString")));
    assert!(problems
        .iter()
        .any(|p| p.contains("release-please-config.json")));
}
