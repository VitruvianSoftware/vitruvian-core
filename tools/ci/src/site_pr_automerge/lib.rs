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

//! //tools/ci:site_pr_automerge — arm/disarm auto-merge on website PRs.

use shell_compat::{capture_stdout as capture, cat, env, err, out, status, subst};
use std::process::Command;

fn say(summary: &[u8], msg: &[u8]) {
    out(&cat(&[msg, b"\n"]));
    if !summary.is_empty() {
        let _ = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(shell_compat::path(summary))
            .and_then(|mut f| {
                use std::io::Write;
                f.write_all(msg)?;
                f.write_all(b"\n\n")
            });
    }
}

fn fail(summary: &[u8], msg: &[u8]) -> i32 {
    out(&cat(&[b"::error title=auto-merge not armed::", msg, b"\n"]));
    if !summary.is_empty() {
        let _ = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(shell_compat::path(summary))
            .and_then(|mut f| {
                use std::io::Write;
                f.write_all(b"> [!WARNING]\n> **Auto-merge is not armed.** ")?;
                f.write_all(msg)?;
                f.write_all(b"\n\n")
            });
    }
    1
}

fn open_pr(repo: &[u8], branch: &[u8]) -> Result<Vec<u8>, i32> {
    let r = capture(
        103,
        Command::new("gh")
            .arg("pr")
            .arg("list")
            .arg("--repo")
            .arg(shell_compat::os(repo))
            .arg("--head")
            .arg(shell_compat::os(branch))
            .arg("--base")
            .arg("main")
            .arg("--state")
            .arg("open")
            .arg("--json")
            .arg("number")
            .arg("--jq")
            .arg(".[0].number // empty"),
    );
    if !r.ok() {
        return Err(r.status);
    }
    Ok(subst(r.stdout))
}

fn disarm_pr(repo: &[u8], summary: &[u8], number: &[u8], why: &[u8]) -> i32 {
    let rc = status(
        116,
        Command::new("gh")
            .arg("pr")
            .arg("merge")
            .arg(shell_compat::os(number))
            .arg("--repo")
            .arg(shell_compat::os(repo))
            .arg("--disable-auto"),
        false,
    );
    if rc == 0 {
        say(
            summary,
            &cat(&[b"Turned auto-merge off on #", number, b": ", why, b"."]),
        );
        0
    } else {
        out(&cat(&[
            b"::warning title=auto-merge still on::could not turn auto-merge off on #",
            number,
            b" (",
            why,
            b")\n",
        ]));
        if !summary.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(summary))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(b"> [!WARNING]\n> Could not turn auto-merge off on #")?;
                    f.write_all(number)?;
                    f.write_all(b" (")?;
                    f.write_all(why)?;
                    f.write_all(b").\n\n")
                });
        }
        1
    }
}

const USAGE: &[u8] =
    b"usage: site-pr-automerge disarm --branch <branch> | arm --branch <branch> --sha <sha>\n";

