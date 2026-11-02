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

//! release-beta-gate — keep a component's release PR out of auto-merge
//! until the push rung that builds its artifact has SUCCEEDED for the exact
//! code the release would tag.

use shell_compat::{capture, cat, env, env_or_empty, err, out, status, subst};
use std::process::Command;

fn gh_capture(args: &[&[u8]]) -> shell_compat::Ran {
    let mut cmd = Command::new("gh");
    for a in args {
        cmd.arg(shell_compat::os(a));
    }
    capture(0, &mut cmd)
}

fn gh_status(args: &[&[u8]]) -> i32 {
    let mut cmd = Command::new("gh");
    for a in args {
        cmd.arg(shell_compat::os(a));
    }
    status(0, &mut cmd, true)
}

/// Run gh with stdout and stderr discarded; the status is ignored by callers
/// that, like the shell's `|| true`, carry on either way.
fn gh_quiet(args: &[&[u8]]) -> i32 {
    let mut cmd = Command::new("gh");
    for a in args {
        cmd.arg(shell_compat::os(a));
    }
    cmd.stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    status(0, &mut cmd, true)
}

struct State {
    repo: Vec<u8>,
    code_path: Vec<u8>,
    beta_job: Vec<u8>,
    pr: Vec<u8>,
    auto_on: bool,
    labels: Vec<u8>,
    run_id: Vec<u8>,
    conclusion: Vec<u8>,
    waiting_on: Vec<u8>,
    latest_code: Vec<u8>,
    latest_read: bool,
    code_sha: Vec<u8>,
}

impl State {
    fn disable_auto(&self) {
        if self.auto_on {
            let rc = gh_status(&[
                b"pr",
                b"merge",
                &self.pr,
                b"--repo",
                &self.repo,
                b"--disable-auto",
            ]);
            if rc != 0 {
                out(&cat(&[
                    b"::warning title=auto-merge still enabled::could not disable auto-merge on #",
                    &self.pr,
                    b"\n",
                ]));
            }
        }
    }

    fn indeterminate(&self, msg: &[u8]) -> i32 {
        out(&cat(&[
            b"::error title=release-beta-gate indeterminate::",
            msg,
            b" \xe2\x80\x94 keeping release PR #",
            &self.pr,
            b" out of auto-merge\n",
        ]));
        self.disable_auto();
        1
    }

    fn decide(&mut self, run_id: &[u8]) -> Result<bool, i32> {
        let r = gh_capture(&[
            b"api",
            &cat(&[
                b"repos/",
                &self.repo,
                b"/actions/runs/",
                run_id,
                b"/jobs?per_page=100",
            ]),
            b"--jq",
            b".jobs[] | \"\\(.name)\\t\\(.status)\\t\\(.conclusion // \"\")\"",
        ]);
        if !r.ok() {
            let msg = cat(&[
                b"could not read jobs for run ",
                run_id,
                b": ",
                &subst(r.stderr),
            ]);
            return Err(self.indeterminate(&msg));
        }
        let jobs_out = subst(r.stdout);
        let mut found_status = Vec::new();
        let mut found_conclusion = Vec::new();
        for line in shell_compat::lines(&jobs_out) {
            let fields = shell_compat::read_fields(&line, b"\t", 3);
            if fields.len() >= 3 && fields[0] == self.beta_job {
                found_status = fields[1].clone();
                found_conclusion = fields[2].clone();
                break;
            }
        }
        if found_status == b"completed" {
            match found_conclusion.as_slice() {
                b"success" | b"failure" | b"timed_out" | b"action_required"
                | b"startup_failure" => {
                    self.run_id = run_id.to_vec();
                    self.conclusion = found_conclusion;
                    return Ok(true);
                }
                _ => {}
            }
        } else if !found_status.is_empty() {
            if self.waiting_on.is_empty() {
                self.waiting_on = run_id.to_vec();
            }
        }
        Ok(false)
    }

    fn code_at_sha(&self, sha: &[u8]) -> Result<Vec<u8>, i32> {
        let r = gh_capture(&[
            b"api",
            &cat(&[
                b"repos/",
                &self.repo,
                b"/commits?sha=",
                sha,
                b"&path=",
                &self.code_path,
                b"&per_page=1",
            ]),
            b"--jq",
            b".[0].sha // empty",
        ]);
        if !r.ok() {
            let msg = cat(&[
                b"could not find the last ",
                &self.code_path,
                b" commit at ",
                sha,
                b": ",
                &subst(r.stderr),
            ]);
            return Err(self.indeterminate(&msg));
        }
        Ok(subst(r.stdout))
    }

