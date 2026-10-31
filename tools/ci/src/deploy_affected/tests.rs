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

//! Black-box tests of //tools/ci:deploy_affected, the deploy gate.
//!
//! Each test builds a REAL temp git repo (git diff is the thing under test)
//! and, for graph mode, a fake target-determinator given through TD_BIN. They
//! pin the FAIL-OPEN invariant (every uncertain path deploys), path-only mode
//! (#1351) and the release-please guard over the whole range (#1840).

use ci_testkit::{assert_has, assert_lacks, bin, git, read, write_exe, Output, Run, TempDir};
use std::path::PathBuf;

/// Prints $FAKE_TD_OUT (one target per line; empty = nothing affected);
/// FAKE_TD_RC forces a failure. Records its arguments in $TD_ARGS_LOG.
const FAKE_TD: &str = r#"#!/usr/bin/env bash
[ -z "${TD_ARGS_LOG:-}" ] || printf '%s\n' "$@" > "$TD_ARGS_LOG"
if [ "${FAKE_TD_RC:-0}" != "0" ]; then echo "td: boom" >&2; exit "${FAKE_TD_RC}"; fi
[ -n "${FAKE_TD_OUT:-}" ] && printf '%s\n' "${FAKE_TD_OUT}"
exit 0
"#;

struct Fx {
    work: TempDir,
    repo: PathBuf,
    td: PathBuf,
}

impl Fx {
    /// A repo with one seed commit, so the first test commit has a base.
    fn new() -> Fx {
        let work = TempDir::new();
        let repo = work.join("repo");
        std::fs::create_dir_all(&repo).unwrap();
        git(&repo, &["init", "-q", "."]);
        let td = work.join("fake-td");
        write_exe(&td, FAKE_TD);
        let fx = Fx { work, repo, td };
        fx.commit("README.md", "seed", "add README.md");
        fx
    }

    fn head(&self) -> String {
        git(&self.repo, &["rev-parse", "HEAD"])
    }

    /// One commit touching exactly `path`; returns the sha BEFORE it (the
    /// BEFORE_REV that shows only this commit's diff).
    fn commit(&self, path: &str, content: &str, msg: &str) -> String {
        let before = self.head_or_empty();
        ci_testkit::write(self.repo.join(path), format!("{content}\n"));
        git(&self.repo, &["add", "--", path]);
        git(&self.repo, &["commit", "-q", "-m", msg]);
        before
    }

    fn head_or_empty(&self) -> String {
        let o = std::process::Command::new("git")
            .arg("-C")
            .arg(&self.repo)
            .args(["rev-parse", "HEAD"])
            .output()
            .unwrap();
        String::from_utf8_lossy(&o.stdout).trim().to_string()
    }

    fn file(&self, path: &str) -> String {
        self.commit(path, "x", &format!("add {path}"))
    }

    /// Runs the gate in the repo with the shell suite's base env; returns the
    /// affected= value written to GITHUB_OUTPUT and the run.
    fn run(&self, before: &str, env: &[(&str, &str)]) -> (String, Output) {
        let out = self.work.join("out");
        std::fs::write(&out, "").unwrap();
        let mut r = Run::new(&bin("BIN"))
            .cwd(&self.repo)
            .env("GITHUB_OUTPUT", &out)
            .env("BEFORE_REV", before)
            .env("TD_BIN", &self.td)
            .env("BUILDBUDDY_API_KEY", "unused");
        for k in [
            "DEPLOY_TARGETS",
            "EXTRA_PATH_REGEX",
            "EXCLUDE_PATH_REGEX",
            "FORCED_PUSH",
            "AFTER_REV",
            "FAKE_TD_OUT",
            "FAKE_TD_RC",
        ] {
            r = r.env_remove(k);
        }
        for (k, v) in env {
            r = r.env(k, v);
        }
        let o = r.go();
        let affected: Vec<String> = read(&out)
            .lines()
            .filter_map(|l| l.strip_prefix("affected=").map(str::to_string))
            .collect();
        (affected.join("\n"), o)
    }

