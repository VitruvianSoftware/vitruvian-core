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

use std::cmp::Ordering;
use std::fs;
use std::path::{Path, PathBuf};

use crate::utils::config::{parse_top_level_json_object, unquote_json_string};

/// Fixed tag of the rolling dev prerelease published per main commit.
pub const DEV_LATEST_TAG: &str = "tabula-extension-dev-latest";

/// Default GitHub repository hosting the dev-latest release.
pub const DEFAULT_REPO: &str = "VitruvianSoftware/vitruvian-core";

/// Shown wherever stable is requested before the M3 Web Store listing exists.
pub const STABLE_CHANNEL_MESSAGE: &str =
    "The stable channel arrives with the Chrome Web Store listing (M3) — use --channel alpha or beta for now.";

/// Tag prefix of release-please's extension releases (beta channel source).
pub const EXTENSION_RELEASE_TAG_PREFIX: &str = "tabula-extension-v";

/// Default load-unpacked install directory (`~/.tabula/extension`).
pub fn default_extension_dir() -> PathBuf {
    let home = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".tabula").join("extension")
}

/// Models the workflow-stamped `build-info.json` / `build_info.json`.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct BundleInfo {
    pub commit: Option<String>,
    pub built_at: Option<String>,
    pub version: Option<String>,
}

/// Read the bundle's build identity; `None` when absent or unreadable.
pub fn read_bundle_info(dir: &Path) -> Option<BundleInfo> {
    let canonical_path = dir.join("build-info.json");
    let legacy_path = dir.join("build_info.json");
    let target_path = if canonical_path.exists() {
        canonical_path
    } else {
        legacy_path
    };
    let raw = fs::read_to_string(target_path).ok()?;
    let pairs = parse_top_level_json_object(&raw).ok()?;
    let mut info = BundleInfo::default();
    for (k, v) in pairs {
        match k.as_str() {
            "commit" => info.commit = unquote_json_string(&v),
            "builtAt" => info.built_at = unquote_json_string(&v),
            "version" => info.version = unquote_json_string(&v),
            _ => {}
        }
    }
    Some(info)
}

/// A bundle dir must at least carry the extension manifest.
pub fn validate_bundle_dir(dir: &Path) -> Result<(), String> {
    if !dir.join("manifest.json").exists() {
        return Err(format!(
            "Downloaded bundle is missing manifest.json (looked in {})",
            dir.display()
        ));
    }
    Ok(())
}

/// Atomically replace `target_dir` with `staging_dir`.
pub fn atomic_install(staging_dir: &Path, target_dir: &Path) -> Result<(), String> {
    atomic_install_with_renamer(staging_dir, target_dir, |from, to| {
        fs::rename(from, to).map_err(|e| e.to_string())
    })
}

/// Atomically replace `target_dir` with `staging_dir` using a customizable rename function
/// (enabling deterministic fault-injection tests for rollback behavior).
pub fn atomic_install_with_renamer<F>(
    staging_dir: &Path,
    target_dir: &Path,
    mut rename_fn: F,
) -> Result<(), String>
where
    F: FnMut(&Path, &Path) -> Result<(), String>,
{
    validate_bundle_dir(staging_dir)?;
    if let Some(parent) = target_dir.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let old_dir = PathBuf::from(format!(
        "{}.old-{}",
        target_dir.display(),
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&old_dir);

    let had_previous = target_dir.exists();
    if had_previous {
        rename_fn(target_dir, &old_dir)?;
    }

    if let Err(err) = rename_fn(staging_dir, target_dir) {
        if had_previous {
            let _ = rename_fn(&old_dir, target_dir);
        }
        return Err(err);
    }

    if had_previous {
        let _ = fs::remove_dir_all(&old_dir);
    }
    Ok(())
}

/// Switchable release channels for the load-unpacked install.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallChannel {
    Alpha,
    Beta,
}

impl InstallChannel {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Alpha => "alpha",
            Self::Beta => "beta",
        }
    }
}

/// Read the install's channel marker; `None` when absent/corrupt/unknown.
pub fn read_installed_channel(dir: &Path) -> Option<InstallChannel> {
    let raw = fs::read_to_string(dir.join("channel.json")).ok()?;
    let pairs = parse_top_level_json_object(&raw).ok()?;
    for (k, v) in pairs {
        if k == "channel" {
            let ch = unquote_json_string(&v)?;
            return match ch.as_str() {
                "alpha" => Some(InstallChannel::Alpha),
                "beta" => Some(InstallChannel::Beta),
                _ => None,
            };
        }
    }
    None
}

/// Label the install with the channel it was installed from.
pub fn write_installed_channel(dir: &Path, channel: InstallChannel) -> Result<(), String> {
    let payload = format!("{{\n  \"channel\": \"{}\"\n}}\n", channel.as_str());
    fs::write(dir.join("channel.json"), payload).map_err(|e| e.to_string())
}