    fn ensure_latest_code(&mut self) -> Result<(), i32> {
        if self.latest_read {
            return Ok(());
        }
        let r = gh_capture(&[
            b"api",
            &cat(&[
                b"repos/",
                &self.repo,
                b"/commits?sha=main&path=",
                &self.code_path,
                b"&per_page=1",
            ]),
            b"--jq",
            b".[0].sha // empty",
        ]);
        if !r.ok() {
            let msg = cat(&[
                b"could not find the last ",
                &self.code_path,
                b" commit on main: ",
                &subst(r.stderr),
            ]);
            return Err(self.indeterminate(&msg));
        }
        self.latest_code = subst(r.stdout);
        self.latest_read = true;
        Ok(())
    }

    fn search(&mut self, wf: &[u8]) -> Result<(), i32> {
        let r = gh_capture(&[
            b"api",
            &cat(&[
                b"repos/",
                &self.repo,
                b"/actions/workflows/",
                wf,
                b"/runs?event=push&branch=main&per_page=20",
            ]),
            b"--jq",
            b".workflow_runs[] | \"\\(.id)\\t\\(.head_sha)\"",
        ]);
        if !r.ok() {
            let msg = cat(&[b"could not list push ", wf, b" runs: ", &subst(r.stderr)]);
            return Err(self.indeterminate(&msg));
        }
        let runs = subst(r.stdout);

        self.ensure_latest_code()?;

        let own_listed = {
            let mut found = false;
            for line in shell_compat::lines(&runs) {
                let fields = shell_compat::read_fields(&line, b"\t", 2);
                if fields.len() >= 2 && fields[1] == self.code_sha {
                    found = true;
                    break;
                }
            }
            found
        };

        let mut seen_own = false;
        for line in shell_compat::lines(&runs) {
            let fields = shell_compat::read_fields(&line, b"\t", 2);
            if fields.len() < 2 {
                continue;
            }
            let id = &fields[0];
            let sha = &fields[1];
            if id.is_empty() {
                continue;
            }

            if *sha == self.code_sha {
                seen_own = true;
            } else if self.latest_code != self.code_sha || !own_listed {
                let at = self.code_at_sha(sha)?;
                if at != self.code_sha {
                    if self.latest_code == self.code_sha {
                        break;
                    }
                    continue;
                }
            }

            match self.decide(id)? {
                true => break,
                false => {}
            }
            if seen_own {
                break;
            }
        }

        if self.conclusion.is_empty() && !seen_own {
            let r = gh_capture(&[
                b"api",
                &cat(&[
                    b"repos/",
                    &self.repo,
                    b"/actions/workflows/",
                    wf,
                    b"/runs?head_sha=",
                    &self.code_sha,
                    b"&event=push&per_page=10",
                ]),
                b"--jq",
                b".workflow_runs[].id",
            ]);
            if !r.ok() {
                let msg = cat(&[
                    b"could not list push ",
                    wf,
                    b" runs for ",
                    &self.code_sha,
                    b": ",
                    &subst(r.stderr),
                ]);
                return Err(self.indeterminate(&msg));
            }
            let own_runs = subst(r.stdout);
            for line in shell_compat::lines(&own_runs) {
                if line.is_empty() {
                    continue;
                }
                if self.decide(&line)? {
                    break;
                }
            }
        }
        Ok(())
    }

