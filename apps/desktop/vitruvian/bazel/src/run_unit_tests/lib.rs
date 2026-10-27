// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Bazel test wrapper for the unit tests, which Swift Testing runs
//! (`Tests/SwiftTesting/UnitTests.swift`):
//!   1. run the binary from the app root, because the tests open repository
//!      files (sources, `Resources/`, `build.sh`) by app-relative paths;
//!   2. on a full run, run `preference_cleanup_tests` and
//!      `uninstall_spaces_tests`;
//!   3. always sweep the throwaway `UserDefaults` suites the tests created;
//!   4. fail unless every suite asked for reported its result;
//!   5. end the log with `TESTS OK` or `TESTS FAILED`, which `mutation_checks`
//!      reads.

use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub test_binary: PathBuf,
    pub app_dir: PathBuf,
    pub selection: String,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    if args.len() < 2 {
        return Err("usage: run_unit_tests <test binary> <app dir> [--suite=<name>...]".into());
    }
    let test_binary = PathBuf::from(&args[0]);
    let app_dir = PathBuf::from(&args[1]);
    let mut suites = Vec::new();
    for argument in &args[2..] {
        if let Some(suite) = argument.strip_prefix("--suite=") {
            if !suite.is_empty() {
                suites.push(suite.to_string());
                continue;
            }
        }
        return Err(format!("Unknown test selection: {}", argument));
    }
    Ok(Config {
        test_binary,
        app_dir,
        selection: suites.join(","),
    })
}

pub fn count_expected_suites_in_test_groups(test_groups_source: &str) -> usize {
    let mut in_names = false;
    let mut count = 0;
    for line in test_groups_source.lines() {
        if !in_names {
            if line.contains("static let names = [") {
                in_names = true;
            }
            continue;
        }
        if line.contains(']') {
            break;
        }
        if line.contains('"') {
            count += 1;
        }
    }
    count
}

pub fn count_expected_suites(selection: &str, test_groups_source: &str) -> usize {
    if !selection.is_empty() {
        selection.split(',').filter(|s| !s.is_empty()).count()
    } else {
        count_expected_suites_in_test_groups(test_groups_source)
    }
}

/// Matches `^[[:alnum:]-]+: (OK|FAILED) \([0-9]+ checks`.
pub fn is_suite_report_line(line: &str) -> bool {
    let Some((suite, rest)) = line.split_once(": ") else {
        return false;
    };
    if suite.is_empty()
        || !suite
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-')
    {
        return false;
    }
    let after_status = rest
        .strip_prefix("OK (")
        .or_else(|| rest.strip_prefix("FAILED ("));
    let Some(after_status) = after_status else {
        return false;
    };
    let digits_len = after_status
        .bytes()
        .take_while(|b| b.is_ascii_digit())
        .count();
    if digits_len == 0 {
        return false;
    }
    after_status[digits_len..].starts_with(" checks")
}

pub fn count_reported_suites(log_output: &str) -> usize {
    log_output
        .lines()
        .filter(|line| is_suite_report_line(line))
        .count()
}

fn resolve_real_home() -> PathBuf {
    if let Ok(out) = Command::new("/bin/sh")
        .arg("-c")
        .arg("eval echo \"~$(/usr/bin/id -un)\"")
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() && !s.starts_with('~') {
                return PathBuf::from(s);
            }
        }
    }
    env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

fn resolve_swift_backtrace_env() -> Option<String> {
    let out = Command::new("xcrun")
        .args(["--find", "swift"])
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let swift_path = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if swift_path.is_empty() {
        return None;
    }
    let swift_dir = Path::new(&swift_path).parent()?;
    let backtracer = swift_dir.join("../libexec/swift/macosx/swift-backtrace");
    let meta = fs::metadata(&backtracer).ok()?;
    if !meta.is_file() {
        return None;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if (meta.permissions().mode() & 0o111) == 0 {
            return None;
        }
    }
    Some(format!(
        "enable=yes,interactive=no,swift-backtrace={}",
        backtracer.display()
    ))
}

fn newest_crash_report(diag_dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(diag_dir).ok()?;
    let mut reports: Vec<(std::time::SystemTime, PathBuf)> = entries
        .flatten()
        .filter_map(|e| {
            let path = e.path();
            let name = path.file_name()?.to_str()?;
            if !name.starts_with("metrics-tests") {
                return None;
            }
            let mtime = e.metadata().ok()?.modified().ok()?;
            Some((mtime, path))
        })
        .collect();
    reports.sort_by(|a, b| b.0.cmp(&a.0));
    reports.into_iter().map(|(_, p)| p).next()
}

