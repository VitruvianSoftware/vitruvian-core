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

//! Black-box guard for the affected-targets binary (#2841, #503). A real temp
//! git repository (the binary diffs it) and a fake `bazel` on PATH that replays
//! a canned plan and records every invocation. Pins:
//!   - the dependency map is handed to the planner when the workflow restored one;
//!   - a map-sourced plan tests every test in the changed packages at HEAD, so a
//!     test the change adds is run and one it deletes is not asked for;
//!   - a live-query plan is run exactly as before;
//!   - "no tests found" on a map-sourced plan full-sweeps, like an empty live plan;
//!   - every route to a full `//...` sweep, and that a red sweep stays red;
//!   - the docs-only and nothing-changed short circuits do no Bazel work.
//!
//! The binary is addressed through AFFECTED_TARGETS_BIN, so any executable that
//! honours the same contract can be pointed at it. That is how the shell
//! original was proven equivalent before it was removed.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn binary() -> PathBuf {
    let rel = std::env::var("AFFECTED_TARGETS_BIN").expect("set by Bazel");
    std::env::current_dir().unwrap().join(rel)
}

/// `jq` from the hermetic toolchain, first on PATH (the binary shells out to it).
fn jq_dir() -> Option<PathBuf> {
    let jq = std::env::var("JQ_BIN").ok()?;
    let jq = match jq.strip_prefix("external/") {
        Some(rest) => format!("../{rest}"),
        None => jq,
    };
    let abs = std::env::current_dir().unwrap().join(jq);
    Some(abs.parent().unwrap().to_path_buf())
}

fn git(dir: &Path, args: &[&str]) -> String {
    let o = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .expect("git runs");
    assert!(
        o.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&o.stderr)
    );
    String::from_utf8_lossy(&o.stdout).trim().to_string()
}

fn write_exec(path: &Path, body: &str) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

struct Case {
    work: PathBuf,
    repo: PathBuf,
    /// The commit before the one change commit (HEAD).
    base: String,
}

struct Ran {
    out: String,
    rc: i32,
    calls: String,
}

impl Ran {
    fn called(&self, s: &str) -> bool {
        self.calls.contains(s)
    }
    fn lines_starting(&self, p: &str) -> Vec<&str> {
        self.calls.lines().filter(|l| l.starts_with(p)).collect()
    }
    fn planned_base(&self) -> String {
        let l = self
            .calls
            .lines()
            .find(|l| l.starts_with("run //tools/pipeline:plan"))
            .unwrap_or("");
        l.split("--base=")
            .nth(1)
            .and_then(|r| r.split_whitespace().next())
            .unwrap_or("")
            .to_string()
    }
}

const MAP_PLAN: &str = r#"{"plan_source":"rdeps-map","affected_packages":["//apps/a:all"],"targets":["//apps/a:gone_test","//apps/a/sub:sub_test","//libs/b:b_test"]}"#;
const LIVE_PLAN: &str = r#"{"plan_source":"live-query","affected_packages":["//apps/a:all"],"targets":["//apps/a:a_test","//libs/b:b_test"]}"#;

