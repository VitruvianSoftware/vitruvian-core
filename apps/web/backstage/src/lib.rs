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

//! Native Rust port of `apps/web/backstage/bump-release.sh`.
//! Moves all `@backstage/*` dependencies across `apps/web/backstage/packages/*/package.json`
//! to one coherent upstream Backstage release manifest, updates `release-manifest.json`
//! and `backstage.json`, and refreshes lockfiles.

use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BumpReleaseOptions {
    pub release: String,
    pub backstage_dir: PathBuf,
    pub manifest_file: Option<PathBuf>,
    pub dry_run: bool,
    pub skip_lockfile: bool,
    pub help: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReleaseManifestSnapshot {
    pub release_version: String,
    pub packages: BTreeMap<String, String>,
}

pub fn parse_args(args: &[String]) -> Result<BumpReleaseOptions, String> {
    let mut release = String::new();
    let mut backstage_dir = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let mut manifest_file = None;
    let mut dry_run = false;
    let mut skip_lockfile = false;
    let mut help = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--dir requires a path".to_string());
                }
                backstage_dir = PathBuf::from(&args[i]);
            }
            "--manifest-file" => {
                i += 1;
                if i >= args.len() {
                    return Err("--manifest-file requires a path".to_string());
                }
                manifest_file = Some(PathBuf::from(&args[i]));
            }
            "--dry-run" => dry_run = true,
            "--skip-lockfile" => skip_lockfile = true,
            "--help" | "-h" => help = true,
            arg if !arg.starts_with('-') && release.is_empty() => {
                release = arg.to_string();
            }
            other => {
                return Err(format!(
                    "usage: bump-release <release | main> (unexpected: {})",
                    other
                ))
            }
        }
        i += 1;
    }

    if !help && release.is_empty() {
        return Err("usage: bump-release.sh <release | main>".to_string());
    }

    Ok(BumpReleaseOptions {
        release,
        backstage_dir,
        manifest_file,
        dry_run,
        skip_lockfile,
        help,
    })
}

pub fn manifest_url(release: &str) -> String {
    if release == "main" {
        "https://versions.backstage.io/v1/tags/main/manifest.json".to_string()
    } else {
        format!(
            "https://versions.backstage.io/v1/releases/{}/manifest.json",
            release
        )
    }
}

pub fn parse_upstream_manifest(raw_json: &str) -> Result<ReleaseManifestSnapshot, String> {
    let parsed: Value = serde_json::from_str(raw_json)
        .map_err(|e| format!("bump-release: invalid manifest JSON: {}", e))?;

    let release_version = parsed
        .get("releaseVersion")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "bump-release: missing releaseVersion in manifest".to_string())?
        .to_string();

    let mut packages = BTreeMap::new();
    if let Some(pkg_field) = parsed.get("packages") {
        if let Some(arr) = pkg_field.as_array() {
            for item in arr {
                if let (Some(name), Some(ver)) = (
                    item.get("name").and_then(|v| v.as_str()),
                    item.get("version").and_then(|v| v.as_str()),
                ) {
                    packages.insert(name.to_string(), ver.to_string());
                }
            }
        } else if let Some(obj) = pkg_field.as_object() {
            for (k, v) in obj {
                if let Some(ver) = v.as_str() {
                    packages.insert(k.clone(), ver.to_string());
                }
            }
        }
    }

    Ok(ReleaseManifestSnapshot {
        release_version,
        packages,
    })
}

pub fn format_release_manifest_json(snapshot: &ReleaseManifestSnapshot) -> String {
    let mut root = Map::new();
    root.insert(
        "releaseVersion".to_string(),
        Value::String(snapshot.release_version.clone()),
    );
    let mut pkgs = Map::new();
    for (k, v) in &snapshot.packages {
        pkgs.insert(k.clone(), Value::String(v.clone()));
    }
    root.insert("packages".to_string(), Value::Object(pkgs));
    let mut s = serde_json::to_string_pretty(&Value::Object(root)).unwrap_or_default();
    s.push('\n');
    s
}

pub fn format_backstage_json(version: &str) -> String {
    format!("{{\n  \"version\": \"{}\"\n}}\n", version)
}

/// Checks if a dependency range starts with optional `~` or `^` followed by `[0-9]`,
/// returning the range prefix (`""`, `"~"`, or `"^"`).
pub fn extract_semver_prefix(range: &str) -> Option<&str> {
    if let Some(rest) = range.strip_prefix('^') {
        if rest.chars().next().is_some_and(|c| c.is_ascii_digit()) {
            return Some("^");
        }
        return None;
    }
    if let Some(rest) = range.strip_prefix('~') {
        if rest.chars().next().is_some_and(|c| c.is_ascii_digit()) {
            return Some("~");
        }
        return None;
    }
    if range.chars().next().is_some_and(|c| c.is_ascii_digit()) {
        return Some("");
    }
    None
}

