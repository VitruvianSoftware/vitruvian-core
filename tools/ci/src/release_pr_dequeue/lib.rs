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

//! release-pr-dequeue — take a component's release PR out of the merge
//! queue when main has just gained a change that PR does not list.

use shell_compat::{capture, cat, out, read_fields, subst};
use std::process::Command;

fn skip(msg: &[u8]) -> i32 {
    out(&cat(&[
        b"::warning title=release PR left in the queue::",
        msg,
        b"\n",
    ]));
    0
}

fn require(name: &str) -> Result<Vec<u8>, i32> {
    match shell_compat::env(name) {
        Some(v) if !v.is_empty() => Ok(v),
        _ => {
            shell_compat::err(&cat(&[name.as_bytes(), b" must be set\n"]));
            Err(1)
        }
    }
}

fn code_at(repo: &[u8], sha: &[u8], code_path: &[u8]) -> Result<Vec<u8>, Vec<u8>> {
    let url = cat(&[
        b"repos/",
        repo,
        b"/commits?sha=",
        sha,
        b"&path=",
        code_path,
        b"&per_page=1",
    ]);
    let r = capture(
        90,
        Command::new("gh")
            .arg("api")
            .arg(shell_compat::os(&url))
            .arg("--jq")
            .arg(".[0].sha // empty"),
    );
    let combined = if r.stderr.is_empty() {
        subst(r.stdout.clone())
    } else {
        subst(cat(&[&r.stdout, &r.stderr]))
    };
    if !r.ok() {
        return Err(combined);
    }
    Ok(subst(r.stdout))
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = match require("REPO") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let component = match require("COMPONENT") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let code_path = match require("CODE_PATH") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let main_sha = match require("MAIN_SHA") {
        Ok(v) => v,
        Err(_) => return 1,
    };

    let branch = cat(&[b"release-please--branches--main--components--", &component]);

    // Split REPO into owner/name.
    let owner_end = repo.iter().position(|&c| c == b'/').unwrap_or(repo.len());
    let owner = &repo[..owner_end];
    let name = if owner_end < repo.len() {
        &repo[owner_end + 1..]
    } else {
        b""
    };

    let query = b"query($owner:String!,$name:String!,$branch:String!){repository(owner:$owner,name:$name){pullRequests(headRefName:$branch,states:OPEN,first:10){nodes{number id headRefOid isCrossRepository isInMergeQueue}}}}";
    let jq_expr = r#".data.repository.pullRequests.nodes | map(select(.isCrossRepository | not)) | .[0] // empty | "\(.number)\t\(.id)\t\(.headRefOid)\t\(.isInMergeQueue)""#;

    let r = capture(
        72,
        Command::new("gh")
            .arg("api")
            .arg("graphql")
            .arg("-f")
            .arg(shell_compat::os(&cat(&[b"owner=", owner])))
            .arg("-f")
            .arg(shell_compat::os(&cat(&[b"name=", name])))
            .arg("-f")
            .arg(shell_compat::os(&cat(&[b"branch=", &branch])))
            .arg("-f")
            .arg(shell_compat::os(&cat(&[b"query=", query])))
            .arg("--jq")
            .arg(jq_expr),
    );
    let pr_row = subst(if r.ok() {
        r.stdout.clone()
    } else {
        cat(&[&r.stdout, &r.stderr])
    });

    if !r.ok() {
        return skip(&cat(&[
            b"could not list open release PRs on ",
            &branch,
            b": ",
            &pr_row,
        ]));
    }
    if pr_row.is_empty() {
        out(&cat(&[
            b"No open release PR on ",
            &branch,
            b" \xe2\x80\x94 nothing to dequeue.\n",
        ]));
        return 0;
    }

    let fields = read_fields(&pr_row, b"\t", 4);
    let pr = &fields[0];
    let pr_id = &fields[1];
    let head_sha = &fields[2];
    let queued = &fields[3];

    if queued.as_slice() != b"true" {
        out(&cat(&[
            b"Release PR #",
            pr,
            b" is not in the merge queue \xe2\x80\x94 release-please can update it.\n",
        ]));
        return 0;
    }

    // Get parent of the release commit.
    let pr_parent = capture(
        85,
        Command::new("gh")
            .arg("api")
            .arg(shell_compat::os(&cat(&[
                b"repos/",
                &repo,
                b"/commits/",
                head_sha,
            ])))
            .arg("--jq")
            .arg(".parents[0].sha // empty"),
    );
    let parent_combined = if pr_parent.stderr.is_empty() {
        subst(pr_parent.stdout.clone())
    } else {
        subst(cat(&[&pr_parent.stdout, &pr_parent.stderr]))
    };
    if !pr_parent.ok() {
        return skip(&cat(&[
            b"could not read release commit ",
            head_sha,
            b" of #",
            pr,
            b": ",
            &parent_combined,
        ]));
    }
    let parent = subst(pr_parent.stdout);
    if parent.is_empty() {
        return skip(&cat(&[
            b"release commit ",
            head_sha,
            b" of #",
            pr,
            b" has no parent",
        ]));
    }

    let listed = match code_at(&repo, &parent, &code_path) {
        Ok(v) => v,
        Err(e) => {
            return skip(&cat(&[
                b"could not find the last ",
                &code_path,
                b" commit at ",
                &parent,
                b": ",
                &e,
            ]));
        }
    };
    let latest = match code_at(&repo, &main_sha, &code_path) {
        Ok(v) => v,
        Err(e) => {
            return skip(&cat(&[
                b"could not find the last ",
                &code_path,
                b" commit at ",
                &main_sha,
                b": ",
                &e,
            ]));
        }
    };

    if listed.is_empty() || latest.is_empty() {
        return skip(&cat(&[
            b"no ",
            &code_path,
            b" commit found at ",
            &parent,
            b" or ",
            &main_sha,
        ]));
    }

    if listed == latest {
        out(&cat(&[
            b"Queued release PR #",
            pr,
            b" already releases ",
            &latest,
            b" \xe2\x80\x94 leaving it in the queue.\n",
        ]));
        return 0;
    }

    out(&cat(&[
        b"Queued release PR #",
        pr,
        b" releases ",
        &listed,
        b", but main is at ",
        &latest,
        b" \xe2\x80\x94 taking it out of the merge queue so release-please can refresh it.\n",
    ]));

    let dequeue_query = b"mutation($id:ID!){dequeuePullRequest(input:{id:$id}){clientMutationId}}";
    let dr = capture(
        107,
        Command::new("gh")
            .arg("api")
            .arg("graphql")
            .arg("-f")
            .arg(shell_compat::os(&cat(&[b"id=", pr_id])))
            .arg("-f")
            .arg(shell_compat::os(&cat(&[b"query=", dequeue_query]))),
    );
    let dr_combined = subst(cat(&[&dr.stdout, &dr.stderr]));
    if !dr.ok() {
        return skip(&cat(&[b"could not dequeue #", pr, b": ", &dr_combined]));
    }
    out(&cat(&[
        b"Release PR #",
        pr,
        b" is out of the merge queue.\n",
    ]));
    0
}
