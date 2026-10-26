// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `Tools/make-dmg.sh`.
//! Packages a signed `Vitruvian.app` into a styled, distributable DMG.

use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const APP_NAME: &str = "Vitruvian";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MakeDmgConfig {
    pub app_path: PathBuf,
    pub output_path: Option<PathBuf>,
    pub developer_id: Option<String>,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MakeDmgPlan {
    pub app_path: PathBuf,
    pub version: String,
    pub output_path: PathBuf,
    pub volume_name: String,
    pub work_dir: PathBuf,
    pub staging_dir: PathBuf,
    pub background_png: PathBuf,
    pub developer_id: Option<String>,
}

pub fn parse_cli_args(
    args: &[String],
    developer_id_env: Option<String>,
) -> Result<MakeDmgConfig, String> {
    let mut dry_run = false;
    let mut positionals = Vec::new();

    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => {
                return Err(format!(
                    "usage: make-dmg.sh <path to the signed {}.app> [output.dmg]",
                    APP_NAME
                ));
            }
            s if s.starts_with('-') => {
                return Err(format!("make-dmg.sh: unknown option '{}'", s));
            }
            s => positionals.push(s.to_string()),
        }
    }

    if positionals.is_empty() || positionals.len() > 2 {
        return Err(format!(
            "usage: make-dmg.sh <path to the signed {}.app>",
            APP_NAME
        ));
    }

    let app_path = PathBuf::from(&positionals[0]);
    let output_path = positionals.get(1).map(PathBuf::from);
    let developer_id = developer_id_env.filter(|s| !s.is_empty());

    Ok(MakeDmgConfig {
        app_path,
        output_path,
        developer_id,
        dry_run,
    })
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