    #[track_caller]
    fn expect(&self, label: &str, before: &str, want: &str, env: &[(&str, &str)]) -> Output {
        let (got, o) = self.run(before, env);
        assert_eq!(
            got, want,
            "{label}\n--- stdout ---\n{}\n--- stderr ---\n{}",
            o.stdout, o.stderr
        );
        assert_eq!(o.code, 0, "{label}: a verdict exits 0\n{}", o.all());
        assert_has(
            &o.stdout,
            &format!("deploy-affected: affected={want} ("),
            label,
        );
        o
    }
}

// --- fail-open basics -----------------------------------------------------

#[test]
fn forced_push_always_deploys() {
    let fx = Fx::new();
    let sha = fx.file("app/a.txt");
    let o = fx.expect(
        "forced push",
        &sha,
        "true",
        &[("FORCED_PUSH", "true"), ("DEPLOY_TARGETS", "//x")],
    );
    assert_has(
        &o.stdout,
        "forced push -- no trustworthy diff base",
        "reason",
    );
}

#[test]
fn empty_before_rev_deploys() {
    let fx = Fx::new();
    let o = fx.expect("empty BEFORE_REV", "", "true", &[("DEPLOY_TARGETS", "//x")]);
    assert_has(
        &o.stdout,
        "BEFORE_REV '' unset or does not resolve to a commit",
        "reason",
    );
}

#[test]
fn garbage_before_rev_deploys() {
    let fx = Fx::new();
    let o = fx.expect(
        "garbage BEFORE_REV",
        "not-a-sha",
        "true",
        &[("DEPLOY_TARGETS", "//x")],
    );
    assert_has(
        &o.stdout,
        "BEFORE_REV 'not-a-sha' unset or does not resolve",
        "reason",
    );
}

// --- no-op diff -----------------------------------------------------------

#[test]
fn no_changed_files_vs_head_itself() {
    let fx = Fx::new();
    fx.file("app/a.txt");
    let head = fx.head();
    let o = fx.expect(
        "no-op diff",
        &head,
        "false",
        &[("DEPLOY_TARGETS", "//x"), ("FAKE_TD_OUT", "")],
    );
    assert_has(&o.stdout, &format!("no changed files vs {head}"), "reason");
}

// --- step 2: EXTRA_PATH_REGEX ----------------------------------------------

#[test]
fn extra_path_match_deploys_without_touching_td() {
    let fx = Fx::new();
    let sha = fx.file("tabula/infra/app/main.go");
    let log = fx.work.join("td-args");
    let log_s = log.to_str().unwrap();
    let o = fx.expect(
        "extra-path match",
        &sha,
        "true",
        &[
            ("DEPLOY_TARGETS", "//x"),
            ("EXTRA_PATH_REGEX", "tabula/infra/app/"),
            ("FAKE_TD_RC", "1"),
            ("TD_ARGS_LOG", log_s),
        ],
    );
    assert_has(&o.stdout, "path matched tabula/infra/app/)", "reason");
    assert!(!log.exists(), "target-determinator must not run");
    // The changed files are listed, indented.
    assert_has(
        &o.stdout,
        "deploy-affected: changed files:\n  tabula/infra/app/main.go\n",
        "listing",
    );
}

#[test]
fn excluded_path_does_not_satisfy_the_include_and_falls_to_td() {
    let fx = Fx::new();
    let sha = fx.file("oauth-user-inspector/infra/identity/x.go");
    fx.expect(
        "excluded include",
        &sha,
        "false",
        &[
            ("DEPLOY_TARGETS", "//x"),
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("EXCLUDE_PATH_REGEX", "oauth-user-inspector/infra/identity/"),
            ("FAKE_TD_OUT", ""),
        ],
    );
}

#[test]
fn exclude_reason_names_both_patterns() {
    let fx = Fx::new();
    let sha = fx.file("oauth-user-inspector/app/x.ts");
    let o = fx.expect(
        "include despite exclude",
        &sha,
        "true",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("EXCLUDE_PATH_REGEX", "oauth-user-inspector/infra/identity/"),
        ],
    );
    assert_has(
        &o.stdout,
        "(path matched oauth-user-inspector/ (excluding oauth-user-inspector/infra/identity/))",
        "reason",
    );
}

// --- step 3: global-impact guard ---------------------------------------------

