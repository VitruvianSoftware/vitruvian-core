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

//! require-dev-soak — refuse to PROMOTE when development is currently RED
//! for the service being promoted. Fail-closed on red, fail-open on unknown.
//!
//! A development deploy that is still RUNNING is neither: the newest answer is
//! not in yet. The gate waits for it (polling every POLL_SECONDS, default 30,
//! for up to WAIT_SECONDS, default 2400) and then judges its result; still
//! running after that, it blocks as not yet soaked. Ignoring it, as the gate
//! once did by reading only completed runs, judged an older run instead and
//! let the promotion's Pulumi applies start while the development deploy still
//! held Pulumi Cloud's account-wide lock (v1.15.4: a 409 on every retry, #4176).

use shell_compat::{capture, cat, env, env_or, env_or_empty, err, lines, out, subst};
use std::process::Command;
use std::time::{Duration, Instant};

enum Verdict {
    Pass(Vec<u8>),
    Block(Vec<u8>),
    Unknown(Vec<u8>),
    /// The newest run that has, or may still reach, the development deploy is
    /// in progress (its run id): wait and look again.
    Pending(Vec<u8>),
    Continue,
}

fn pass(dev_job_name: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"require-dev-soak[",
        dev_job_name,
        b"]: PASS \xe2\x80\x94 ",
        reason,
        b"\n",
    ]));
    0
}

fn block(dev_job_name: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"::error title=development is red \xe2\x80\x94 promotion blocked::",
        reason,
        b"\n",
    ]));
    err(&cat(&[
        b"require-dev-soak[",
        dev_job_name,
        b"]: BLOCKED \xe2\x80\x94 ",
        reason,
        b"\n",
    ]));
    1
}

fn unknown(dev_job_name: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"::warning title=dev-soak indeterminate::",
        reason,
        b" \xe2\x80\x94 allowing the promotion (this gate fails open on an UNKNOWN answer; it blocks only on a definitive red development deploy)\n",
    ]));
    out(&cat(&[
        b"require-dev-soak[",
        dev_job_name,
        b"]: PASS (indeterminate) \xe2\x80\x94 ",
        reason,
        b"\n",
    ]));
    0
}

