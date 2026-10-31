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

//! Black-box tests for //tools/ci:dependabot_lock_rebase. A REAL bare git
//! "origin" plus a real clone as the working checkout (git merge and conflict
//! resolution are the thing under test); `gh` (PR listing) and `bazel` (the
//! pnpm/tidy reconcile) are fakes. No network, no real Bazel.

use ci_testkit::{bin, git, read, write, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const FAKE_GH: &str = r#"#!/usr/bin/env bash
if [ "$1 $2" = "pr list" ]; then
  printf '%s' "${FAKE_PR_LIST_OUT:-}"
  exit 0
fi
echo "unexpected fake gh invocation: $*" >&2
exit 99
"#;

// app-4.txt exists only on pr4-branch's merge result: the pnpm reconcile
// fails ONLY for that PR.
const FAKE_BAZEL: &str = r#"#!/usr/bin/env bash
echo "$*" >> "${FAKE_BAZEL_LOG}"
case "$*" in
  *"@pnpm//:pnpm"*)
    [ -f app-4.txt ] && exit 1
    exit 0
    ;;
  *"//:tidy"*)
    exit 0
    ;;
  *)
    echo "unexpected fake bazel invocation: $*" >&2
    exit 99
    ;;
esac
"#;

const PRS_TSV: &str =
    "1\tpr1-branch\n2\tpr2-branch\n3\tpr3-branch\n4\tpr4-branch\n5\tpr5-branch\n6\tpr6-branch";

struct Fixture {
    work: TempDir,
    bare: PathBuf,
    ws: PathBuf,
}

/// Clone the bare origin into a scratch dir named `name`.
fn scratch(f: &Fixture, name: &str) -> PathBuf {
    let s = f.work.join(format!("scratch-{name}"));
    git(
        f.work.path(),
        &["clone", "-q", f.bare.to_str().unwrap(), s.to_str().unwrap()],
    );
    s
}

fn branch_with(f: &Fixture, name: &str, file: &str, contents: &str) {
    let s = scratch(f, name);
    git(&s, &["checkout", "-q", "-b", &format!("{name}-branch")]);
    write(s.join(file), contents);
    git(&s, &["add", "-A"]);
    git(&s, &["commit", "-q", "-m", &format!("{name} change")]);
    git(&s, &["push", "-q", "origin", &format!("{name}-branch")]);
}

/// main + PR branches 1-6, as the shell suite built them.
fn fixture() -> Fixture {
    let work = TempDir::new();
    write_exe(work.join("bin/gh"), FAKE_GH);
    write_exe(work.join("bin/bazel"), FAKE_BAZEL);

    let src = work.join("src");
    std::fs::create_dir_all(&src).unwrap();
    git(&src, &["init", "-q", "-b", "main"]);
    write(src.join("app.txt"), "v1\n");
    write(src.join("pnpm-lock.yaml"), "lock-top\nlock-mid\nlock-bot\n");
    git(&src, &["add", "-A"]);
    git(&src, &["commit", "-q", "-m", "initial"]);
    let bare = work.join("origin.git");
    git(
        work.path(),
        &[
            "clone",
            "-q",
            "--bare",
            src.to_str().unwrap(),
            bare.to_str().unwrap(),
        ],
    );
    let ws = work.join("workdir");
    let mut f = Fixture { work, bare, ws };

    // PR 1: clean merge.
    branch_with(&f, "pr1", "app-1.txt", "pr1\n");
    // PR 2: lock-only conflict (main also moves the lock).
    branch_with(&f, "pr2", "pnpm-lock.yaml", "lock-v1-pr2\n");
    // PR 3: a real conflict outside the lock (main also edits app.txt).
    branch_with(&f, "pr3", "app.txt", "pr3-edit\n");
    // PR 4: clean merge, but the reconcile fails.
    branch_with(&f, "pr4", "app-4.txt", "pr4\n");
    // PR 6: a bottom-line lock edit that merges textually with main's
    // top-line edit; the unconditional reset must discard the splice.
    branch_with(
        &f,
        "pr6",
        "pnpm-lock.yaml",
        "lock-top\nlock-mid\nlock-bot-pr6\n",
    );

    // Advance main.
    let s = scratch(&f, "mainadv");
    write(s.join("app.txt"), "main-v2\n");
    write(
        s.join("pnpm-lock.yaml"),
        "lock-top-v2\nlock-mid\nlock-bot\n",
    );
    git(&s, &["add", "-A"]);
    git(&s, &["commit", "-q", "-m", "main advances"]);
    git(&s, &["push", "-q", "origin", "main"]);
    // PR 5: branched from the advanced main: merging main is a no-op.
    let s = scratch(&f, "pr5");
    git(&s, &["push", "-q", "origin", "main:pr5-branch"]);

    // The working checkout (mirrors actions/checkout).
    git(
        f.work.path(),
        &[
            "clone",
            "-q",
            f.bare.to_str().unwrap(),
            f.ws.to_str().unwrap(),
        ],
    );
    git(&f.ws, &["config", "user.email", "placeholder@example.com"]);
    git(&f.ws, &["config", "user.name", "placeholder"]);
    f.ws = std::fs::canonicalize(&f.ws).unwrap();
    f
}

