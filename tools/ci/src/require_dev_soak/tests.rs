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
///   runs.txt        run ids for `gh run list` (runs.legacy.txt for -w legacy.yaml)
///   jobs.<id>       "<name>\t<conclusion>" lines for `gh run view <id>`
///   list_rc         forced exit code for `gh run list`
///   api_workflow    what `gh api repos/...` returns; absent = the lookup fails
const FAKE_GH: &str = r#"#!/usr/bin/env bash
W="$GH_STUB_DIR"
case "$1 $2" in
  "api repos"*)
    if [ -f "$W/api_workflow" ]; then cat "$W/api_workflow"; else exit 1; fi
    ;;
  "run list")
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
    cat "$W/runs.txt" 2>/dev/null
    ;;
  "run view")
    if [ -f "$W/jobs.$3" ]; then
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
