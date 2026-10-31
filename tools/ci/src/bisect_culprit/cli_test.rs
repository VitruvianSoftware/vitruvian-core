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

//! Black-box guard for the bisect-culprit binary: each case builds a throwaway
//! git repo (no network, no Bazel; `TEST_CMD` is the binary's own documented
//! per-commit hook) and drives the real executable.
//!
//! THE CASE THIS FILE EXISTS FOR: GOOD_SHA == BAD_SHA. `git merge-base
//! --is-ancestor` cannot reject it, because a commit is its own ancestor, so
//! the ancestry guard alone passes the one input that degenerates bisect. The
//! equality guard turns it into an input error (exit 2); without it git itself
//! refuses at `git bisect start` and the run would report the failure under the
//! "bisect could not identify a culprit" code. `git_refuses_same_commit_itself`
//! is the control that shows the guard is still needed.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn binary() -> PathBuf {
    let rel = std::env::var("BISECT_CULPRIT_BIN").expect("BISECT_CULPRIT_BIN is set by Bazel");
    std::env::current_dir().unwrap().join(rel)
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

/// A repo with `n` commits; commit i writes i to ./marker.
fn make_repo(n: u32) -> (tempdir::Dir, PathBuf) {
    let dir = tempdir::Dir::new();
    let p = dir.path().to_path_buf();
    git(&p, &["init", "-q", "."]);
    git(&p, &["config", "user.email", "test@example.com"]);
    git(&p, &["config", "user.name", "test"]);
    git(&p, &["config", "commit.gpgsign", "false"]);
    for i in 1..=n {
        std::fs::write(p.join("marker"), format!("{i}\n")).unwrap();
        git(&p, &["add", "marker"]);
        git(&p, &["commit", "-qm", &format!("commit {i}")]);
    }
    (dir, p)
}

