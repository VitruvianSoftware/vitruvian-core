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

//! //tools/ci:resolve_deploy_base — find the durable diff base for a push-triggered
//! deploy lane whose concurrency group intentionally coalesces queued pushes.

use shell_compat::{capture, cat, env, env_or, env_or_empty, err, os, out, subst};
use std::process::Command;

fn emit(sha: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"resolve-deploy-base: base_sha='",
        sha,
        b"' (",
        reason,
        b")\n",
    ]));
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&cat(&[b"base_sha=", sha, b"\n"]))
                });
        }
    }
    0
}

fn last_success(gh_bin: &[u8], repo: &[u8], workflow_file: &[u8], branch: &[u8]) -> (i32, Vec<u8>) {
    let r = capture(
        0,
        Command::new(os(gh_bin))
            .arg("run")
            .arg("list")
            .arg("--repo")
            .arg(os(repo))
            .arg("-w")
            .arg(os(workflow_file))
            .arg("-b")
            .arg(os(branch))
            .arg("-e")
            .arg("push")
            .arg("-s")
            .arg("success")
            .arg("-L")
            .arg("1")
            .arg("--json")
            .arg("headSha")
            .arg("--jq")
            .arg(".[0].headSha // empty"),
    );
    let combined = if r.ok() {
        subst(r.stdout)
    } else {
        let mut v = r.stdout;
        v.extend_from_slice(&r.stderr);
        subst(v)
    };
    (r.status, combined)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let gh_bin = env_or("GH_BIN", b"gh");
    let repo = {
        let r = env_or_empty("REPO");
        if r.is_empty() {
            env_or_empty("GITHUB_REPOSITORY")
        } else {
            r
        }
    };
    let branch = env_or("BRANCH", b"main");
    let workflow_file = env_or_empty("WORKFLOW_FILE");
    if workflow_file.is_empty() {
        err(b"resolve-deploy-base: WORKFLOW_FILE must be set to the calling workflow filename\n");
        return 1;
    }

    if repo.is_empty() {
        return emit(
            b"",
            b"REPO/GITHUB_REPOSITORY unset -- cannot query run history",
        );
    }

    let (rc, result) = last_success(&gh_bin, &repo, &workflow_file, &branch);
    if rc != 0 {
        out(&cat(&[
            b"::warning title=deploy-gate-durable-base-fallback::could not resolve the durable deploy base for ",
            &workflow_file,
            b" (",
            &result,
            b"); falling back to github.event.before\n",
        ]));
        return emit(
            b"",
            &cat(&[
                b"gh run list failed (rc=",
                format!("{}", rc).as_bytes(),
                b"): ",
                &result,
            ]),
        );
    }

    if !result.is_empty() {
        return emit(
            &result,
            &cat(&[b"last successful push-triggered run of ", &workflow_file]),
        );
    }

    let legacy = env_or_empty("LEGACY_WORKFLOW_FILE");
    if !legacy.is_empty() && legacy != workflow_file {
        let (lrc, lresult) = last_success(&gh_bin, &repo, &legacy, &branch);
        if lrc != 0 {
            out(&cat(&[
                b"::warning title=deploy-gate-durable-base-fallback::no successful run of ",
                &workflow_file,
                b" yet, and could not read ",
                &legacy,
                b" (",
                &lresult,
                b"); falling back to github.event.before\n",
            ]));
            return emit(
                b"",
                &cat(&[
                    b"gh run list for ",
                    &legacy,
                    b" failed (rc=",
                    format!("{}", lrc).as_bytes(),
                    b"): ",
                    &lresult,
                ]),
            );
        }
        if !lresult.is_empty() {
            return emit(
                &lresult,
                &cat(&[
                    b"no successful push-triggered run of ",
                    &workflow_file,
                    b" yet; last successful push-triggered run of ",
                    &legacy,
                    b", which delivered these units before it",
                ]),
            );
        }
    }

    emit(
        b"",
        &cat(&[
            b"no prior successful push-triggered run of ",
            &workflow_file,
            b" found (first run, or every prior run failed/was evicted)",
        ]),
    )
}
