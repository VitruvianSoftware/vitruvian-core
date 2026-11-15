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

//! Holds `vitruvian-tool.json` to `release-please`'s JSON layout (every
//! non-empty array one item a line, 2-space indent, trailing newline) and
//! verifies its version stays in lockstep with `release-please-config.json`
//! and `.release-please-manifest.json`.

use std::fs;
use std::path::PathBuf;

fn env_path(var: &str) -> PathBuf {
    PathBuf::from(std::env::var(var).unwrap_or_else(|_| panic!("{var} must be set")))
}

fn semver(text: &str) -> Option<(u32, u32, u32)> {
    let parts: Vec<&str> = text.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    Some((
        parts[0].parse().ok()?,
        parts[1].parse().ok()?,
        parts[2].parse().ok()?,
    ))
}

fn format_json_utf8(val: &conformance_rs_lib::json::Value, indent: usize) -> String {
    use conformance_rs_lib::json::Value;
    match val {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true" } else { "false" }.to_string(),
        Value::Int(s) => s.clone(),
        Value::Float(f) => serde_json::to_string(f).unwrap_or_else(|_| f.to_string()),
        Value::Str(s) => serde_json::to_string(s).expect("serialize string"),
        Value::Arr(items) => {
            if items.is_empty() {
                return "[]".to_string();
            }
            let inner_pad = " ".repeat(indent + 2);
            let outer_pad = " ".repeat(indent);
            let parts: Vec<String> = items
                .iter()
                .map(|item| format!("{inner_pad}{}", format_json_utf8(item, indent + 2)))
                .collect();
            format!("[\n{}\n{outer_pad}]", parts.join(",\n"))
        }
        Value::Obj(entries) => {
            if entries.is_empty() {
                return "{}".to_string();
            }
            let inner_pad = " ".repeat(indent + 2);
            let outer_pad = " ".repeat(indent);
            let parts: Vec<String> = entries
                .iter()
                .map(|(k, v)| {
                    let k_json = serde_json::to_string(k).expect("serialize key");
                    let v_json = format_json_utf8(v, indent + 2);
                    format!("{inner_pad}{k_json}: {v_json}")
                })
                .collect();
            format!("{{\n{}\n{outer_pad}}}", parts.join(",\n"))
        }
    }
}

fn release_please_layout(text: &str) -> String {
    let val = conformance_rs_lib::json::loads(text).expect("vitruvian-tool.json is not valid JSON");
    let mut out = format_json_utf8(&val, 0);
    out.push('\n');
    out
}

#[test]
fn version_and_layout_checks_pass() {
    let mut problems = Vec::new();

    let manifest_path = env_path("MANIFEST_PATH");
    let manifest_text = fs::read_to_string(&manifest_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", manifest_path.display()));

    if manifest_text != release_please_layout(&manifest_text) {
        problems.push(
            "vitruvian-tool.json is not in the layout release-please writes \
             (every array one item a line); the release PR would fail tidy-check"
                .to_string(),
        );
    }

    let manifest: serde_json::Value = serde_json::from_str(&manifest_text)
        .unwrap_or_else(|e| panic!("cannot parse {}: {e}", manifest_path.display()));
    let manifest_version = manifest
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    if semver(&manifest_version).is_none() {
        problems.push(format!(
            "vitruvian-tool.json's version {manifest_version:?} is not X.Y.Z"
        ));
    }

    let rp_manifest_path = env_path("RP_MANIFEST_PATH");
    let rp_manifest_text = fs::read_to_string(&rp_manifest_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", rp_manifest_path.display()));
    let rp_manifest: serde_json::Value = serde_json::from_str(&rp_manifest_text)
        .unwrap_or_else(|e| panic!("cannot parse {}: {e}", rp_manifest_path.display()));
    let released = rp_manifest
        .as_object()
        .and_then(|m| m.values().next())
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let config_path = env_path("RP_CONFIG_PATH");
    let config_text = fs::read_to_string(&config_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", config_path.display()));
    let config: serde_json::Value = serde_json::from_str(&config_text)
        .unwrap_or_else(|e| panic!("cannot parse {}: {e}", config_path.display()));
    let package = config
        .get("packages")
        .and_then(|p| p.as_object())
        .and_then(|p| p.values().next())
        .expect("no package in release-please-config.json");

    let expected = if released == "0.0.0" {
        package
            .get("initial-version")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string()
    } else {
        released.to_string()
    };
    if expected != manifest_version {
        problems.push(format!(
            "release-please says the version is {expected}, \
             vitruvian-tool.json says {manifest_version}"
        ));
    }

    let has_manifest_updater = package
        .get("extra-files")
        .and_then(|e| e.as_array())
        .map(|arr| {
            arr.iter().any(|entry| {
                entry.get("type").and_then(|t| t.as_str()) == Some("json")
                    && entry.get("path").and_then(|p| p.as_str()) == Some("vitruvian-tool.json")
                    && entry.get("jsonpath").and_then(|j| j.as_str()) == Some("$.version")
            })
        })
        .unwrap_or(false);
    if !has_manifest_updater {
        problems.push(
            "release-please-config.json does not update $.version in vitruvian-tool.json"
                .to_string(),
        );
    }

    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{p}");
        }
        panic!("{} version problem(s)", problems.len());
    }
}

#[test]
fn release_please_layout_expands_short_arrays() {
    let collapsed = "{\n  \"version\": \"0.1.0\",\n  \"uses\": [\"notify\", \"storage\"]\n}\n";
    let expanded =
        "{\n  \"version\": \"0.1.0\",\n  \"uses\": [\n    \"notify\",\n    \"storage\"\n  ]\n}\n";
    assert_eq!(release_please_layout(collapsed), expanded);
    assert_eq!(release_please_layout(expanded), expanded);
}

#[test]
fn semver_validation() {
    assert_eq!(semver("0.1.0"), Some((0, 1, 0)));
    assert_eq!(semver("1.2"), None);
    assert_eq!(semver("1.2.x"), None);
}
