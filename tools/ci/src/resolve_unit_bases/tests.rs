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

//! Black-box guard for //tools/ci:resolve_unit_bases (#1842). Stubs only
//! `gh`; the real workflow parsing and the real two-pass reduction run.

use ci_testkit::{assert_has, bin, read, write, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};

// A workflow shaped like a generated delivery-<app>.yaml: two units where one
// name is a prefix of the other, a helper job gated on NO affected_* (the
// changelog trap), and a release-gated rung that must not count as a push-lane
// delivery.
const WF: &str = "jobs:
  orchestrate:
    if: github.event_name == 'push'
    outputs:
      affected_app: ${{ steps.m.outputs.affected_app }}
      affected_app_identity: ${{ steps.m.outputs.affected_app_identity }}
  app-changelog:
    if: vars.X == 'true' && github.event_name == 'push'
  app-build:
    if: github.event_name == 'push' && needs.orchestrate.outputs.affected_app == 'true'
  app-development:
    if: github.event_name == 'push' && needs.orchestrate.outputs.affected_app == 'true'
  app-production:
    if: github.event_name == 'release'
  app-identity-development:
    if: github.event_name == 'push' && needs.orchestrate.outputs.affected_app_identity == 'true'
";

// RUNS is "id sha" lines (newest first); JOBS_<id> is "conclusion<TAB>name"
// lines. Every argv is logged to GH_ARGV.
const FAKE_GH: &str = r#"#!/usr/bin/env bash
echo "$*" >> "${GH_ARGV:-/dev/null}"
if [ "$1" = "run" ]; then
  wf=""; lim=1000
  while [ $# -gt 0 ]; do
    case "$1" in -w) wf="$2" ;; -L) lim="$2" ;; esac
    shift
  done
  if [ "$wf" = "legacy.yaml" ]; then
    [ "${LEGACY_RC:-0}" = "0" ] || exit 1
    printf '%s\n' "${LEGACY_RUNS:-}" | grep . | head -n "$lim"
  else
    printf '%s\n' "$RUNS" | grep . | head -n "$lim"
  fi
  exit 0
fi
if [ "$1" = "api" ]; then
  id="$(sed -n 's#.*/runs/\([0-9]*\)/jobs.*#\1#p' <<<"$2")"
  var="JOBS_${id}"; printf '%s\n' "${!var}" | awk -F'\t' '$1=="success"{print $2}'
  exit 0
fi
exit 1
"#;

const FAILING_GH: &str = "#!/usr/bin/env bash\nexit 1\n";

struct Fx {
    work: TempDir,
    gh: PathBuf,
}

impl Fx {
    fn new(gh_script: &str) -> Fx {
        let work = TempDir::new();
        let gh = work.join("gh");
        write_exe(&gh, gh_script);
        Fx { work, gh }
    }

    /// A repo dir holding the workflow at .github/workflows/wf.yaml.
    fn repo(&self, name: &str, wf: &str) -> PathBuf {
        let d = self.work.join(name);
        write(d.join(".github/workflows/wf.yaml"), wf);
        d
    }

    fn base(&self) -> Run {
        Run::new(&bin("BIN"))
            .env("GH_BIN", &self.gh)
            .env("REPO", "o/r")
            .env("GITHUB_REPOSITORY", "")
            .env("WORKFLOW_FILE", "wf.yaml")
            .env("WORKFLOW_PATH", ".github/workflows/wf.yaml")
            .env("LOOKBACK", "10")
            .env("GITHUB_OUTPUT", "/dev/null")
            .env_remove("LEGACY_WORKFLOW_FILE")
            .env_remove("LEGACY_RUNS")
    }

    /// Runs in `dir` and returns the echoed unit_bases JSON.
    fn run(&self, dir: &Path, envs: &[(&str, &str)]) -> String {
        let mut r = self.base().cwd(dir);
        for (k, v) in envs {
            r = r.env(k, v);
        }
        json(&r.go())
    }
}

/// The JSON from `resolve-unit-bases: unit_bases=<json> (<reason>)`.
fn json(o: &Output) -> String {
    for l in o.all().lines() {
        if let Some(rest) = l.strip_prefix("resolve-unit-bases: unit_bases=") {
            if let Some(i) = rest.find(" (") {
                return rest[..i].to_string();
            }
        }
    }
    panic!("no unit_bases line: {o:?}");
}

const SCENARIO1: &[(&str, &str)] = &[
    ("RUNS", "200 shaNEW\n100 shaOLD"),
    (
        "JOBS_200",
        "success\tapp-changelog\nsuccess\tapp-identity-development\nskipped\tapp-build\nskipped\tapp-development",
    ),
    (
        "JOBS_100",
        "success\tapp-build\nsuccess\tapp-development\nsuccess\tapp-identity-development",
    ),
];

