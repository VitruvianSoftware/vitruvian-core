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

//! release-hold.sh — hold or release a component's open release PR based on
//! the conclusion of its development deploy job.

use shell_compat::{capture, cat, env_or_empty, err, out, status, subst};
use std::process::Command;

const HOLD_LABEL: &[u8] = b"dev-deploy-red";
const PERSON_LABEL: &[u8] = b"do-not-automerge";

fn require_env(name: &str) -> Vec<u8> {
    let v = env_or_empty(name);
    if v.is_empty() {
        err(&cat(&[name.as_bytes(), b" must be set\n"]));
        std::process::exit(1);
    }
    v
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = require_env("REPO");
    let run_id = require_env("RUN_ID");
    let dev_job = require_env("DEV_JOB");
    let component = require_env("COMPONENT");
    let source = env_or_empty("SOURCE");
    let triggered_by = env_or_empty("TRIGGERED_BY");

    if !source.is_empty() && !triggered_by.is_empty() && source != triggered_by {
        out(&cat(&[
            b"Triggered by '",
            &triggered_by,
            b"', this entry is for '",
            &source,
            b"' \xe2\x80\x94 nothing to do.\n",
        ]));
        return 0;
    }

    let branch = cat(&[b"release-please--branches--main--components--", &component]);

    // gh pr list — find open release PR. Capture stdout+stderr merged (2>&1).
    let pr_lookup = capture(
        76,
        Command::new("gh")
            .arg("pr")
            .arg("list")
            .arg("--repo")
            .arg(shell_compat::os(&repo))
            .arg("--head")
            .arg(shell_compat::os(&branch))
            .arg("--state")
            .arg("open")
            .arg("--json")
            .arg("number")
            .arg("--jq")
            .arg(".[0].number // empty")
            .stderr(std::process::Stdio::piped()),
    );
    let pr_output = {
        let mut merged = pr_lookup.stdout.clone();
        merged.extend_from_slice(&pr_lookup.stderr);
        subst(merged)
    };
    if pr_lookup.status != 0 {
        out(&cat(&[
            b"::warning title=release-hold indeterminate::could not list open release PRs on ",
            &branch,
            b": ",
            &pr_output,
            b" \xe2\x80\x94 leaving any hold/release untouched\n",
        ]));
        return 0;
    }
    let pr = subst(pr_lookup.stdout);
    if pr.is_empty() {
        out(&cat(&[
            b"No open release PR on ",
            &branch,
            b" \xe2\x80\x94 nothing to hold or release.\n",
        ]));
        return 0;
    }

    // gh run view — read jobs TSV. Capture stdout+stderr merged.
    let jobs_result = capture(
        91,
        Command::new("gh")
            .arg("run")
            .arg("view")
            .arg(shell_compat::os(&run_id))
            .arg("--repo")
            .arg(shell_compat::os(&repo))
            .arg("--json")
            .arg("jobs")
            .arg("--jq")
            .arg(r#".jobs[] | "\(.name)\t\(.conclusion)""#)
            .stderr(std::process::Stdio::piped()),
    );
    let jobs_output = {
        let mut merged = jobs_result.stdout.clone();
        merged.extend_from_slice(&jobs_result.stderr);
        subst(merged)
    };
    if jobs_result.status != 0 {
        out(&cat(&[
            b"::warning title=release-hold indeterminate::could not read jobs for run ",
            &run_id,
            b": ",
            &jobs_output,
            b" \xe2\x80\x94 leaving release PR #",
            &pr,
            b" untouched\n",
        ]));
        return 0;
    }

    let jobs_text = subst(jobs_result.stdout);

    // Parse TSV: find DEV_JOB's conclusion.
    let mut conclusion: Vec<u8> = Vec::new();
    for line in shell_compat::lines(&jobs_text) {
        if let Some(tab) = line.iter().position(|&c| c == b'\t') {
            if line[..tab] == dev_job[..] {
                conclusion = line[tab + 1..].to_vec();
                break;
            }
        }
    }

    if conclusion.is_empty() {
        out(&cat(&[
            b"Run ",
            &run_id,
            b" has no '",
            &dev_job,
            b"' job (nothing deployable changed) \xe2\x80\x94 leaving release PR #",
            &pr,
            b" untouched.\n",
        ]));
        return 0;
    }

    out(&cat(&[
        b"Development job '",
        &dev_job,
        b"' concluded '",
        &conclusion,
        b"' in run ",
        &run_id,
        b"; release PR is #",
        &pr,
        b".\n",
    ]));

    match conclusion.as_slice() {
        b"success" | b"skipped" => {
            // Check current labels via gh pr view.
            let labels_r = capture(
                123,
                Command::new("gh")
                    .arg("pr")
                    .arg("view")
                    .arg(shell_compat::os(&pr))
                    .arg("--repo")
                    .arg(shell_compat::os(&repo))
                    .arg("--json")
                    .arg("labels")
                    .arg("--jq")
                    .arg(".labels[].name")
                    .stderr(std::process::Stdio::null()),
            );
            let labels = subst(labels_r.stdout);
            let label_lines = shell_compat::lines(&labels);

            let has_hold = label_lines.iter().any(|l| l.as_slice() == HOLD_LABEL);
            let has_person = label_lines.iter().any(|l| l.as_slice() == PERSON_LABEL);

            if has_hold {
                out(&cat(&[
                    b"Development is green again \xe2\x80\x94 releasing this workflow's hold on #",
                    &pr,
                    b".\n",
                ]));
                // gh pr edit --remove-label || true
                status(
                    126,
                    Command::new("gh")
                        .arg("pr")
                        .arg("edit")
                        .arg(shell_compat::os(&pr))
                        .arg("--repo")
                        .arg(shell_compat::os(&repo))
                        .arg("--remove-label")
                        .arg(shell_compat::os(HOLD_LABEL)),
                    false,
                );
                if has_person {
                    out(&cat(&[
                        b"#",
                        &pr,
                        b" also carries ",
                        PERSON_LABEL,
                        b": a person is holding it. Leaving auto-merge off.\n",
                    ]));
                } else {
                    // gh pr merge --squash --auto || warning
                    let rc = status(
                        130,
                        Command::new("gh")
                            .arg("pr")
                            .arg("merge")
                            .arg(shell_compat::os(&pr))
                            .arg("--repo")
                            .arg(shell_compat::os(&repo))
                            .arg("--squash")
                            .arg("--auto"),
                        false,
                    );
                    if rc != 0 {
                        out(&cat(&[
                            b"::warning title=auto-merge not re-enabled::could not re-enable auto-merge on #",
                            &pr,
                            b"; merge it manually or re-run this workflow\n",
                        ]));
                    }
                }
            } else {
                out(&cat(&[
                    b"No hold of this workflow's on #",
                    &pr,
                    b"; nothing to do.\n",
                ]));
            }
        }
        b"failure" | b"cancelled" | b"timed_out" | b"action_required" | b"startup_failure" => {
            out(&cat(&[
                b"::warning title=release PR held::",
                &component,
                b"'s development deploy concluded '",
                &conclusion,
                b"' \xe2\x80\x94 holding release PR #",
                &pr,
                b" out of auto-merge\n",
            ]));
            // gh label create || true
            status(
                139,
                Command::new("gh")
                    .arg("label")
                    .arg("create")
                    .arg(shell_compat::os(HOLD_LABEL))
                    .arg("--repo")
                    .arg(shell_compat::os(&repo))
                    .arg("--force")
                    .arg("--color")
                    .arg("d93f0b")
                    .arg("--description")
                    .arg("Held by release-hold: this component's development deploy is red")
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null()),
                true,
            );
            // gh pr edit --add-label || true
            status(
                141,
                Command::new("gh")
                    .arg("pr")
                    .arg("edit")
                    .arg(shell_compat::os(&pr))
                    .arg("--repo")
                    .arg(shell_compat::os(&repo))
                    .arg("--add-label")
                    .arg(shell_compat::os(HOLD_LABEL)),
                false,
            );
            // gh pr merge --disable-auto || warning
            let rc = status(
                143,
                Command::new("gh")
                    .arg("pr")
                    .arg("merge")
                    .arg(shell_compat::os(&pr))
                    .arg("--repo")
                    .arg(shell_compat::os(&repo))
                    .arg("--disable-auto"),
                false,
            );
            if rc != 0 {
                out(&cat(&[
                    b"::warning title=auto-merge still enabled::could not disable auto-merge on #",
                    &pr,
                    b" \xe2\x80\x94 it may merge despite the hold label\n",
                ]));
            }
            // gh pr comment || true
            let body = cat(&[
                b"Held out of auto-merge: `",
                &component,
                b"`'s development deploy concluded **",
                &conclusion,
                b"** in [run ",
                &run_id,
                b"](https://github.com/",
                &repo,
                b"/actions/runs/",
                &run_id,
                b").\n\nMerging this release would promote an artifact whose development deploy is red, and nonproduction has no reviewer to catch it. This PR is released automatically once development is green again.",
            ]);
            status(
                145,
                Command::new("gh")
                    .arg("pr")
                    .arg("comment")
                    .arg(shell_compat::os(&pr))
                    .arg("--repo")
                    .arg(shell_compat::os(&repo))
                    .arg("--body")
                    .arg(shell_compat::os(&body)),
                false,
            );
        }
        _ => {
            out(&cat(&[
                b"Unrecognised conclusion '",
                &conclusion,
                b"' \xe2\x80\x94 leaving #",
                &pr,
                b" untouched.\n",
            ]));
        }
    }

    0
}
