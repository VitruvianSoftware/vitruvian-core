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

//! Black-box tests for //tools/ci:require_dev_soak, the promotion interlock
//! each generated delivery-<app>.yaml runs before a nonproduction deploy.
//! Runs the REAL binary with a fake `gh` (hermetic: no network, no token).
//! Ported case for case from the former require-dev-soak_test.sh.

use ci_testkit::{assert_has, bin, write, write_exe, Output, Run, TempDir};

/// Behaviour is driven by files in $GH_STUB_DIR, so each case reshapes it:
///   runs.txt        "<id>[\t<status>]" lines for `gh run list` (runs.legacy.txt
///                   for -w legacy.yaml); runs.txt.<n>, if present, answers the
///                   n-th call instead, so a run can finish while the gate waits
///   jobs.<id>       "<name>\t<conclusion>" lines for `gh run view <id>`;
///                   jobs.<id>.<n> answers the n-th view of that run
///   list_rc         forced exit code for `gh run list`
///   api_workflow    what `gh api repos/...` returns; absent = the lookup fails
///   list_argv       written BY the fake: each `gh run list` command line
const FAKE_GH: &str = r#"#!/usr/bin/env bash
W="$GH_STUB_DIR"
case "$1 $2" in
  "api repos"*)
    if [ -f "$W/api_workflow" ]; then cat "$W/api_workflow"; else exit 1; fi
    ;;
  "run list")
    printf '%s\n' "$*" >>"$W/list_argv"
    case " $* " in
      *" -w legacy.yaml "*)
        cat "$W/runs.legacy.txt" 2>/dev/null
        exit 0
        ;;
    esac
    if [ -f "$W/list_rc" ]; then
      echo "simulated gh failure" >&2
      exit "$(cat "$W/list_rc")"
    fi
    n=$(( $(cat "$W/list_count" 2>/dev/null || echo 0) + 1 ))
    echo "$n" >"$W/list_count"
    if [ -f "$W/runs.txt.$n" ]; then cat "$W/runs.txt.$n"; else cat "$W/runs.txt" 2>/dev/null; fi
    ;;
  "run view")
    n=$(( $(cat "$W/view_count.$3" 2>/dev/null || echo 0) + 1 ))
    echo "$n" >"$W/view_count.$3"
    if [ -f "$W/jobs.$3.$n" ]; then
      cat "$W/jobs.$3.$n"
    elif [ -f "$W/jobs.$3" ]; then
      cat "$W/jobs.$3"
    else
      echo "no such run" >&2
      exit 1
    fi
    ;;
  *) echo "unexpected gh invocation: $*" >&2; exit 99 ;;
esac
"#;

const JOB: &str = "deploy-dev / deploy";

struct Gate {
    dir: TempDir,
}

impl Gate {
    fn new() -> Gate {
        let dir = TempDir::new();
        write_exe(dir.join("gh"), FAKE_GH);
        Gate { dir }
    }

    fn file(&self, name: &str, contents: &str) -> &Gate {
        write(self.dir.join(name), contents);
        self
    }

    /// The shell suite's run_gate: a fixed env, then per-case overrides.
    /// Ambient GitHub variables are removed so a CI runner cannot leak in.
    fn run(&self, overrides: &[(&str, &str)]) -> Output {
        let mut r = Run::new(&bin("BIN"))
            .env("GH_STUB_DIR", self.dir.path())
            .env("GH_BIN", self.dir.join("gh"))
            .env("REPO", "acme/repo")
            .env("WORKFLOW_FILE", "tabula-deploy.yaml")
            .env("DEV_JOB_NAME", JOB)
            .env("ALLOW_UNSOAKED", "false")
            .env("SCAN_LIMIT", "20")
            // Poll without sleeping, and bound any wait so a bug cannot hang.
            .env("POLL_SECONDS", "0")
            .env("WAIT_SECONDS", "5")
            .env_remove("LEGACY_WORKFLOW_FILE")
            .env_remove("GITHUB_RUN_ID")
            .env_remove("GITHUB_WORKFLOW_REF")
            .env_remove("GITHUB_REPOSITORY");
        for (k, v) in overrides {
            r = r.env(k, v);
        }
        r.go()
    }
}

fn jobs(lines: &[(&str, &str)]) -> String {
    lines.iter().map(|(n, c)| format!("{n}\t{c}\n")).collect()
}

// --- the core case this gate exists for: development is RED ---------------