#[test]
fn module_bazel_change_is_global_impact() {
    let fx = Fx::new();
    let sha = fx.file("MODULE.bazel");
    let o = fx.expect(
        "MODULE.bazel",
        &sha,
        "true",
        &[("DEPLOY_TARGETS", "//x"), ("FAKE_TD_RC", "1")],
    );
    assert_has(&o.stdout, "(global-impact file changed)", "reason");
    // The guard's grep is silent (the script sent it to /dev/null): the path
    // appears only once, indented, in the changed-files listing.
    assert!(
        !o.stdout.lines().any(|l| l == "MODULE.bazel"),
        "the global-impact grep leaked its match to stdout:\n{}",
        o.stdout
    );
}

#[test]
fn allowlisted_tools_ci_is_not_global_impact() {
    let fx = Fx::new();
    let sha = fx.file("tools/ci/allowed.sh");
    fx.expect(
        "tools/ci/ allowlisted",
        &sha,
        "false",
        &[("DEPLOY_TARGETS", "//x"), ("FAKE_TD_OUT", "")],
    );
}

#[test]
fn non_allowlisted_tools_dir_is_global_impact() {
    let fx = Fx::new();
    let sha = fx.file("tools/randomdir/x.sh");
    let o = fx.expect(
        "tools/randomdir",
        &sha,
        "true",
        &[("DEPLOY_TARGETS", "//x"), ("FAKE_TD_RC", "1")],
    );
    assert!(
        !o.stdout.lines().any(|l| l == "tools/randomdir/x.sh"),
        "grep leaked:\n{}",
        o.stdout
    );
}

// --- step 4: graph attribution -------------------------------------------------

#[test]
fn td_reports_a_target_affected() {
    let fx = Fx::new();
    let sha = fx.file("unrelated/z.txt");
    let o = fx.expect(
        "TD affected",
        &sha,
        "true",
        &[("DEPLOY_TARGETS", "//x"), ("FAKE_TD_OUT", "//x")],
    );
    assert_has(
        &o.stdout,
        "deploy-affected: affected deploy target(s):\n  //x\n",
        "lists the targets",
    );
    assert_has(
        &o.stdout,
        "(deploy target(s) affected by the diff)",
        "reason",
    );
    assert_eq!(
        read(fx.repo.join("deploy-affected.txt")),
        "//x\n",
        "TD output file"
    );
}

#[test]
fn td_reports_nothing_affected() {
    let fx = Fx::new();
    let sha = fx.file("unrelated/z.txt");
    let o = fx.expect(
        "TD empty",
        &sha,
        "false",
        &[("DEPLOY_TARGETS", "//x"), ("FAKE_TD_OUT", "")],
    );
    assert_has(
        &o.stdout,
        "(no deploy target affected by the diff)",
        "reason",
    );
    assert_lacks(&o.stdout, "::warning", "an empty answer is not degraded");
}

#[test]
fn td_error_fails_open_as_degraded() {
    let fx = Fx::new();
    let sha = fx.file("unrelated/z.txt");
    let summary = fx.work.join("summary.md");
    let o = fx.expect(
        "TD error",
        &sha,
        "true",
        &[
            ("DEPLOY_TARGETS", "//x"),
            ("FAKE_TD_RC", "1"),
            ("GITHUB_STEP_SUMMARY", summary.to_str().unwrap()),
        ],
    );
    assert_has(
        &o.stdout,
        "::warning title=deploy-gate-fallback::deploy gate degraded -- failing OPEN to deploy (target-determinator returned non-zero)",
        "degraded warning",
    );
    let s = read(&summary);
    assert_has(&s, "### ⚠ deploy-gate fallback (degraded)\n\n- reason: target-determinator returned non-zero\n", "summary");
    assert_has(
        &s,
        "check the target-determinator pin in tools/ci/src/deploy_affected/lib.rs",
        "summary names the pin",
    );
    assert_lacks(&s, "td-lib.sh", "the deleted script");
}

