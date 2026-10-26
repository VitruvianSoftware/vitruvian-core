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

//! Rust port of `apps/mobile/android-remote/macmenu/scripts/publish-tool.sh`.

use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const PKG: &str = "apps/mobile/android-remote/macmenu";
pub const DEFAULT_REPO: &str = "VitruvianSoftware/vitruvian-core";
pub const PROGRAMS: [&str; 2] = ["tool", "vitruvian-remote-agent"];
pub const ARCHS: [&str; 2] = ["arm64", "x86_64"];

pub fn parse_args(args: &[String]) -> Result<bool, String> {
    let mut dry_run = false;
    for arg in args.iter().skip(1) {
        if arg == "--dry-run" {
            dry_run = true;
        } else {
            return Err(format!("error: unknown argument {arg} (only --dry-run)"));
        }
    }
    Ok(dry_run)
}

pub fn resolve_version(
    version_env: Option<&str>,
    tag_env: Option<&str>,
    manifest_content: &str,
) -> Option<String> {
    if let Some(v) = version_env {
        if !v.is_empty() {
            return Some(v.to_string());
        }
    }
    if let Some(tag) = tag_env {
        if !tag.is_empty() {
            return Some(
                tag.strip_prefix("android-remote-v")
                    .unwrap_or(tag)
                    .to_string(),
            );
        }
    }
    extract_manifest_version(manifest_content)
}

pub fn extract_manifest_version(content: &str) -> Option<String> {
    for line in content.lines() {
        if let Some(pos) = line.find("\"version\":") {
            let rest = &line[pos + "\"version\":".len()..];
            let trimmed = rest.trim_start();
            if let Some(inner) = trimmed.strip_prefix('"') {
                if let Some(end) = inner.find('"') {
                    return Some(inner[..end].to_string());
                }
            }
        }
    }
    None
}

pub fn is_valid_min_macos(ver: &str) -> bool {
    let parts: Vec<&str> = ver.split('.').collect();
    if parts.len() != 2 {
        return false;
    }
    parts
        .iter()
        .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
}

pub fn extract_plist_string_key(plist_xml: &str, key: &str) -> Option<String> {
    let key_tag = format!("<key>{key}</key>");
    let pos = plist_xml.find(&key_tag)?;
    let rest = &plist_xml[pos + key_tag.len()..];
    let start_tag = "<string>";
    let end_tag = "</string>";
    let s_pos = rest.find(start_tag)?;
    let after_s = &rest[s_pos + start_tag.len()..];
    let e_pos = after_s.find(end_tag)?;
    Some(after_s[..e_pos].trim().to_string())
}

pub fn build_bazel_flags(min_macos: &str, buildbuddy_key: Option<&str>) -> Vec<String> {
    let mut flags = vec![
        "--config=macos-app".to_string(),
        "-c".to_string(),
        "opt".to_string(),
        format!("--macos_minimum_os={min_macos}"),
    ];
    if let Some(key) = buildbuddy_key {
        if !key.is_empty() {
            flags.push("--config=remotecache-ci".to_string());
            flags.push(format!("--remote_header=x-buildbuddy-api-key={key}"));
        }
    }
    flags
}

pub fn select_cquery_output(outputs: &str, program: &str) -> Option<String> {
    let suffix = format!("/built/remote/bin/{program}");
    for line in outputs.lines() {
        let trimmed = line.trim();
        if trimmed.ends_with(&suffix) {
            return Some(trimmed.to_string());
        }
    }
    None
}

pub fn asset_name(version: &str) -> String {
    format!("VitruvianRemote-{version}-tool.zip")
}

fn find_repo_root() -> Result<PathBuf, String> {
    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !ws.is_empty() {
            return Ok(PathBuf::from(ws));
        }
    }
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .map_err(|e| format!("failed to locate repo root: {e}"))?;
    if output.status.success() {
        return Ok(PathBuf::from(
            String::from_utf8_lossy(&output.stdout).trim(),
        ));
    }
    env::current_dir().map_err(|e| format!("cannot determine current dir: {e}"))
}

