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

//! dependabot-lock-rebase.sh — rebase every open Dependabot npm PR onto the
//! just-merged root lock file, re-resolving it hermetically.

use shell_compat::{capture, cat, env_or, env_or_empty, err, out, status, subst};
use std::process::Command;

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = env_or_empty("REPO");
    if repo.is_empty() {
        err(b"REPO must be set (owner/repo)\n");
        return 1;
    }
    let base_branch = env_or("BASE_BRANCH", b"main");
    let lock_file = env_or("LOCK_FILE", b"pnpm-lock.yaml");
    let branch_prefix = env_or("BRANCH_PREFIX", b"dependabot/npm_and_yarn/");
    let git_user_name = env_or("GIT_USER_NAME", b"VitruvianSoftware Sync");
    let git_user_email = env_or("GIT_USER_EMAIL", b"sync@vitruviansoftware.com");
    let work_dir = match shell_compat::env("WORK_DIR") {
        Some(v) if !v.is_empty() => v,
        _ => match shell_compat::env("RUNNER_TEMP") {
            Some(v) if !v.is_empty() => v,
            _ => match shell_compat::mktemp_dir() {
                Ok(d) => d,
                Err(_) => {
                    err(b"could not create work directory\n");
                    return 1;
                }
            },
        },
    };

    let prefix_escaped = escape_jq_string(&branch_prefix);
    let filter = cat(&[
        b".[] | select(.headRefName | startswith(\"",
        &prefix_escaped,
        b"\")) | [.number,.headRefName] | @tsv",
    ]);

    let r = capture(
        71,
        Command::new("gh")
            .arg("pr")
            .arg("list")
            .arg("-R")
            .arg(shell_compat::os(&repo))
            .arg("--state")
            .arg("open")
            .arg("--json")
            .arg("number,headRefName")
            .arg("--jq")
            .arg(shell_compat::os(&filter)),
    );
    let prs = subst(r.stdout);
    if prs.is_empty() {
        out(b"No open Dependabot npm PRs \xe2\x80\x94 nothing to rebase.\n");
        return 0;
    }

    status(
        77,
        Command::new("git")
            .arg("config")
            .arg("user.name")
            .arg(shell_compat::os(&git_user_name)),
        false,
    );
    status(
        78,
        Command::new("git")
            .arg("config")
            .arg("user.email")
            .arg(shell_compat::os(&git_user_email)),
        false,
    );

    let prs_file = cat(&[&work_dir, b"/prs.tsv"]);
    let _ = shell_compat::write_file(&prs_file, &cat(&[&prs, b"\n"]), 0o644);

    let mut rc = 0i32;

    for line in shell_compat::lines(&prs) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
        if fields.len() < 2 {
            continue;
        }
        let num = fields[0];
        let branch = fields[1];
        if num.is_empty() {
            continue;
        }

        out(&cat(&[b"::group::#", num, b" (", branch, b")\n"]));

        let fetch_rc = status(
            91,
            Command::new("git")
                .arg("fetch")
                .arg("--quiet")
                .arg("origin")
                .arg(shell_compat::os(branch)),
            false,
        );
        if fetch_rc != 0 {
            out(&cat(&[
                b"::warning::#",
                num,
                b": cannot fetch ",
                branch,
                b"; skipping.\n",
            ]));
            out(b"::endgroup::\n");
            continue;
        }

        status(
            95,
            Command::new("git")
                .arg("checkout")
                .arg("--quiet")
                .arg("--force")
                .arg("-B")
                .arg(shell_compat::os(&cat(&[b"rebase-", num])))
                .arg(shell_compat::os(&cat(&[b"origin/", branch]))),
            false,
        );

        let merge_rc = status(
            100,
            Command::new("git")
                .arg("merge")
                .arg("--no-edit")
                .arg(shell_compat::os(&cat(&[b"origin/", &base_branch]))),
            false,
        );
        if merge_rc != 0 {
            let r = capture(
                105,
                Command::new("git")
                    .arg("diff")
                    .arg("--name-only")
                    .arg("--diff-filter=U"),
            );
            let unmerged = subst(r.stdout);
            if unmerged != lock_file {
                out(&cat(&[
                    b"::warning::#",
                    num,
                    b": conflicts outside ",
                    &lock_file,
                    b", leaving for a human:\n",
                ]));
                for uline in shell_compat::lines(&unmerged) {
                    out(&cat(&[b"    ", &uline, b"\n"]));
                }
                let _ = status(109, Command::new("git").arg("merge").arg("--abort"), true);
                rc = 1;
                out(b"::endgroup::\n");
                continue;
            }
            let co_rc = status(
                113,
                Command::new("git")
                    .arg("checkout")
                    .arg("--theirs")
                    .arg("--")
                    .arg(shell_compat::os(&lock_file)),
                true,
            );
            if co_rc != 0 {
                status(
                    113,
                    Command::new("git")
                        .arg("checkout")
                        .arg(shell_compat::os(&cat(&[b"origin/", &base_branch])))
                        .arg("--")
                        .arg(shell_compat::os(&lock_file)),
                    false,
                );
            }
            status(
                114,
                Command::new("git")
                    .arg("add")
                    .arg("--")
                    .arg(shell_compat::os(&lock_file)),
                false,
            );
            status(
                115,
                Command::new("git")
                    .arg("commit")
                    .arg("--no-edit")
                    .arg("--quiet"),
                false,
            );
        }

        // Unconditionally reset LOCK_FILE to BASE_BRANCH's canonical version.
        status(
            127,
            Command::new("git")
                .arg("checkout")
                .arg(shell_compat::os(&cat(&[b"origin/", &base_branch])))
                .arg("--")
                .arg(shell_compat::os(&lock_file)),
            false,
        );

        // Re-resolve from the merged manifests.
        let cwd = std::env::current_dir()
            .map(|p| shell_compat::path_bytes(&p))
            .unwrap_or_default();
        let pnpm_rc = status(
            136,
            Command::new("bazel")
                .arg("run")
                .arg("--")
                .arg("@pnpm//:pnpm")
                .arg("install")
                .arg("--dir")
                .arg(shell_compat::os(&cwd))
                .arg("--lockfile-only"),
            false,
        );
        if pnpm_rc != 0 {
            out(&cat(&[
                b"::error::#",
                num,
                b": pnpm re-resolve failed; leaving the branch untouched.\n",
            ]));
            rc = 1;
            out(b"::endgroup::\n");
            continue;
        }
        let tidy_rc = status(140, Command::new("bazel").arg("run").arg("//:tidy"), false);
        if tidy_rc != 0 {
            out(&cat(&[
                b"::error::#",
                num,
                b": //:tidy failed; leaving the branch untouched.\n",
            ]));
            rc = 1;
            out(b"::endgroup::\n");
            continue;
        }

        status(145, Command::new("git").arg("add").arg("-A"), false);

        let diff_rc = status(
            146,
            Command::new("git")
                .arg("diff")
                .arg("--cached")
                .arg("--quiet"),
            true,
        );
        if diff_rc != 0 {
            status(
                147,
                Command::new("git")
                    .arg("commit")
                    .arg("--quiet")
                    .arg("-m")
                    .arg(shell_compat::os(&cat(&[
                        b"chore(deps): reconcile lock against ",
                        &base_branch,
                        b" (automated)",
                    ]))),
                false,
            );
        }

        let r_head = capture(155, Command::new("git").arg("rev-parse").arg("HEAD"));
        let head_sha = subst(r_head.stdout);
        let r_origin = capture(
            155,
            Command::new("git")
                .arg("rev-parse")
                .arg(shell_compat::os(&cat(&[b"origin/", branch]))),
        );
        let origin_sha = subst(r_origin.stdout);

        if head_sha == origin_sha {
            out(&cat(&[
                b"#",
                num,
                b": already current with ",
                &base_branch,
                b" \xe2\x80\x94 nothing to push.\n",
            ]));
        } else {
            let push_rc = status(
                157,
                Command::new("git")
                    .arg("push")
                    .arg("--quiet")
                    .arg("origin")
                    .arg(shell_compat::os(&cat(&[b"HEAD:", branch]))),
                false,
            );
            if push_rc == 0 {
                out(&cat(&[
                    b"#",
                    num,
                    b": rebased onto ",
                    &base_branch,
                    b" and pushed.\n",
                ]));
            } else {
                out(&cat(&[b"::error::#", num, b": push failed.\n"]));
                rc = 1;
            }
        }
        out(b"::endgroup::\n");
    }

    rc
}

fn escape_jq_string(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    for &b in s {
        match b {
            b'\\' => out.extend_from_slice(b"\\\\"),
            b'"' => out.extend_from_slice(b"\\\""),
            _ => out.push(b),
        }
    }
    out
}