/// The run as CI makes it, from `cwd`, plus `extra` env.
fn run(f: &Fixture, cwd: &Path, prs: &str, extra: &[(&str, &str)]) -> Output {
    let out_dir = f.work.join("scratch-out");
    std::fs::create_dir_all(&out_dir).unwrap();
    let mut r = Run::new(&bin("BIN"))
        .cwd(cwd)
        .path_first(&f.work.join("bin"))
        .env("FAKE_PR_LIST_OUT", prs)
        .env("FAKE_BAZEL_LOG", f.work.join("bazel.log"))
        .env("REPO", "owner/repo")
        .env("GH_TOKEN", "x")
        .env("WORK_DIR", &out_dir)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null");
    for (k, v) in extra {
        r = r.env(k, v);
    }
    r.go()
}

struct Main {
    f: Fixture,
    out: Output,
}

/// The shell suite's single scenario run, shared by the assertions below.
fn main_run() -> &'static Main {
    static M: OnceLock<Main> = OnceLock::new();
    M.get_or_init(|| {
        let f = fixture();
        let out = run(&f, &f.ws.clone(), PRS_TSV, &[]);
        Main { f, out }
    })
}

fn main_is_ancestor_of(bare: &Path, branch: &str) -> bool {
    let main = git(bare, &["rev-parse", "main"]);
    let head = git(bare, &["rev-parse", branch]);
    std::process::Command::new("git")
        .arg("-C")
        .arg(bare)
        .args(["merge-base", "--is-ancestor", &main, &head])
        .status()
        .unwrap()
        .success()
}

#[test]
fn overall_exit_is_1_when_one_pr_conflicts_and_one_fails_to_reconcile() {
    let m = main_run();
    assert_eq!(m.out.code, 1, "{}", m.out.all());
}

#[test]
fn pr1_clean_merge_is_pushed() {
    let m = main_run();
    assert!(main_is_ancestor_of(&m.f.bare, "pr1-branch"));
    assert!(
        m.out.stdout.contains("#1: rebased onto main and pushed."),
        "{}",
        m.out.all()
    );
}

#[test]
fn pr2_lock_only_conflict_is_resolved_and_pushed() {
    let m = main_run();
    assert!(main_is_ancestor_of(&m.f.bare, "pr2-branch"));
    assert!(
        m.out.stdout.contains("#2: rebased onto main and pushed."),
        "{}",
        m.out.all()
    );
}

#[test]
fn pr3_conflict_outside_the_lock_is_left_for_a_human_and_not_pushed() {
    let m = main_run();
    assert!(
        m.out
            .stdout
            .contains("::warning::#3: conflicts outside pnpm-lock.yaml, leaving for a human:"),
        "{}",
        m.out.all()
    );
    assert!(
        m.out.stdout.lines().any(|l| l.trim() == "app.txt"),
        "the conflicting path is listed: {}",
        m.out.stdout
    );
    assert!(
        !main_is_ancestor_of(&m.f.bare, "pr3-branch"),
        "pr3 must not be pushed"
    );
}

#[test]
fn pr4_reconcile_failure_is_reported_and_not_pushed() {
    let m = main_run();
    assert!(
        m.out
            .stdout
            .contains("::error::#4: pnpm re-resolve failed; leaving the branch untouched."),
        "{}",
        m.out.all()
    );
    assert!(
        !main_is_ancestor_of(&m.f.bare, "pr4-branch"),
        "pr4 must not be pushed"
    );
}

#[test]
fn pr5_already_current_is_not_pushed() {
    let m = main_run();
    assert!(
        m.out
            .stdout
            .contains("#5: already current with main \u{2014} nothing to push."),
        "{}",
        m.out.all()
    );
}