#[test]
fn td_invocation_and_universe() {
    let fx = Fx::new();
    let sha = fx.file("unrelated/z.txt");
    let log = fx.work.join("td-args");
    let o = fx.expect(
        "TD args",
        &sha,
        "false",
        &[
            ("DEPLOY_TARGETS", "//a:img  //b:zip"),
            ("FAKE_TD_OUT", ""),
            ("BUILDBUDDY_API_KEY", "k123"),
            ("TD_ARGS_LOG", log.to_str().unwrap()),
        ],
    );
    assert_eq!(
        read(&log),
        format!(
            "--bazel\nbazel\n--targets\n//a:img + //b:zip\n--bazel-opts=--config=remotecache-ci\n\
             --bazel-opts=--remote_header=x-buildbuddy-api-key=k123\n\
             --before-query-error-behavior=ignore-and-build-all\n{sha}\n"
        )
    );
    assert_has(
        &o.stdout,
        &format!("td-lib: using TD_BIN override at {}\n", fx.td.display()),
        "override line",
    );
    assert_has(
        &o.stdout,
        &format!("deploy-affected: computing affected deploy targets since {sha} (universe: //a:img + //b:zip)...\n"),
        "universe line",
    );
}

#[test]
fn td_output_of_one_blank_line_still_deploys() {
    // `[ -s file ]` is "non-empty": a lone newline is not proof of nothing.
    let fx = Fx::new();
    let sha = fx.file("unrelated/z.txt");
    write_exe(&fx.td, "#!/usr/bin/env bash\necho\n");
    fx.expect("blank TD line", &sha, "true", &[("DEPLOY_TARGETS", "//x")]);
}

#[test]
fn td_bin_that_is_not_executable_fails_open() {
    let fx = Fx::new();
    let sha = fx.file("unrelated/z.txt");
    let plain = fx.work.join("not-exec");
    std::fs::write(&plain, "#!/usr/bin/env bash\nexit 0\n").unwrap();
    let o = fx.expect(
        "non-executable TD_BIN",
        &sha,
        "true",
        &[
            ("DEPLOY_TARGETS", "//x"),
            ("TD_BIN", plain.to_str().unwrap()),
        ],
    );
    assert_has(
        &o.stdout,
        &format!(
            "target-determinator unavailable (TD_BIN='{}' is not an executable)",
            plain.display()
        ),
        "reason",
    );
    assert_has(
        &o.stdout,
        "::warning title=deploy-gate-fallback::",
        "degraded",
    );
}

// --- path-only mode (#1351) ------------------------------------------------------

#[test]
fn path_only_match_deploys() {
    let fx = Fx::new();
    let sha = fx.file("oauth-user-inspector/app/index.ts");
    fx.expect(
        "path-only match",
        &sha,
        "true",
        &[("EXTRA_PATH_REGEX", "oauth-user-inspector/")],
    );
}

#[test]
fn path_only_no_match_skips_without_td() {
    let fx = Fx::new();
    let sha = fx.file("docs/unrelated.md");
    let o = fx.expect(
        "path-only no match",
        &sha,
        "false",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("FAKE_TD_RC", "1"),
        ],
    );
    assert_has(&o.stdout, "no path matched (path-only mode", "reason");
}

/// The include regex is anchored at the start of the path: an app's
/// directory name appearing deeper in another tree is not that app.
#[test]
fn path_only_include_is_anchored_at_the_repo_root() {
    let fx = Fx::new();
    let sha = fx.file("docs/oauth-user-inspector/notes.md");
    let o = fx.expect(
        "nested include",
        &sha,
        "false",
        &[("EXTRA_PATH_REGEX", "oauth-user-inspector/")],
    );
    assert_has(&o.stdout, "no path matched (path-only mode", "reason");
}

/// The exclude regex is anchored too: a path that merely contains the
/// excluded directory deeper down still matches the include.
#[test]
fn path_only_exclude_is_anchored_at_the_repo_root() {
    let fx = Fx::new();
    let sha = fx.file("oauth-user-inspector/docs/oauth-user-inspector/infra/identity/y.md");
    fx.expect(
        "nested exclude",
        &sha,
        "true",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("EXCLUDE_PATH_REGEX", "oauth-user-inspector/infra/identity/"),
        ],
    );
}

#[test]
fn path_only_excluded_only_match_skips() {
    let fx = Fx::new();
    let sha = fx.file("oauth-user-inspector/infra/identity/y.go");
    fx.expect(
        "path-only excluded",
        &sha,
        "false",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("EXCLUDE_PATH_REGEX", "oauth-user-inspector/infra/identity/"),
        ],
    );
}

