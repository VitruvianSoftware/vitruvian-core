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

//! Black-box tests for //tools/ci:agent_fast_lane (#3418, Step 2b), and for
//! how ci.yaml and presubmit.yaml use it. Runs the REAL binary against the
//! real agent roster. The point of most cases is that only one exact
//! combination skips the heavy jobs; everything else runs them. Ported case
//! for case from the former agent-fast-lane_test.sh.

use ci_testkit::{
    bin, names_job, read, workflow_job_text, workflow_jobs, write, Output, Run, TempDir,
};

const ROSTER: &str = "tools/agent-app/agents.tsv";
const CI: &str = ".github/workflows/ci.yaml";
const PRESUBMIT: &str = ".github/workflows/presubmit.yaml";

/// A real agent's bot user id, read from the real roster, so the test
/// follows it.
fn agent_id() -> String {
    let text = std::fs::read_to_string(ROSTER).expect("read the agent roster");
    let id = text
        .lines()
        .filter(|l| !l.starts_with('#'))
        .map(|l| l.split('\t').collect::<Vec<_>>())
        .find(|f| f.len() >= 4)
        .map(|f| f[3].to_string())
        .unwrap_or_default();
    assert!(
        !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()),
        "could not read an agent id from {ROSTER}: {id:?}"
    );
    id
}

