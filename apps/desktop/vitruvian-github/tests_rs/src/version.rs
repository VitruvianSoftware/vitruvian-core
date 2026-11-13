// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::fs;
use std::path::Path;

const KIT_WITH_STATUS_WORDS: (u32, u32, u32) = (1, 4, 0);

pub fn semver(text: &str) -> Option<(u32, u32, u32)> {
    let parts: Vec<&str> = text.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    let major = parts[0].parse::<u32>().ok()?;
    let minor = parts[1].parse::<u32>().ok()?;
    let patch = parts[2].parse::<u32>().ok()?;
    Some((major, minor, patch))
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

pub fn release_please_layout(text: &str) -> String {
    let val = conformance_rs_lib::json::loads(text).expect("invalid JSON");
    let mut out = format_json_utf8(&val, 0);
    out.push('\n');
    out
}

fn extract_version_swift(text: &str) -> Option<String> {
    for line in text.lines() {
        if let Some(rest) = line.trim().strip_prefix("current = \"") {
            if let Some(idx) = rest.find("\" // x-release-please-version") {
                return Some(rest[..idx].to_string());
            }
        }
        if line.contains("current = \"") && line.contains("// x-release-please-version") {
            let start = line.find("current = \"")? + "current = \"".len();
            let end = line[start..].find('"')? + start;
            return Some(line[start..end].to_string());
        }
    }
    None
}

fn extract_kit_version(text: &str) -> Option<String> {
    let marker = "vitruvian-sdk\", from: \"";
    let pos = text.find(marker)? + marker.len();
    let end = text[pos..].find('"')? + pos;
    Some(text[pos..end].to_string())
}

pub fn check_version(base: &Path) -> Vec<String> {
    let mut problems = Vec::new();

    let manifest_text = fs::read_to_string(base.join("vitruvian-tool.json"))
        .expect("cannot read vitruvian-tool.json");
    let manifest_json: serde_json::Value =
        serde_json::from_str(&manifest_text).expect("invalid manifest JSON");
    let manifest_version = manifest_json
        .get("version")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    if manifest_text != release_please_layout(&manifest_text) {
        problems.push(
            "vitruvian-tool.json is not in the layout release-please writes \
             (every array one item a line); the release PR would fail tidy-check"
                .to_string(),
        );
    }

    let swift_text = fs::read_to_string(base.join("Sources/GitHubToolCore/Version.swift"))
        .expect("cannot read Version.swift");
    match extract_version_swift(&swift_text) {
        None => {
            problems.push(
                r#"Version.swift has no `current = "X.Y.Z" // x-release-please-version` line"#
                    .to_string(),
            );
        }
        Some(swift_ver) => {
            if swift_ver != manifest_version {
                problems.push(format!(
                    "Version.swift says {swift_ver}, vitruvian-tool.json says {manifest_version}"
                ));
            }
        }
    }

    if semver(&manifest_version).is_none() {
        problems.push(format!(
            "vitruvian-tool.json's version {manifest_version:?} is not X.Y.Z"
        ));
    }

    let rp_manifest_path = base.join(".release-please-manifest.json");
    if rp_manifest_path.exists() {
        let rp_text =
            fs::read_to_string(&rp_manifest_path).expect("cannot read release-please manifest");
        let rp_json: serde_json::Value =
            serde_json::from_str(&rp_text).expect("invalid release-please manifest JSON");
        let released = rp_json
            .as_object()
            .and_then(|m| m.values().next())
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let config_text = fs::read_to_string(base.join("release-please-config.json"))
            .expect("cannot read release-please-config.json");
        let config_json: serde_json::Value =
            serde_json::from_str(&config_text).expect("invalid config JSON");
        let packages = config_json
            .get("packages")
            .and_then(|p| p.as_object())
            .expect("no packages in config");
        let package = packages.values().next().expect("no package in config");

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

        let extra_files: Vec<String> = package
            .get("extra-files")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .map(|entry| {
                        if let Some(obj) = entry.as_object() {
                            obj.get("path")
                                .and_then(|p| p.as_str())
                                .unwrap_or("")
                                .to_string()
                        } else {
                            entry.as_str().unwrap_or("").to_string()
                        }
                    })
                    .collect()
            })
            .unwrap_or_default();

        for needed in [
            "vitruvian-tool.json",
            "Sources/GitHubToolCore/Version.swift",
        ] {
            if !extra_files.iter().any(|p| p == needed) {
                problems.push(format!(
                    "release-please-config.json does not write the version into {needed}"
                ));
            }
        }
    }

    let package_swift =
        fs::read_to_string(base.join("Package.swift")).expect("cannot read Package.swift");
    match extract_kit_version(&package_swift) {
        None => {
            problems.push(
                "Package.swift does not depend on VitruvianSoftware/vitruvian-sdk with `from:`"
                    .to_string(),
            );
        }
        Some(kit_ver_str) => {
            let kit_ver = semver(&kit_ver_str).unwrap_or((0, 0, 0));
            if kit_ver < KIT_WITH_STATUS_WORDS {
                problems.push(format!(
                    "Package.swift builds against kit {kit_ver_str}, \
                     before App.status took words ({}.{}.{})",
                    KIT_WITH_STATUS_WORDS.0, KIT_WITH_STATUS_WORDS.1, KIT_WITH_STATUS_WORDS.2
                ));
            }
        }
    }

    problems
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semver_valid() {
        assert_eq!(semver("1.2.3"), Some((1, 2, 3)));
        assert_eq!(semver("0.0.0"), Some((0, 0, 0)));
        assert_eq!(semver("10.20.30"), Some((10, 20, 30)));
    }

    #[test]
    fn semver_invalid() {
        assert_eq!(semver("1.2"), None);
        assert_eq!(semver("1.2.3.4"), None);
        assert_eq!(semver("abc"), None);
        assert_eq!(semver(""), None);
        assert_eq!(semver("1.2.x"), None);
    }

    #[test]
    fn release_please_layout_roundtrips() {
        let input = r#"{"version":"1.0.0","name":"test"}"#;
        let formatted = release_please_layout(input);
        assert!(formatted.ends_with('\n'));
        assert!(formatted.contains("  "));
        let reparsed: serde_json::Value = serde_json::from_str(&formatted).unwrap();
        assert_eq!(reparsed["version"], "1.0.0");
    }

    #[test]
    fn release_please_layout_idempotent() {
        let input = "{\n  \"version\": \"1.0.0\"\n}\n";
        let formatted = release_please_layout(input);
        assert_eq!(formatted, input);
    }

    #[test]
    fn extract_version_swift_found() {
        let text = r#"    static let current = "1.2.3" // x-release-please-version"#;
        assert_eq!(extract_version_swift(text), Some("1.2.3".to_string()));
    }

    #[test]
    fn extract_version_swift_missing() {
        let text = "let current = \"1.2.3\"";
        assert_eq!(extract_version_swift(text), None);
    }

    #[test]
    fn extract_kit_version_found() {
        let text = r#".package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "1.4.0"),"#;
        assert_eq!(extract_kit_version(text), Some("1.4.0".to_string()));
    }

    #[test]
    fn extract_kit_version_missing() {
        let text = ".package(url: \"https://example.com/other\", from: \"1.0.0\"),";
        assert_eq!(extract_kit_version(text), None);
    }

    #[test]
    fn kit_below_threshold() {
        let text = r#".package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "1.3.0"),"#;
        let ver = extract_kit_version(text).unwrap();
        let parsed = semver(&ver).unwrap();
        assert!(parsed < KIT_WITH_STATUS_WORDS);
    }

    #[test]
    fn kit_at_threshold() {
        let text = r#".package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "1.4.0"),"#;
        let ver = extract_kit_version(text).unwrap();
        let parsed = semver(&ver).unwrap();
        assert!(parsed >= KIT_WITH_STATUS_WORDS);
    }
}
