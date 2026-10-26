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
//! Checks vitruvian-tool.json version is X.Y.Z, matches
//! Sources/NexusAgentToolCore/Version.swift and
//! Sources/NexusAgent/Version.swift, checks release-please-config.json
//! extra-files includes the tool's paths, and checks Package.swift
//! vitruvian-sdk >= 1.9.0.

use std::fs;
use std::path::PathBuf;

const PKG: &str = "apps/desktop/nexus-agent/macos";
const APP: &str = "apps/desktop/nexus-agent";

const KIT_THE_TOOL_NEEDS: (u32, u32, u32) = (1, 9, 0);

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

#[test]
fn tool_version_matches_app() {
    let mut problems = Vec::new();

    let manifest_path = rlocation(&format!("{}/tool/vitruvian-tool.json", PKG));
    let manifest_text = fs::read_to_string(&manifest_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {}", manifest_path.display(), e));
    let manifest: serde_json::Value = serde_json::from_str(&manifest_text)
        .unwrap_or_else(|e| panic!("cannot parse {}: {}", manifest_path.display(), e));
    let manifest_version = manifest
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let tool_version = version_line(&rlocation(&format!(
        "{}/Sources/NexusAgentToolCore/Version.swift",
        PKG
    )));
    let app_version = version_line(&rlocation(&format!(
        "{}/Sources/NexusAgent/Version.swift",
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

    let config_path = rlocation(&format!("{}/release-please-config.json", APP));
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
        "macos/tool/vitruvian-tool.json",
        "macos/Sources/NexusAgentToolCore/Version.swift",
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
        Some(v) if semver(v).unwrap_or((0, 0, 0)) < KIT_THE_TOOL_NEEDS => {
            problems.push(format!(
                "Package.swift builds against kit {}, older than the kit the tool needs ({}.{}.{}): \
                 its handed work can leave a command unanswered",
                v, KIT_THE_TOOL_NEEDS.0, KIT_THE_TOOL_NEEDS.1, KIT_THE_TOOL_NEEDS.2
            ));
        }
        _ => {}
    }

    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{}", p);
        }
        panic!("{} version check(s) failed", problems.len());
    }

    println!(
        "the tool is {}, the app's version, in every file that says so, against kit {} or later",
        manifest_version,
        kit_version.as_deref().unwrap_or("?")
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
    let content = r#"let version = "1.2.3" // x-release-please-version"#;
    let dir = std::env::temp_dir().join("nexus-version-test");
    let _ = fs::create_dir_all(&dir);
    let path = dir.join("Version.swift");
    fs::write(&path, content).unwrap();
    assert_eq!(version_line(&path), Some("1.2.3".into()));

    let no_marker = r#"let version = "1.2.3""#;
    fs::write(&path, no_marker).unwrap();
    assert_eq!(version_line(&path), None);
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn test_extract_kit_version() {
    let swift =
        r#".package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "1.9.0")"#;
    assert_eq!(extract_kit_version(swift), Some("1.9.0".into()));

    let no_match = r#".package(url: "https://github.com/other/lib", from: "2.0.0")"#;
    assert_eq!(extract_kit_version(no_match), None);
}

#[test]
fn test_semver_comparison() {
    assert!((1, 9, 0) >= KIT_THE_TOOL_NEEDS);
    assert!((1, 8, 0) < KIT_THE_TOOL_NEEDS);
    assert!((2, 0, 0) >= KIT_THE_TOOL_NEEDS);
    assert!((0, 9, 0) < KIT_THE_TOOL_NEEDS);
}
