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
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

const APK_SPECS: &[(&str, &str)] = &[
    ("vitruvian-pulse", "VitruvianPulse"),
    ("remote", "VitruvianWearRemote"),
    ("home-control", "VitruvianHomeControl"),
    ("nexus-wrist", "VitruvianNexusWrist"),
];

const ANDROID_HOME_CANDIDATES: &[&str] = &[
    "/usr/local/lib/android/sdk",
    "/opt/homebrew/share/android-commandlinetools",
];

pub fn strip_version_prefix(tag: &str) -> String {
    let v = tag.strip_prefix("wearos-apps-v").unwrap_or(tag);
    let v = v.strip_prefix('v').unwrap_or(v);
    v.to_string()
}

pub fn resolve_version_from_manifest(manifest_path: &Path) -> Option<String> {
    let content = fs::read_to_string(manifest_path).ok()?;
    parse_manifest_version(&content)
}

pub fn parse_manifest_version(content: &str) -> Option<String> {
    let needle = "\"apps/mobile/wearos/apps\"";
    let idx = content.find(needle)?;
    let rest = &content[idx + needle.len()..];
    // skip optional whitespace and colon
    let rest = rest.trim_start();
    let rest = rest.strip_prefix(':')?;
    let rest = rest.trim_start();
    // extract quoted value
    let rest = rest.strip_prefix('"')?;
    let end = rest.find('"')?;
    let ver = &rest[..end];
    if ver.is_empty() {
        None
    } else {
        Some(ver.to_string())
    }
}

fn detect_android_home() -> Option<String> {
    if let Ok(val) = env::var("ANDROID_HOME") {
        if !val.is_empty() {
            return Some(val);
        }
    }
    for cand in ANDROID_HOME_CANDIDATES {
        if Path::new(cand).join("platforms").is_dir() {
            return Some(cand.to_string());
        }
    }
    if let Ok(home) = env::var("HOME") {
        let user_sdk = format!("{}/Library/Android/sdk", home);
        if Path::new(&user_sdk).join("platforms").is_dir() {
            return Some(user_sdk);
        }
    }
    None
}

fn resolve_suite_dir() -> PathBuf {
    let exe = env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let script_dir = exe.parent().unwrap_or(Path::new("."));
    script_dir.parent().unwrap_or(Path::new(".")).to_path_buf()
}

fn resolve_repo_root(suite_dir: &Path) -> PathBuf {
    suite_dir
        .ancestors()
        .nth(3)
        .unwrap_or(Path::new("."))
        .to_path_buf()
}

pub fn apk_filename(display_name: &str, version: &str) -> String {
    format!("{}-{}.apk", display_name, version)
}

pub fn sha256_command() -> (&'static str, Vec<&'static str>) {
    if Command::new("sha256sum").arg("--version").output().is_ok() {
        ("sha256sum", vec![])
    } else {
        ("shasum", vec!["-a", "256"])
    }
}

