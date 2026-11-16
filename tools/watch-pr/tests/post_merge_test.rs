// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Runs the real watch-pr binary through its post-merge phase against a fake
//! `gh` and `bazel`.
//!
//! On 2026-11-16 PR #4953 (squash fa49ec5e) landed in a batched push whose tip
//! was 5373aea8. pipeline-status judged it by that tip and watch-pr showed the
//! tip's runs in progress for 20 minutes. Then the agent token watch-pr had
//! minted an hour earlier expired: every GitHub read inside pipeline-status
//! failed, pipeline-status answered "no verdict yet" (exit 3), and watch-pr
//! printed "No push workflow runs registered for fa49ec5e" for four hours.
//! The post-merge loop never re-minted the token, and it hid why there was no
//! verdict.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const SQUASH: &str = "fa49ec5e5d0a9b2e0d4c1f3e9a8b7c6d5e4f3a2b";

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn write_exe(path: &Path, body: &str) {
    fs::write(path, body).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

/// Watch a PR that has already merged. The fake `bazel run //tools/agent-app`
/// hands out `tok-1`, then `tok-2`, ... (one per mint). The fake
/// `bazel run //tools/pipeline-status` behaves as the real one did with an
/// expired token while GH_TOKEN is `tok-1`, and reports the batched push
/// green once it is anything newer.
fn watch(name: &str) -> Run {
    let tmp = PathBuf::from(std::env::var("TEST_TMPDIR").unwrap()).join(name);
    let bin = tmp.join("bin");
    fs::create_dir_all(&bin).unwrap();
    // watch-pr only mints its own token inside a checkout that has the tool.
    fs::create_dir_all(tmp.join("tools/agent-app")).unwrap();
    fs::write(tmp.join("tools/agent-app/BUILD"), "").unwrap();

    write_exe(
        &bin.join("gh"),
        &format!(
            r#"#!/bin/sh
case "$*" in
  *mergeCommit.oid*) echo '{SQUASH}' ;;
  "pr view"*) echo '{{"mergeCommit":{{"oid":"{SQUASH}"}},"mergeStateStatus":"UNKNOWN","state":"MERGED"}}' ;;
  *) exit 1 ;;
esac
"#
        ),
    );
    write_exe(&bin.join("git"), "#!/bin/sh\nexit 0\n");
    let counter = tmp.join("mints");
    write_exe(
        &bin.join("bazel"),
        &format!(
            r#"#!/bin/sh
case "$*" in
  *//tools/agent-app*)
    n=$(( $(cat '{c}' 2>/dev/null || echo 0) + 1 ))
    echo "$n" > '{c}'
    echo "export GH_TOKEN=tok-$n"
    ;;
  *//tools/pipeline-status*)
    echo "→ Checking GitHub Actions pipeline status for commit fa49ec5e in VitruvianSoftware/vitruvian-core..."
    if [ "$GH_TOKEN" = "tok-1" ]; then
      echo "⚠ No verdict yet for commit fa49ec5e: cannot read the push history: gh api repos/VitruvianSoftware/vitruvian-core/activity?ref=refs/heads/main&per_page=100 failed (exit 1)"
      exit 3
    fi
    echo "→ batched: fa49ec5e landed in a push whose tip is 5373aea8; evaluating the tip's runs"
    echo "✓ All post-merge workflows for fa49ec5e are GREEN (ALL_PASSED: 20 passed out of 20 total)"
    exit 0
    ;;
  *) exit 1 ;;
esac
"#,
            c = counter.display()
        ),
    );

    let watch_pr = fs::canonicalize(std::env::var("WATCH_PR_BIN").unwrap()).unwrap();
    let path = format!(
        "{}:{}",
        bin.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let out = Command::new(watch_pr)
        .args(["4953", "--timeout", "8", "--interval", "1"])
        .env("PATH", path)
        .env_remove("GH_TOKEN")
        .env("BUILD_WORKSPACE_DIRECTORY", &tmp)
        .env("WATCH_PR_REPO", "VitruvianSoftware/vitruvian-core")
        .output()
        .unwrap();
    Run {
        code: out.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
    }
}

/// Fail-before: watch-pr kept the expired token, so every poll said "no
/// runs registered" until the watchdog timed out (exit 2).
#[test]
fn an_expired_token_is_reminted_and_the_batched_push_goes_green() {
    let run = watch("expired");
    let all = format!("stdout:\n{}\nstderr:\n{}", run.stdout, run.stderr);
    assert_eq!(run.code, 0, "{all}");
    // It says why there was no verdict, not that no runs exist.
    assert!(run.stdout.contains("cannot read the push history"), "{all}");
    assert!(
        !run.stdout.contains("No push workflow runs registered"),
        "{all}"
    );
    assert!(run.stdout.contains("Minted a fresh GitHub token"), "{all}");
    // And it says the verdict came from the push that landed the commit.
    assert!(
        run.stdout
            .contains("batched: fa49ec5e landed in a push whose tip is 5373aea8"),
        "{all}"
    );
}