impl Case {
    fn new() -> Case {
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let base_dir = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
        let work = Path::new(&base_dir).join(format!(
            "affected-targets-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&work);
        let repo = work.join("repo");
        std::fs::create_dir_all(repo.join("apps/a")).unwrap();
        assert!(Command::new("git")
            .args(["init", "-q", "-b", "main"])
            .arg(&repo)
            .status()
            .unwrap()
            .success());
        git(&repo, &["config", "user.email", "test@example.com"]);
        git(&repo, &["config", "user.name", "test"]);
        git(&repo, &["config", "commit.gpgsign", "false"]);
        std::fs::write(repo.join("apps/a/a.go"), "one\n").unwrap();
        git(&repo, &["add", "."]);
        git(&repo, &["commit", "-q", "-m", "base"]);
        let base = git(&repo, &["rev-parse", "HEAD"]);
        std::fs::write(repo.join("apps/a/a.go"), "two\n").unwrap();
        git(&repo, &["commit", "-q", "-am", "change"]);

        // Fake bazel: `run` prints $FAKE_PLAN (and $FAKE_PLAN_STDERR on stderr);
        // `build` exits $FAKE_BUILD_RC; `test` of //... exits $FAKE_SWEEP_RC and
        // any other test exits $FAKE_TEST_RC. Every call is appended to $CALLS.
        let bin = work.join("bin");
        std::fs::create_dir_all(&bin).unwrap();
        std::fs::create_dir_all(work.join("tmp")).unwrap();
        write_exec(
            &bin.join("bazel"),
            r#"#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1" in
  run) [ -n "${FAKE_PLAN_STDERR:-}" ] && echo "${FAKE_PLAN_STDERR}" >&2; printf '%s' "${FAKE_PLAN:-}" ;;
  build) exit "${FAKE_BUILD_RC:-0}" ;;
  test) case "$*" in *'//...'*) exit "${FAKE_SWEEP_RC:-0}" ;; *) exit "${FAKE_TEST_RC:-0}" ;; esac ;;
esac
exit 0
"#,
        );
        write_exec(
            &bin.join("plan"),
            r#"#!/usr/bin/env bash
echo "plan-bin $*" >> "$CALLS"
printf '%s' "${FAKE_PLAN:-}"
"#,
        );
        Case { work, repo, base }
    }

    /// Adds a commit on top of HEAD and returns its sha.
    fn commit(&self, path: &str, content: &str) -> String {
        let p = self.repo.join(path);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(&p, format!("{content}\n")).unwrap();
        git(&self.repo, &["add", path]);
        git(
            &self.repo,
            &["commit", "-q", "-m", &format!("{path} {content}")],
        );
        git(&self.repo, &["rev-parse", "HEAD"])
    }

    fn head(&self) -> String {
        git(&self.repo, &["rev-parse", "HEAD"])
    }

    fn map_for(&self, commit: &str) -> PathBuf {
        let p = self.work.join("map.json");
        std::fs::write(&p, format!("{{\"schema\":1,\"commit\":\"{commit}\"}}")).unwrap();
        p
    }

    /// Runs the binary in the repo. BEFORE_REV defaults to the base commit,
    /// BUILDBUDDY_API_KEY to "k"; `envs` overrides and `unset` removes.
    fn run(&self, plan: &str, envs: &[(&str, &str)], unset: &[&str]) -> Ran {
        let calls = self.work.join("calls");
        std::fs::write(&calls, "").unwrap();
        let mut path = format!(
            "{}:{}",
            self.work.join("bin").display(),
            std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
        );
        if let Some(d) = jq_dir() {
            path = format!("{}:{path}", d.display());
        }
        let mut c = Command::new(binary());
        c.current_dir(&self.repo)
            .env_clear()
            .env("PATH", path)
            .env("HOME", &self.work)
            .env("TMPDIR", self.work.join("tmp"))
            .env("CALLS", &calls)
            .env("BUILDBUDDY_API_KEY", "k")
            .env("BEFORE_REV", &self.base)
            .env("FAKE_PLAN", plan)
            .env("GIT_TERMINAL_PROMPT", "0");
        for (k, v) in envs {
            c.env(k, v);
        }
        for k in unset {
            c.env_remove(k);
        }
        let o: Output = c.output().expect("binary runs");
        Ran {
            out: format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            ),
            rc: o.status.code().unwrap_or(-1),
            calls: std::fs::read_to_string(&calls).unwrap_or_default(),
        }
    }
}

fn swept(r: &Ran) -> bool {
    r.called("build --config=remote --remote_header=x-buildbuddy-api-key=k //...")
        && r.lines_starting("test ")
            .iter()
            .any(|l| l.ends_with("//..."))
}