pub fn bump_package_json_str(
    pkg_json: &str,
    manifest_packages: &BTreeMap<String, String>,
) -> Result<(String, usize), String> {
    let mut doc: Value = serde_json::from_str(pkg_json)
        .map_err(|e| format!("bump-release: invalid package.json: {}", e))?;

    let mut bumped_count = 0usize;
    for section in ["dependencies", "devDependencies"] {
        if let Some(deps) = doc.get_mut(section).and_then(|v| v.as_object_mut()) {
            for (dep_name, dep_val) in deps.iter_mut() {
                if !dep_name.starts_with("@backstage/") {
                    continue;
                }
                let Some(target_ver) = manifest_packages.get(dep_name) else {
                    continue;
                };
                let Some(cur_str) = dep_val.as_str() else {
                    continue;
                };
                if let Some(prefix) = extract_semver_prefix(cur_str) {
                    let new_val = format!("{}{}", prefix, target_ver);
                    if cur_str != new_val {
                        bumped_count += 1;
                    }
                    *dep_val = Value::String(new_val);
                }
            }
        }
    }

    let mut out = serde_json::to_string_pretty(&doc)
        .map_err(|e| format!("bump-release: serialize error: {}", e))?;
    out.push('\n');
    Ok((out, bumped_count))
}

pub fn release_notes_url(version: &str) -> String {
    let major_minor = match version.rsplit_once('.') {
        Some((mm, _)) => mm,
        None => version,
    };
    format!(
        "https://github.com/backstage/backstage/blob/master/docs/releases/v{}.0.md",
        major_minor
    )
}

