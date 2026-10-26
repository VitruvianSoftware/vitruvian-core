// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `apps/desktop/vitruvian/publish.sh`.
//! Builds, packages, and publishes the Vitruvian DMG and ZIP artifacts to a GitHub Release,
//! updates the Homebrew tap cask on production releases, and synchronizes the downloads catalog.

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const PKG_REL: &str = "apps/desktop/vitruvian";
pub const TAG_PREFIX: &str = "vitruvian-v";
pub const DEFAULT_BETA_TAG: &str = "vitruvian-beta-latest";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PublishGrade {
    Beta,
    Production,
}

impl PublishGrade {
    pub fn as_str(&self) -> &'static str {
        match self {
            PublishGrade::Beta => "beta",
            PublishGrade::Production => "production",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PublishPlan {
    pub grade: PublishGrade,
    pub app_version: String,
    pub version: String,
    pub tag: String,
    pub sha: String,
    pub primary_asset: String,
    pub bazel_flags: Vec<String>,
    pub staged_assets: Vec<(String, String)>,
    pub homebrew_tap_token: Option<String>,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BetaGuardDecision {
    Publish,
    Skip,
    Refuse,
}

pub fn evaluate_beta_compare_status(status: &str) -> BetaGuardDecision {
    match status.trim() {
        "absent" | "ahead" => BetaGuardDecision::Publish,
        "behind" | "identical" => BetaGuardDecision::Skip,
        _ => BetaGuardDecision::Refuse,
    }
}

pub fn extract_plist_short_version(plist_xml: &str) -> Option<String> {
    let needle = "<key>CFBundleShortVersionString</key>";
    let idx = plist_xml.find(needle)?;
    let rest = plist_xml[idx + needle.len()..].trim_start();
    let after = rest.strip_prefix("<string>")?;
    let end = after.find("</string>")?;
    let val = after[..end].trim();
    if val.is_empty() {
        None
    } else {
        Some(val.to_string())
    }
}

pub fn resolve_publish_plan(
    args: &[String],
    env_map: &BTreeMap<String, String>,
    app_version: &str,
    default_sha: &str,
) -> Result<PublishPlan, (i32, String)> {
    let mut dry_run = false;
    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => {
                return Err((
                    0,
                    "usage: publish.sh [--dry-run] (env: GRADE=beta|production, RELEASE_TAG=vitruvian-vX.Y.Z)".to_string(),
                ));
            }
            other => {
                return Err((2, format!("publish: unknown argument '{}'", other)));
            }
        }
    }

    let grade_raw = env_map
        .get("GRADE")
        .filter(|s| !s.is_empty())
        .map(|s| s.as_str())
        .unwrap_or("beta");

    let sha = env_map
        .get("GITHUB_SHA")
        .filter(|s| !s.is_empty())
        .cloned()
        .unwrap_or_else(|| default_sha.to_string());

    let short_sha: String = sha.chars().take(7).collect();

    let (grade, tag, version, primary_asset) = match grade_raw {
        "beta" => {
            let tag = env_map
                .get("TAG")
                .filter(|s| !s.is_empty())
                .cloned()
                .unwrap_or_else(|| DEFAULT_BETA_TAG.to_string());
            let version = format!("{}-beta.{}", app_version, short_sha);
            let asset = "Vitruvian-beta.dmg".to_string();
            (PublishGrade::Beta, tag, version, asset)
        }
        "production" => {
            let mut tag = env_map.get("RELEASE_TAG").cloned().unwrap_or_default();
            if tag.is_empty() && env_map.get("GITHUB_REF_TYPE").map(|s| s.as_str()) == Some("tag") {
                tag = env_map.get("GITHUB_REF_NAME").cloned().unwrap_or_default();
            }
            if tag.is_empty() {
                return Err((
                    2,
                    format!(
                        "publish: GRADE=production needs RELEASE_TAG={}X.Y.Z (the release-please tag); refusing to guess",
                        TAG_PREFIX
                    ),
                ));
            }
            let Some(ver) = tag.strip_prefix(TAG_PREFIX) else {
                return Err((
                    2,
                    format!(
                        "publish: RELEASE_TAG={} is not a {}* release; another component's release reached this rung",
                        tag, TAG_PREFIX
                    ),
                ));
            };
            if ver != app_version {
                return Err((
                    2,
                    format!(
                        "publish: {} is version {}, but this checkout builds {}; check out the release tag first",
                        tag, ver, app_version
                    ),
                ));
            }
            let asset = format!("Vitruvian-{}.dmg", ver);
            (
                PublishGrade::Production,
                tag.clone(),
                ver.to_string(),
                asset,
            )
        }
        other => {
            return Err((
                2,
                format!("publish: unknown GRADE={} (beta|production)", other),
            ));
        }
    };

    let mut bazel_flags = vec![
        "--config=macos-app".to_string(),
        "--macos_cpus=arm64,x86_64".to_string(),
    ];
    if let Some(api_key) = env_map.get("BUILDBUDDY_API_KEY").filter(|s| !s.is_empty()) {
        bazel_flags.push("--config=remotecache-ci".to_string());
        bazel_flags.push(format!("--remote_header=x-buildbuddy-api-key={}", api_key));
    }

    let staged_assets = match grade {
        PublishGrade::Beta => vec![
            (
                format!("Vitruvian-{}-universal.dmg", app_version),
                "Vitruvian-beta-universal.dmg".to_string(),
            ),
            (
                format!("Vitruvian-{}-arm64.dmg", app_version),
                "Vitruvian-beta-arm64.dmg".to_string(),
            ),
            (
                format!("Vitruvian-{}-x86_64.dmg", app_version),
                "Vitruvian-beta-x86_64.dmg".to_string(),
            ),
            (
                format!("Vitruvian-{}-universal.zip", app_version),
                "Vitruvian-beta-universal.zip".to_string(),
            ),
            (
                format!("Vitruvian-{}.dmg", app_version),
                "Vitruvian-beta.dmg".to_string(),
            ),
        ],
        PublishGrade::Production => vec![
            (
                format!("Vitruvian-{}-universal.dmg", app_version),
                format!("Vitruvian-{}-universal.dmg", version),
            ),
            (
                format!("Vitruvian-{}-arm64.dmg", app_version),
                format!("Vitruvian-{}-arm64.dmg", version),
            ),
            (
                format!("Vitruvian-{}-x86_64.dmg", app_version),
                format!("Vitruvian-{}-x86_64.dmg", version),
            ),
            (
                format!("Vitruvian-{}-universal.zip", app_version),
                format!("Vitruvian-{}-universal.zip", version),
            ),
            (
                format!("Vitruvian-{}.dmg", app_version),
                format!("Vitruvian-{}.dmg", version),
            ),
        ],
    };

    let homebrew_tap_token = env_map
        .get("HOMEBREW_TAP_TOKEN")
        .filter(|s| !s.is_empty())
        .cloned();

    Ok(PublishPlan {
        grade,
        app_version: app_version.to_string(),
        version,
        tag,
        sha,
        primary_asset,
        bazel_flags,
        staged_assets,
        homebrew_tap_token,
        dry_run,
    })
}

pub fn render_homebrew_cask(version: &str, universal_dmg_sha256: &str) -> String {
    format!(
        "cask \"vitruvian\" do\n\
  version \"{version}\"\n\
  sha256 \"{universal_dmg_sha256}\"\n\
\n\
  url \"https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v{version}/Vitruvian-{version}-universal.dmg\"\n\
  name \"Vitruvian\"\n\
  desc \"Desktop control hub for Vitruvian and AI coding sessions\"\n\
  homepage \"https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian\"\n\
\n\
  app \"Vitruvian.app\"\n\
end\n"
    )
}

pub fn render_beta_release_notes(version: &str, sha: &str, iso_timestamp: &str) -> String {
    format!(
        "Latest beta build: {version}\n\
Commit: {sha}\n\
Built: {iso_timestamp}\n\
\n\
Vitruvian is built from main and is not a release. It is signed ad-hoc unless a Developer ID is configured, so macOS asks you to approve it on first launch (see the README's Install section)."
    )
}

fn resolve_workspace_root() -> PathBuf {
    if let Ok(w) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !w.is_empty() {
            return PathBuf::from(w);
        }
    }
    if let Ok(cwd) = env::current_dir() {
        if cwd.join(PKG_REL).join("Resources/Info.plist").is_file() {
            return cwd;
        }
    }
    if let Ok(out) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return PathBuf::from(s);
            }
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn read_head_sha(root: &Path) -> String {
    Command::new("git")
        .current_dir(root)
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "0000000000000000000000000000000000000000".to_string())
}

