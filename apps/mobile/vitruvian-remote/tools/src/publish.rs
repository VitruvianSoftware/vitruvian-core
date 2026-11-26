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

use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

const REMOTE_ANDROID_PLATFORMS: &str =
    "--android_platforms=@rules_android//:arm64-v8a,@rules_android//:x86_64";
const REMOTE_APK_LABEL: &str = "//apps/mobile/vitruvian-remote:app.apk";
const REMOTE_APK_SUFFIX: &str = "/apps/mobile/vitruvian-remote/app.apk";

pub fn select_single_artifact_path(stdout: &str, suffix: &str) -> Result<PathBuf, String> {
    let matches: Vec<&str> = stdout
        .lines()
        .map(str::trim)
        .filter(|line| line.ends_with(suffix))
        .collect();
    if matches.len() != 1 {
        return Err(format!(
            "expected exactly one output ending with {suffix}, got {}:\n{}",
            matches.len(),
            if matches.is_empty() {
                "<none>".to_string()
            } else {
                matches.join("\n")
            }
        ));
    }
    Ok(PathBuf::from(matches[0]))
}

pub fn absolute_artifact_path(workspace: &Path, rel: &Path) -> PathBuf {
    if rel.is_absolute() {
        rel.to_path_buf()
    } else {
        workspace.join(rel)
    }
}

