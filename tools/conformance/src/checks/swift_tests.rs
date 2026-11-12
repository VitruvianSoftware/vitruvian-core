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

//! Swift tests keep out of ~/Library/Preferences (2026-11-02: some 56,000
//! leftover test suites there had stopped macOS saving any app's settings).
//!
//! - Every Bazel `swift_test` comes from //tools/swift-test-preferences:defs.bzl,
//!   which keeps the test's UserDefaults in a container under TEST_TMPDIR. A
//!   BUILD or .bzl file that loads rules_swift's `swift_test` directly fails.
//! - A Swift test opens a suite only through its folder's `ScratchDefaults.swift`;
//!   `UserDefaults(suiteName:)` anywhere else in test code fails, and so does
//!   writing preferences with CFPreferences, which no container covers.
//! - Every copy of `ScratchDefaults.swift` is the same below its licence lines.

use std::fs;

use crate::Context;

const GROUP: &str = "SWIFTPREFS";
const UPSTREAM_SWIFT_TEST: &str = "@build_bazel_rules_swift//swift:swift_test.bzl";
const MACRO: &str = "tools/swift-test-preferences/defs.bzl";
/// The redirect's own proof test opens raw suites on purpose.
const REDIRECT_PACKAGE: &str = "tools/swift-test-preferences/";
const HELPER: &str = "ScratchDefaults.swift";
/// Where a copy of the helper starts, after its licence lines.
const HELPER_BODY_START: &str = "// The one way tests here open a UserDefaults suite.";
/// Copies of BUILD files and plans kept as text, not built.
const NOT_BUILT: &[&str] = &["docs/", "tools/pipeline/unitfile/testdata/"];

pub fn check_test_preferences(ctx: &Context) {
    let mut failed = false;

    let mut build_files = ctx.files.discover(&ctx.root, "BUILD");
    build_files.extend(ctx.files.discover(&ctx.root, "BUILD.bazel"));
    build_files.extend(ctx.files.discover(&ctx.root, "*.bzl"));
    build_files.sort();
    for path in &build_files {
        let rel = ctx.rel(path);
        if rel == MACRO || NOT_BUILT.iter().any(|p| rel.starts_with(p)) {
            continue;
        }
        let Ok(text) = fs::read_to_string(path) else {
            continue;
        };
        if text.contains(UPSTREAM_SWIFT_TEST) {
            failed = true;
            ctx.emit_fail(
                GROUP,
                &rel,
                "rules_swift swift_test",
                "//tools/swift-test-preferences:defs.bzl",
                "a Swift test loaded straight from rules_swift saves its preferences in ~/Library/Preferences",
                "load(\"//tools/swift-test-preferences:defs.bzl\", \"swift_test\")",
            );
        }
    }

    let mut helpers: Vec<(String, String)> = Vec::new();
    for path in ctx.files.discover(&ctx.root, "*.swift") {
        let rel = ctx.rel(&path);
        if NOT_BUILT.iter().any(|p| rel.starts_with(p)) || rel.starts_with(REDIRECT_PACKAGE) {
            continue;
        }
        let file_name = rel.rsplit('/').next().unwrap_or(&rel);
        let is_test = rel.starts_with("Tests/") || rel.contains("/Tests/");
        if !is_test {
            continue;
        }
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        if file_name == HELPER {
            helpers.push((rel, text));
            continue;
        }
        for (number, line) in code_lines(&text) {
            let found = if opens_suite(line) {
                "UserDefaults(suiteName:)"
            } else if line.contains("CFPreferencesSetAppValue")
                || line.contains("CFPreferencesSetValue")
                || line.contains("CFPreferencesSetMultiple")
            {
                "CFPreferencesSet…"
            } else {
                continue;
            };
            failed = true;
            ctx.emit_fail(
                GROUP,
                &format!("{rel}:{number}"),
                found,
                "ScratchDefaults.suite(named:)",
                "a test's own suite would land in ~/Library/Preferences when run outside Bazel",
                "open it with ScratchDefaults.suite(named:) from the folder's ScratchDefaults.swift",
            );
        }
    }

    let bodies: Vec<(String, Option<&str>)> = helpers
        .iter()
        .map(|(rel, text)| {
            (
                rel.clone(),
                text.find(HELPER_BODY_START).map(|at| &text[at..]),
            )
        })
        .collect();
    let reference = bodies.iter().find_map(|(_, body)| *body);
    for (rel, body) in &bodies {
        if body.is_none() || *body != reference {
            failed = true;
            ctx.emit_fail(
                GROUP,
                rel,
                "a different ScratchDefaults.swift",
                "the same as every other copy",
                "the copies of the helper have drifted apart",
                "copy one of the others, keeping only this folder's licence lines",
            );
        }
    }

    if !failed {
        ctx.emit_ok(
            GROUP,
            "Swift tests",
            &format!(
                "{} BUILD files, {} ScratchDefaults.swift",
                build_files.len(),
                helpers.len()
            ),
            "preferences stay under TEST_TMPDIR",
            "",
        );
    }
}

/// Lines that are code, numbered from 1: comment lines and the insides of
/// block comments are left out, so prose that names the call does not count.
fn code_lines(text: &str) -> Vec<(usize, &str)> {
    let mut in_block = false;
    let mut lines = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let trimmed = line.trim_start();
        if in_block {
            in_block = !trimmed.contains("*/");
            continue;
        }
        if trimmed.starts_with("/*") {
            in_block = !trimmed.contains("*/");
            continue;
        }
        if trimmed.starts_with("//") {
            continue;
        }
        lines.push((index + 1, line));
    }
    lines
}

