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

//! Black-box tests for //tools/ci:site_pr_automerge, which arms auto-merge on
//! the website PRs catalog-publish and site-sync-downloads open, at the commit
//! they pushed, and leaves a held PR alone.
//!
//! A fake `gh` answers from env fixtures and logs every call; no network, no
//! credentials, no jq. It never evaluates --jq, so it answers with what the
//! real filter prints: "<armed> <draft> <head> <hold labels>".

use ci_testkit::{bin, read, write_exe, Output, Run, TempDir};

const FAKE_GH: &str = r#"#!/usr/bin/env bash
echo "$*" >>"$FAKE_GH_LOG"
case "$1 $2" in
  "pr list")
    [ "${FAKE_LIST_RC:-0}" = "0" ] || { echo "gh: HTTP 502" >&2; exit 1; }
    printf '%s\n' "${FAKE_LIST_OUT-42}"
    ;;
  "pr view")
    [ "${FAKE_VIEW_RC:-0}" = "0" ] || { echo "gh: HTTP 500" >&2; exit 1; }
    case "$*" in
      *headRefOid*) printf '%s\n' "${FAKE_STATE:-false false sha1 }" ;;
      *) printf '%s\n' "${FAKE_ARMED:-false}" ;;
    esac
    ;;
  "pr merge")
    case "$*" in
      *--disable-auto*) [ "${FAKE_DISABLE_RC:-0}" = "0" ] || { echo "gh: HTTP 422" >&2; exit 1; } ;;
      *) [ "${FAKE_MERGE_RC:-0}" = "0" ] || { echo "gh: HTTP 422" >&2; exit 1; } ;;
    esac
    ;;
  *)
    echo "unexpected gh call: $*" >&2
    exit 99
    ;;
esac
"#;

struct Case {
    out: Output,
    log: String,
    summary: String,
}

impl Case {
    fn armed_at(&self, sha: &str) -> bool {
        let want = format!("pr merge 42 --repo o/r --squash --auto --match-head-commit {sha}");
        self.log.lines().any(|l| l == want)
    }
    fn any_arm(&self) -> bool {
        self.log.contains("--auto")
    }
    fn disabled(&self) -> bool {
        self.log
            .lines()
            .any(|l| l == "pr merge 42 --repo o/r --disable-auto")
    }
    fn labels_touched(&self) -> bool {
        self.log
            .lines()
            .any(|l| l.starts_with("pr edit") || l.contains("-label") || l.starts_with("label"))
    }
    fn merged_any(&self) -> bool {
        self.log.lines().any(|l| l.starts_with("pr merge"))
    }
}

/// Run with `args`, the fake gh first on PATH, REPO=o/r, plus `env`.
fn run(args: &[&str], env: &[(&str, &str)]) -> Case {
    let work = TempDir::new();
    let fakes = work.join("bin");
    write_exe(fakes.join("gh"), FAKE_GH);
    let log = work.join("log");
    let summary = work.join("summary");
    let mut r = Run::new(&bin("BIN"))
        .path_first(&fakes)
        .env("GH_TOKEN", "x")
        .env("REPO", "o/r")
        .env("FAKE_GH_LOG", &log)
        .env("GITHUB_STEP_SUMMARY", &summary)
        .args(args);
    for (k, v) in env {
        r = r.env(k, v);
    }
    let out = r.go();
    Case {
        out,
        log: read(&log),
        summary: read(&summary),
    }
}

const ARM: &[&str] = &["arm", "--branch", "auto/x", "--sha", "sha1"];
const DISARM: &[&str] = &["disarm", "--branch", "auto/x"];

// --- arm ---

#[test]
fn a_new_pr_is_armed_squash_at_the_pushed_commit() {
    let c = run(ARM, &[]);
    assert_eq!(c.out.code, 0, "{:?}", c.out);
    assert!(c.armed_at("sha1"), "log: {}", c.log);
    assert!(
        c.summary.contains("Armed auto-merge on #42"),
        "{}",
        c.summary
    );
}

#[test]
fn already_armed_at_this_head_is_left_alone() {
    let c = run(ARM, &[("FAKE_STATE", "true false sha1 ")]);
    assert_eq!(c.out.code, 0);
    assert!(!c.any_arm() && !c.disabled(), "log: {}", c.log);
    assert!(c.summary.contains("already on"), "{}", c.summary);
}

#[test]
fn do_not_automerge_is_not_armed_and_the_label_stays() {
    let c = run(ARM, &[("FAKE_STATE", "false false sha1 do-not-automerge")]);
    assert_eq!(c.out.code, 0);
    assert!(
        !c.any_arm() && !c.disabled() && !c.labels_touched(),
        "log: {}",
        c.log
    );
    assert!(
        c.summary
            .contains("not armed: it is held (do-not-automerge)"),
        "{}",
        c.summary
    );
}

#[test]
fn needs_human_with_auto_merge_on_is_turned_off_not_rearmed() {
    let c = run(ARM, &[("FAKE_STATE", "true false sha1 needs-human")]);
    assert_eq!(c.out.code, 0);
    assert!(
        c.disabled() && !c.any_arm() && !c.labels_touched(),
        "log: {}",
        c.log
    );
}

#[test]
fn both_hold_labels_are_named_comma_separated() {
    let c = run(
        ARM,
        &[("FAKE_STATE", "false true sha1 do-not-automerge,needs-human")],
    );
    assert_eq!(c.out.code, 0);
    assert!(
        c.summary
            .contains("it is held (do-not-automerge, needs-human) (a draft)"),
        "{}",
        c.summary
    );
}

