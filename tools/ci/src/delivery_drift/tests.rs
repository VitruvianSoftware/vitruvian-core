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

//! Black-box tests of //tools/ci:delivery_drift.
//!
//! `gh` and `bazel` are stubbed (there is no GitHub or Bazel in a hermetic
//! test) but the REAL decision engine (//tools/ci:deploy_affected) runs over a
//! real git history, so "the detector and the decider agree about what
//! affected means" is exercised rather than mocked away. A fake `sleep` proves
//! the check never waits, and a fake `python3` proves it no longer needs one.

use ci_testkit::{assert_has, assert_lacks, bin, git, read, write, write_exe, Run, TempDir};
use std::path::PathBuf;

const OAUTH_LABEL: &str = "//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit";
const OTHER_LABEL: &str = "//other/infra:other-unit.delivery_unit";
const NEWER_SHA: &str = "1234567890abcdef1234567890abcdef12345678";

/// The gh stub. It answers `run list` (recent push runs, or a history),
/// `api graphql` pages of runs with their successful jobs, the workflow id
/// lookup and the compare API. Knobs (all env):
///   STUB_RECENT / STUB_RECENT_OTHER  "<id> <status> <sha> <conclusion>" lines
///   STUB_RUNLIST_FAIL, STUB_INFLIGHT, STUB_INFLIGHT_WF, STUB_INFLIGHT_STATUS
///   STUB_POLL_LOG    one line per read of recent runs: "<workflow>"
///   STUB_COMPARE     the compare API's answer (empty => it fails)
///   STUB_DELIVERED_SHA / STUB_DELIVERED_WF  a one-run history "111 <sha>"
///   STUB_RUNS / STUB_LEGACY_RUNS  "<id> <sha>" histories, newest first
///   STUB_HIT_RUNS    run ids whose dev job succeeded
///   STUB_GQL_FAIL, STUB_LOG (workflows queried), STUB_GQL_LOG ("<wf> <after>")
const GH_STUB: &str = r#"#!/usr/bin/env bash
history() {
  if [ "$1" = "delivery.yaml" ] && [ -n "${STUB_LEGACY_RUNS:-}" ]; then printf '%s\n' "$STUB_LEGACY_RUNS"; return; fi
  if [ -n "${STUB_RUNS:-}" ] && [ "$1" != "delivery.yaml" ]; then printf '%s\n' "$STUB_RUNS"; return; fi
  if [ -n "${STUB_RUNS:-}${STUB_LEGACY_RUNS:-}" ]; then return; fi
  if [ -n "${STUB_DELIVERED_WF:-}" ] && [ "$1" != "$STUB_DELIVERED_WF" ]; then return; fi
  [ -z "${STUB_DELIVERED_SHA:-}" ] || echo "111 ${STUB_DELIVERED_SHA}"
}
inflight_n() {
  if [ -n "${STUB_INFLIGHT_WF:-}" ] && [ "$1" != "$STUB_INFLIGHT_WF" ]; then echo 0; return; fi
  echo "${STUB_INFLIGHT:-0}"
}
recent() {
  if [ "$1" = "delivery-other.yaml" ] && [ -n "${STUB_RECENT_OTHER:-}" ]; then printf '%s\n' "$STUB_RECENT_OTHER"; return; fi
  if [ -n "${STUB_RECENT:-}" ]; then printf '%s\n' "$STUB_RECENT"; return; fi
  local n i=0 head
  n="$(inflight_n "$1")"
  head="$(git rev-parse HEAD)"
  while [ "$i" -lt "$n" ]; do echo "90$i ${STUB_INFLIGHT_STATUS:-in_progress} ${head} "; i=$((i + 1)); done
  echo "800 completed ${head} success"
}
hits=" ${STUB_HIT_RUNS:-} "
[ -z "${STUB_DELIVERED_SHA:-}" ] || hits="${hits}111 "
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  wf=""; limit=20; prev=""
  for a in "$@"; do
    [ "$prev" = "--workflow" ] && wf="$a"
    [ "$prev" = "--limit" ] && limit="$a"
    prev="$a"
  done
  echo "$wf" >> "${STUB_LOG:-/dev/null}"
  [ -z "${STUB_RUNLIST_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }
  case "$*" in
    *"headSha"*)
      echo "$wf" >>"${STUB_POLL_LOG:-/dev/null}"
      recent "$wf" | head -n "$limit"; exit 0 ;;
    *) history "$wf" | head -n "$limit"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  [ -z "${STUB_GQL_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }
  id=""; n=100; after=""
  for a in "$@"; do
    case "$a" in id=*) id="${a#id=}" ;; n=*) n="${a#n=}" ;; after=*) after="${a#after=}" ;; esac
  done
  wf="${id#WF:}"
  echo "$wf" >> "${STUB_LOG:-/dev/null}"
  echo "$wf ${after:-start}" >> "${STUB_GQL_LOG:-/dev/null}"
  rows=()
  while read -r line; do [ -z "$line" ] || rows+=("$line"); done < <(history "$wf")
  off=0; [ -z "$after" ] || off="${after#o}"
  nodes=""; i="$off"
  while [ "$i" -lt "$((off + n))" ] && [ "$i" -lt "${#rows[@]}" ]; do
    read -r rid sha <<<"${rows[$i]}"
    jobs=""
    case "$hits" in *" $rid "*) jobs='{"name":"oauth-user-inspector-development / deploy"},' ;; esac
    jobs="${jobs}"'{"name":"orchestrate"}'
    nodes="${nodes}${nodes:+,}{\"databaseId\":${rid},\"checkSuite\":{\"branch\":{\"name\":\"main\"},\"commit\":{\"oid\":\"${sha}\"},\"checkRuns\":{\"nodes\":[${jobs}]}}}"
    i=$((i + 1))
  done
  if [ "$((off + n))" -lt "${#rows[@]}" ]; then more=true; cur="\"o$((off + n))\""; else more=false; cur=null; fi
  printf '{"data":{"node":{"runs":{"pageInfo":{"hasNextPage":%s,"endCursor":%s},"nodes":[%s]}}}}\n' "$more" "$cur" "$nodes"
  exit 0
