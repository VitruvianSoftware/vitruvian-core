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

//! Verifies that the paths, launchd label, and HTTP endpoint written by
//! `macagent_scripts_lib` stay in lockstep with
//! `Sources/RemoteMenuCore/AgentStatus.swift`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub fn expected_swift_needles() -> Vec<(&'static str, String)> {
    vec![
        ("label", format!("\"{}\"", macagent_scripts_lib::LABEL)),
        (
            "binary",
            format!("\"{}\"", macagent_scripts_lib::BIN_REL_PATH),
        ),
        (
            "binary name",
            format!("{}\"", macagent_scripts_lib::BIN_NAME),
        ),
        ("log", format!("\"{}\"", macagent_scripts_lib::LOG_REL_PATH)),
        ("log dir", format!("{}/", macagent_scripts_lib::LOG_REL_DIR)),
        ("port", format!("\"{}\"", macagent_scripts_lib::BASE_URL)),
    ]
}

pub fn verify_paths_match(swift_text: &str) -> Vec<String> {
    let mut errors = Vec::new();
    for (name, swift_needle) in expected_swift_needles() {
        if !swift_text.contains(&swift_needle) {
            errors.push(format!(
                "AgentStatus.swift no longer contains: {swift_needle} ({name})"
            ));
        }
    }
    errors
}

fn find_runfile(rel: &str) -> PathBuf {
    let direct = PathBuf::from(rel);
    if direct.is_file() {
        return direct;
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(base) = env::var(var) {
            let candidate = Path::new(&base).join("_main").join(rel);
            if candidate.is_file() {
                return candidate;
            }
        }
    }
    direct
}

#[test]
fn live_installer_and_swift_paths_match() {
    let swift_path =
        find_runfile("apps/mobile/android-remote/macmenu/Sources/RemoteMenuCore/AgentStatus.swift");
    let swift_text = fs::read_to_string(&swift_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", swift_path.display()));

    let errors = verify_paths_match(&swift_text);
    assert!(
        errors.is_empty(),
        "path mismatch between macagent_scripts_lib and AgentStatus.swift:\n{}",
        errors.join("\n")
    );
}

#[test]
fn rust_macagent_installer_lib_matches_swift_paths() {
    let paths = macagent_scripts_lib::InstallerPaths::for_home(Path::new("/Users/tester"));
    assert_eq!(
        paths.bin,
        PathBuf::from(format!(
            "/Users/tester/{}",
            macagent_scripts_lib::BIN_REL_PATH
        ))
    );
    assert_eq!(
        paths.log,
        PathBuf::from(format!(
            "/Users/tester/{}",
            macagent_scripts_lib::LOG_REL_PATH
        ))
    );
    assert_eq!(
        paths.plist,
        PathBuf::from(format!(
            "/Users/tester/{}/{}.plist",
            macagent_scripts_lib::PLIST_REL_DIR,
            macagent_scripts_lib::LABEL
        ))
    );
}

#[test]
fn detects_drift_when_installer_or_swift_changes() {
    let errors = verify_paths_match("let x = 1");
    assert_eq!(errors.len(), expected_swift_needles().len());
}