// --- dependency map handed to the planner -----------------------------------

#[test]
fn rdeps_map_is_passed_to_the_planner_when_set() {
    let c = Case::new();
    let map = c.work.join("map.json");
    let r = c.run(MAP_PLAN, &[("RDEPS_MAP", map.to_str().unwrap())], &[]);
    let want = format!(
        "run //tools/pipeline:plan -- --base={} --head=HEAD --format=json --rdeps-map={}",
        c.base,
        map.display()
    );
    assert!(r.called(&want), "{}", r.calls);
}

#[test]
fn no_rdeps_map_flag_without_rdeps_map() {
    let c = Case::new();
    let r = c.run(LIVE_PLAN, &[], &[]);
    assert!(r.called("run //tools/pipeline:plan"), "{}", r.calls);
    assert!(!r.called("--rdeps-map"), "{}", r.calls);
}

// --- prebuilt planner -------------------------------------------------------

#[test]
fn a_prebuilt_planner_is_used_instead_of_bazel_run() {
    let c = Case::new();
    let map = c.work.join("map.json");
    let plan = c.work.join("bin/plan");
    let r = c.run(
        LIVE_PLAN,
        &[
            ("PLAN_BIN", plan.to_str().unwrap()),
            ("RDEPS_MAP", map.to_str().unwrap()),
        ],
        &[],
    );
    let want = format!(
        "plan-bin --base={} --head=HEAD --format=json --rdeps-map={} --repo-root=",
        c.base,
        map.display()
    );
    assert!(r.called(&want), "{}", r.calls);
    assert!(!r.called("run //tools/pipeline:plan"), "{}", r.calls);
}

#[test]
fn a_missing_prebuilt_planner_falls_back_to_bazel_run() {
    let c = Case::new();
    let missing = c.work.join("bin/missing");
    let r = c.run(LIVE_PLAN, &[("PLAN_BIN", missing.to_str().unwrap())], &[]);
    assert!(r.called("run //tools/pipeline:plan"), "{}", r.calls);
}

#[test]
fn a_non_executable_prebuilt_planner_falls_back_to_bazel_run() {
    let c = Case::new();
    let plain = c.work.join("bin/plain");
    std::fs::write(&plain, "#!/bin/sh\n").unwrap();
    let r = c.run(LIVE_PLAN, &[("PLAN_BIN", plain.to_str().unwrap())], &[]);
    assert!(r.called("run //tools/pipeline:plan"), "{}", r.calls);
}

// --- map-sourced plan -------------------------------------------------------