/// The script's `usage`: one message, exit 2.
fn usage() -> i32 {
    err(USAGE);
    2
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    // As the script: the arguments are checked first, then REPO.
    let mode: Vec<u8> = args.first().cloned().unwrap_or_default();
    let mut branch = Vec::new();
    let mut sha = Vec::new();
    let mut i = 1;
    while i < args.len() {
        let slot = match args[i].as_slice() {
            b"--branch" => &mut branch,
            b"--sha" => &mut sha,
            _ => return usage(),
        };
        // `shift 2` fails when the value is missing: usage.
        if i + 1 >= args.len() {
            return usage();
        }
        *slot = args[i + 1].clone();
        i += 2;
    }
    match mode.as_slice() {
        b"disarm" if !branch.is_empty() => {}
        b"arm" if !branch.is_empty() && !sha.is_empty() => {}
        _ => return usage(),
    }

    let repo = match env("REPO") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"REPO (owner/name) is not set\n");
            return 2;
        }
    };
    let summary = env("GITHUB_STEP_SUMMARY").unwrap_or_default();

    if mode == b"disarm" {
        let number = match open_pr(&repo, &branch) {
            Ok(n) => n,
            Err(_) => {
                out(&cat(&[
                    b"::error::could not look up the open pull request from ",
                    &branch,
                    b"\n",
                ]));
                return 1;
            }
        };
        if number.is_empty() {
            out(&cat(&[b"No open pull request from ", &branch, b" yet.\n"]));
            return 0;
        }
        let r = capture(
            136,
            Command::new("gh")
                .arg("pr")
                .arg("view")
                .arg(shell_compat::os(&number))
                .arg("--repo")
                .arg(shell_compat::os(&repo))
                .arg("--json")
                .arg("autoMergeRequest")
                .arg("--jq")
                .arg(".autoMergeRequest != null"),
        );
        if !r.ok() {
            out(&cat(&[b"::error::could not read #", &number, b"\n"]));
            return 1;
        }
        let armed = subst(r.stdout);
        if armed == b"true" {
            let rc = disarm_pr(
                &repo,
                &summary,
                &number,
                b"this run is about to push a new commit; it is armed again at that commit only",
            );
            if rc != 0 {
                return 1;
            }
        } else {
            out(&cat(&[b"Auto-merge is off on #", &number, b".\n"]));
        }
        return 0;
    }

    // arm mode
    let number = match open_pr(&repo, &branch) {
        Ok(n) => n,
        Err(_) => {
            return fail(
                &summary,
                &cat(&[
                    b"could not look up the open pull request from `",
                    &branch,
                    b"`.",
                ]),
            );
        }
    };
    if number.is_empty() {
        return fail(
            &summary,
            &cat(&[
                b"no open pull request from `",
                &branch,
                b"`, though this run just pushed it.",
            ]),
        );
    }

    // Read PR state: "<armed> <draft> <head> <hold labels>"
    let r = capture(
        109,
        Command::new("gh")
            .arg("pr")
            .arg("view")
            .arg(shell_compat::os(&number))
            .arg("--repo")
            .arg(shell_compat::os(&repo))
            .arg("--json")
            .arg("autoMergeRequest,isDraft,headRefOid,labels")
            .arg("--jq")
            .arg("[(.autoMergeRequest != null), .isDraft, .headRefOid, ([.labels[].name | select(. == \"do-not-automerge\" or . == \"needs-human\")] | join(\",\"))] | map(tostring) | join(\" \")"),
    );
    if !r.ok() {
        return fail(&summary, &cat(&[b"could not read #", &number, b"."]));
    }
    let state = subst(r.stdout);
    let fields: Vec<&[u8]> = state.splitn(4, |&c| c == b' ').collect();
    if fields.len() < 3 {
        return fail(&summary, &cat(&[b"could not read #", &number, b"."]));
    }
    let armed = fields[0];
    let draft = fields[1];
    let head = fields[2];
    let held = if fields.len() > 3 { fields[3] } else { b"" };

    if !held.is_empty() || draft == b"true" {
        let mut why = b"it is held".to_vec();
        if !held.is_empty() {
            why.extend_from_slice(b" (");
            // Replace commas with ", "
            for (i, part) in held.split(|&c| c == b',').enumerate() {
                if i > 0 {
                    why.extend_from_slice(b", ");
                }
                why.extend_from_slice(part);
            }
            why.extend_from_slice(b")");
        }
        if draft == b"true" {
            why.extend_from_slice(b" (a draft)");
        }
        if armed == b"true" {
            let rc = disarm_pr(&repo, &summary, &number, &why);
            if rc != 0 {
                return 1;
            }
        }
        say(
            &summary,
            &cat(&[
                b"#",
                &number,
                b" is not armed: ",
                &why,
                b". Lift the hold and arm it by hand: `gh pr merge ",
                &number,
                b" --squash --auto`.",
            ]),
        );
        return 0;
    }

    if head != sha.as_slice() {
        if armed == b"true" {
            let why = cat(&[
                b"its head moved to ",
                head,
                b" after this run pushed ",
                &sha,
            ]);
            let rc = disarm_pr(&repo, &summary, &number, &why);
            if rc != 0 {
                return 1;
            }
        }
        out(&cat(&[
            b"::warning title=auto-merge not armed::#",
            &number,
            b"'s head is ",
            head,
            b", not ",
            &sha,
            b": someone pushed after this run. Not arming a commit this run did not write.\n",
        ]));
        say(
            &summary,
            &cat(&[
                b"#",
                &number,
                b" is not armed: its head is `",
                head,
                b"`, not `",
                &sha,
                b"`, which this run pushed.",
            ]),
        );
        return 0;
    }

    if armed == b"true" {
        say(
            &summary,
            &cat(&[b"Auto-merge is already on for #", &number, b"."]),
        );
        return 0;
    }

    let rc = status(
        184,
        Command::new("gh")
            .arg("pr")
            .arg("merge")
            .arg(shell_compat::os(&number))
            .arg("--repo")
            .arg(shell_compat::os(&repo))
            .arg("--squash")
            .arg("--auto")
            .arg("--match-head-commit")
            .arg(shell_compat::os(&sha)),
        false,
    );
    if rc != 0 {
        return fail(
            &summary,
            &cat(&[
                b"`gh pr merge ",
                &number,
                b" --squash --auto --match-head-commit ",
                &sha,
                b"` failed. Re-run this workflow, or arm it by hand.",
            ]),
        );
    }
    say(
        &summary,
        &cat(&[
            b"Armed auto-merge on #",
            &number,
            b" at `",
            &sha,
            b"`: the merge queue merges it once its checks pass.",
        ]),
    );
    0
}
