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

//! The tool's version is the app's, in every file that says it.
//!
//! Checks tool/vitruvian-tool.json layout (2-space indented JSON matching
//! release-please) and version X.Y.Z, matches
//! Sources/HomeSpeakerToolCore/Version.swift and
//! Sources/HomeSpeakerCore/Version.swift, checks release-please-config.json
//! extra-files, and checks Package.swift vitruvian-sdk >= 1.8.0 (with 1.1.0,
//! 1.3.0, 1.8.0 thresholds).

use std::fs;
use std::path::PathBuf;

const PKG: &str = "apps/desktop/home-speaker";

const KIT_WITH_WAKER: (u32, u32, u32) = (1, 1, 0);
const KIT_WITH_CHOICE: (u32, u32, u32) = (1, 3, 0);
const KIT_WITH_CHIPS: (u32, u32, u32) = (1, 8, 0);

fn rlocation(short_path: &str) -> PathBuf {
    if let Ok(dir) = std::env::var("RUNFILES_DIR") {
        let p = PathBuf::from(&dir).join("_main").join(short_path);
        if p.exists() {
            return p;
        }
    }
    if let Ok(dir) = std::env::var("TEST_SRCDIR") {
        let ws = std::env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".into());
        let p = PathBuf::from(&dir).join(&ws).join(short_path);
        if p.exists() {
            return p;
        }
    }
    PathBuf::from(short_path)
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

fn version_line(path: &PathBuf) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    for line in text.lines() {
        if line.contains("// x-release-please-version") {
            let start = line.find('"')? + 1;
            let end = line[start..].find('"')? + start;
            return Some(line[start..end].to_string());
        }
    }
    None
}

fn extract_kit_version(package_swift: &str) -> Option<String> {
    let marker = "vitruvian-sdk\", from: \"";
    let start = package_swift.find(marker)? + marker.len();
    let end = package_swift[start..].find('"')? + start;
    Some(package_swift[start..end].to_string())
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
    let value =
        conformance_rs_lib::json::loads(text).expect("vitruvian-tool.json is not valid JSON");
    let mut serialized = format_json_utf8(&value, 0);
    serialized.push('\n');
    serialized
}

