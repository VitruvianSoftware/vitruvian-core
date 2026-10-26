// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

fn resolve_archive(candidates: &str) -> Option<PathBuf> {
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

fn regex_escape(s: &str) -> String {
    let mut result = String::new();
    for c in s.chars() {
        if "[]\\.*^$+?(){}|/".contains(c) {
            result.push('\\');
        }
        result.push(c);
    }
    result
}

fn running_pids(patterns: &[String]) -> Vec<u32> {
    let mut pids = std::collections::BTreeSet::new();
    for pattern in patterns {
        if let Ok(out) = Command::new("pgrep").args(["-f", pattern]).output() {
            if out.status.success() {
                for line in String::from_utf8_lossy(&out.stdout).lines() {
                    if let Ok(pid) = line.trim().parse::<u32>() {
                        pids.insert(pid);
                    }
                }
            }
        }
    }
    pids.into_iter().collect()
}

pub fn run(args: &[String]) -> i32 {
    if args.len() < 3 {
        eprintln!("Usage: install <inject-app-credentials> <Courier.zip> [--dest DIR]");
        return 2;
    }

    let injector = &args[1];
    let archive_arg = &args[2];

    let mut dest = PathBuf::from("/Applications");
    let mut i = 3;
    while i < args.len() {
        match args[i].as_str() {
            "--dest" => {
                if i + 1 >= args.len() {
                    eprintln!("install: --dest needs a folder");
                    return 2;
                }
                i += 1;
                dest = PathBuf::from(&args[i]);
            }
            other => {
                eprintln!("install: unknown argument {}", other);
                return 2;
            }
        }
        i += 1;
    }

    let archive = match resolve_archive(archive_arg) {
        Some(a) => a,
        None => PathBuf::from(archive_arg),
    };

    if !archive.exists() {
        eprintln!("install: no Courier.zip at {}", archive.display());
        return 2;
    }
    if !dest.is_dir() {
        eprintln!("install: {} is not a folder", dest.display());
        return 2;
    }

    let dest = fs::canonicalize(&dest).unwrap_or(dest);
    let installed = dest.join("Courier.app");

    let scratch_base = env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
    let scratch = format!("{}/courier-install.{}", scratch_base, std::process::id());
    let _ = fs::create_dir_all(&scratch);

    // Unzip
    let status = Command::new("unzip")
        .args([
            "-q",
            &archive.to_string_lossy(),
            "-d",
            &format!("{}/unpacked", scratch),
        ])
        .status();
    if !status.map(|s| s.success()).unwrap_or(false) {
        eprintln!("install: unzip failed");
        let _ = fs::remove_dir_all(&scratch);
        return 1;
    }

    let app = format!("{}/unpacked/Courier.app", scratch);
    if !Path::new(&app).is_dir() {
        eprintln!("install: the archive holds no Courier.app");
        let _ = fs::remove_dir_all(&scratch);
        return 1;
    }

    // Run injector with --allow-missing
    let injector_status = Command::new(injector)
        .args(["--allow-missing", &app])
        .status();
    if !injector_status.map(|s| s.success()).unwrap_or(false) {
        // injector already printed its error
    }

    let plist_path = format!("{}/Contents/Resources/TelegramApp.plist", app);
    if !Path::new(&plist_path).exists() {
        println!("Note: this Courier has no Telegram app ID built in, so it will ask for Telegram keys when Telegram is added.");
    }

    // Build patterns for running process detection
    let installed_str = installed.to_string_lossy().to_string();
    let installed_real = fs::canonicalize(&dest)
        .map(|d| d.join("Courier.app").to_string_lossy().to_string())
        .unwrap_or_else(|_| installed_str.clone());

    let mut patterns = Vec::new();
    for prefix in &[&installed_str, &installed_real] {
        let escaped = regex_escape(prefix);
        patterns.push(format!("^{}/Contents/MacOS/Courier( |$)", escaped));
        patterns.push(format!("^{}/Contents/Helpers/courier-engine( |$)", escaped));
    }

    let pids = running_pids(&patterns);
    if !pids.is_empty() {
        println!("Quitting the Courier installed in {}...", dest.display());
        let _ = Command::new("osascript")
            .args(["-e", &format!("quit app \"{}\"", installed_str)])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();

        let mut waited = 0u32;
        while !running_pids(&patterns).is_empty() && waited < 30 {
            thread::sleep(Duration::from_secs(1));
            waited += 1;
            if waited == 10 {
                for pid in running_pids(&patterns) {
                    unsafe {
                        libc::kill(pid as i32, libc::SIGTERM);
                    }
                }
            }
        }

        if !running_pids(&patterns).is_empty() {
            eprintln!("install: Courier is still running after 30 seconds. Quit it and run this again; nothing was replaced.");
            let _ = fs::remove_dir_all(&scratch);
            return 1;
        }
    }

    let staging = dest.join(".Courier.app.new");
    let aside = dest.join(".Courier.app.old");
    let _ = fs::remove_dir_all(&staging);

    // Recover from interrupted previous install
    if aside.exists() {
        if !installed.exists() {
            let _ = fs::rename(&aside, &installed);
            println!(
                "Note: an earlier install was interrupted; the Courier it had set aside is back in {}.",
                dest.display()
            );
        } else {
            let verify = Command::new("codesign")
                .args(["--verify", "--deep", "--strict", &installed_str])
                .status();
            if verify.map(|s| s.success()).unwrap_or(false) {
                let _ = fs::remove_dir_all(&aside);
            } else {
                let _ = fs::remove_dir_all(&installed);
                let _ = fs::rename(&aside, &installed);
                println!(
                    "Note: an earlier install was interrupted; the Courier it had set aside is back in {}.",
                    dest.display()
                );
            }
        }
    }

    // ditto the app
    let status = Command::new("ditto")
        .args([&app, &staging.to_string_lossy().to_string()])
        .status();
    if !status.map(|s| s.success()).unwrap_or(false) {
        eprintln!("install: ditto failed");
        let _ = fs::remove_dir_all(&scratch);
        let _ = fs::remove_dir_all(&staging);
        return 1;
    }

    let had_old = installed.exists();

    // Move old aside, move new into place
    if had_old {
        if fs::rename(&installed, &aside).is_err() {
            eprintln!("install: could not move the old app aside");
            let _ = fs::remove_dir_all(&scratch);
            let _ = fs::remove_dir_all(&staging);
            return 1;
        }
    }

    if fs::rename(&staging, &installed).is_err() {
        // Restore
        if had_old {
            if aside.exists() {
                let _ = fs::remove_dir_all(&installed);
                let _ = fs::rename(&aside, &installed);
            }
            eprintln!("install: Could not move the new app into place. The previous Courier is back in place.");
        } else {
            let _ = fs::remove_dir_all(&installed);
            eprintln!("install: Could not move the new app into place. Nothing was installed.");
        }
        let _ = fs::remove_dir_all(&scratch);
        return 1;
    }

    // Verify
    let verify = Command::new("codesign")
        .args(["--verify", "--deep", "--strict", &installed_str])
        .status();
    if !verify.map(|s| s.success()).unwrap_or(false) {
        if had_old {
            if aside.exists() {
                let _ = fs::remove_dir_all(&installed);
                let _ = fs::rename(&aside, &installed);
            }
            eprintln!("install: The new app does not pass codesign --verify. The previous Courier is back in place.");
        } else {
            let _ = fs::remove_dir_all(&installed);
            eprintln!(
                "install: The new app does not pass codesign --verify. Nothing was installed."
            );
        }
        let _ = fs::remove_dir_all(&scratch);
        return 1;
    }

    let _ = fs::remove_dir_all(&aside);
    let _ = fs::remove_dir_all(&scratch);
    println!("Installed {}.", installed_str);
    0
}

// Placeholder for libc SIGTERM — use raw syscall on unix platforms
#[cfg(unix)]
mod libc {
    pub const SIGTERM: i32 = 15;
    extern "C" {
        pub fn kill(pid: i32, sig: i32) -> i32;
    }
}
