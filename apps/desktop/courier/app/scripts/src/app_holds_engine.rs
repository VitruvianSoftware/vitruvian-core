// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn resolve_app(paths: &[String]) -> Result<PathBuf, String> {
    let mut archive: Option<PathBuf> = None;
    let mut app: Option<PathBuf> = None;

    for path in paths {
        if path.ends_with(".zip") {
            archive = Some(PathBuf::from(path));
        } else if path.ends_with("Courier.app") && Path::new(path).is_dir() {
            app = Some(PathBuf::from(path));
        } else {
            let zip = format!("{}.zip", path);
            if Path::new(&zip).exists() {
                archive = Some(PathBuf::from(zip));
            }
        }
    }

    if app.is_none() {
        if let Some(ref arc) = archive {
            let tmp = env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
            let dest = format!("{}/unzipped", tmp);
            let status = Command::new("unzip")
                .args(["-q", &arc.to_string_lossy(), "-d", &dest])
                .status()
                .map_err(|e| format!("unzip failed: {}", e))?;
            if !status.success() {
                return Err(format!("unzip failed on {}", arc.display()));
            }
            let candidate = PathBuf::from(&dest).join("Courier.app");
            if candidate.is_dir() {
                app = Some(candidate);
            }
        }
    }

    app.ok_or_else(|| format!("no Courier.app among the paths given: {}", paths.join(" ")))
}

pub fn run(args: &[String]) -> i32 {
    if args.len() < 3 {
        eprintln!("Usage: app-holds-engine <version> <path>...");
        return 2;
    }

    let version = &args[1];
    let paths = &args[2..];

    let app = match resolve_app(&paths.to_vec()) {
        Ok(a) => a,
        Err(msg) => {
            eprintln!("FAIL: {}", msg);
            return 2;
        }
    };

    let mut failed = 0;

    let engine = app.join("Contents/Helpers/courier-engine");
    if !engine.exists() {
        eprintln!("FAIL: Contents/Helpers/courier-engine is missing or not executable");
        eprintln!("Contents holds:");
        let _ = Command::new("find")
            .args([
                &app.join("Contents").to_string_lossy().to_string(),
                "-maxdepth",
                "2",
            ])
            .stderr(std::process::Stdio::inherit())
            .status();
        return 1;
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(&engine) {
            if meta.permissions().mode() & 0o111 == 0 {
                eprintln!("FAIL: Contents/Helpers/courier-engine is missing or not executable");
                return 1;
            }
        }
    }

    // Check file type
    let engine_str = engine.to_string_lossy().to_string();
    if let Ok(out) = Command::new("file").args(["-b", &engine_str]).output() {
        let kind = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if kind.contains("Mach-O 64-bit executable arm64") {
            println!("ok: courier-engine is {}", kind);
        } else {
            eprintln!(
                "FAIL: courier-engine is not an arm64 Mach-O executable: {}",
                kind
            );
            failed = 1;
        }
    }

    // Run engine --help
    match Command::new(&engine_str).arg("--help").output() {
        Ok(out) => {
            let status = out.status.code().unwrap_or(-1);
            let combined = format!(
                "{}{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            if status == 2 && combined.contains("usage: courier-engine --data DIR [--parent-fd N]")
            {
                println!("ok: courier-engine --help exits 2 with its usage");
            } else {
                eprintln!(
                    "FAIL: courier-engine --help exited {} with: {}",
                    status,
                    combined.trim()
                );
                failed = 1;
            }
        }
        Err(e) => {
            eprintln!("FAIL: cannot run courier-engine --help: {}", e);
            failed = 1;
        }
    }

    // Check version in Info.plist
    let plist = app.join("Contents/Info.plist");
    let plist_str = plist.to_string_lossy().to_string();
    for key in &["CFBundleShortVersionString", "CFBundleVersion"] {
        let got = Command::new("plutil")
            .args(["-extract", key, "raw", "-o", "-", &plist_str])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default();
        if got == *version {
            println!("ok: {} is {}", key, version);
        } else {
            eprintln!("FAIL: {} is '{}', expected {}", key, got, version);
            failed = 1;
        }
    }

    // Check resources
    for resource in &["AppIcon.icns", "en.lproj/Localizable.strings"] {
        let path = app.join("Contents/Resources").join(resource);
        if path.exists() {
            println!("ok: Contents/Resources/{}", resource);
        } else {
            eprintln!("FAIL: Contents/Resources/{} is missing", resource);
            failed = 1;
        }
    }

    failed
}
