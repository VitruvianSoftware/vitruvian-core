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

//! Keeps `tools/testinfra/claude_cli.bzl` on the newest Claude Code CLI.
//!
//! The pin holds one version and the npm `dist.integrity` of each platform
//! package. This crate reads that file, asks the npm registry for a version,
//! checks the answer, and rewrites the version and the four hashes together.

use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

/// The pin file, relative to the workspace root.
pub const PIN_REL: &str = "tools/testinfra/claude_cli.bzl";

/// The npm package whose platform builds the pin tracks.
pub const MAIN_PACKAGE: &str = "@anthropic-ai/claude-code";

/// The platform builds the pin must cover, in the order the file lists them.
pub const PLATFORMS: [&str; 4] = ["darwin-arm64", "darwin-x64", "linux-arm64", "linux-x64"];

const REGISTRY: &str = "https://registry.npmjs.org";
const MAX_RESPONSE_BYTES: usize = 4 * 1024 * 1024;
const VERSION_PREFIX: &str = "_VERSION = \"";

/// A version and the integrity of each platform package at that version.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pin {
    pub version: String,
    pub integrity: BTreeMap<String, String>,
}

/// What a run should do once it knows the current pin and the target.
#[derive(Debug, PartialEq, Eq)]
pub enum Plan {
    Current,
    Update { from: String, to: String },
}

pub fn platform_package(platform: &str) -> String {
    format!("{MAIN_PACKAGE}-{platform}")
}

/// `latest`, or an exact `x.y.z` version.
pub fn validate_request(requested: &str) -> Result<(), String> {
    if requested == "latest" {
        return Ok(());
    }
    validate_version(requested)
}

pub fn validate_version(version: &str) -> Result<(), String> {
    let parts: Vec<&str> = version.split('.').collect();
    let ok = parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 9 && p.bytes().all(|b| b.is_ascii_digit()));
    if ok {
        Ok(())
    } else {
        Err(format!("{version:?} is not a plain x.y.z version"))
    }
}

pub fn validate_integrity(integrity: &str) -> Result<(), String> {
    let Some(b64) = integrity.strip_prefix("sha512-") else {
        return Err(format!("{integrity:?} is not a sha512 integrity"));
    };
    let ok = b64.len() == 88
        && b64.ends_with("==")
        && b64[..86]
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/');
    if ok {
        Ok(())
    } else {
        Err(format!(
            "{integrity:?} is not a well-formed sha512 integrity"
        ))
    }
}

pub fn compare_versions(a: &str, b: &str) -> Ordering {
    let nums = |v: &str| -> Vec<u64> { v.split('.').map(|p| p.parse().unwrap_or(0)).collect() };
    nums(a).cmp(&nums(b))
}

fn integrity_line(line: &str) -> Option<(&str, &str)> {
    let rest = line.trim_start().strip_prefix('"')?;
    let (platform, rest) = rest.split_once("\": \"")?;
    let (integrity, tail) = rest.split_once('"')?;
    if tail != "," || !PLATFORMS.contains(&platform) {
        return None;
    }
    Some((platform, integrity))
}

/// Reads the version and hashes out of the pin file.
pub fn parse_pin(text: &str) -> Result<Pin, String> {
    let mut version = None;
    let mut integrity = BTreeMap::new();
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix(VERSION_PREFIX) {
            let v = rest
                .strip_suffix('"')
                .ok_or_else(|| format!("{PIN_REL}: malformed _VERSION line {line:?}"))?;
            if version.replace(v.to_string()).is_some() {
                return Err(format!("{PIN_REL}: more than one _VERSION line"));
            }
        } else if let Some((platform, value)) = integrity_line(line) {
            if integrity
                .insert(platform.to_string(), value.to_string())
                .is_some()
            {
                return Err(format!("{PIN_REL}: {platform} is listed twice"));
            }
        }
    }
    let version = version.ok_or_else(|| format!("{PIN_REL}: no _VERSION line"))?;
    validate_version(&version)?;
    for platform in PLATFORMS {
        let value = integrity
            .get(platform)
            .ok_or_else(|| format!("{PIN_REL}: no integrity for {platform}"))?;
        validate_integrity(value)?;
    }
    Ok(Pin { version, integrity })
}

/// Rewrites the version and hashes, leaving every other byte alone.
pub fn render_pin(text: &str, pin: &Pin) -> Result<String, String> {
    let mut out = String::with_capacity(text.len());
    let mut seen = 0;
    for line in text.split_inclusive('\n') {
        let (body, newline) = match line.strip_suffix('\n') {
            Some(b) => (b, "\n"),
            None => (line, ""),
        };
        if body.starts_with(VERSION_PREFIX) {
            out.push_str(&format!("{VERSION_PREFIX}{}\"{newline}", pin.version));
            seen += 1;
        } else if let Some((platform, old)) = integrity_line(body) {
            let new = pin
                .integrity
                .get(platform)
                .ok_or_else(|| format!("no integrity for {platform}"))?;
            out.push_str(&body.replacen(old, new, 1));
            out.push_str(newline);
            seen += 1;
        } else {
            out.push_str(line);
        }
    }
    if seen != PLATFORMS.len() + 1 {
        return Err(format!(
            "{PIN_REL}: expected 1 version and {} integrity lines, found {seen} lines in all",
            PLATFORMS.len()
        ));
    }
    Ok(out)
}

fn field<'a>(v: &'a serde_json::Value, key: &str, what: &str) -> Result<&'a str, String> {
    v.get(key)
        .and_then(|x| x.as_str())
        .ok_or_else(|| format!("{what}: no string field {key:?}"))
}