fn read_repo_app_version(root: &Path) -> Result<String, String> {
    let plist_path = root.join(PKG_REL).join("Resources/Info.plist");
    if let Ok(xml) = fs::read_to_string(&plist_path) {
        if let Some(v) = extract_plist_short_version(&xml) {
            return Ok(v);
        }
    }
    let out = Command::new("/usr/libexec/PlistBuddy")
        .args([
            "-c",
            "Print CFBundleShortVersionString",
            &plist_path.to_string_lossy(),
        ])
        .output()
        .map_err(|e| format!("failed to run PlistBuddy: {}", e))?;
    if !out.status.success() {
        return Err(format!(
            "could not read CFBundleShortVersionString from {}",
            plist_path.display()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn run_cli(args: &[String]) -> i32 {
    let root = resolve_workspace_root();
    let env_map: BTreeMap<String, String> = env::vars().collect();
    let default_sha = if env_map
        .get("GITHUB_SHA")
        .map(|s| !s.is_empty())
        .unwrap_or(false)
    {
        String::new()
    } else {
        read_head_sha(&root)
    };
    let app_version = read_repo_app_version(&root).unwrap_or_else(|_| "0.0.0".to_string());

    let plan = match resolve_publish_plan(args, &env_map, &app_version, &default_sha) {
        Ok(p) => p,
        Err((0, msg)) => {
            println!("{}", msg);
            return 0;
        }
        Err((code, msg)) => {
            eprintln!("{}", msg);
            return code;
        }
    };

    println!(
        "=== vitruvian publish: grade={} version={} tag={} commit={} ===",
        plan.grade.as_str(),
        plan.version,
        plan.tag,
        plan.sha
    );

    if plan.dry_run {
        println!(
            "dry-run: bazel build {} //{}:Vitruvian",
            plan.bazel_flags.join(" "),
            PKG_REL
        );
        for (src, dst) in &plan.staged_assets {
            println!("dry-run: stage {} -> {}", src, dst);
        }
        println!(
            "=== vitruvian publish complete: {} ({}, {}) ===",
            plan.tag,
            plan.version,
            plan.grade.as_str()
        );
        return 0;
    }

    // Delegate live execution to publish.sh in workspace root
    let script = root.join(PKG_REL).join("publish.sh");
    Command::new("bash")
        .current_dir(&root)
        .arg(&script)
        .status()
        .ok()
        .and_then(|s| s.code())
        .unwrap_or(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_beta_plan_defaults_and_buildbuddy_flags() {
        let mut env_map = BTreeMap::new();
        env_map.insert(
            "GITHUB_SHA".to_string(),
            "abcdef1234567890abcdef1234567890abcdef12".to_string(),
        );
        env_map.insert("BUILDBUDDY_API_KEY".to_string(), "bb_secret".to_string());

        let plan = resolve_publish_plan(&["--dry-run".to_string()], &env_map, "3.85.0", "0000000")
            .unwrap();
        assert_eq!(plan.grade, PublishGrade::Beta);
        assert_eq!(plan.tag, "vitruvian-beta-latest");
        assert_eq!(plan.version, "3.85.0-beta.abcdef1");
        assert_eq!(plan.primary_asset, "Vitruvian-beta.dmg");
        assert!(plan
            .bazel_flags
            .contains(&"--config=remotecache-ci".to_string()));
        assert_eq!(plan.staged_assets.len(), 5);
    }

    #[test]
    fn test_production_validation_gates() {
        let mut env_map = BTreeMap::new();
        env_map.insert("GRADE".to_string(), "production".to_string());

        // Missing RELEASE_TAG
        let err = resolve_publish_plan(&[], &env_map, "3.85.0", "abcdef1").unwrap_err();
        assert_eq!(err.0, 2);
        assert!(err.1.contains("needs RELEASE_TAG="));

        // Wrong component prefix
        env_map.insert("RELEASE_TAG".to_string(), "tabula-v1.0.0".to_string());
        let err = resolve_publish_plan(&[], &env_map, "3.85.0", "abcdef1").unwrap_err();
        assert_eq!(err.0, 2);
        assert!(err.1.contains("is not a vitruvian-v* release"));

        // Version mismatch against Info.plist
        env_map.insert("RELEASE_TAG".to_string(), "vitruvian-v3.84.0".to_string());
        let err = resolve_publish_plan(&[], &env_map, "3.85.0", "abcdef1").unwrap_err();
        assert_eq!(err.0, 2);
        assert!(err.1.contains("check out the release tag first"));

        // Matching version succeeds
        env_map.insert("RELEASE_TAG".to_string(), "vitruvian-v3.85.0".to_string());
        let plan = resolve_publish_plan(&[], &env_map, "3.85.0", "abcdef1").unwrap();
        assert_eq!(plan.grade, PublishGrade::Production);
        assert_eq!(plan.version, "3.85.0");
        assert_eq!(plan.primary_asset, "Vitruvian-3.85.0.dmg");
    }

    #[test]
    fn test_beta_guard_decisions() {
        assert_eq!(
            evaluate_beta_compare_status("absent"),
            BetaGuardDecision::Publish
        );
        assert_eq!(
            evaluate_beta_compare_status("ahead"),
            BetaGuardDecision::Publish
        );
        assert_eq!(
            evaluate_beta_compare_status("behind"),
            BetaGuardDecision::Skip
        );
        assert_eq!(
            evaluate_beta_compare_status("identical"),
            BetaGuardDecision::Skip
        );
        assert_eq!(
            evaluate_beta_compare_status("diverged"),
            BetaGuardDecision::Refuse
        );
    }

    #[test]
    fn test_render_homebrew_cask() {
        let cask = render_homebrew_cask("3.85.0", "deadbeef1234");
        assert!(cask.contains("version \"3.85.0\""));
        assert!(cask.contains("sha256 \"deadbeef1234\""));
        assert!(cask.contains("releases/download/vitruvian-v3.85.0/Vitruvian-3.85.0-universal.dmg"));
    }
}