/// An agent PR from this repo with the label, unless an override changes
/// one part of it.
fn decide(overrides: &[(&str, &str)]) -> Output {
    let roster = std::fs::canonicalize(ROSTER).unwrap();
    let mut r = Run::new(&bin("BIN"))
        .env("EVENT_NAME", "pull_request")
        .env("GITHUB_REPOSITORY", "o/r")
        .env("PR_HEAD_REPO", "o/r")
        .env("PR_AUTHOR_TYPE", "Bot")
        .env("PR_AUTHOR_ID", agent_id())
        .env("PR_LABELS", r#"["ci","agent-fast-lane"]"#)
        .env("AGENTS_TSV", roster);
    for (k, v) in overrides {
        r = r.env(k, v);
    }
    r.go()
}

fn said(o: &Output, line: &str) -> bool {
    o.stdout.lines().any(|l| l == line)
}

#[track_caller]
fn full(what: &str, overrides: &[(&str, &str)]) {
    let o = decide(overrides);
    assert!(o.code == 0 && said(&o, "verdict=full"), "{what}: got {o:?}");
    assert!(
        o.stdout.lines().any(|l| l.starts_with("reason=")),
        "{what}: no reason given: {o:?}"
    );
}

// --- the one case that skips

#[test]
fn an_agent_pr_from_this_repo_with_the_label_is_fast() {
    let o = decide(&[]);
    assert!(o.code == 0 && said(&o, "verdict=fast"), "got {o:?}");
}

#[test]
fn writes_the_verdict_to_github_output() {
    let dir = TempDir::new();
    let gho = dir.join("gho");
    write(&gho, "");
    let o = decide(&[("GITHUB_OUTPUT", &gho.display().to_string())]);
    assert_eq!(o.code, 0, "{o:?}");
    assert!(
        read(&gho).lines().any(|l| l == "verdict=fast"),
        "GITHUB_OUTPUT: {:?}",
        read(&gho)
    );
}

// --- everything else runs in full

#[test]
fn a_fork_pr_with_the_label() {
    full("a fork PR with the label", &[("PR_HEAD_REPO", "someone/r")]);
}

#[test]
fn a_person_with_the_label() {
    full(
        "a PR opened by a person",
        &[("PR_AUTHOR_TYPE", "User"), ("PR_AUTHOR_ID", "3703513")],
    );
    full(
        "a person whose user id happens to match an agent's",
        &[("PR_AUTHOR_TYPE", "User")],
    );
}

#[test]
fn a_bot_that_is_not_one_of_our_agents() {
    full(
        "a bot that is not one of our agents",
        &[("PR_AUTHOR_ID", "49699333")],
    );
}

#[test]
fn label_problems() {
    full(
        "an agent PR without the label",
        &[("PR_LABELS", r#"["ci"]"#)],
    );
    full("an agent PR with no labels at all", &[("PR_LABELS", "[]")]);
    full(
        "a label that only looks similar",
        &[("PR_LABELS", r#"["agent-fast-lane-x","Agent-Fast-Lane"]"#)],
    );
    full("an unreadable label list", &[("PR_LABELS", "not json")]);
    full(
        "a label list that is not a list",
        &[("PR_LABELS", r#""agent-fast-lane""#)],
    );
    full("an empty label list value", &[("PR_LABELS", "")]);
}

#[test]
fn events_other_than_a_pull_request() {
    full("a merge_group event", &[("EVENT_NAME", "merge_group")]);
    full("a push event", &[("EVENT_NAME", "push")]);
}

#[test]
fn author_id_problems() {
    full("no author id", &[("PR_AUTHOR_ID", "")]);
    full(
        "an author id that is not a number",
        &[("PR_AUTHOR_ID", "1 OR 1")],
    );
}

#[test]
fn roster_problems() {
    let dir = TempDir::new();
    full(
        "the roster is missing",
        &[("AGENTS_TSV", &dir.join("nope.tsv").display().to_string())],
    );
    let commented = dir.join("commented.tsv");
    write(
        &commented,
        format!(
            "# agent\tapp_id\tinstallation_id\tbot_user_id\n#x\t1\t2\t{}\n",
            agent_id()
        ),
    );
    full(
        "an id that appears only in a comment line",
        &[("AGENTS_TSV", &commented.display().to_string())],
    );
}

#[test]
fn github_repository_unset() {
    full("GITHUB_REPOSITORY unset", &[("GITHUB_REPOSITORY", "")]);
}

// --- ci.yaml: heavy jobs skip on the fast lane, the fast checks never do

#[test]
fn ci_yaml_heavy_jobs_skip_on_the_fast_lane_and_fast_checks_never_do() {
    let ci = std::fs::read_to_string(CI).unwrap();
    // The fast checks that live in ci.yaml. The rest (secret scan, osv-scan,
    // conformance, tidy, actionlint) are other workflows and never see the label.
    let fast_checks = ["license-check", "lint-naming"];
    let mut count = 0;
    let mut bad = Vec::new();
    for j in workflow_jobs(&ci) {
        if j.id == "queued" || j.id == "fast-lane" {
            continue;
        }
        count += 1;
        let both = format!("{}{}", j.needs, j.cond);
        if fast_checks.contains(&j.id.as_str()) {
            if both.contains("fast-lane") {
                bad.push(format!(
                    "fast check {} must always run on a PR, but it reads fast-lane",
                    j.id
                ));
            }
            continue;
        }
        let mut why = Vec::new();
        if !names_job(&j.needs, "fast-lane") {
            why.push("does not need fast-lane");
        }
        if !j.cond.contains("needs.fast-lane.outputs.skip != 'true'") {
            why.push("does not skip on the fast lane");
        }
        if !(j.cond.contains("!cancelled()") || j.cond.contains("always()")) {
            why.push("would be skipped whenever fast-lane is skipped");
        }
        if !why.is_empty() {
            bad.push(format!("heavy job {}: {}", j.id, why.join("; ")));
        }
    }
    assert!(
        count >= 10,
        "read only {count} ci.yaml jobs; the parser is out of date"
    );
    assert!(bad.is_empty(), "{}", bad.join("\n"));
}

/// The fast-lane job decides with main's copy of the rule and roster: the
/// rule is built from a checkout of the base commit, and the roster is read
/// from that checkout. Only the build action comes from the pull request.
#[test]
fn ci_yaml_fast_lane_builds_and_reads_the_base_commit() {
    let ci = std::fs::read_to_string(CI).unwrap();
    let fl = workflow_job_text(&ci, "fast-lane");
    assert!(!fl.is_empty(), "ci.yaml has no fast-lane job");
    assert!(
        fl.contains("    if: github.event_name == 'pull_request' && contains(github.event.pull_request.labels.*.name, 'agent-fast-lane')"),
        "fast-lane must be skipped unless the PR has the label:\n{fl}"
    );
    assert!(
        fl.contains("ref: ${{ github.event.pull_request.base.sha }}\n          path: base\n"),
        "fast-lane must check the PR's base commit out under base/:\n{fl}"
    );
    assert!(
        fl.contains("tool: agent_fast_lane\n          source-root: base\n"),
        "fast-lane must build the rule from the base checkout:\n{fl}"
    );
    assert!(
        fl.contains("AGENTS_TSV: base/tools/agent-app/agents.tsv\n"),
        "fast-lane must read the roster from the base checkout:\n{fl}"
    );
    assert!(
        fl.contains("\"$FAST_LANE\""),
        "fast-lane no longer runs the built rule:\n{fl}"
    );
}

/// presubmit.yaml (generated by //tools/pipeline:gen) does the same with
/// `git show` of the base commit's files.
#[test]
fn presubmit_fast_lane_builds_and_reads_the_base_commit() {
    let p = std::fs::read_to_string(PRESUBMIT).unwrap();
    for needle in [
        "if ! git show \"$PR_BASE_SHA:$f\" > \"$src/$f\"; then",
        "tools/ci/src/agent_fast_lane/lib.rs tools/ci/src/agent_fast_lane/main.rs tools/shell-compat/src/lib.rs tools/agent-app/agents.tsv",
        "source-root: ${{ steps.fastlane-src.outputs.root }}",
        "AGENTS_TSV: ${{ steps.fastlane-src.outputs.root }}/tools/agent-app/agents.tsv",
        "\"$FAST_LANE\" | tee",
    ] {
        assert!(p.contains(needle), "presubmit.yaml's fast lane lost: {needle}");
    }
}