#[test]
fn red_dev_deploy_blocks_with_error_naming_the_run() {
    let g = Gate::new();
    g.file("runs.txt", "900\n899\n")
        .file("jobs.900", &jobs(&[("build", "success"), (JOB, "failure")]));
    let o = g.run(&[]);
    assert_eq!(
        o.code,
        1,
        "a failed dev deploy BLOCKS the promotion:\n{}",
        o.all()
    );
    assert_has(
        &o.stdout,
        "::error",
        "blocking emits a GitHub ::error annotation",
    );
    assert_has(
        &o.all(),
        "actions/runs/900",
        "the block names the offending run",
    );
}

// --- the per-app split: legacy history ------------------------------------

#[test]
fn red_in_legacy_workflow_blocks_when_own_has_no_result() {
    let g = Gate::new();
    g.file("runs.txt", "")
        .file("runs.legacy.txt", "700\n")
        .file("jobs.700", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("LEGACY_WORKFLOW_FILE", "legacy.yaml")]);
    assert_eq!(o.code, 1, "legacy red should block:\n{}", o.all());
}

#[test]
fn legacy_history_not_read_without_legacy_workflow_file() {
    let g = Gate::new();
    g.file("runs.txt", "")
        .file("runs.legacy.txt", "700\n")
        .file("jobs.700", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &o.stdout,
        "indeterminate",
        "without LEGACY_WORKFLOW_FILE it is an indeterminate pass",
    );
}

#[test]
fn own_result_wins_over_older_legacy_history() {
    let g = Gate::new();
    g.file("runs.txt", "701\n")
        .file("jobs.701", &jobs(&[(JOB, "success")]))
        .file("runs.legacy.txt", "700\n")
        .file("jobs.700", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("LEGACY_WORKFLOW_FILE", "legacy.yaml")]);
    assert_eq!(
        o.code,
        0,
        "the own green result should decide:\n{}",
        o.all()
    );
}

// --- healthy development promotes ------------------------------------------

#[test]
fn green_dev_deploy_allows_promotion() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "success")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&o.stdout, "succeeded in run 900", "the pass names the run");
}

// --- `skipped` is a PASS, not a failure (the docs/CLI-only trap) ----------

#[test]
fn skipped_dev_deploy_passes() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "skipped")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &o.stdout,
        "was skipped in run 900",
        "skipped is reported as such",
    );
}

// --- newest run decides, not an older green one ---------------------------

#[test]
fn newest_terminal_result_decides() {
    let g = Gate::new();
    g.file("runs.txt", "900\n899\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]))
        .file("jobs.899", &jobs(&[(JOB, "success")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 1, "old green must not mask new red:\n{}", o.all());
}

// --- runs where the job never materialised are skipped, not counted -------

#[test]
fn run_without_the_job_is_not_evidence() {
    let g = Gate::new();
    g.file("runs.txt", "900\n899\n")
        .file("jobs.900", &jobs(&[("build", "success")]))
        .file("jobs.899", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 1, "should skip past the jobless run:\n{}", o.all());
    assert_has(
        &o.all(),
        "actions/runs/899",
        "the block names the run that decided",
    );
}

// --- per-service isolation --------------------------------------------------

#[test]
fn other_services_red_does_not_block() {
    let g = Gate::new();
    g.file("runs.txt", "900\n").file(
        "jobs.900",
        &jobs(&[("deploy-dev-web / deploy", "failure"), (JOB, "success")]),
    );
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "only deploy-dev / deploy matters:\n{}", o.all());
}

// --- fail OPEN on indeterminate --------------------------------------------

#[test]
fn api_failure_fails_open_with_warning() {
    let g = Gate::new();
    g.file("list_rc", "1\n");
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &o.stdout,
        "::warning",
        "the indeterminate path emits a ::warning",
    );
    assert_has(&o.stdout, "rc=1", "the warning carries gh's exit code");
}

#[test]
fn no_run_history_fails_open() {
    let g = Gate::new();
    g.file("runs.txt", "");
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &o.stdout,
        "PASS (indeterminate)",
        "no history is indeterminate",
    );
}

#[test]
fn job_absent_from_scan_window_fails_open() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[("build", "success")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &o.stdout,
        "PASS (indeterminate)",
        "an absent job is indeterminate",
    );
}

// --- break-glass override ---------------------------------------------------

