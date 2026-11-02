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
    bin, names_job, read, step_env, step_list, step_run, step_value, verdict_fail_open,
    workflow_job_text, workflow_jobs, workflow_steps, write, Output, Run, TempDir,
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
        fl.contains("\"$FAST_LANE_BIN\""),
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
        "\"$FAST_LANE_BIN\" | tee",
    ] {
        assert!(p.contains(needle), "presubmit.yaml's fast lane lost: {needle}");
    }
}

// --- an empty verdict always means the full run ---------------------------
//
// The rule's build step is continue-on-error, so a failed build leaves the
// verdict empty, as does a failed or skipped decide step. Each comparison has
// to name "fast" the right way round or "" turns into a skip (#4173 review:
// `skip: ... != 'full'` went unnoticed).

#[test]
fn ci_yaml_skips_only_on_an_explicit_fast() {
    let ci = std::fs::read_to_string(CI).unwrap();
    let fl = workflow_job_text(&ci, "fast-lane");
    assert!(
        fl.contains("\n      skip: ${{ steps.decide.outputs.verdict == 'fast' }}\n"),
        "fast-lane's skip output must be exactly verdict == 'fast':\n{fl}"
    );
    let bad = verdict_fail_open(&ci, "decide", "fast");
    assert!(bad.is_empty(), "ci.yaml:\n{}", bad.join("\n"));
}

#[test]
fn presubmit_skips_only_on_an_explicit_fast() {
    let p = std::fs::read_to_string(PRESUBMIT).unwrap();
    let bad = verdict_fail_open(&p, "fastlane", "fast");
    assert!(bad.is_empty(), "presubmit.yaml:\n{}", bad.join("\n"));
    assert!(
        p.contains("if [ \"$FAST_LANE\" = \"fast\" ]; then"),
        "the planner no longer plans nothing for an explicit fast verdict"
    );
}

// --- the shape of the fast-lane jobs, not just their strings -------------
//
// The strings above can all be present while the job still decides with the
// PR's code: a step that copies the PR's sources over base/, or a generator
// that reads head.sha (#4173 review). These pin the steps themselves.

const BASE_SHA: &str = "${{ github.event.pull_request.base.sha }}";

/// ci.yaml's fast-lane job is exactly these four steps, in this order: the
/// PR checkout holds only the build action, the base checkout holds the rule
/// and the roster under base/, the build reads base/, and the decision runs
/// the binary and writes the summary, nothing else. Any added step (one that
/// overwrites base/, say) fails here.
#[test]
fn ci_yaml_fast_lane_job_has_exactly_this_shape() {
    let ci = std::fs::read_to_string(CI).unwrap();
    let job = workflow_job_text(&ci, "fast-lane");
    let steps = workflow_steps(&job);
    assert_eq!(
        steps.len(),
        4,
        "fast-lane must have exactly 4 steps:\n{job}"
    );

    let pr = &steps[0];
    assert!(
        step_value(pr, "uses")
            .unwrap_or_default()
            .starts_with("actions/checkout@"),
        "{pr}"
    );
    assert_eq!(
        step_value(pr, "ref"),
        None,
        "the first checkout is the PR's own:\n{pr}"
    );
    assert_eq!(step_value(pr, "path"), None, "{pr}");
    assert_eq!(
        step_list(pr, "sparse-checkout"),
        Some(vec![".github/actions/build-ci-tool".to_string()]),
        "the PR checkout must hold only the build action:\n{pr}"
    );

    let base = &steps[1];
    assert!(
        step_value(base, "uses")
            .unwrap_or_default()
            .starts_with("actions/checkout@"),
        "{base}"
    );
    assert_eq!(step_value(base, "ref").as_deref(), Some(BASE_SHA), "{base}");
    assert_eq!(step_value(base, "path").as_deref(), Some("base"), "{base}");
    assert_eq!(
        step_list(base, "sparse-checkout"),
        Some(vec![
            "tools/ci/src/agent_fast_lane".to_string(),
            "tools/shell-compat".to_string(),
            "tools/agent-app".to_string(),
        ]),
        "{base}"
    );
    for s in [pr, base] {
        assert_eq!(
            step_value(s, "persist-credentials").as_deref(),
            Some("false"),
            "{s}"
        );
    }

    let build = &steps[2];
    assert_eq!(step_value(build, "id").as_deref(), Some("rule"), "{build}");
    assert_eq!(
        step_value(build, "uses").as_deref(),
        Some("./.github/actions/build-ci-tool"),
        "{build}"
    );
    assert_eq!(
        step_value(build, "tool").as_deref(),
        Some("agent_fast_lane"),
        "{build}"
    );
    assert_eq!(
        step_value(build, "source-root").as_deref(),
        Some("base"),
        "{build}"
    );

    let decide = &steps[3];
    assert_eq!(
        step_value(decide, "id").as_deref(),
        Some("decide"),
        "{decide}"
    );
    let env = step_env(decide);
    assert!(
        env.contains(&(
            "AGENTS_TSV".into(),
            "base/tools/agent-app/agents.tsv".into()
        )),
        "{decide}"
    );
    assert!(
        env.contains(&(
            "FAST_LANE_BIN".into(),
            "${{ steps.rule.outputs.path }}".into()
        )),
        "{decide}"
    );
    assert_eq!(
        step_run(decide),
        concat!(
            "\"$FAST_LANE_BIN\" | tee \"$RUNNER_TEMP/fast-lane.out\"\n",
            "{\n",
            "  echo \"### Agent fast lane?\"\n",
            "  echo \"\"\n",
            "  echo \"- verdict: $(sed -n 's/^verdict=//p' \"$RUNNER_TEMP/fast-lane.out\")\"\n",
            "  echo \"- why: $(sed -n 's/^reason=//p' \"$RUNNER_TEMP/fast-lane.out\")\"\n",
            "} >> \"$GITHUB_STEP_SUMMARY\"\n",
        ),
        "the decision step must run the built rule and write the summary, nothing else"
    );
}