fn run_and_tee(cmd: &mut Command, log_path: &Path) -> Result<i32, String> {
    let log_file =
        File::create(log_path).map_err(|e| format!("create {}: {}", log_path.display(), e))?;
    let writer = Arc::new(Mutex::new(log_file));

    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd
        .spawn()
        .map_err(|e| format!("spawn test binary: {}", e))?;

    let child_out = child.stdout.take();
    let child_err = child.stderr.take();

    let w_out = Arc::clone(&writer);
    let t_out = thread::spawn(move || {
        if let Some(mut out) = child_out {
            let mut buf = [0u8; 4096];
            while let Ok(n) = out.read(&mut buf) {
                if n == 0 {
                    break;
                }
                let _ = io::stdout().write_all(&buf[..n]);
                let _ = io::stdout().flush();
                if let Ok(mut f) = w_out.lock() {
                    let _ = f.write_all(&buf[..n]);
                }
            }
        }
    });

    let w_err = Arc::clone(&writer);
    let t_err = thread::spawn(move || {
        if let Some(mut err) = child_err {
            let mut buf = [0u8; 4096];
            while let Ok(n) = err.read(&mut buf) {
                if n == 0 {
                    break;
                }
                let _ = io::stdout().write_all(&buf[..n]);
                let _ = io::stdout().flush();
                if let Ok(mut f) = w_err.lock() {
                    let _ = f.write_all(&buf[..n]);
                }
            }
        }
    });

    let status = child.wait().map_err(|e| format!("wait: {}", e))?;
    let _ = t_out.join();
    let _ = t_err.join();

    if let Some(code) = status.code() {
        Ok(code)
    } else {
        #[cfg(unix)]
        {
            use std::os::unix::process::ExitStatusExt;
            if let Some(sig) = status.signal() {
                return Ok(128 + sig);
            }
        }
        Ok(1)
    }
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };

    let pwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let test_tmpdir = env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::temp_dir());
    let bin_dir = test_tmpdir.join("bin");
    if let Err(e) = fs::create_dir_all(&bin_dir) {
        eprintln!("failed to create {}: {}", bin_dir.display(), e);
        return 1;
    }
    let binary = bin_dir.join("metrics-tests");
    let src_binary = if config.test_binary.is_absolute() {
        config.test_binary.clone()
    } else {
        pwd.join(&config.test_binary)
    };
    if let Err(e) = fs::copy(&src_binary, &binary) {
        eprintln!(
            "failed to copy {} to {}: {}",
            src_binary.display(),
            binary.display(),
            e
        );
        return 1;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(&binary) {
            let mut perms = meta.permissions();
            perms.set_mode(perms.mode() | 0o755);
            let _ = fs::set_permissions(&binary, perms);
        }
    }

    let real_home = resolve_real_home();

    if let Err(e) = env::set_current_dir(&config.app_dir) {
        eprintln!("failed to cd to {}: {}", config.app_dir.display(), e);
        return 1;
    }

    let test_groups_src = fs::read_to_string("Tests/TestGroups.swift").unwrap_or_default();
    let expected = count_expected_suites(&config.selection, &test_groups_src);
    let output_log = test_tmpdir.join("unit-tests.log");

    let mut cmd = Command::new(&binary);
    cmd.env("VITRUVIAN_TEST_SUITES", &config.selection);
    if let Some(bt) = resolve_swift_backtrace_env() {
        cmd.env("SWIFT_BACKTRACE", bt);
    }

    let mut status = match run_and_tee(&mut cmd, &output_log) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    };

    if status != 0 {
        if status > 128 {
            println!("the test binary was killed by signal {}", status - 128);
        } else {
            println!("the test binary exited with status {}", status);
        }
        let diag_dir = real_home.join("Library/Logs/DiagnosticReports");
        if let Some(report) = newest_crash_report(&diag_dir) {
            println!("crash report: {}", report.display());
            if let Ok(mut f) = File::open(&report) {
                let mut buf = vec![0u8; 16000];
                if let Ok(n) = f.read(&mut buf) {
                    let _ = io::stdout().write_all(&buf[..n]);
                }
            }
            println!();
        }
    }

    let log_text = fs::read_to_string(&output_log).unwrap_or_default();
    let reported = count_reported_suites(&log_text);
    if reported != expected {
        println!("{} of {} suites reported a result", reported, expected);
        status = 1;
    }
    if status == 0 {
        println!("TESTS OK ({} suites)", reported);
    } else {
        println!("TESTS FAILED: the failed checks are listed under their suites above");
    }

    if config.selection.is_empty() {
        if preference_cleanup_tests::run_cli(&[]) != 0 {
            status = 1;
        }
        if uninstall_spaces_tests::run_cli(&[]) != 0 {
            status = 1;
        }
    }

    let prefs_dir = real_home.join("Library/Preferences");
    if let Err(e) = preference_cleanup_tests::discard_test_preferences(&prefs_dir) {
        eprintln!("{}", e);
        status = 1;
    }

    status
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_args() {
        let cfg = parse_args(&[
            "bin/test".to_string(),
            "apps/desktop/vitruvian".to_string(),
            "--suite=notch".to_string(),
            "--suite=mixer".to_string(),
        ])
        .unwrap();
        assert_eq!(cfg.selection, "notch,mixer");

        assert!(parse_args(&[
            "bin/test".to_string(),
            "apps/desktop/vitruvian".to_string(),
            "--unknown".to_string()
        ])
        .is_err());
        assert!(parse_args(&[
            "bin/test".to_string(),
            "apps/desktop/vitruvian".to_string(),
            "--suite=".to_string()
        ])
        .is_err());
    }

    #[test]
    fn test_count_expected_and_reported_suites() {
        let sample_groups = "\
enum TestGroups {
    nonisolated static let names = [
        \"harness\",
        \"metrics\",
        \"notch\",
    ]
}
";
        assert_eq!(count_expected_suites("", sample_groups), 3);
        assert_eq!(count_expected_suites("notch,metrics", sample_groups), 2);

        let log = "\
Running tests...
harness: OK (12 checks)
metrics: FAILED (4 checks)
unrelated: line
notch: OK (99 checks in 0.1s)
";
        assert_eq!(count_reported_suites(log), 3);
    }
}
