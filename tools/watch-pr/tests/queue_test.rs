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

//! Runs the real watch-pr binary against a fake `gh` and `git`, to pin what
//! it does once a PR's checks are green and it is waiting for the merge
//! queue. On 2026-11-13 PR #4771 was removed from the queue
//! (`checks_timed_out`) and the watcher kept printing "Waiting for squash
//! merge..." for an hour: it never asked GitHub whether the PR was still
//! queued, and it showed a failed `gh` call as "OPEN (mergeStateStatus:
//! QUEUED)", a value GitHub never returns.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

/// What the fake `gh api graphql` prints, as GitHub did for #4771 after it
/// was removed (same shape as the live response).
const REMOVED: &str = r#"{"data":{"repository":{"pullRequest":{"state":"OPEN","mergeStateStatus":"CLEAN","mergeCommit":null,"autoMergeRequest":null,"mergeQueueEntry":null,"timelineItems":{"nodes":[{"__typename":"AddedToMergeQueueEvent","createdAt":"2026-11-13T22:48:10Z"},{"__typename":"RemovedFromMergeQueueEvent","createdAt":"2026-11-14T01:24:44Z","reason":"checks_timed_out"}]}}}}}"#;

/// A PR that merged from the queue: GitHub records that as a removal too,
/// with reason `merged`, which must not read as a failure.
const MERGED_VIA_QUEUE: &str = r#"{"data":{"repository":{"pullRequest":{"state":"MERGED","mergeStateStatus":"UNKNOWN","mergeCommit":{"oid":"6960e3c655f3da6b63e68ea38f5acffb7e1ce1ea"},"autoMergeRequest":null,"mergeQueueEntry":null,"timelineItems":{"nodes":[{"__typename":"AddedToMergeQueueEvent","createdAt":"2026-11-14T00:25:20Z"},{"__typename":"RemovedFromMergeQueueEvent","createdAt":"2026-11-14T02:08:16Z","reason":"merged"}]}}}}}"#;

/// Still queued: the watcher should keep waiting (and so time out here).
const QUEUED: &str = r#"{"data":{"repository":{"pullRequest":{"state":"OPEN","mergeStateStatus":"CLEAN","mergeCommit":null,"autoMergeRequest":null,"mergeQueueEntry":{"state":"QUEUED","position":7,"enqueuedAt":"2026-11-14T02:20:49Z"},"timelineItems":{"nodes":[{"__typename":"RemovedFromMergeQueueEvent","createdAt":"2026-11-14T01:24:44Z","reason":"checks_timed_out"},{"__typename":"AddedToMergeQueueEvent","createdAt":"2026-11-14T02:20:49Z"}]}}}}}"#;

/// Removed, then auto-merge armed again: GitHub will re-queue it, so wait.
const REARMED: &str = r#"{"data":{"repository":{"pullRequest":{"state":"OPEN","mergeStateStatus":"BLOCKED","mergeCommit":null,"autoMergeRequest":{"enabledAt":"2026-11-14T02:19:00Z"},"mergeQueueEntry":null,"timelineItems":{"nodes":[{"__typename":"RemovedFromMergeQueueEvent","createdAt":"2026-11-14T01:24:44Z","reason":"checks_timed_out"}]}}}}}"#;

struct Run {
    code: i32,
    stdout: String,
    stderr: String,
}

fn write_exe(path: &Path, body: &str) {
    fs::write(path, body).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

/// Run watch-pr on PR #4771 with a fake `gh` whose `api graphql` prints
/// `graphql` (or fails, when it is None). `pr view` says OPEN (or fails
/// with it) and `pr checks` one passing check, so the watcher reaches the
/// queue phase.
fn watch(name: &str, graphql: Option<&str>) -> Run {
    let tmp = PathBuf::from(std::env::var("TEST_TMPDIR").unwrap()).join(name);
    let bin = tmp.join("bin");
    fs::create_dir_all(&bin).unwrap();
    // When GitHub cannot be read, `pr view` fails too, as it did for #4771.
    let pr_view_case = if graphql.is_some() {
        r#"echo '{"mergeCommit":null,"mergeStateStatus":"CLEAN","state":"OPEN"}'"#
    } else {
        "exit 1"
    };
    let graphql_case = match graphql {
        Some(json) => {
            fs::write(tmp.join("graphql.json"), json).unwrap();
            format!("cat '{}'", tmp.join("graphql.json").display())
        }
        None => "echo 'HTTP 401: Bad credentials (https://api.github.com/graphql)' >&2; exit 1"
            .to_string(),
    };
    write_exe(
        &bin.join("gh"),
        &format!(
            r#"#!/bin/sh
case "$1 $2" in
  "pr view") {pr_view_case} ;;
  "pr checks") echo '[{{"name":"ci","state":"SUCCESS","bucket":"pass","workflow":"CI","link":"https://github.com/o/r/actions/runs/1"}}]' ;;
  "api graphql") {graphql_case} ;;
  *) exit 1 ;;
esac
"#
        ),
    );
    // No squash commit on main, ever: only GitHub's answer can end the wait.
    write_exe(&bin.join("git"), "#!/bin/sh\nexit 0\n");

    let watch_pr = fs::canonicalize(std::env::var("WATCH_PR_BIN").unwrap()).unwrap();
    let path = format!(
        "{}:{}",
        bin.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let out = Command::new(watch_pr)
        .args([
            "4771",
            "--timeout",
            "15",
            "--interval",
            "1",
            "--skip-post-merge",
        ])
        .env("PATH", path)
        .env("GH_TOKEN", "fake")
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

#[test]
fn removed_from_queue_exits_1_with_the_reason() {
    let run = watch("removed", Some(REMOVED));
    assert_eq!(
        run.code, 1,
        "stdout:\n{}\nstderr:\n{}",
        run.stdout, run.stderr
    );
    assert!(
        run.stderr.contains("removed from the merge queue"),
        "{}",
        run.stderr
    );
    assert!(run.stderr.contains("checks_timed_out"), "{}", run.stderr);
    assert!(
        run.stderr.contains("2026-11-14T01:24:44Z"),
        "{}",
        run.stderr
    );
}

#[test]
fn merged_from_queue_is_success() {
    let run = watch("merged", Some(MERGED_VIA_QUEUE));
    assert_eq!(
        run.code, 0,
        "stdout:\n{}\nstderr:\n{}",
        run.stdout, run.stderr
    );
    assert!(run.stdout.contains("MERGED"), "{}", run.stdout);
}

#[test]
fn still_queued_keeps_waiting_and_shows_the_position() {
    let run = watch("queued", Some(QUEUED));
    assert_eq!(
        run.code, 2,
        "stdout:\n{}\nstderr:\n{}",
        run.stdout, run.stderr
    );
    assert!(run.stdout.contains("position 7"), "{}", run.stdout);
}

#[test]
fn rearmed_after_removal_keeps_waiting() {
    let run = watch("rearmed", Some(REARMED));
    assert_eq!(
        run.code, 2,
        "stdout:\n{}\nstderr:\n{}",
        run.stdout, run.stderr
    );
    assert!(run.stdout.contains("auto-merge is armed"), "{}", run.stdout);
}

#[test]
fn unreadable_state_fails_instead_of_claiming_queued() {
    let run = watch("unreadable", None);
    assert!(
        !run.stdout.contains("mergeStateStatus: QUEUED"),
        "made up a queued state:\n{}",
        run.stdout
    );
    assert_eq!(
        run.code, 1,
        "stdout:\n{}\nstderr:\n{}",
        run.stdout, run.stderr
    );
    assert!(run.stderr.contains("Bad credentials"), "{}", run.stderr);
}