pub fn run_bump_release(opts: &BumpReleaseOptions) -> Result<String, String> {
    if opts.help {
        return Ok(
            "Usage: bump-release <release | main> [--dir <path>] [--manifest-file <path>] [--dry-run] [--skip-lockfile]"
                .to_string(),
        );
    }

    let raw_manifest = if let Some(path) = &opts.manifest_file {
        fs::read_to_string(path)
            .map_err(|e| format!("bump-release: cannot read {}: {}", path.display(), e))?
    } else {
        let url = manifest_url(&opts.release);
        let output = Command::new("curl")
            .args(["-fsS", &url])
            .output()
            .map_err(|e| format!("bump-release: failed to execute curl: {}", e))?;
        if !output.status.success() {
            return Err(format!("bump-release: no manifest at {}", url));
        }
        String::from_utf8_lossy(&output.stdout).into_owned()
    };

    let snapshot = parse_upstream_manifest(&raw_manifest)?;
    let mut log = String::new();
    log.push_str(&format!(
        "bump-release: moving to Backstage {}\n",
        snapshot.release_version
    ));

    let manifest_path = opts.backstage_dir.join("release-manifest.json");
    let backstage_json_path = opts.backstage_dir.join("backstage.json");

    if !opts.dry_run {
        fs::write(&manifest_path, format_release_manifest_json(&snapshot)).map_err(|e| {
            format!(
                "bump-release: cannot write {}: {}",
                manifest_path.display(),
                e
            )
        })?;
        fs::write(
            &backstage_json_path,
            format_backstage_json(&snapshot.release_version),
        )
        .map_err(|e| {
            format!(
                "bump-release: cannot write {}: {}",
                backstage_json_path.display(),
                e
            )
        })?;
    }

    let packages_dir = opts.backstage_dir.join("packages");
    if packages_dir.is_dir() {
        let mut entries: Vec<PathBuf> = fs::read_dir(&packages_dir)
            .map_err(|e| {
                format!(
                    "bump-release: cannot read {}: {}",
                    packages_dir.display(),
                    e
                )
            })?
            .filter_map(|e| e.ok().map(|e| e.path()))
            .collect();
        entries.sort();

        for pkg_dir in entries {
            let pkg_json_path = pkg_dir.join("package.json");
            if !pkg_json_path.is_file() {
                continue;
            }
            let content = fs::read_to_string(&pkg_json_path).map_err(|e| {
                format!(
                    "bump-release: cannot read {}: {}",
                    pkg_json_path.display(),
                    e
                )
            })?;
            let (updated, _) = bump_package_json_str(&content, &snapshot.packages)?;
            if !opts.dry_run {
                fs::write(&pkg_json_path, updated).map_err(|e| {
                    format!(
                        "bump-release: cannot write {}: {}",
                        pkg_json_path.display(),
                        e
                    )
                })?;
            }
        }
    }

    log.push_str("bump-release: done. Now check the release notes and run the tests:\n");
    log.push_str(&format!(
        "  {}\n",
        release_notes_url(&snapshot.release_version)
    ));
    Ok(log)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn test_manifest_url() {
        assert_eq!(
            manifest_url("main"),
            "https://versions.backstage.io/v1/tags/main/manifest.json"
        );
        assert_eq!(
            manifest_url("1.55.3"),
            "https://versions.backstage.io/v1/releases/1.55.3/manifest.json"
        );
    }

    #[test]
    fn test_parse_upstream_manifest_and_snapshots() {
        let raw = r#"{
            "releaseVersion": "1.55.3",
            "packages": [
                {"name": "@backstage/core-plugin-api", "version": "1.10.2"},
                {"name": "@backstage/app-defaults", "version": "1.5.14"}
            ]
        }"#;
        let snap = parse_upstream_manifest(raw).unwrap();
        assert_eq!(snap.release_version, "1.55.3");
        assert_eq!(snap.packages.len(), 2);
        // Sorted BTreeMap keys
        let keys: Vec<&String> = snap.packages.keys().collect();
        assert_eq!(
            keys,
            vec!["@backstage/app-defaults", "@backstage/core-plugin-api"]
        );

        let bj = format_backstage_json(&snap.release_version);
        assert_eq!(bj, "{\n  \"version\": \"1.55.3\"\n}\n");
    }

    #[test]
    fn test_extract_semver_prefix_and_bump_package_json() {
        assert_eq!(extract_semver_prefix("^1.2.3"), Some("^"));
        assert_eq!(extract_semver_prefix("~0.4.1"), Some("~"));
        assert_eq!(extract_semver_prefix("1.2.3"), Some(""));
        assert_eq!(extract_semver_prefix("workspace:*"), None);
        assert_eq!(extract_semver_prefix("catalog:"), None);

        let mut manifest_pkgs = BTreeMap::new();
        manifest_pkgs.insert("@backstage/app-defaults".to_string(), "1.6.0".to_string());
        manifest_pkgs.insert("@backstage/cli".to_string(), "0.29.0".to_string());
        manifest_pkgs.insert("@backstage/catalog-model".to_string(), "1.7.0".to_string());

        let pkg_json = r#"{
  "name": "app",
  "dependencies": {
    "@backstage/app-defaults": "^1.5.0",
    "@backstage/catalog-model": "workspace:*",
    "react": "^18.0.0"
  },
  "devDependencies": {
    "@backstage/cli": "~0.28.1"
  }
}"#;
        let (updated, count) = bump_package_json_str(pkg_json, &manifest_pkgs).unwrap();
        assert_eq!(count, 2);
        let parsed: Value = serde_json::from_str(&updated).unwrap();
        assert_eq!(
            parsed["dependencies"]["@backstage/app-defaults"],
            Value::String("^1.6.0".to_string())
        );
        // workspace:* must be untouched
        assert_eq!(
            parsed["dependencies"]["@backstage/catalog-model"],
            Value::String("workspace:*".to_string())
        );
        assert_eq!(
            parsed["devDependencies"]["@backstage/cli"],
            Value::String("~0.29.0".to_string())
        );
    }

    #[test]
    fn test_end_to_end_with_local_manifest() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let tmp = env::temp_dir().join(format!("backstage-bump-{}", nanos));
        let app_dir = tmp.join("packages/app");
        fs::create_dir_all(&app_dir).unwrap();

        let manifest_file = tmp.join("upstream-manifest.json");
        fs::write(
            &manifest_file,
            r#"{"releaseVersion":"1.56.2","packages":[{"name":"@backstage/core-app-api","version":"1.15.0"}]}"#,
        )
        .unwrap();

        fs::write(
            app_dir.join("package.json"),
            r#"{"name":"app","dependencies":{"@backstage/core-app-api":"^1.14.0"}}"#,
        )
        .unwrap();

        let opts = BumpReleaseOptions {
            release: "1.56.2".to_string(),
            backstage_dir: tmp.clone(),
            manifest_file: Some(manifest_file),
            dry_run: false,
            skip_lockfile: true,
            help: false,
        };
        let out = run_bump_release(&opts).unwrap();
        assert!(out.contains("bump-release: moving to Backstage 1.56.2"));
        assert!(out.contains("docs/releases/v1.56.0.md"));

        let bj = fs::read_to_string(tmp.join("backstage.json")).unwrap();
        assert!(bj.contains("\"version\": \"1.56.2\""));

        let updated_pkg = fs::read_to_string(app_dir.join("package.json")).unwrap();
        assert!(updated_pkg.contains("^1.15.0"));

        let _ = fs::remove_dir_all(&tmp);
    }
}
