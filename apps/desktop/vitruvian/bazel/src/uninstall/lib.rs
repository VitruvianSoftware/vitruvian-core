// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `Tools/uninstall.sh`.
//! Cleanly removes Vitruvian and every piece of system state it created:
//! the fan helper daemon, login item, TCC permissions, preferences, saved state,
//! application data, closed-lid sudoers rules, and checks sleep/Space arrangement recovery.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

pub const DEFAULT_BUNDLE_ID: &str = "com.vitruviansoftware.vitruvian";
pub const DEFAULT_APP_PATH: &str = "/Applications/Vitruvian.app";
pub const CLOSED_LID_RULE_PATHS: &[&str] = &[
    "/etc/sudoers.d/vitruvian-clamshell",
    "/etc/sudoers.d/vitruvian-utils-clamshell",
    "/etc/sudoers.d/vitru-clamshell",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UninstallConfig {
    pub home_dir: PathBuf,
    pub bundle_id: String,
    pub app_path: PathBuf,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PostUninstallWarnings {
    pub fan_helper_still_registered: bool,
    pub sleep_stuck: bool,
    pub sleep_unknown: bool,
    pub spaces_stuck: bool,
    pub spaces_unloaded: bool,
    pub spaces_unknown: bool,
}

impl PostUninstallWarnings {
    pub fn is_clean(&self) -> bool {
        !self.fan_helper_still_registered
            && !self.sleep_stuck
            && !self.sleep_unknown
            && !self.spaces_stuck
            && !self.spaces_unloaded
            && !self.spaces_unknown
    }
}

pub fn parse_cli_args(args: &[String], home_dir: &Path) -> Result<UninstallConfig, String> {
    let mut dry_run = false;
    let mut bundle_id = DEFAULT_BUNDLE_ID.to_string();
    let mut app_path = PathBuf::from(DEFAULT_APP_PATH);

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--dry-run" => dry_run = true,
            "--bundle-id" => {
                i += 1;
                if i >= args.len() {
                    return Err("uninstall: --bundle-id requires a value".to_string());
                }
                bundle_id = args[i].clone();
            }
            "--app" => {
                i += 1;
                if i >= args.len() {
                    return Err("uninstall: --app requires a value".to_string());
                }
                app_path = PathBuf::from(&args[i]);
            }
            "-h" | "--help" => {
                return Err(
                    "usage: uninstall.sh [--dry-run] [--bundle-id <id>] [--app <path>]".to_string(),
                );
            }
            other => {
                return Err(format!("uninstall.sh: unknown argument '{}'", other));
            }
        }
        i += 1;
    }

    Ok(UninstallConfig {
        home_dir: home_dir.to_path_buf(),
        bundle_id,
        app_path,
        dry_run,
    })
}

pub fn user_state_paths(home: &Path, bundle: &str) -> Vec<PathBuf> {
    vec![
        home.join(format!("Library/Preferences/{}.plist", bundle)),
        home.join(format!(
            "Library/Saved Application State/{}.savedState",
            bundle
        )),
        home.join(format!("Library/Application Support/{}", bundle)),
        home.join(format!("Library/Caches/{}", bundle)),
        home.join(format!("Library/HTTPStorages/{}", bundle)),
        home.join(format!("Library/HTTPStorages/{}.binarycookies", bundle)),
    ]
}

pub fn remove_user_state(home: &Path, bundle: &str) {
    for path in user_state_paths(home, bundle) {
        if path.is_dir() {
            let _ = fs::remove_dir_all(&path);
        } else {
            let _ = fs::remove_file(&path);
        }
    }

    let by_host_dir = home.join("Library/Preferences/ByHost");
    let prefix = format!("{}.", bundle);
    if let Ok(entries) = fs::read_dir(&by_host_dir) {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.starts_with(&prefix) && name.ends_with(".plist") {
                    let _ = fs::remove_file(&p);
                }
            }
        }
    }
}

