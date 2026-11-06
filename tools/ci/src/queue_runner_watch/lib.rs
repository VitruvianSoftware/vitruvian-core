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

//! queue-runner-watch — is the homelab runner pool taking jobs? If not, send the
//! merge queue's jobs back to GitHub-hosted runners until it is.
//!
//! Runs in the queue-runner-watch workflow, which starts a one-step "canary" job
//! on the homelab runners and this tool on a hosted runner. After WAIT seconds
//! the canary must be running or done: a canary still queued means no homelab
//! runner took it (cluster down, power, network, controller), and a failed one
//! means runners start but cannot run a job. Either way the repository variable
//! QUEUE_RUNNER_FALLBACK is set to "on", which every routed workflow reads
//! (spec §4): jobs then run on GitHub-hosted runners. A canary that runs flips
//! it back to "off". The variable only changes when the answer does.
//!
//! Spec: docs/superpowers/specs/2026-10-19-queue-runners-on-homelab-design.md
//!
//! Env: REPO, RUN_ID (this workflow run), CANARY_JOB (job name, default
//! "canary"), WAIT_SECONDS (default 600), POLL_SECONDS (default 15), GH_TOKEN
//! (can write variables and cancel runs), GH_BIN (tests).

use shell_compat::{capture, cat, env, env_or, err, out, status, subst};
use std::process::Command;

