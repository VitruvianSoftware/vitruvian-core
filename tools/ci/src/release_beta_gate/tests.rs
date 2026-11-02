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

//! Black-box tests for //tools/ci:release_beta_gate, which keeps a
//! component's release PR out of auto-merge until the push rung that builds
//! its artifact succeeded for the exact code the release would tag.
//! Runs the REAL binary with a fake `gh` (hermetic: no network, no token).
//! Ported case for case from the former release-beta-gate_test.sh, plus the
//! cases that suite never covered (required env, every holding conclusion,
//! the exact gh argument lists, a refused enable).

use ci_testkit::{assert_has, assert_lacks, bin, read, write, write_exe, Output, Run, TempDir};

/// Answers each lookup from fixture files in $FX and logs every invocation
/// to $FAKE_GH_LOG. A fixture holds what the real call's --jq would print; a
/// missing one prints nothing, and a `<name>.rc` file makes that call fail.
/// `merge.rc` / `disable.rc` make `pr merge --squash --auto` /
/// `pr merge --disable-auto` fail. `label create` prints noise on both
/// streams, which the gate must discard.
const FAKE_GH: &str = r#"#!/usr/bin/env bash
echo "$*" >> "${FAKE_GH_LOG}"
answer() { # <fixture name>
  if [ -f "${FX}/$1.rc" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
  [ -f "${FX}/$1" ] && cat "${FX}/$1"
  exit 0
}
case "$1 $2" in
  "pr list") answer prs ;;
  "pr view") answer comments ;;
  "pr merge")
    case " $* " in
      *" --disable-auto "*) [ -f "${FX}/disable.rc" ] && exit 1 ;;
      *" --auto "*) [ -f "${FX}/merge.rc" ] && exit 1 ;;
    esac
    exit 0
    ;;
  "label create") echo "LABEL-CREATE-STDOUT"; echo "LABEL-CREATE-STDERR" >&2; exit 0 ;;
  "pr edit" | "pr comment") exit 0 ;;
  api\ *)
    path="$2"
    case "$path" in
      */commits/*) answer parent ;;
      */commits\?sha=*)
        sha="${path#*commits?sha=}"
        answer "code.${sha%%&*}"
        ;;
      */actions/workflows/legacy.yaml/*head_sha=*) answer ownruns.legacy ;;
      */actions/workflows/legacy.yaml/*) answer runs.legacy ;;
      */actions/workflows/*head_sha=*) answer ownruns ;;
      */actions/workflows/*) answer runs ;;
      */actions/runs/*/jobs*)
        id="${path#*actions/runs/}"
        answer "jobs.${id%%/*}"
        ;;
      *) echo "unexpected fake gh api path: $path" >&2; exit 99 ;;
    esac
    ;;
  *) echo "unexpected fake gh invocation: $*" >&2; exit 99 ;;
esac
"#;

struct Gate {
    dir: TempDir,
}

/// What one run did: the binary's output plus every gh command line.
struct Ran {
    o: Output,
    log: String,
}

impl Ran {
    fn show(&self) -> String {
        format!(
            "exit {}\n--- stdout\n{}--- stderr\n{}--- gh log\n{}",
            self.o.code, self.o.stdout, self.o.stderr, self.log
        )
    }
    fn line(&self, exact: &str) -> bool {
        self.log.lines().any(|l| l == exact)
    }
    fn starts(&self, prefix: &str) -> bool {
        self.log.lines().any(|l| l.starts_with(prefix))
    }
    fn logged(&self, needle: &str) -> bool {
        self.log.contains(needle)
    }
    fn enabled(&self) -> bool {
        self.line("pr merge 42 --repo owner/repo --squash --auto")
    }
    fn disabled(&self) -> bool {
        self.line("pr merge 42 --repo owner/repo --disable-auto")
    }
    fn commented(&self) -> bool {
        self.starts("pr comment 42")
    }
    fn mutated(&self) -> bool {
        self.starts("pr edit") || self.starts("pr merge") || self.starts("pr comment")
    }
    fn code(&self, want: i32) {
        assert_eq!(self.o.code, want, "exit code\n{}", self.show());
    }
    fn yes(&self, cond: bool, what: &str) {
        assert!(cond, "{what}\n{}", self.show());
    }
}

/// beta(status, conclusion): a run's jobs with vitruvian-beta in that state.
fn beta(status: &str, conclusion: &str) -> String {
    format!("orchestrate\tcompleted\tsuccess\nvitruvian-beta\t{status}\t{conclusion}")
}

impl Gate {
    /// The shell suite's `fresh`: a release PR (#42, head1, not draft,
    /// auto-merge off, no labels) on main commit main9, whose app code is app5.
    fn fresh() -> Gate {
        let dir = TempDir::new();
        write_exe(dir.join("bin/gh"), FAKE_GH);
        let g = Gate { dir };
        g.fx("prs", "42\thead1\tfalse\tfalse\t")
            .fx("parent", "main9")
            .fx("code.main9", "app5");
        g
    }

    fn fx(&self, name: &str, contents: &str) -> &Gate {
        write(self.dir.join("fx").join(name), contents);
        self
    }

    fn fail(&self, name: &str) -> &Gate {
        self.fx(&format!("{name}.rc"), "")
    }

    fn run(&self, extra: &[(&str, &str)]) -> Ran {
        let log = self.dir.join("log");
        write(&log, "");
        let mut r = Run::new(&bin("BIN"))
            .path_first(&self.dir.join("bin"))
            .env("GH_TOKEN", "x")
            .env("FAKE_GH_LOG", &log)
            .env("FX", self.dir.join("fx"))
            .env("REPO", "owner/repo")
            .env("COMPONENT", "vitruvian")
            .env("CODE_PATH", "apps/desktop/vitruvian")
            .env("BETA_JOB", "vitruvian-beta")
            .env("WORKFLOW", "delivery.yaml")
            .env_remove("LEGACY_WORKFLOW");
        for (k, v) in extra {
            r = r.env(k, v);
        }
        let o = r.go();
        Ran { o, log: read(&log) }
    }
}

// --- which run counts -------------------------------------------------------

#[test]
fn reads_parent_then_last_app_commit_then_its_push_run() {
    let g = Gate::fresh();
    g.fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        r.starts("api repos/owner/repo/commits/head1 "),
        "reads the release commit",
    );
    r.yes(
        r.starts("api repos/owner/repo/commits?sha=main9&path=apps/desktop/vitruvian&per_page=1 "),
        "reads the last app commit at the parent",
    );
    r.yes(
        r.starts("api repos/owner/repo/actions/workflows/delivery.yaml/runs?event=push&branch=main&per_page=20 "),
        "lists the newest push runs",
    );
    r.yes(
        r.starts("api repos/owner/repo/actions/runs/901/jobs"),
        "reads the run's jobs",
    );
    r.yes(r.enabled(), "enables auto-merge");
}

#[test]
fn later_same_code_run_counts_newer_app_change_does_not() {
    // 903 is a newer app change (app7) the PR is not built on, 902 coalesced
    // app5 (same code), 901 is app5's own run (cancelled), 900 is older.
    let g = Gate::fresh();
    g.fx("runs", "903\tmain11\n902\tmain10\n901\tapp5\n900\tapp4")
        .fx("code.main11", "app7")
        .fx("code.main10", "app5")
        .fx("jobs.903", &beta("completed", "failure"))
        .fx("jobs.902", &beta("completed", "success"))
        .fx("jobs.901", &beta("completed", "cancelled"))
        .fx("code.main", "app7");
    let r = g.run(&[]);
    r.code(0);
    r.yes(r.enabled(), "enables auto-merge");
    r.yes(
        !r.logged("runs/903/jobs"),
        "a newer app change's run is not read",
    );
    assert_has(
        &r.o.stdout,
        "succeeded for app5 in run 902",
        "credits the coalesced run",
    );
}

#[test]
fn skipped_beta_defers_to_older_same_code_run() {
    let g = Gate::fresh();
    g.fx("runs", "902\tmain10\n901\tapp5\n900\tapp4")
        .fx("code.main10", "app5")
        .fx("jobs.902", &beta("completed", "skipped"))
        .fx("jobs.901", &beta("completed", "success"))
        .fx("jobs.900", &beta("completed", "failure"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(r.enabled(), "enables auto-merge");
    r.yes(
        !r.logged("runs/900/jobs"),
        "stops at the code commit's own run",
    );
}

#[test]
fn reads_nothing_older_than_the_code_commits_own_run() {
    let g = Gate::fresh();
    g.fx("runs", "902\tmain10\n901\tapp5\n900\tapp4")
        .fx("code.main10", "app5")
        .fx("jobs.902", &beta("completed", "skipped"))
        .fx("jobs.901", &beta("completed", "cancelled"))
        .fx("jobs.900", &beta("completed", "failure"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.enabled(), "does not enable auto-merge");
    r.yes(
        !r.logged("sha=app4") && !r.logged("runs/900/"),
        "nothing older is read",
    );
}

#[test]
fn code_commit_older_than_the_window_is_judged_by_its_own_run() {
    let g = Gate::fresh();
    g.fx("runs", "905\tmain14\n904\tmain13")
        .fx("code.main14", "app5")
        .fx("code.main13", "app5")
        .fx("jobs.904", &beta("completed", "skipped"))
        .fx("jobs.905", &beta("completed", "skipped"))
        .fx("ownruns", "901")
        .fx("jobs.901", &beta("completed", "failure"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        r.starts("api repos/owner/repo/actions/workflows/delivery.yaml/runs?head_sha=app5&event=push&per_page=10 "),
        "looks the code commit's runs up by sha",
    );
    r.yes(r.commented() && !r.enabled(), "holds on the red own run");
}

#[test]
fn by_sha_lookup_skipped_when_window_held_the_own_run() {
    let g = Gate::fresh();
    g.fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "cancelled"))
        .fx("ownruns", "901");
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.logged("head_sha="), "no by-sha lookup");
}

#[test]
fn main_still_on_release_code_newer_runs_count_without_lookup() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("runs", "903\tmain12\n902\tmain10\n901\tapp5")
        .fx("jobs.903", &beta("completed", "skipped"))
        .fx("jobs.902", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(r.enabled(), "enables auto-merge");
    r.yes(
        !r.logged("sha=main10&") && !r.logged("sha=main12&"),
        "newer runs need no code lookup of their own",
    );
}

#[test]
fn without_own_run_listed_an_older_build_is_not_credited() {
    // 900 built older code (app4) and is not app5's beta.
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("runs", "900\tmain8\n899\tmain7")
        .fx("code.main8", "app4")
        .fx("jobs.900", &beta("completed", "success"))
        .fx("jobs.899", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.enabled(), "an older build is not credited");
    assert_has(&r.o.stdout, "waiting", "waits");
    r.yes(
        !r.logged("runs/900/jobs") && !r.logged("runs/899/jobs") && !r.logged("sha=main7&"),
        "nothing older is read",
    );
}

// --- code built before the per-app split (LEGACY_WORKFLOW) ------------------

#[test]
fn legacy_run_that_built_older_code_is_not_credited() {
    // 2026-10-13, release 3.47.0: the new workflow's run for app5 had not
    // created its beta job yet, and the legacy workflow's newest run (a week
    // older, green) was credited as app5's build.
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("runs", "905\tapp5")
        .fx("jobs.905", "orchestrate\tin_progress\t")
        .fx("runs.legacy", "801\told2\n800\told1")
        .fx("code.old2", "app1")
        .fx("jobs.801", &beta("completed", "success"))
        .fx("jobs.800", &beta("completed", "success"));
    let r = g.run(&[("LEGACY_WORKFLOW", "legacy.yaml")]);
    r.code(0);
    r.yes(
        !r.enabled(),
        "an old legacy build does not let the release through",
    );
    assert_has(&r.o.stdout, "waiting", "waits");
    r.yes(
        !r.logged("runs/801/jobs") && !r.logged("runs/800/jobs") && !r.logged("sha=old1&"),
        "nothing older is read",
    );
}

#[test]
fn code_the_legacy_workflow_built_is_judged_by_that_run() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("code.main14", "app5")
        .fx("runs", "905\tmain14")
        .fx("jobs.905", &beta("completed", "skipped"))
        .fx("runs.legacy", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[("LEGACY_WORKFLOW", "legacy.yaml")]);
    r.code(0);
    r.yes(r.enabled(), "enables auto-merge");
    r.yes(
        r.logged("actions/workflows/legacy.yaml/runs?event=push"),
        "reads legacy runs",
    );
    assert_has(
        &r.o.stdout,
        "succeeded for app5 in run 901",
        "credits the legacy run",
    );
    assert_has(
        &r.o.stdout,
        "No push delivery.yaml run has run vitruvian-beta for app5; reading legacy.yaml, which ran it before delivery.yaml existed.",
        "says why it reads the legacy workflow",
    );
}

#[test]
fn without_legacy_workflow_the_legacy_history_is_not_read() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("code.main14", "app5")
        .fx("runs", "905\tmain14")
        .fx("jobs.905", &beta("completed", "skipped"))
        .fx("runs.legacy", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        !r.enabled() && !r.logged("legacy.yaml"),
        "legacy is not read; the PR waits",
    );
}

#[test]
fn legacy_equal_to_workflow_is_not_read_twice() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("code.main14", "app5")
        .fx("runs", "905\tmain14")
        .fx("jobs.905", &beta("completed", "skipped"));
    let r = g.run(&[("LEGACY_WORKFLOW", "delivery.yaml")]);
    r.code(0);
    let listings = r
        .log
        .lines()
        .filter(|l| {
            l.starts_with("api repos/owner/repo/actions/workflows/delivery.yaml/runs?event=push")
        })
        .count();
    assert_eq!(listings, 1, "one listing of delivery.yaml\n{}", r.show());
    assert_lacks(&r.o.stdout, "reading delivery.yaml", "no legacy pass");
}

#[test]
fn beta_still_running_in_new_workflow_is_waited_for() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("code.main14", "app5")
        .fx("runs", "905\tmain14")
        .fx("jobs.905", &beta("in_progress", ""))
        .fx("runs.legacy", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[("LEGACY_WORKFLOW", "legacy.yaml")]);
    r.code(0);
    r.yes(!r.enabled(), "does not enable auto-merge");
    assert_has(
        &r.o.stdout,
        "vitruvian-beta for app5 is still running in run 905",
        "waits on 905",
    );
    r.yes(!r.logged("legacy.yaml"), "legacy history is not read");
}

#[test]
fn new_workflows_decision_wins_over_legacy_history() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("code.main14", "app5")
        .fx("runs", "905\tmain14")
        .fx("jobs.905", &beta("completed", "failure"))
        .fx("runs.legacy", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[("LEGACY_WORKFLOW", "legacy.yaml")]);
    r.code(0);
    r.yes(
        !r.enabled() && r.commented(),
        "holds on the new workflow's red",
    );
    r.yes(!r.logged("legacy.yaml"), "legacy history is not read");
}

#[test]
fn legacy_workflow_is_searched_by_sha_too() {
    let g = Gate::fresh();
    g.fx("code.main", "app5")
        .fx("runs", "")
        .fx("runs.legacy", "903\tmain12")
        .fx("jobs.903", &beta("completed", "skipped"))
        .fx("ownruns.legacy", "901")
        .fx("jobs.901", &beta("completed", "failure"));
    let r = g.run(&[("LEGACY_WORKFLOW", "legacy.yaml")]);
    r.code(0);
    r.yes(
        r.starts("api repos/owner/repo/actions/workflows/legacy.yaml/runs?head_sha=app5"),
        "legacy by-sha lookup",
    );
    r.yes(r.commented() && !r.enabled(), "holds");
}

// --- success ----------------------------------------------------------------

#[test]
fn green_beta_with_auto_merge_already_on_changes_nothing() {
    let g = Gate::fresh();
    g.fx("prs", "42\thead1\tfalse\ttrue\t")
        .fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.mutated(), "no PR mutation");
    assert_has(&r.o.stdout, "Auto-merge already enabled on #42.", "says so");
}

#[test]
fn green_beta_clears_own_hold_and_enables_auto_merge() {
    let g = Gate::fresh();
    g.fx(
        "prs",
        "42\thead1\tfalse\tfalse\tautorelease: pending,beta-not-built",
    )
    .fx("runs", "901\tapp5")
    .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        r.line("pr edit 42 --repo owner/repo --remove-label beta-not-built"),
        "removes its label",
    );
    r.yes(r.enabled(), "enables auto-merge");
    assert_has(
        &r.o.stdout,
        "Enabling auto-merge on #42; the merge queue merges it on green CI.",
        "says so",
    );
}

#[test]
fn green_beta_leaves_a_persons_hold_on() {
    let g = Gate::fresh();
    g.fx(
        "prs",
        "42\thead1\tfalse\tfalse\tautorelease: pending,do-not-automerge",
    )
    .fx("runs", "901\tapp5")
    .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.mutated(), "nothing touched");
    assert_has(
        &r.o.stdout,
        "a person is holding it",
        "names the person's hold",
    );
}

#[test]
fn both_holds_on_clears_only_its_own() {
    let g = Gate::fresh();
    g.fx(
        "prs",
        "42\thead1\tfalse\tfalse\tbeta-not-built,do-not-automerge",
    )
    .fx("runs", "901\tapp5")
    .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        r.line("pr edit 42 --repo owner/repo --remove-label beta-not-built"),
        "removes its own",
    );
    r.yes(
        !r.logged("remove-label do-not-automerge"),
        "keeps the person's",
    );
    r.yes(!r.enabled(), "auto-merge stays off");
}

#[test]
fn a_label_that_only_contains_the_hold_name_is_not_the_hold() {
    // Labels are matched whole, as `grep -qx` did.
    let g = Gate::fresh();
    g.fx(
        "prs",
        "42\thead1\tfalse\tfalse\tnot-do-not-automerge,beta-not-built-yet",
    )
    .fx("runs", "901\tapp5")
    .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.logged("remove-label"), "no label removed");
    r.yes(r.enabled(), "not mistaken for a person's hold");
}

#[test]
fn draft_release_pr_is_left_for_a_maintainer() {
    let g = Gate::fresh();
    g.fx("prs", "42\thead1\ttrue\tfalse\t")
        .fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.mutated(), "draft untouched");
    assert_has(&r.o.stdout, "is a draft", "says so");
}

#[test]
fn refused_enable_fails_the_run_visibly() {
    let g = Gate::fresh();
    g.fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "success"))
        .fail("merge");
    let r = g.run(&[]);
    r.code(1);
    assert_has(
        &r.o.stdout,
        "::error title=auto-merge not enabled::could not enable auto-merge on #42",
        "names the refusal",
    );
}

// --- failure ----------------------------------------------------------------

#[test]
fn red_beta_holds_disables_and_comments_with_marker() {
    let g = Gate::fresh();
    g.fx("prs", "42\thead1\tfalse\ttrue\t")
        .fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "failure"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        r.line("pr edit 42 --repo owner/repo --add-label beta-not-built"),
        "adds its own label",
    );
    r.yes(
        !r.logged("add-label do-not-automerge"),
        "never adds the person's label",
    );
    r.yes(r.disabled() && !r.enabled(), "disables auto-merge");
    r.yes(
        r.starts("pr comment 42 --repo owner/repo --body <!-- release-beta-gate:app5 -->"),
        "comments with the commit's marker",
    );
    r.yes(
        r.logged("Held out of auto-merge: `vitruvian-beta` concluded **failure** for app5 in [run 901](https://github.com/owner/repo/actions/runs/901)."),
        "comment links the run",
    );
    r.yes(
        r.starts("label create beta-not-built --repo owner/repo --force --color d93f0b --description Held by release-beta-gate"),
        "ensures the label exists",
    );
    assert_has(
        &r.o.stdout,
        "::warning title=release PR held::vitruvian-beta concluded 'failure' for app5",
        "warns",
    );
    assert_lacks(
        &r.o.all(),
        "LABEL-CREATE-",
        "label create output is discarded",
    );
}

#[test]
fn every_failing_conclusion_holds() {
    for c in ["failure", "timed_out", "action_required", "startup_failure"] {
        let g = Gate::fresh();
        g.fx("prs", "42\thead1\tfalse\ttrue\t")
            .fx("runs", "901\tapp5")
            .fx("jobs.901", &beta("completed", c));
        let r = g.run(&[]);
        r.code(0);
        r.yes(
            r.line("pr edit 42 --repo owner/repo --add-label beta-not-built")
                && r.disabled()
                && !r.enabled(),
            &format!("conclusion {c} holds"),
        );
    }
}

#[test]
fn red_beta_already_commented_is_not_commented_again() {
    let g = Gate::fresh();
    g.fx("prs", "42\thead1\tfalse\ttrue\t")
        .fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "failure"))
        .fx(
            "comments",
            "<!-- release-beta-gate:app5 -->\nHeld out of auto-merge",
        );
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.commented() && r.disabled(), "no duplicate comment");
}

#[test]
fn newest_decided_run_wins() {
    let g = Gate::fresh();
    g.fx("runs", "902\tmain10\n901\tapp5")
        .fx("code.main10", "app5")
        .fx("jobs.902", &beta("completed", "success"))
        .fx("jobs.901", &beta("completed", "failure"));
    let r = g.run(&[]);
    r.code(0);
    r.yes(
        r.enabled() && !r.commented(),
        "a later success outweighs an older failure",
    );
}

#[test]
fn a_failed_disable_warns_and_still_holds() {
    let g = Gate::fresh();
    g.fx("prs", "42\thead1\tfalse\ttrue\t")
        .fx("runs", "901\tapp5")
        .fx("jobs.901", &beta("completed", "failure"))
        .fail("disable");
    let r = g.run(&[]);
    r.code(0);
    assert_has(
        &r.o.stdout,
        "::warning title=auto-merge still enabled::could not disable auto-merge on #42",
        "warns",
    );
    r.yes(
        r.line("pr edit 42 --repo owner/repo --add-label beta-not-built"),
        "still labels",
    );
}

// --- waiting ----------------------------------------------------------------

#[test]
fn undecided_beta_turns_auto_merge_off_and_waits() {
    for (name, jobs) in [
        ("running", beta("in_progress", "")),
        ("queued", beta("queued", "")),
        ("cancelled", beta("completed", "cancelled")),
        ("skipped", beta("completed", "skipped")),
        ("absent", "other-job\tcompleted\tsuccess".to_string()),
    ] {
        let g = Gate::fresh();
        g.fx("prs", "42\thead1\tfalse\ttrue\t")
            .fx("runs", "901\tapp5")
            .fx("jobs.901", &jobs);
        let r = g.run(&[]);
        r.code(0);
        r.yes(
            r.disabled() && !r.enabled() && !r.commented() && r.o.stdout.contains("waiting"),
            &format!("beta {name} waits"),
        );
    }
}

#[test]
fn no_run_yet_waits_and_makes_no_calls_with_auto_merge_off() {
    let g = Gate::fresh();
    g.fx("runs", "");
    let r = g.run(&[]);
    r.code(0);
    r.yes(!r.mutated(), "no mutation");
    assert_has(
        &r.o.stdout,
        "No push delivery.yaml run has finished vitruvian-beta for app5 yet",
        "waits",
    );
}

// --- lookup failures never let the PR through --------------------------------

#[test]
fn failed_pr_lookup_fails_visibly() {
    let g = Gate::fresh();
    g.fail("prs");
    let r = g.run(&[]);
    r.code(1);
    assert_has(
        &r.o.stdout,
        "::error title=release-beta-gate indeterminate::could not list",
        "error annotation",
    );
    r.yes(!r.mutated(), "no mutation");
}

#[test]
fn every_failed_lookup_fails_and_turns_auto_merge_off() {
    for broken in [
        "parent",
        "code.main9",
        "runs",
        "code.main",
        "code.main10",
        "jobs.901",
        "ownruns",
    ] {
        let g = Gate::fresh();
        g.fx("prs", "42\thead1\tfalse\ttrue\t")
            .fx("runs", "902\tmain10\n901\tapp5")
            .fx("code.main10", "app5")
            .fx("jobs.902", &beta("completed", "cancelled"))
            .fx("jobs.901", &beta("completed", "success"));
        if broken == "ownruns" {
            g.fx("runs", "902\tmain10").fx("ownruns", "901");
        }
        g.fail(broken);
        let r = g.run(&[]);
        r.code(1);
        r.yes(
            r.disabled() && !r.enabled(),
            &format!("{broken}: auto-merge off"),
        );
        assert_has(
            &r.o.stdout,
            "::error title=release-beta-gate indeterminate::",
            &format!("{broken}: error annotation"),
        );
        assert_has(
            &r.o.stdout,
            "keeping release PR #42 out of auto-merge",
            broken,
        );
    }
}

#[test]
fn empty_parent_or_code_is_indeterminate() {
    for (name, want) in [
        ("parent", "release commit head1 has no parent"),
        (
            "code.main9",
            "no commit at or before main9 touches apps/desktop/vitruvian",
        ),
    ] {
        let g = Gate::fresh();
        g.fx("prs", "42\thead1\tfalse\ttrue\t").fx(name, "");
        let r = g.run(&[]);
        r.code(1);
        assert_has(&r.o.stdout, want, name);
        r.yes(r.disabled() && !r.enabled(), name);
    }
}

#[test]
fn no_open_release_pr_is_one_lookup_and_nothing_else() {
    let g = Gate::fresh();
    g.fx("prs", "");
    let r = g.run(&[]);
    r.code(0);
    assert_eq!(r.log.lines().count(), 1, "one gh call\n{}", r.show());
    assert_has(
        &r.o.stdout,
        "No open release PR on release-please--branches--main--components--vitruvian",
        "says so",
    );
}

#[test]
fn pr_lookup_targets_only_the_components_release_branch() {
    let g = Gate::fresh();
    g.fx("prs", "");
    let r = g.run(&[]);
    r.yes(
        r.line("pr list --repo owner/repo --head release-please--branches--main--components--vitruvian --state open --json number,headRefOid,isDraft,autoMergeRequest,labels,isCrossRepository --jq map(select(.isCrossRepository | not)) | .[0] // empty | \"\\(.number)\\t\\(.headRefOid)\\t\\(.isDraft)\\t\\(.autoMergeRequest != null)\\t\\([.labels[].name] | join(\",\"))\""),
        "exact pr list argv (in-repo PRs only)",
    );
}

// --- required environment -------------------------------------------------

#[test]
fn missing_or_empty_required_env_fails_before_any_gh_call() {
    for var in ["REPO", "COMPONENT", "CODE_PATH", "BETA_JOB", "WORKFLOW"] {
        for unset in [true, false] {
            let g = Gate::fresh();
            let log = g.dir.join("log");
            write(&log, "");
            let mut r = Run::new(&bin("BIN"))
                .path_first(&g.dir.join("bin"))
                .env("FAKE_GH_LOG", &log)
                .env("FX", g.dir.join("fx"))
                .env("REPO", "owner/repo")
                .env("COMPONENT", "vitruvian")
                .env("CODE_PATH", "apps/desktop/vitruvian")
                .env("BETA_JOB", "vitruvian-beta")
                .env("WORKFLOW", "delivery.yaml");
            r = if unset {
                r.env_remove(var)
            } else {
                r.env(var, "")
            };
            let o = r.go();
            assert_eq!(o.code, 1, "{var} unset={unset}: {o:?}");
            assert_has(&o.stderr, &format!("{var} must be set"), var);
            assert_eq!(read(&log), "", "{var}: no gh call");
        }
    }
}
