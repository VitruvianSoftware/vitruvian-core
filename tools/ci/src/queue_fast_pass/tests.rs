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

//! Black-box tests for //tools/ci:queue_fast_pass (#2841, #3418). A real git
//! repository supplies the tree hash and a fake `gh` plays GitHub, answering
//! from JSON files the test writes. Runs the REAL binary, with jq from the
//! Bazel toolchain on PATH as the runner has it. The point of most cases is
//! that doubt is always a miss. Ported case for case from the former
//! queue-fast-pass_test.sh.

use ci_testkit::{
    bin, git, names_job, read, verdict_fail_open, workflow_job_text, workflow_jobs, write,
    write_exe, Output, Run, TempDir,
};
use std::path::{Path, PathBuf};

/// `gh api <path>` prints $GH_STUB_DIR/<path with / ? & = turned into _>, or
/// fails when that file is absent. Every path asked for goes to `calls`.
const FAKE_GH: &str = r#"#!/usr/bin/env bash
[ "$1" = api ] || exit 64
echo "$2" >>"$GH_STUB_DIR/calls"
f="$GH_STUB_DIR/$(printf '%s' "$2" | tr '/?&=' '____')"
[ -f "$f" ] || exit 1
cat "$f"
"#;

fn key(path: &str) -> String {
    path.chars()
        .map(|c| if "/?&=".contains(c) { '_' } else { c })
        .collect()
}

/// The directory holding jq from the Bazel toolchain (JQ_BIN is an execpath:
/// external/<repo>/jq, which sits at ../<repo>/jq from the runfiles root).
fn jq_dir() -> PathBuf {
    let jq = std::env::var("JQ_BIN").expect("JQ_BIN (the BUILD file passes the jq toolchain)");
    let jq = match jq.strip_prefix("external/") {
        Some(rest) => format!("../{rest}"),
        None => jq,
    };
    let jq = std::fs::canonicalize(&jq).unwrap_or_else(|e| panic!("jq at {jq}: {e}"));
    jq.parent().unwrap().to_path_buf()
}

struct Gh {
    _dir: TempDir,
    repo: PathBuf,
    bin: PathBuf,
    api: PathBuf,
}

impl Gh {
    /// A repo with one commit (`f` = one) and an empty fake GitHub.
    fn new() -> Gh {
        let dir = TempDir::new();
        let repo = dir.join("repo");
        std::fs::create_dir_all(&repo).unwrap();
        git(&repo, &["init", "-q", "."]);
        write(repo.join("f"), "one\n");
        git(&repo, &["add", "f"]);
        git(&repo, &["commit", "-q", "-m", "c1"]);
        let bin = dir.join("bin");
        write_exe(bin.join("gh"), FAKE_GH);
        let api = dir.join("api");
        std::fs::create_dir_all(&api).unwrap();
        Gh {
            repo,
            bin,
            api,
            _dir: dir,
        }
    }

    /// A second commit (`f` = two), as the shell suite made before its
    /// "different tree" and `queued` cases.
    fn second_commit(&self) {
        write(self.repo.join("f"), "two\n");
        git(&self.repo, &["commit", "-q", "-am", "c2"]);
    }

    fn tree(&self) -> String {
        git(&self.repo, &["rev-parse", "HEAD^{tree}"])
    }

    fn marker(&self) -> String {
        format!("passed-presubmit-{}", self.tree())
    }

    fn reply(&self, path: &str, body: &str) {
        write(self.api.join(key(path)), body);
    }

    fn calls(&self) -> String {
        read(self.api.join("calls"))
    }

    fn artifacts(&self, body: &str) {
        let path = format!(
            "repos/o/r/actions/artifacts?name={}&per_page=30",
            self.marker()
        );
        self.reply(&path, body);
    }

    fn run_json(&self, id: u64, body: &str) {
        self.reply(&format!("repos/o/r/actions/runs/{id}"), body);
    }

    fn artifact(&self, id: u64, run: u64, head_repo_id: u64, expired: bool) -> String {
        format!(
            r#"{{"name":"{}","expired":{},"created_at":"2026-10-09T0{}:00:00Z","workflow_run":{{"id":{},"repository_id":7,"head_repository_id":{}}}}}"#,
            self.marker(),
            expired,
            id,
            run,
            head_repo_id
        )
    }