fn scan(
    gh_bin: &[u8],
    repo: &[u8],
    branch: &[u8],
    scan_limit: &[u8],
    dev_job_name: &[u8],
    wf: &[u8],
) -> Verdict {
    let r = capture(
        0,
        Command::new(shell_compat::os(gh_bin))
            .arg("run")
            .arg("list")
            .arg("--repo")
            .arg(shell_compat::os(repo))
            .arg("-w")
            .arg(shell_compat::os(wf))
            .arg("-b")
            .arg(shell_compat::os(branch))
            .arg("-e")
            .arg("push")
            .arg("-L")
            .arg(shell_compat::os(scan_limit))
            .arg("--json")
            .arg("databaseId,status")
            .arg("--jq")
            .arg(".[] | \"\\(.databaseId)\\t\\(.status)\""),
    );
    if !r.ok() {
        let runs_out = subst(r.stdout);
        let runs_err = subst(r.stderr);
        let combined = if !runs_out.is_empty() {
            runs_out
        } else {
            runs_err
        };
        return Verdict::Unknown(cat(&[
            b"gh run list for ",
            wf,
            b" failed (rc=",
            r.status.to_string().as_bytes(),
            b"): ",
            &combined,
        ]));
    }
    let runs = subst(r.stdout);

    for run_line in lines(&runs) {
        if run_line.is_empty() {
            continue;
        }
        // "<id>\t<status>"; a bare id is a completed run.
        let (run_id, run_done) = match run_line.iter().position(|&c| c == b'\t') {
            Some(t) => (&run_line[..t], &run_line[t + 1..] == b"completed"),
            None => (&run_line[..], true),
        };

        let jr = capture(
            0,
            Command::new(shell_compat::os(gh_bin))
                .arg("run")
                .arg("view")
                .arg(shell_compat::os(run_id))
                .arg("--repo")
                .arg(shell_compat::os(repo))
                .arg("--json")
                .arg("jobs")
                .arg("--jq")
                .arg(".jobs[] | \"\\(.name)\\t\\(.conclusion)\""),
        );
        if !jr.ok() {
            let jobs_out = subst(jr.stdout);
            let jobs_err = subst(jr.stderr);
            let combined = if !jobs_out.is_empty() {
                jobs_out
            } else {
                jobs_err
            };
            err(&cat(&[
                b"require-dev-soak: could not read jobs for run ",
                run_id,
                b" (rc=",
                jr.status.to_string().as_bytes(),
                b"): ",
                &combined,
                b"\n",
            ]));
            // An unreadable run is no evidence, running or not: waiting on it
            // would turn an API error into a block.
            continue;
        }
        let jobs = subst(jr.stdout);

        // None: the run has no such job (yet). Some(empty): it is queued or
        // running.
        let mut conclusion: Option<Vec<u8>> = None;
        for job_line in lines(&jobs) {
            if let Some(tab_pos) = job_line.iter().position(|&c| c == b'\t') {
                let name = &job_line[..tab_pos];
                if name == dev_job_name {
                    let c = &job_line[tab_pos + 1..];
                    conclusion = Some(if c == b"null" { Vec::new() } else { c.to_vec() });
                    break;
                }
            }
        }
        let conclusion = match conclusion {
            // A finished run without the job never deployed development.
            None if run_done => continue,
            // A running one may still reach it: a later job shows up in the
            // run only once its needs finish.
            None => return Verdict::Pending(run_id.to_vec()),
            Some(c) if c.is_empty() => return Verdict::Pending(run_id.to_vec()),
            Some(c) => c,
        };

        match conclusion.as_slice() {
            b"success" => {
                return Verdict::Pass(cat(&[
                    b"development deploy '",
                    dev_job_name,
                    b"' succeeded in run ",
                    run_id,
                    b" of ",
                    wf,
                ]));
            }
            b"skipped" => {
                return Verdict::Pass(cat(&[
                    b"development deploy '",
                    dev_job_name,
                    b"' was skipped in run ",
                    run_id,
                    b" of ",
                    wf,
                    b" (the graph gate found no deployable change \xe2\x80\x94 nothing to soak)",
                ]));
            }
            b"failure" | b"cancelled" | b"timed_out" | b"action_required" | b"startup_failure" => {
                return Verdict::Block(cat(&[
                    b"development deploy '",
                    dev_job_name,
                    b"' concluded '",
                    &conclusion,
                    b"' in the most recent run that reached it (run ",
                    run_id,
                    b": https://github.com/",
                    repo,
                    b"/actions/runs/",
                    run_id,
                    b"). Promoting now would ship an artifact whose development deploy is RED. Fix development first, or set ALLOW_UNSOAKED=true to override deliberately.",
                ]));
            }
            _ => {
                err(&cat(&[
                    b"require-dev-soak: unrecognised conclusion '",
                    &conclusion,
                    b"' for run ",
                    run_id,
                    b"; continuing\n",
                ]));
            }
        }
    }

    Verdict::Continue
}

