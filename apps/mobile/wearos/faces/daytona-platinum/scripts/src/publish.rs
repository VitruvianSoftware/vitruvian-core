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

const MANIFEST_KEY: &str = "apps/mobile/wearos/faces/daytona-platinum";
const TAG_PREFIX: &str = "daytona-platinum-v";
const DEFAULT_VERSION: &str = "0.1.0";
const APK_PREFIX: &str = "DaytonaPlatinum";

pub fn strip_version_from_tag(tag: &str) -> String {
    let v = tag.strip_prefix(TAG_PREFIX).unwrap_or(tag);
    v.strip_prefix('v').unwrap_or(v).to_string()
}

pub fn parse_version_from_manifest(content: &str) -> Option<String> {
    let pattern = format!("\"{}\"", MANIFEST_KEY);
    for line in content.lines() {
        if let Some(pos) = line.find(&pattern) {
            let after_key = &line[pos + pattern.len()..];
            // Skip `: "` or `:"` or `: "`
            if let Some(colon_pos) = after_key.find(':') {
                let after_colon = after_key[colon_pos + 1..].trim();
                let after_colon = after_colon.strip_prefix('"').unwrap_or(after_colon);
                if let Some(end) = after_colon.find('"') {
                    return Some(after_colon[..end].to_string());
                }
            }
        }
    }
    None
}

fn resolve_app_dir() -> PathBuf {
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        return Path::new(&bwd)
            .join("apps/mobile/wearos/faces/daytona-platinum")
            .to_path_buf();
    }
    // Walk from script location: scripts/src -> scripts -> daytona-platinum
    let exe = env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let exe_dir = exe.parent().unwrap_or(Path::new("."));
    let mut dir = exe_dir.to_path_buf();
    for _ in 0..10 {
        if dir.join("src/main/AndroidManifest.xml").is_file() {
            return dir;
        }
        if !dir.pop() {
            break;
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn resolve_version(tag: &str, app_dir: &Path) -> String {
    let version_env = env::var("VERSION").unwrap_or_default();
    if !version_env.is_empty() {
        return version_env;
    }

    if !tag.is_empty() {
        return strip_version_from_tag(tag);
    }

    let manifest_path = app_dir.join(".release-please-manifest.json");
    if manifest_path.is_file() {
        if let Ok(content) = fs::read_to_string(&manifest_path) {
            if let Some(v) = parse_version_from_manifest(&content) {
                if !v.is_empty() {
                    return v;
                }
            }
        }
    }

    DEFAULT_VERSION.to_string()
}

fn detect_android_home() {
    if env::var("ANDROID_HOME").is_ok() {
        return;
    }
    let candidates = [
        "/usr/local/lib/android/sdk",
        "/opt/homebrew/share/android-commandlinetools",
    ];
    for cand in &candidates {
        if Path::new(cand).is_dir() {
            env::set_var("ANDROID_HOME", cand);
            return;
        }
    }
}

fn generate_sha256(dist_dir: &Path, apk_name: &str) -> io::Result<String> {
    // Try sha256sum first, fall back to shasum -a 256
    let output = Command::new("sha256sum")
        .arg(apk_name)
        .current_dir(dist_dir)
        .output()
        .or_else(|_| {
            Command::new("shasum")
                .args(["-a", "256", apk_name])
                .current_dir(dist_dir)
                .output()
        })?;

    if !output.status.success() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "sha256 computation failed",
        ));
    }

    let checksum = String::from_utf8_lossy(&output.stdout).to_string();
    let sha_file = dist_dir.join(format!("{}.sha256", apk_name));
    fs::write(&sha_file, &checksum)?;
    Ok(checksum)
}