    fn run(&self, args: &[&str], env: &[(&str, &str)]) -> Output {
        self.run_in(&self.repo, args, env)
    }

    fn run_in(&self, dir: &Path, args: &[&str], env: &[(&str, &str)]) -> Output {
        let path = format!(
            "{}:{}:{}",
            self.bin.display(),
            jq_dir().display(),
            std::env::var("PATH").unwrap_or_default()
        );
        let mut r = Run::new(&bin("BIN"))
            .cwd(dir)
            .args(args)
            .env("PATH", path)
            .env("GH_STUB_DIR", &self.api)
            .env("GITHUB_REPOSITORY", "o/r")
            .env("WORKFLOW_PATH", ".github/workflows/presubmit.yaml")
            .env_remove("PUSH_BEFORE")
            .env_remove("FORCED_PUSH")
            .env_remove("CACHE_KEY_REGEX")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_CONFIG_GLOBAL", "/dev/null");
        for (k, v) in env {
            r = r.env(k, v);
        }
        r.go()
    }

    fn reset(&self) {
        let _ = std::fs::remove_dir_all(&self.api);
        std::fs::create_dir_all(&self.api).unwrap();
    }
}

fn good_run(id: u64, event: &str, conclusion: &str, repo: &str, path: &str) -> String {
    format!(
        r#"{{"id":{id},"event":"{event}","conclusion":{c},"head_repository":{{"full_name":"{repo}"}},"path":"{path}"}}"#,
        // "json-null" is GitHub's real null for a run still in progress; the
        // shell suite's "null" was the quoted string, kept for parity.
        c = if conclusion == "json-null" {
            "null".to_string()
        } else {
            format!("\"{conclusion}\"")
        }
    )
}

fn good(id: u64) -> String {
    good_run(
        id,
        "pull_request",
        "success",
        "o/r",
        ".github/workflows/presubmit.yaml",
    )
}

fn said(o: &Output, line: &str) -> bool {
    o.stdout.lines().any(|l| l == line)
}

#[track_caller]
fn assert_miss(o: &Output, what: &str) {
    assert!(
        o.code == 0 && said(o, "verdict=miss") && said(o, "run="),
        "{what}: got {o:?}"
    );
}

// --- tree

#[test]
fn tree_prints_the_tree_hash_and_marker_and_asks_github_nothing() {
    let g = Gh::new();
    let o = g.run(&["tree"], &[]);
    assert_eq!(o.code, 0, "{o:?}");
    assert!(said(&o, &format!("tree={}", g.tree())), "{o:?}");
    assert!(said(&o, &format!("marker={}", g.marker())), "{o:?}");
    assert!(
        !o.stdout.contains("verdict="),
        "tree printed a verdict: {o:?}"
    );
    assert_eq!(g.calls(), "", "tree called gh");
}

// --- lookup: hit

#[test]
fn a_passed_pull_request_run_on_the_same_tree_is_a_hit() {
    let g = Gh::new();
    g.artifacts(&format!(
        r#"{{"artifacts":[{}]}}"#,
        g.artifact(1, 100, 7, false)
    ));
    g.run_json(100, &good(100));
    let o = g.run(&["lookup", "presubmit"], &[]);
    assert!(
        o.code == 0 && said(&o, "verdict=hit") && said(&o, "run=100"),
        "{o:?}"
    );
}

#[test]
fn lookup_writes_the_same_lines_to_github_output() {
    let g = Gh::new();
    g.artifacts(&format!(
        r#"{{"artifacts":[{}]}}"#,
        g.artifact(1, 100, 7, false)
    ));
    g.run_json(100, &good(100));
    let gho = g.repo.parent().unwrap().join("gho");
    write(&gho, "");
    g.run(
        &["lookup", "presubmit"],
        &[("GITHUB_OUTPUT", &gho.display().to_string())],
    );
    let got = read(&gho);
    assert!(
        got.lines().any(|l| l == "verdict=hit")
            && got.lines().any(|l| l == format!("tree={}", g.tree())),
        "GITHUB_OUTPUT: {got:?}"
    );
}