fn locate_apk() -> Result<PathBuf, String> {
    let ws_output = Command::new("bazel")
        .args(["info", "workspace"])
        .output()
        .map_err(|e| format!("failed to run bazel info workspace: {}", e))?;
    if !ws_output.status.success() {
        return Err(format!(
            "bazel info workspace failed:\n{}",
            String::from_utf8_lossy(&ws_output.stderr)
        ));
    }
    let ws_str = String::from_utf8_lossy(&ws_output.stdout);
    let ws_trimmed = ws_str.trim();
    if ws_trimmed.is_empty() {
        return Err("bazel info workspace returned an empty path".to_string());
    }
    let workspace = PathBuf::from(ws_trimmed);

    let output = Command::new("bazel")
        .args([
            "cquery",
            REMOTE_ANDROID_PLATFORMS,
            "--output=files",
            REMOTE_APK_LABEL,
        ])
        .output()
        .map_err(|e| format!("failed to run bazel cquery: {}", e))?;
    if !output.status.success() {
        return Err(format!(
            "bazel cquery {} failed:\n{}",
            REMOTE_APK_LABEL,
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let rel = select_single_artifact_path(&stdout, REMOTE_APK_SUFFIX)?;
    let path = absolute_artifact_path(&workspace, &rel);
    if !path.is_file() {
        return Err(format!(
            "Expected APK output at {} not found",
            path.display()
        ));
    }
    Ok(path)
}

pub fn strip_version_prefix(tag: &str) -> &str {
    let s = tag.strip_prefix("vitruvian-remote-v").unwrap_or(tag);
    s.strip_prefix('v').unwrap_or(s)
}

pub fn version_from_manifest(manifest_path: &Path, key: &str) -> Option<String> {
    let content = fs::read_to_string(manifest_path).ok()?;
    let pattern = format!("\"{}\"", key);
    let idx = content.find(&pattern)?;
    let rest = &content[idx + pattern.len()..];
    let colon = rest.find(':')?;
    let after_colon = &rest[colon + 1..];
    let open_quote = after_colon.find('"')?;
    let after_open = &after_colon[open_quote + 1..];
    let close_quote = after_open.find('"')?;
    let version = &after_open[..close_quote];
    if version.is_empty() {
        None
    } else {
        Some(version.to_string())
    }
}

pub fn version_from_build_file(build_path: &Path) -> Option<String> {
    let content = fs::read_to_string(build_path).ok()?;
    let pattern = "\"versionName\":";
    let idx = content.find(pattern)?;
    let rest = &content[idx + pattern.len()..];
    let open_quote = rest.find('"')?;
    let after_open = &rest[open_quote + 1..];
    let close_quote = after_open.find('"')?;
    let version = &after_open[..close_quote];
    if version.is_empty() {
        None
    } else {
        Some(version.to_string())
    }
}

pub fn min_sdk_from_build_file(build_path: &Path) -> Option<String> {
    let content = fs::read_to_string(build_path).ok()?;
    let pattern = "\"minSdkVersion\":";
    let idx = content.find(pattern)?;
    let rest = &content[idx + pattern.len()..];
    let open_quote = rest.find('"')?;
    let after_open = &rest[open_quote + 1..];
    let close_quote = after_open.find('"')?;
    let value = &after_open[..close_quote];
    if value.is_empty() || !value.bytes().all(|b| b.is_ascii_digit()) {
        None
    } else {
        Some(value.to_string())
    }
}

/// The versionCode BUILD stamps: `major*10000 + minor*100 + patch`, for plain
/// `X.Y.Z` with minor and patch under 100 (the app refuses anything else).
pub fn version_code(version: &str) -> Option<u64> {
    let parts: Vec<&str> = version.split('.').collect();
    if parts.len() != 3
        || parts
            .iter()
            .any(|p| p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit()))
    {
        return None;
    }
    let n: Vec<u64> = parts
        .iter()
        .map(|p| p.parse().ok())
        .collect::<Option<_>>()?;
    if n[1] > 99 || n[2] > 99 || parts[1].len() > 2 || parts[2].len() > 2 {
        return None;
    }
    Some(n[0] * 10000 + n[1] * 100 + n[2])
}

/// `[text](url)` -> `text`, for every link in `line`.
fn unlink(line: &str) -> String {
    let mut out = String::new();
    let mut rest = line;
    while let Some(open) = rest.find('[') {
        let after = &rest[open + 1..];
        match (after.find("]("), after.find(']')) {
            (Some(close), Some(first)) if close == first => {
                let tail = &after[close + 2..];
                if let Some(end) = tail.find(')') {
                    out.push_str(&rest[..open]);
                    out.push_str(&after[..close]);
                    rest = &tail[end + 1..];
                    continue;
                }
                out.push_str(&rest[..=open]);
                rest = after;
            }
            _ => {
                out.push_str(&rest[..=open]);
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// One CHANGELOG bullet as a sentence for the phone: no scope, no PR or commit links.
fn clean_note(bullet: &str) -> String {
    let mut s = bullet.trim().to_string();
    // release-please's trailing "([#123](...)) ([abc1234](...))" groups.
    loop {
        let t = s.trim_end();
        if t.ends_with("))") {
            if let Some(start) = t.rfind(" ([") {
                s = t[..start].to_string();
                continue;
            }
        }
        break;
    }
    // A leading "**scope:** ".
    if s.starts_with("**") {
        if let Some(end) = s[2..].find(":**") {
            s = s[2 + end + 3..].trim_start().to_string();
        }
    }
    unlink(&s).trim().to_string()
}

/// The release date and the changes CHANGELOG.md lists for `version`.
pub fn release_notes(changelog: &str, version: &str) -> (Option<String>, Vec<String>) {
    let heading_link = format!("## [{}]", version);
    let heading_plain = format!("## {}", version);
    let mut date = None;
    let mut notes = Vec::new();
    let mut inside = false;
    for line in changelog.lines() {
        if line.starts_with("## ") {
            if inside {
                break;
            }
            let rest = line
                .strip_prefix(&heading_link)
                .or_else(|| line.strip_prefix(&heading_plain));
            if let Some(rest) = rest {
                if rest.is_empty() || rest.starts_with('(') || rest.starts_with(' ') {
                    inside = true;
                    if let (Some(open), Some(close)) = (rest.rfind('('), rest.rfind(')')) {
                        let d = &rest[open + 1..close];
                        if d.len() == 10 && d.as_bytes()[4] == b'-' && d.as_bytes()[7] == b'-' {
                            date = Some(d.to_string());
                        }
                    }
                }
            }
            continue;
        }
        if inside {
            if let Some(bullet) = line.strip_prefix("* ") {
                let note = clean_note(bullet);
                if !note.is_empty() {
                    notes.push(note);
                }
            }
        }
    }
    (date, notes)
}

fn json_string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// What the app's update check reads (UpdateFeed.kt): the release's version,
/// APK, size, SHA-256 and changes. Laid out as prettier lays out JSON, so the
/// file the release opens a pull request with passes the format check as is.
pub struct Feed<'a> {
    pub version: &'a str,
    pub version_code: u64,
    pub min_sdk: &'a str,
    pub published: &'a str,
    pub url: &'a str,
    pub size: u64,
    pub sha256: &'a str,
    pub notes: &'a [String],
}

pub fn render_feed(feed: &Feed) -> String {
    let notes = if feed.notes.is_empty() {
        "[]".to_string()
    } else {
        let quoted: Vec<String> = feed.notes.iter().map(|n| json_string(n)).collect();
        let inline = format!("[{}]", quoted.join(", "));
        // prettier keeps an array on the key's line when it fits in 80 columns.
        if "  \"notes\": ".len() + inline.len() <= 80 {
            inline
        } else {
            let lines: Vec<String> = quoted.iter().map(|q| format!("    {}", q)).collect();
            format!("[\n{}\n  ]", lines.join(",\n"))
        }
    };
    format!(
        "{{\n  \"kind\": \"vitruvian-android-update\",\n  \"schema\": 1,\n  \"packageName\": \"dev.vitruvian.remote\",\n  \"version\": {},\n  \"versionCode\": {},\n  \"minSdk\": {},\n  \"published\": {},\n  \"apk\": {{\n    \"url\": {},\n    \"size\": {},\n    \"sha256\": {}\n  }},\n  \"notes\": {}\n}}\n",
        json_string(feed.version),
        feed.version_code,
        feed.min_sdk,
        json_string(feed.published),
        json_string(feed.url),
        feed.size,
        json_string(feed.sha256),
        notes,
    )
}

pub const FEED_NAME: &str = "vitruvian-remote-update.json";

pub fn resolve_version(tag: &str, app_dir: &Path) -> String {
    if !tag.is_empty() {
        let v = strip_version_prefix(tag);
        if !v.is_empty() {
            return v.to_string();
        }
    }

    if let Some(v) = version_from_manifest(
        &app_dir.join(".release-please-manifest.json"),
        "apps/mobile/vitruvian-remote",
    ) {
        return v;
    }

    if let Some(v) = version_from_build_file(&app_dir.join("BUILD")) {
        return v;
    }

    "0.1.0".to_string()
}

fn resolve_android_home() -> Option<String> {
    if let Ok(home) = env::var("ANDROID_HOME") {
        if !home.is_empty() {
            return Some(home);
        }
    }
    let fallback = "/usr/local/lib/android/sdk";
    if Path::new(fallback).is_dir() {
        return Some(fallback.to_string());
    }
    None
}

fn generate_sha256(dist_dir: &Path, apk_name: &str) -> io::Result<()> {
    let sha_file = dist_dir.join(format!("{}.sha256", apk_name));
    let result = Command::new("sha256sum")
        .arg(apk_name)
        .current_dir(dist_dir)
        .output();

    let output = match result {
        Ok(o) if o.status.success() => o,
        _ => Command::new("shasum")
            .args(["-a", "256", apk_name])
            .current_dir(dist_dir)
            .output()?,
    };

    if !output.status.success() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "both sha256sum and shasum failed",
        ));
    }

    fs::write(&sha_file, &output.stdout)?;
    io::stdout().write_all(&output.stdout)?;
    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let dry_run = args.iter().any(|a| a == "--dry-run");

    let tag = env::var("TAG").unwrap_or_default();
    let version_env = env::var("VERSION").unwrap_or_default();

    let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let app_dir = if cwd.join("apps/mobile/vitruvian-remote/BUILD").is_file() {
        let sub = cwd.join("apps/mobile/vitruvian-remote");
        let _ = env::set_current_dir(&sub);
        sub
    } else {
        cwd
    };
    let version = if !version_env.is_empty() {
        version_env
    } else {
        resolve_version(&tag, &app_dir)
    };

    let tag_suffix = if tag.is_empty() {
        String::new()
    } else {
        format!(" (tag: {})", tag)
    };
    println!(
        "==> Packaging Vitruvian Remote release v{}{}",
        version, tag_suffix
    );

    let android_home = match resolve_android_home() {
        Some(home) => {
            env::set_var("ANDROID_HOME", &home);
            home
        }
        None => {
            if dry_run {
                println!("==> Dry run: ANDROID_HOME is unset; skipping local build check.");
                return 0;
            } else {
                eprintln!("Error: ANDROID_HOME is unset. A local Android SDK is required to build the release APK.");
                return 1;
            }
        }
    };
    let _ = android_home;

    println!("==> Building Android release APK with Bazel");
    let build_status = Command::new("bazel")
        .args([
            "build",
            REMOTE_ANDROID_PLATFORMS,
            "//apps/mobile/vitruvian-remote:app",
        ])
        .status();

    match build_status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!(
                "Error: bazel build failed with exit code {}",
                s.code().unwrap_or(-1)
            );
            return 1;
        }
        Err(e) => {
            eprintln!("Error: failed to run bazel: {}", e);
            return 1;
        }
    }

    let bin_apk = match locate_apk() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("Error: {}", e);
            return 1;
        }
    };

    let dist_dir = app_dir.join("dist");
    let _ = fs::remove_dir_all(&dist_dir);
    if let Err(e) = fs::create_dir_all(&dist_dir) {
        eprintln!("Error: failed to create dist directory: {}", e);
        return 1;
    }

    let apk_name = format!("VitruvianRemote-{}.apk", version);
    let dest_apk = dist_dir.join(&apk_name);
    if let Err(e) = fs::copy(&bin_apk, &dest_apk) {
        eprintln!("Error: failed to copy APK: {}", e);
        return 1;
    }

    println!("==> Generating SHA256 checksum");
    if let Err(e) = generate_sha256(&dist_dir, &apk_name) {
        eprintln!("Error: failed to generate SHA256: {}", e);
        return 1;
    }

    let sha_text =
        fs::read_to_string(dist_dir.join(format!("{}.sha256", apk_name))).unwrap_or_default();
    let sha = sha_text.split_whitespace().next().unwrap_or("").to_string();
    let size = fs::metadata(&dest_apk).map(|m| m.len()).unwrap_or(0);
    let code = match version_code(&version) {
        Some(c) => c,
        None => {
            eprintln!(
                "Error: {} is not a plain X.Y.Z version; the update feed needs one",
                version
            );
            return 1;
        }
    };
    let min_sdk =
        min_sdk_from_build_file(&app_dir.join("BUILD")).unwrap_or_else(|| "26".to_string());
    let changelog = fs::read_to_string(app_dir.join("CHANGELOG.md")).unwrap_or_default();
    let (date, notes) = release_notes(&changelog, &version);
    let url = format!(
        "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-remote-v{v}/VitruvianRemote-{v}.apk",
        v = version
    );
    if sha.len() != 64 || size == 0 {
        eprintln!("Error: could not read the APK's size and SHA-256 for the update feed");
        return 1;
    }
    let feed_path = dist_dir.join(FEED_NAME);
    let feed = render_feed(&Feed {
        version: &version,
        version_code: code,
        min_sdk: &min_sdk,
        published: date.as_deref().unwrap_or(""),
        url: &url,
        size,
        sha256: &sha,
        notes: &notes,
    });
    if let Err(e) = fs::write(&feed_path, feed) {
        eprintln!("Error: failed to write the update feed: {}", e);
        return 1;
    }
    println!(
        "==> Wrote the update feed {} ({} notes)",
        FEED_NAME,
        notes.len()
    );

    if dry_run {
        println!("==> Dry run: verified release artifact successfully created in dist/:");
        if let Ok(meta) = fs::metadata(&dest_apk) {
            println!("  {} ({} bytes)", apk_name, meta.len());
        }
        if let Ok(meta) = fs::metadata(dist_dir.join(format!("{}.sha256", apk_name))) {
            println!("  {}.sha256 ({} bytes)", apk_name, meta.len());
        }
        return 0;
    }

    if tag.is_empty() {
        println!("==> No TAG specified; packages created in dist/. Skipping upload.");
        return 0;
    }

    let repo = env::var("GITHUB_REPOSITORY")
        .unwrap_or_else(|_| "VitruvianSoftware/vitruvian-core".to_string());
    println!(
        "==> Attaching release artifacts to GitHub Release {} in {}",
        tag, repo
    );

    let sha_path = dist_dir.join(format!("{}.sha256", apk_name));
    let upload_status = Command::new("gh")
        .args([
            "release",
            "upload",
            &tag,
            dest_apk.to_str().unwrap_or(""),
            sha_path.to_str().unwrap_or(""),
            feed_path.to_str().unwrap_or(""),
            "--repo",
            &repo,
            "--clobber",
        ])
        .status();

    match upload_status {
        Ok(s) if s.success() => {
            println!("==> Upload completed successfully.");
            0
        }
        Ok(s) => {
            eprintln!(
                "Error: gh release upload failed with exit code {}",
                s.code().unwrap_or(-1)
            );
            1
        }
        Err(e) => {
            eprintln!("Error: failed to run gh: {}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn strip_vitruvian_remote_v_prefix() {
        assert_eq!(strip_version_prefix("vitruvian-remote-v1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_v_prefix() {
        assert_eq!(strip_version_prefix("v1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_no_prefix() {
        assert_eq!(strip_version_prefix("1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_vitruvian_remote_v_then_v() {
        assert_eq!(strip_version_prefix("vitruvian-remote-vv1.0.0"), "1.0.0");
    }

    #[test]
    fn manifest_parsing() {
        let p = env::temp_dir().join("publish_test_manifest");
        let _ = fs::create_dir_all(&p);
        let dir = TempDir(p);
        let manifest = dir.path().join("manifest.json");
        fs::write(
            &manifest,
            r#"{"apps/mobile/vitruvian-remote": "2.5.1", "other": "1.0.0"}"#,
        )
        .unwrap();
        assert_eq!(
            version_from_manifest(&manifest, "apps/mobile/vitruvian-remote"),
            Some("2.5.1".to_string())
        );
    }

    #[test]
    fn manifest_missing_key() {
        let dir = env::temp_dir().join("publish_test_manifest_miss");
        let _ = fs::create_dir_all(&dir);
        let manifest = dir.join("manifest.json");
        fs::write(&manifest, r#"{"other": "1.0.0"}"#).unwrap();
        assert_eq!(
            version_from_manifest(&manifest, "apps/mobile/vitruvian-remote"),
            None
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn manifest_file_missing() {
        let missing = PathBuf::from("/nonexistent/manifest.json");
        assert_eq!(
            version_from_manifest(&missing, "apps/mobile/vitruvian-remote"),
            None
        );
    }

    #[test]
    fn build_file_version_parsing() {
        let dir = env::temp_dir().join("publish_test_build");
        let _ = fs::create_dir_all(&dir);
        let build = dir.join("BUILD");
        fs::write(
            &build,
            r#"android_binary(name = "app", "versionName": "3.0.1")"#,
        )
        .unwrap();
        assert_eq!(version_from_build_file(&build), Some("3.0.1".to_string()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn build_file_missing() {
        let missing = PathBuf::from("/nonexistent/BUILD");
        assert_eq!(version_from_build_file(&missing), None);
    }

    #[test]
    fn resolve_version_from_tag() {
        let dir = env::temp_dir().join("publish_test_resolve_tag");
        let _ = fs::create_dir_all(&dir);
        assert_eq!(resolve_version("vitruvian-remote-v4.0.0", &dir), "4.0.0");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_version_from_v_tag() {
        let dir = env::temp_dir().join("publish_test_resolve_vtag");
        let _ = fs::create_dir_all(&dir);
        assert_eq!(resolve_version("v5.1.0", &dir), "5.1.0");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_version_fallback_default() {
        let dir = env::temp_dir().join("publish_test_resolve_default");
        let _ = fs::create_dir_all(&dir);
        assert_eq!(resolve_version("", &dir), "0.1.0");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_version_from_manifest_file() {
        let dir = env::temp_dir().join("publish_test_resolve_manifest");
        let _ = fs::create_dir_all(&dir);
        let manifest = dir.join(".release-please-manifest.json");
        fs::write(&manifest, r#"{"apps/mobile/vitruvian-remote": "7.8.9"}"#).unwrap();
        assert_eq!(resolve_version("", &dir), "7.8.9");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn version_codes_follow_build() {
        assert_eq!(version_code("0.1.46"), Some(146));
        assert_eq!(version_code("1.2.3"), Some(10203));
        assert_eq!(version_code("0.1.100"), None);
        assert_eq!(version_code("1.2"), None);
        assert_eq!(version_code("1.2.3-rc.1"), None);
        assert_eq!(version_code("dev"), None);
    }

    #[test]
    fn min_sdk_is_read_from_build() {
        let dir = env::temp_dir().join("publish_test_min_sdk");
        let _ = fs::create_dir_all(&dir);
        let build = dir.join("BUILD");
        fs::write(&build, "_M = {\n    \"minSdkVersion\": \"26\",\n}").unwrap();
        assert_eq!(min_sdk_from_build_file(&build), Some("26".to_string()));
        let _ = fs::remove_dir_all(&dir);
    }

    const CHANGELOG: &str = "# Changelog\n\n## [0.1.47](https://github.com/x/compare/a...b) (2026-11-18)\n\n\n### Features\n\n* **vitruvian-remote:** update the app from Settings, About ([#5111](https://github.com/x/issues/5111)) ([abc1234](https://github.com/x/commit/abc1234))\n* plain change with a [link](https://example.com) inside\n\n### Bug Fixes\n\n* **sentry:** quieter \"crash\" reports ([#1](u)) ([2](v))\n\n## [0.1.46](https://github.com/x/compare/c...d) (2026-11-16)\n\n* older change\n";

    #[test]
    fn notes_come_from_this_versions_section_only() {
        let (date, notes) = release_notes(CHANGELOG, "0.1.47");
        assert_eq!(date.as_deref(), Some("2026-11-18"));
        assert_eq!(
            notes,
            vec![
                "update the app from Settings, About".to_string(),
                "plain change with a link inside".to_string(),
                "quieter \"crash\" reports".to_string(),
            ]
        );
        let (date, notes) = release_notes(CHANGELOG, "0.1.46");
        assert_eq!(date.as_deref(), Some("2026-11-16"));
        assert_eq!(notes, vec!["older change".to_string()]);
        // 0.1.4 must not match the 0.1.47 or 0.1.46 headings.
        assert_eq!(release_notes(CHANGELOG, "0.1.4"), (None, vec![]));
    }

    #[test]
    fn the_feed_is_what_the_app_reads_laid_out_as_prettier_does() {
        let notes =
            vec!["move the Android apps to Sentry 8 with one shared privacy setup".to_string()];
        let feed = render_feed(&Feed {
            version: "0.1.46",
            version_code: 146,
            min_sdk: "26",
            published: "2026-11-16",
            url: "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-remote-v0.1.46/VitruvianRemote-0.1.46.apk",
            size: 9682039,
            sha256: "6e751e3699e145c06c97936167ef687cd4dcb28eaa291fb9bf2c9190c25ba7fd",
            notes: &notes,
        });
        // Byte for byte what prettier leaves alone, and what the app's
        // update_feed_test reads from catalog/android/ with the app's own parser.
        let expected = r#"{
  "kind": "vitruvian-android-update",
  "schema": 1,
  "packageName": "dev.vitruvian.remote",
  "version": "0.1.46",
  "versionCode": 146,
  "minSdk": 26,
  "published": "2026-11-16",
  "apk": {
    "url": "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-remote-v0.1.46/VitruvianRemote-0.1.46.apk",
    "size": 9682039,
    "sha256": "6e751e3699e145c06c97936167ef687cd4dcb28eaa291fb9bf2c9190c25ba7fd"
  },
  "notes": ["move the Android apps to Sentry 8 with one shared privacy setup"]
}
"#;
        assert_eq!(feed, expected);
        let quoted = ["a \"q\"".to_string()];
        let short = render_feed(&Feed {
            notes: &quoted,
            ..sample()
        });
        assert!(short.contains("  \"notes\": [\"a \\\"q\\\"\"]\n"));
        let none = render_feed(&Feed {
            notes: &[],
            ..sample()
        });
        // Too long for one line: one note per line, as prettier writes it.
        let long = ["a".repeat(60), "b".repeat(10)];
        let wide = render_feed(&Feed {
            notes: &long,
            ..sample()
        });
        assert!(wide.contains(&format!(
            "  \"notes\": [\n    \"{}\",\n    \"{}\"\n  ]\n",
            long[0], long[1]
        )));
        assert!(none.contains("  \"notes\": []\n"));
    }

    fn sample() -> Feed<'static> {
        Feed {
            version: "1.0.0",
            version_code: 10000,
            min_sdk: "26",
            published: "",
            url: "u",
            size: 1,
            sha256: "s",
            notes: &[],
        }
    }

    #[test]
    fn select_single_artifact_path_picks_transitioned_apk_and_rejects_bad_counts() {
        let out = "\
bazel-out/k8-fastbuild-ST-abc/bin/apps/mobile/vitruvian-remote/app_unsigned.apk
bazel-out/k8-fastbuild-ST-abc/bin/apps/mobile/vitruvian-remote/app.apk
";
        assert_eq!(
            select_single_artifact_path(out, REMOTE_APK_SUFFIX).unwrap(),
            PathBuf::from("bazel-out/k8-fastbuild-ST-abc/bin/apps/mobile/vitruvian-remote/app.apk")
        );

        let unsigned_only =
            "bazel-out/k8-fastbuild-ST-abc/bin/apps/mobile/vitruvian-remote/app_unsigned.apk\n";
        let err = select_single_artifact_path(unsigned_only, REMOTE_APK_SUFFIX).unwrap_err();
        assert!(err.contains("got 0"), "{err}");

        let dupes = "\
bazel-out/k8-fastbuild-ST-aaa/bin/apps/mobile/vitruvian-remote/app.apk
bazel-out/k8-fastbuild-ST-bbb/bin/apps/mobile/vitruvian-remote/app.apk
";
        let err = select_single_artifact_path(dupes, REMOTE_APK_SUFFIX).unwrap_err();
        assert!(
            err.contains("got 2") && err.contains("-ST-aaa") && err.contains("-ST-bbb"),
            "{err}"
        );
    }

    #[test]
    fn absolute_artifact_path_joins_relative_onto_workspace_and_preserves_absolute() {
        let workspace = Path::new("/repo/vitruvian-core");
        let rel = Path::new(
            "bazel-out/darwin_arm64-fastbuild-ST-abc/bin/apps/mobile/vitruvian-remote/app.apk",
        );
        assert_eq!(
            absolute_artifact_path(workspace, rel),
            PathBuf::from(
                "/repo/vitruvian-core/bazel-out/darwin_arm64-fastbuild-ST-abc/bin/apps/mobile/vitruvian-remote/app.apk"
            )
        );

        let abs = Path::new("/tmp/already-absolute/app.apk");
        assert_eq!(absolute_artifact_path(workspace, abs), abs);
    }

    struct TempDir(PathBuf);
    impl TempDir {
        fn path(&self) -> &Path {
            &self.0
        }
    }
    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
}
