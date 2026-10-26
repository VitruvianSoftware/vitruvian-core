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

//! notify-ci-issues.sh — poll for stuck approvals and main-branch failures,
//! push an ntfy notification for each. Always exits 0.

use shell_compat::{capture, cat, env_or, env_or_empty, err, out, subst};
use std::process::Command;

fn iso_cutoff(minutes: u64) -> Vec<u8> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let cutoff_secs = now.as_secs().saturating_sub(minutes * 60);
    let s = cutoff_secs % 60;
    let m = (cutoff_secs / 60) % 60;
    let h = (cutoff_secs / 3600) % 24;
    let total_days = (cutoff_secs / 86400) as i64;
    let z = total_days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let yr = if mo <= 2 { y + 1 } else { y };
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", yr, mo, d, h, m, s).into_bytes()
}

fn pipe_jq(input: &[u8], args: &[&[u8]], filter: &str) -> Vec<u8> {
    let mut cmd = Command::new("jq");
    for a in args {
        cmd.arg(shell_compat::os(a));
    }
    cmd.arg(filter);
    cmd.stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                let _ = stdin.write_all(input);
            }
            match child.wait_with_output() {
                Ok(o) if o.status.success() => subst(o.stdout),
                _ => Vec::new(),
            }
        }
        Err(_) => Vec::new(),
    }
}

fn gh_api_paginate(url: &[u8]) -> (Vec<u8>, bool) {
    let r = capture(
        0,
        Command::new("gh")
            .arg("api")
            .arg(shell_compat::os(url))
            .arg("--paginate"),
    );
    let ok = r.ok();
    (r.stdout, ok)
}

fn gh_api(url: &[u8]) -> shell_compat::Ran {
    capture(0, Command::new("gh").arg("api").arg(shell_compat::os(url)))
}

fn gh_api_quiet(url: &[u8]) -> shell_compat::Ran {
    let mut cmd = Command::new("gh");
    cmd.arg("api")
        .arg(shell_compat::os(url))
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    match cmd.output() {
        Ok(o) => shell_compat::Ran {
            status: shell_compat::status_code(o.status),
            stdout: o.stdout,
            stderr: Vec::new(),
        },
        Err(_) => shell_compat::Ran {
            status: 1,
            stdout: Vec::new(),
            stderr: Vec::new(),
        },
    }
}

fn notify(title: &[u8], message: &[u8], priority: &[u8], tags: &[u8], url: &[u8]) {
    let ntfy_password = env_or_empty("NTFY_PASSWORD");
    let r = capture(
        0,
        Command::new("jq")
            .arg("-n")
            .arg("--arg")
            .arg("title")
            .arg(shell_compat::os(title))
            .arg("--arg")
            .arg("message")
            .arg(shell_compat::os(message))
            .arg("--argjson")
            .arg("priority")
            .arg(shell_compat::os(priority))
            .arg("--argjson")
            .arg("tags")
            .arg(shell_compat::os(tags))
            .arg("--arg")
            .arg("click")
            .arg(shell_compat::os(url))
            .arg(r#"{"topic":"vitruvian-alerts","title":$title,"message":$message,"priority":$priority,"tags":$tags,"click":$click}"#),
    );
    if !r.ok() {
        return;
    }
    let body = subst(r.stdout);
    let auth = cat(&[b"github-actions:", &ntfy_password]);
    let rc = shell_compat::status(
        0,
        Command::new("curl")
            .arg("-fsS")
            .arg("-u")
            .arg(shell_compat::os(&auth))
            .arg("-H")
            .arg("Content-Type: application/json")
            .arg("-H")
            .arg("User-Agent: vitruvian-ci-notify/1.0")
            .arg("-X")
            .arg("POST")
            .arg("https://ntfy.ipv1337.dev")
            .arg("-d")
            .arg(shell_compat::os(&body))
            .stdout(std::process::Stdio::null()),
        true,
    );
    if rc != 0 {
        err(&cat(&[b"WARN: ntfy push failed for: ", title, b"\n"]));
    }
}

fn check_waiting(repo: &[u8], cutoff: &[u8]) {
    out(&cat(&[
        b"Checking for runs waiting on approval, updated since ",
        cutoff,
        b"...\n",
    ]));
    let url = cat(&[b"repos/", repo, b"/actions/runs?status=waiting&per_page=50"]);
    let (raw, _) = gh_api_paginate(&url);
    let filter = r#".workflow_runs[] | select(.updated_at >= $cutoff) | [.name, .html_url] | @tsv"#;
    let jq_out = pipe_jq(&raw, &[b"-r", b"--arg", b"cutoff", cutoff], filter);
    for line in shell_compat::lines(&jq_out) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
        if fields.len() < 2 {
            continue;
        }
        let name = fields[0];
        let url = fields[1];
        out(&cat(&[b"  -> waiting: ", name, b" (", url, b")\n"]));
        notify(
            &cat(&[b"[ci] approval needed: ", name]),
            &cat(&[
                b"Workflow run is waiting on a required-reviewer approval. ",
                url,
            ]),
            b"4",
            b"[\"hourglass_flowing_sand\",\"ci\"]",
            url,
        );
    }
}