pub fn find_closed_lid_rules(root: &Path) -> Vec<String> {
    let mut found = Vec::new();
    for &rule in CLOSED_LID_RULE_PATHS {
        let rel = rule.strip_prefix('/').unwrap_or(rule);
        let candidate = if root.as_os_str().is_empty() || root == Path::new("/") {
            PathBuf::from(rule)
        } else {
            root.join(rel)
        };
        if candidate.exists() || candidate.symlink_metadata().is_ok() {
            found.push(rule.to_string());
        }
    }
    found
}

pub fn parse_sleep_disabled(pmset_output: &str) -> String {
    for line in pmset_output.lines() {
        let mut fields = line.split_whitespace();
        if let Some(first) = fields.next() {
            if first == "SleepDisabled" {
                if let Some(val) = fields.next() {
                    return val.to_string();
                }
            }
        }
    }
    String::new()
}

pub fn evaluate_sleep_warning(sleep_was_ours: bool, sleep_state: &str) -> (bool, bool) {
    if !sleep_was_ours {
        return (false, false);
    }
    if sleep_state == "1" {
        (true, false)
    } else if sleep_state != "0" {
        (false, true)
    } else {
        (false, false)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlistValue {
    String(String),
    Integer(String),
    Bool(bool),
    Data(String),
    Other,
}

pub fn is_valid_plist_xml(xml: &str) -> bool {
    let trimmed = xml.trim();
    trimmed.contains("<plist")
        && trimmed.ends_with("</plist>")
        && (trimmed.contains("<dict/>")
            || (trimmed.contains("<dict>") && trimmed.contains("</dict>")))
}

pub fn lookup_plist_key(xml: &str, key: &str) -> Result<Option<PlistValue>, ()> {
    if !is_valid_plist_xml(xml) {
        return Err(());
    }
    let needle = format!("<key>{}</key>", key);
    let Some(idx) = xml.find(&needle) else {
        return Ok(None);
    };
    let rest = xml[idx + needle.len()..].trim_start();
    if rest.starts_with("<true/>") {
        Ok(Some(PlistValue::Bool(true)))
    } else if rest.starts_with("<false/>") {
        Ok(Some(PlistValue::Bool(false)))
    } else if let Some(after) = rest.strip_prefix("<string>") {
        let end = after.find("</string>").ok_or(())?;
        Ok(Some(PlistValue::String(after[..end].to_string())))
    } else if rest.starts_with("<string/>") {
        Ok(Some(PlistValue::String(String::new())))
    } else if let Some(after) = rest.strip_prefix("<integer>") {
        let end = after.find("</integer>").ok_or(())?;
        Ok(Some(PlistValue::Integer(after[..end].trim().to_string())))
    } else if let Some(after) = rest.strip_prefix("<data>") {
        let end = after.find("</data>").ok_or(())?;
        Ok(Some(PlistValue::Data(after[..end].trim().to_string())))
    } else {
        Ok(Some(PlistValue::Other))
    }
}

pub fn spaces_recovery_value(snapshot: &str, key: &str) -> Result<String, ()> {
    match lookup_plist_key(snapshot, key)? {
        None => Ok(String::new()),
        Some(PlistValue::String(s)) if !s.is_empty() => Ok(s),
        _ => Err(()),
    }
}

pub fn spaces_leftover(owed: &str, journal: &str, preference: &str, dock_pid: &str) -> String {
    if (owed.is_empty() || owed == "off") && journal.is_empty() {
        return String::new();
    }
    match owed {
        "" | "absent" | "on" | "off" => {}
        _ => return "unknown".to_string(),
    }
    if preference == "unknown" || (!journal.is_empty() && dock_pid == "unknown") {
        return "unknown".to_string();
    }

    let mut journal_pid = "";
    let mut journal_runs = "";
    let mut journal_wrote: Vec<&str> = Vec::new();

    if !journal.is_empty() {
        let mut parts = journal.split_whitespace();
        journal_pid = parts.next().unwrap_or("");
        journal_runs = parts.next().unwrap_or("");
        journal_wrote = parts.collect();

        let pid_is_numeric =
            !journal_pid.is_empty() && journal_pid.bytes().all(|b| b.is_ascii_digit());
        let runs_valid = journal_runs == "fixed" || journal_runs == "rearranging";
        if !pid_is_numeric || !runs_valid || journal_wrote.is_empty() {
            return "unknown".to_string();
        }
        for &written in &journal_wrote {
            match written {
                "absent" | "on" | "off" => {}
                _ => return "unknown".to_string(),
            }
        }
    }

    let reads = match preference {
        "0" => "off",
        "1" => "on",
        "" => "absent",
        _ => return "unknown".to_string(),
    };

    if !owed.is_empty() && owed != "off" && preference == "0" {
        "stuck".to_string()
    } else if journal_runs == "fixed"
        && preference != "0"
        && !dock_pid.is_empty()
        && journal_pid == dock_pid
        && journal_wrote.contains(&reads)
    {
        "unloaded".to_string()
    } else {
        String::new()
    }
}

fn live_read_domain(domain: &str) -> Result<String, ()> {
    let out = Command::new("defaults")
        .args(["export", domain, "-"])
        .output()
        .map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    let xml = String::from_utf8_lossy(&out.stdout).to_string();
    if !is_valid_plist_xml(&xml) {
        return Err(());
    }
    Ok(xml)
}

fn live_dock_preference() -> String {
    let Ok(snapshot) = live_read_domain("com.apple.dock") else {
        return "unknown".to_string();
    };
    match lookup_plist_key(&snapshot, "mru-spaces") {
        Ok(None) => String::new(),
        Ok(Some(PlistValue::Bool(false))) => "0".to_string(),
        Ok(Some(PlistValue::Integer(ref s))) if s == "0" => "0".to_string(),
        Ok(Some(PlistValue::Bool(true))) => "1".to_string(),
        Ok(Some(PlistValue::Integer(ref s))) if s == "1" => "1".to_string(),
        _ => "unknown".to_string(),
    }
}

fn live_dock_pid() -> String {
    let out = Command::new("pgrep").args(["-x", "Dock"]).output();
    match out {
        Ok(o) if o.status.code() == Some(0) => {
            let s = String::from_utf8_lossy(&o.stdout);
            let first = s.lines().next().unwrap_or("").trim();
            if !first.is_empty() {
                first.to_string()
            } else {
                "unknown".to_string()
            }
        }
        Ok(o) if o.status.code() == Some(1) => String::new(),
        _ => "unknown".to_string(),
    }
}

fn live_spaces_removal_state(owed: &str, journal: &str) -> String {
    if (owed.is_empty() || owed == "off") && journal.is_empty() {
        return String::new();
    }
    spaces_leftover(owed, journal, &live_dock_preference(), &live_dock_pid())
}

pub fn run_cli(args: &[String]) -> i32 {
    let home = env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"));
    let cfg = match parse_cli_args(args, &home) {
        Ok(c) => c,
        Err(msg) => {
            if msg.starts_with("usage:") {
                println!("{}", msg);
                return 0;
            }
            eprintln!("{}", msg);
            return 2;
        }
    };

    if cfg.dry_run {
        println!("dry-run: pkill -x Vitruvian");
        for p in user_state_paths(&cfg.home_dir, &cfg.bundle_id) {
            println!("dry-run: remove {}", p.display());
        }
        return 0;
    }

    println!("▸ Quitting…");
    let _ = Command::new("pkill").args(["-x", "Vitruvian"]).output();
    thread::sleep(Duration::from_millis(500));

    let mut detached = true;
    let mut ran_app = false;
    let candidate = cfg.app_path.join("Contents/MacOS/Vitruvian");
    if candidate.is_file() {
        println!(
            "▸ Detaching the fan helper and login item, restoring sleep and Space rearranging…"
        );
        ran_app = true;
        if Command::new(&candidate)
            .arg("--uninstall")
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            detached = false;
        }
    }

    if detached {
        let code = Command::new("launchctl")
            .args(["print", &format!("system/{}.fan-control", cfg.bundle_id)])
            .output()
            .ok()
            .and_then(|o| o.status.code());
        if code == Some(113) {
            detached = false;
        }
    }

    let sleep_was_ours = Command::new("defaults")
        .args(["read", &cfg.bundle_id, "vitruDisabledSleep"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "1")
        .unwrap_or(false);

    let (spaces_owed, spaces_journal) = match live_read_domain(&cfg.bundle_id).and_then(|snap| {
        let owed = spaces_recovery_value(&snap, "spacesOrderRestore")?;
        let journal = spaces_recovery_value(&snap, "spacesOrderRestartPending")?;
        Ok((owed, journal))
    }) {
        Ok(pair) => pair,
        Err(()) => {
            eprintln!(
                "Could not read Space arrangement recovery. The app and its preferences were kept."
            );
            eprintln!("Try uninstalling again when the preferences can be read.");
            return 1;
        }
    };

    let spaces_before_removal = live_spaces_removal_state(&spaces_owed, &spaces_journal);
    if !spaces_before_removal.is_empty() && ran_app {
        match spaces_before_removal.as_str() {
            "stuck" => eprintln!("Space rearranging has not been restored."),
            "unloaded" => eprintln!("The Dock has not loaded the restored Space arrangement yet."),
            _ => eprintln!("Could not confirm that Space rearranging was restored."),
        }
        eprintln!("The app and its recovery preferences were kept. Try uninstalling again.");
        return 1;
    }

    println!("▸ Resetting permissions (Accessibility, Screen Recording)…");
    let _ = Command::new("tccutil")
        .args(["reset", "All", &cfg.bundle_id])
        .output();

    println!(
        "▸ Removing app, preferences, saved state and stored data (clipboard history, shelf files, share links)…"
    );
    let _ = fs::remove_dir_all(&cfg.app_path);
    let _ = Command::new("defaults")
        .args(["delete", &cfg.bundle_id])
        .output();
    remove_user_state(&cfg.home_dir, &cfg.bundle_id);

    let found_rules = find_closed_lid_rules(Path::new("/"));
    if !found_rules.is_empty() {
        println!("▸ Removing closed-lid sudoers rule (asks for your admin password)…");
        let joined = found_rules.join(" ");
        let script = format!(
            "do shell script \"rm -f {}\" with administrator privileges with prompt \"Vitruvian uninstaller\"",
            joined
        );
        let _ = Command::new("osascript").args(["-e", &script]).status();
    }

    let pmset_out = Command::new("pmset")
        .arg("-g")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    let sleep_state = parse_sleep_disabled(&pmset_out);
    let (sleep_stuck, sleep_unknown) = evaluate_sleep_warning(sleep_was_ours, &sleep_state);

    let after_state = live_spaces_removal_state(&spaces_owed, &spaces_journal);
    let warnings = PostUninstallWarnings {
        fan_helper_still_registered: detached,
        sleep_stuck,
        sleep_unknown,
        spaces_stuck: after_state == "stuck",
        spaces_unloaded: after_state == "unloaded",
        spaces_unknown: after_state == "unknown",
    };

    if warnings.is_clean() {
        println!("✓ Vitruvian fully removed.");
        return 0;
    }

    if warnings.fan_helper_still_registered {
        eprintln!("⚠ Vitruvian removed, but its fan helper is still registered with the system.");
        eprintln!(
            "  Reinstall Vitruvian, then use Settings › Advanced to uninstall from inside the app."
        );
    }
    if warnings.sleep_stuck {
        eprintln!("⚠ Vitruvian removed, but this Mac still has sleep switched off.");
        eprintln!("  Closed-lid mode disabled it, and restoring it needed a password this script could not ask for.");
        eprintln!("  Put it back with: sudo pmset disablesleep 0");
    }
    if warnings.sleep_unknown {
        eprintln!("⚠ Vitruvian removed, but whether sleep came back could not be read.");
        eprintln!(
            "  Closed-lid mode had switched it off. Check with: pmset -g | grep SleepDisabled"
        );
        eprintln!("  If that reads 1, put it back with: sudo pmset disablesleep 0");
    }
    if warnings.spaces_stuck {
        eprintln!("⚠ Vitruvian removed, but Spaces are still kept in a fixed order.");
        eprintln!("  Fixed Space order had turned rearranging off, and it was not put back.");
        eprintln!("  Turn it back on in System Settings › Desktop & Dock with");
        eprintln!("  \"Automatically rearrange Spaces based on most recent use\".");
    }
    if warnings.spaces_unloaded {
        eprintln!("⚠ Vitruvian removed, but the Dock still keeps Spaces in a fixed order.");
        eprintln!("  Space rearranging was put back on, and the Dock reads it when it restarts.");
        eprintln!("  Log out and back in to finish.");
    }
    if warnings.spaces_unknown {
        eprintln!(
            "Vitruvian removed, but whether Space rearranging was restored could not be confirmed."
        );
        eprintln!(
            "Check Automatically rearrange Spaces based on most recent use in System Settings."
        );
    }
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn test_remove_user_state_cleans_expected_files_and_keeps_other_bundles() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let scratch = env::temp_dir().join(format!(
            "vitruvian_uninstall_rs_test_{}_{}",
            std::process::id(),
            nanos
        ));
        let bundle = "com.vitruviansoftware.vitruvian";

        fs::create_dir_all(scratch.join("Library/Preferences/ByHost")).unwrap();
        fs::create_dir_all(scratch.join(format!(
            "Library/Saved Application State/{}.savedState",
            bundle
        )))
        .unwrap();
        fs::create_dir_all(scratch.join(format!("Library/Application Support/{}", bundle)))
            .unwrap();
        fs::create_dir_all(scratch.join(format!("Library/Caches/{}", bundle))).unwrap();
        fs::create_dir_all(scratch.join(format!("Library/HTTPStorages/{}", bundle))).unwrap();

        fs::write(
            scratch.join(format!("Library/Preferences/{}.plist", bundle)),
            "x",
        )
        .unwrap();
        fs::write(
            scratch.join(format!("Library/HTTPStorages/{}.binarycookies", bundle)),
            "x",
        )
        .unwrap();
        fs::write(
            scratch.join(format!(
                "Library/Preferences/ByHost/{}.1234-5678.plist",
                bundle
            )),
            "x",
        )
        .unwrap();
        let other_pref = scratch.join("Library/Preferences/com.other.app.plist");
        fs::write(&other_pref, "keep").unwrap();

        remove_user_state(&scratch, bundle);

        for p in user_state_paths(&scratch, bundle) {
            assert!(!p.exists(), "expected {} to be removed", p.display());
        }
        assert!(!scratch
            .join(format!(
                "Library/Preferences/ByHost/{}.1234-5678.plist",
                bundle
            ))
            .exists());
        assert!(other_pref.exists());

        let _ = fs::remove_dir_all(&scratch);
    }

    #[test]
    fn test_find_closed_lid_rules_in_scratch_root() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let scratch = env::temp_dir().join(format!(
            "vitruvian_sudoers_rs_test_{}_{}",
            std::process::id(),
            nanos
        ));
        let sudoers = scratch.join("etc/sudoers.d");
        fs::create_dir_all(&sudoers).unwrap();
        fs::write(sudoers.join("vitruvian-clamshell"), "rule1").unwrap();
        fs::write(sudoers.join("vitru-clamshell"), "rule2").unwrap();

        let found = find_closed_lid_rules(&scratch);
        assert_eq!(
            found,
            vec![
                "/etc/sudoers.d/vitruvian-clamshell".to_string(),
                "/etc/sudoers.d/vitru-clamshell".to_string(),
            ]
        );
        let _ = fs::remove_dir_all(&scratch);
    }

    #[test]
    fn test_parse_sleep_disabled_and_warnings() {
        let pmset = "System-wide power settings:\nCurrently in use:\n SleepDisabled\t\t1\n";
        assert_eq!(parse_sleep_disabled(pmset), "1");
        assert_eq!(evaluate_sleep_warning(true, "1"), (true, false));
        assert_eq!(evaluate_sleep_warning(true, "0"), (false, false));
        assert_eq!(evaluate_sleep_warning(true, ""), (false, true));
        assert_eq!(evaluate_sleep_warning(false, "1"), (false, false));
    }

    #[test]
    fn test_spaces_leftover_states() {
        assert_eq!(spaces_leftover("", "", "", "500"), "");
        assert_eq!(spaces_leftover("absent", "", "0", "500"), "stuck");
        assert_eq!(
            spaces_leftover("", "500 fixed absent", "", "500"),
            "unloaded"
        );
        assert_eq!(spaces_leftover("on", "", "unknown", "500"), "unknown");
    }
}