#[test]
fn a_draft_is_not_armed() {
    let c = run(ARM, &[("FAKE_STATE", "false true sha1 ")]);
    assert_eq!(c.out.code, 0);
    assert!(!c.any_arm(), "log: {}", c.log);
    assert!(c.summary.contains("a draft"), "{}", c.summary);
}

#[test]
fn head_moved_past_this_runs_commit_turns_off_and_warns() {
    let c = run(ARM, &[("FAKE_STATE", "true false sha2 ")]);
    assert_eq!(c.out.code, 0);
    assert!(c.disabled() && !c.any_arm(), "log: {}", c.log);
    assert!(
        c.out
            .stdout
            .contains("::warning title=auto-merge not armed::"),
        "{}",
        c.out.stdout
    );
}

// --- arm: failures are loud ---

#[test]
fn a_refused_arm_fails_with_an_error_and_a_summary_warning() {
    let c = run(ARM, &[("FAKE_MERGE_RC", "1")]);
    assert_eq!(c.out.code, 1);
    assert!(c
        .out
        .stdout
        .contains("::error title=auto-merge not armed::"));
    assert!(c.summary.contains("WARNING") && c.summary.contains("Auto-merge is not armed"));
}

#[test]
fn a_failed_lookup_is_not_read_as_no_pr() {
    let c = run(ARM, &[("FAKE_LIST_RC", "1")]);
    assert_eq!(c.out.code, 1);
    assert!(!c.merged_any(), "log: {}", c.log);
    assert!(
        c.summary.contains("Auto-merge is not armed"),
        "{}",
        c.summary
    );
    // gh's own error reaches the log, as it did from `$(gh ...)`.
    assert!(c.out.stderr.contains("gh: HTTP 502"), "{}", c.out.stderr);
}

#[test]
fn no_open_pr_right_after_the_push_fails() {
    let c = run(ARM, &[("FAKE_LIST_OUT", "")]);
    assert_eq!(c.out.code, 1);
    assert!(c.summary.contains("no open pull request"), "{}", c.summary);
}

#[test]
fn an_unreadable_pr_fails_without_arming() {
    let c = run(ARM, &[("FAKE_VIEW_RC", "1")]);
    assert_eq!(c.out.code, 1);
    assert!(!c.merged_any(), "log: {}", c.log);
}

#[test]
fn a_hold_whose_auto_merge_cannot_be_turned_off_fails() {
    let c = run(
        ARM,
        &[
            ("FAKE_STATE", "true false sha1 do-not-automerge"),
            ("FAKE_DISABLE_RC", "1"),
        ],
    );
    assert_eq!(c.out.code, 1);
    assert!(!c.any_arm(), "log: {}", c.log);
}

// --- disarm (before the push) ---

#[test]
fn disarm_turns_an_armed_pr_off() {
    let c = run(DISARM, &[("FAKE_ARMED", "true")]);
    assert_eq!(c.out.code, 0);
    assert!(c.disabled() && !c.any_arm(), "log: {}", c.log);
}

#[test]
fn disarm_with_auto_merge_already_off_does_nothing() {
    let c = run(DISARM, &[("FAKE_ARMED", "false")]);
    assert_eq!(c.out.code, 0);
    assert!(!c.merged_any(), "log: {}", c.log);
}

#[test]
fn disarm_with_no_pr_yet_does_nothing() {
    let c = run(DISARM, &[("FAKE_LIST_OUT", "")]);
    assert_eq!(c.out.code, 0);
    assert!(
        !c.log.lines().any(|l| l.starts_with("pr view")),
        "log: {}",
        c.log
    );
}

#[test]
fn disarm_fails_on_a_failed_lookup() {
    let c = run(DISARM, &[("FAKE_LIST_RC", "1")]);
    assert_eq!(c.out.code, 1);
}

#[test]
fn disarm_fails_when_auto_merge_cannot_be_turned_off() {
    let c = run(DISARM, &[("FAKE_ARMED", "true"), ("FAKE_DISABLE_RC", "1")]);
    assert_eq!(c.out.code, 1);
}

// --- usage ---

#[test]
fn arm_without_sha_is_refused_before_any_gh_call() {
    let c = run(&["arm", "--branch", "auto/x"], &[]);
    assert_eq!(c.out.code, 2);
    assert!(c.log.is_empty(), "log: {}", c.log);
}

#[test]
fn no_repo_is_refused_before_any_gh_call() {
    let c = run(ARM, &[("REPO", "")]);
    assert_eq!(c.out.code, 2);
    assert!(c.log.is_empty(), "log: {}", c.log);
}

#[test]
fn unknown_or_dangling_arguments_are_refused() {
    for args in [
        &["arm", "--branch", "auto/x", "--sha", "sha1", "--bogus"][..],
        &["disarm", "--branch"][..],
        &["arm", "--branch", "auto/x", "--sha"][..],
        &["frobnicate", "--branch", "auto/x"][..],
        &[][..],
    ] {
        let c = run(args, &[]);
        assert_eq!(c.out.code, 2, "{args:?}: {:?}", c.out);
        assert!(
            c.out.stderr.contains("usage:"),
            "{args:?}: {}",
            c.out.stderr
        );
        assert!(c.log.is_empty(), "{args:?} log: {}", c.log);
    }
}

#[test]
fn bad_arguments_are_reported_before_a_missing_repo() {
    let c = run(&["arm", "--branch", "auto/x"], &[("REPO", "")]);
    assert_eq!(c.out.code, 2);
    assert!(c.out.stderr.contains("usage:"), "{}", c.out.stderr);
}
