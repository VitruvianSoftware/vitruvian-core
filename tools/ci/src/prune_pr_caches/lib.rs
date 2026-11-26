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

//! prune-pr-caches — delete GitHub Actions caches belonging to CLOSED pull
//! requests, deleted merge-queue branches, and superseded LLVM caches on main.

use shell_compat::{capture, cat, env_or, env_or_empty, err, out, status, subst, which};
use std::collections::HashMap;
use std::process::Command;

fn log(msg: &[u8]) {
    err(&cat(&[b"prune-pr-caches: ", msg, b"\n"]));
}

struct MainEntry {
    id: Vec<u8>,
    id_num: Option<u64>,
    size: u64,
    created_at: Vec<u8>,
}

/// Group key for `refs/heads/main` LLVM contents caches: returns the
/// `llvm-contents-v2-<os>-<osrel>-` prefix so superseded `MODULE.bazel`
/// hashes are pruned while preserving the newest entry per `(os, osrel)`.
fn llvm_main_group_prefix(key: &[u8]) -> Option<&[u8]> {
    const PREFIX: &[u8] = b"llvm-contents-v2-";
    let rest = key.strip_prefix(PREFIX)?;
    let mut parts = rest.split(|&c| c == b'-');
    let os = parts.next()?;
    let osrel = parts.next()?;
    let hash = parts.last()?;
    if os.is_empty() || osrel.is_empty() || hash.is_empty() {
        return None;
    }
    let last_dash = key.iter().rposition(|&c| c == b'-')?;
    Some(&key[..=last_dash])
}

#[allow(clippy::too_many_arguments)]
fn delete_or_dry_run(
    gh: &[u8],
    repo: &[u8],
    dry_run: &[u8],
    id: &[u8],
    size: u64,
    ref_name: &[u8],
    reason: &[u8],
    deleted: &mut u64,
    freed: &mut u64,
) {
    if !dry_run.is_empty() {
        log(&cat(&[
            b"DRY_RUN would delete cache ",
            id,
            b" (",
            (size / 1048576).to_string().as_bytes(),
            b"MiB) from ",
            ref_name,
            b" (",
            reason,
            b")",
        ]));
        *deleted += 1;
        *freed += size;
        return;
    }

    let rc = status(
        199,
        Command::new(shell_compat::os(gh))
            .arg("api")
            .arg("-X")
            .arg("DELETE")
            .arg(shell_compat::os(&cat(&[
                b"repos/",
                repo,
                b"/actions/caches/",
                id,
            ])))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null()),
        true,
    );
    if rc == 0 {
        *deleted += 1;
        *freed += size;
    } else {
        log(&cat(&[b"failed to delete cache ", id, b" from ", ref_name]));
    }
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let repo = env_or("REPO", b"VitruvianSoftware/vitruvian-core");
    let gh = env_or("GH", b"gh");
    let mut only_pr = Vec::new();
    let mut explicit_prune_main = false;
    for arg in args {
        if arg == b"--prune-main" {
            explicit_prune_main = true;
        } else if only_pr.is_empty() && !arg.is_empty() {
            only_pr = arg.clone();
        }
    }
    let prune_main = explicit_prune_main || only_pr.is_empty();
    let dry_run = env_or_empty("DRY_RUN");
    let cache_limit_gb = env_or_empty("CACHE_LIMIT_GB");

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
            .arg(".actions_caches[] | [.id, .size_in_bytes, .ref, (.key // \"\"), (.created_at // \"\")] | @tsv"),
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
    let mut main_llvm_groups: HashMap<Vec<u8>, Vec<MainEntry>> = HashMap::new();

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
            // gh reports an API error as "gh: <message> (HTTP <status>)".
            // Only the status says the branch is gone: a 5xx message carries
            // the request URL, and a queue branch's SHA can contain "404".
            let combined = cat(&[&r.stdout, &r.stderr]);
            let lower: Vec<u8> = combined.iter().map(|c| c.to_ascii_lowercase()).collect();
            if shell_compat::contains(&lower, b"(http 404)") {
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
        let fields: Vec<&[u8]> = line.splitn(5, |&c| c == b'\t').collect();
        if fields.len() < 3 {
            continue;
        }
        let id = fields[0];
        let size: u64 = std::str::from_utf8(fields[1])
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        let ref_name = fields[2];
        let key = fields.get(3).copied().unwrap_or(b"");
        let created_at = fields.get(4).copied().unwrap_or(b"");
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
            if prune_main && ref_name == b"refs/heads/main" {
                if let Some(group_prefix) = llvm_main_group_prefix(key) {
                    let id_num = std::str::from_utf8(id)
                        .ok()
                        .and_then(|s| s.parse::<u64>().ok());
                    main_llvm_groups
                        .entry(group_prefix.to_vec())
                        .or_default()
                        .push(MainEntry {
                            id: id.to_vec(),
                            id_num,
                            size,
                            created_at: created_at.to_vec(),
                        });
                }
            }
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

        delete_or_dry_run(
            &gh,
            &repo,
            &dry_run,
            id,
            size,
            ref_name,
            &reason,
            &mut deleted,
            &mut freed,
        );
    }

    if prune_main {
        let mut prefixes: Vec<Vec<u8>> = main_llvm_groups.keys().cloned().collect();
        prefixes.sort();
        for prefix in prefixes {
            let entries = main_llvm_groups.get_mut(&prefix).unwrap();
            if entries.len() <= 1
                || entries
                    .iter()
                    .any(|e| e.created_at.is_empty() || e.id_num.is_none())
            {
                continue;
            }
            entries.sort_by(|a, b| {
                a.created_at
                    .cmp(&b.created_at)
                    .then_with(|| a.id_num.cmp(&b.id_num))
            });
            for entry in &entries[..entries.len() - 1] {
                delete_or_dry_run(
                    &gh,
                    &repo,
                    &dry_run,
                    &entry.id,
                    entry.size,
                    b"refs/heads/main",
                    b"superseded main cache",
                    &mut deleted,
                    &mut freed,
                );
            }
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
    if cache_limit_gb.is_empty() {
        log(&cat(&[
            b"remaining: ",
            remaining_entries.to_string().as_bytes(),
            b" entries, ",
            (remaining_bytes / 1048576).to_string().as_bytes(),
            b"MiB",
        ]));
    } else {
        log(&cat(&[
            b"remaining: ",
            remaining_entries.to_string().as_bytes(),
            b" entries, ",
            (remaining_bytes / 1048576).to_string().as_bytes(),
            b"MiB of the ",
            &cache_limit_gb,
            b"GB repo budget",
        ]));
    }

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