#[test]
fn path_only_does_not_apply_the_global_impact_guard() {
    let fx = Fx::new();
    let sha = fx.file("tools/randomdir/y.sh");
    fx.expect(
        "path-only global",
        &sha,
        "false",
        &[("EXTRA_PATH_REGEX", "oauth-user-inspector/")],
    );
}

#[test]
fn no_signal_at_all_is_a_hard_error() {
    let fx = Fx::new();
    let sha = fx.file("tools/randomdir/y.sh");
    let (got, o) = fx.run(&sha, &[]);
    assert_ne!(o.code, 0, "both unset must not exit 0");
    assert_eq!(got, "", "and must write no verdict");
    assert_has(&o.stderr, "no affected signal at all", "message");
}

// --- release-please version-bump guard ------------------------------------------------

#[test]
fn release_commit_chore_main_skips() {
    let fx = Fx::new();
    let sha = fx.commit(
        "oauth-user-inspector/package.json",
        r#"{"version":"1.7.2"}"#,
        "chore(main): release oauth-user-inspector 1.7.2",
    );
    let o = fx.expect(
        "chore(main): release",
        &sha,
        "false",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("FAKE_TD_RC", "1"),
        ],
    );
    assert_has(
        &o.stdout,
        "is a release-please version bump ('chore(main): release oauth-user-inspector 1.7.2') -- skipping dev deploy (promotes via release tag)",
        "reason",
    );
}

#[test]
fn release_commit_chore_release_skips() {
    let fx = Fx::new();
    let sha = fx.commit(
        "tabula/package.json",
        r#"{"version":"2.0.0"}"#,
        "chore(release): release tabula 2.0.0",
    );
    fx.expect(
        "chore(release): release",
        &sha,
        "false",
        &[("EXTRA_PATH_REGEX", "tabula/"), ("FAKE_TD_RC", "1")],
    );
}

#[test]
fn normal_feature_commit_matching_path_deploys() {
    let fx = Fx::new();
    let sha = fx.commit(
        "oauth-user-inspector/app/foo.ts",
        "x",
        "feat(oauth): update login feature",
    );
    fx.expect(
        "feature commit",
        &sha,
        "true",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("FAKE_TD_RC", "1"),
        ],
    );
}

#[test]
fn release_bump_at_head_does_not_dismiss_real_commits_behind_it() {
    // Live run 32363502989 (afc7e5c1..c0639105).
    let fx = Fx::new();
    let base = fx.head();
    fx.commit(
        "oauth-user-inspector/app/real-change.ts",
        "x",
        "feat(oauth): a real change that must deploy",
    );
    fx.commit(
        "oauth-user-inspector/package.json",
        r#"{"version":"1.7.3"}"#,
        "chore(main): release oauth-user-inspector 1.7.3",
    );
    fx.expect(
        "mixed range",
        &base,
        "true",
        &[
            ("EXTRA_PATH_REGEX", "oauth-user-inspector/"),
            ("FAKE_TD_RC", "1"),
        ],
    );
}

#[test]
fn an_all_release_commit_range_still_skips() {
    let fx = Fx::new();
    let base = fx.head();
    fx.commit(
        "tabula/package.json",
        r#"{"version":"2.0.1"}"#,
        "chore(main): release tabula 2.0.1",
    );
    fx.commit(
        "tabula/extension/package.json",
        r#"{"version":"0.1.38"}"#,
        "chore(main): release tabula-extension 0.1.38",
    );
    fx.expect(
        "all-release range",
        &base,
        "false",
        &[("EXTRA_PATH_REGEX", "tabula/"), ("FAKE_TD_RC", "1")],
    );
}

#[test]
fn after_rev_bounds_the_range() {
    // delivery-drift judges one commit at a time with AFTER_REV: a real
    // change AFTER the release commit must not count against it.
    let fx = Fx::new();
    let before = fx.commit(
        "tabula/package.json",
        r#"{"version":"3.0.0"}"#,
        "chore(main): release tabula 3.0.0",
    );
    let release = fx.head();
    fx.commit("tabula/app.ts", "x", "feat(tabula): later work");
    fx.expect(
        "AFTER_REV",
        &before,
        "false",
        &[("EXTRA_PATH_REGEX", "tabula/"), ("AFTER_REV", &release)],
    );
}