/// Precedence: explicit flag > installed `channel.json` > `alpha`.
pub fn resolve_channel(
    flag: Option<&str>,
    installed: Option<InstallChannel>,
) -> Result<InstallChannel, String> {
    match flag {
        Some("stable") => Err(STABLE_CHANNEL_MESSAGE.to_string()),
        Some("alpha") => Ok(InstallChannel::Alpha),
        Some("beta") => Ok(InstallChannel::Beta),
        Some(other) => Err(format!(
            "Unknown channel '{other}' — valid: alpha, beta, stable."
        )),
        None => Ok(installed.unwrap_or(InstallChannel::Alpha)),
    }
}

/// Numeric-segment version compare (missing segments are zero).
pub fn compare_semver(a: &str, b: &str) -> Ordering {
    let a_parts: Vec<i64> = a
        .split('.')
        .map(|s| s.parse::<i64>().unwrap_or(0))
        .collect();
    let b_parts: Vec<i64> = b
        .split('.')
        .map(|s| s.parse::<i64>().unwrap_or(0))
        .collect();
    let len = a_parts.len().max(b_parts.len());
    for i in 0..len {
        let av = a_parts.get(i).copied().unwrap_or(0);
        let bv = b_parts.get(i).copied().unwrap_or(0);
        match av.cmp(&bv) {
            Ordering::Equal => continue,
            non_eq => return non_eq,
        }
    }
    Ordering::Equal
}

/// Numeric-segment version difference matching JS `compareSemver(a, b): number`.
pub fn compare_semver_diff(a: &str, b: &str) -> i64 {
    let a_parts: Vec<i64> = a
        .split('.')
        .map(|s| s.parse::<i64>().unwrap_or(0))
        .collect();
    let b_parts: Vec<i64> = b
        .split('.')
        .map(|s| s.parse::<i64>().unwrap_or(0))
        .collect();
    let len = a_parts.len().max(b_parts.len());
    for i in 0..len {
        let av = a_parts.get(i).copied().unwrap_or(0);
        let bv = b_parts.get(i).copied().unwrap_or(0);
        let diff = av - bv;
        if diff != 0 {
            return diff;
        }
    }
    0
}

fn is_numeric_dotted_version(v: &str) -> bool {
    if v.is_empty() {
        return false;
    }
    v.split('.')
        .all(|seg| !seg.is_empty() && seg.bytes().all(|b| b.is_ascii_digit()))
}

/// Pick the newest `tabula-extension-v*` tag from `gh release list --json tagName` output.
pub fn resolve_latest_extension_tag(release_list_json: &str) -> Option<String> {
    let trimmed = release_list_json.trim();
    if !trimmed.starts_with('[') || !trimmed.ends_with(']') {
        return None;
    }
    let body = trimmed[1..trimmed.len() - 1].trim();
    if body.is_empty() {
        return None;
    }

    // Split top-level JSON array elements
    let mut elements = Vec::new();
    let mut start = 0;
    let mut in_string = false;
    let mut escape = false;
    let mut depth = 0i32;
    for (idx, &b) in body.as_bytes().iter().enumerate() {
        if in_string {
            if escape {
                escape = false;
            } else if b == b'\\' {
                escape = true;
            } else if b == b'"' {
                in_string = false;
            }
            continue;
        }
        match b {
            b'"' => in_string = true,
            b'{' | b'[' => depth += 1,
            b'}' | b']' => {
                depth -= 1;
                if depth < 0 {
                    return None;
                }
            }
            b',' if depth == 0 => {
                elements.push(&body[start..idx]);
                start = idx + 1;
            }
            _ => {}
        }
    }
    if in_string || depth != 0 {
        return None;
    }
    elements.push(&body[start..]);

    let mut versions: Vec<String> = Vec::new();
    for elem in elements {
        let pairs = parse_top_level_json_object(elem.trim()).ok()?;
        for (k, v) in pairs {
            if k == "tagName" {
                if let Some(tag) = unquote_json_string(&v) {
                    if let Some(ver) = tag.strip_prefix(EXTENSION_RELEASE_TAG_PREFIX) {
                        if is_numeric_dotted_version(ver) {
                            versions.push(ver.to_string());
                        }
                    }
                }
            }
        }
    }

    if versions.is_empty() {
        return None;
    }
    versions.sort_by(|a, b| compare_semver(a, b));
    let newest = versions.last()?;
    Some(format!("{EXTENSION_RELEASE_TAG_PREFIX}{newest}"))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BetaArtifact {
    pub tag: String,
    pub zip_name: String,
}

/// Beta artifact coordinates from `gh release list --json tagName` output.
pub fn resolve_beta_artifact(release_list_json: &str) -> Option<BetaArtifact> {
    let tag = resolve_latest_extension_tag(release_list_json)?;
    Some(BetaArtifact {
        zip_name: format!("{tag}-chrome.zip"),
        tag,
    })
}