#[test]
fn tool_version_matches_app() {
    let mut problems = Vec::new();

    let manifest_path = rlocation(&format!("{}/tool/vitruvian-tool.json", PKG));
    let manifest_text = fs::read_to_string(&manifest_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", manifest_path.display(), e));

    if manifest_text != release_please_layout(&manifest_text) {
        problems.push(
            "vitruvian-tool.json is not in the layout release-please writes \
             (every array one item a line); the release PR would fail tidy-check"
                .to_string(),
        );
    }

    let manifest: serde_json::Value = serde_json::from_str(&manifest_text)
        .unwrap_or_else(|e| panic!("cannot parse {}: {}", manifest_path.display(), e));
    let manifest_version = manifest
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let tool_version = version_line(&rlocation(&format!(
        "{}/Sources/HomeSpeakerToolCore/Version.swift",
        PKG
    )));
    let app_version = version_line(&rlocation(&format!(
        "{}/Sources/HomeSpeakerCore/Version.swift",
        PKG
    )));

    if semver(&manifest_version).is_none() {
        problems.push(format!(
            "vitruvian-tool.json's version {:?} is not X.Y.Z",
            manifest_version
        ));
    }
    if tool_version.as_deref() != Some(&manifest_version) {
        problems.push(format!(
            "the tool's Version.swift says {:?}, vitruvian-tool.json says {:?}",
            tool_version, manifest_version
        ));
    }
    if app_version.as_deref() != Some(&manifest_version) {
        problems.push(format!(
            "the app's Version.swift says {:?}, vitruvian-tool.json says {:?}",
            app_version, manifest_version
        ));
    }

    let config_path = rlocation(&format!("{}/release-please-config.json", PKG));
    let config_text = fs::read_to_string(&config_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", config_path.display(), e));
    let config: serde_json::Value = serde_json::from_str(&config_text)
        .unwrap_or_else(|e| panic!("cannot parse {}: {}", config_path.display(), e));

    let extra_files: Vec<String> = config
        .get("packages")
        .and_then(|p| p.as_object())
        .and_then(|p| p.values().next())
        .and_then(|p| p.get("extra-files"))
        .and_then(|e| e.as_array())
        .map(|arr| {
            arr.iter()
                .map(|entry| {
                    entry
                        .get("path")
                        .and_then(|p| p.as_str())
                        .or_else(|| entry.as_str())
                        .unwrap_or("")
                        .to_string()
                })
                .collect()
        })
        .unwrap_or_default();

    for needed in &[
        "tool/vitruvian-tool.json",
        "Sources/HomeSpeakerToolCore/Version.swift",
    ] {
        if !extra_files.iter().any(|f| f == needed) {
            problems.push(format!(
                "release-please-config.json does not write the version into {}",
                needed
            ));
        }
    }

    let package_swift_path = rlocation(&format!("{}/Package.swift", PKG));
    let package_swift = fs::read_to_string(&package_swift_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", package_swift_path.display(), e));

    let kit_version = extract_kit_version(&package_swift);
    match &kit_version {
        None => problems.push(
            "Package.swift does not depend on VitruvianSoftware/vitruvian-sdk with `from:`".into(),
        ),
        Some(v) => {
            let ver = semver(v).unwrap_or((0, 0, 0));
            if ver < KIT_WITH_WAKER {
                problems.push(format!(
                    "Package.swift builds against kit {}, before ToolWaker came ({}.{}.{})",
                    v, KIT_WITH_WAKER.0, KIT_WITH_WAKER.1, KIT_WITH_WAKER.2
                ));
            } else if ver < KIT_WITH_CHOICE {
                problems.push(format!(
                    "Package.swift builds against kit {}, before the choice block came ({}.{}.{})",
                    v, KIT_WITH_CHOICE.0, KIT_WITH_CHOICE.1, KIT_WITH_CHOICE.2
                ));
            } else if ver < KIT_WITH_CHIPS {
                problems.push(format!(
                    "Package.swift builds against kit {}, before the chips block came ({}.{}.{})",
                    v, KIT_WITH_CHIPS.0, KIT_WITH_CHIPS.1, KIT_WITH_CHIPS.2
                ));
            }
        }
    }

    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{}", p);
        }
        panic!("{} version check(s) failed", problems.len());
    }

    println!(
        "the tool is {}, the app's version, in every file that says so, \
         against a kit with a waker, choice and chips",
        manifest_version
    );
}

#[test]
fn test_semver_parsing() {
    assert_eq!(semver("1.2.3"), Some((1, 2, 3)));
    assert_eq!(semver("0.0.0"), Some((0, 0, 0)));
    assert_eq!(semver("10.20.30"), Some((10, 20, 30)));
    assert_eq!(semver("1.2"), None);
    assert_eq!(semver("1.2.3.4"), None);
    assert_eq!(semver("abc"), None);
    assert_eq!(semver(""), None);
    assert_eq!(semver("1.2.x"), None);
}

#[test]
fn test_version_line_extraction() {
    let content = "let version = \"3.48.0\" // x-release-please-version";
    let dir = std::env::temp_dir().join("hs-version-test");
    let _ = fs::create_dir_all(&dir);
    let path = dir.join("Version.swift");
    fs::write(&path, content).unwrap();
    assert_eq!(version_line(&path), Some("3.48.0".into()));

    let no_marker = "let version = \"3.48.0\"";
    fs::write(&path, no_marker).unwrap();
    assert_eq!(version_line(&path), None);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn test_extract_kit_version() {
    let swift =
        ".package(url: \"https://github.com/VitruvianSoftware/vitruvian-sdk\", from: \"1.8.0\")";
    assert_eq!(extract_kit_version(swift), Some("1.8.0".into()));

    let no_match = ".package(url: \"https://github.com/other/lib\", from: \"2.0.0\")";
    assert_eq!(extract_kit_version(no_match), None);
}

#[test]
fn test_semver_threshold_comparison() {
    assert!((1, 1, 0) >= KIT_WITH_WAKER);
    assert!((1, 0, 0) < KIT_WITH_WAKER);
    assert!((1, 3, 0) >= KIT_WITH_CHOICE);
    assert!((1, 2, 0) < KIT_WITH_CHOICE);
    assert!((1, 8, 0) >= KIT_WITH_CHIPS);
    assert!((1, 7, 0) < KIT_WITH_CHIPS);
    assert!((2, 0, 0) >= KIT_WITH_CHIPS);
}

#[test]
fn test_release_please_layout() {
    let compact = r#"{"version":"1.0.0","name":"test"}"#;
    let laid_out = release_please_layout(compact);
    assert!(laid_out.contains("  "));
    assert!(laid_out.ends_with('\n'));
    assert_eq!(laid_out, release_please_layout(&laid_out));
}