#[test]
fn pr6_textual_lock_splice_is_reset_to_mains_lock() {
    let m = main_run();
    assert!(main_is_ancestor_of(&m.f.bare, "pr6-branch"));
    assert!(
        m.out.stdout.contains("#6: rebased onto main and pushed."),
        "{}",
        m.out.all()
    );
    let lock = git(&m.f.bare, &["show", "pr6-branch:pnpm-lock.yaml"]);
    assert!(
        !lock.contains("lock-bot-pr6"),
        "the textual splice survived: {lock}"
    );
    assert!(
        lock.lines().any(|l| l == "lock-bot"),
        "main's lock missing: {lock}"
    );
}

#[test]
fn pnpm_reconcile_runs_for_every_merged_pr_only() {
    let m = main_run();
    let log = read(m.f.work.join("bazel.log"));
    let n = log.lines().filter(|l| l.contains("@pnpm//:pnpm")).count();
    assert_eq!(n, 5, "PR3's aborted merge is the only one skipped:\n{log}");
    assert!(
        log.lines().all(|l| !l.contains("@pnpm//:pnpm")
            || l == format!(
                "run -- @pnpm//:pnpm install --dir {} --lockfile-only",
                m.f.ws.display()
            )),
        "pnpm re-resolves the checkout it runs in:\n{log}"
    );
    assert_eq!(
        log.lines().filter(|l| *l == "run //:tidy").count(),
        4,
        "{log}"
    );
}

#[test]
fn groups_open_and_close_once_per_pr() {
    let m = main_run();
    let opens = m
        .out
        .stdout
        .lines()
        .filter(|l| l.starts_with("::group::#"))
        .count();
    let closes = m
        .out
        .stdout
        .lines()
        .filter(|l| *l == "::endgroup::")
        .count();
    assert_eq!((opens, closes), (6, 6), "{}", m.out.stdout);
    assert!(m.out.stdout.contains("::group::#2 (pr2-branch)"));
}

// `bazel run` starts the binary in its runfiles tree with BUILD_WORKING_DIRECTORY
// naming the caller's directory: it must act on that checkout.
#[test]
fn under_bazel_run_it_acts_on_the_callers_checkout() {
    let f = fixture();
    let elsewhere = TempDir::new();
    let out = run(
        &f,
        elsewhere.path(),
        "1\tpr1-branch",
        &[("BUILD_WORKING_DIRECTORY", f.ws.to_str().unwrap())],
    );
    assert_eq!(out.code, 0, "{}", out.all());
    assert!(
        out.stdout.contains("#1: rebased onto main and pushed."),
        "{}",
        out.all()
    );
    assert!(main_is_ancestor_of(&f.bare, "pr1-branch"));
    let log = read(f.work.join("bazel.log"));
    assert!(
        log.contains(&format!("--dir {} --lockfile-only", f.ws.display())),
        "{log}"
    );
}

#[test]
fn no_open_prs_is_a_clean_no_op() {
    let f = fixture();
    let before = git(&f.ws, &["rev-parse", "HEAD"]);
    let out = run(&f, &f.ws.clone(), "", &[]);
    assert_eq!(out.code, 0, "{}", out.all());
    assert!(
        out.stdout
            .contains("No open Dependabot npm PRs \u{2014} nothing to rebase."),
        "{}",
        out.all()
    );
    assert_eq!(git(&f.ws, &["rev-parse", "HEAD"]), before);
    assert!(read(f.work.join("bazel.log")).is_empty());
}

#[test]
fn an_unfetchable_branch_is_skipped_with_a_warning_not_a_failure() {
    let f = fixture();
    let out = run(&f, &f.ws.clone(), "9\tno-such-branch\n1\tpr1-branch", &[]);
    assert_eq!(out.code, 0, "{}", out.all());
    assert!(
        out.stdout
            .contains("::warning::#9: cannot fetch no-such-branch; skipping."),
        "{}",
        out.all()
    );
    assert!(out.stdout.contains("#1: rebased onto main and pushed."));
}

#[test]
fn repo_is_required() {
    let f = fixture();
    let out = run(&f, &f.ws.clone(), PRS_TSV, &[("REPO", "")]);
    assert_ne!(out.code, 0);
    assert!(
        out.stderr.contains("REPO must be set (owner/repo)"),
        "{}",
        out.stderr
    );
    assert!(read(f.work.join("bazel.log")).is_empty());
}
