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

//! Black-box tests for //tools/ci:release_hold, which holds or releases a
//! component's open release PR on its development deploy's conclusion
//! (.github/workflows/release-hold.yaml). Runs the REAL binary with a fake
//! `gh` on PATH (hermetic: no network, no token). Ported case for case from
//! the former release-hold_test.sh, plus the cases that suite never pinned:
//! every blocking conclusion, `skipped`, an unrecognised conclusion, the
//! exact read-only lookups, the comment text, failed auto-merge calls, and a
//! missing required variable.

use ci_testkit::{assert_has, assert_lacks, bin, read, write_exe, Output, Run, TempDir};

/// Every invocation is logged to $GH_STUB_DIR/log as one `$*` line. The
/// comment body (the last argument of `pr comment`) also goes to
/// $GH_STUB_DIR/comment, since it spans lines. Answers come from env:
///   FAKE_PR_LIST_RC / FAKE_PR_LIST_OUT     `gh pr list`
///   FAKE_RUN_VIEW_RC / FAKE_RUN_VIEW_OUT   `gh run view`
///   FAKE_PR_VIEW_LABELS_OUT                `gh pr view` (labels, one a line)
///   FAKE_MERGE_RC                          `gh pr merge` (either direction)
const FAKE_GH: &str = r#"#!/usr/bin/env bash
W="$GH_STUB_DIR"
echo "$*" >> "$W/log"
case "$1 $2" in
  "pr list")
    if [ "${FAKE_PR_LIST_RC:-0}" != "0" ]; then
      echo "gh: HTTP 502 (something went wrong)" >&2
      exit "${FAKE_PR_LIST_RC}"
    fi
    printf '%s' "${FAKE_PR_LIST_OUT:-}"
    ;;
  "run view")
    if [ "${FAKE_RUN_VIEW_RC:-0}" != "0" ]; then
      echo "gh: HTTP 500 (internal error)" >&2
      exit "${FAKE_RUN_VIEW_RC}"
    fi
    printf '%s' "${FAKE_RUN_VIEW_OUT:-}"
    ;;
  "pr view")
    printf '%s' "${FAKE_PR_VIEW_LABELS_OUT:-}"
    ;;
  "pr merge")
    exit "${FAKE_MERGE_RC:-0}"
    ;;
  "pr comment")
    printf '%s' "${@: -1}" > "$W/comment"
    ;;
  "pr edit" | "label create")
    exit 0
    ;;
  *)
    echo "unexpected fake gh invocation: $*" >&2
    exit 99
    ;;
esac
"#;

const DEV_JOB: &str = "deploy-dev / deploy";

struct Hold {
    dir: TempDir,
}

impl Hold {
    fn new() -> Hold {
        let dir = TempDir::new();
        write_exe(dir.join("bin/gh"), FAKE_GH);
        Hold { dir }
    }

    /// The shell suite's run(): a fixed env, then per-case overrides. Ambient
    /// matrix variables are removed so a CI runner cannot leak in.
    fn run(&self, overrides: &[(&str, &str)]) -> Output {
        let _ = std::fs::remove_file(self.dir.join("log"));
        let _ = std::fs::remove_file(self.dir.join("comment"));
        let mut r = Run::new(&bin("BIN"))
            .path_first(&self.dir.join("bin"))
            .env("GH_STUB_DIR", self.dir.path())
            .env("GH_TOKEN", "x")
            .env("REPO", "owner/repo")
            .env("RUN_ID", "999")
            .env("DEV_JOB", DEV_JOB)
            .env("COMPONENT", "tabula-api")
            .env_remove("SOURCE")
            .env_remove("TRIGGERED_BY")
            .env_remove("FAKE_PR_LIST_RC")
            .env_remove("FAKE_PR_LIST_OUT")
            .env_remove("FAKE_RUN_VIEW_RC")
            .env_remove("FAKE_RUN_VIEW_OUT")
            .env_remove("FAKE_PR_VIEW_LABELS_OUT")
            .env_remove("FAKE_MERGE_RC");
        for (k, v) in overrides {
            r = r.env(k, v);
        }
        r.go()
    }

    fn log(&self) -> String {
        read(self.dir.join("log"))
    }

    fn calls(&self, prefix: &str) -> usize {
        self.log().lines().filter(|l| l.starts_with(prefix)).count()
    }

    fn comment(&self) -> String {
        read(self.dir.join("comment"))
    }
}