fn run(repo: &Path, envs: &[(&str, &str)]) -> Output {
    let mut c = Command::new(binary());
    c.current_dir(repo)
        .env_remove("GITHUB_OUTPUT")
        .env_remove("TEST_CMD")
        .env_remove("BAZEL_ARGS")
        .env("GIT_TERMINAL_PROMPT", "0");
    for (k, v) in envs {
        c.env(k, v);
    }
    c.output().expect("binary runs")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

/// git's refusal when one commit is marked both good and bad. The quoting
/// varies by git build ("was both 'good' and 'bad'" on Homebrew git, without
/// quotes on Apple git and Ubuntu git); accept either.
fn is_both_good_and_bad(s: &str) -> bool {
    s.contains("was both good and bad") || s.contains("was both 'good' and 'bad'")
}

mod tempdir {
    use std::path::{Path, PathBuf};
    pub struct Dir(PathBuf);
    impl Dir {
        pub fn new() -> Dir {
            use std::sync::atomic::{AtomicU32, Ordering};
            static N: AtomicU32 = AtomicU32::new(0);
            let base = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
            let p = Path::new(&base).join(format!(
                "bisect-culprit-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::SeqCst)
            ));
            std::fs::create_dir_all(&p).unwrap();
            Dir(p)
        }
        pub fn path(&self) -> &Path {
            &self.0
        }
    }
    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
}

#[test]
fn same_commit_is_an_input_error() {
    let (_d, repo) = make_repo(3);
    let s = git(&repo, &["rev-parse", "HEAD"]);
    let o = run(
        &repo,
        &[
            ("GOOD_SHA", &s),
            ("BAD_SHA", &s),
            ("TARGETS", "//:noop"),
            ("TEST_CMD", "true"),
        ],
    );
    let t = text(&o);
    assert_eq!(o.status.code(), Some(2), "{t}");
    assert!(t.contains("are the same commit"), "{t}");
    // Short-circuited before `git bisect start`, so git's own refusal never appears.
    assert!(!is_both_good_and_bad(&t), "reached git bisect start: {t}");
}

#[test]
fn abbreviated_and_full_sha_of_one_commit_are_the_same_commit() {
    let (_d, repo) = make_repo(3);
    let s = git(&repo, &["rev-parse", "HEAD"]);
    let o = run(
        &repo,
        &[
            ("GOOD_SHA", &s[..8]),
            ("BAD_SHA", &s),
            ("TARGETS", "//:noop"),
            ("TEST_CMD", "true"),
        ],
    );
    let t = text(&o);
    assert_eq!(o.status.code(), Some(2), "{t}");
    assert!(t.contains("are the same commit"), "{t}");
}

#[test]
fn git_refuses_same_commit_itself() {
    // The delete-the-fix control: with no equality guard the run would die at
    // `git bisect start` with this message, under the wrong exit code.
    let (_d, repo) = make_repo(3);
    let s = git(&repo, &["rev-parse", "HEAD"]);
    let o = Command::new("git")
        .arg("-C")
        .arg(&repo)
        .args(["bisect", "start", &s, &s])
        .output()
        .unwrap();
    assert!(!o.status.success());
    assert!(is_both_good_and_bad(&text(&o)), "{}", text(&o));
    let _ = Command::new("git")
        .arg("-C")
        .arg(&repo)
        .args(["bisect", "reset"])
        .output();
}

#[test]
fn unrelated_history_is_rejected_by_the_ancestry_guard() {
    let (_d, repo) = make_repo(2);
    let branch = git(&repo, &["rev-parse", "--abbrev-ref", "HEAD"]);
    git(&repo, &["checkout", "-q", "--orphan", "other"]);
    std::fs::write(repo.join("marker"), "other\n").unwrap();
    git(&repo, &["add", "marker"]);
    git(&repo, &["commit", "-qm", "orphan"]);
    let orphan = git(&repo, &["rev-parse", "HEAD"]);
    git(&repo, &["checkout", "-q", &branch]);
    let head = git(&repo, &["rev-parse", "HEAD"]);
    let o = run(
        &repo,
        &[
            ("GOOD_SHA", &orphan),
            ("BAD_SHA", &head),
            ("TARGETS", "//:noop"),
            ("TEST_CMD", "true"),
        ],
    );
    let t = text(&o);
    assert_eq!(o.status.code(), Some(2), "{t}");
    assert!(t.contains("not an ancestor"), "{t}");
}

#[test]
fn unresolvable_revision_is_an_input_error() {
    let (_d, repo) = make_repo(2);
    let head = git(&repo, &["rev-parse", "HEAD"]);
    let o = run(
        &repo,
        &[
            ("GOOD_SHA", "no-such-ref"),
            ("BAD_SHA", &head),
            ("TARGETS", "//:noop"),
            ("TEST_CMD", "true"),
        ],
    );
    let t = text(&o);
    assert_eq!(o.status.code(), Some(2), "{t}");
    assert!(
        t.contains("'no-such-ref' does not resolve to a commit"),
        "{t}"
    );
}

#[test]
fn missing_environment_fails_naming_the_variable() {
    let (_d, repo) = make_repo(2);
    let head = git(&repo, &["rev-parse", "HEAD"]);
    for (set, missing) in [
        (
            vec![("BAD_SHA", head.as_str()), ("TARGETS", "//:noop")],
            "GOOD_SHA",
        ),
        (
            vec![("GOOD_SHA", head.as_str()), ("TARGETS", "//:noop")],
            "BAD_SHA",
        ),
        (
            vec![("GOOD_SHA", head.as_str()), ("BAD_SHA", head.as_str())],
            "TARGETS",
        ),
    ] {
        let o = run(&repo, &set);
        let t = text(&o);
        assert_eq!(o.status.code(), Some(1), "{missing}: {t}");
        assert!(
            t.contains(&format!("{missing} must be set")),
            "{missing}: {t}"
        );
    }
}

#[test]
fn a_real_range_converges_on_the_first_bad_commit() {
    let (_d, repo) = make_repo(5);
    let good = git(&repo, &["rev-parse", "HEAD~4"]);
    let bad = git(&repo, &["rev-parse", "HEAD"]);
    let want = git(&repo, &["rev-parse", "HEAD~2"]);
    let gh_out = repo
        .join("..")
        .join(format!("gh_out_{}", std::process::id()));
    let _ = std::fs::remove_file(&gh_out);
    let o = run(
        &repo,
        &[
            ("GOOD_SHA", &good),
            ("BAD_SHA", &bad),
            ("TARGETS", "//:noop"),
            ("GITHUB_OUTPUT", gh_out.to_str().unwrap()),
            // Bad from commit 3 onward.
            ("TEST_CMD", "test \"$(cat marker)\" -lt 3"),
        ],
    );
    let t = text(&o);
    assert_eq!(o.status.code(), Some(0), "{t}");
    let written = std::fs::read_to_string(&gh_out).unwrap_or_default();
    let _ = std::fs::remove_file(&gh_out);
    assert!(
        written.contains(&format!("culprit={want}\n")),
        "{written}\n{t}"
    );
    assert!(written.contains("culprit_subject=commit 3\n"), "{written}");
    // The log is streamed to our stdout, culprit line included.
    assert!(
        t.contains(&format!("bisect-culprit: culprit={want} (commit 3)")),
        "{t}"
    );
    // Bisect state is cleaned up afterwards.
    assert!(!repo.join(".git/BISECT_START").exists());
}

#[test]
fn a_range_where_every_midpoint_is_skipped_does_not_converge() {
    let (_d, repo) = make_repo(4);
    let good = git(&repo, &["rev-parse", "HEAD~3"]);
    let bad = git(&repo, &["rev-parse", "HEAD"]);
    let o = run(
        &repo,
        // 125 means "cannot test this commit": git is left with only skipped
        // candidates and names none of them as the first bad commit.
        &[
            ("GOOD_SHA", &good),
            ("BAD_SHA", &bad),
            ("TARGETS", "//:noop"),
            ("TEST_CMD", "exit 125"),
        ],
    );
    let t = text(&o);
    assert_eq!(o.status.code(), Some(1), "{t}");
    assert!(
        t.contains("did not converge on a single first-bad commit"),
        "{t}"
    );
    assert!(!repo.join(".git/BISECT_START").exists());
}