fn generate_sha256(dist_dir: &Path, apk_name: &str) -> Result<(), String> {
    let (cmd, extra_args) = sha256_command();
    let output = Command::new(cmd)
        .args(&extra_args)
        .arg(apk_name)
        .current_dir(dist_dir)
        .output()
        .map_err(|e| format!("sha256 command failed: {}", e))?;
    if !output.status.success() {
        return Err("sha256 command returned non-zero".to_string());
    }
    let sha_path = dist_dir.join(format!("{}.sha256", apk_name));
    let mut f = fs::File::create(&sha_path)
        .map_err(|e| format!("cannot create {}: {}", sha_path.display(), e))?;
    f.write_all(&output.stdout)
        .map_err(|e| format!("write failed: {}", e))?;
    let digest = String::from_utf8_lossy(&output.stdout);
    print!("{}", digest);
    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let dry_run = args.iter().any(|a| a == "--dry-run");

    let tag = env::var("TAG").unwrap_or_default();
    let mut version = env::var("VERSION").unwrap_or_default();

    if version.is_empty() && !tag.is_empty() {
        version = strip_version_prefix(&tag);
    }

    let suite_dir = resolve_suite_dir();

    if version.is_empty() {
        let manifest = suite_dir.join(".release-please-manifest.json");
        if manifest.is_file() {
            if let Some(v) = resolve_version_from_manifest(&manifest) {
                version = v;
            }
        }
    }
    if version.is_empty() {
        version = "0.1.0".to_string();
    }

    if tag.is_empty() {
        println!(
            "==> Packaging Vitruvian Wear OS Apps Suite release v{}",
            version
        );
    } else {
        println!(
            "==> Packaging Vitruvian Wear OS Apps Suite release v{} (tag: {})",
            version, tag
        );
    }

    if let Some(ah) = detect_android_home() {
        env::set_var("ANDROID_HOME", &ah);
    }

    let has_android_home = env::var("ANDROID_HOME")
        .map(|v| !v.is_empty())
        .unwrap_or(false);

    if !has_android_home {
        if dry_run {
            println!("==> Dry run: ANDROID_HOME is unset; skipping local build check.");
            return 0;
        } else {
            eprintln!("Error: ANDROID_HOME is unset. A local Android SDK is required to build the Wear OS release APKs.");
            return 1;
        }
    }

    let repo_root = resolve_repo_root(&suite_dir);
    if env::set_current_dir(&repo_root).is_err() {
        eprintln!("Error: cannot cd to {}", repo_root.display());
        return 1;
    }

    println!("==> Building all 4 Wear OS release APKs with Bazel");
    let build_status = Command::new("bazel")
        .args([
            "build",
            "--android_platforms=@rules_android//:armeabi-v7a,@rules_android//:arm64-v8a,@rules_android//:x86_64",
            "//apps/mobile/wearos/apps/vitruvian-pulse:app",
            "//apps/mobile/wearos/apps/remote:app",
            "//apps/mobile/wearos/apps/home-control:app",
            "//apps/mobile/wearos/apps/nexus-wrist:app",
        ])
        .status();
    match build_status {
        Ok(s) if s.success() => {}
        _ => {
            eprintln!("Error: bazel build failed");
            return 1;
        }
    }

    let bin_root = match Command::new("bazel").args(["info", "bazel-bin"]).output() {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        _ => {
            eprintln!("Error: cannot determine bazel-bin");
            return 1;
        }
    };

    let dist_dir = suite_dir.join("dist");
    let _ = fs::remove_dir_all(&dist_dir);
    if fs::create_dir_all(&dist_dir).is_err() {
        eprintln!("Error: cannot create dist directory");
        return 1;
    }

    let mut upload_files: Vec<PathBuf> = Vec::new();

    for &(pkg, display_name) in APK_SPECS {
        let apk_name = apk_filename(display_name, &version);
        let src_apk = format!("{}/apps/mobile/wearos/apps/{}/app.apk", bin_root, pkg);
        if !Path::new(&src_apk).is_file() {
            eprintln!("Error: Expected APK output at {} not found", src_apk);
            return 1;
        }
        let dest = dist_dir.join(&apk_name);
        if fs::copy(&src_apk, &dest).is_err() {
            eprintln!("Error: failed to copy APK to dist/");
            return 1;
        }
        if let Err(e) = generate_sha256(&dist_dir, &apk_name) {
            eprintln!("Error: {}", e);
            return 1;
        }
        upload_files.push(dest.clone());
        upload_files.push(dist_dir.join(format!("{}.sha256", apk_name)));
    }

    if dry_run {
        println!("==> Dry run: verified all 4 Wear OS APKs and SHA256 checksums in dist/:");
        if let Ok(entries) = fs::read_dir(&dist_dir) {
            for entry in entries.flatten() {
                println!("  {}", entry.path().display());
            }
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
        "==> Attaching Wear OS release artifacts to GitHub Release {} in {}",
        tag, repo
    );

    let mut cmd = Command::new("gh");
    cmd.args(["release", "upload", &tag]);
    for f in &upload_files {
        cmd.arg(f);
    }
    cmd.args(["--repo", &repo, "--clobber"]);

    match cmd.status() {
        Ok(s) if s.success() => {}
        _ => {
            eprintln!("Error: gh release upload failed");
            return 1;
        }
    }

    println!("==> Upload completed successfully.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_version_wearos_apps_prefix() {
        assert_eq!(strip_version_prefix("wearos-apps-v1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_version_v_prefix() {
        assert_eq!(strip_version_prefix("v1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_version_bare() {
        assert_eq!(strip_version_prefix("1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_version_wearos_apps_then_v() {
        assert_eq!(strip_version_prefix("wearos-apps-v0.5.0"), "0.5.0");
    }

    #[test]
    fn parse_manifest_version_present() {
        let content = r#"{"apps/mobile/wearos/apps": "2.1.0", "other": "1.0.0"}"#;
        assert_eq!(parse_manifest_version(content), Some("2.1.0".to_string()));
    }

    #[test]
    fn parse_manifest_version_missing() {
        let content = r#"{"apps/mobile/other": "1.0.0"}"#;
        assert_eq!(parse_manifest_version(content), None);
    }

    #[test]
    fn parse_manifest_version_with_spaces() {
        let content = r#"{"apps/mobile/wearos/apps" : "3.0.1"}"#;
        assert_eq!(parse_manifest_version(content), Some("3.0.1".to_string()));
    }

    #[test]
    fn apk_specs_count() {
        assert_eq!(APK_SPECS.len(), 4);
    }

    #[test]
    fn apk_filename_format() {
        assert_eq!(
            apk_filename("VitruvianPulse", "1.0.0"),
            "VitruvianPulse-1.0.0.apk"
        );
    }

    #[test]
    fn apk_filename_all_specs() {
        let expected = vec![
            ("vitruvian-pulse", "VitruvianPulse-2.0.0.apk"),
            ("remote", "VitruvianWearRemote-2.0.0.apk"),
            ("home-control", "VitruvianHomeControl-2.0.0.apk"),
            ("nexus-wrist", "VitruvianNexusWrist-2.0.0.apk"),
        ];
        for (i, &(pkg, display_name)) in APK_SPECS.iter().enumerate() {
            let name = apk_filename(display_name, "2.0.0");
            assert_eq!(pkg, expected[i].0);
            assert_eq!(name, expected[i].1);
        }
    }

    #[test]
    fn sha256_command_returns_valid() {
        let (cmd, _) = sha256_command();
        assert!(cmd == "sha256sum" || cmd == "shasum");
    }
}