fn job(conclusion: &str) -> String {
    format!("{DEV_JOB}\t{conclusion}")
}

/// No PR state changes at all: no label edit, no merge call, no comment.
#[track_caller]
fn assert_no_mutation(h: &Hold, what: &str) {
    let log = h.log();
    for m in ["pr edit", "pr merge", "pr comment", "label create"] {
        assert_eq!(
            h.calls(m),
            0,
            "{what}: unexpected `{m}`\n--- log ---\n{log}"
        );
    }
}

const LIST: &str = "pr list --repo owner/repo --head release-please--branches--main--components--tabula-api --state open --json number --jq .[0].number // empty";
const VIEW: &str =
    "run view 999 --repo owner/repo --json jobs --jq .jobs[] | \"\\(.name)\\t\\(.conclusion)\"";
const LABELS: &str = "pr view 42 --repo owner/repo --json labels --jq .labels[].name";
const LABEL_CREATE: &str = "label create dev-deploy-red --repo owner/repo --force --color d93f0b --description Held by release-hold: this component's development deploy is red";

// --- the bug fix: a failed `gh pr list` must NOT look like "no open PR" ----

#[test]
fn pr_list_failure_is_an_indeterminate_warning_not_no_pr() {
    let h = Hold::new();
    let o = h.run(&[("FAKE_PR_LIST_RC", "1")]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "::warning title=release-hold indeterminate::",
        "titled warning",
    );
    assert_has(&o.stdout, "could not list open release PRs", "warning text");
    assert_has(&o.stdout, "HTTP 502", "gh's own error is quoted");
    assert_has(
        &o.stdout,
        "leaving any hold/release untouched",
        "says nothing changed",
    );
    assert_lacks(
        &o.stdout,
        "No open release PR",
        "not mistaken for an empty list",
    );
}

#[test]
fn pr_list_failure_short_circuits_before_run_view() {
    let h = Hold::new();
    h.run(&[("FAKE_PR_LIST_RC", "1")]);
    assert_eq!(h.calls("pr list"), 1, "{}", h.log());
    assert_eq!(h.calls("run view"), 0, "{}", h.log());
    assert_no_mutation(&h, "pr list failure");
}

// --- lookups ---------------------------------------------------------------

#[test]
fn run_view_failure_surfaces_its_own_indeterminate_warning() {
    let h = Hold::new();
    let o = h.run(&[("FAKE_PR_LIST_OUT", "42"), ("FAKE_RUN_VIEW_RC", "1")]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "::warning title=release-hold indeterminate::could not read jobs for run 999: ",
        "run view warning",
    );
    assert_has(
        &o.stdout,
        "leaving release PR #42 untouched",
        "names the PR",
    );
    assert_no_mutation(&h, "run view failure");
}

#[test]
fn empty_pr_list_exits_cleanly() {
    let h = Hold::new();
    let o = h.run(&[("FAKE_PR_LIST_OUT", "")]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "No open release PR on release-please--branches--main--components--tabula-api",
        "nothing open",
    );
    assert_eq!(h.calls("run view"), 0, "{}", h.log());
    assert_no_mutation(&h, "no PR");
}

/// The lookups are what scope the gate to ONE PR on ONE branch: a dropped
/// --head or --state open would let it act on some other PR.
#[test]
fn lookups_target_exactly_the_component_release_branch_and_run() {
    let h = Hold::new();
    h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
    ]);
    let log = h.log();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(lines.first().copied(), Some(LIST), "pr list argv\n{log}");
    assert_eq!(lines.get(1).copied(), Some(VIEW), "run view argv\n{log}");
    assert_eq!(lines.get(2).copied(), Some(LABELS), "pr view argv\n{log}");
}

#[test]
fn dev_job_absent_from_the_run_makes_no_mutating_calls() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", "some-other-job\tsuccess"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(&o.stdout, "has no 'deploy-dev / deploy' job", "missing job");
    assert_no_mutation(&h, "missing job");
}

/// The job name is matched exactly, not as a prefix or substring.
#[test]
fn dev_job_match_is_exact() {
    let h = Hold::new();
    let jobs = format!("{DEV_JOB} (extra)\tfailure\nx {DEV_JOB}\tfailure");
    let o = h.run(&[("FAKE_PR_LIST_OUT", "42"), ("FAKE_RUN_VIEW_OUT", &jobs)]);
    assert_has(
        &o.stdout,
        "has no 'deploy-dev / deploy' job",
        "no exact match",
    );
    assert_no_mutation(&h, "near-miss job names");
}