/// Cancel any `in_progress` or `queued` `merge_group` workflow runs whose
/// `gh-readonly-queue/main/...` branch ref has already been deleted on GitHub
/// (because the queue entry merged or was evicted). Without this, evicted
/// queue runs remain queued/running on self-hosted `vitruvian-queue` runners
/// and starve subsequent merge-queue and canary jobs.
fn cancel_orphaned_merge_group_runs(gh: &[u8], repo: &[u8], own_run_id: &[u8]) {
    let mut candidates: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
    for st in [b"in_progress".as_slice(), b"queued".as_slice()] {
        let r = capture(
            42,
            Command::new(shell_compat::os(gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    repo,
                    b"/actions/runs?event=merge_group&status=",
                    st,
                    b"&per_page=100",
                ])))
                .arg("--jq")
                .arg(r#".workflow_runs[] | "\(.id) \(.head_branch // "")""#),
        );
        if !r.ok() {
            return;
        }
        let text = subst(r.stdout);
        for line in text.split(|&c| c == b'\n') {
            if line.is_empty() {
                continue;
            }
            if let Some(sp) = line.iter().position(|&c| c == b' ') {
                let id = &line[..sp];
                let branch = &line[sp + 1..];
                if id != own_run_id && branch.starts_with(b"gh-readonly-queue/main/") {
                    candidates.push((id.to_vec(), branch.to_vec()));
                }
            }
        }
    }
    if candidates.is_empty() {
        return;
    }

    let refs_r = capture(
        45,
        Command::new(shell_compat::os(gh))
            .arg("api")
            .arg(shell_compat::os(&cat(&[
                b"repos/",
                repo,
                b"/git/matching-refs/heads/gh-readonly-queue/main/",
            ])))
            .arg("--jq")
            .arg(".[].ref"),
    );
    if !refs_r.ok() {
        return;
    }
    let refs_text = subst(refs_r.stdout);
    let live_refs: Vec<&[u8]> = refs_text
        .split(|&c| c == b'\n')
        .filter(|l| !l.is_empty())
        .collect();

    for (id, branch) in candidates {
        let full_ref = cat(&[b"refs/heads/", &branch]);
        if !live_refs.iter().any(|&r| r == full_ref.as_slice()) {
            let _ = status(
                47,
                Command::new(shell_compat::os(gh))
                    .arg("api")
                    .arg("-X")
                    .arg("POST")
                    .arg(shell_compat::os(&cat(&[
                        b"repos/",
                        repo,
                        b"/actions/runs/",
                        &id,
                        b"/cancel",
                    ])))
                    .stdout(std::process::Stdio::null()),
                true,
            );
            out(&cat(&[
                b"queue-runner-watch: cancelled orphaned merge_group run ",
                &id,
                b" (",
                &branch,
                b")\n",
            ]));
        }
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let gh = env_or("GH_BIN", b"gh");
    let repo = match env("REPO") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"REPO is required\n");
            return 2;
        }
    };
    let run_id = match env("RUN_ID") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"RUN_ID is required\n");
            return 2;
        }
    };
    let job = env_or("CANARY_JOB", b"canary");
    let wait_s = env_or("WAIT_SECONDS", b"600");
    let poll_s = env_or("POLL_SECONDS", b"15");
    let var_name = b"QUEUE_RUNNER_FALLBACK";

    cancel_orphaned_merge_group_runs(&gh, &repo, &run_id);

    let wait_secs: u64 = std::str::from_utf8(&wait_s)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(600);
    let poll_secs: u64 = std::str::from_utf8(&poll_s)
        .ok()
        .and_then(|s| s.parse().ok())
        .filter(|&n| n > 0)
        .unwrap_or(15);

    // Poll canary job state until it starts/completes or WAIT_SECONDS elapses.
    let jq_expr = cat(&[
        b".jobs[] | select(.name == \"",
        &job,
        // jq receives `"\(.status) \(.conclusion // "")"`: inside a `\( )`
        // interpolation the inner quotes stay bare. `\"` there is a jq syntax
        // error, gh prints nothing and the watcher sees no canary job.
        br#"") | "\(.status) \(.conclusion // "")""#,
    ]);
    let mut elapsed: u64 = 0;
    let state = loop {
        let step = poll_secs.min(wait_secs.saturating_sub(elapsed));
        if step > 0 {
            std::thread::sleep(std::time::Duration::from_secs(step));
            elapsed += step;
        }
        let r = capture(
            48,
            Command::new(shell_compat::os(&gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    &repo,
                    b"/actions/runs/",
                    &run_id,
                    b"/jobs",
                ])))
                .arg("--jq")
                .arg(shell_compat::os(&jq_expr)),
        );
        let s = subst(r.stdout);
        let space = s.iter().position(|&c| c == b' ').unwrap_or(s.len());
        let st = &s[..space];
        if st == b"in_progress" || st == b"completed" || elapsed >= wait_secs {
            break s;
        }
    };
    if state.is_empty() {
        err(&cat(&[
            b"queue-runner-watch: no job named '",
            &job,
            b"' in run ",
            &run_id,
            b"\n",
        ]));
        return 1;
    }

    let space = state.iter().position(|&c| c == b' ').unwrap_or(state.len());
    let status_val = &state[..space];
    let conclusion = if space < state.len() {
        &state[space + 1..]
    } else {
        &[][..]
    };

    let (want, why);
    if status_val == b"in_progress" || (status_val == b"completed" && conclusion == b"success") {
        want = b"off".as_slice();
        let mut msg = cat(&[b"the canary ", status_val]);
        if !conclusion.is_empty() {
            msg.extend_from_slice(b" (");
            msg.extend_from_slice(conclusion);
            msg.extend_from_slice(b")");
        }
        msg.extend_from_slice(b": homelab runners are taking jobs");
        why = msg;
    } else {
        want = b"on".as_slice();
        let mut msg = cat(&[b"the canary is '", status_val]);
        if !conclusion.is_empty() {
            msg.extend_from_slice(b" / ");
            msg.extend_from_slice(conclusion);
        }
        msg.extend_from_slice(b"' after ");
        msg.extend_from_slice(&wait_s);
        msg.extend_from_slice(b"s: homelab runners are not taking jobs");
        why = msg;
    }

    // Read current variable
    let current_r = capture(
        66,
        Command::new(shell_compat::os(&gh))
            .arg("api")
            .arg(shell_compat::os(&cat(&[
                b"repos/",
                &repo,
                b"/actions/variables/",
                var_name,
            ])))
            .arg("--jq")
            .arg(".value"),
    );
    let current = if current_r.ok() {
        let v = subst(current_r.stdout);
        if v == b"on" || v == b"off" {
            v
        } else {
            b"missing".to_vec()
        }
    } else {
        b"missing".to_vec()
    };

    out(&cat(&[
        b"queue-runner-watch: ",
        &why,
        b"; ",
        var_name,
        b" is '",
        &current,
        b"', want '",
        want,
        b"'\n",
    ]));

    if current != want {
        if current == b"missing" {
            let _ = status(
                75,
                Command::new(shell_compat::os(&gh))
                    .arg("api")
                    .arg("-X")
                    .arg("POST")
                    .arg(shell_compat::os(&cat(&[
                        b"repos/",
                        &repo,
                        b"/actions/variables",
                    ])))
                    .arg("-f")
                    .arg(shell_compat::os(&cat(&[b"name=", var_name])))
                    .arg("-f")
                    .arg(shell_compat::os(&cat(&[b"value=", want])))
                    .stdout(std::process::Stdio::null()),
                false,
            );
        } else {
            let _ = status(
                77,
                Command::new(shell_compat::os(&gh))
                    .arg("api")
                    .arg("-X")
                    .arg("PATCH")
                    .arg(shell_compat::os(&cat(&[
                        b"repos/",
                        &repo,
                        b"/actions/variables/",
                        var_name,
                    ])))
                    .arg("-f")
                    .arg(shell_compat::os(&cat(&[b"value=", want])))
                    .stdout(std::process::Stdio::null()),
                false,
            );
        }
        if want == b"on" {
            out(&cat(&[
                b"::warning::queue jobs fall back to GitHub-hosted runners: ",
                &why,
                b"\n",
            ]));
        } else {
            out(b"queue jobs return to the homelab runners\n");
        }
    }

    // Cancel a queued canary nobody picked up
    if want == b"on" && status_val != b"completed" && status_val != b"in_progress" {
        let _ = status(
            89,
            Command::new(shell_compat::os(&gh))
                .arg("api")
                .arg("-X")
                .arg("POST")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    &repo,
                    b"/actions/runs/",
                    &run_id,
                    b"/cancel",
                ])))
                .stdout(std::process::Stdio::null()),
            true,
        );
    }

    0
}