#[test]
fn a_map_sourced_plan_retests_whole_changed_packages() {
    let c = Case::new();
    let map = c.work.join("map.json");
    let r = c.run(MAP_PLAN, &[("RDEPS_MAP", map.to_str().unwrap())], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    let t = r.lines_starting("test ").join("\n");
    assert!(
        t.contains(" --build_tests_only ") && t.contains("//apps/a:all"),
        "missing package pattern: {t}"
    );
    assert!(
        !t.contains("//apps/a:gone_test"),
        "still asks for a base-commit label in a changed package: {t}"
    );
    let sub = t
        .find("//apps/a/sub:sub_test")
        .expect("subpackage label kept");
    assert!(
        t[sub..].contains("//libs/b:b_test"),
        "lost an unchanged-package label: {t}"
    );
    assert!(
        r.out.contains("source: rdeps-map"),
        "no plan-source line: {}",
        r.out
    );
    assert!(
        r.out.contains("affected-targets: executing 3 affected test targets:\n  //apps/a/sub:sub_test\n  //libs/b:b_test\n  //apps/a:all\n"),
        "{}",
        r.out
    );
}

// --- live-query plan --------------------------------------------------------

#[test]
fn a_live_query_plan_is_run_exactly_as_planned() {
    let c = Case::new();
    let r = c.run(
        LIVE_PLAN,
        &[(
            "FAKE_PLAN_STDERR",
            "no dependency map for this diff base; falling back to the live query",
        )],
        &[],
    );
    let t = r.lines_starting("test ").join("\n");
    assert!(
        !t.contains("build_tests_only") && !t.contains(":all"),
        "live plan was rewritten: {t}"
    );
    assert!(
        t.ends_with("//apps/a:a_test //libs/b:b_test"),
        "unexpected: {t}"
    );
    assert!(
        r.out.contains("no dependency map for this diff base"),
        "fallback reason hidden: {}",
        r.out
    );
}

#[test]
fn a_plan_source_note_is_echoed() {
    let c = Case::new();
    let plan =
        r#"{"plan_source":"live-query","plan_source_note":"map was stale","targets":["//a:t"]}"#;
    let r = c.run(plan, &[], &[]);
    assert!(
        r.out.contains("affected-targets: map was stale\n"),
        "{}",
        r.out
    );
}

// --- failures and fallbacks -------------------------------------------------

#[test]
fn a_failing_test_still_fails_the_job() {
    let c = Case::new();
    let r = c.run(MAP_PLAN, &[("FAKE_TEST_RC", "3")], &[]);
    assert_eq!(r.rc, 3, "{}", r.out);
}

#[test]
fn no_tests_found_on_a_map_plan_full_sweeps() {
    let c = Case::new();
    let r = c.run(MAP_PLAN, &[("FAKE_TEST_RC", "4")], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(swept(&r), "{}", r.calls);
    assert!(
        r.out.contains(
            "::notice::affected-targets: full //... sweep (no tests left in the changed packages)"
        ),
        "{}",
        r.out
    );
}

#[test]
fn exit_4_on_a_live_plan_is_passed_through() {
    let c = Case::new();
    let r = c.run(LIVE_PLAN, &[("FAKE_TEST_RC", "4")], &[]);
    assert_eq!(r.rc, 4, "{}", r.out);
    assert!(!swept(&r), "{}", r.calls);
}

#[test]
fn no_plan_full_sweeps_and_shows_the_planners_error() {
    let c = Case::new();
    let r = c.run("", &[("FAKE_PLAN_STDERR", "planner exploded")], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(swept(&r), "{}", r.calls);
    assert!(r.out.contains("planner exploded"), "{}", r.out);
    assert!(
        r.out.contains("planner produced no plan after "),
        "{}",
        r.out
    );
    assert!(
        r.out.contains("::warning title=affected-selection-fallback::affected-targets fast path degraded -- full //... sweep (change detection plan failed -- fail-closed fallback)"),
        "{}",
        r.out
    );
}

#[test]
fn an_over_budget_map_plan_warns() {
    let c = Case::new();
    let r = c.run(MAP_PLAN, &[("PLAN_BUDGET_SEC", "-1")], &[]);
    assert!(r.out.contains("title=affected-selection-slow"), "{}", r.out);
}

#[test]
fn a_map_plan_within_budget_does_not_warn() {
    let c = Case::new();
    let r = c.run(MAP_PLAN, &[], &[]);
    assert!(!r.out.contains("affected-selection-slow"), "{}", r.out);
}

#[test]
fn a_map_plan_listing_no_changed_packages_full_sweeps_degraded() {
    let c = Case::new();
    let plan =
        r#"{"plan_source":"rdeps-map","affected_packages":[],"targets":["//libs/b:b_test"]}"#;
    let r = c.run(plan, &[], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(swept(&r), "{}", r.calls);
    assert!(
        r.out
            .contains("full //... sweep (dependency-map plan lists no changed packages)"),
        "{}",
        r.out
    );
}

#[test]
fn a_plan_with_no_targets_full_sweeps() {
    let c = Case::new();
    let r = c.run(r#"{"plan_source":"live-query","targets":[]}"#, &[], &[]);
    assert!(swept(&r), "{}", r.calls);
    assert!(
        r.out.contains("::notice::affected-targets: full //... sweep (full sweep required by change detection plan)"),
        "{}",
        r.out
    );
}

#[test]
fn a_plan_flagged_global_impact_full_sweeps() {
    let c = Case::new();
    let r = c.run(
        r#"{"plan_source":"live-query","is_global_impact":true,"targets":["//a:t"]}"#,
        &[],
        &[],
    );
    assert!(swept(&r), "{}", r.calls);
    assert!(
        !r.lines_starting("test ")
            .iter()
            .any(|l| l.contains("//a:t")),
        "{}",
        r.calls
    );
}

#[test]
fn a_plan_flagged_docs_only_builds_nothing() {
    let c = Case::new();
    let r = c.run(
        r#"{"plan_source":"live-query","is_docs_only":true}"#,
        &[],
        &[],
    );
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(
        r.lines_starting("test ").is_empty() && r.lines_starting("build ").is_empty(),
        "{}",
        r.calls
    );
    assert!(
        r.out.contains("::notice::affected-targets: all changed files are docs/gitops/markdown-only \u{2192} nothing to build or test."),
        "{}",
        r.out
    );
}

// --- the diff base and the routes to a sweep --------------------------------

#[test]
fn a_forced_push_full_sweeps_without_planning() {
    let c = Case::new();
    let r = c.run(LIVE_PLAN, &[("FORCED_PUSH", "true")], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(swept(&r), "{}", r.calls);
    assert!(!r.called("pipeline:plan"), "{}", r.calls);
    assert_eq!(
        r.out,
        "::notice::affected-targets: full //... sweep (forced push -- no trustworthy diff base)\n"
    );
}

#[test]
fn an_unresolvable_before_rev_full_sweeps() {
    let c = Case::new();
    let zero = "0000000000000000000000000000000000000000";
    let r = c.run(LIVE_PLAN, &[("BEFORE_REV", zero)], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(swept(&r), "{}", r.calls);
    assert!(
        r.out.contains(&format!(
            "::notice::affected-targets: full //... sweep (BEFORE_REV '{zero}' does not resolve to a commit)"
        )),
        "{}",
        r.out
    );
}

#[test]
fn neither_before_rev_nor_base_ref_full_sweeps_degraded_with_a_summary() {
    let c = Case::new();
    let summary = c.work.join("summary.md");
    let r = c.run(
        LIVE_PLAN,
        &[("GITHUB_STEP_SUMMARY", summary.to_str().unwrap())],
        &["BEFORE_REV"],
    );
    assert!(swept(&r), "{}", r.calls);
    assert!(
        r.out.contains("::warning title=affected-selection-fallback::affected-targets fast path degraded -- full //... sweep (neither BEFORE_REV nor BASE_REF is set)"),
        "{}",
        r.out
    );
    assert_eq!(
        std::fs::read_to_string(&summary).unwrap(),
        "### \u{26a0} affected-selection fallback (degraded)\n\n- reason: neither BEFORE_REV nor BASE_REF is set\n- consequence: this run paid a full `//...` sweep instead of affected targets\n- if this recurs across runs, the fast path is broken (see #503): check the TD pin in `tools/ci/td-lib.sh` and the runner platform\n"
    );
}

#[test]
fn base_ref_uses_the_merge_base_with_origin() {
    let c = Case::new();
    git(
        &c.repo,
        &["update-ref", "refs/remotes/origin/main", &c.base],
    );
    let r = c.run(LIVE_PLAN, &[("BASE_REF", "main")], &["BEFORE_REV"]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(
        r.out.contains(&format!(
            "affected-targets: before-rev (merge-base) = {}\n",
            c.base
        )),
        "{}",
        r.out
    );
    assert_eq!(r.planned_base(), c.base);
}

#[test]
fn a_base_ref_with_no_origin_branch_full_sweeps_degraded() {
    let c = Case::new();
    let r = c.run(LIVE_PLAN, &[("BASE_REF", "nope")], &["BEFORE_REV"]);
    assert!(swept(&r), "{}", r.calls);
    assert!(
        r.out.contains("::warning title=affected-selection-fallback::affected-targets fast path degraded -- full //... sweep (could not compute merge-base against origin/nope)"),
        "{}",
        r.out
    );
}

#[test]
fn an_explicit_before_rev_wins_over_base_ref() {
    let c = Case::new();
    let r = c.run(LIVE_PLAN, &[("BASE_REF", "nope")], &[]);
    assert!(
        r.out.contains(&format!(
            "affected-targets: before-rev (explicit) = {}\n",
            c.base
        )),
        "{}",
        r.out
    );
    assert!(!swept(&r), "{}", r.calls);
}

#[test]
fn nothing_changed_does_nothing() {
    let c = Case::new();
    let head = c.head();
    let r = c.run(LIVE_PLAN, &[("BEFORE_REV", &head)], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert_eq!(r.calls, "");
    assert_eq!(
        r.out,
        format!("affected-targets: before-rev (explicit) = {head}\naffected-targets: no changed files detected vs {head}; nothing to do.\n")
    );
}

#[test]
fn a_docs_only_diff_builds_nothing_and_never_plans() {
    let c = Case::new();
    let before = c.head();
    c.commit("docs/guide.md", "x");
    c.commit("gitops/app/values.yaml", "y");
    let r = c.run(LIVE_PLAN, &[("BEFORE_REV", &before)], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert_eq!(r.calls, "");
    assert!(
        r.out.contains(
            "affected-targets: changed files:\n  docs/guide.md\n  gitops/app/values.yaml\n"
        ),
        "{}",
        r.out
    );
    assert!(
        r.out.contains("::notice::affected-targets: all changed files are docs/gitops/markdown/metadata-only \u{2192} nothing to build or test."),
        "{}",
        r.out
    );
}

#[test]
fn a_global_impact_file_full_sweeps_without_planning() {
    for path in [
        "MODULE.bazel",
        ".bazelrc",
        "BUILD",
        "tools/newthing/x.bzl",
        "gazelle_python.yaml",
    ] {
        let c = Case::new();
        let before = c.head();
        c.commit(path, "g");
        let r = c.run(LIVE_PLAN, &[("BEFORE_REV", &before)], &[]);
        assert_eq!(r.rc, 0, "{path}: {}", r.out);
        assert!(swept(&r), "{path}: {}", r.calls);
        assert!(!r.called("pipeline:plan"), "{path}: {}", r.calls);
        assert!(
            r.out
                .contains("full //... sweep (global-impact file changed"),
            "{path}: {}",
            r.out
        );
    }
}

#[test]
fn an_allowlisted_tools_directory_is_not_global_impact() {
    for path in [
        "tools/ci/x.sh",
        "tools/deploy/y.bzl",
        "tools/pipeline/z.rs",
        "tools/repin",
    ] {
        let c = Case::new();
        let before = c.head();
        c.commit(path, "g");
        let r = c.run(LIVE_PLAN, &[("BEFORE_REV", &before)], &[]);
        assert!(!swept(&r), "{path}: {}", r.calls);
        assert!(r.called("pipeline:plan"), "{path}: {}", r.calls);
    }
}

// --- a red sweep stays red --------------------------------------------------

#[test]
fn a_failing_sweep_build_fails_the_job_and_skips_the_tests() {
    let c = Case::new();
    let r = c.run(
        LIVE_PLAN,
        &[("FORCED_PUSH", "true"), ("FAKE_BUILD_RC", "1")],
        &[],
    );
    assert_eq!(r.rc, 1, "{}", r.out);
    assert!(r.lines_starting("test ").is_empty(), "{}", r.calls);
}

#[test]
fn a_failing_sweep_test_fails_the_job() {
    let c = Case::new();
    let r = c.run(
        LIVE_PLAN,
        &[("FORCED_PUSH", "true"), ("FAKE_SWEEP_RC", "3")],
        &[],
    );
    assert_eq!(r.rc, 3, "{}", r.out);
    assert!(swept(&r), "{}", r.calls);
}

#[test]
fn an_unset_buildbuddy_key_is_an_error_not_a_sweep() {
    let c = Case::new();
    let r = c.run(LIVE_PLAN, &[], &["BUILDBUDDY_API_KEY"]);
    assert_ne!(r.rc, 0, "{}", r.out);
    assert_eq!(r.calls, "");
}

// --- map from an earlier commit (#2841) -------------------------------------

/// History on top of base -> change:  x1 -> g (MODULE.bazel) -> x2 -> x3 (HEAD).
struct History {
    c: Case,
    x1: String,
    g: String,
    x2: String,
    side: String,
}

fn history() -> History {
    let c = Case::new();
    let x1 = c.commit("libs/x/x.go", "1");
    let g = c.commit("MODULE.bazel", "1");
    let x2 = c.commit("apps/a/a.go", "three");
    c.commit("apps/a/a.go", "four");
    let tree = git(&c.repo, &["rev-parse", &format!("{}^{{tree}}", c.base)]);
    let side = git(&c.repo, &["commit-tree", "-m", "side", &tree]);
    History { c, x1, g, x2, side }
}

fn run_with_map(h: &History, map_commit: &str, extra: &[(&str, &str)]) -> Ran {
    let map = h.c.map_for(map_commit);
    let mut envs = vec![
        ("BEFORE_REV", h.x2.as_str()),
        ("RDEPS_MAP", map.to_str().unwrap()),
    ];
    envs.extend_from_slice(extra);
    h.c.run(MAP_PLAN, &envs, &[])
}

#[test]
fn a_map_for_the_exact_base_leaves_the_base_alone() {
    let h = history();
    let r = run_with_map(&h, &h.x2, &[]);
    assert_eq!(r.planned_base(), h.x2);
}

#[test]
fn a_map_one_commit_back_is_compared_against_and_says_so() {
    let h = history();
    let r = run_with_map(&h, &h.g, &[]);
    assert_eq!(r.planned_base(), h.g, "{}", r.out);
    assert!(
        r.out.contains(&format!(
            "affected-targets: no dependency map for the diff base yet; using the one from 1 commit(s) back ({}) and treating everything changed since then as changed\n",
            &h.g[..12]
        )),
        "{}",
        r.out
    );
}

#[test]
fn a_global_impact_change_since_the_map_means_the_map_is_not_used() {
    let h = history();
    let r = run_with_map(&h, &h.x1, &[]);
    assert_eq!(r.planned_base(), h.x2, "{}", r.out);
    assert!(
        r.out.contains(&format!(
            "affected-targets: a global-impact file changed since the dependency map at {} -- not used\n",
            &h.x1[..12]
        )),
        "{}",
        r.out
    );
}

#[test]
fn a_map_further_back_than_the_limit_is_not_used() {
    let h = history();
    let r = run_with_map(&h, &h.g, &[("MAP_MAX_BEHIND", "0")]);
    assert_eq!(r.planned_base(), h.x2, "{}", r.out);
    assert!(
        r.out.contains("affected-targets: dependency map is 1 commits behind the diff base (limit 0) -- not used\n"),
        "{}",
        r.out
    );
}

#[test]
fn a_map_from_a_commit_that_is_not_an_ancestor_is_not_used() {
    let h = history();
    let r = run_with_map(&h, &h.side, &[]);
    assert_eq!(r.planned_base(), h.x2, "{}", r.out);
    assert!(
        r.out.contains(&format!(
            "affected-targets: dependency map is for {}, not an ancestor of the diff base -- not used\n",
            &h.side[..12]
        )),
        "{}",
        r.out
    );
}

#[test]
fn an_unreadable_map_leaves_the_base_alone() {
    let h = history();
    let map = h.c.work.join("map.json");
    std::fs::write(&map, "not json").unwrap();
    let r = h.c.run(
        MAP_PLAN,
        &[("BEFORE_REV", &h.x2), ("RDEPS_MAP", map.to_str().unwrap())],
        &[],
    );
    assert_eq!(r.planned_base(), h.x2, "{}", r.out);
}

// --- no litter, and grep failures never mean "docs only" -------------------

/// Everything in the checkout's top level plus whatever is in TMPDIR.
fn footprint(c: &Case) -> (Vec<String>, Vec<String>) {
    let ls = |d: &Path| {
        let mut v: Vec<String> = std::fs::read_dir(d)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        v.sort();
        v
    };
    (ls(&c.repo), ls(&c.work.join("tmp")))
}

#[test]
fn no_run_leaves_files_in_the_checkout_or_the_temp_dir() {
    let cases: Vec<(&str, Vec<(&str, &str)>, &str)> = vec![
        ("live plan", vec![], LIVE_PLAN),
        ("map plan", vec![], MAP_PLAN),
        ("no plan -> sweep", vec![], ""),
        ("planner docs-only", vec![], r#"{"is_docs_only":true}"#),
        ("forced push", vec![("FORCED_PUSH", "true")], LIVE_PLAN),
    ];
    for (label, envs, plan) in cases {
        let c = Case::new();
        let before = footprint(&c);
        let r = c.run(plan, &envs, &[]);
        let after = footprint(&c);
        assert_eq!(after.0, before.0, "{label}: checkout litter\n{}", r.out);
        assert_eq!(after.1, before.1, "{label}: temp litter\n{}", r.out);
        assert!(after.1.is_empty());
    }
}

fn fake_grep(c: &Case, body: &str) {
    write_exec(&c.work.join("bin/grep"), body);
}

fn docs_only_diff(c: &Case) -> String {
    let before = c.head();
    c.commit("docs/guide.md", "x");
    before
}

#[test]
fn a_grep_that_errors_is_never_docs_only() {
    let c = Case::new();
    fake_grep(&c, "#!/bin/sh\nexit 2\n");
    let before = docs_only_diff(&c);
    let r = c.run(LIVE_PLAN, &[("BEFORE_REV", &before)], &[]);
    assert_eq!(r.rc, 0, "{}", r.out);
    assert!(swept(&r), "{}{}", r.out, r.calls);
    assert!(!r.out.contains("nothing to build or test"), "{}", r.out);
    assert!(
        r.out.contains("could not classify the changed files"),
        "{}",
        r.out
    );
}

#[test]
fn a_grep_count_that_is_not_a_number_is_never_docs_only() {
    let c = Case::new();
    fake_grep(
        &c,
        "#!/bin/sh\ncase \" $* \" in *\" -c \"*) echo junk; exit 0 ;; esac\nexec /usr/bin/grep \"$@\"\n",
    );
    let before = docs_only_diff(&c);
    let r = c.run(LIVE_PLAN, &[("BEFORE_REV", &before)], &[]);
    assert!(swept(&r), "{}{}", r.out, r.calls);
    assert!(!r.out.contains("nothing to build or test"), "{}", r.out);
}

#[test]
fn a_grep_that_cannot_classify_global_impact_means_a_sweep() {
    let c = Case::new();
    // The docs-only count works; the global-impact patterns hit an error.
    fake_grep(
        &c,
        "#!/bin/sh\ncase \" $* \" in *\" -c \"*) exec /usr/bin/grep \"$@\" ;; esac\nexit 2\n",
    );
    let r = c.run(LIVE_PLAN, &[], &[]);
    assert!(swept(&r), "{}{}", r.out, r.calls);
    assert!(r.out.contains("global-impact file changed"), "{}", r.out);
    assert!(!r.called("pipeline:plan"), "{}", r.calls);
}