// --- green: release this workflow's own hold, never a person's --------------

#[test]
fn success_with_own_hold_clears_label_and_rearms_auto_merge() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
        ("FAKE_PR_VIEW_LABELS_OUT", "dev-deploy-red"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    let log = h.log();
    assert_has(
        &log,
        "pr edit 42 --repo owner/repo --remove-label dev-deploy-red\n",
        "label removed",
    );
    assert_has(
        &log,
        "pr merge 42 --repo owner/repo --squash --auto\n",
        "auto-merge re-armed",
    );
    assert_has(&o.stdout, "Development is green again", "says it released");
    assert_eq!(h.calls("pr comment"), 0, "{log}");
}

#[test]
fn skipped_counts_as_green() {
    let h = Hold::new();
    h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("skipped")),
        ("FAKE_PR_VIEW_LABELS_OUT", "dev-deploy-red"),
    ]);
    assert_has(
        &h.log(),
        "pr merge 42 --repo owner/repo --squash --auto\n",
        "re-armed on skipped",
    );
}

#[test]
fn success_with_only_a_persons_hold_makes_no_mutating_calls() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
        ("FAKE_PR_VIEW_LABELS_OUT", "do-not-automerge"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "No hold of this workflow's on #42",
        "nothing of ours",
    );
    assert_no_mutation(&h, "person's hold only");
}

#[test]
fn success_with_both_holds_clears_only_ours_and_leaves_auto_merge_off() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
        (
            "FAKE_PR_VIEW_LABELS_OUT",
            "dev-deploy-red\ndo-not-automerge",
        ),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    let log = h.log();
    assert_has(
        &log,
        "pr edit 42 --repo owner/repo --remove-label dev-deploy-red\n",
        "ours removed",
    );
    assert_lacks(
        &log,
        "remove-label do-not-automerge",
        "a person's hold is never touched",
    );
    assert_eq!(h.calls("pr merge"), 0, "auto-merge stays off\n{log}");
    assert_has(
        &o.stdout,
        "a person is holding it. Leaving auto-merge off.",
        "says why",
    );
}

#[test]
fn success_without_any_hold_makes_no_mutating_calls() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
        ("FAKE_PR_VIEW_LABELS_OUT", ""),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_no_mutation(&h, "no hold");
}

/// Labels are matched as whole lines: a label merely containing ours is not
/// ours, and a person's label is not mistaken for absent by a prefix match.
#[test]
fn hold_labels_match_whole_lines_only() {
    let h = Hold::new();
    h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
        (
            "FAKE_PR_VIEW_LABELS_OUT",
            "not-dev-deploy-red\ndev-deploy-red-ish",
        ),
    ]);
    assert_no_mutation(&h, "look-alike labels");
}

#[test]
fn failed_rearm_warns_and_still_exits_zero() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("success")),
        ("FAKE_PR_VIEW_LABELS_OUT", "dev-deploy-red"),
        ("FAKE_MERGE_RC", "1"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "::warning title=auto-merge not re-enabled::could not re-enable auto-merge on #42",
        "re-arm failure is loud",
    );
}

// --- red: hold the PR ------------------------------------------------------

#[test]
fn failure_adds_own_label_disables_auto_merge_and_comments() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("failure")),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    let log = h.log();
    assert_has(
        &log,
        &format!("{LABEL_CREATE}\n"),
        "hold label created idempotently",
    );
    assert_has(
        &log,
        "pr edit 42 --repo owner/repo --add-label dev-deploy-red\n",
        "label added",
    );
    assert_lacks(&log, "add-label do-not-automerge", "never a person's label");
    assert_has(
        &log,
        "pr merge 42 --repo owner/repo --disable-auto\n",
        "auto-merge disabled",
    );
    assert_has(&log, "pr comment 42 --repo owner/repo --body ", "commented");
    assert_lacks(&log, "--squash --auto", "never armed while red");
    assert_has(
        &o.stdout,
        "::warning title=release PR held::tabula-api's development deploy concluded 'failure' \u{2014} holding release PR #42 out of auto-merge",
        "held warning",
    );
}

