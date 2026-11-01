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

//! Every workflow that captures a secret from //tools/ci:gcp_secret_or_fail
//! must mask it with `::add-mask::` right after. A value fetched at runtime is
//! not a GitHub secret, so the runner does not redact it on its own: the
//! migrate step's DATABASE_URL went unmasked this way.

use std::path::PathBuf;

/// How many lines after the capture the mask may appear (the capture's own
/// continuation lines included).
const WINDOW: usize = 8;

/// `NAME="$(... gcp_secret_or_fail ...` -> NAME.
fn captured_var(line: &str) -> Option<&str> {
    if !line.contains("gcp_secret_or_fail") {
        return None;
    }
    let (lhs, _) = line.split_once("=\"$(")?;
    let name = lhs.trim().trim_start_matches("export ").trim();
    name.chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_')
        .then_some(name)
        .filter(|n| !n.is_empty())
}

/// Every unmasked capture in `text`, as "line N: NAME".
fn unmasked(text: &str) -> Vec<String> {
    let lines: Vec<&str> = text.lines().collect();
    let mut bad = Vec::new();
    for (i, line) in lines.iter().enumerate() {
        if let Some(name) = captured_var(line) {
            let masks = [
                format!("::add-mask::${name}"),
                format!("::add-mask::${{{name}}}"),
            ];
            let end = (i + 1 + WINDOW).min(lines.len());
            if !lines[i + 1..end]
                .iter()
                .any(|l| masks.iter().any(|m| l.contains(m.as_str())))
            {
                bad.push(format!("line {}: {name}", i + 1));
            }
        }
    }
    bad
}

#[test]
fn every_runtime_secret_capture_is_masked() {
    let files = std::env::var("WORKFLOW_FILES").expect("WORKFLOW_FILES");
    let mut captures = 0;
    let mut problems = Vec::new();
    for f in files.split_whitespace() {
        let text = std::fs::read_to_string(PathBuf::from(f)).unwrap();
        captures += text.lines().filter(|l| captured_var(l).is_some()).count();
        for p in unmasked(&text) {
            problems.push(format!("{f} {p}"));
        }
    }
    // Guards the guard: if the call shape changes, this must not go quietly green.
    assert!(
        captures >= 3,
        "found only {captures} gcp_secret_or_fail captures; did the call shape change?"
    );
    assert!(
        problems.is_empty(),
        "secret captured from gcp_secret_or_fail but never masked with ::add-mask:: within {WINDOW} lines:\n  {}",
        problems.join("\n  ")
    );
}

#[test]
fn detector_flags_an_unmasked_capture_and_accepts_a_masked_one() {
    let bad = "X=\"$(\"$PWD/bazel-bin/tools/ci/gcp_secret_or_fail\" \\\n  A b c)\"\nexport X\n";
    assert_eq!(unmasked(bad), vec!["line 1: X".to_string()]);
    let good = "X=\"$(\"$PWD/bazel-bin/tools/ci/gcp_secret_or_fail\" \\\n  A b c)\"\nif [ -n \"$X\" ]; then echo \"::add-mask::$X\"; fi\n";
    assert!(unmasked(good).is_empty());
    let braces = "  value=\"$(\"$PWD/bazel-bin/tools/ci/gcp_secret_or_fail\" \\\n  echo \"::add-mask::${value}\"\n";
    assert!(unmasked(braces).is_empty());
}
