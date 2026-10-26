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

//! rdeps-map-ref.sh — store/fetch/prune rdeps maps as git refs.

use shell_compat::{capture, cat, env, env_or, err, os, out, subst};
use std::process::Command;

const PREFIX: &[u8] = b"refs/rdeps-map";

fn log(msg: &[u8]) {
    err(&cat(&[b"rdeps-map-ref: ", msg, b"\n"]));
}

fn is_sha(s: &[u8]) -> bool {
    s.len() == 40
        && s.iter()
            .all(|&c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
}

fn auth_git_cmd() -> Command {
    let mut cmd = Command::new("git");
    if let Some(token) = env("GH_TOKEN") {
        if !token.is_empty() {
            let plain = cat(&[b"x-access-token:", &token]);
            let encoded = base64_encode(&plain);
            let header = cat(&[
                b"http.https://github.com/.extraheader=AUTHORIZATION: basic ",
                &encoded,
            ]);
            cmd.arg("-c").arg(os(&header));
        }
    }
    cmd
}

fn base64_encode(input: &[u8]) -> Vec<u8> {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity((input.len() + 2) / 3 * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(CHARS[((triple >> 18) & 0x3F) as usize]);
        out.push(CHARS[((triple >> 12) & 0x3F) as usize]);
        if chunk.len() > 1 {
            out.push(CHARS[((triple >> 6) & 0x3F) as usize]);
        } else {
            out.push(b'=');
        }
        if chunk.len() > 2 {
            out.push(CHARS[(triple & 0x3F) as usize]);
        } else {
            out.push(b'=');
        }
    }
    out
}

fn map_commit(file: &[u8]) -> Vec<u8> {
    let r = capture(
        0,
        Command::new("jq")
            .arg("-r")
            .arg(".commit // \"\"")
            .arg(os(file)),
    );
    if r.ok() {
        subst(r.stdout)
    } else {
        Vec::new()
    }
}

fn cmd_save(args: &[Vec<u8>], remote: &[u8]) -> i32 {
    if args.len() < 3 {
        log(b"usage: save <map.json> <sha>");
        return 2;
    }
    let file = &args[1];
    let sha = &args[2];
    if !is_sha(sha) {
        log(&cat(&[b"not a full commit sha: ", sha]));
        return 2;
    }
    let got = map_commit(file);
    if got != sha.as_slice() {
        log(&cat(&[
            b"refusing to save: ",
            file,
            b" describes '",
            &got,
            b"', not ",
            sha,
        ]));
        return 1;
    }
    let r = capture(
        0,
        Command::new("git")
            .arg("hash-object")
            .arg("-w")
            .arg(os(file)),
    );
    let blob = subst(r.stdout);

    let refspec = cat(&[b"+", &blob, b":", PREFIX, b"/", sha]);
    let r = capture(
        0,
        auth_git_cmd()
            .arg("push")
            .arg("--quiet")
            .arg(os(remote))
            .arg(os(&refspec)),
    );
    if !r.ok() {
        log(&cat(&[b"push failed: ", &r.stderr]));
        return 1;
    }
    let short = &sha[..std::cmp::min(12, sha.len())];
    log(&cat(&[
        b"saved the map for ",
        short,
        b" at ",
        PREFIX,
        b"/",
        short,
        b"...",
    ]));
    0
}

fn cmd_fetch(args: &[Vec<u8>], remote: &[u8], max_behind: usize) -> i32 {
    if args.len() < 2 {
        log(b"usage: fetch <out.json> <base>");
        return 2;
    }
    let out_path = &args[1];
    let base = if args.len() > 2 {
        &args[2]
    } else {
        b"" as &[u8]
    };
    let mut found = Vec::new();

    if !base.is_empty() {
        let verify = capture(
            0,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(os(&cat(&[base, b"^{commit}"]))),
        );
        if verify.ok() {
            let base_sha = subst(verify.stdout);
            let r = capture(
                0,
                auth_git_cmd()
                    .arg("ls-remote")
                    .arg(os(remote))
                    .arg(os(&cat(&[PREFIX, b"/*"]))),
            );
            let remote_refs_raw = if r.ok() { r.stdout } else { Vec::new() };
            let remote_refs: Vec<Vec<u8>> = shell_compat::lines(&remote_refs_raw)
                .into_iter()
                .filter_map(|line| {
                    let parts: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
                    if parts.len() == 2 {
                        Some(parts[1].to_vec())
                    } else {
                        None
                    }
                })
                .collect();

            let rev_list = capture(
                0,
                Command::new("git")
                    .arg("rev-list")
                    .arg("--first-parent")
                    .arg("-n")
                    .arg(&format!("{}", max_behind + 1))
                    .arg(os(&base_sha)),
            );
            let commits = shell_compat::lines(&subst(rev_list.stdout));
            let mut behind: usize = 0;
            for c in &commits {
                if c.is_empty() {
                    continue;
                }
                let expected_ref = cat(&[PREFIX, b"/", c]);
                if remote_refs.iter().any(|r| r == &expected_ref) {
                    let tmp = match shell_compat::mktemp_file(b"rdeps.XXXXXXXXXX") {
                        Ok(p) => p,
                        Err(_) => {
                            behind += 1;
                            continue;
                        }
                    };
                    let fetch_r = capture(
                        0,
                        auth_git_cmd()
                            .arg("fetch")
                            .arg("--quiet")
                            .arg("--no-tags")
                            .arg(os(remote))
                            .arg(os(&expected_ref)),
                    );
                    if fetch_r.ok() {
                        let cat_r = capture(
                            0,
                            Command::new("git")
                                .arg("cat-file")
                                .arg("blob")
                                .arg("FETCH_HEAD"),
                        );
                        if cat_r.ok() {
                            let _ = shell_compat::write_file(&tmp, &cat_r.stdout, 0o644);
                            let mc = map_commit(&tmp);
                            if mc == c.as_slice() {
                                let _ = std::fs::rename(
                                    shell_compat::path(&tmp),
                                    shell_compat::path(out_path),
                                );
                                found = c.clone();
                                let short = &c[..std::cmp::min(12, c.len())];
                                log(&cat(&[
                                    b"found the map for ",
                                    short,
                                    b" (",
                                    format!("{}", behind).as_bytes(),
                                    b" commit(s) behind the diff base)",
                                ]));
                                break;
                            }
                        }
                    }
                    let _ = std::fs::remove_file(shell_compat::path(&tmp));
                    let short = &c[..std::cmp::min(12, c.len())];
                    log(&cat(&[
                        b"the map at ",
                        PREFIX,
                        b"/",
                        short,
                        b"... is unreadable or mislabelled -- skipped",
                    ]));
                }
                behind += 1;
            }
        }
    }

    if found.is_empty() {
        log(&cat(&[
            b"no map under ",
            PREFIX,
            b"/ for the diff base or its last ",
            format!("{}", max_behind).as_bytes(),
            b" ancestors",
        ]));
    }
    let output_line = cat(&[b"commit=", &found]);
    out(&cat(&[&output_line, b"\n"]));
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&cat(&[&output_line, b"\n"]))
                });
        }
    }
    0
}