fn check_action_required(repo: &[u8], cutoff: &[u8]) {
    out(&cat(&[
        b"Checking for runs needing approval to start, updated since ",
        cutoff,
        b"...\n",
    ]));
    let url = cat(&[
        b"repos/",
        repo,
        b"/actions/runs?status=action_required&per_page=50",
    ]);
    let (raw, _) = gh_api_paginate(&url);
    let filter = concat!(
        "[.[].workflow_runs[] | select(.updated_at >= $cutoff)]",
        " | group_by(.head_branch)[]",
        " | [.[0].head_branch, (length | tostring), .[0].html_url] | @tsv"
    );
    let jq_out = pipe_jq(&raw, &[b"-s", b"-r", b"--arg", b"cutoff", cutoff], filter);
    for line in shell_compat::lines(&jq_out) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(3, |&c| c == b'\t').collect();
        if fields.len() < 3 {
            continue;
        }
        let branch = fields[0];
        let count = fields[1];
        let url = fields[2];
        out(&cat(&[
            b"  -> action_required: ",
            count,
            b" run(s) on ",
            branch,
            b" (",
            url,
            b")\n",
        ]));
        notify(
            &cat(&[b"[ci] approval needed to start: ", branch]),
            &cat(&[
                count,
                b" workflow run(s) on ",
                branch,
                b" will not start until approved ('Approve and run'). Required checks stay absent and the PR stays blocked until then. ",
                url,
            ]),
            b"4",
            b"[\"hourglass_flowing_sand\",\"ci\"]",
            url,
        );
    }
}

fn check_failures(repo: &[u8], mirrors: &[u8], cutoff: &[u8]) {
    let recent_filter =
        r#".workflow_runs[] | select(.updated_at >= $cutoff) | [.name, .html_url] | @tsv"#;

    let mut repos: Vec<Vec<u8>> = vec![repo.to_vec()];
    for m in shell_compat::ifs_split(mirrors) {
        if !m.is_empty() {
            repos.push(m);
        }
    }

    for r in &repos {
        out(&cat(&[
            b"Checking for failures on main in ",
            r,
            b", updated since ",
            cutoff,
            b"...\n",
        ]));
        let url = cat(&[
            b"repos/",
            r,
            b"/actions/runs?branch=main&event=push&status=failure&per_page=20",
        ]);
        let api_r = capture(
            0,
            Command::new("gh")
                .arg("api")
                .arg(shell_compat::os(&url))
                .arg("--paginate"),
        );
        if !api_r.ok() {
            let msg = subst(api_r.stderr);
            let trunc = if msg.len() > 200 { &msg[..200] } else { &msg };
            err(&cat(&[
                b"WARN: cannot read ",
                r,
                b"'s runs -- NOT watching it: ",
                trunc,
                b"\n",
            ]));
            continue;
        }
        let jq_out = pipe_jq(
            &api_r.stdout,
            &[b"-r", b"--arg", b"cutoff", cutoff],
            recent_filter,
        );
        for line in shell_compat::lines(&jq_out) {
            if line.is_empty() {
                continue;
            }
            let fields: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
            if fields.len() < 2 {
                continue;
            }
            let name = fields[0];
            let url = fields[1];
            out(&cat(&[b"  -> failed on main: ", name, b" (", url, b")\n"]));
            if r.as_slice() == repo {
                notify(
                    &cat(&[b"[ci] main broken: ", name]),
                    &cat(&[b"Failed on main after landing. ", url]),
                    b"5",
                    b"[\"red_circle\",\"ci\"]",
                    url,
                );
            } else {
                let short_name = match r.iter().position(|&c| c == b'/') {
                    Some(i) => &r[i + 1..],
                    None => r.as_slice(),
                };
                notify(
                    &cat(&[b"[ci] ", short_name, b" broken: ", name]),
                    &cat(&[
                        b"Failed on ",
                        r,
                        b"'s main after landing. This is an exported mirror; the fix usually belongs in vitruvian-core. ",
                        url,
                    ]),
                    b"4",
                    b"[\"red_circle\",\"ci\",\"mirror\"]",
                    url,
                );
            }
        }
    }
}