#[test]
fn allow_unsoaked_overrides_red_and_warns() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("ALLOW_UNSOAKED", "true")]);
    assert_eq!(o.code, 0, "the override should pass:\n{}", o.all());
    assert_has(
        &o.stdout,
        "::warning",
        "the override is logged loudly as a ::warning",
    );
}

// --- workflow resolution ----------------------------------------------------

#[test]
fn resolves_workflow_from_run_id_and_blocks_on_red() {
    let g = Gate::new();
    g.file("api_workflow", "oauth-user-inspector-deploy.yaml\n")
        .file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("WORKFLOW_FILE", ""), ("GITHUB_RUN_ID", "4242")]);
    assert_eq!(
        o.code,
        1,
        "the run-id-resolved workflow should be searched:\n{}",
        o.all()
    );
    assert_has(
        &o.stdout,
        "searching oauth-user-inspector-deploy.yaml",
        "logs which workflow history it searched",
    );
}

#[test]
fn explicit_workflow_file_overrides_run_id_resolution() {
    let g = Gate::new();
    g.file("api_workflow", "wrong-workflow.yaml\n")
        .file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("GITHUB_RUN_ID", "4242")]);
    assert_has(
        &o.stdout,
        "searching tabula-deploy.yaml",
        "an explicit WORKFLOW_FILE wins",
    );
}

#[test]
fn unresolvable_workflow_fails_open() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("WORKFLOW_FILE", "")]);
    assert_eq!(o.code, 0, "never a false block:\n{}", o.all());
    assert_has(
        &o.stdout,
        "could not determine",
        "says why it is indeterminate",
    );
}

// --- not in the shell suite: the remaining resolution and input paths ------

#[test]
fn falls_back_to_workflow_ref_basename() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[
        ("WORKFLOW_FILE", ""),
        (
            "GITHUB_WORKFLOW_REF",
            "acme/repo/.github/workflows/delivery-x.yaml@refs/heads/main",
        ),
    ]);
    assert_eq!(o.code, 1, "{}", o.all());
    assert_has(
        &o.stdout,
        "searching delivery-x.yaml on main",
        "the ref basename is used",
    );
}

#[test]
fn missing_dev_job_name_is_an_error() {
    let g = Gate::new();
    let o = g.run(&[("DEV_JOB_NAME", "")]);
    assert_eq!(o.code, 1, "{}", o.all());
    assert_has(
        &o.stderr,
        "DEV_JOB_NAME must name",
        "names the missing input",
    );
}

#[test]
fn unset_repo_fails_open() {
    let g = Gate::new();
    let o = g.run(&[("REPO", "")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&o.stdout, "REPO/GITHUB_REPOSITORY unset", "says why");
}

// --- every blocking conclusion blocks, one test each ------------------------

fn assert_blocks_on(conclusion: &str) {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, conclusion)]));
    let o = g.run(&[]);
    assert_eq!(
        o.code,
        1,
        "a dev deploy that concluded '{conclusion}' must block:\n{}",
        o.all()
    );
    assert_has(
        &o.all(),
        &format!("concluded '{conclusion}'"),
        "the block names the conclusion",
    );
}

#[test]
fn failure_blocks() {
    assert_blocks_on("failure");
}

#[test]
fn cancelled_blocks() {
    assert_blocks_on("cancelled");
}

#[test]
fn timed_out_blocks() {
    assert_blocks_on("timed_out");
}

#[test]
fn action_required_blocks() {
    assert_blocks_on("action_required");
}

#[test]
fn startup_failure_blocks() {
    assert_blocks_on("startup_failure");
}

// --- only the exact value "true" is the break-glass override ----------------

fn assert_no_bypass(value: &str) {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("ALLOW_UNSOAKED", value)]);
    assert_eq!(
        o.code,
        1,
        "ALLOW_UNSOAKED={value:?} must NOT bypass a red dev deploy:\n{}",
        o.all()
    );
    assert!(
        !o.stdout.contains("bypassed"),
        "no bypass warning for {value:?}:\n{}",
        o.all()
    );
}

#[test]
fn allow_unsoaked_upper_case_true_does_not_bypass() {
    assert_no_bypass("TRUE");
}

#[test]
fn allow_unsoaked_one_does_not_bypass() {
    assert_no_bypass("1");
}

#[test]
fn allow_unsoaked_yes_does_not_bypass() {
    assert_no_bypass("yes");
}

#[test]
fn allow_unsoaked_empty_does_not_bypass() {
    assert_no_bypass("");
}