// --- bazel run --------------------------------------------------------------------------

#[test]
fn bazel_run_acts_in_the_callers_directory() {
    // `bazel run` starts the binary in its runfiles tree and names the
    // caller's directory in BUILD_WORKING_DIRECTORY.
    let fx = Fx::new();
    let sha = fx.file("oauth-user-inspector/app/index.ts");
    let elsewhere = TempDir::new();
    let out = fx.work.join("out-bwd");
    std::fs::write(&out, "").unwrap();
    let o = Run::new(&bin("BIN"))
        .cwd(elsewhere.path())
        .env("BUILD_WORKING_DIRECTORY", &fx.repo)
        .env("GITHUB_OUTPUT", &out)
        .env("BEFORE_REV", &sha)
        .env("EXTRA_PATH_REGEX", "oauth-user-inspector/")
        .env_remove("DEPLOY_TARGETS")
        .go();
    assert_eq!(o.code, 0, "{}", o.all());
    assert_eq!(
        read(&out),
        "affected=true\n",
        "same verdict as in the repo:\n{}",
        o.all()
    );
    let (in_repo, _) = fx.run(&sha, &[("EXTRA_PATH_REGEX", "oauth-user-inspector/")]);
    assert_eq!(in_repo, "true");
}

// --- large input ----------------------------------------------------------
//
// The gate pipes the range's commit subjects and changed paths through grep.
// Writing all of grep's stdin before reading its stdout deadlocks once grep's
// output fills the pipe (64 KiB): a ~3,000-commit range hung for minutes
// where the shell script answered in 0.28 s. Each test below pushes one of
// the four grep call sites past 256 KiB and times ONLY the gate's own run
// (the fixture is built first, untimed) against a 2 s budget.

/// The gate's time budget on 3,000 commits.
const BUDGET: std::time::Duration = std::time::Duration::from_secs(2);
/// A hang is killed here, so a deadlock fails the test instead of wedging it.
const HANG: std::time::Duration = std::time::Duration::from_secs(10);