/// A whole number of seconds from `name`, or `default` when unset or not a
/// number.
fn seconds_env(name: &str, default: u64) -> u64 {
    env(name)
        .and_then(|v| String::from_utf8(v).ok())
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(default)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let gh_bin = env_or("GH_BIN", b"gh");
    let repo = env_or_empty("REPO");
    let repo = if repo.is_empty() {
        env_or_empty("GITHUB_REPOSITORY")
    } else {
        repo
    };
    let branch = env_or("BRANCH", b"main");
    let scan_limit = env_or("SCAN_LIMIT", b"20");
    let allow_unsoaked = env_or("ALLOW_UNSOAKED", b"false");

    let dev_job_name = match env("DEV_JOB_NAME") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"require-dev-soak: DEV_JOB_NAME must name the development deploy job\n");
            return 1;
        }
    };

    if allow_unsoaked == b"true" {
        out(b"::warning title=dev-soak gate bypassed::ALLOW_UNSOAKED=true \xe2\x80\x94 promoting WITHOUT confirming the development deploy is green\n");
        return pass(&dev_job_name, b"explicitly bypassed via ALLOW_UNSOAKED");
    }

    if repo.is_empty() {
        return unknown(
            &dev_job_name,
            b"REPO/GITHUB_REPOSITORY unset \xe2\x80\x94 cannot query run history",
        );
    }

    // Resolve WORKFLOW_FILE
    let mut workflow_file = env_or_empty("WORKFLOW_FILE");

    if workflow_file.is_empty() {
        if let Some(run_id) = env("GITHUB_RUN_ID") {
            if !run_id.is_empty() {
                let r = capture(
                    0,
                    Command::new(shell_compat::os(&gh_bin))
                        .arg("api")
                        .arg(shell_compat::os(&cat(&[
                            b"repos/",
                            &repo,
                            b"/actions/runs/",
                            &run_id,
                        ])))
                        .arg("--jq")
                        .arg(".workflow_id"),
                );
                if r.ok() {
                    let wf_id = subst(r.stdout);
                    if !wf_id.is_empty() {
                        workflow_file = wf_id;
                    }
                }
            }
        }
    }
    if workflow_file.is_empty() {
        if let Some(wf_ref) = env("GITHUB_WORKFLOW_REF") {
            if !wf_ref.is_empty() {
                // strip @refs/heads/...
                let stripped = if let Some(at_pos) = wf_ref.iter().position(|&c| c == b'@') {
                    &wf_ref[..at_pos]
                } else {
                    &wf_ref
                };
                // basename
                let base = if let Some(slash_pos) = stripped.iter().rposition(|&c| c == b'/') {
                    &stripped[slash_pos + 1..]
                } else {
                    stripped
                };
                if !base.is_empty() {
                    workflow_file = base.to_vec();
                }
            }
        }
    }
    if workflow_file.is_empty() {
        return unknown(&dev_job_name, b"could not determine which workflow's history to search (no WORKFLOW_FILE, no resolvable GITHUB_RUN_ID, no GITHUB_WORKFLOW_REF)");
    }

    out(&cat(&[
        b"require-dev-soak[",
        &dev_job_name,
        b"]: searching ",
        &workflow_file,
        b" on ",
        &branch,
        b" (repo ",
        &repo,
        b")\n",
    ]));

    let wait = Duration::from_secs(seconds_env("WAIT_SECONDS", 2400));
    let poll = Duration::from_secs(seconds_env("POLL_SECONDS", 30));
    let started = Instant::now();
    let verdict = loop {
        match scan(
            &gh_bin,
            &repo,
            &branch,
            &scan_limit,
            &dev_job_name,
            &workflow_file,
        ) {
            Verdict::Pending(run_id) => {
                if started.elapsed() >= wait {
                    return block(
                        &dev_job_name,
                        &cat(&[
                            b"development deploy '",
                            &dev_job_name,
                            b"' is still running in run ",
                            &run_id,
                            b" (https://github.com/",
                            &repo,
                            b"/actions/runs/",
                            &run_id,
                            b") after waiting ",
                            started.elapsed().as_secs().to_string().as_bytes(),
                            b"s, so development is not yet soaked. Re-run this job once that run finishes, or set ALLOW_UNSOAKED=true to override deliberately.",
                        ]),
                    );
                }
                out(&cat(&[
                    b"require-dev-soak[",
                    &dev_job_name,
                    b"]: waiting \xe2\x80\x94 run ",
                    &run_id,
                    b" of ",
                    &workflow_file,
                    b" is still in progress and may deploy development (",
                    started.elapsed().as_secs().to_string().as_bytes(),
                    b"s of ",
                    wait.as_secs().to_string().as_bytes(),
                    b"s)\n",
                ]));
                std::thread::sleep(poll);
            }
            v => break v,
        }
    };
    match verdict {
        Verdict::Pass(reason) => return pass(&dev_job_name, &reason),
        Verdict::Block(reason) => return block(&dev_job_name, &reason),
        Verdict::Unknown(reason) => return unknown(&dev_job_name, &reason),
        Verdict::Pending(_) | Verdict::Continue => {}
    }

    let mut searched = workflow_file.clone();

    let legacy = env_or_empty("LEGACY_WORKFLOW_FILE");
    if !legacy.is_empty() && legacy != workflow_file {
        out(&cat(&[
            b"require-dev-soak[",
            &dev_job_name,
            b"]: no terminal result in ",
            &workflow_file,
            b"; searching ",
            &legacy,
            b", which deployed development before it\n",
        ]));
        // The legacy workflow no longer deploys, so nothing there is still
        // running; a run that somehow is gives no answer either way.
        match scan(&gh_bin, &repo, &branch, &scan_limit, &dev_job_name, &legacy) {
            Verdict::Pass(reason) => return pass(&dev_job_name, &reason),
            Verdict::Block(reason) => return block(&dev_job_name, &reason),
            Verdict::Unknown(reason) => return unknown(&dev_job_name, &reason),
            Verdict::Pending(_) | Verdict::Continue => {}
        }
        searched = cat(&[&workflow_file, b" and ", &legacy]);
    }

    unknown(
        &dev_job_name,
        &cat(&[
            b"scanned the last ",
            &scan_limit,
            b" push runs of ",
            &searched,
            b" without finding a terminal '",
            &dev_job_name,
            b"' result",
        ]),
    )
}