#[test]
fn a_units_base_is_its_laggiest_rung_not_the_run_head() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r1", WF);
    let got = fx.run(&d, SCENARIO1);
    assert_has(
        &got,
        r#""app":"shaOLD""#,
        "app pinned to the older delivery",
    );
}

#[test]
fn a_helper_job_gated_on_no_affected_cannot_advance_a_unit() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r1", WF);
    let got = fx.run(&d, SCENARIO1);
    assert!(!got.contains(r#""app":"shaNEW""#), "changelog trap: {got}");
}

#[test]
fn the_identity_unit_advances_on_its_own_delivery() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r1", WF);
    let got = fx.run(&d, SCENARIO1);
    assert_has(&got, r#""app-identity":"shaNEW""#, "identity unit");
}

#[test]
fn only_the_delivering_unit_advances() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r1", WF);
    let got = fx.run(&d, SCENARIO1);
    assert_eq!(
        got.matches("shaNEW").count(),
        1,
        "prefix boundary leaked: {got}"
    );
    // The exact object, keys in sorted unit order.
    assert_eq!(got, r#"{"app":"shaOLD","app-identity":"shaNEW"}"#);
}

#[test]
fn affected_app_does_not_absorb_affected_app_identity() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r5", WF);
    let got = fx.run(
        &d,
        &[
            ("RUNS", "500 shaNEW\n400 shaOLD"),
            (
                "JOBS_500",
                "success\tapp-build\nsuccess\tapp-development\nskipped\tapp-identity-development",
            ),
            ("JOBS_400", "success\tapp-identity-development"),
        ],
    );
    assert_has(&got, r#""app":"shaNEW""#, "boundary observable");
}

// New (the shell suite never had one unit's rungs last succeed in different
// runs, so "oldest of the rungs' newest successes" was untested).
#[test]
fn a_unit_is_only_as_current_as_its_laggiest_rung() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r11", WF);
    let got = fx.run(
        &d,
        &[
            ("RUNS", "300 shaNEW\n200 shaMID\n100 shaOLD"),
            (
                "JOBS_300",
                "success\tapp-build\nsuccess\tapp-identity-development",
            ),
            ("JOBS_200", "success\tapp-development\nsuccess\tapp-build"),
            ("JOBS_100", "success\tapp-development"),
        ],
    );
    // build last delivered at shaNEW, development at shaMID: app is at shaMID.
    assert_eq!(got, r#"{"app":"shaMID","app-identity":"shaNEW"}"#);
}

#[test]
fn a_unit_with_an_unsucceeded_rung_is_omitted() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r2", WF);
    let got = fx.run(
        &d,
        &[("RUNS", "300 shaX"), ("JOBS_300", "success\tapp-build")],
    );
    assert!(!got.contains(r#""app""#), "app must be omitted: {got}");
}

const SPLIT: &[(&str, &str)] = &[
    ("RUNS", "700 shaNEW"),
    (
        "JOBS_700",
        "success\tapp-identity-development\nskipped\tapp-build\nskipped\tapp-development",
    ),
    ("LEGACY_RUNS", "600 shaLEG\n550 shaOLDER"),
    ("JOBS_600", "success\tapp-build\nsuccess\tapp-development"),
    ("JOBS_550", "success\tapp-identity-development"),
];

fn with<'a>(base: &[(&'a str, &'a str)], extra: &[(&'a str, &'a str)]) -> Vec<(&'a str, &'a str)> {
    base.iter().chain(extra.iter()).copied().collect()
}

#[test]
fn a_unit_last_delivered_by_the_legacy_workflow_keeps_that_base() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r6", WF);
    let got = fx.run(&d, &with(SPLIT, &[("LEGACY_WORKFLOW_FILE", "legacy.yaml")]));
    assert_has(&got, r#""app":"shaLEG""#, "legacy base");
}

#[test]
fn the_new_workflows_own_runs_stay_newest() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r6", WF);
    let mut r = fx.base().cwd(&d);
    for (k, v) in with(SPLIT, &[("LEGACY_WORKFLOW_FILE", "legacy.yaml")]) {
        r = r.env(k, v);
    }
    let o = r.go();
    assert_has(&json(&o), r#""app-identity":"shaNEW""#, "own run first");
    assert_has(
        &o.stdout,
        "push runs of wf.yaml, then legacy.yaml)",
        "source note",
    );
}

#[test]
fn without_legacy_workflow_file_the_legacy_history_is_not_read() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r6", WF);
    let got = fx.run(&d, SPLIT);
    assert!(!got.contains(r#""app""#), "{got}");
}

#[test]
fn the_legacy_fill_only_tops_the_window_up_to_lookback() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r6", WF);
    let argv = fx.work.join("argv");
    let got = fx.run(
        &d,
        &with(
            SPLIT,
            &[
                ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
                ("LOOKBACK", "1"),
                ("GH_ARGV", &argv.to_string_lossy()),
            ],
        ),
    );
    assert!(!got.contains(r#""app""#), "fill ignored LOOKBACK: {got}");
    assert!(
        !read(&argv).contains("legacy.yaml"),
        "a full window must not query the legacy workflow"
    );
    // With room for 9 more, the legacy query asks for exactly that many.
    let _ = std::fs::remove_file(&argv);
    fx.run(
        &d,
        &with(
            SPLIT,
            &[
                ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
                ("GH_ARGV", &argv.to_string_lossy()),
            ],
        ),
    );
    assert_has(
        &read(&argv),
        "-w legacy.yaml -b main -e push -L 9 ",
        "fill size",
    );
}

#[test]
fn a_legacy_lookup_failure_keeps_the_workflows_own_verdicts() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r6", WF);
    let got = fx.run(
        &d,
        &with(
            SPLIT,
            &[("LEGACY_WORKFLOW_FILE", "legacy.yaml"), ("LEGACY_RC", "1")],
        ),
    );
    assert_has(&got, r#""app-identity":"shaNEW""#, "own verdicts kept");
}

#[test]
fn gh_failure_fails_open_to_an_empty_object() {
    let fx = Fx::new(FAILING_GH);
    let d = fx.repo("r3", WF);
    assert_eq!(fx.run(&d, &[]), "{}");
}

#[test]
fn a_missing_workflow_fails_open_to_an_empty_object() {
    let fx = Fx::new(FAILING_GH);
    let d = fx.work.join("r4");
    std::fs::create_dir_all(&d).unwrap();
    let o = fx.base().cwd(&d).env("WORKFLOW_PATH", "nope.yaml").go();
    assert_eq!(json(&o), "{}");
    assert_has(&o.stdout, "(workflow nope.yaml not readable)", "reason");
}

#[test]
fn repo_unset_fails_open_without_calling_gh() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r7", WF);
    let argv = fx.work.join("argv");
    let o = fx.base().cwd(&d).env("REPO", "").env("GH_ARGV", &argv).go();
    assert_eq!(json(&o), "{}");
    assert_has(&o.stdout, "REPO/GITHUB_REPOSITORY unset", "reason");
    assert_eq!(read(&argv), "");
}

#[test]
fn missing_workflow_file_is_a_caller_bug() {
    let fx = Fx::new(FAKE_GH);
    let o = fx.base().env_remove("WORKFLOW_FILE").go();
    assert_eq!(o.code, 1, "{o:?}");
    assert_has(&o.stderr, "WORKFLOW_FILE must be set", "message");
}

#[test]
fn queries_push_runs_and_successful_jobs_with_the_scripts_arguments() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r8", WF);
    let argv = fx.work.join("argv");
    fx.run(
        &d,
        &with(SCENARIO1, &[("GH_ARGV", &argv.to_string_lossy())]),
    );
    let log = read(&argv);
    assert_has(
        &log,
        r#"run list --repo o/r -w wf.yaml -b main -e push -L 10 --json databaseId,headSha --jq .[] | "\(.databaseId) \(.headSha)""#,
        "run list",
    );
    assert_has(
        &log,
        r#"api /repos/o/r/actions/runs/200/jobs --paginate --jq .jobs[] | select(.conclusion=="success") | .name"#,
        "jobs api",
    );
}

#[test]
fn writes_unit_bases_to_github_output_and_strips_reusable_job_suffixes() {
    let fx = Fx::new(FAKE_GH);
    // A digit-first job id is still a job (awk's [a-z0-9] first char).
    let wf = WF.replace(
        "  app-identity-development:",
        "  9app-identity-development:",
    );
    let d = fx.repo("r9", &wf);
    let out = fx.work.join("gh_output");
    let o = fx
        .base()
        .cwd(&d)
        .env("GITHUB_OUTPUT", &out)
        .env("RUNS", "200 shaNEW")
        .env(
            "JOBS_200",
            "success\tapp-build / deploy\nsuccess\tapp-development / inner / x\nsuccess\t9app-identity-development",
        )
        .go();
    assert_eq!(o.code, 0);
    assert_eq!(
        read(&out),
        "unit_bases={\"app\":\"shaNEW\",\"app-identity\":\"shaNEW\"}\n"
    );
}

#[test]
fn bazel_run_acts_from_the_callers_directory() {
    let fx = Fx::new(FAKE_GH);
    let d = fx.repo("r10", WF);
    let in_dir = fx.run(&d, SCENARIO1);
    let elsewhere = TempDir::new();
    let mut r = fx
        .base()
        .cwd(elsewhere.path())
        .env("BUILD_WORKING_DIRECTORY", &d);
    for (k, v) in SCENARIO1 {
        r = r.env(k, v);
    }
    let via_bazel_run = json(&r.go());
    assert_eq!(via_bazel_run, in_dir);
    assert_eq!(via_bazel_run, r#"{"app":"shaOLD","app-identity":"shaNEW"}"#);
}
