// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `Tools/package-release.sh`.
//! Unpacks the Bazel-built `Vitruvian.zip`, signs and notarizes the universal,
//! `arm64`, and `x86_64` bundles, and builds the distributable DMGs and ZIP.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const APP_BUNDLE_ID: &str = "com.vitruviansoftware.vitruvian";
pub const FAN_HELPER_ID: &str = "com.vitruviansoftware.vitruvian.fan-control";
pub const NOW_PLAYING_ADAPTER_ID: &str = "com.vitruviansoftware.vitruvian.now-playing";
pub const MOUSE_TOOL_ID: &str = "com.vitruviansoftware.vitruvian.gravastar-mouse";
pub const ENTITLEMENTS_REL: &str = "Resources/Vitruvian.entitlements";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageReleaseConfig {
    pub archive_path: PathBuf,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BundleLayout {
    pub app: PathBuf,
    pub main_executable: PathBuf,
    pub helper: PathBuf,
    pub adapter: PathBuf,
    pub mouse_tool: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandSpec {
    pub program: String,
    pub args: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReleaseArtifacts {
    pub universal_dmg: PathBuf,
    pub default_dmg: PathBuf,
    pub universal_zip: PathBuf,
    pub arm64_dmg: PathBuf,
    pub x86_64_dmg: PathBuf,
}

pub fn parse_cli_args(args: &[String]) -> Result<PackageReleaseConfig, String> {
    let mut dry_run = false;
    let mut archive: Option<PathBuf> = None;

    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => {
                return Err(
                    "usage: package-release.sh <path to the Bazel-built Vitruvian.zip>".to_string(),
                );
            }
            s if s.starts_with('-') => {
                return Err(format!("package-release.sh: unknown option '{}'", s));
            }
            s => {
                if archive.is_some() {
                    return Err(
                        "usage: package-release.sh <path to the Bazel-built Vitruvian.zip>"
                            .to_string(),
                    );
                }
                archive = Some(PathBuf::from(s));
            }
        }
    }

    let Some(archive_path) = archive else {
        return Err(
            "usage: package-release.sh <path to the Bazel-built Vitruvian.zip>".to_string(),
        );
    };

    Ok(PackageReleaseConfig {
        archive_path,
        dry_run,
    })
}

pub fn bundle_layout(target_app: &Path) -> BundleLayout {
    BundleLayout {
        app: target_app.to_path_buf(),
        main_executable: target_app.join("Contents/MacOS/Vitruvian"),
        helper: target_app
            .join("Contents/Library/LaunchServices")
            .join(FAN_HELPER_ID),
        adapter: target_app.join("Contents/Frameworks/libVitruvianNowPlaying.dylib"),
        mouse_tool: target_app.join("Contents/Helpers/gravastar-mouse"),
    }
}

pub fn expected_artifacts(dist_dir: &Path, version: &str) -> ReleaseArtifacts {
    ReleaseArtifacts {
        universal_dmg: dist_dir.join(format!("Vitruvian-{}-universal.dmg", version)),
        default_dmg: dist_dir.join(format!("Vitruvian-{}.dmg", version)),
        universal_zip: dist_dir.join(format!("Vitruvian-{}-universal.zip", version)),
        arm64_dmg: dist_dir.join(format!("Vitruvian-{}-arm64.dmg", version)),
        x86_64_dmg: dist_dir.join(format!("Vitruvian-{}-x86_64.dmg", version)),
    }
}

pub fn build_sign_bundle_commands(
    target_app: &Path,
    developer_id: Option<&str>,
    entitlements_path: &Path,
) -> Vec<CommandSpec> {
    let layout = bundle_layout(target_app);
    let app_str = layout.app.to_string_lossy().to_string();
    let helper_str = layout.helper.to_string_lossy().to_string();
    let adapter_str = layout.adapter.to_string_lossy().to_string();
    let mouse_str = layout.mouse_tool.to_string_lossy().to_string();
    let ent_str = entitlements_path.to_string_lossy().to_string();

    let mut cmds = Vec::new();
    if let Some(dev_id) = developer_id.filter(|s| !s.is_empty()) {
        for (id, path) in [
            (FAN_HELPER_ID, &helper_str),
            (NOW_PLAYING_ADAPTER_ID, &adapter_str),
            (MOUSE_TOOL_ID, &mouse_str),
        ] {
            cmds.push(CommandSpec {
                program: "codesign".to_string(),
                args: vec![
                    "--force".to_string(),
                    "--options".to_string(),
                    "runtime".to_string(),
                    "--timestamp".to_string(),
                    "--identifier".to_string(),
                    id.to_string(),
                    "--sign".to_string(),
                    dev_id.to_string(),
                    path.clone(),
                ],
            });
        }
        cmds.push(CommandSpec {
            program: "codesign".to_string(),
            args: vec![
                "--force".to_string(),
                "--options".to_string(),
                "runtime".to_string(),
                "--timestamp".to_string(),
                "--entitlements".to_string(),
                ent_str,
                "--sign".to_string(),
                dev_id.to_string(),
                app_str.clone(),
            ],
        });
    } else {
        for (id, path) in [
            (FAN_HELPER_ID, &helper_str),
            (NOW_PLAYING_ADAPTER_ID, &adapter_str),
            (MOUSE_TOOL_ID, &mouse_str),
        ] {
            cmds.push(CommandSpec {
                program: "codesign".to_string(),
                args: vec![
                    "--force".to_string(),
                    "--identifier".to_string(),
                    id.to_string(),
                    "--sign".to_string(),
                    "-".to_string(),
                    path.clone(),
                ],
            });
        }
        cmds.push(CommandSpec {
            program: "codesign".to_string(),
            args: vec![
                "--force".to_string(),
                "--sign".to_string(),
                "-".to_string(),
                app_str.clone(),
            ],
        });
    }

    for path in [&helper_str, &adapter_str, &mouse_str] {
        cmds.push(CommandSpec {
            program: "codesign".to_string(),
            args: vec!["--verify".to_string(), "--strict".to_string(), path.clone()],
        });
    }
    cmds.push(CommandSpec {
        program: "codesign".to_string(),
        args: vec![
            "--verify".to_string(),
            "--deep".to_string(),
            "--strict".to_string(),
            app_str,
        ],
    });

    cmds
}

pub fn build_lipo_thin_commands(target_app: &Path, arch: &str) -> Vec<CommandSpec> {
    let layout = bundle_layout(target_app);
    [
        layout.main_executable,
        layout.helper,
        layout.adapter,
        layout.mouse_tool,
    ]
    .into_iter()
    .map(|bin| {
        let s = bin.to_string_lossy().to_string();
        CommandSpec {
            program: "lipo".to_string(),
            args: vec![
                s.clone(),
                "-thin".to_string(),
                arch.to_string(),
                "-output".to_string(),
                s,
            ],
        }
    })
    .collect()
}

pub fn parse_developer_id_from_security(security_output: &str) -> Option<String> {
    for line in security_output.lines() {
        if line.contains("Developer ID Application") {
            let first_quote = line.find('"')?;
            let rest = &line[first_quote + 1..];
            let second_quote = rest.find('"')?;
            let id = &rest[..second_quote];
            if !id.is_empty() {
                return Some(id.to_string());
            }
        }
    }
    None
}

fn detect_developer_id() -> Option<String> {
    let out = Command::new("security")
        .args(["find-identity", "-v", "-p", "codesigning"])
        .output()
        .ok()?;
    parse_developer_id_from_security(&String::from_utf8_lossy(&out.stdout))
}

pub fn run_cli(args: &[String]) -> i32 {
    let cfg = match parse_cli_args(args) {
        Ok(c) => c,
        Err(msg) => {
            eprintln!("{}", msg);
            return 1;
        }
    };

    if cfg.dry_run {
        let stage_app = Path::new("/tmp/stage/Vitruvian.app");
        let cmds = build_sign_bundle_commands(
            stage_app,
            Some("Developer ID Application: Example"),
            Path::new(ENTITLEMENTS_REL),
        );
        for cmd in cmds {
            println!("dry-run: {} {}", cmd.program, cmd.args.join(" "));
        }
        let artifacts = expected_artifacts(Path::new("dist"), "0.0.0");
        println!("dry-run: artifacts -> {:?}", artifacts);
        return 0;
    }

    if !cfg.archive_path.is_file() {
        eprintln!("usage: package-release.sh <path to the Bazel-built Vitruvian.zip>");
        return 1;
    }

    let archive_abs = fs::canonicalize(&cfg.archive_path).unwrap_or(cfg.archive_path.clone());
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let stage = env::temp_dir().join(format!(
        "vitruvian_package_release_{}_{}",
        std::process::id(),
        nanos
    ));
    let _ = fs::create_dir_all(&stage);

    let code = execute_release(&archive_abs, &stage);
    let _ = fs::remove_dir_all(&stage);
    code
}

fn sign_bundle_live(target_app: &Path, dev_id: Option<&str>) -> bool {
    let _ = Command::new("chmod")
        .args(["-R", "u+w", &target_app.to_string_lossy()])
        .status();
    let _ = Command::new("xattr")
        .args(["-cr", &target_app.to_string_lossy()])
        .output();

    if let Some(id) = dev_id {
        println!("▸ Signing with {}…", id);
    } else {
        println!("▸ No Developer ID identity installed; signing ad-hoc…");
    }

    for cmd in build_sign_bundle_commands(target_app, dev_id, Path::new(ENTITLEMENTS_REL)) {
        let ok = Command::new(&cmd.program)
            .args(&cmd.args)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !ok {
            return false;
        }
    }
    true
}

fn thin_bundle_arch(universal_app: &Path, stage_dir: &Path, arch: &str) -> Result<PathBuf, ()> {
    let arch_dir = stage_dir.join(arch);
    let _ = fs::create_dir_all(&arch_dir);
    let dest_app = arch_dir.join("Vitruvian.app");
    let ok = Command::new("ditto")
        .args([
            &universal_app.to_string_lossy().to_string(),
            &dest_app.to_string_lossy().to_string(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !ok {
        return Err(());
    }

    for cmd in build_lipo_thin_commands(&dest_app, arch) {
        let bin = &cmd.args[0];
        let has_arch = Command::new("lipo")
            .args(["-info", bin])
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).contains(arch))
            .unwrap_or(false);
        if has_arch {
            let thinned = Command::new(&cmd.program)
                .args(&cmd.args)
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if !thinned {
                return Err(());
            }
        }
    }
    Ok(dest_app)
}

fn execute_release(archive: &Path, stage: &Path) -> i32 {
    println!("▸ Unpacking {}…", archive.display());
    if !Command::new("ditto")
        .args([
            "-x",
            "-k",
            &archive.to_string_lossy(),
            &stage.to_string_lossy(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    let layout = bundle_layout(&stage.join("Vitruvian.app"));
    for part in [
        &layout.app,
        &layout.helper,
        &layout.adapter,
        &layout.mouse_tool,
    ] {
        if !part.exists() {
            eprintln!("✗ {} is missing from the archive", part.display());
            return 1;
        }
    }

    let dev_id = detect_developer_id();
    if !sign_bundle_live(&layout.app, dev_id.as_deref()) {
        return 1;
    }
    if !Command::new("./Tools/notarize.sh")
        .arg(&layout.app)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    let info_plist = layout.app.join("Contents/Info.plist");
    let out = match Command::new("/usr/libexec/PlistBuddy")
        .args([
            "-c",
            "Print CFBundleShortVersionString",
            &info_plist.to_string_lossy(),
        ])
        .output()
    {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        _ => return 1,
    };
    let version = out;
    let dist_dir = Path::new("dist");
    let _ = fs::create_dir_all(dist_dir);
    let artifacts = expected_artifacts(dist_dir, &version);

    println!("▸ Packaging Universal DMG & ZIP…");
    if !Command::new("./Tools/make-dmg.sh")
        .args([
            &layout.app.to_string_lossy().to_string(),
            &artifacts.universal_dmg.to_string_lossy().to_string(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }
    if fs::copy(&artifacts.universal_dmg, &artifacts.default_dmg).is_err() {
        return 1;
    }
    let _ = fs::remove_file(&artifacts.universal_zip);
    if !Command::new("ditto")
        .args([
            "-c",
            "-k",
            "--keepParent",
            &layout.app.to_string_lossy(),
            &artifacts.universal_zip.to_string_lossy(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    println!("▸ Thinning and packaging Apple Silicon (arm64) DMG…");
    let Ok(app_arm64) = thin_bundle_arch(&layout.app, stage, "arm64") else {
        return 1;
    };
    if !sign_bundle_live(&app_arm64, dev_id.as_deref()) {
        return 1;
    }
    if !Command::new("./Tools/notarize.sh")
        .arg(&app_arm64)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }
    if !Command::new("./Tools/make-dmg.sh")
        .args([
            &app_arm64.to_string_lossy().to_string(),
            &artifacts.arm64_dmg.to_string_lossy().to_string(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    println!("▸ Thinning and packaging Intel (x86_64) DMG…");
    let Ok(app_x86_64) = thin_bundle_arch(&layout.app, stage, "x86_64") else {
        return 1;
    };
    if !sign_bundle_live(&app_x86_64, dev_id.as_deref()) {
        return 1;
    }
    if !Command::new("./Tools/notarize.sh")
        .arg(&app_x86_64)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }
    if !Command::new("./Tools/make-dmg.sh")
        .args([
            &app_x86_64.to_string_lossy().to_string(),
            &artifacts.x86_64_dmg.to_string_lossy().to_string(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    println!("▸ Notarizing DMGs…");
    for dmg in [
        &artifacts.universal_dmg,
        &artifacts.arm64_dmg,
        &artifacts.x86_64_dmg,
        &artifacts.default_dmg,
    ] {
        if !Command::new("./Tools/notarize.sh")
            .arg(dmg)
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            return 1;
        }
    }

    println!("✓ Release artifacts ready in dist/:");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cli_args() {
        assert!(parse_cli_args(&[]).is_err());
        let cfg = parse_cli_args(&["--dry-run".to_string(), "Vitruvian.zip".to_string()]).unwrap();
        assert!(cfg.dry_run);
        assert_eq!(cfg.archive_path, PathBuf::from("Vitruvian.zip"));
    }

    #[test]
    fn test_sign_bundle_commands_developer_id_vs_adhoc() {
        let app = Path::new("/tmp/stage/Vitruvian.app");
        let ent = Path::new("Resources/Vitruvian.entitlements");

        let dev_cmds = build_sign_bundle_commands(app, Some("Developer ID Application: Test"), ent);
        assert_eq!(dev_cmds.len(), 8);
        assert!(dev_cmds[0].args.contains(&"runtime".to_string()));
        assert!(dev_cmds[0].args.contains(&FAN_HELPER_ID.to_string()));
        assert!(dev_cmds[1]
            .args
            .contains(&NOW_PLAYING_ADAPTER_ID.to_string()));
        assert!(dev_cmds[2].args.contains(&MOUSE_TOOL_ID.to_string()));
        assert!(dev_cmds[3].args.contains(&"--entitlements".to_string()));

        let adhoc_cmds = build_sign_bundle_commands(app, None, ent);
        assert_eq!(adhoc_cmds.len(), 8);
        assert!(!adhoc_cmds[0].args.contains(&"runtime".to_string()));
        assert!(adhoc_cmds[3].args.contains(&"-".to_string()));
    }

    #[test]
    fn test_lipo_thin_commands_and_expected_artifacts() {
        let app = Path::new("/tmp/stage/arm64/Vitruvian.app");
        let lipo_cmds = build_lipo_thin_commands(app, "arm64");
        assert_eq!(lipo_cmds.len(), 4);
        assert!(lipo_cmds[0].args[0].ends_with("Contents/MacOS/Vitruvian"));
        assert!(lipo_cmds[3].args[0].ends_with("Contents/Helpers/gravastar-mouse"));

        let artifacts = expected_artifacts(Path::new("dist"), "1.5.0");
        assert_eq!(
            artifacts.universal_dmg,
            PathBuf::from("dist/Vitruvian-1.5.0-universal.dmg")
        );
        assert_eq!(
            artifacts.arm64_dmg,
            PathBuf::from("dist/Vitruvian-1.5.0-arm64.dmg")
        );
        assert_eq!(
            artifacts.x86_64_dmg,
            PathBuf::from("dist/Vitruvian-1.5.0-x86_64.dmg")
        );
    }
}
