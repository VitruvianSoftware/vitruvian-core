// Copyright (c) 2026 VitruvianSoftware
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

//! Rust port of `tools/workspace-status.sh`.
//!
//! Runs the repository configuration guard (`tools/githooks/check-config.sh` logic),
//! resolves `STABLE_GIT_COMMIT` via `git rev-parse HEAD` and
//! `STABLE_MONOREPO_VERSION` via `git describe --tags --long --match="[0-9][0-9][0-9][0-9].[0-9][0-9]"`
//! with `s/-/./;s/-g/-/` formatting, and writes the stamp lines to stdout.

use std::env;
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

extern "C" {
    fn geteuid() -> u32;
}

pub const GITHOOKS_MSG_STDERR: &str = "    cat <<EOF\n  It looks like the git config option core.hooksPath is not set.\n  This repository uses hooks stored in tools/githooks/ to run tools such as formatters.\n  You can disable this warning by running:\n\n    echo \"common --workspace_status_command=\" >> ~/.bazelrc\n\n  To set up the hooks, please run:\n\n    git config core.hooksPath tools/githooks\n\n";

/// Transforms `git describe --tags --long --match="[0-9][0-9][0-9][0-9].[0-9][0-9]"`
/// output using the equivalent of `sed -e 's/-/./;s/-g/-/'`.
pub fn format_describe_version(describe_output: &str) -> String {
    let trimmed = describe_output.trim_end_matches(&['\r', '\n'][..]);
    let step1 = trimmed.replacen('-', ".", 1);
    step1.replacen("-g", "-", 1)
}

pub fn format_stamp_output(git_commit: &str, auto_version: &str) -> String {
    let commit = git_commit.trim_end_matches(&['\r', '\n'][..]);
    let version = auto_version.trim_end_matches(&['\r', '\n'][..]);
    format!("STABLE_GIT_COMMIT {commit}\nSTABLE_MONOREPO_VERSION {version}\n")
}

pub fn format_primary_branch_guard(branch: &str) -> String {
    format!(
        "  ✗ Bazel invocation refused: the PRIMARY checkout is on '{branch}', not 'main'.\n\n  This checkout is shared across concurrent sessions — branch work here stomps\n  other sessions' HEAD and contends on one Bazel server (#455/#502).\n\n  Do branch work in an isolated worktree instead:\n\n      git switch main\n      bazel run //tools/worktree -- {branch}\n\n  Break-glass override (only if you are certain nothing else shares this\n  checkout right now):\n\n      export VITRUVIAN_ALLOW_PRIMARY_BRANCH=1\n"
    )
}

pub fn xcode_version_matches(have: &str, want: &str) -> bool {
    if have == want {
        return true;
    }
    have.len() > want.len()
        && have.starts_with(want)
        && have.as_bytes().get(want.len()) == Some(&b'.')
}

fn capture_git(dir: &Path, args: &[&str], quiet_stderr: bool) -> (bool, String) {
    let mut cmd = Command::new("git");
    cmd.current_dir(dir).args(args).stdout(Stdio::piped());
    if quiet_stderr {
        cmd.stderr(Stdio::null());
    } else {
        cmd.stderr(Stdio::inherit());
    }
    match cmd.output() {
        Ok(o) => {
            let s = String::from_utf8_lossy(&o.stdout)
                .trim_end_matches(&['\r', '\n'][..])
                .to_string();
            (o.status.success(), s)
        }
        Err(_) => (false, String::new()),
    }
}