pub fn run(args: &[String]) -> i32 {
    let dry_run = args.iter().any(|a| a == "--dry-run");
    let tag = env::var("TAG").unwrap_or_default();
    let app_dir = resolve_app_dir();
    let version = resolve_version(&tag, &app_dir);

    if tag.is_empty() {
        println!(
            "==> Packaging Daytona Platinum Watch Face release v{}",
            version
        );
    } else {
        println!(
            "==> Packaging Daytona Platinum Watch Face release v{} (tag: {})",
            version, tag
        );
    }

    detect_android_home();

    // Clean and create dist/
    let dist_dir = app_dir.join("dist");
    let _ = fs::remove_dir_all(&dist_dir);
    if let Err(e) = fs::create_dir_all(&dist_dir) {
        eprintln!("error: cannot create dist/: {}", e);
        return 1;
    }

    let apk_name = format!("{}-{}.apk", APK_PREFIX, version);
    let apk_path = dist_dir.join(&apk_name);

    // Build via build_wff_apk.sh
    let build_script = app_dir.join("scripts/build_wff_apk.sh");
    let status = match Command::new("bash")
        .arg(build_script.to_str().unwrap_or("build_wff_apk.sh"))
        .arg(apk_path.to_str().unwrap_or("out.apk"))
        .status()
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error: failed to run build_wff_apk.sh: {}", e);
            return 1;
        }
    };
    if !status.success() {
        eprintln!("error: build_wff_apk.sh failed");
        return 1;
    }

    println!("==> Generating SHA256 checksum");
    match generate_sha256(&dist_dir, &apk_name) {
        Ok(checksum) => print!("{}", checksum),
        Err(e) => {
            eprintln!("error: SHA256 generation failed: {}", e);
            return 1;
        }
    }

    if dry_run {
        println!("==> Dry run: verified release artifact created in dist/:");
        match fs::read_dir(&dist_dir) {
            Ok(entries) => {
                for entry in entries.flatten() {
                    if let Ok(meta) = entry.metadata() {
                        println!("  {} ({} bytes)", entry.path().display(), meta.len());
                    }
                }
            }
            Err(e) => eprintln!("warning: cannot list dist/: {}", e),
        }
        return 0;
    }

    if tag.is_empty() {
        println!("==> No TAG specified; packages created in dist/. Skipping upload.");
        return 0;
    }

    let repo =
        env::var("GITHUB_REPOSITORY").unwrap_or_else(|_| "VitruvianSoftware/vitruvian-core".into());
    println!(
        "==> Attaching release artifacts to GitHub Release {} in {}",
        tag, repo
    );

    let sha_file = dist_dir.join(format!("{}.sha256", apk_name));
    let upload_status = Command::new("gh")
        .args([
            "release",
            "upload",
            &tag,
            apk_path.to_str().unwrap_or(""),
            sha_file.to_str().unwrap_or(""),
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
            eprintln!("error: gh release upload failed with {}", s);
            1
        }
        Err(e) => {
            eprintln!("error: gh release upload failed: {}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_tag_full_prefix() {
        assert_eq!(strip_version_from_tag("daytona-platinum-v1.2.3"), "1.2.3");
    }

    #[test]
    fn strip_tag_v_only() {
        assert_eq!(strip_version_from_tag("v1.0.0"), "1.0.0");
    }

    #[test]
    fn strip_tag_bare() {
        assert_eq!(strip_version_from_tag("2.0.0"), "2.0.0");
    }

    #[test]
    fn strip_tag_with_prerelease() {
        assert_eq!(
            strip_version_from_tag("daytona-platinum-v1.0.0-rc1"),
            "1.0.0-rc1"
        );
    }

    #[test]
    fn parse_manifest_valid() {
        let content = r#"{
  "apps/mobile/wearos/faces/daytona-platinum": "3.2.1",
  "apps/other": "1.0.0"
}"#;
        assert_eq!(
            parse_version_from_manifest(content),
            Some("3.2.1".to_string())
        );
    }

    #[test]
    fn parse_manifest_no_key() {
        let content = r#"{
  "apps/other": "1.0.0"
}"#;
        assert_eq!(parse_version_from_manifest(content), None);
    }

    #[test]
    fn parse_manifest_spaces() {
        let content = r#"  "apps/mobile/wearos/faces/daytona-platinum" : "4.5.6"  "#;
        assert_eq!(
            parse_version_from_manifest(content),
            Some("4.5.6".to_string())
        );
    }

    #[test]
    fn default_version_fallback() {
        assert_eq!(DEFAULT_VERSION, "0.1.0");
    }

    #[test]
    fn apk_name_format() {
        let version = "1.2.3";
        let name = format!("{}-{}.apk", APK_PREFIX, version);
        assert_eq!(name, "DaytonaPlatinum-1.2.3.apk");
    }

    #[test]
    fn manifest_key_constant() {
        assert_eq!(MANIFEST_KEY, "apps/mobile/wearos/faces/daytona-platinum");
    }

    #[test]
    fn tag_prefix_constant() {
        assert_eq!(TAG_PREFIX, "daytona-platinum-v");
    }
}