fi
if [ "$1" = "api" ]; then
  case "$2" in
    repos/*/actions/workflows/*) echo "WF:${2##*/}"; exit 0 ;;
    repos/*/compare/*) [ -n "${STUB_COMPARE:-}" ] || exit 1; echo "$STUB_COMPARE"; exit 0 ;;
  esac
  exit 0
fi
exit 0
"#;

struct Fx {
    work: TempDir,
    repo: PathBuf,
    stubs: PathBuf,
    base: String,
    real: String,
    release: String,
    head: String,
}

struct R {
    code: i32,
    out: String,
    err: String,
    result: String,
    summary: String,
    polls: Vec<String>,
}

impl R {
    fn conclusion_is(&self, want: &str) -> bool {
        self.result
            .lines()
            .any(|l| l == format!("conclusion={want}"))
    }

    #[track_caller]
    fn verdict(&self, code: i32, out: &str, what: &str) {
        assert_eq!(
            (self.code, self.out.as_str()),
            (code, out),
            "{what}\n--- err ---\n{}\n--- result ---\n{}\n--- summary ---\n{}",
            self.err,
            self.result,
            self.summary
        );
    }
}

impl Fx {
    fn new() -> Fx {
        let work = TempDir::new();
        let repo = work.join("repo");
        std::fs::create_dir_all(repo.join("oauth-user-inspector/app")).unwrap();
        git(&repo, &["init", "-q", "."]);
        write(repo.join("tools/ci/.keep"), "");
        git(&repo, &["add", "-A"]);
        git(&repo, &["commit", "-qm", "base"]);
        let base = git(&repo, &["rev-parse", "HEAD"]);
        write(repo.join("oauth-user-inspector/app/index.ts"), "changed\n");
        git(&repo, &["add", "-A"]);
        git(
            &repo,
            &["commit", "-qm", "feat(oauth): a change that must deploy"],
        );
        let real = git(&repo, &["rev-parse", "HEAD"]);
        // A release-please bump: its artifacts match the unit's paths but need
        // no deploy (the code already soaked; releases promote by TAG).
        write(
            repo.join("oauth-user-inspector/package.json"),
            "{\"version\":\"1.2.3\"}\n",
        );
        write(
            repo.join("oauth-user-inspector/.release-please-manifest.json"),
            "{\".\":\"1.2.3\"}\n",
        );
        git(&repo, &["add", "-A"]);
        git(
            &repo,
            &[
                "commit",
                "-qm",
                "chore(main): release oauth-user-inspector 1.2.3",
            ],
        );
        let release = git(&repo, &["rev-parse", "HEAD"]);
        // A real commit that does NOT touch the unit: REAL..HEAD is now MIXED.
        write(repo.join("tools/pulumi/wrapper.sh"), "unrelated\n");
        git(&repo, &["add", "-A"]);
        git(
            &repo,
            &[
                "commit",
                "-qm",
                "fix(pulumi): something unrelated to this unit",
            ],
        );
        let head = git(&repo, &["rev-parse", "HEAD"]);

        // Unit metadata, the shape delivery() emits (untracked, as bazel-bin is).
        write(
            repo.join(
                "bazel-bin/oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json",
            ),
            r#"{"schema":1,"name":"oauth-user-inspector","app":"oauth-user-inspector","kind":"cloud-run",
 "environments":["development","nonproduction","production"],
 "extra_paths":["oauth-user-inspector/"],"exclude_paths":[],"graph_targets":[]}
"#,
        );
        write(
            repo.join("bazel-bin/other/infra/other-unit.delivery.json"),
            r#"{"schema":1,"name":"other-unit","app":"other","kind":"cloud-run",
 "environments":["development"],"extra_paths":["other/"],"exclude_paths":[],"graph_targets":[]}
"#,
        );

        let stubs = work.join("stubs");
        write_exe(
            stubs.join("bazel"),
            format!(
                "#!/usr/bin/env bash\ncase \"$1\" in\n  query) printf '%s\\n' ${{STUB_LABELS:-{OAUTH_LABEL}}} ;;\n  build) exit 0 ;;\n  info)  echo \"{}/bazel-bin\" ;;\nesac\n",
                repo.display()
            ),
        );
        write_exe(stubs.join("gh"), GH_STUB);
        write_exe(
            stubs.join("sleep"),
            "#!/usr/bin/env bash\necho \"sleep $*\" >>\"${STUB_SLEEP_LOG:-/dev/null}\"\n",
        );
        write_exe(
            stubs.join("python3"),
            "#!/usr/bin/env bash\necho \"python3 $*\" >>\"${STUB_PY_LOG:-/dev/null}\"\nexit 1\n",
        );
        Fx {
            work,
            repo,
            stubs,
            base,
            real,
            release,
            head,
        }
    }

    fn p(&self, name: &str) -> PathBuf {
        self.work.join(name)
    }

    fn cmd(&self, inflight: &str, delivered: &str, env: &[(&str, &str)]) -> Run {
        let mut r = Run::new(&bin("BIN"))
            .cwd(&self.repo)
            .env("PATH", format!("{}:/usr/bin:/bin", self.stubs.display()))
            .env("STUB_INFLIGHT", inflight)
            .env("STUB_DELIVERED_SHA", delivered)
            .env("STUB_POLL_LOG", self.p("polls"))
            .env("STUB_SLEEP_LOG", self.p("sleeps"))
            .env("STUB_PY_LOG", self.p("python"))
            .env("DRIFT_RESULT_FILE", self.p("result"))
            .env("DRIFT_SUMMARY_FILE", self.p("summary"))
            .env("REPO", "o/r")
            .env("DEPLOY_AFFECTED_BIN", bin("ENGINE"));
        for k in [
            "WORKFLOW_FILE",
            "LEGACY_WORKFLOW_FILE",
            "BRANCH",
            "RUN_SCAN_LIMIT",
            "DRIFT_PAGE_SIZE",
            "DRIFT_RECENT_RUNS",
            "DRIFT_IGNORE_IN_FLIGHT",
            "BAZEL",
            "GH",
            "TD_BIN",
            "BUILDBUDDY_API_KEY",
        ] {
            r = r.env_remove(k);
        }
        for (k, v) in env {
            r = r.env(k, v);
        }
        r
    }

    fn run(&self, inflight: &str, delivered: &str, env: &[(&str, &str)]) -> R {
        let _ = std::fs::remove_file(self.p("result"));
        let _ = std::fs::remove_file(self.p("summary"));
        std::fs::write(self.p("polls"), "").unwrap();
        let o = self.cmd(inflight, delivered, env).go();
        let r = R {
            code: o.code,
            out: o.stdout.trim().to_string(),
            err: o.stderr,
            result: read(self.p("result")),
            summary: read(self.p("summary")),
            polls: read(self.p("polls")).lines().map(str::to_string).collect(),
        };
        // Across every run: the check never sleeps and never needs python3.
        assert_eq!(read(self.p("sleeps")), "", "the check slept");
        assert_eq!(read(self.p("python")), "", "the check ran python3");
        r
    }

    fn s8(sha: &str) -> &str {
        &sha[..8]
    }
}

fn lines(rows: &[String]) -> String {
    rows.join("\n")
}

// --- drift is detected when a unit is behind main ---------------------------

#[test]
fn drift_is_detected_when_a_unit_is_behind_main() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.base, &[]);
    r.verdict(1, "DRIFT", "last delivery predates an affecting commit");
    assert!(r.conclusion_is("failure"), "{}", r.result);
    assert_has(&r.err, "DRIFT oauth-user-inspector", "names the unit");
    // A genuine miss behind a release commit is still caught, and named.
    assert_has(
        &r.err,
        "should have delivered and did not",
        "names the culprit commit",
    );
    assert_has(
        &r.err,
        &format!(
            "DRIFT oauth-user-inspector: last delivered {}, but {} ('feat(oauth): a change that must deploy') should have delivered and did not -- affected=true (path matched oauth-user-inspector/)",
            Fx::s8(&fx.base),
            Fx::s8(&fx.real)
        ),
        "the full drift line, with the engine's reason",
    );
    assert_eq!(
        r.result,
        "conclusion=failure\ntitle=1 of 1 unit(s) behind main or unknown\nchecked=1\nskipped=0\n"
    );
    assert_has(
        &r.summary,
        &format!(
            "### Checked (1)\n- `oauth-user-inspector`: **DRIFT: last delivered `{}`, but `{}` should have delivered and did not (judged at `{}`)**\n",
            Fx::s8(&fx.base),
            Fx::s8(&fx.real),
            Fx::s8(&fx.head)
        ),
        "summary",
    );
}

#[test]
fn no_drift_when_the_unit_already_has_main() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.head, &[]);
    r.verdict(0, "OK", "delivered at HEAD");
    assert!(r.conclusion_is("success"));
    assert_eq!(
        r.result,
        "conclusion=success\ntitle=1 unit(s) delivered\nchecked=1\nskipped=0\n"
    );
    assert_eq!(
        r.summary,
        format!(
            "**1 unit(s) delivered** (commit `{}`)\n\n### Checked (1)\n- `oauth-user-inspector`: up to date (delivered `{}`)\n\nEach unit is judged at the newest finished delivery run of its app, not at main's tip: newer commits are still being delivered, and a later check judges them.\n",
            Fx::s8(&fx.head),
            Fx::s8(&fx.head)
        )
    );
}

// --- release-please noise is NOT drift ----------------------------------------

#[test]
fn release_noise_in_a_mixed_range_is_not_drift() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.real, &[]);
    r.verdict(
        0,
        "OK",
        "a mixed range whose only matching files are release artifacts",
    );
    assert_has(
        &r.err,
        "only version-bump commits since",
        "phase 2 ran and cleared it",
    );
}

#[test]
fn an_unrelated_real_commit_alone_is_not_drift() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.release, &[]);
    r.verdict(0, "OK", "single unrelated commit");
    assert_has(
        &r.err,
        "nothing since affects it (affected=false (",
        "phase 1 cleared it with the engine's reason",
    );
}

// --- a busy workflow is judged at its newest FINISHED run -------------------------

#[test]
fn busy_workflow_is_judged_at_its_newest_finished_run() {
    let fx = Fx::new();
    let busy = format!(
        "905 in_progress {h} \n904 queued {h} \n903 completed {b} success",
        h = fx.head,
        b = fx.base
    );
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &busy)]);
    r.verdict(0, "OK", "busy, newest finished run at the delivered commit");
    assert!(r.conclusion_is("success"));
    assert_has(
        &r.err,
        &format!("up to date (delivered {})", Fx::s8(&fx.base)),
        "judged",
    );
    assert_has(&r.result, "checked=1\n", "counted as checked");
    assert_has(&r.result, "skipped=0\n", "not skipped");
    assert_has(
        &r.err,
        "2 newer still in flight",
        "names the runs in flight",
    );
}

#[test]
fn busy_workflow_whose_finished_run_skipped_an_affecting_commit_is_drift() {
    let fx = Fx::new();
    let busy = format!(
        "905 in_progress {} \n904 completed {} success",
        fx.head, fx.real
    );
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &busy)]);
    r.verdict(1, "DRIFT", "finished run skipped REAL");
    assert!(r.conclusion_is("failure"));
    assert_has(
        &r.err,
        &format!(
            "DRIFT oauth-user-inspector: last delivered {}, but {}",
            Fx::s8(&fx.base),
            Fx::s8(&fx.real)
        ),
        "blames REAL",
    );
}

#[test]
fn a_failed_run_is_judged_not_passed_over() {
    let fx = Fx::new();
    let recent = format!(
        "904 completed {} failure\n903 completed {} success",
        fx.real, fx.base
    );
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &recent)]);
    r.verdict(1, "DRIFT", "a failed run is evidence");
    assert!(r.conclusion_is("failure"));
}

#[test]
fn a_delivery_newer_than_the_judged_commit_is_up_to_date_by_ancestry() {
    let fx = Fx::new();
    let busy = format!(
        "905 in_progress {h} \n904 queued {h} \n903 completed {b} success",
        h = fx.head,
        b = fx.base
    );
    let r = fx.run("0", &fx.real, &[("STUB_RECENT", &busy)]);
    r.verdict(0, "OK", "ancestry");
    assert_has(
        &r.err,
        &format!(
            "delivered {}, which includes the judged {}",
            Fx::s8(&fx.real),
            Fx::s8(&fx.base)
        ),
        "by ancestry",
    );
}

// --- a cancelled run is neither delivery nor drift -------------------------------------

#[test]
fn a_cancelled_run_is_passed_over() {
    let fx = Fx::new();
    let cancelled = format!(
        "906 queued {h} \n905 completed {h} cancelled\n904 completed {b} success",
        h = fx.head,
        b = fx.base
    );
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &cancelled)]);
    r.verdict(0, "OK", "cancelled run passed over");
    assert_has(
        &r.err,
        &format!("up to date (delivered {})", Fx::s8(&fx.base)),
        "judged before it",
    );
    assert_has(&r.err, "1 newer cancelled", "names the cancelled run");
}

#[test]
fn the_run_that_superseded_a_cancelled_one_is_judged() {
    let fx = Fx::new();
    let forward = format!(
        "906 completed {} success\n905 completed {} cancelled\n904 completed {} success",
        fx.head, fx.real, fx.base
    );
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &forward)]);
    r.verdict(
        1,
        "DRIFT",
        "superseding run covers the cancelled run's commits",
    );
    assert_has(&r.err, &format!("but {}", Fx::s8(&fx.real)), "blames REAL");
    let r = fx.run("0", &fx.head, &[("STUB_RECENT", &forward)]);
    r.verdict(0, "OK", "and when it delivered, up to date");
}

// --- a run that checked nothing is NEUTRAL, not a pass ------------------------------------

fn unfinished(fx: &Fx) -> String {
    format!(
        "903 in_progress {h} \n902 completed {h} cancelled\n901 queued {b} ",
        h = fx.head,
        b = fx.base
    )
}

#[test]
fn no_finished_run_is_nothing_checked() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &unfinished(&fx))]);
    r.verdict(0, "NOTHING_CHECKED", "no finished run");
    assert!(r.conclusion_is("neutral"));
    assert_has(&r.result, "Nothing checked", "title");
    assert_has(&r.summary, "oauth-user-inspector", "names the unit");
    assert_has(&r.summary, "no finished push run", "says why");
    assert_has(&r.summary, "2 in flight, 1 cancelled", "counts");
    assert_has(
        &r.summary,
        "This is not a pass: no unit was judged. Every one was skipped, for the reason given below.",
        "not a pass",
    );
    assert_has(&r.summary, "### Not checked (1)\n", "section");
    assert_lacks(
        &r.summary,
        "Each unit is judged",
        "the judged-commit note only follows a check",
    );
    assert_lacks(
        &r.err,
        "should have delivered and did not",
        "mid-convergence is not drift",
    );
}

#[test]
fn a_run_parked_on_an_approval_leaves_its_units_unchecked() {
    let fx = Fx::new();
    let recent = format!(
        "905 waiting {} \n904 completed {} success",
        fx.head, fx.base
    );
    let r = fx.run("0", &fx.base, &[("STUB_RECENT", &recent)]);
    r.verdict(0, "NOTHING_CHECKED", "waiting run");
    assert!(r.conclusion_is("neutral"));
    assert_has(&r.summary, "waiting on an approval", "reason");
    assert_has(
        &r.summary,
        "run 905 of `delivery-oauth-user-inspector.yaml` is waiting on an approval",
        "names the run",
    );

    let r = fx.run("1", &fx.base, &[("STUB_INFLIGHT_STATUS", "waiting")]);
    assert_eq!(r.out, "NOTHING_CHECKED");
    assert_eq!(
        r.polls.len(),
        1,
        "a waiting run is read once, not polled: {:?}",
        r.polls
    );
}

// --- nothing waits: one read per workflow -------------------------------------------------

#[test]
fn a_busy_shared_workflow_is_read_once() {
    let fx = Fx::new();
    let labels = format!("{OAUTH_LABEL} {OTHER_LABEL}");
    let r = fx.run(
        "3",
        &fx.head,
        &[
            ("STUB_LABELS", &labels),
            ("WORKFLOW_FILE", "delivery-shared.yaml"),
        ],
    );
    assert!(r.result.lines().any(|l| l == "checked=2"), "{}", r.result);
    assert_eq!(
        r.polls,
        vec!["delivery-shared.yaml".to_string()],
        "exactly one read"
    );
}

// --- failed and partial reads ---------------------------------------------------------------

#[test]
fn a_failed_read_of_recent_runs_is_unknown() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.head, &[("STUB_RUNLIST_FAIL", "1")]);
    r.verdict(1, "DRIFT", "failed run-list read");
    assert!(r.conclusion_is("failure"));
    assert_has(&r.err, "could not read the recent runs", "reason");
}

#[test]
fn a_finished_run_newer_than_this_checkout() {
    let fx = Fx::new();
    let recent = format!("800 completed {NEWER_SHA} success");
    let r = fx.run(
        "0",
        &fx.head,
        &[("STUB_RECENT", &recent), ("STUB_COMPARE", "ahead")],
    );
    r.verdict(0, "OK", "newer run that contains the checkout");
    assert_has(&r.err, "judged at the checkout", "reason");

    let r = fx.run(
        "0",
        &fx.head,
        &[("STUB_RECENT", &recent), ("STUB_COMPARE", "")],
    );
    r.verdict(1, "DRIFT", "cannot be placed");
    assert!(r.conclusion_is("failure"));
    assert_has(&r.err, "not in this checkout", "reason");
    assert_has(
        &r.err,
        "(GitHub compare: no answer)",
        "names the missing answer",
    );
}

#[test]
fn some_checked_some_not_checkable_is_success_naming_the_skipped() {
    let fx = Fx::new();
    let labels = format!("{OAUTH_LABEL} {OTHER_LABEL}");
    let un = unfinished(&fx);
    let r = fx.run(
        "0",
        &fx.head,
        &[("STUB_LABELS", &labels), ("STUB_RECENT_OTHER", &un)],
    );
    r.verdict(0, "OK", "one judged, one skipped");
    assert!(r.conclusion_is("success"));
    assert_has(&r.summary, "other-unit", "skipped unit named");
    assert_has(
        &r.result,
        "title=1 unit(s) delivered; 1 not checked\n",
        "title counts it",
    );
    assert_lacks(
        &r.err,
        "other-unit: up to date",
        "the skipped unit was not judged",
    );
    assert_has(
        &r.err,
        "delivery-drift: NOT CHECKED: other-unit\n",
        "names it in the log",
    );
    let n = |wf: &str| r.polls.iter().filter(|p| *p == wf).count();
    assert_eq!(n("delivery-other.yaml"), 1, "{:?}", r.polls);
    assert_eq!(n("delivery-oauth-user-inspector.yaml"), 1, "{:?}", r.polls);
}

#[test]
fn a_delivery_newer_than_the_checkout_is_current() {
    let fx = Fx::new();
    let runs = format!("700 {NEWER_SHA}");
    let r = fx.run(
        "0",
        "",
        &[
            ("STUB_RUNS", &runs),
            ("STUB_HIT_RUNS", "700"),
            ("STUB_COMPARE", "ahead"),
        ],
    );
    r.verdict(0, "OK", "newer delivered commit containing HEAD");
    assert_has(
        &r.err,
        "up to date (delivered 12345678, newer than",
        "reason",
    );

    let r = fx.run(
        "0",
        "",
        &[
            ("STUB_RUNS", &runs),
            ("STUB_HIT_RUNS", "700"),
            ("STUB_COMPARE", ""),
        ],
    );
    r.verdict(1, "DRIFT", "compare fails");
    assert!(r.conclusion_is("failure"));
    assert_has(&r.err, "UNKNOWN", "unknown");
}

// --- which history ----------------------------------------------------------------------------

#[test]
fn each_unit_is_read_from_its_own_apps_workflow() {
    let fx = Fx::new();
    let log = fx.p("gh.log");
    std::fs::write(&log, "").unwrap();
    fx.run("0", &fx.head, &[("STUB_LOG", log.to_str().unwrap())]);
    let l = read(&log);
    assert!(
        l.lines().any(|x| x == "delivery-oauth-user-inspector.yaml"),
        "{l}"
    );
    assert!(
        !l.lines().any(|x| x == "delivery.yaml"),
        "the legacy history was read: {l}"
    );
}

#[test]
fn a_unit_last_delivered_before_the_per_app_split() {
    let fx = Fx::new();
    let r = fx.run("0", &fx.head, &[("STUB_DELIVERED_WF", "delivery.yaml")]);
    r.verdict(0, "OK", "legacy delivery counts");
    assert_has(
        &r.err,
        "last delivered by delivery.yaml",
        "names the legacy workflow",
    );

    let r = fx.run(
        "0",
        &fx.head,
        &[
            ("STUB_DELIVERED_WF", "delivery.yaml"),
            ("LEGACY_WORKFLOW_FILE", ""),
        ],
    );
    assert_eq!(r.code, 1, "legacy fallback disabled => UNKNOWN\n{}", r.err);
}

fn twenty_runs(fx: &Fx) -> String {
    let rows: Vec<String> = (1001..=1020)
        .map(|n| format!("{n} {}", if n == 1010 { &fx.head } else { &fx.base }))
        .collect();
    lines(&rows)
}

#[test]
fn the_newest_delivery_wins() {
    let fx = Fx::new();
    let runs = twenty_runs(&fx);
    let r = fx.run(
        "0",
        "",
        &[("STUB_RUNS", &runs), ("STUB_HIT_RUNS", "1013 1010")],
    );
    r.verdict(0, "OK", "run 1010 (HEAD) wins over 1013");
    assert_has(
        &r.err,
        &format!("up to date (delivered {})", Fx::s8(&fx.head)),
        "HEAD",
    );
}

#[test]
fn a_long_history_costs_one_query_per_page() {
    let fx = Fx::new();
    let gql = fx.p("gql.log");
    std::fs::write(&gql, "").unwrap();
    let runs = twenty_runs(&fx);
    fx.run(
        "0",
        "",
        &[
            ("STUB_GQL_LOG", gql.to_str().unwrap()),
            ("STUB_RUNS", &runs),
            ("STUB_HIT_RUNS", "1020"),
        ],
    );
    assert_eq!(
        read(&gql).lines().count(),
        1,
        "20 runs in 1 query: {}",
        read(&gql)
    );
}

/// 300 runs, newest first; runs >= 1020 at `late`, older ones at BASE.
fn long_runs(fx: &Fx, late: &str) -> String {
    let rows: Vec<String> = (1001..=1300)
        .rev()
        .map(|n| format!("{n} {}", if n >= 1020 { late } else { &fx.base }))
        .collect();
    lines(&rows)
}

#[test]
fn a_delivery_older_than_any_fixed_window_is_still_found() {
    // The charts/esp32-s3 false alarms of 2026-10-11..14.
    let fx = Fx::new();
    let runs = long_runs(&fx, &fx.head);
    let legacy = format!("900 {}", fx.base);
    let r = fx.run(
        "0",
        "",
        &[
            ("STUB_RUNS", &runs),
            ("STUB_LEGACY_RUNS", &legacy),
            ("STUB_HIT_RUNS", "1020 900"),
        ],
    );
    r.verdict(0, "OK", "the delivery 281 runs back");
    assert_has(
        &r.err,
        &format!("up to date (delivered {})", Fx::s8(&fx.head)),
        "found",
    );
    assert_lacks(
        &r.err,
        "should have delivered and did not",
        "no commit blamed",
    );
    assert_lacks(
        &r.err,
        "last delivered by delivery.yaml",
        "legacy not consulted",
    );

    let runs = long_runs(&fx, &fx.real);
    let r = fx.run(
        "0",
        "",
        &[
            ("STUB_RUNS", &runs),
            ("STUB_LEGACY_RUNS", &legacy),
            ("STUB_HIT_RUNS", "1020 900"),
        ],
    );
    r.verdict(0, "OK", "old delivery followed only by a release bump");
    assert_has(&r.err, &format!("delivered {}", Fx::s8(&fx.real)), "REAL");
}

#[test]
fn the_legacy_history_is_used_only_once_the_units_own_is_exhausted() {
    let fx = Fx::new();
    let gql = fx.p("gql.log");
    std::fs::write(&gql, "").unwrap();
    let runs = long_runs(&fx, &fx.head);
    let legacy = format!("900 {}", fx.head);
    let r = fx.run(
        "0",
        "",
        &[
            ("STUB_GQL_LOG", gql.to_str().unwrap()),
            ("STUB_RUNS", &runs),
            ("STUB_LEGACY_RUNS", &legacy),
            ("STUB_HIT_RUNS", "900"),
        ],
    );
    r.verdict(0, "OK", "falls back to delivery.yaml");
    assert_has(&r.err, "last delivered by delivery.yaml", "legacy");
    let g = read(&gql);
    assert_eq!(
        g.lines()
            .filter(|l| l.starts_with("delivery-oauth-user-inspector.yaml "))
            .count(),
        3,
        "all 3 pages read first: {g}"
    );
    assert_has(
        &g,
        "delivery-oauth-user-inspector.yaml o200\n",
        "pages follow the cursor",
    );
}

#[test]
fn a_commit_that_really_was_not_delivered_is_still_drift() {
    let fx = Fx::new();
    let runs = long_runs(&fx, &fx.base);
    let legacy = format!("900 {}", fx.head);
    let r = fx.run(
        "0",
        "",
        &[
            ("STUB_RUNS", &runs),
            ("STUB_LEGACY_RUNS", &legacy),
            ("STUB_HIT_RUNS", "1020 900"),
        ],
    );
    r.verdict(1, "DRIFT", "genuine miss");
    assert_has(
        &r.err,
        &format!(
            "DRIFT oauth-user-inspector: last delivered {}, but {}",
            Fx::s8(&fx.base),
            Fx::s8(&fx.real)
        ),
        "blames REAL",
    );
}

#[test]
fn a_history_longer_than_the_scan_limit_is_unknown() {
    let fx = Fx::new();
    let runs = long_runs(&fx, &fx.head);
    let legacy = format!("900 {}", fx.head);
    let r = fx.run(
        "0",
        "",
        &[
            ("RUN_SCAN_LIMIT", "200"),
            ("STUB_RUNS", &runs),
            ("STUB_LEGACY_RUNS", &legacy),
            ("STUB_HIT_RUNS", "1020 900"),
        ],
    );
    assert_eq!(r.code, 1, "{}", r.err);
    assert_has(&r.err, "UNKNOWN", "unknown");
    assert_has(&r.err, "in the newest 200 runs of delivery-oauth-user-inspector.yaml, and its history goes back further (RUN_SCAN_LIMIT=200)", "capped");
    assert_lacks(&r.err, "last delivered by delivery.yaml", "no fallback");
}

#[test]
fn an_api_failure_is_unknown_not_a_fallback() {
    let fx = Fx::new();
    let r = fx.run(
        "0",
        &fx.head,
        &[
            ("STUB_GQL_FAIL", "1"),
            ("STUB_DELIVERED_WF", "delivery.yaml"),
        ],
    );
    assert_eq!(r.code, 1);
    assert!(r.conclusion_is("failure"));
    assert_has(&r.err, "could not read", "reason");
    assert_lacks(
        &r.err,
        "last delivered by delivery.yaml",
        "nothing inferred",
    );
}

#[test]
fn an_unknown_delivery_state_is_not_healthy() {
    let fx = Fx::new();
    let r = fx.run("0", "", &[]);
    assert_eq!(r.code, 1);
    assert!(r.conclusion_is("failure"));
    assert_has(
        &r.summary,
        "**UNKNOWN: no delivery found in `delivery-oauth-user-inspector.yaml or delivery.yaml` (absent, 0 runs read)**",
        "summary",
    );
}

// --- setup, metadata and the engine (no shell counterpart) -----------------------

#[test]
fn malformed_graphql_is_a_failed_read() {
    let fx = Fx::new();
    // An `errors` answer and a non-JSON answer both read as failures.
    write_exe(
        fx.stubs.join("gh"),
        format!(
            "#!/usr/bin/env bash\nif [ \"$1 $2\" = \"api graphql\" ]; then echo '{{\"errors\":[{{\"message\":\"x\"}}]}}'; exit 0; fi\n{}",
            GH_STUB.trim_start_matches("#!/usr/bin/env bash\n")
        ),
    );
    let r = fx.run("0", &fx.head, &[]);
    assert_eq!(r.code, 1);
    assert_has(
        &r.err,
        "could not read the run history of delivery-oauth-user-inspector.yaml",
        "errors",
    );
}

#[test]
fn unreadable_metadata_is_unknown_not_skipped() {
    let fx = Fx::new();
    write(
        fx.repo
            .join("bazel-bin/oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json"),
        "{not json",
    );
    let r = fx.run("0", &fx.head, &[]);
    r.verdict(1, "DRIFT", "unreadable metadata");
    assert_has(&r.summary, "its metadata cannot be read", "summary");
}

#[test]
fn missing_metadata_is_unknown() {
    let fx = Fx::new();
    std::fs::remove_file(
        fx.repo
            .join("bazel-bin/other/infra/other-unit.delivery.json"),
    )
    .unwrap();
    let labels = format!("{OAUTH_LABEL} {OTHER_LABEL}");
    let r = fx.run("0", &fx.head, &[("STUB_LABELS", &labels)]);
    r.verdict(1, "DRIFT", "missing metadata");
    assert_has(
        &r.err,
        &format!("metadata missing for {OTHER_LABEL} -- cannot check, treating as UNKNOWN"),
        "log",
    );
}

#[test]
fn setup_errors_exit_2_without_a_verdict() {
    let fx = Fx::new();
    // No units declared.
    let r = fx.run("0", &fx.head, &[("STUB_LABELS", " ")]);
    assert_eq!(r.code, 2, "{}", r.err);
    assert_eq!(r.result, "", "no verdict");
    assert_has(&r.err, "no delivery units declared", "reason");
    // gh missing.
    let r = fx.run("0", &fx.head, &[("GH", "/nonexistent/gh")]);
    assert_eq!(r.code, 2);
    assert_has(&r.err, "gh not found on PATH", "reason");
    // The engine missing: never a pass built on nothing.
    let r = fx.run(
        "0",
        &fx.base,
        &[("DEPLOY_AFFECTED_BIN", "/nonexistent/deploy_affected")],
    );
    assert_eq!(r.code, 2, "{}", r.err);
    assert_eq!(r.result, "");
    assert_has(&r.err, "is not an executable", "reason");
}

#[test]
fn the_default_engine_is_the_one_in_the_runfiles() {
    // No DEPLOY_AFFECTED_BIN: the binary finds //tools/ci:deploy_affected in
    // its runfiles (this test's runfiles carry it), and still judges DRIFT.
    let fx = Fx::new();
    let o = fx
        .cmd("0", &fx.base, &[])
        .env_remove("DEPLOY_AFFECTED_BIN")
        .go();
    assert_eq!((o.code, o.stdout.trim()), (1, "DRIFT"), "{}", o.stderr);
    assert_has(
        &o.stderr,
        "affected=true (path matched oauth-user-inspector/)",
        "the real engine ran",
    );
}

#[test]
fn bazel_run_acts_in_the_callers_directory() {
    let fx = Fx::new();
    let elsewhere = TempDir::new();
    let o = fx
        .cmd("0", &fx.base, &[])
        .cwd(elsewhere.path())
        .env("BUILD_WORKING_DIRECTORY", &fx.repo)
        .go();
    assert_eq!(
        (o.code, o.stdout.trim()),
        (1, "DRIFT"),
        "same verdict as in the repo\n{}",
        o.stderr
    );
}

#[test]
fn drift_ignore_in_flight_judges_mains_tip() {
    let fx = Fx::new();
    let busy = format!("905 waiting {} \n", fx.head);
    let r = fx.run(
        "0",
        &fx.head,
        &[("STUB_RECENT", &busy), ("DRIFT_IGNORE_IN_FLIGHT", "1")],
    );
    r.verdict(0, "OK", "the waiting run is ignored");
    assert!(
        r.polls.is_empty(),
        "recent runs are not read: {:?}",
        r.polls
    );
    assert_has(&r.err, "main's tip (DRIFT_IGNORE_IN_FLIGHT set)", "reason");
}