fn check_queue_bypass(repo: &[u8], cutoff: &[u8], allow_list: &[u8]) {
    out(&cat(&[
        b"Checking for commits on main that skipped the merge queue, since ",
        cutoff,
        b"...\n",
    ]));
    let url = cat(&[
        b"repos/",
        repo,
        b"/commits?sha=main&since=",
        cutoff,
        b"&per_page=50",
    ]);
    let api_r = gh_api(&url);
    if !api_r.ok() {
        let msg = subst(api_r.stderr);
        let trunc = if msg.len() > 200 { &msg[..200] } else { &msg };
        err(&cat(&[
            b"WARN: cannot list ",
            repo,
            b"'s recent commits -- NOT watching for queue bypasses: ",
            trunc,
            b"\n",
        ]));
        return;
    }

    let jq_filter = r#".[] | [.sha, (.author.login // .commit.author.name // "unknown"), .html_url, (.commit.message | split("\n")[0])] | @tsv"#;
    let jq_out = pipe_jq(&api_r.stdout, &[b"-r"], jq_filter);

    let allow_padded = cat(&[b" ", allow_list, b" "]);

    for line in shell_compat::lines(&jq_out) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(4, |&c| c == b'\t').collect();
        if fields.len() < 4 {
            continue;
        }
        let sha = fields[0];
        let who = fields[1];
        let url = fields[2];
        let subject = fields[3];

        let who_padded = cat(&[b" ", who, b" "]);
        if shell_compat::contains(&allow_padded, &who_padded) {
            continue;
        }

        let check_url = cat(&[
            b"repos/",
            repo,
            b"/actions/runs?event=merge_group&head_sha=",
            sha,
            b"&per_page=1",
        ]);
        let check_r = gh_api_quiet(&check_url);
        if !check_r.ok() {
            let sha_short = if sha.len() >= 9 { &sha[..9] } else { sha };
            err(&cat(&[
                b"WARN: cannot tell whether ",
                sha_short,
                b" went through the merge queue\n",
            ]));
            continue;
        }

        let tested_s = pipe_jq(&check_r.stdout, &[b"-r"], ".total_count");
        let tested_str = match std::str::from_utf8(&tested_s) {
            Ok(s) => s.trim(),
            Err(_) => {
                let sha_short = if sha.len() >= 9 { &sha[..9] } else { sha };
                err(&cat(&[
                    b"WARN: cannot tell whether ",
                    sha_short,
                    b" went through the merge queue\n",
                ]));
                continue;
            }
        };
        let tested: i64 = match tested_str.parse() {
            Ok(n) => n,
            Err(_) => {
                let sha_short = if sha.len() >= 9 { &sha[..9] } else { sha };
                err(&cat(&[
                    b"WARN: cannot tell whether ",
                    sha_short,
                    b" went through the merge queue\n",
                ]));
                continue;
            }
        };
        if tested != 0 {
            continue;
        }

        let sha_short = if sha.len() >= 9 { &sha[..9] } else { sha };
        out(&cat(&[
            b"  -> merged past the queue: ",
            sha_short,
            b" ",
            subject,
            b" (",
            url,
            b")\n",
        ]));
        notify(
            &cat(&[b"[ci] merged past the queue: ", sha_short]),
            &cat(&[
                b"This commit is on main but the merge queue never tested it: ",
                subject,
                b" (author ",
                who,
                b"). It was merged directly. Check main's status. ",
                url,
            ]),
            b"4",
            b"[\"warning\",\"ci\"]",
            url,
        );
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let repo = env_or_empty("REPO");
    if repo.is_empty() {
        err(b"REPO must be set (owner/repo)\n");
        return 1;
    }
    let cutoff_minutes: u64 = std::str::from_utf8(&env_or("CUTOFF_MINUTES", b"20"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(20);
    let mirrors = env_or_empty("MIRRORS");
    let queue_bypass_allow = env_or("QUEUE_BYPASS_ALLOW", b"vitruvian-copybara-sync[bot]");

    let cutoff = iso_cutoff(cutoff_minutes);

    check_waiting(&repo, &cutoff);
    check_action_required(&repo, &cutoff);
    check_failures(&repo, &mirrors, &cutoff);
    check_queue_bypass(&repo, &cutoff, &queue_bypass_allow);

    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_cutoff_format() {
        let ts = iso_cutoff(0);
        let s = std::str::from_utf8(&ts).unwrap();
        assert!(s.ends_with('Z'));
        assert_eq!(s.len(), 20);
        assert_eq!(&s[4..5], "-");
        assert_eq!(&s[7..8], "-");
        assert_eq!(&s[10..11], "T");
        assert_eq!(&s[13..14], ":");
        assert_eq!(&s[16..17], ":");
    }

    #[test]
    fn iso_cutoff_subtracts() {
        let now = iso_cutoff(0);
        let ago = iso_cutoff(60);
        assert!(now > ago);
    }
}
