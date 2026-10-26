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

//! Rust port of `apps/mobile/android-remote/macmenu/paths_match_installer_test.sh`.
//!
//! Verifies that the paths, launchd label, and HTTP endpoint written by both
//! `macagent/install.sh` and `macagent_scripts_lib` stay in lockstep with
//! `Sources/RemoteMenuCore/AgentStatus.swift`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const CHECKS: &[(&str, &str, &str)] = &[
    (
        "label",
        "LABEL=\"com.vitruvian.remote-agent\"",
        "\"com.vitruvian.remote-agent\"",
    ),
    (
        "binary",
        "BIN_DIR=\"${HOME}/.local/bin\"",
        "\".local/bin/vitruvian-remote-agent\"",
    ),
    (
        "binary name",
        "BIN=\"${BIN_DIR}/vitruvian-remote-agent\"",
        "vitruvian-remote-agent\"",
    ),
    (
        "log",
        "LOG=\"${LOG_DIR}/vitruvian-remote-agent.log\"",
        "\"Library/Logs/vitruvian-remote-agent.log\"",
    ),
    (
        "log dir",
        "LOG_DIR=\"${HOME}/Library/Logs\"",
        "Library/Logs/",
    ),
    ("port", "http://127.0.0.1:7411", "\"http://127.0.0.1:7411\""),
];

pub fn verify_paths_match(installer_text: &str, swift_text: &str) -> Vec<String> {
    let mut errors = Vec::new();
    for (name, installer_needle, swift_needle) in CHECKS {
        if !installer_text.contains(installer_needle) {
            errors.push(format!(
                "install.sh no longer contains: {installer_needle} ({name})"
            ));
        }
        if !swift_text.contains(swift_needle) {
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
    let installer_path = find_runfile("apps/mobile/android-remote/macagent/install.sh");
    let swift_path =
        find_runfile("apps/mobile/android-remote/macmenu/Sources/RemoteMenuCore/AgentStatus.swift");

    let installer_text = fs::read_to_string(&installer_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", installer_path.display()));
    let swift_text = fs::read_to_string(&swift_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", swift_path.display()));

    let errors = verify_paths_match(&installer_text, &swift_text);
    assert!(
        errors.is_empty(),
        "path mismatch between install.sh and AgentStatus.swift:\n{}",
        errors.join("\n")
    );
}

#[test]
fn rust_macagent_installer_lib_matches_swift_paths() {
    let swift_path =
        find_runfile("apps/mobile/android-remote/macmenu/Sources/RemoteMenuCore/AgentStatus.swift");
    let swift_text = fs::read_to_string(&swift_path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", swift_path.display()));

    assert!(swift_text.contains(&format!("\"{}\"", macagent_scripts_lib::LABEL)));
    assert!(swift_text.contains(&format!("\"{}\"", macagent_scripts_lib::BIN_REL_PATH)));
    assert!(swift_text.contains(&format!("\"{}\"", macagent_scripts_lib::LOG_REL_PATH)));
    assert!(swift_text.contains(&format!("\"{}\"", macagent_scripts_lib::BASE_URL)));
}

#[test]
fn detects_drift_when_installer_or_swift_changes() {
    let errors = verify_paths_match("LABEL=\"wrong\"", "let x = 1");
    assert_eq!(errors.len(), CHECKS.len() * 2);
}
