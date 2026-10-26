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

//! queue-runner-watch — is the homelab runner pool taking jobs?

use shell_compat::{capture, cat, env, env_or, err, out, status, subst};
use std::process::Command;

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
    let wait_s = env_or("WAIT_SECONDS", b"240");
    let var_name = b"QUEUE_RUNNER_FALLBACK";

    // sleep
    let wait_secs: u64 = std::str::from_utf8(&wait_s)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(240);
    std::thread::sleep(std::time::Duration::from_secs(wait_secs));

    // Query canary job state
    let jq_expr = cat(&[
        b".jobs[] | select(.name == \"",
        &job,
        b"\") | \"\\(.status) \\(.conclusion // \\\"\\\")\"",
    ]);
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
    let state = subst(r.stdout);
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