#[test]
fn a_newer_failed_run_does_not_hide_an_older_passed_one() {
    let g = Gh::new();
    g.artifacts(&format!(
        r#"{{"artifacts":[{},{}]}}"#,
        g.artifact(1, 100, 7, false),
        g.artifact(2, 200, 7, false)
    ));
    g.run_json(100, &good(100));
    g.run_json(
        200,
        &good_run(
            200,
            "pull_request",
            "failure",
            "o/r",
            ".github/workflows/presubmit.yaml",
        ),
    );
    let o = g.run(&["lookup", "presubmit"], &[]);
    assert!(said(&o, "verdict=hit") && said(&o, "run=100"), "{o:?}");
}

// --- lookup: doubt is a miss

#[test]
fn lookup_misses_when_github_is_unreachable() {
    let g = Gh::new();
    assert_miss(&g.run(&["lookup", "presubmit"], &[]), "GitHub unreachable");
}

#[test]
fn lookup_misses_on_an_empty_or_unreadable_artifact_list() {
    let g = Gh::new();
    g.artifacts(r#"{"artifacts":[]}"#);
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "no marker for this tree",
    );
    g.reset();
    g.artifacts("not json");
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "unreadable artifact list",
    );
}

#[test]
fn lookup_misses_on_an_expired_or_forked_marker() {
    let g = Gh::new();
    g.artifacts(&format!(
        r#"{{"artifacts":[{}]}}"#,
        g.artifact(1, 100, 7, true)
    ));
    g.run_json(100, &good(100));
    assert_miss(&g.run(&["lookup", "presubmit"], &[]), "marker has expired");
    g.reset();
    g.artifacts(&format!(
        r#"{{"artifacts":[{}]}}"#,
        g.artifact(1, 100, 99, false)
    ));
    g.run_json(100, &good(100));
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "marker was uploaded by a fork's run",
    );
}

#[test]
fn lookup_misses_when_the_run_behind_the_marker_cannot_be_read() {
    let g = Gh::new();
    g.artifacts(&format!(
        r#"{{"artifacts":[{}]}}"#,
        g.artifact(1, 100, 7, false)
    ));
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "the run cannot be read",
    );
}

#[test]
fn lookup_misses_unless_the_run_is_a_successful_pull_request_run() {
    for (event, conclusion) in [
        ("merge_group", "success"),
        ("push", "success"),
        ("pull_request", "failure"),
        ("pull_request", "cancelled"),
        ("pull_request", "null"),
        ("pull_request", "json-null"),
    ] {
        let g = Gh::new();
        g.artifacts(&format!(
            r#"{{"artifacts":[{}]}}"#,
            g.artifact(1, 100, 7, false)
        ));
        g.run_json(
            100,
            &good_run(
                100,
                event,
                conclusion,
                "o/r",
                ".github/workflows/presubmit.yaml",
            ),
        );
        assert_miss(
            &g.run(&["lookup", "presubmit"], &[]),
            &format!("run is '{event} {conclusion}'"),
        );
    }
}

#[test]
fn lookup_misses_on_a_forked_run_or_another_workflow() {
    let g = Gh::new();
    g.artifacts(&format!(
        r#"{{"artifacts":[{}]}}"#,
        g.artifact(1, 100, 7, false)
    ));
    g.run_json(
        100,
        &good_run(
            100,
            "pull_request",
            "success",
            "someone/fork",
            ".github/workflows/presubmit.yaml",
        ),
    );
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "run's head repository is a fork",
    );
    g.run_json(
        100,
        &good_run(
            100,
            "pull_request",
            "success",
            "o/r",
            ".github/workflows/other.yaml",
        ),
    );
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "run is of a different workflow",
    );
}

