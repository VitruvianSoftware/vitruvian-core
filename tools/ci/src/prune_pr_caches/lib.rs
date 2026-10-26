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

//! prune-pr-caches.sh — delete GitHub Actions caches belonging to CLOSED pull
//! requests.

use shell_compat::{capture, cat, env_or, env_or_empty, err, out, status, subst, which};
use std::collections::HashMap;
use std::process::Command;

fn log(msg: &[u8]) {
    err(&cat(&[b"prune-pr-caches: ", msg, b"\n"]));
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let repo = env_or("REPO", b"VitruvianSoftware/vitruvian-core");
    let gh = env_or("GH", b"gh");
    let only_pr = if !args.is_empty() {
        args[0].clone()
    } else {
        Vec::new()
    };
    let dry_run = env_or_empty("DRY_RUN");

    if which(&gh).is_none() {
        log(b"gh not found on PATH");
        return 2;
    }

    let r = capture(
        80,
        Command::new(shell_compat::os(&gh))
            .arg("api")
            .arg("--paginate")
            .arg(shell_compat::os(&cat(&[
                b"repos/",
                &repo,
                b"/actions/caches?per_page=100",
            ])))
            .arg("--jq")
            .arg(".actions_caches[] | [.id, .size_in_bytes, .ref] | @tsv"),
    );
    let listing = subst(r.stdout);
    if listing.is_empty() {
        log(b"no caches found (or the listing call failed) -- nothing to do");
        return 0;
    }

    let mut deleted: u64 = 0;
    let mut freed: u64 = 0;
    let mut kept_open: u64 = 0;
    let mut kept_live: u64 = 0;
    let mut total_entries: u64 = 0;
    let mut total_bytes: u64 = 0;

    let mut pr_state_cache: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();
    let mut branch_gone_cache: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();

    let state_of = |num: &[u8], cache: &mut HashMap<Vec<u8>, Vec<u8>>| -> Vec<u8> {
        if let Some(v) = cache.get(num) {
            return v.clone();
        }
        let r = capture(
            108,
            Command::new(shell_compat::os(&gh))
                .arg("pr")
                .arg("view")
                .arg(shell_compat::os(num))
                .arg("--repo")
                .arg(shell_compat::os(&repo))
                .arg("--json")
                .arg("state")
                .arg("--jq")
                .arg(".state"),
        );
        let st = if r.ok() { subst(r.stdout) } else { Vec::new() };
        cache.insert(num.to_vec(), st.clone());
        st
    };

    let branch_gone = |branch: &[u8], cache: &mut HashMap<Vec<u8>, Vec<u8>>| -> Vec<u8> {
        if let Some(v) = cache.get(branch) {
            return v.clone();
        }
        let r = capture(
            120,
            Command::new(shell_compat::os(&gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    &repo,
                    b"/branches/",
                    branch,
                ]))),
        );
        let result = if r.ok() {
            b"no".to_vec()
        } else {
            let combined = cat(&[&r.stdout, &r.stderr]);
            let lower: Vec<u8> = combined.iter().map(|c| c.to_ascii_lowercase()).collect();
            if shell_compat::contains(&lower, b"404")
                || shell_compat::contains(&lower, b"not found")
            {
                b"yes".to_vec()
            } else {
                b"unknown".to_vec()
            }
        };
        cache.insert(branch.to_vec(), result.clone());
        result
    };

    for line in shell_compat::lines(&listing) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(3, |&c| c == b'\t').collect();
        if fields.len() < 3 {
            continue;
        }
        let id = fields[0];
        let size: u64 = std::str::from_utf8(fields[1])
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        let ref_name = fields[2];
        if ref_name.is_empty() {
            continue;
        }

        total_entries += 1;
        total_bytes += size;

        // Classify ref
        let kind;
        if shell_compat::contains(ref_name, b"/pull/") {
            kind = "pr";
        } else if ref_name.starts_with(b"refs/heads/gh-readonly-queue/") {
            kind = "queue";
        } else {
            continue;
        }

        let num;
        if kind == "pr" {
            // refs/pull/<n>/merge -> <n>
            let parts: Vec<&[u8]> = ref_name.split(|&c| c == b'/').collect();
            if parts.len() >= 3 {
                num = parts[2].to_vec();
            } else {
                continue;
            }
        } else {
            // refs/heads/gh-readonly-queue/<base>/pr-<n>-<sha> -> <n>
            let leaf = ref_name.rsplit(|&c| c == b'/').next().unwrap_or(b"");
            let leaf = leaf.strip_prefix(b"pr-").unwrap_or(leaf);
            if let Some(dash) = leaf.iter().position(|&c| c == b'-') {
                num = leaf[..dash].to_vec();
            } else {
                num = leaf.to_vec();
            }
        }

        if !only_pr.is_empty() && num != only_pr {
            continue;
        }

        let reason;
        if kind == "queue" {
            let branch_name = ref_name.strip_prefix(b"refs/heads/").unwrap_or(ref_name);
            let gone = branch_gone(branch_name, &mut branch_gone_cache);
            match gone.as_slice() {
                b"yes" => {}
                b"no" => {
                    kept_live += 1;
                    continue;
                }
                _ => {
                    log(&cat(&[
                        b"queue ref ",
                        ref_name,
                        b": existence undeterminable -- leaving its cache alone",
                    ]));
                    continue;
                }
            }
            reason = b"queue branch deleted".to_vec();
        } else {
            let st = state_of(&num, &mut pr_state_cache);
            match st.as_slice() {
                b"MERGED" | b"CLOSED" => {}
                b"OPEN" => {
                    kept_open += 1;
                    continue;
                }
                _ => {
                    log(&cat(&[
                        b"PR #",
                        &num,
                        b": state unknown ('",
                        &st,
                        b"') -- leaving its caches alone",
                    ]));
                    continue;
                }
            }
            reason = cat(&[b"PR ", &st]);
        }

        if !dry_run.is_empty() {
            log(&cat(&[
                b"DRY_RUN would delete cache ",
                id,
                b" (",
                (size / 1048576).to_string().as_bytes(),
                b"MiB) from ",
                ref_name,
                b" (",
                &reason,
                b")",
            ]));
            deleted += 1;
            freed += size;
            continue;
        }

        let rc = status(
            199,
            Command::new(shell_compat::os(&gh))
                .arg("api")
                .arg("-X")
                .arg("DELETE")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    &repo,
                    b"/actions/caches/",
                    id,
                ])))
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        );
        if rc == 0 {
            deleted += 1;
            freed += size;
        } else {
            log(&cat(&[b"failed to delete cache ", id, b" from ", ref_name]));
        }
    }

    let remaining_entries;
    let remaining_bytes;
    if !dry_run.is_empty() {
        remaining_entries = total_entries;
        remaining_bytes = total_bytes;
    } else {
        remaining_entries = total_entries - deleted;
        remaining_bytes = total_bytes - freed;
    }

    let ies = if deleted == 1 { "y" } else { "ies" };
    log(&cat(&[
        b"deleted ",
        deleted.to_string().as_bytes(),
        b" orphaned cache entr",
        ies.as_bytes(),
        b", freed ",
        (freed / 1048576).to_string().as_bytes(),
        b"MiB (left ",
        kept_open.to_string().as_bytes(),
        b" belonging to open PRs, ",
        kept_live.to_string().as_bytes(),
        b" to live queue entries)",
    ]));
    log(&cat(&[
        b"remaining: ",
        remaining_entries.to_string().as_bytes(),
        b" entries, ",
        (remaining_bytes / 1048576).to_string().as_bytes(),
        b"MiB of the 10240MiB repo budget",
    ]));

    out(&cat(&[b"deleted=", deleted.to_string().as_bytes(), b"\n"]));
    out(&cat(&[
        b"freed_mib=",
        (freed / 1048576).to_string().as_bytes(),
        b"\n",
    ]));
    out(&cat(&[
        b"remaining_entries=",
        remaining_entries.to_string().as_bytes(),
        b"\n",
    ]));
    out(&cat(&[
        b"remaining_mib=",
        (remaining_bytes / 1048576).to_string().as_bytes(),
        b"\n",
    ]));

    0
}