/// The PR comment links the exact run and says how it is released.
#[test]
fn hold_comment_names_component_conclusion_and_run() {
    let h = Hold::new();
    h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("timed_out")),
    ]);
    assert_eq!(
        h.comment(),
        "Held out of auto-merge: `tabula-api`'s development deploy concluded **timed_out** in \
         [run 999](https://github.com/owner/repo/actions/runs/999).\n\nMerging this release would \
         promote an artifact whose development deploy is red, and nonproduction has no reviewer to \
         catch it. This PR is released automatically once development is green again."
    );
}

#[test]
fn every_blocking_conclusion_holds() {
    for c in [
        "failure",
        "cancelled",
        "timed_out",
        "action_required",
        "startup_failure",
    ] {
        let h = Hold::new();
        let o = h.run(&[("FAKE_PR_LIST_OUT", "42"), ("FAKE_RUN_VIEW_OUT", &job(c))]);
        assert_eq!(o.code, 0, "{c}: {o:?}");
        assert_has(
            &h.log(),
            "pr merge 42 --repo owner/repo --disable-auto\n",
            &format!("{c} must hold"),
        );
    }
}

#[test]
fn failed_disable_auto_warns_it_may_still_merge() {
    let h = Hold::new();
    let o = h.run(&[
        ("FAKE_PR_LIST_OUT", "42"),
        ("FAKE_RUN_VIEW_OUT", &job("failure")),
        ("FAKE_MERGE_RC", "1"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "::warning title=auto-merge still enabled::could not disable auto-merge on #42",
        "disable failure is loud",
    );
    assert_eq!(h.calls("pr comment"), 1, "still comments\n{}", h.log());
}

/// An in-progress job reads as "null"; anything not listed leaves the PR alone.
#[test]
fn unrecognised_conclusion_leaves_the_pr_untouched() {
    for c in ["null", "neutral", "stale", "Failure"] {
        let h = Hold::new();
        let o = h.run(&[("FAKE_PR_LIST_OUT", "42"), ("FAKE_RUN_VIEW_OUT", &job(c))]);
        assert_eq!(o.code, 0, "{c}: {o:?}");
        assert_has(&o.stdout, &format!("Unrecognised conclusion '{c}'"), c);
        assert_no_mutation(&h, c);
        assert_eq!(h.calls("pr view"), 0, "{c}: no label lookup\n{}", h.log());
    }
}

// --- matrix source filtering -----------------------------------------------

#[test]
fn source_differing_from_trigger_skips_with_zero_gh_calls() {
    let h = Hold::new();
    let o = h.run(&[
        ("SOURCE", "tabula-deploy"),
        ("TRIGGERED_BY", "oauth-user-inspector-deploy"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(h.log(), "", "no gh calls at all");
    assert_has(&o.stdout, "this entry is for 'tabula-deploy'", "says why");
}

#[test]
fn matching_source_or_a_lone_source_still_evaluates() {
    for ov in [
        vec![
            ("SOURCE", "delivery-tabula"),
            ("TRIGGERED_BY", "delivery-tabula"),
        ],
        vec![("SOURCE", "delivery-tabula")],
        vec![("TRIGGERED_BY", "delivery-tabula")],
    ] {
        let h = Hold::new();
        let mut all = vec![("FAKE_PR_LIST_OUT", "42"), ("FAKE_RUN_VIEW_OUT", "")];
        all.extend(ov.iter().copied());
        h.run(&all);
        assert_eq!(h.calls("pr list"), 1, "{ov:?}\n{}", h.log());
    }
}

// --- required environment --------------------------------------------------

#[test]
fn a_missing_required_variable_fails_before_any_gh_call() {
    for var in ["REPO", "RUN_ID", "DEV_JOB", "COMPONENT"] {
        for how in ["unset", "empty"] {
            let h = Hold::new();
            let r = Run::new(&bin("BIN"))
                .path_first(&h.dir.join("bin"))
                .env("GH_STUB_DIR", h.dir.path())
                .env("REPO", "owner/repo")
                .env("RUN_ID", "999")
                .env("DEV_JOB", DEV_JOB)
                .env("COMPONENT", "tabula-api");
            let r = if how == "unset" {
                r.env_remove(var)
            } else {
                r.env(var, "")
            };
            let o = r.go();
            assert_eq!(o.code, 1, "{var} {how}: {o:?}");
            assert_has(&o.stderr, var, "names the variable");
            assert_eq!(h.log(), "", "{var} {how}: no gh calls");
        }
    }
}
