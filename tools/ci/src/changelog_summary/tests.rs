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

//! Black-box tests for //tools/ci:changelog_summary, the release-notes panel
//! `_changelog-summary.yaml` and foundation-release.yaml write onto a run's
//! summary page before a gated deploy is approved. Runs the REAL binary on
//! fixture changelogs and throwaway git repos. Ported case for case from the
//! former changelog-summary_test.sh, plus exact-output checks of the panels
//! (taken from the script's own output) and the never-fail contract.

use ci_testkit::{
    assert_has, assert_lacks, bin, commit_file, git_init, read, write, Output, Run, TempDir,
};
use std::path::Path;

const CHANGELOG: &str = "# Changelog

## [1.3.0](https://example/compare/v1.2.0...v1.3.0) (2026-07-19)


### Features

* **thing:** add the new thing ([#42](https://example/issues/42))

## [1.2.0](https://example/compare/v1.1.0...v1.2.0) (2026-07-01)


### Bug Fixes

* **thing:** fix the old thing ([#7](https://example/issues/7))
";

/// A temp dir holding `demo/CHANGELOG.md`.
fn fixture() -> (TempDir, String) {
    let t = TempDir::new();
    let cl = t.join("demo/CHANGELOG.md");
    write(&cl, CHANGELOG);
    let p = cl.display().to_string();
    (t, p)
}

fn run_in(cwd: &Path, args: &[&str]) -> Output {
    Run::new(&bin("BIN")).cwd(cwd).args(args).go()
}

fn run(args: &[&str]) -> Output {
    Run::new(&bin("BIN")).args(args).go()
}

// --- 1) the top (most recent) block -----------------------------------------

#[test]
fn top_block_is_the_latest_release_nested_one_level_under_the_title() {
    let (_t, cl) = fixture();
    let o = run(&[&cl, "", "demo"]);
    assert_eq!(o.code, 0, "{o:?}");
    // The script's exact bytes: blank lines inside the block kept, the ones
    // before the next `## ` dropped, then `---`.
    assert_eq!(
        o.stdout,
        "## 📓 demo — release notes\n\n\
         ### [1.3.0](https://example/compare/v1.2.0...v1.3.0) (2026-07-19)\n\n\n\
         #### Features\n\n\
         * **thing:** add the new thing ([#42](https://example/issues/42))\n\n\
         ---\n\n"
    );
    assert_lacks(
        &o.stdout,
        "fix the old thing",
        "top excludes the older release",
    );
}

// --- 2) a specific (older) version ------------------------------------------

#[test]
fn a_pinned_version_selects_that_block_only() {
    let (_t, cl) = fixture();
    let o = run(&[&cl, "1.2.0", "demo"]);
    assert_eq!(o.code, 0);
    assert_has(&o.stdout, "### [1.2.0]", "pin: 1.2.0 block");
    assert_has(&o.stdout, "#### Bug Fixes", "pin: nested heading");
    assert_has(&o.stdout, "fix the old thing", "pin: 1.2.0 content");
    assert_lacks(&o.stdout, "add the new thing", "pin excludes the latest");
    assert!(
        o.stdout
            .ends_with("([#7](https://example/issues/7))\n\n---\n\n"),
        "{}",
        o.stdout
    );
}

// --- 3) a v-prefixed version normalizes -------------------------------------

#[test]
fn a_v_prefixed_version_normalizes() {
    let (_t, cl) = fixture();
    let o = run(&[&cl, "v1.3.0", "demo"]);
    assert_has(&o.stdout, "### [1.3.0]", "v-prefix normalizes");
    assert_lacks(&o.stdout, "fix the old thing", "v-prefix: only 1.3.0");
}

// --- 4) an unknown version: a note, exit 0 ----------------------------------

#[test]
fn an_unknown_version_is_a_note_and_exit_zero() {
    let (_t, cl) = fixture();
    let o = run(&[&cl, "9.9.9", "demo"]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        o.stdout,
        format!("## 📓 demo\n\n_Release notes for `9.9.9` not found in `{cl}`._\n\n")
    );
}

#[test]
fn a_changelog_with_no_release_headings_says_latest_was_not_found() {
    let t = TempDir::new();
    let cl = t.join("x/CHANGELOG.md");
    write(&cl, "just prose\n");
    let cl = cl.display().to_string();
    let o = run(&[&cl, "", "x"]);
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "_Release notes for `latest` not found in `",
        "latest note",
    );
}

// --- 5) a missing file: a note, exit 0 --------------------------------------

#[test]
fn a_missing_file_is_a_note_and_exit_zero() {
    let t = TempDir::new();
    let nope = t.join("nope.md").display().to_string();
    let o = run(&[&nope, "", "ghost"]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        o.stdout,
        format!("## 📓 ghost\n\n_No changelog found at `{nope}`._\n\n")
    );
}

// --- 6) default title is the changelog's directory name ---------------------

#[test]
fn the_default_title_is_the_changelog_directory_name() {
    let (_t, cl) = fixture();
    let o = run(&[&cl]);
    assert_has(&o.stdout, "## 📓 demo — release notes", "default title");
}

#[test]
fn a_bare_filename_titles_the_panel_dot() {
    // basename(dirname("CHANGELOG.md")) is ".", as in the script.
    let t = TempDir::new();
    let o = run_in(t.path(), &["CHANGELOG.md"]);
    assert_eq!(
        o.stdout,
        "## 📓 .\n\n_No changelog found at `CHANGELOG.md`._\n\n"
    );
}

#[test]
fn no_arguments_is_a_usage_error_exit_two() {
    let o = run(&[]);
    assert_eq!(o.code, 2);
    assert_has(
        &o.stderr,
        "usage: changelog_summary <changelog-path>",
        "usage",
    );
    assert_eq!(o.stdout, "");
}

// --- deploy scope: WHAT IS SHIPPING (--range / --path) ----------------------

struct Repo {
    _t: TempDir,
    dir: std::path::PathBuf,
    base: String,
    head: String,
    cl: String,
}

/// first (app) <- base, unrelated (other), second (app) <- head.
fn repo() -> Repo {
    let (t, cl) = fixture();
    let dir = t.join("repo");
    git_init(&dir);
    let base = commit_file(&dir, "app/x.txt", "a\n", "feat(app): first thing");
    commit_file(&dir, "other/y.txt", "b\n", "chore(other): unrelated thing");
    let head = commit_file(&dir, "app/z.txt", "c\n", "fix(app): second thing");
    Repo {
        _t: t,
        dir,
        base,
        head,
        cl,
    }
}

#[test]
fn range_lists_the_shipping_commits_filtered_by_path_above_the_changelog() {
    let r = repo();
    let range = format!("{}..{}", r.base, r.head);
    let o = run_in(
        &r.dir,
        &[&r.cl, "", "demo", "--range", &range, "--path", "app"],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert!(
        o.stdout.starts_with("## 🚢 demo — shipping in this deploy\n\n* fix(app): second thing\n\n## 📓 demo — release notes\n\n"),
        "{}",
        o.stdout
    );
    assert_lacks(&o.stdout, "unrelated thing", "out-of-path commit");
    assert_lacks(&o.stdout, "first thing", "the base itself");
    assert_has(&o.stdout, "add the new thing", "changelog still rendered");
}

#[test]
fn range_without_a_path_lists_every_commit_in_it() {
    let r = repo();
    let range = format!("{}..{}", r.base, r.head);
    let o = run_in(&r.dir, &[&r.cl, "", "demo", "--range", &range]);
    assert_has(
        &o.stdout,
        "* fix(app): second thing\n* chore(other): unrelated thing\n\n",
        "both commits, newest first",
    );
}

#[test]
fn flags_may_come_before_the_positionals() {
    let r = repo();
    let range = format!("{}..{}", r.base, r.head);
    let o = run_in(
        &r.dir,
        &["--path", "app", "--range", &range, &r.cl, "", "demo"],
    );
    assert_has(
        &o.stdout,
        "## 🚢 demo — shipping in this deploy\n\n* fix(app): second thing\n",
        "flags first",
    );
    assert_has(
        &o.stdout,
        "## 📓 demo — release notes",
        "positionals after flags",
    );
}

#[test]
fn an_empty_range_is_a_note_naming_range_and_path_exit_zero() {
    let r = repo();
    let range = format!("{0}..{0}", r.head);
    let o = run_in(
        &r.dir,
        &[&r.cl, "", "demo", "--range", &range, "--path", "app"],
    );
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        &format!(
            "## 🚢 demo — shipping in this deploy\n\n_No commits in `{range}` touching `app`._\n\n"
        ),
        "empty-range note",
    );
    let o = run_in(&r.dir, &[&r.cl, "", "demo", "--range", &range]);
    assert_has(
        &o.stdout,
        &format!("_No commits in `{range}`._\n\n"),
        "no path: no `touching`",
    );
}

#[test]
fn a_bogus_range_never_fails_the_caller() {
    let r = repo();
    let range = format!("deadbeef..{}", r.head);
    let o = run_in(
        &r.dir,
        &[&r.cl, "", "demo", "--range", &range, "--path", "app"],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        &format!("_Scope could not be determined for `{range}` (unknown revision, or a shallow clone without that history)._\n\n"),
        "bogus-range note",
    );
    assert_eq!(
        o.stderr, "",
        "git's complaint stays out of the log, as 2>/dev/null did"
    );
    assert_has(&o.stdout, "add the new thing", "changelog still rendered");
}

#[test]
fn without_git_on_path_the_range_is_undeterminable_not_fatal() {
    let (_t, cl) = fixture();
    let empty = TempDir::new();
    let o = Run::new(&bin("BIN"))
        .env("PATH", empty.path())
        .args([cl.as_str(), "", "demo", "--range", "a..b"])
        .go();
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "_Scope could not be determined for `a..b`",
        "no git",
    );
}

// --- the GitHub sink ---------------------------------------------------------

#[test]
fn under_actions_the_panel_is_appended_to_the_step_summary_not_stdout() {
    let r = repo();
    let summary = r._t.join("summary.md");
    write(&summary, "earlier step\n");
    let range = format!("{}..{}", r.base, r.head);
    let o = Run::new(&bin("BIN"))
        .cwd(&r.dir)
        .env("GITHUB_STEP_SUMMARY", &summary)
        .args([
            r.cl.as_str(),
            "",
            "demo",
            "--range",
            &range,
            "--path",
            "app",
        ])
        .go();
    assert_eq!(o.code, 0);
    assert_eq!(o.stdout, "", "nothing on stdout under Actions");
    let s = read(&summary);
    assert!(
        s.starts_with("earlier step\n## 🚢 demo — shipping"),
        "appended, not replaced: {s}"
    );
    assert_has(&s, "## 📓 demo — release notes", "both panels appended");
}

// --- parsing details the script's awk/sed fixed ------------------------------

#[test]
fn trailing_blank_lines_of_the_block_collapse_to_one_newline() {
    let t = TempDir::new();
    let cl = t.join("c/CHANGELOG.md");
    write(&cl, "## [1.0.0]\n* x\n\n\n\n");
    let o = run(&[&cl.display().to_string(), "", "c"]);
    assert_eq!(
        o.stdout,
        "## 📓 c — release notes\n\n### [1.0.0]\n* x\n\n---\n\n"
    );
}

#[test]
fn a_crlf_changelog_keeps_its_carriage_returns_like_the_script() {
    let t = TempDir::new();
    let cl = t.join("c/CHANGELOG.md");
    write(&cl, "## [1.0.0]\r\n### F\r\n* a\r\n\r\n## [0.9.0]\r\n");
    let o = run(&[&cl.display().to_string(), "", "c"]);
    // Only `\n` is trimmed off the block's end; the last `\r` stays.
    assert_eq!(
        o.stdout,
        "## 📓 c — release notes\n\n### [1.0.0]\r\n#### F\r\n* a\r\n\r\n\n---\n\n"
    );
}

#[test]
fn the_version_is_the_first_non_empty_bracket_as_awk_matched_it() {
    let t = TempDir::new();
    let cl = t.join("c/CHANGELOG.md");
    write(&cl, "## [] [1.2.0] odd\n* odd\n");
    let o = run(&[&cl.display().to_string(), "1.2.0", "c"]);
    assert_eq!(
        o.stdout,
        "## 📓 c — release notes\n\n### [] [1.2.0] odd\n* odd\n\n---\n\n"
    );
}

#[test]
fn only_the_first_v_is_stripped() {
    let t = TempDir::new();
    let cl = t.join("c/CHANGELOG.md");
    write(&cl, "## [v1.0.0]\n* a\n");
    let o = run(&[&cl.display().to_string(), "vv1.0.0", "c"]);
    assert_has(&o.stdout, "### [v1.0.0]", "`vv1.0.0` looks for `v1.0.0`");
}