/// presubmit.yaml's plan job: the three fast-lane steps sit together, the
/// first reads every file from the base commit and nothing else, and no
/// other step touches the folder they build from.
#[test]
fn presubmit_fast_lane_steps_have_exactly_this_shape() {
    let p = std::fs::read_to_string(PRESUBMIT).unwrap();
    let job = workflow_job_text(&p, "plan");
    let steps = workflow_steps(&job);
    let at = |id: &str| {
        steps
            .iter()
            .position(|s| step_value(s, "id").as_deref() == Some(id))
            .unwrap_or_else(|| panic!("no step {id} in the plan job"))
    };
    let (src, bin, decide) = (at("fastlane-src"), at("fastlane-bin"), at("fastlane"));
    assert_eq!(
        (bin, decide),
        (src + 1, src + 2),
        "the fast-lane steps must be adjacent"
    );

    let s = &steps[src];
    assert_eq!(
        step_env(s),
        vec![("PR_BASE_SHA".to_string(), BASE_SHA.to_string())],
        "the source step must read the BASE commit and nothing else:\n{s}"
    );
    assert_eq!(
        step_run(s),
        concat!(
            "src=\"$RUNNER_TEMP/fast-lane-base\"\n",
            "for f in tools/ci/src/agent_fast_lane/lib.rs tools/ci/src/agent_fast_lane/main.rs tools/shell-compat/src/lib.rs tools/agent-app/agents.tsv; do\n",
            "  mkdir -p \"$src/$(dirname \"$f\")\"\n",
            "  if ! git show \"$PR_BASE_SHA:$f\" > \"$src/$f\"; then\n",
            "    echo \"::notice::The base commit has no fast-lane rule yet; every unit runs.\"\n",
            "    exit 0\n",
            "  fi\n",
            "done\n",
            "echo \"root=$src\" >> \"$GITHUB_OUTPUT\"\n",
        ),
        "the source step changed shape"
    );

    let b = &steps[bin];
    assert_eq!(
        step_value(b, "if").as_deref(),
        Some("steps.fastlane-src.outputs.root != ''"),
        "{b}"
    );
    assert_eq!(
        step_value(b, "uses").as_deref(),
        Some("./.github/actions/build-ci-tool"),
        "{b}"
    );
    assert_eq!(
        step_value(b, "tool").as_deref(),
        Some("agent_fast_lane"),
        "{b}"
    );
    assert_eq!(
        step_value(b, "source-root").as_deref(),
        Some("${{ steps.fastlane-src.outputs.root }}"),
        "{b}"
    );

    let d = &steps[decide];
    assert_eq!(
        step_value(d, "if").as_deref(),
        Some("steps.fastlane-bin.outputs.path != ''"),
        "{d}"
    );
    let env = step_env(d);
    assert!(
        env.contains(&(
            "AGENTS_TSV".into(),
            "${{ steps.fastlane-src.outputs.root }}/tools/agent-app/agents.tsv".into()
        )),
        "{d}"
    );
    assert!(
        env.contains(&(
            "FAST_LANE_BIN".into(),
            "${{ steps.fastlane-bin.outputs.path }}".into()
        )),
        "{d}"
    );
    assert!(
        step_run(d).starts_with("\"$FAST_LANE_BIN\" | tee \"$RUNNER_TEMP/fast-lane.out\"\n"),
        "{d}"
    );

    for (i, s) in steps.iter().enumerate() {
        if i == src || i == bin || i == decide {
            assert!(
                !s.contains("head.sha") && !s.contains("head_ref"),
                "a fast-lane step reads the PR head:\n{s}"
            );
            continue;
        }
        assert!(
            !s.contains("fast-lane-base") && !s.contains("fastlane-src.outputs.root"),
            "only the fast-lane steps may touch the base sources:\n{s}"
        );
    }
}