fn cmd_prune(remote: &[u8], keep: usize) -> i32 {
    let head_r = capture(0, Command::new("git").arg("rev-parse").arg("HEAD"));
    let head_sha = subst(head_r.stdout);

    let _ = capture(
        0,
        auth_git_cmd()
            .arg("fetch")
            .arg("--quiet")
            .arg("--no-tags")
            .arg(&format!("--depth={}", keep))
            .arg(os(remote))
            .arg(os(&head_sha)),
    );

    let rev_r = capture(
        0,
        Command::new("git")
            .arg("rev-list")
            .arg("--first-parent")
            .arg("-n")
            .arg(&format!("{}", keep))
            .arg(os(&head_sha)),
    );
    let keep_set: Vec<Vec<u8>> = shell_compat::lines(&subst(rev_r.stdout))
        .into_iter()
        .filter(|l| !l.is_empty())
        .collect();

    if keep_set.len() < 2 {
        log(b"not enough history to tell which maps are old -- pruning nothing");
        return 0;
    }

    let ls_r = capture(
        0,
        auth_git_cmd()
            .arg("ls-remote")
            .arg(os(remote))
            .arg(os(&cat(&[PREFIX, b"/*"]))),
    );
    let refs: Vec<Vec<u8>> = shell_compat::lines(&ls_r.stdout)
        .into_iter()
        .filter_map(|line| {
            let parts: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
            if parts.len() == 2 && !parts[1].is_empty() {
                Some(parts[1].to_vec())
            } else {
                None
            }
        })
        .collect();

    let prefix_slash = cat(&[PREFIX, b"/"]);
    let mut stale: Vec<Vec<u8>> = Vec::new();
    for r in &refs {
        if !r.starts_with(&prefix_slash) {
            continue;
        }
        let commit_part = &r[prefix_slash.len()..];
        if !keep_set.iter().any(|k| k == commit_part) {
            stale.push(r.clone());
        }
    }

    if stale.is_empty() {
        log(b"nothing to prune");
        return 0;
    }

    for chunk in stale.chunks(50) {
        let mut cmd = auth_git_cmd();
        cmd.arg("push")
            .arg("--quiet")
            .arg(os(remote))
            .arg("--delete");
        for r in chunk {
            cmd.arg(os(r));
        }
        let _ = capture(0, &mut cmd);
    }
    log(&cat(&[
        b"pruned ",
        format!("{}", stale.len()).as_bytes(),
        b" map(s) older than the last ",
        format!("{}", keep).as_bytes(),
        b" commits",
    ]));
    0
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let remote = env_or("RDEPS_MAP_REMOTE", b"origin");
    let max_behind: usize = std::str::from_utf8(&env_or("RDEPS_MAP_MAX_BEHIND", b"9"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(9);
    let keep: usize = std::str::from_utf8(&env_or("RDEPS_MAP_KEEP", b"300"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(300);

    let cmd = if !args.is_empty() {
        args[0].as_slice()
    } else {
        b""
    };
    match cmd {
        b"save" => cmd_save(args, &remote),
        b"fetch" => cmd_fetch(args, &remote, max_behind),
        b"prune" => cmd_prune(&remote, keep),
        _ => {
            log(b"usage: rdeps-map-ref.sh save <map.json> <sha> | fetch <out.json> <base> | prune");
            2
        }
    }
}