pub fn run(args: &[String]) -> i32 {
    let dry_run = match parse_args(args) {
        Ok(d) => d,
        Err(msg) => {
            eprintln!("{msg}");
            return 2;
        }
    };

    let root = match find_repo_root() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };
    let macmenu_dir = root.join(PKG);
    let script_dir = macmenu_dir.join("scripts");

    let tag = env::var("TAG").unwrap_or_default();
    let version_env = env::var("VERSION").ok();
    let manifest_path = macmenu_dir.join("tool/vitruvian-tool.json");
    let manifest_content = fs::read_to_string(&manifest_path).unwrap_or_default();

    let version = match resolve_version(
        version_env.as_deref(),
        if tag.is_empty() {
            None
        } else {
            Some(tag.as_str())
        },
        &manifest_content,
    ) {
        Some(v) if !v.is_empty() => v,
        _ => {
            eprintln!("error: could not determine version");
            return 1;
        }
    };

    if tag.is_empty() {
        println!("==> Packaging the Vitruvian Remote extension v{version}");
    } else {
        println!("==> Packaging the Vitruvian Remote extension v{version} (tag: {tag})");
    }

    let info_plist_path = macmenu_dir.join("Resources/Info.plist");
    let min_macos = Command::new("plutil")
        .args(["-extract", "LSMinimumSystemVersion", "raw", "-o", "-"])
        .arg(&info_plist_path)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .or_else(|| {
            fs::read_to_string(&info_plist_path)
                .ok()
                .and_then(|xml| extract_plist_string_key(&xml, "LSMinimumSystemVersion"))
        })
        .unwrap_or_default();

    if !is_valid_min_macos(&min_macos) {
        eprintln!("error: Resources/Info.plist's LSMinimumSystemVersion is '{min_macos}'");
        return 1;
    }

    let bb_key = env::var("BUILDBUDDY_API_KEY").ok();
    let flags = build_bazel_flags(&min_macos, bb_key.as_deref());

    let work_base = env::var("RUNNER_TEMP")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            env::temp_dir().join(format!("publish-tool-{nanos}"))
        });
    let work = work_base.join("remote-tool-dist");
    let _ = fs::remove_dir_all(&work);
    for sub in ["arm64", "x86_64", "universal", "dist"] {
        if let Err(e) = fs::create_dir_all(work.join(sub)) {
            eprintln!("error: failed to create {}: {e}", work.join(sub).display());
            return 1;
        }
    }

    let target = format!("//{PKG}:tool-folder");
    for arch in ARCHS {
        println!("==> Building the extension for {arch}");
        let mut arch_flags = flags.clone();
        arch_flags.push(format!(
            "--platforms=@apple_support//platforms:macos_{arch}"
        ));

        let build_status = Command::new("bazel")
            .arg("build")
            .args(&arch_flags)
            .arg(&target)
            .current_dir(&root)
            .status();
        if !build_status.map(|s| s.success()).unwrap_or(false) {
            eprintln!("error: bazel build failed for {arch}");
            return 1;
        }

        let cquery_out = match Command::new("bazel")
            .arg("cquery")
            .args(&arch_flags)
            .args(["--output=files", &target])
            .current_dir(&root)
            .output()
        {
            Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).into_owned(),
            _ => {
                eprintln!("error: bazel cquery failed for {arch}");
                return 1;
            }
        };

        for program in PROGRAMS {
            let rel = match select_cquery_output(&cquery_out, program) {
                Some(r) => r,
                None => {
                    eprintln!("error: bazel left no bin/{program} for {arch}");
                    return 1;
                }
            };
            let built_path = root.join(&rel);
            if !built_path.is_file() {
                eprintln!("error: bazel left no bin/{program} for {arch}");
                return 1;
            }
            let dest = work.join(arch).join(program);
            if let Err(e) = fs::copy(&built_path, &dest) {
                eprintln!("error: failed to copy {}: {e}", built_path.display());
                return 1;
            }
            let got = Command::new("lipo")
                .arg("-archs")
                .arg(&dest)
                .output()
                .ok()
                .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
                .unwrap_or_default();
            if got != arch {
                eprintln!("error: the {arch} build of bin/{program} is '{got}'");
                return 1;
            }
        }
    }

    for program in PROGRAMS {
        let arm_bin = work.join("arm64").join(program);
        let x86_bin = work.join("x86_64").join(program);
        let uni_bin = work.join("universal").join(program);

        if !Command::new("lipo")
            .arg("-create")
            .arg(&arm_bin)
            .arg(&x86_bin)
            .arg("-output")
            .arg(&uni_bin)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            eprintln!("error: lipo -create failed for {program}");
            return 1;
        }
        let _ = Command::new("lipo").arg("-info").arg(&uni_bin).status();
        if !Command::new("codesign")
            .args(["--force", "--sign", "-"])
            .arg(&uni_bin)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            eprintln!("error: codesign failed for {program}");
            return 1;
        }
        if !Command::new("codesign")
            .args(["--verify", "--strict"])
            .arg(&uni_bin)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            eprintln!("error: codesign --verify failed for {program}");
            return 1;
        }
    }

    let zip_status = Command::new("bash")
        .arg(script_dir.join("zip-tool.sh"))
        .arg(work.join("universal/tool"))
        .arg(work.join("universal/vitruvian-remote-agent"))
        .arg(&version)
        .arg(work.join("dist"))
        .env("REMOTE_TOOL_REQUIRE_UNIVERSAL", "1")
        .env("REMOTE_TOOL_MAX_MINOS", &min_macos)
        .status();
    if !zip_status.map(|s| s.success()).unwrap_or(false) {
        eprintln!("error: zip-tool.sh failed");
        return 1;
    }

    let asset = asset_name(&version);
    let dist_dir = work.join("dist");
    let shasum_out = match Command::new("shasum")
        .args(["-a", "256", &asset])
        .current_dir(&dist_dir)
        .output()
    {
        Ok(o) if o.status.success() => o.stdout,
        _ => {
            eprintln!("error: shasum failed for {asset}");
            return 1;
        }
    };
    let sha_file = dist_dir.join(format!("{asset}.sha256"));
    if let Err(e) = fs::File::create(&sha_file).and_then(|mut f| f.write_all(&shasum_out)) {
        eprintln!("error: failed to write {}: {e}", sha_file.display());
        return 1;
    }
    print!("{}", String::from_utf8_lossy(&shasum_out));

    for file in [&asset, &format!("{asset}.sha256")] {
        let p = dist_dir.join(file);
        let non_empty = fs::metadata(&p).map(|m| m.len() > 0).unwrap_or(false);
        if !non_empty {
            eprintln!("error: packaging left no {file}");
            return 1;
        }
    }

    if dry_run {
        println!(
            "==> Dry run: the extension's zip is in {}; nothing uploaded.",
            dist_dir.display()
        );
        return 0;
    }
    if tag.is_empty() {
        println!(
            "==> No TAG: the extension's zip is in {}; nothing uploaded.",
            dist_dir.display()
        );
        return 0;
    }

    let repo = env::var("GITHUB_REPOSITORY")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| DEFAULT_REPO.to_string());
    println!("==> Attaching {asset} to GitHub Release {tag} in {repo}");
    let upload_ok = Command::new("gh")
        .args(["release", "upload", &tag])
        .arg(dist_dir.join(&asset))
        .arg(&sha_file)
        .args(["--repo", &repo, "--clobber"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !upload_ok {
        eprintln!("error: gh release upload failed");
        return 1;
    }
    println!("==> Upload completed.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_args_accepts_only_dry_run() {
        assert!(!parse_args(&["publish-tool".into()]).unwrap());
        assert!(parse_args(&["publish-tool".into(), "--dry-run".into()]).unwrap());
        let err = parse_args(&["publish-tool".into(), "--dryrun".into()]).unwrap_err();
        assert_eq!(err, "error: unknown argument --dryrun (only --dry-run)");
    }

    #[test]
    fn resolve_version_precedence() {
        let manifest = "{\n  \"version\": \"0.1.21\"\n}\n";
        assert_eq!(
            resolve_version(Some("1.2.3"), Some("android-remote-v9.9.9"), manifest).as_deref(),
            Some("1.2.3")
        );
        assert_eq!(
            resolve_version(None, Some("android-remote-v0.2.0"), manifest).as_deref(),
            Some("0.2.0")
        );
        assert_eq!(
            resolve_version(None, None, manifest).as_deref(),
            Some("0.1.21")
        );
    }

    #[test]
    fn min_macos_validation() {
        assert!(is_valid_min_macos("14.0"));
        assert!(is_valid_min_macos("15.2"));
        assert!(!is_valid_min_macos(""));
        assert!(!is_valid_min_macos("14"));
        assert!(!is_valid_min_macos("14.0.1"));
        assert!(!is_valid_min_macos("abc.def"));
    }

    #[test]
    fn extract_plist_string_key_reads_ls_minimum_system_version() {
        let plist = "\
<plist version=\"1.0\">
<dict>
\t<key>CFBundleShortVersionString</key>
\t<string>0.1.21</string>
\t<key>LSMinimumSystemVersion</key>
\t<string>14.0</string>
</dict>
</plist>";
        assert_eq!(
            extract_plist_string_key(plist, "LSMinimumSystemVersion").as_deref(),
            Some("14.0")
        );
        assert_eq!(
            extract_plist_string_key(plist, "CFBundleShortVersionString").as_deref(),
            Some("0.1.21")
        );
    }

    #[test]
    fn build_bazel_flags_with_and_without_buildbuddy() {
        let local = build_bazel_flags("14.0", None);
        assert_eq!(
            local,
            vec!["--config=macos-app", "-c", "opt", "--macos_minimum_os=14.0"]
        );

        let remote = build_bazel_flags("14.0", Some("bb_secret"));
        assert_eq!(
            remote,
            vec![
                "--config=macos-app",
                "-c",
                "opt",
                "--macos_minimum_os=14.0",
                "--config=remotecache-ci",
                "--remote_header=x-buildbuddy-api-key=bb_secret",
            ]
        );
    }

    #[test]
    fn select_cquery_output_matches_exact_program_suffix() {
        let outputs = "\
bazel-out/darwin_arm64-opt/bin/apps/mobile/android-remote/macmenu/built/remote/vitruvian-tool.json
bazel-out/darwin_arm64-opt/bin/apps/mobile/android-remote/macmenu/built/remote/bin/tool
bazel-out/darwin_arm64-opt/bin/apps/mobile/android-remote/macmenu/built/remote/bin/vitruvian-remote-agent
";
        assert_eq!(
            select_cquery_output(outputs, "tool").as_deref(),
            Some("bazel-out/darwin_arm64-opt/bin/apps/mobile/android-remote/macmenu/built/remote/bin/tool")
        );
        assert_eq!(
            select_cquery_output(outputs, "vitruvian-remote-agent").as_deref(),
            Some("bazel-out/darwin_arm64-opt/bin/apps/mobile/android-remote/macmenu/built/remote/bin/vitruvian-remote-agent")
        );
        assert!(select_cquery_output(outputs, "missing").is_none());
    }
}
