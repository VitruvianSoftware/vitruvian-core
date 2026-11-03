// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Runs the test copy of Courier (`:CourierTestCopy`): a real build, with its own bundle identifier, in its own data
//! folder, so a change can be tried by hand or by a script without touching the installed Courier, its data in
//! ~/Library/Application Support/Courier, or its Keychain items.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The test copy's bundle identifier, as BUILD and CourierCore's `TestCopy` give it.
pub const BUNDLE_ID: &str = "com.vitruviansoftware.courier.dev";
/// The app's name in the archive.
pub const APP_NAME: &str = "Courier Test Copy.app";

/// The archive among Bazel's `rootpaths` (the .zip, or a path with a .zip beside it).
pub fn resolve_archive(candidates: &str) -> Option<PathBuf> {
    let mut chosen: Option<PathBuf> = None;
    for candidate in candidates.split_whitespace() {
        if candidate.ends_with(".zip") {
            chosen = Some(PathBuf::from(candidate));
        } else if chosen.is_none() {
            let zip = format!("{}.zip", candidate);
            if Path::new(&zip).exists() {
                chosen = Some(PathBuf::from(zip));
            }
        }
    }
    chosen
}

/// Whether `data` is the installed Courier's data folder (or inside it), which the test copy must never use.
pub fn is_installed_apps_data(data: &Path, home: &Path) -> bool {
    let real = home.join("Library/Application Support/Courier");
    let normalized =
        |p: &Path| -> PathBuf { fs::canonicalize(p).unwrap_or_else(|_| p.components().collect()) };
    normalized(data).starts_with(normalized(&real))
}

fn bundle_identifier(app: &Path) -> Option<String> {
    let out = Command::new("/usr/bin/plutil")
        .args(["-extract", "CFBundleIdentifier", "raw", "-o", "-"])
        .arg(app.join("Contents/Info.plist"))
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn run(args: &[String]) -> i32 {
    if args.len() < 2 {
        eprintln!("Usage: run_test_copy <CourierTestCopy.zip> [--data DIR] [--no-open]");
        return 2;
    }
    let base = PathBuf::from(env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string()))
        .join("courier-test-copy");
    let mut data = base.join("data");
    let mut open = true;
    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--data" if i + 1 < args.len() => {
                i += 1;
                data = PathBuf::from(&args[i]);
            }
            "--no-open" => open = false,
            other => {
                eprintln!("run_test_copy: unknown argument {}", other);
                return 2;
            }
        }
        i += 1;
    }
    let home = PathBuf::from(env::var("HOME").unwrap_or_default());
    if is_installed_apps_data(&data, &home) {
        eprintln!(
            "run_test_copy: {} is the installed Courier's data; give the test copy its own",
            data.display()
        );
        return 2;
    }
    let Some(archive) = resolve_archive(&args[1]) else {
        eprintln!("run_test_copy: no CourierTestCopy.zip in {}", args[1]);
        return 2;
    };

    let unpacked = base.join("app");
    let _ = fs::remove_dir_all(&unpacked);
    if fs::create_dir_all(&unpacked).is_err() || fs::create_dir_all(&data).is_err() {
        eprintln!(
            "run_test_copy: cannot make {} or {}",
            unpacked.display(),
            data.display()
        );
        return 1;
    }
    let unzipped = Command::new("/usr/bin/unzip")
        .arg("-q")
        .arg(&archive)
        .arg("-d")
        .arg(&unpacked)
        .status();
    if !unzipped.map(|s| s.success()).unwrap_or(false) {
        eprintln!("run_test_copy: unzip failed");
        return 1;
    }
    let app = unpacked.join(APP_NAME);
    match bundle_identifier(&app) {
        Some(id) if id == BUNDLE_ID => {}
        other => {
            eprintln!(
                "run_test_copy: {} has bundle identifier {:?}, not {}; refusing to run it",
                app.display(),
                other,
                BUNDLE_ID
            );
            return 1;
        }
    }
    println!("Test copy: {}", app.display());
    println!("Its data:  {}", data.display());
    if !open {
        return 0;
    }
    // -n: a new instance even if one is running; --env reaches the app, which hands the folder to its engine.
    let opened = Command::new("/usr/bin/open")
        .arg("-n")
        .arg("--env")
        .arg(format!("COURIER_DATA_DIR={}", data.display()))
        .arg(&app)
        .status();
    if opened.map(|s| s.success()).unwrap_or(false) {
        println!("Opened. Quit it from its menu (Courier Test Copy) when done.");
        0
    } else {
        eprintln!("run_test_copy: open failed");
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_the_installed_apps_data() {
        let home = Path::new("/Users/example");
        assert!(is_installed_apps_data(
            Path::new("/Users/example/Library/Application Support/Courier"),
            home
        ));
        assert!(is_installed_apps_data(
            Path::new("/Users/example/Library/Application Support/Courier/sub"),
            home
        ));
        assert!(!is_installed_apps_data(
            Path::new("/Users/example/Library/Application Support/Courier Test Copy"),
            home
        ));
        assert!(!is_installed_apps_data(
            Path::new("/tmp/courier-test-copy/data"),
            home
        ));
    }

    #[test]
    fn finds_the_archive() {
        assert_eq!(
            resolve_archive("a/CourierTestCopy.zip"),
            Some(PathBuf::from("a/CourierTestCopy.zip"))
        );
        assert_eq!(resolve_archive("nothing-here"), None);
    }

    #[test]
    fn no_arguments_is_a_usage_error() {
        assert_eq!(run(&["run_test_copy".to_string()]), 2);
    }
}