pub fn check_repo_config_and_head(dir: &Path) -> Result<String, i32> {
    let (ok, rev_out) = capture_git(
        dir,
        &[
            "rev-parse",
            "HEAD",
            "--is-inside-work-tree",
            "--git-dir",
            "--git-common-dir",
            "--symbolic-full-name",
            "HEAD",
        ],
        true,
    );
    let lines: Vec<&str> = rev_out.lines().collect();
    let head_sha = lines.first().copied().unwrap_or("");
    let inside = lines.get(1).copied().unwrap_or("");
    let git_dir = lines.get(2).copied().unwrap_or("");
    let git_common_dir = lines.get(3).copied().unwrap_or("");
    let sym_ref = lines.get(4).copied().unwrap_or("");

    let euid = unsafe { geteuid() };

    if inside == "true" && euid != 0 {
        let (_, hooks_path) = capture_git(dir, &["config", "core.hooksPath"], false);
        if hooks_path.is_empty() {
            eprint!("{GITHOOKS_MSG_STDERR}");
        }
    }

    let ci_empty = env::var("CI").unwrap_or_default().is_empty();
    let gha_empty = env::var("GITHUB_ACTIONS").unwrap_or_default().is_empty();
    let claude_remote = env::var("CLAUDE_CODE_REMOTE").unwrap_or_default() == "true";
    let allow_primary =
        env::var("VITRUVIAN_ALLOW_PRIMARY_BRANCH").unwrap_or_else(|_| "0".into()) == "1";

    if inside == "true" && ci_empty && gha_empty && !claude_remote && !allow_primary {
        if !git_dir.is_empty() && git_dir == git_common_dir {
            let branch = sym_ref.strip_prefix("refs/heads/").unwrap_or("(detached)");
            if branch != "main" {
                eprint!("{}", format_primary_branch_guard(branch));
                return Err(1);
            }
        }
    }

    let xcode_ver_file = dir.join(".xcode-version");
    if cfg!(target_os = "macos") && ci_empty && xcode_ver_file.is_file() {
        let want_xcode: String = fs::read_to_string(&xcode_ver_file)
            .unwrap_or_default()
            .chars()
            .filter(|c| !c.is_ascii_whitespace())
            .collect();
        let dev_dir = Command::new("xcode-select")
            .arg("-p")
            .stderr(Stdio::null())
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .trim_end_matches(&['\r', '\n'][..])
                    .to_string()
            })
            .unwrap_or_default();
        let base_dir = dev_dir
            .strip_suffix("/Contents/Developer")
            .unwrap_or(&dev_dir);
        let plist_path = format!("{base_dir}/Contents/Info.plist");
        let plistbuddy =
            env::var("PLISTBUDDY_BIN").unwrap_or_else(|_| "/usr/libexec/PlistBuddy".to_string());
        let have_xcode = Command::new(&plistbuddy)
            .args(["-c", "Print :CFBundleShortVersionString", &plist_path])
            .stderr(Stdio::null())
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| {
                String::from_utf8_lossy(&o.stdout)
                    .trim_end_matches(&['\r', '\n'][..])
                    .to_string()
            })
            .unwrap_or_else(|| "none (Command Line Tools only)".to_string());
        if !xcode_version_matches(&have_xcode, &want_xcode) {
            eprintln!(
                "  ⚠ Xcode {have_xcode} is selected, but CI builds Swift with Xcode {want_xcode} (.xcode-version)."
            );
            eprintln!(
                "    Swift results may differ from CI. Fix: sudo xcode-select -s /Applications/Xcode.app  (after installing Xcode {want_xcode})"
            );
        }
    }

    if !ok || head_sha.is_empty() {
        return Err(1);
    }
    Ok(head_sha.to_string())
}

pub fn run_in_dir(dir: &Path) -> Result<String, i32> {
    let git_commit = check_repo_config_and_head(dir)?;

    let (desc_ok, raw_describe) = capture_git(
        dir,
        &[
            "describe",
            "--tags",
            "--long",
            "--match=[0-9][0-9][0-9][0-9].[0-9][0-9]",
        ],
        false,
    );
    if !desc_ok || raw_describe.is_empty() {
        return Err(1);
    }

    let auto_version = format_describe_version(&raw_describe);
    Ok(format_stamp_output(&git_commit, &auto_version))
}

pub fn run(_args: &[String]) -> i32 {
    let cwd = env::current_dir().unwrap_or_else(|_| Path::new(".").to_path_buf());
    match run_in_dir(&cwd) {
        Ok(out) => {
            print!("{out}");
            0
        }
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn describe_version_replaces_first_dash_and_g_prefix() {
        assert_eq!(
            format_describe_version("2026.10-42-g1234567\n"),
            "2026.10.42-1234567"
        );
        assert_eq!(
            format_describe_version("2026.01-0-gabcdef0"),
            "2026.01.0-abcdef0"
        );
    }

    #[test]
    fn stamp_output_matches_expected_key_value_lines() {
        let out = format_stamp_output("deadbeef1234", "2026.10.5-deadbee");
        assert_eq!(
            out,
            "STABLE_GIT_COMMIT deadbeef1234\nSTABLE_MONOREPO_VERSION 2026.10.5-deadbee\n"
        );
    }

    #[test]
    fn end_to_end_git_repo_produces_valid_stamp() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let repo = env::temp_dir().join(format!("workspace-status-test-{nanos}"));
        fs::create_dir_all(&repo).unwrap();

        let run_git = |args: &[&str]| {
            let status = Command::new("git")
                .current_dir(&repo)
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .env("GIT_CONFIG_SYSTEM", "/dev/null")
                .args(args)
                .status()
                .unwrap();
            assert!(status.success(), "git {args:?} failed");
        };

        run_git(&["init", "-q", "-b", "main"]);
        run_git(&["config", "user.name", "test"]);
        run_git(&["config", "user.email", "test@example.invalid"]);
        run_git(&["config", "core.hooksPath", "tools/githooks"]);
        run_git(&["commit", "-q", "--allow-empty", "-m", "initial"]);
        run_git(&["tag", "2026.10"]);
        run_git(&["commit", "-q", "--allow-empty", "-m", "second"]);

        let (_, expected_sha) = capture_git(&repo, &["rev-parse", "HEAD"], true);
        let stamp = run_in_dir(&repo).expect("run_in_dir should succeed on main with YYYY.MM tag");
        let lines: Vec<&str> = stamp.lines().collect();
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0], format!("STABLE_GIT_COMMIT {expected_sha}"));
        assert!(
            lines[1].starts_with("STABLE_MONOREPO_VERSION 2026.10.1-"),
            "unexpected version line: {}",
            lines[1]
        );

        let _ = fs::remove_dir_all(&repo);
    }
}