    fn has_label(&self, label: &[u8]) -> bool {
        for part in self.labels.split(|&b| b == b',') {
            if part == label {
                return true;
            }
        }
        false
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = match env("REPO") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"REPO must be set (owner/repo)\n");
            return 1;
        }
    };
    let component = match env("COMPONENT") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"COMPONENT must be set\n");
            return 1;
        }
    };
    let code_path = match env("CODE_PATH") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"CODE_PATH must be set\n");
            return 1;
        }
    };
    let beta_job = match env("BETA_JOB") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"BETA_JOB must be set\n");
            return 1;
        }
    };
    let workflow = match env("WORKFLOW") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"WORKFLOW must be set\n");
            return 1;
        }
    };
    let legacy_workflow = env_or_empty("LEGACY_WORKFLOW");

    let branch = cat(&[b"release-please--branches--main--components--", &component]);
    let hold_label: &[u8] = b"beta-not-built";
    let person_label: &[u8] = b"do-not-automerge";

    let r = gh_capture(&[
        b"pr",
        b"list",
        b"--repo",
        &repo,
        b"--head",
        &branch,
        b"--state",
        b"open",
        b"--json",
        b"number,headRefOid,isDraft,autoMergeRequest,labels,isCrossRepository",
        b"--jq",
        b"map(select(.isCrossRepository | not)) | .[0] // empty | \"\\(.number)\\t\\(.headRefOid)\\t\\(.isDraft)\\t\\(.autoMergeRequest != null)\\t\\([.labels[].name] | join(\",\"))\"",
    ]);
    if !r.ok() {
        out(&cat(&[
            b"::error title=release-beta-gate indeterminate::could not list open release PRs on ",
            &branch,
            b": ",
            &subst(r.stderr),
            b"\n",
        ]));
        return 1;
    }
    let pr_json = subst(r.stdout);
    if pr_json.is_empty() {
        out(&cat(&[
            b"No open release PR on ",
            &branch,
            b" \xe2\x80\x94 nothing to gate.\n",
        ]));
        return 0;
    }

    let fields = shell_compat::read_fields(&pr_json, b"\t", 5);
    if fields.len() < 5 {
        out(&cat(&[
            b"::error title=release-beta-gate indeterminate::could not parse PR fields from: ",
            &pr_json,
            b"\n",
        ]));
        return 1;
    }
    let pr = fields[0].clone();
    let head_sha = fields[1].clone();
    let is_draft = fields[2] == b"true";
    let auto_on = fields[3] == b"true";
    let labels = fields[4].clone();

    let mut st = State {
        repo: repo.clone(),
        code_path: code_path.clone(),
        beta_job: beta_job.clone(),
        pr: pr.clone(),
        auto_on,
        labels: labels.clone(),
        run_id: Vec::new(),
        conclusion: Vec::new(),
        waiting_on: Vec::new(),
        latest_code: Vec::new(),
        latest_read: false,
        code_sha: Vec::new(),
    };

    let r = gh_capture(&[
        b"api",
        &cat(&[b"repos/", &repo, b"/commits/", &head_sha]),
        b"--jq",
        b".parents[0].sha // empty",
    ]);
    if !r.ok() {
        let msg = cat(&[
            b"could not read release commit ",
            &head_sha,
            b": ",
            &subst(r.stderr),
        ]);
        return st.indeterminate(&msg);
    }
    let parent = subst(r.stdout);
    if parent.is_empty() {
        let msg = cat(&[b"release commit ", &head_sha, b" has no parent"]);
        return st.indeterminate(&msg);
    }

    let r = gh_capture(&[
        b"api",
        &cat(&[
            b"repos/",
            &repo,
            b"/commits?sha=",
            &parent,
            b"&path=",
            &code_path,
            b"&per_page=1",
        ]),
        b"--jq",
        b".[0].sha // empty",
    ]);
    if !r.ok() {
        let msg = cat(&[
            b"could not find the last ",
            &code_path,
            b" commit at ",
            &parent,
            b": ",
            &subst(r.stderr),
        ]);
        return st.indeterminate(&msg);
    }
    let code_sha = subst(r.stdout);
    if code_sha.is_empty() {
        let msg = cat(&[
            b"no commit at or before ",
            &parent,
            b" touches ",
            &code_path,
        ]);
        return st.indeterminate(&msg);
    }

    out(&cat(&[
        b"Release PR #",
        &pr,
        b" releases ",
        &parent,
        b"; its ",
        &code_path,
        b" code is ",
        &code_sha,
        b".\n",
    ]));

    st.code_sha = code_sha.clone();

    if let Err(rc) = st.search(&workflow.clone()) {
        return rc;
    }

    if st.conclusion.is_empty()
        && st.waiting_on.is_empty()
        && !legacy_workflow.is_empty()
        && legacy_workflow != workflow
    {
        out(&cat(&[
            b"No push ",
            &workflow,
            b" run has run ",
            &beta_job,
            b" for ",
            &code_sha,
            b"; reading ",
            &legacy_workflow,
            b", which ran it before ",
            &workflow,
            b" existed.\n",
        ]));
        if let Err(rc) = st.search(&legacy_workflow.clone()) {
            return rc;
        }
    }

    match st.conclusion.as_slice() {
        b"success" => {
            out(&cat(&[
                &beta_job,
                b" succeeded for ",
                &code_sha,
                b" in run ",
                &st.run_id,
                b".\n",
            ]));
            if is_draft {
                out(&cat(&[
                    b"Release PR #",
                    &pr,
                    b" is a draft \xe2\x80\x94 leaving it for a maintainer.\n",
                ]));
                return 0;
            }
            if st.has_label(hold_label) {
                gh_status(&[
                    b"pr",
                    b"edit",
                    &pr,
                    b"--repo",
                    &repo,
                    b"--remove-label",
                    hold_label,
                ]);
            }
            if st.has_label(person_label) {
                out(&cat(&[
                    b"Release PR #",
                    &pr,
                    b" carries ",
                    person_label,
                    b": a person is holding it. Leaving auto-merge off.\n",
                ]));
                return 0;
            }
            if auto_on {
                out(&cat(&[b"Auto-merge already enabled on #", &pr, b".\n"]));
            } else {
                out(&cat(&[
                    b"Enabling auto-merge on #",
                    &pr,
                    b"; the merge queue merges it on green CI.\n",
                ]));
                let rc = gh_status(&[
                    b"pr",
                    b"merge",
                    &pr,
                    b"--repo",
                    &repo,
                    b"--squash",
                    b"--auto",
                ]);
                if rc != 0 {
                    out(&cat(&[
                        b"::error title=auto-merge not enabled::could not enable auto-merge on #",
                        &pr,
                        b"; re-run this workflow or merge it by hand\n",
                    ]));
                    return 1;
                }
            }
        }
        b"failure" | b"cancelled" | b"timed_out" | b"action_required" | b"startup_failure" => {
            out(&cat(&[
                b"::warning title=release PR held::",
                &beta_job,
                b" concluded '",
                &st.conclusion,
                b"' for ",
                &code_sha,
                b" \xe2\x80\x94 holding release PR #",
                &pr,
                b"\n",
            ]));
            // Its output is discarded, as the shell's `>/dev/null 2>&1` did:
            // the label usually exists already, and the hold continues anyway.
            gh_quiet(&[
                b"label",
                b"create",
                hold_label,
                b"--repo",
                &repo,
                b"--force",
                b"--color",
                b"d93f0b",
                b"--description",
                b"Held by release-beta-gate: the beta build for this release's code is not green",
            ]);
            gh_status(&[
                b"pr",
                b"edit",
                &pr,
                b"--repo",
                &repo,
                b"--add-label",
                hold_label,
            ]);
            st.disable_auto();

            let marker = cat(&[b"<!-- release-beta-gate:", &code_sha, b" -->"]);
            let r = gh_capture(&[
                b"pr",
                b"view",
                &pr,
                b"--repo",
                &repo,
                b"--json",
                b"comments",
                b"--jq",
                b".comments[].body",
            ]);
            let comments = subst(r.stdout);
            if !shell_compat::contains(&comments, &marker) {
                let body = cat(&[
                    &marker,
                    b"\nHeld out of auto-merge: `",
                    &beta_job,
                    b"` concluded **",
                    &st.conclusion,
                    b"** for ",
                    &code_sha,
                    b" in [run ",
                    &st.run_id,
                    b"](https://github.com/",
                    &repo,
                    b"/actions/runs/",
                    &st.run_id,
                    b").\n\nThat rung builds the same artifact the release would attach, so this release would publish nothing. Fix it on `main`; release-please then rebuilds this PR on the fix, and it is released automatically once `",
                    &beta_job,
                    b"` succeeds there.",
                ]);
                gh_status(&[b"pr", b"comment", &pr, b"--repo", &repo, b"--body", &body]);
            }
        }
        _ => {
            if !st.waiting_on.is_empty() {
                out(&cat(&[
                    &beta_job,
                    b" for ",
                    &code_sha,
                    b" is still running in run ",
                    &st.waiting_on,
                    b" \xe2\x80\x94 waiting.\n",
                ]));
            } else {
                out(&cat(&[
                    b"No push ",
                    &workflow,
                    b" run has finished ",
                    &beta_job,
                    b" for ",
                    &code_sha,
                    b" yet \xe2\x80\x94 waiting.\n",
                ]));
            }
            st.disable_auto();
        }
    }
    0
}