#[test]
fn an_artifact_with_a_different_name_in_the_reply_is_ignored() {
    let g = Gh::new();
    let other = g
        .artifact(1, 100, 7, false)
        .replace(&g.marker(), &format!("{}x", g.marker()));
    g.artifacts(&format!(r#"{{"artifacts":[{other}]}}"#));
    g.run_json(100, &good(100));
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "artifact with a different name",
    );
}

// --- lookup: a different tree does not match

#[test]
fn after_the_files_change_the_old_marker_is_not_found() {
    let g = Gh::new();
    let old = g.artifact(1, 100, 7, false);
    let old_marker = g.marker();
    g.second_commit();
    // The reply is filed under the OLD tree's marker query.
    g.reply(
        &format!("repos/o/r/actions/artifacts?name={old_marker}&per_page=30"),
        &format!(r#"{{"artifacts":[{old}]}}"#),
    );
    g.run_json(100, &good(100));
    assert_miss(
        &g.run(&["lookup", "presubmit"], &[]),
        "the old marker after the files change",
    );
    assert!(
        g.calls()
            .contains(&format!("passed-presubmit-{}", g.tree())),
        "it did not ask for the new tree's marker: {}",
        g.calls()
    );
}

// --- queued: a push to main the merge queue already passed

struct Queued {
    g: Gh,
    before: String,
    head: String,
}

impl Queued {
    /// HEAD is c2; c1 is main before the push. The queue squash-merges, so
    /// the commit that lands has the tree its merge_group run tested.
    fn new() -> Queued {
        let g = Gh::new();
        g.second_commit();
        let before = git(&g.repo, &["rev-parse", "HEAD~1"]);
        let head = git(&g.repo, &["rev-parse", "HEAD"]);
        Queued { g, before, head }
    }

    fn changed(&self, files: &[&str]) {
        let list: Vec<String> = files
            .iter()
            .map(|f| format!(r#"{{"filename":"{f}"}}"#))
            .collect();
        self.compare(&format!(r#"{{"files":[{}]}}"#, list.join(",")));
    }

    fn compare(&self, body: &str) {
        self.g.reply(
            &format!("repos/o/r/compare/{}...{}", self.before, self.head),
            body,
        );
    }

    fn queue_runs(&self, runs: &str) {
        self.g.reply(
            "repos/o/r/actions/workflows/presubmit.yaml/runs?event=merge_group&status=success&per_page=30",
            &format!(r#"{{"workflow_runs":[{runs}]}}"#),
        );
    }

    fn queue_run(
        id: u64,
        tree: &str,
        event: &str,
        conclusion: &str,
        repo: &str,
        path: &str,
    ) -> String {
        let c = if conclusion == "json-null" {
            "null".to_string()
        } else {
            format!("\"{conclusion}\"")
        };
        format!(
            r#"{{"id":{id},"event":"{event}","conclusion":{c},"head_repository":{{"full_name":"{repo}"}},"path":"{path}","head_commit":{{"tree_id":"{tree}"}}}}"#
        )
    }

    fn matching(&self, id: u64) -> String {
        Self::queue_run(
            id,
            &self.g.tree(),
            "merge_group",
            "success",
            "o/r",
            ".github/workflows/presubmit.yaml",
        )
    }

    fn run(&self, env: &[(&str, &str)]) -> Output {
        let mut all: Vec<(&str, &str)> =
            vec![("PUSH_BEFORE", &self.before), ("FORCED_PUSH", "false")];
        all.extend_from_slice(env);
        self.g.run(&["queued"], &all)
    }
}

const OTHER_TREE: &str = "0000000000000000000000000000000000000001";

#[test]
fn a_green_merge_group_run_on_the_same_tree_skips_the_re_test() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    q.queue_runs(&q.matching(300));
    let o = q.run(&[]);
    assert!(
        o.code == 0 && said(&o, "verdict=hit") && said(&o, "run=300"),
        "{o:?}"
    );
}

#[test]
fn a_newer_queue_run_on_other_code_does_not_hide_the_matching_one() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    let other = Queued::queue_run(
        301,
        OTHER_TREE,
        "merge_group",
        "success",
        "o/r",
        ".github/workflows/presubmit.yaml",
    );
    q.queue_runs(&format!("{other},{}", q.matching(300)));
    let o = q.run(&[]);
    assert!(said(&o, "verdict=hit") && said(&o, "run=300"), "{o:?}");
}

#[test]
fn it_asks_about_the_calling_workflow_and_a_presubmit_run_does_not_count_for_ci() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    q.queue_runs(&q.matching(300));
    let o = q.run(&[("WORKFLOW_PATH", ".github/workflows/ci.yaml")]);
    assert!(said(&o, "verdict=miss"), "{o:?}");
    assert!(
        q.g.calls().contains("workflows/ci.yaml/runs"),
        "asked: {}",
        q.g.calls()
    );
}

// --- queued: anything else runs everything

#[test]
fn queued_misses_with_no_queue_run_or_a_run_on_other_code() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    q.queue_runs("");
    assert_miss(&q.run(&[]), "no merge queue run at all (a direct push)");
    q.queue_runs(&Queued::queue_run(
        300,
        OTHER_TREE,
        "merge_group",
        "success",
        "o/r",
        ".github/workflows/presubmit.yaml",
    ));
    assert_miss(&q.run(&[]), "the queue tested different code");
}

#[test]
fn queued_misses_unless_the_matching_run_is_a_successful_merge_group_run() {
    for (event, conclusion) in [
        ("push", "success"),
        ("pull_request", "success"),
        ("merge_group", "failure"),
        ("merge_group", "cancelled"),
        ("merge_group", "null"),
        ("merge_group", "json-null"),
    ] {
        let q = Queued::new();
        q.changed(&["apps/web/page.ts"]);
        q.queue_runs(&Queued::queue_run(
            300,
            &q.g.tree(),
            event,
            conclusion,
            "o/r",
            ".github/workflows/presubmit.yaml",
        ));
        assert_miss(
            &q.run(&[]),
            &format!("the matching run is '{event} {conclusion}'"),
        );
    }
}

#[test]
fn queued_misses_on_a_forked_run_or_another_workflow() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    q.queue_runs(&Queued::queue_run(
        300,
        &q.g.tree(),
        "merge_group",
        "success",
        "someone/fork",
        ".github/workflows/presubmit.yaml",
    ));
    assert_miss(&q.run(&[]), "the matching run came from a fork");
    q.queue_runs(&Queued::queue_run(
        300,
        &q.g.tree(),
        "merge_group",
        "success",
        "o/r",
        ".github/workflows/other.yaml",
    ));
    assert_miss(&q.run(&[]), "the matching run is of another workflow");
}

#[test]
fn queued_misses_when_github_cannot_answer() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    assert_miss(&q.run(&[]), "the queue runs cannot be listed");
    q.g.reset();
    q.queue_runs(&q.matching(300));
    assert_miss(&q.run(&[]), "the changed files cannot be listed");
}

#[test]
fn queued_misses_on_300_or_more_changed_files() {
    let q = Queued::new();
    let mut body = String::from(r#"{"files":["#);
    for _ in 0..300 {
        body.push_str(r#"{"filename":"x"},"#);
    }
    body.push_str(r#"{"filename":"last"}]}"#);
    q.compare(&body);
    q.queue_runs(&q.matching(300));
    assert_miss(
        &q.run(&[]),
        "300 or more changed files (the list may be cut short)",
    );
}

#[test]
fn queued_misses_when_the_push_changed_a_file_a_main_only_cache_is_keyed_on() {
    for f in [
        "MODULE.bazel",
        "MODULE.bazel.lock",
        ".bazelversion",
        ".bazelrc",
        "go.sum",
        "apps/cli/devx/go.mod",
        "go.work.sum",
        ".xcode-version",
        "apps/cli/devx/.golangci.yml",
    ] {
        let q = Queued::new();
        q.changed(&["docs/a.md", f]);
        q.queue_runs(&q.matching(300));
        assert_miss(&q.run(&[]), &format!("the push changed {f}"));
    }
}

#[test]
fn queued_misses_on_a_forced_push_or_no_usable_before_commit() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    q.queue_runs(&q.matching(300));
    assert_miss(&q.run(&[("FORCED_PUSH", "true")]), "a forced push");
    assert_miss(
        &q.run(&[("PUSH_BEFORE", "0000000000000000000000000000000000000000")]),
        "main was just created (before is all zeros)",
    );
    assert_miss(&q.run(&[("PUSH_BEFORE", "")]), "no before commit");
}

#[test]
fn queued_refuses_a_workflow_path_that_is_not_a_workflow_file() {
    let q = Queued::new();
    q.changed(&["apps/web/page.ts"]);
    q.queue_runs(&q.matching(300));
    let o = q.run(&[("WORKFLOW_PATH", "../../etc/passwd")]);
    assert!(said(&o, "verdict=miss"), "{o:?}");
    assert!(
        !q.g.calls().contains("actions/workflows"),
        "asked GitHub anyway: {}",
        q.g.calls()
    );
}

// --- queued: ci.yaml waits on the lookup the safe way

/// Every job in CI must skip on a hit and must still run when the lookup job
/// itself is skipped, which it is on every pull request and in the queue. A
/// job that needs `queued` without !cancelled() or always() would be skipped
/// there too, and GitHub counts a skipped required check as passing: that
/// change would never be tested. (A job that forgets the hit check only
/// wastes a run.)
#[test]
fn every_ci_yaml_job_skips_on_a_hit_and_runs_when_the_lookup_is_skipped() {
    let ci = std::fs::read_to_string(".github/workflows/ci.yaml").unwrap();
    let mut count = 0;
    let mut bad = Vec::new();
    for j in workflow_jobs(&ci) {
        if j.id == "queued" || j.id == "fast-lane" {
            continue;
        }
        count += 1;
        let mut why = Vec::new();
        if !names_job(&j.needs, "queued") {
            why.push("does not need queued");
        }
        if !j.cond.contains("needs.queued.outputs.hit != 'true'") {
            why.push("does not skip on a hit");
        }
        if !(j.cond.contains("!cancelled()") || j.cond.contains("always()")) {
            why.push("would be skipped whenever queued is skipped");
        }
        if !why.is_empty() {
            bad.push(format!("ci.yaml job {}: {}", j.id, why.join("; ")));
        }
    }
    assert!(
        count >= 10,
        "read only {count} ci.yaml jobs; the parser is out of date"
    );
    assert!(bad.is_empty(), "{}", bad.join("\n"));
}

// --- bad input

#[test]
fn outside_a_git_repository_it_misses_and_exits_0() {
    let g = Gh::new();
    let outside = TempDir::new();
    let o = g.run_in(outside.path(), &["lookup", "presubmit"], &[]);
    assert!(
        o.code == 0 && said(&o, "verdict=miss") && said(&o, "tree="),
        "{o:?}"
    );
}

#[test]
fn it_refuses_a_check_name_that_is_not_a_plain_slug() {
    let o = Gh::new().run(&["lookup", "bad name;rm"], &[]);
    assert_eq!(o.code, 2, "accepted a bad check name: {o:?}");
}

#[test]
fn it_refuses_an_unknown_mode() {
    let o = Gh::new().run(&["nonsense"], &[]);
    assert_eq!(o.code, 2, "accepted an unknown mode: {o:?}");
}

// --- an empty verdict always means the full run ---------------------------
//
// The lookup's build step is continue-on-error, so a failed build leaves the
// verdict empty, as does a failed lookup. Each comparison has to name "hit"
// the right way round or "" turns into a skip (#4173 review: `hit: ... !=
// 'miss'` went unnoticed).

#[test]
fn ci_yaml_skips_only_on_an_explicit_hit() {
    let ci = std::fs::read_to_string(".github/workflows/ci.yaml").unwrap();
    let q = workflow_job_text(&ci, "queued");
    assert!(
        q.contains("\n      hit: ${{ steps.lookup.outputs.verdict == 'hit' }}\n"),
        "queued's hit output must be exactly verdict == 'hit':\n{q}"
    );
    let bad = verdict_fail_open(&ci, "lookup", "hit");
    assert!(bad.is_empty(), "ci.yaml:\n{}", bad.join("\n"));
}

#[test]
fn presubmit_skips_only_on_an_explicit_hit() {
    let p = std::fs::read_to_string(".github/workflows/presubmit.yaml").unwrap();
    let bad = verdict_fail_open(&p, "queued", "hit");
    assert!(bad.is_empty(), "presubmit.yaml:\n{}", bad.join("\n"));
    assert!(
        p.contains("if [ \"$QUEUED\" = \"hit\" ]; then"),
        "the planner no longer plans nothing for an explicit hit"
    );
}
