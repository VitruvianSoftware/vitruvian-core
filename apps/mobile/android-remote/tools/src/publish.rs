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

pub fn strip_version_prefix(tag: &str) -> &str {
    let s = tag.strip_prefix("android-remote-v").unwrap_or(tag);
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

pub fn resolve_version(tag: &str, app_dir: &Path) -> String {
    if !tag.is_empty() {
        let v = strip_version_prefix(tag);
        if !v.is_empty() {
            return v.to_string();
        }
    }

    if let Some(v) = version_from_manifest(
        &app_dir.join(".release-please-manifest.json"),
        "apps/mobile/android-remote",
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
    let app_dir = if cwd.join("apps/mobile/android-remote/BUILD").is_file() {
        let sub = cwd.join("apps/mobile/android-remote");
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
            "--android_platforms=@rules_android//:arm64-v8a,@rules_android//:x86_64",
            "//apps/mobile/android-remote:app",
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

    let bazel_bin = match Command::new("bazel").args(["info", "bazel-bin"]).output() {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        _ => {
            eprintln!("Error: failed to get bazel-bin path");
            return 1;
        }
    };

    let bin_apk = PathBuf::from(&bazel_bin).join("apps/mobile/android-remote/app.apk");
    if !bin_apk.is_file() {
        eprintln!(
            "Error: Expected APK output at {} not found",
            bin_apk.display()
        );
        return 1;
    }

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
    fn strip_android_remote_v_prefix() {
        assert_eq!(strip_version_prefix("android-remote-v1.2.3"), "1.2.3");
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
    fn strip_android_remote_v_then_v() {
        assert_eq!(strip_version_prefix("android-remote-vv1.0.0"), "1.0.0");
    }

    #[test]
    fn manifest_parsing() {
        let p = env::temp_dir().join("publish_test_manifest");
        let _ = fs::create_dir_all(&p);
        let dir = TempDir(p);
        let manifest = dir.path().join("manifest.json");
        fs::write(
            &manifest,
            r#"{"apps/mobile/android-remote": "2.5.1", "other": "1.0.0"}"#,
        )
        .unwrap();
        assert_eq!(
            version_from_manifest(&manifest, "apps/mobile/android-remote"),
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
            version_from_manifest(&manifest, "apps/mobile/android-remote"),
            None
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn manifest_file_missing() {
        let missing = PathBuf::from("/nonexistent/manifest.json");
        assert_eq!(
            version_from_manifest(&missing, "apps/mobile/android-remote"),
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
        assert_eq!(resolve_version("android-remote-v4.0.0", &dir), "4.0.0");
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
        fs::write(&manifest, r#"{"apps/mobile/android-remote": "7.8.9"}"#).unwrap();
        assert_eq!(resolve_version("", &dir), "7.8.9");
        let _ = fs::remove_dir_all(&dir);
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
