// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Native Rust implementation of `discard_test_preferences` (from `build.sh`)
//! and the `Tests/PreferenceCleanupTests.sh` test suite.

use std::env;
use std::fs;
use std::path::Path;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const TEST_PREF_PREFIXES: &[&str] = &["vitru.tests.", "com.vitruviansoftware.vitruvian.tests."];
pub const METRICS_TESTS_PLIST: &str = "metrics-tests.plist";

pub fn is_test_preference_filename(name: &str) -> bool {
    if name == METRICS_TESTS_PLIST {
        return true;
    }
    if !name.ends_with(".plist") {
        return false;
    }
    TEST_PREF_PREFIXES
        .iter()
        .any(|prefix| name.starts_with(prefix))
}

pub fn remove_matching_test_preferences(preferences: &Path) {
    let Ok(entries) = fs::read_dir(preferences) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if is_test_preference_filename(name) {
                let _ = fs::remove_file(&path);
            }
        }
    }
}

pub fn count_surviving_test_preferences(preferences: &Path) -> usize {
    let Ok(entries) = fs::read_dir(preferences) else {
        return 0;
    };
    entries
        .flatten()
        .filter(|entry| {
            entry
                .path()
                .file_name()
                .and_then(|n| n.to_str())
                .map(is_test_preference_filename)
                .unwrap_or(false)
        })
        .count()
}

/// Native Rust equivalent of `discard_test_preferences` in `build.sh`.
/// Requires two consecutive quiet checks across up to 10 attempts, calling
/// `sleep_fn` after each pass (which sleeps 200ms in production or emulates
/// delayed `cfprefsd` writes in tests).
pub fn discard_test_preferences_with_sleep<F>(
    preferences: &Path,
    mut sleep_fn: F,
) -> Result<(), String>
where
    F: FnMut(&Path),
{
    let mut survivors = 0usize;
    let mut quiet_passes = 0usize;

    for _attempt in 1..=10 {
        remove_matching_test_preferences(preferences);
        sleep_fn(preferences);
        survivors = count_surviving_test_preferences(preferences);
        if survivors == 0 {
            quiet_passes += 1;
            if quiet_passes == 2 {
                return Ok(());
            }
        } else {
            quiet_passes = 0;
        }
    }

    Err(format!(
        "✗ test preferences did not settle in {} ({} remaining)",
        preferences.display(),
        survivors
    ))
}

pub fn discard_test_preferences(preferences: &Path) -> Result<(), String> {
    discard_test_preferences_with_sleep(preferences, |_| {
        thread::sleep(Duration::from_millis(200));
    })
}

/// Runs the full `Tests/PreferenceCleanupTests.sh` suite in an isolated temp directory.
pub fn run_preference_cleanup_test_suite() -> Result<(), String> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let cleanup_test_dir = env::temp_dir().join(format!(
        "vitruvian_pref_cleanup_test_{}_{}",
        std::process::id(),
        nanos
    ));
    fs::create_dir_all(&cleanup_test_dir)
        .map_err(|e| format!("failed to create temp dir: {}", e))?;

    let result = (|| -> Result<(), String> {
        let mut remaining_writes: usize = 2;
        fs::write(cleanup_test_dir.join("vitru.tests.first.plist"), "{}\n")
            .map_err(|e| e.to_string())?;
        fs::write(cleanup_test_dir.join("metrics-tests.plist"), "{}\n")
            .map_err(|e| e.to_string())?;
        fs::write(cleanup_test_dir.join("unrelated.plist"), "preserve\n")
            .map_err(|e| e.to_string())?;

        discard_test_preferences_with_sleep(&cleanup_test_dir, |dir| {
            if remaining_writes > 0 {
                let _ = fs::write(
                    dir.join("com.vitruviansoftware.vitruvian.tests.delayed.plist"),
                    "{}\n",
                );
                remaining_writes -= 1;
            }
        })?;

        if cleanup_test_dir
            .join("com.vitruviansoftware.vitruvian.tests.delayed.plist")
            .exists()
        {
            return Err("delayed test plist still exists".into());
        }
        if cleanup_test_dir.join("vitru.tests.first.plist").exists() {
            return Err("vitru.tests.first.plist still exists".into());
        }
        if cleanup_test_dir.join("metrics-tests.plist").exists() {
            return Err("metrics-tests.plist still exists".into());
        }
        let unrelated = fs::read_to_string(cleanup_test_dir.join("unrelated.plist"))
            .map_err(|e| e.to_string())?;
        if unrelated.trim() != "preserve" {
            return Err(format!("unrelated.plist was modified: {:?}", unrelated));
        }

        // A writer that never settles must still fail rather than hiding the problem.
        remaining_writes = 100;
        let persistent_res = discard_test_preferences_with_sleep(&cleanup_test_dir, |dir| {
            if remaining_writes > 0 {
                let _ = fs::write(
                    dir.join("com.vitruviansoftware.vitruvian.tests.delayed.plist"),
                    "{}\n",
                );
                remaining_writes -= 1;
            }
        });
        if persistent_res.is_ok() {
            return Err("preference cleanup accepted a persistent writer".into());
        }
        if remaining_writes != 90 {
            return Err(format!(
                "expected remaining_writes == 90 after 10 attempts, got {}",
                remaining_writes
            ));
        }

        remaining_writes = 0;
        discard_test_preferences_with_sleep(&cleanup_test_dir, |dir| {
            if remaining_writes > 0 {
                let _ = fs::write(
                    dir.join("com.vitruviansoftware.vitruvian.tests.delayed.plist"),
                    "{}\n",
                );
                remaining_writes -= 1;
            }
        })?;

        Ok(())
    })();

    let _ = fs::remove_dir_all(&cleanup_test_dir);
    result
}

pub fn run_cli(_args: &[String]) -> i32 {
    match run_preference_cleanup_test_suite() {
        Ok(()) => {
            println!("PREFERENCE CLEANUP TESTS OK");
            0
        }
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preference_cleanup_suite() {
        run_preference_cleanup_test_suite().unwrap();
    }

    #[test]
    fn test_filename_matching() {
        assert!(is_test_preference_filename("vitru.tests.first.plist"));
        assert!(is_test_preference_filename(
            "com.vitruviansoftware.vitruvian.tests.delayed.plist"
        ));
        assert!(is_test_preference_filename("metrics-tests.plist"));
        assert!(!is_test_preference_filename("unrelated.plist"));
        assert!(!is_test_preference_filename(
            "com.vitruviansoftware.vitruvian.plist"
        ));
    }
}
