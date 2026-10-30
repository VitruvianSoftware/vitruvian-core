// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Bazel test wrapper for the app's runtime health check (`--selftest`).
//!
//! The self test reads resources through `Bundle.main` (the menu bar icon, the
//! symbol gallery), so it has to run from inside the assembled bundle, not from
//! a bare binary. `rules_apple` emits the bundle as a `.zip` unless tree-artifact
//! outputs are on; accept either.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn select_bundle_candidate(candidates: &[String]) -> Option<String> {
    for candidate in candidates {
        if candidate.ends_with(".zip") || candidate.ends_with(".app") {
            return Some(candidate.clone());
        }
    }
    for candidate in candidates {
        let zipped = format!("{}.zip", candidate);
        if Path::new(&zipped).exists() {
            return Some(zipped);
        }
    }
    None
}

pub fn find_first_app_in_dir(dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(dir).ok()?;
    let mut apps: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.ends_with(".app"))
                .unwrap_or(false)
        })
        .collect();
    apps.sort();
    apps.into_iter().next()
}

pub fn is_executable(path: &Path) -> bool {
    let Ok(meta) = fs::metadata(path) else {
        return false;
    };
    if !meta.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        (meta.permissions().mode() & 0o111) != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

fn exit_code_of(status: std::process::ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        code
    } else {
        #[cfg(unix)]
        {
            use std::os::unix::process::ExitStatusExt;
            if let Some(sig) = status.signal() {
                return 128 + sig;
            }
        }
        1
    }
}

pub fn run_cli_with_tools(args: &[String], ditto_bin: &str, codesign_bin: &str) -> i32 {
    if args.is_empty() {
        eprintln!("usage: run_selftest <executable name> <the bundle target's files...>");
        return 2;
    }
    let executable = &args[0];
    let candidates = &args[1..];
    let bundle = select_bundle_candidate(candidates).unwrap_or_default();

    let app_path: Option<PathBuf> = if bundle.ends_with(".zip") {
        let tmp_base = env::var("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| env::temp_dir());
        let bundle_dir = tmp_base.join("bundle");
        let status = match Command::new(ditto_bin)
            .args(["-x", "-k", &bundle])
            .arg(&bundle_dir)
            .status()
        {
            Ok(s) => s,
            Err(e) => {
                eprintln!("failed to run {}: {}", ditto_bin, e);
                return 1;
            }
        };
        if !status.success() {
            return exit_code_of(status);
        }
        find_first_app_in_dir(&bundle_dir)
    } else if bundle.ends_with(".app") {
        Some(PathBuf::from(&bundle))
    } else {
        eprintln!(
            "no .zip or .app among the bundle outputs: {}",
            candidates.join(" ")
        );
        return 2;
    };

    let Some(app) = app_path else {
        eprintln!(
            "no executable Contents/MacOS/{} in <missing bundle>",
            executable
        );
        return 1;
    };
    let bin_path = app.join("Contents/MacOS").join(executable);
    if !is_executable(&bin_path) {
        eprintln!(
            "no executable Contents/MacOS/{} in {}",
            executable,
            app.display()
        );
        return 1;
    }

    let cs_status = match Command::new(codesign_bin)
        .args(["--verify", "--deep", "--strict"])
        .arg(&app)
        .status()
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("failed to run {}: {}", codesign_bin, e);
            return 1;
        }
    };
    if !cs_status.success() {
        return exit_code_of(cs_status);
    }

    match Command::new(&bin_path).arg("--selftest").status() {
        Ok(s) => exit_code_of(s),
        Err(e) => {
            eprintln!("failed to run {}: {}", bin_path.display(), e);
            1
        }
    }
}

pub fn run_cli(args: &[String]) -> i32 {
    run_cli_with_tools(args, "/usr/bin/ditto", "/usr/bin/codesign")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_select_bundle_candidate() {
        assert_eq!(
            select_bundle_candidate(&["launcher".to_string(), "Vitruvian.app".to_string()]),
            Some("Vitruvian.app".to_string())
        );
        assert_eq!(
            select_bundle_candidate(&["launcher".to_string(), "Vitruvian.zip".to_string()]),
            Some("Vitruvian.zip".to_string())
        );
        assert_eq!(select_bundle_candidate(&["launcher".to_string()]), None);
    }

    #[test]
    fn test_run_selftest_with_app_bundle_and_missing_cases() {
        let tmp = env::temp_dir().join(format!("test_run_selftest_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        // Missing bundle outputs -> exit 2
        assert_eq!(
            run_cli_with_tools(
                &["Vitruvian".to_string(), "not_a_bundle".to_string()],
                "/usr/bin/true",
                "/usr/bin/true"
            ),
            2
        );

        // .app without executable -> exit 1
        let empty_app = tmp.join("Empty.app");
        fs::create_dir_all(&empty_app).unwrap();
        assert_eq!(
            run_cli_with_tools(
                &[
                    "Vitruvian".to_string(),
                    empty_app.to_string_lossy().to_string()
                ],
                "/usr/bin/true",
                "/usr/bin/true"
            ),
            1
        );

        // .app with valid executable -> runs codesign & executable --selftest
        let valid_app = tmp.join("Valid.app");
        let macos_dir = valid_app.join("Contents/MacOS");
        fs::create_dir_all(&macos_dir).unwrap();
        let exe = macos_dir.join("Vitruvian");
        fs::write(
            &exe,
            "#!/bin/sh\ntest \"$1\" = \"--selftest\" && exit 0\nexit 3\n",
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&exe).unwrap().permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&exe, perms).unwrap();
        }

        assert_eq!(
            run_cli_with_tools(
                &[
                    "Vitruvian".to_string(),
                    valid_app.to_string_lossy().to_string()
                ],
                "/usr/bin/true",
                "/usr/bin/true"
            ),
            0
        );

        let _ = fs::remove_dir_all(&tmp);
    }
}