/// Checks the main package document and returns its version. Every platform
/// package must be one of its optional dependencies at that same version.
pub fn parse_main(json: &str, requested: &str) -> Result<String, String> {
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("{MAIN_PACKAGE}: invalid JSON: {e}"))?;
    let name = field(&v, "name", MAIN_PACKAGE)?;
    if name != MAIN_PACKAGE {
        return Err(format!(
            "registry answered for {name:?}, not {MAIN_PACKAGE}"
        ));
    }
    let version = field(&v, "version", MAIN_PACKAGE)?.to_string();
    validate_version(&version)?;
    if requested != "latest" && version != requested {
        return Err(format!(
            "asked for {requested}, registry answered {version}"
        ));
    }
    let deps = v
        .get("optionalDependencies")
        .and_then(|d| d.as_object())
        .ok_or_else(|| format!("{MAIN_PACKAGE}@{version}: no optionalDependencies"))?;
    for platform in PLATFORMS {
        let pkg = platform_package(platform);
        match deps.get(&pkg).and_then(|d| d.as_str()) {
            Some(d) if d == version => {}
            other => {
                return Err(format!(
                    "{MAIN_PACKAGE}@{version} depends on {pkg} at {other:?}, expected {version:?}"
                ))
            }
        }
    }
    Ok(version)
}

/// Checks one platform package document and returns its integrity.
pub fn parse_platform(json: &str, platform: &str, version: &str) -> Result<String, String> {
    let pkg = platform_package(platform);
    let v: serde_json::Value =
        serde_json::from_str(json).map_err(|e| format!("{pkg}: invalid JSON: {e}"))?;
    let name = field(&v, "name", &pkg)?;
    let got = field(&v, "version", &pkg)?;
    if name != pkg || got != version {
        return Err(format!(
            "expected {pkg}@{version}, registry answered {name}@{got}"
        ));
    }
    let integrity = v
        .get("dist")
        .map(|d| field(d, "integrity", &pkg))
        .ok_or_else(|| format!("{pkg}@{version}: no dist"))??
        .to_string();
    validate_integrity(&integrity)?;
    Ok(integrity)
}

/// The registry path for a package at a version (or `latest`).
pub fn registry_path(package: &str, version: &str) -> String {
    format!("{package}/{version}")
}

/// Resolves a version through `fetch`, which maps a registry path to JSON.
pub fn resolve(
    fetch: &dyn Fn(&str) -> Result<String, String>,
    requested: &str,
) -> Result<Pin, String> {
    validate_request(requested)?;
    let version = parse_main(&fetch(&registry_path(MAIN_PACKAGE, requested))?, requested)?;
    let mut integrity = BTreeMap::new();
    for platform in PLATFORMS {
        let pkg = platform_package(platform);
        let json = fetch(&registry_path(&pkg, &version))?;
        integrity.insert(
            platform.to_string(),
            parse_platform(&json, platform, &version)?,
        );
    }
    Ok(Pin { version, integrity })
}

/// Decides what to do. Never moves to an older version unless asked by
/// number, and refuses when the registry disagrees with a hash already pinned
/// for the same version: npm versions are immutable, so that means tampering
/// or a broken pin, and a person must look.
pub fn plan(current: &Pin, target: &Pin, explicit_version: bool) -> Result<Plan, String> {
    if current.version == target.version {
        if current.integrity != target.integrity {
            return Err(format!(
                "the registry's hashes for {} differ from the pinned ones; not rewriting them",
                current.version
            ));
        }
        return Ok(Plan::Current);
    }
    if !explicit_version && compare_versions(&target.version, &current.version) == Ordering::Less {
        return Err(format!(
            "registry latest {} is older than the pinned {}; pass --version to move back",
            target.version, current.version
        ));
    }
    Ok(Plan::Update {
        from: current.version.clone(),
        to: target.version.clone(),
    })
}

/// Fetches a registry path over HTTPS with curl.
pub fn fetch_registry(path: &str) -> Result<String, String> {
    let url = format!("{REGISTRY}/{path}");
    let out = Command::new("curl")
        .args([
            "-q",
            "-fsSL",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-redirs",
            "5",
            "--max-filesize",
            "4194304",
            "--connect-timeout",
            "15",
            "--max-time",
            "30",
            "-H",
            "Accept: application/json",
            "-H",
            "User-Agent: VitruvianSoftware/vitruvian-core claude-cli-pin",
            &url,
        ])
        .output()
        .map_err(|e| format!("failed to run curl for {url}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!(
            "curl {url} exited with {}: {}",
            out.status,
            stderr.trim()
        ));
    }
    if out.stdout.len() > MAX_RESPONSE_BYTES {
        return Err(format!(
            "{url}: response larger than {MAX_RESPONSE_BYTES} bytes"
        ));
    }
    String::from_utf8(out.stdout).map_err(|e| format!("{url}: invalid UTF-8: {e}"))
}

/// Serves registry paths from a directory of recorded documents, named
/// `<package name without @anthropic-ai/>.json`. The directory holds one version.
pub fn offline_fetcher(dir: &Path) -> impl Fn(&str) -> Result<String, String> + '_ {
    move |path: &str| {
        let (package, _version) = path
            .rsplit_once('/')
            .ok_or_else(|| format!("bad registry path {path:?}"))?;
        let file = package
            .strip_prefix("@anthropic-ai/")
            .ok_or_else(|| format!("unexpected package {package:?}"))?;
        let full = dir.join(format!("{file}.json"));
        std::fs::read_to_string(&full).map_err(|e| format!("{}: {e}", full.display()))
    }
}

#[cfg(test)]
mod tests;