/// `n` commits on top of HEAD in one `git fast-import`. Commit i has the
/// subject `subject(i)` and adds `{dir}/<long dir>/file-{i:05}.txt`, so the
/// changed-path list is about 100 bytes per commit. Returns the base sha.
fn bulk_commits(fx: &Fx, n: usize, dir: &str, subject: impl Fn(usize) -> String) -> String {
    use std::io::Write;
    let start = std::time::Instant::now();
    let base = fx.head();
    // Whatever the default branch is called, HEAD moves with it.
    let branch = git(&fx.repo, &["symbolic-ref", "HEAD"]);
    let mut s = String::new();
    for i in 0..n {
        let msg = format!("{}\n", subject(i));
        s.push_str(&format!("commit {branch}\n"));
        s.push_str("committer t <t@t> 1700000000 +0000\n");
        s.push_str(&format!("data {}\n{msg}", msg.len()));
        if i == 0 {
            s.push_str(&format!("from {base}\n"));
        }
        s.push_str(&format!(
            "M 100644 inline {dir}/a-fairly-long-directory-name-to-fatten-the-changed-path-list/file-{i:05}.txt\ndata 2\nx\n\n"
        ));
    }
    let mut child = std::process::Command::new("git")
        .arg("-C")
        .arg(&fx.repo)
        .args(["fast-import", "--quiet"])
        .stdin(std::process::Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(s.as_bytes()).unwrap();
    assert!(child.wait().unwrap().success(), "git fast-import failed");
    assert_eq!(
        git(&fx.repo, &["rev-list", "--count", &format!("{base}..HEAD")]),
        n.to_string(),
        "the fixture range"
    );
    eprintln!("fixture: {n} commits in {:?} (untimed)", start.elapsed());
    base
}

/// Runs the gate once over `base..HEAD` and times only that run. Returns the
/// run, its wall time, and what it wrote to GITHUB_OUTPUT.
fn timed_gate(fx: &Fx, base: &str, env: &[(&str, &str)]) -> (Output, std::time::Duration, String) {
    let out = fx.work.join("out-big");
    std::fs::write(&out, "").unwrap();
    let mut r = Run::new(&bin("BIN"))
        .cwd(&fx.repo)
        .env("GITHUB_OUTPUT", &out)
        .env("BEFORE_REV", base)
        .env("TD_BIN", &fx.td)
        .env("BUILDBUDDY_API_KEY", "unused");
    for k in [
        "DEPLOY_TARGETS",
        "EXTRA_PATH_REGEX",
        "EXCLUDE_PATH_REGEX",
        "FORCED_PUSH",
        "AFTER_REV",
        "FAKE_TD_OUT",
        "FAKE_TD_RC",
    ] {
        r = r.env_remove(k);
    }
    for (k, v) in env {
        r = r.env(k, v);
    }
    let start = std::time::Instant::now();
    let o = r.go_within(HANG).unwrap_or_else(|| {
        panic!("deploy-affected did not finish within {HANG:?} on a 3,000-commit range (grep pipe deadlock)")
    });
    let took = start.elapsed();
    eprintln!("deploy-affected on 3,000 commits: {took:?}");
    assert!(
        took < BUDGET,
        "deploy-affected took {took:?} on 3,000 commits; the budget is {BUDGET:?}\n{}",
        o.all()
    );
    (o, took, read(&out))
}

/// The release-please guard: about 300 KiB of subjects through `grep -Ev`.
/// No path matches, so the path greps print nothing and only the guard can
/// fill a pipe.
#[test]
fn a_huge_range_of_subjects_does_not_hang_the_release_guard() {
    let fx = Fx::new();
    let pad = "x".repeat(80);
    let base = bulk_commits(&fx, 3000, "bigapp", |i| {
        format!("feat(app): change {i:05} {pad}")
    });
    let (o, _, out) = timed_gate(&fx, &base, &[("EXTRA_PATH_REGEX", "elsewhere/")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&out, "affected=false", "no path matched");
    assert_has(&o.stdout, "affected=false (no path matched", "reason");
}

/// The release guard still sees every subject of a huge range: 2,999 release
/// bumps and one real commit at the very bottom is not a release-only range.
#[test]
fn a_huge_range_of_release_bumps_still_finds_the_one_real_commit() {
    let fx = Fx::new();
    let base = bulk_commits(&fx, 3000, "bigapp", |i| {
        if i == 0 {
            "fix(app): the one real change".to_string()
        } else {
            format!("chore(main): release app {i}.0.0 with a long enough subject to fill the pipe")
        }
    });
    let (o, _, out) = timed_gate(&fx, &base, &[("EXTRA_PATH_REGEX", "bigapp/")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&out, "affected=true", "the real commit deploys");
    assert_lacks(
        &o.stdout,
        "release-please version bump",
        "not a release-only range",
    );
}

/// Path-only mode: about 300 KiB of changed paths through `grep -E` and then
/// the exclude's `grep -Ev`, with short subjects so the guard is not the cause.
#[test]
fn a_huge_changed_path_list_does_not_hang_the_path_match() {
    let fx = Fx::new();
    let base = bulk_commits(&fx, 3000, "bigapp", |i| format!("c{i}"));
    let (o, _, out) = timed_gate(
        &fx,
        &base,
        &[
            ("EXTRA_PATH_REGEX", "bigapp/"),
            ("EXCLUDE_PATH_REGEX", "bigapp/never-matches/"),
        ],
    );
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(&out, "affected=true", "a matching path deploys");
    assert_has(
        &o.stdout,
        "path matched bigapp/ (excluding bigapp/never-matches/)",
        "reason",
    );
    assert_has(&o.stdout, "file-02999.txt", "every changed file is listed");
}

/// Graph mode: about 300 KiB of tools/ paths through the global-impact
/// guard's `grep -E ^tools/` and its allowlist `grep -Ev`.
#[test]
fn a_huge_tools_change_does_not_hang_the_global_impact_guard() {
    let fx = Fx::new();
    let base = bulk_commits(&fx, 3000, "tools/bigtool", |i| format!("c{i}"));
    let (o, _, out) = timed_gate(&fx, &base, &[("DEPLOY_TARGETS", "//apps/x:image")]);
    assert_eq!(o.code, 0, "{}", o.all());
    assert_has(
        &out,
        "affected=true",
        "an unlisted tools/ dir is global impact",
    );
    assert_has(&o.stdout, "global-impact file changed", "reason");
}