// --- a development deploy still running is waited for, not ignored (#4176) --
// The release commit's own push run deploys development while the release run
// starts; judging an older finished run instead promoted unsoaked code and
// started the promotion's Pulumi applies under the dev deploy's lock.

#[test]
fn running_dev_deploy_is_waited_for_then_its_green_decides() {
    let g = Gate::new();
    g.file("runs.txt.1", "901\tin_progress\n900\tcompleted\n")
        .file("runs.txt", "901\tcompleted\n900\tcompleted\n")
        .file("jobs.901.1", &jobs(&[("build", "success"), (JOB, "")]))
        .file("jobs.901", &jobs(&[("build", "success"), (JOB, "success")]))
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&o.stdout, "waiting", "the gate says it is waiting");
    assert_has(&o.stdout, "succeeded in run 901", "the newest run decides");
}

#[test]
fn running_dev_deploy_that_ends_red_blocks() {
    let g = Gate::new();
    g.file("runs.txt.1", "901\tin_progress\n900\tcompleted\n")
        .file("runs.txt", "901\tcompleted\n900\tcompleted\n")
        .file("jobs.901.1", &jobs(&[(JOB, "")]))
        .file("jobs.901", &jobs(&[(JOB, "failure")]))
        .file("jobs.900", &jobs(&[(JOB, "success")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 1, "{}", o.all());
    assert_has(&o.all(), "actions/runs/901", "the block names the new run");
}

#[test]
fn dev_deploy_still_running_after_the_wait_blocks_as_unsoaked() {
    let g = Gate::new();
    g.file("runs.txt", "901\tin_progress\n900\tcompleted\n")
        .file("jobs.901", &jobs(&[(JOB, "null")]))
        .file("jobs.900", &jobs(&[(JOB, "success")]));
    let o = g.run(&[("WAIT_SECONDS", "0")]);
    assert_eq!(
        o.code,
        1,
        "an older green must not stand in for a deploy still running:\n{}",
        o.all()
    );
    assert_has(&o.all(), "still running in run 901", "the block says why");
}

#[test]
fn running_run_that_has_not_reached_the_dev_job_is_waited_for() {
    let g = Gate::new();
    g.file("runs.txt.1", "902\tqueued\n900\tcompleted\n")
        .file("runs.txt", "902\tcompleted\n900\tcompleted\n")
        .file("jobs.902.1", &jobs(&[("orchestrate", "")]))
        .file(
            "jobs.902",
            &jobs(&[("orchestrate", "success"), (JOB, "skipped")]),
        )
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &o.stdout,
        "was skipped in run 902",
        "the newest run decides",
    );
}

#[test]
fn running_run_whose_dev_job_already_finished_is_evidence() {
    let g = Gate::new();
    g.file("runs.txt", "901\tin_progress\n900\tcompleted\n")
        .file("jobs.901", &jobs(&[(JOB, "success"), ("later", "")]))
        .file("jobs.900", &jobs(&[(JOB, "failure")]));
    let o = g.run(&[("WAIT_SECONDS", "0")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&o.stdout, "succeeded in run 901", "no wait needed");
}

// --- the run-history query keeps its filters --------------------------------
// Only push runs on the branch carry the development deploy; a query without
// these filters reads release or PR runs. Runs still in progress are read too
// (with their status), so the gate can wait for them.

fn list_argv(g: &Gate) -> String {
    std::fs::read_to_string(g.dir.join("list_argv")).unwrap_or_default()
}

#[test]
fn run_list_filters_push_runs_on_main() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "success")]));
    let o = g.run(&[]);
    assert_eq!(o.code, 0, "{}", o.all());
    let argv = format!(" {} ", list_argv(&g).trim());
    for want in [
        " -w tabula-deploy.yaml ",
        " -b main ",
        " -e push ",
        " -L 20 ",
        " --json databaseId,status ",
    ] {
        assert_has(&argv, want, "gh run list must pass this filter");
    }
    assert!(
        !argv.contains(" -s completed "),
        "reading only completed runs ignores a deploy still running: {argv}"
    );
}

#[test]
fn run_list_uses_the_configured_branch() {
    let g = Gate::new();
    g.file("runs.txt", "900\n")
        .file("jobs.900", &jobs(&[(JOB, "success")]));
    let o = g.run(&[("BRANCH", "release-1")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &list_argv(&g),
        " -b release-1 ",
        "BRANCH reaches gh run list",
    );
}
