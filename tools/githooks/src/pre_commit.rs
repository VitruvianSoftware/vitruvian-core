// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT
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

//! Rust port of `tools/githooks/pre-commit`.

use shell_compat::{os, out, subst};
use std::path::Path;
use std::process::{Command, Stdio};

pub const BAZEL_ENV_FORMAT: &str = "bazel-out/bazel_env-opt/bin/tools/bazel_env/bin/format";
pub const BAZEL_ENV_GAZELLE: &str = "bazel-out/bazel_env-opt/bin/tools/bazel_env/bin/gazelle";

/// Split NUL-delimited output from `git diff --cached --diff-filter=AM --name-only -z`.
pub fn parse_nul_delimited_paths(raw: &[u8]) -> Vec<Vec<u8>> {
    if raw.is_empty() {
        return Vec::new();
    }
    let mut parts: Vec<Vec<u8>> = raw.split(|&b| b == 0).map(|s| s.to_vec()).collect();
    if parts.last().map_or(false, |last| last.is_empty()) {
        parts.pop();
    }
    parts
}

fn format_staged_files(files: &[Vec<u8>]) {
    if files.is_empty() {
        return;
    }

    let mut msg = b"Formatting staged files: ".to_vec();
    for (idx, f) in files.iter().enumerate() {
        if idx > 0 {
            msg.push(b' ');
        }
        msg.extend_from_slice(f);
    }
    msg.push(b'\n');
    out(&msg);

    if Path::new(BAZEL_ENV_FORMAT).exists() {
        let mut cmd = Command::new(BAZEL_ENV_FORMAT);
        for f in files {
            cmd.arg(os(f));
        }
        let _ = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
    } else {
        let mut cmd = Command::new("bazel");
        cmd.arg("run").arg("//tools/format").arg("--");
        for f in files {
            cmd.arg(os(f));
        }
        let _ = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
    }

    let mut diff_quiet = Command::new("git");
    diff_quiet.arg("diff").arg("--quiet").arg("--");
    for f in files {
        diff_quiet.arg(os(f));
    }
    let quiet_ok = diff_quiet
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    if !quiet_ok {
        out(b"\xE2\x9D\x8C Some staged files were modified by the pre-commit hook.\n");
        out(b"Please review and stage the changes before committing again.\n");
        let mut diff_stat = Command::new("git");
        diff_stat.arg("diff").arg("--stat").arg("--");
        for f in files {
            diff_stat.arg(os(f));
        }
        let _ = diff_stat
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let staged_out = Command::new("git")
        .arg("diff")
        .arg("--cached")
        .arg("--diff-filter=AM")
        .arg("--name-only")
        .arg("-z")
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();

    if let Ok(o) = staged_out {
        let files = parse_nul_delimited_paths(&o.stdout);
        format_staged_files(&files);
    }

    if Path::new(BAZEL_ENV_GAZELLE).exists() {
        let _ = Command::new(BAZEL_ENV_GAZELLE)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
    } else {
        let _ = Command::new("bazel")
            .arg("run")
            .arg("//:gazelle")
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
    }

    let untracked_out = Command::new("git")
        .arg("ls-files")
        .arg("--others")
        .arg("--exclude-standard")
        .arg("--")
        .arg("*BUILD")
        .arg("*BUILD.bazel")
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    let build_untracked = untracked_out.map(|o| subst(o.stdout)).unwrap_or_default();

    let build_diff_ok = Command::new("git")
        .arg("diff")
        .arg("--quiet")
        .arg("--")
        .arg("*BUILD")
        .arg("*BUILD.bazel")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    if !build_diff_ok || !build_untracked.is_empty() {
        out(b"\xE2\x9D\x8C gazelle updated BUILD files.\n");
        out(b"Please review and stage the changes before committing again.\n");
        let _ = Command::new("git")
            .arg("diff")
            .arg("--stat")
            .arg("--")
            .arg("*BUILD")
            .arg("*BUILD.bazel")
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        if !build_untracked.is_empty() {
            let mut line = build_untracked;
            line.push(b'\n');
            out(&line);
        }
        return 1;
    }

    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_nul_delimited_paths() {
        assert!(parse_nul_delimited_paths(b"").is_empty());
        assert_eq!(
            parse_nul_delimited_paths(b"a.rs\0b/c.go\0"),
            vec![b"a.rs".to_vec(), b"b/c.go".to_vec()]
        );
    }
}