/// Whether a line calls `UserDefaults(suiteName:` or `UserDefaults.init(suiteName:`,
/// spaces allowed between the parts.
fn opens_suite(line: &str) -> bool {
    let mut rest = line;
    while let Some(at) = rest.find("UserDefaults") {
        let mut after = rest[at + "UserDefaults".len()..].trim_start();
        if let Some(stripped) = after.strip_prefix(".init") {
            after = stripped.trim_start();
        }
        if let Some(stripped) = after.strip_prefix('(') {
            if let Some(stripped) = stripped.trim_start().strip_prefix("suiteName") {
                if stripped.trim_start().starts_with(':') {
                    return true;
                }
            }
        }
        rest = &rest[at + "UserDefaults".len()..];
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo(files: &[(&str, &str)]) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static N: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!(
            "conformance-swiftprefs-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        for (rel, body) in files {
            let p = dir.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, body).unwrap();
        }
        dir
    }

    fn run(files: &[(&str, &str)]) -> (u32, u32, String) {
        let dir = repo(files);
        let ctx = Context::for_root(dir.to_str().unwrap());
        check_test_preferences(&ctx);
        let out = (
            ctx.ok_count.get(),
            ctx.fail_count.get(),
            ctx.rows.get(GROUP),
        );
        let _ = fs::remove_dir_all(&dir);
        out
    }

    const MACRO_LOAD: &str = "load(\"//tools/swift-test-preferences:defs.bzl\", \"swift_test\")\n";
    const HELPER_A: &str = "// Copyright A\n\n// The one way tests here open a UserDefaults suite.\nenum ScratchDefaults {\n    // UserDefaults(suiteName: name)\n}\n";
    const HELPER_B: &str = "// SPDX B\n// Copyright B\n\n// The one way tests here open a UserDefaults suite.\nenum ScratchDefaults {\n    // UserDefaults(suiteName: name)\n}\n";

    #[test]
    fn the_repository_as_it_should_be_passes() {
        let (ok, fail, rows) = run(&[
            ("apps/a/BUILD", MACRO_LOAD),
            ("tools/swift-test-preferences/defs.bzl", "load(\"@build_bazel_rules_swift//swift:swift_test.bzl\", _t = \"swift_test\")\n"),
            ("tools/swift-test-preferences/Tests/T.swift", "let d = UserDefaults(suiteName: \"probe\")\n"),
            ("docs/plan.md", "load(\"@build_bazel_rules_swift//swift:swift_test.bzl\", \"swift_test\")\n"),
            ("apps/a/Tests/ATests/ScratchDefaults.swift", HELPER_A),
            ("apps/b/Tests/ScratchDefaults.swift", HELPER_B),
            ("apps/a/Tests/ATests/ModelTests.swift", "/// Not UserDefaults(suiteName: x) itself.\nlet d = ScratchDefaults.suite(named: \"x\")!\n"),
            // App code reading the system's domains is not a test's suite.
            ("apps/a/Sources/Dock.swift", "let dock = UserDefaults(suiteName: \"com.apple.dock\")\n"),
        ]);
        assert_eq!((ok, fail), (1, 0), "{rows}");
    }

    /// The old code: a BUILD loading rules_swift's swift_test, and tests
    /// opening their own suites.
    #[test]
    fn a_raw_swift_test_or_suite_fails() {
        let (_, fail, rows) = run(&[
            ("apps/a/BUILD", "load(\"@build_bazel_rules_swift//swift:swift_test.bzl\", \"swift_test\")\n"),
            ("apps/a/Tests/ATests/ModelTests.swift", "import Foundation\n\nlet d = UserDefaults(suiteName: \"vitruvian-courier-tests-\\(UUID())\")!\n"),
            ("apps/a/Tests/ATests/More.swift", "let d = UserDefaults.init( suiteName : name)\n"),
            ("apps/b/Tests/Prefs.swift", "CFPreferencesSetAppValue(key, value, domain)\n"),
        ]);
        assert_eq!(fail, 4, "{rows}");
        assert!(rows.contains("apps/a/BUILD"), "{rows}");
        assert!(
            rows.contains("apps/a/Tests/ATests/ModelTests.swift:3"),
            "{rows}"
        );
        assert!(rows.contains("apps/a/Tests/ATests/More.swift:1"), "{rows}");
        assert!(rows.contains("apps/b/Tests/Prefs.swift:1"), "{rows}");
    }

    #[test]
    fn helpers_that_drift_apart_fail() {
        let drifted = HELPER_B.replace("enum", "struct");
        let (_, fail, rows) = run(&[
            ("apps/a/Tests/ScratchDefaults.swift", HELPER_A),
            ("apps/b/Tests/ScratchDefaults.swift", &drifted),
        ]);
        assert_eq!(fail, 1, "{rows}");
        assert!(
            rows.contains("apps/b/Tests/ScratchDefaults.swift"),
            "{rows}"
        );
    }

    #[test]
    fn opens_suite_matches_only_the_call() {
        assert!(opens_suite("let d = UserDefaults(suiteName: name)"));
        assert!(opens_suite("x(UserDefaults.init(suiteName:\"a\"))"));
        assert!(!opens_suite("let d = ScratchDefaults.suite(named: name)"));
        assert!(!opens_suite(
            "let d = LockWatchingDefaults(suiteName: name)"
        ));
        assert!(!opens_suite("let s = \"UserDefaults(suiteName\" + \": \""));
    }
}
