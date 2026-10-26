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

//! Rust port of `tools/githooks/check-config.sh`.

use shell_compat::{env_or, env_or_empty, err, os, subst};
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

extern "C" {
    fn geteuid() -> u32;
}

/// Exact heredoc read into `GITHOOKS_MSG` by `IFS='' read -r -d '' GITHOOKS_MSG <<"EOF"`,
/// followed by the newline added by `echo >&2 "${GITHOOKS_MSG}"`.
pub const GITHOOKS_MSG_STDERR: &[u8] = b"    cat <<EOF
  It looks like the git config option core.hooksPath is not set.
  This repository uses hooks stored in tools/githooks/ to run tools such as formatters.
  You can disable this warning by running:

    echo \"common --workspace_status_command=\" >> ~/.bazelrc

  To set up the hooks, please run:

    git config core.hooksPath tools/githooks

";

pub fn format_primary_branch_guard(branch: &[u8]) -> Vec<u8> {
    let b = String::from_utf8_lossy(branch);
    format!(
        "  ✗ Bazel invocation refused: the PRIMARY checkout is on '{b}', not 'main'.\n\n  This checkout is shared across concurrent sessions — branch work here stomps\n  other sessions' HEAD and contends on one Bazel server (#455/#502).\n\n  Do branch work in an isolated worktree instead:\n\n      git switch main\n      bazel run //tools/worktree -- {b}\n\n  Break-glass override (only if you are certain nothing else shares this\n  checkout right now):\n\n      export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1\n"
    )
    .into_bytes()
}

pub fn strip_ascii_whitespace(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .copied()
        .filter(|c| !matches!(c, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c))
        .collect()
}

pub fn xcode_version_matches(have: &[u8], want: &[u8]) -> bool {
    if have == want {
        return true;
    }
    have.len() > want.len() && have.starts_with(want) && have[want.len()] == b'.'
}

pub fn info_plist_path_from_dev_dir(dev_dir: &[u8]) -> Vec<u8> {
    let base = dev_dir
        .strip_suffix(b"/Contents/Developer")
        .unwrap_or(dev_dir);
    let mut out = base.to_vec();
    out.extend_from_slice(b"/Contents/Info.plist");
    out
}

fn capture_stdout_quiet_stderr(cmd: &mut Command) -> (bool, Vec<u8>) {
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    match cmd.output() {
        Ok(o) => (o.status.success(), subst(o.stdout)),
        Err(_) => (false, Vec::new()),
    }
}

fn capture_stdout_inherit_stderr(cmd: &mut Command) -> (bool, Vec<u8>) {
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    match cmd.output() {
        Ok(o) => (o.status.success(), subst(o.stdout)),
        Err(_) => (false, Vec::new()),
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let (_, inside_work_tree) = capture_stdout_quiet_stderr(
        Command::new("git")
            .arg("rev-parse")
            .arg("--is-inside-work-tree"),
    );

    let euid = unsafe { geteuid() };
    if inside_work_tree == b"true" && euid != 0 {
        let (_, hooks_path) =
            capture_stdout_inherit_stderr(Command::new("git").arg("config").arg("core.hooksPath"));
        if hooks_path.is_empty() {
            err(GITHOOKS_MSG_STDERR);
        }
    }

    if inside_work_tree == b"true"
        && env_or_empty("CI").is_empty()
        && env_or_empty("GITHUB_ACTIONS").is_empty()
        && env_or_empty("CLAUDE_CODE_REMOTE") != b"true"
        && env_or("VITRUVIAN_ALLOW_PRIMARY_BRANCH", b"0") != b"1"
    {
        let (_, git_dir) =
            capture_stdout_quiet_stderr(Command::new("git").arg("rev-parse").arg("--git-dir"));
        let (_, git_common_dir) = capture_stdout_quiet_stderr(
            Command::new("git").arg("rev-parse").arg("--git-common-dir"),
        );
        if !git_dir.is_empty() && git_dir == git_common_dir {
            let (ok, sym_branch) = capture_stdout_inherit_stderr(
                Command::new("git")
                    .arg("symbolic-ref")
                    .arg("--short")
                    .arg("-q")
                    .arg("HEAD"),
            );
            let branch = if ok {
                sym_branch
            } else {
                b"(detached)".to_vec()
            };
            if branch != b"main" {
                err(&format_primary_branch_guard(&branch));
                return 1;
            }
        }
    }

    let (_, uname_s) = capture_stdout_inherit_stderr(Command::new("uname").arg("-s"));
    if uname_s == b"Darwin"
        && env_or_empty("CI").is_empty()
        && Path::new(".xcode-version").is_file()
    {
        let raw_want = fs::read(".xcode-version").unwrap_or_default();
        let want_xcode = strip_ascii_whitespace(&raw_want);
        let (_, dev_dir) = capture_stdout_quiet_stderr(Command::new("xcode-select").arg("-p"));
        let plist_path = info_plist_path_from_dev_dir(&dev_dir);
        let plistbuddy = env_or("PLISTBUDDY_BIN", b"/usr/libexec/PlistBuddy");
        let pb_res = Command::new(os(&plistbuddy))
            .arg("-c")
            .arg("Print :CFBundleShortVersionString")
            .arg(os(&plist_path))
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output();
        let have_xcode = match pb_res {
            Ok(o) if o.status.success() => subst(o.stdout),
            Ok(mut o) => {
                o.stdout
                    .extend_from_slice(b"none (Command Line Tools only)\n");
                subst(o.stdout)
            }
            Err(_) => b"none (Command Line Tools only)".to_vec(),
        };
        if !xcode_version_matches(&have_xcode, &want_xcode) {
            let have_s = String::from_utf8_lossy(&have_xcode);
            let want_s = String::from_utf8_lossy(&want_xcode);
            err(format!(
                "  ⚠ Xcode {have_s} is selected, but CI builds Swift with Xcode {want_s} (.xcode-version).\n    Swift results may differ from CI. Fix: sudo xcode-select -s /Applications/Xcode.app  (after installing Xcode {want_s})\n"
            )
            .as_bytes());
        }
    }

    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xcode_version_prefix_matching() {
        assert!(xcode_version_matches(b"27.0", b"27.0"));
        assert!(xcode_version_matches(b"27.0.1", b"27.0"));
        assert!(!xcode_version_matches(b"27.1", b"27.0"));
        assert!(!xcode_version_matches(
            b"none (Command Line Tools only)",
            b"27.0"
        ));
    }

    #[test]
    fn info_plist_strips_contents_developer_suffix() {
        assert_eq!(
            info_plist_path_from_dev_dir(b"/Applications/Xcode.app/Contents/Developer"),
            b"/Applications/Xcode.app/Contents/Info.plist"
        );
        assert_eq!(
            info_plist_path_from_dev_dir(b"/Library/Developer/CommandLineTools"),
            b"/Library/Developer/CommandLineTools/Contents/Info.plist"
        );
    }

    #[test]
    fn primary_branch_guard_formats_branch_name() {
        let msg = String::from_utf8(format_primary_branch_guard(b"feat/demo")).unwrap();
        assert!(msg.contains("PRIMARY checkout is on 'feat/demo', not 'main'."));
        assert!(msg.contains("bazel run //tools/worktree -- feat/demo"));
    }
}