pub fn read_app_version(app_path: &Path) -> Result<String, String> {
    let info_plist = app_path.join("Contents/Info.plist");
    if !info_plist.is_file() {
        return Err(format!("{} not found", info_plist.display()));
    }
    if let Ok(xml) = fs::read_to_string(&info_plist) {
        if let Some(v) = extract_plist_short_version(&xml) {
            return Ok(v);
        }
    }
    let out = Command::new("/usr/libexec/PlistBuddy")
        .args([
            "-c",
            "Print CFBundleShortVersionString",
            &info_plist.to_string_lossy(),
        ])
        .output()
        .map_err(|e| format!("failed to run PlistBuddy: {}", e))?;
    if !out.status.success() {
        return Err(format!(
            "could not read version from {}",
            info_plist.display()
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn build_plan(
    cfg: &MakeDmgConfig,
    version: &str,
    work_dir: &Path,
    staging_dir: &Path,
) -> MakeDmgPlan {
    let output_path = cfg
        .output_path
        .clone()
        .unwrap_or_else(|| PathBuf::from(format!("dist/{}-{}.dmg", APP_NAME, version)));

    MakeDmgPlan {
        app_path: cfg.app_path.clone(),
        version: version.to_string(),
        output_path,
        volume_name: APP_NAME.to_string(),
        work_dir: work_dir.to_path_buf(),
        staging_dir: staging_dir.to_path_buf(),
        background_png: work_dir.join("dmg-background.png"),
        developer_id: cfg.developer_id.clone(),
    }
}

pub fn parse_mount_point(attach_output: &str) -> Option<String> {
    for line in attach_output.lines() {
        if let Some(idx) = line.find("/Volumes/") {
            let mount = line[idx..].trim();
            if !mount.is_empty() {
                return Some(mount.to_string());
            }
        }
    }
    None
}

pub fn extract_image_devices(hdiutil_info: &str, target: &str) -> Vec<String> {
    let stripped = target.strip_prefix("/private").unwrap_or(target);
    let private_prefixed = format!("/private{}", target);
    let mut matched = false;
    let mut seen = HashSet::new();
    let mut devices = Vec::new();

    for line in hdiutil_info.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("===") {
            matched = false;
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("image-path") {
            let rest_trimmed = rest.trim_start();
            if let Some(after_colon) = rest_trimmed.strip_prefix(':') {
                let path = after_colon.trim();
                matched = path == target || path == private_prefixed || path == stripped;
                continue;
            }
        }
        if matched {
            if let Some(rest) = trimmed.strip_prefix("/dev/disk") {
                let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
                if !digits.is_empty() {
                    let dev = format!("/dev/disk{}", digits);
                    if seen.insert(dev.clone()) {
                        devices.push(dev);
                    }
                }
            }
        }
    }
    devices
}

pub fn render_finder_applescript(volume: &str, app_name: &str) -> String {
    format!(
        "tell application \"Finder\"\n\
    tell disk \"{volume}\"\n\
        open\n\
        set current view of container window to icon view\n\
        set toolbar visible of container window to false\n\
        set statusbar visible of container window to false\n\
        set the bounds of container window to {{200, 120, 800, 520}}\n\
        set theOptions to the icon view options of container window\n\
        set arrangement of theOptions to not arranged\n\
        set icon size of theOptions to 128\n\
        set text size of theOptions to 13\n\
        set background picture of theOptions to file \".background:background.png\"\n\
        set position of item \"{app_name}.app\" of container window to {{150, 200}}\n\
        set position of item \"Applications\" of container window to {{450, 200}}\n\
        update without registering applications\n\
        delay 1\n\
        close\n\
    end tell\n\
end tell\n"
    )
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

fn release_image(rw_path: &Path) {
    let Ok(out) = Command::new("hdiutil").arg("info").output() else {
        return;
    };
    let info = String::from_utf8_lossy(&out.stdout);
    for dev in extract_image_devices(&info, &rw_path.to_string_lossy()) {
        let _ = Command::new("hdiutil")
            .args(["detach", &dev, "-force"])
            .status();
    }
}

pub fn run_cli(args: &[String]) -> i32 {
    let dev_id_env = env::var("DEVELOPER_ID").ok();
    let cfg = match parse_cli_args(args, dev_id_env) {
        Ok(c) => c,
        Err(msg) => {
            eprintln!("{}", msg);
            return 1;
        }
    };

    if cfg.dry_run {
        let version = read_app_version(&cfg.app_path).unwrap_or_else(|_| "0.0.0".to_string());
        let plan = build_plan(
            &cfg,
            &version,
            Path::new("/tmp/make-dmg-work"),
            Path::new("/tmp/make-dmg-staging"),
        );
        println!(
            "dry-run: stage {} -> {}",
            plan.app_path.display(),
            plan.staging_dir.display()
        );
        println!(
            "dry-run: hdiutil create/attach/convert -> {}",
            plan.output_path.display()
        );
        return 0;
    }

    if !cfg.app_path.is_dir() {
        eprintln!("✗ {} not found", cfg.app_path.display());
        return 1;
    }

    let _ = Command::new("xattr")
        .args(["-cr", &cfg.app_path.to_string_lossy()])
        .output();
    if !Command::new("codesign")
        .args([
            "--verify",
            "--deep",
            "--strict",
            &cfg.app_path.to_string_lossy(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    let version = match read_app_version(&cfg.app_path) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("✗ {}", e);
            return 1;
        }
    };

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let work_dir = env::temp_dir().join(format!(
        "vitruvian_dmg_work_{}_{}",
        std::process::id(),
        nanos
    ));
    let staging_dir = env::temp_dir().join(format!(
        "vitruvian_dmg_stage_{}_{}",
        std::process::id(),
        nanos
    ));
    let _ = fs::create_dir_all(&work_dir);
    let _ = fs::create_dir_all(&staging_dir);

    let mut plan = build_plan(&cfg, &version, &work_dir, &staging_dir);
    if plan.developer_id.is_none() {
        plan.developer_id = detect_developer_id();
    }

    let result = execute_plan(&plan);

    let _ = fs::remove_dir_all(&staging_dir);
    let _ = fs::remove_dir_all(&work_dir);
    result
}

fn execute_plan(plan: &MakeDmgPlan) -> i32 {
    println!("▸ Rendering installer background…");
    if !Command::new("swift")
        .args([
            "Tools/MakeDMGBackground.swift",
            &plan.background_png.to_string_lossy(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    println!("▸ Staging DMG contents…");
    let staged_app = plan.staging_dir.join(format!("{}.app", APP_NAME));
    if !Command::new("ditto")
        .args([
            &plan.app_path.to_string_lossy().to_string(),
            &staged_app.to_string_lossy().to_string(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }
    let _ = Command::new("xattr")
        .args(["-cr", &staged_app.to_string_lossy()])
        .output();
    if !Command::new("codesign")
        .args([
            "--verify",
            "--deep",
            "--strict",
            &staged_app.to_string_lossy(),
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    #[cfg(unix)]
    {
        let _ = std::os::unix::fs::symlink("/Applications", plan.staging_dir.join("Applications"));
    }
    let bg_dir = plan.staging_dir.join(".background");
    let _ = fs::create_dir_all(&bg_dir);
    if fs::copy(&plan.background_png, bg_dir.join("background.png")).is_err() {
        return 1;
    }

    println!("▸ Creating writable image…");
    let _ = Command::new("hdiutil")
        .args([
            "detach",
            &format!("/Volumes/{}", plan.volume_name),
            "-force",
        ])
        .output();

    let mut rw_image = None;
    for attempt in 1..=3 {
        let candidate = plan.work_dir.join(format!("rw-{}.dmg", attempt));
        let ok = Command::new("hdiutil")
            .args([
                "create",
                "-volname",
                &plan.volume_name,
                "-srcfolder",
                &plan.staging_dir.to_string_lossy(),
                "-fs",
                "HFS+",
                "-format",
                "UDRW",
                "-ov",
                &candidate.to_string_lossy(),
            ])
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            rw_image = Some(candidate);
            break;
        }
        eprintln!(
            "  hdiutil create failed (attempt {} of 3), retrying…",
            attempt
        );
        release_image(&candidate);
        let _ = fs::remove_file(&candidate);
        thread::sleep(Duration::from_secs(3));
    }

    let Some(rw) = rw_image else {
        eprintln!("✗ Could not create the disk image after 3 attempts");
        return 1;
    };

    let attach_out = match Command::new("hdiutil")
        .args(["attach", &rw.to_string_lossy(), "-nobrowse"])
        .output()
    {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => {
            eprintln!("✗ hdiutil attach failed");
            return 1;
        }
    };

    let Some(mount) = parse_mount_point(&attach_out) else {
        eprintln!("✗ Could not find mounted volume in hdiutil output");
        eprintln!("{}", attach_out);
        return 1;
    };
    if !Path::new(&mount).is_dir() {
        eprintln!("✗ Could not find mounted volume in hdiutil output");
        return 1;
    }

    println!("▸ Arranging window (icons, arrow, background)…");
    let script = render_finder_applescript(&plan.volume_name, APP_NAME);
    let _ = Command::new("osascript").args(["-e", &script]).status();

    let mut detached = false;
    for attempt in 1..=4 {
        let ok = Command::new("hdiutil")
            .args(["detach", &mount])
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok || !Path::new(&mount).is_dir() {
            detached = true;
            break;
        }
        eprintln!(
            "  hdiutil detach failed (attempt {} of 4), retrying…",
            attempt
        );
        thread::sleep(Duration::from_secs(2));
    }
    if !detached && Path::new(&mount).is_dir() {
        let _ = Command::new("hdiutil")
            .args(["detach", &mount, "-force"])
            .status();
    }

    release_image(&rw);

    println!("▸ Compressing…");
    if let Some(parent) = plan.output_path.parent() {
        if !parent.as_os_str().is_empty() {
            let _ = fs::create_dir_all(parent);
        }
    }
    let _ = fs::remove_file(&plan.output_path);

    let mut converted = false;
    for attempt in 1..=3 {
        let ok = Command::new("hdiutil")
            .args([
                "convert",
                &rw.to_string_lossy(),
                "-format",
                "UDZO",
                "-imagekey",
                "zlib-level=9",
                "-o",
                &plan.output_path.to_string_lossy(),
            ])
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            converted = true;
            break;
        }
        eprintln!(
            "  hdiutil convert failed (attempt {} of 3), retrying…",
            attempt
        );
        let _ = fs::remove_file(&plan.output_path);
        thread::sleep(Duration::from_secs(5));
    }
    if !converted {
        eprintln!("✗ Could not compress the disk image after 3 attempts");
        return 1;
    }

    if let Some(ref dev_id) = plan.developer_id {
        println!("▸ Signing the disk image with {}…", dev_id);
        let out_str = plan.output_path.to_string_lossy().to_string();
        if !Command::new("codesign")
            .args(["--force", "--timestamp", "--sign", dev_id, &out_str])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            return 1;
        }
        if !Command::new("codesign")
            .args(["--verify", "--strict", &out_str])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            return 1;
        }
    } else {
        println!("▸ No Developer ID identity installed; the disk image stays unsigned");
    }

    println!("✓ DMG ready: {}", plan.output_path.display());
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cli_args_and_default_output() {
        let cfg = parse_cli_args(&["/tmp/Vitruvian.app".to_string()], None).unwrap();
        let plan = build_plan(&cfg, "2.4.1", Path::new("/tmp/w"), Path::new("/tmp/s"));
        assert_eq!(plan.output_path, PathBuf::from("dist/Vitruvian-2.4.1.dmg"));
    }

    #[test]
    fn test_extract_plist_short_version() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>3.12.0</string>
</dict>
</plist>"#;
        assert_eq!(extract_plist_short_version(xml), Some("3.12.0".to_string()));
    }

    #[test]
    fn test_parse_mount_point_handles_spaces_in_volume_name() {
        let out = "/dev/disk6          \tGUID_partition_scheme          \t\n\
                   /dev/disk6s1        \tApple_HFS                      \t/Volumes/Vitruvian 1\n";
        assert_eq!(
            parse_mount_point(out),
            Some("/Volumes/Vitruvian 1".to_string())
        );
    }

    #[test]
    fn test_extract_image_devices_matches_private_and_non_private() {
        let info = "================================================\n\
                    image-path      : /private/var/folders/xx/T/work/rw-1.dmg\n\
                    /dev/disk9          \tFDisk_partition_scheme         \t\n\
                    /dev/disk9s1        \tApple_HFS                      \t\n";
        let devs = extract_image_devices(info, "/var/folders/xx/T/work/rw-1.dmg");
        assert_eq!(devs, vec!["/dev/disk9".to_string()]);
    }

    #[test]
    fn test_parse_developer_id_from_security() {
        let sec = "  1) ABCDEF123456 \"Developer ID Application: Vitruvian Software (TEAMID1234)\"\n     1 valid identities found\n";
        assert_eq!(
            parse_developer_id_from_security(sec),
            Some("Developer ID Application: Vitruvian Software (TEAMID1234)".to_string())
        );
    }

    #[test]
    fn test_render_finder_applescript() {
        let script = render_finder_applescript("Vitruvian", "Vitruvian");
        assert!(script
            .contains("set position of item \"Vitruvian.app\" of container window to {150, 200}"));
        assert!(script
            .contains("set position of item \"Applications\" of container window to {450, 200}"));
    }
}
