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

//! //tools/ci:resolve_unit_bases — per-unit durable diff bases for an app's delivery
//! lane (#1842).

use shell_compat::{capture, cat, env, env_or, env_or_empty, is_readable, out, subst};
use std::process::Command;

fn emit(json: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"resolve-unit-bases: unit_bases=",
        json,
        b" (",
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
                    f.write_all(&cat(&[b"unit_bases=", json, b"\n"]))
                });
        }
    }
    0
}

fn list_runs(
    gh: &[u8],
    repo: &[u8],
    wf: &[u8],
    branch: &[u8],
    limit: &[u8],
) -> Result<Vec<u8>, Vec<u8>> {
    let r = capture(
        126,
        Command::new(shell_compat::os(gh))
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
            .arg(shell_compat::os(limit))
            .arg("--json")
            .arg("databaseId,headSha")
            .arg("--jq")
            .arg(".[] | \"\\(.databaseId) \\(.headSha)\""),
    );
    if r.ok() {
        Ok(subst(r.stdout))
    } else {
        let mut msg = r.stdout;
        msg.extend_from_slice(&r.stderr);
        Err(subst(msg))
    }
}

struct JobSuccess {
    job: Vec<u8>,
    run_index: usize,
    sha: Vec<u8>,
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let gh = env_or("GH_BIN", b"gh");
    let repo = {
        let r = env_or_empty("REPO");
        if r.is_empty() {
            env_or_empty("GITHUB_REPOSITORY")
        } else {
            r
        }
    };
    let branch = env_or("BRANCH", b"main");
    let lookback = env_or("LOOKBACK", b"30");
    let workflow_file = match env("WORKFLOW_FILE") {
        Some(v) if !v.is_empty() => v,
        _ => {
            // `${WORKFLOW_FILE:?...}`: bash names the variable and exits 1.
            shell_compat::err(b"resolve-unit-bases: WORKFLOW_FILE: WORKFLOW_FILE must be set\n");
            return 1;
        }
    };
    let workflow_path = match env("WORKFLOW_PATH") {
        Some(v) if !v.is_empty() => v,
        _ => cat(&[b".github/workflows/", &workflow_file]),
    };

    if repo.is_empty() {
        return emit(b"{}", b"REPO/GITHUB_REPOSITORY unset");
    }
    if !is_readable(&workflow_path) {
        return emit(
            b"{}",
            &cat(&[b"workflow ", &workflow_path, b" not readable"]),
        );
    }

    // Parse units from workflow: affected_<unit>: outputs
    let wf_content = match std::fs::read(shell_compat::path(&workflow_path)) {
        Ok(c) => c,
        Err(_) => {
            return emit(
                b"{}",
                &cat(&[b"workflow ", &workflow_path, b" not readable"]),
            )
        }
    };
    let mut units: Vec<Vec<u8>> = Vec::new();
    for line in wf_content.split(|&c| c == b'\n') {
        let trimmed = line
            .iter()
            .position(|c| !c.is_ascii_whitespace())
            .map(|i| &line[i..])
            .unwrap_or(b"");
        if trimmed.starts_with(b"affected_") {
            if let Some(colon) = trimmed.iter().position(|&c| c == b':') {
                let name = &trimmed[9..colon]; // after "affected_"
                if !name.is_empty()
                    && name
                        .iter()
                        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'_')
                {
                    if !units.contains(&name.to_vec()) {
                        units.push(name.to_vec());
                    }
                }
            }
        }
    }
    units.sort();
    units.dedup();
    if units.is_empty() {
        return emit(
            b"{}",
            &cat(&[b"no affected_* outputs found in ", &workflow_path]),
        );
    }

    // Parse job conditions: job_id -> condition (the `if:` line)
    let mut conds: Vec<(Vec<u8>, Vec<u8>)> = Vec::new(); // (job_id, condition)
    {
        let mut in_jobs = false;
        let mut current_job = Vec::new();
        for line in wf_content.split(|&c| c == b'\n') {
            if line.starts_with(b"jobs:") {
                in_jobs = true;
                continue;
            }
            if !in_jobs {
                continue;
            }
            // Job definition, awk's /^  [a-z0-9][a-z0-9-]*:[[:space:]]*$/
            let lower_or_digit = |c: &u8| c.is_ascii_lowercase() || c.is_ascii_digit();
            if line.len() >= 3 && line[0] == b' ' && line[1] == b' ' && lower_or_digit(&line[2]) {
                let rest = &line[2..];
                if let Some(colon) = rest.iter().position(|&c| c == b':') {
                    let name = &rest[..colon];
                    if !name.is_empty() && name.iter().all(|c| lower_or_digit(c) || *c == b'-') {
                        let after = &rest[colon + 1..];
                        if after.iter().all(|c| c.is_ascii_whitespace()) {
                            current_job = name.to_vec();
                        }
                    }
                }
            }
            // if: line under a job: "    if: ..."
            if line.starts_with(b"    if: ") && !current_job.is_empty() {
                let cond = &line[8..];
                conds.push((current_job.clone(), cond.to_vec()));
            }
        }
    }
    if conds.is_empty() {
        return emit(
            b"{}",
            &cat(&[b"no job conditions parsed from ", &workflow_path]),
        );
    }

    // List runs
    let runs_raw = match list_runs(&gh, &repo, &workflow_file, &branch, &lookback) {
        Ok(r) => r,
        Err(e) => {
            return emit(
                b"{}",
                &cat(&[b"could not list runs for ", &workflow_file, b": ", &e]),
            );
        }
    };

    let lookback_n: usize = std::str::from_utf8(&lookback)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(30);

    let mut runs = runs_raw.clone();
    let have = shell_compat::lines(&runs_raw)
        .iter()
        .filter(|l| !l.is_empty())
        .count();
    let mut source_note = workflow_file.clone();

    if let Some(legacy) = env("LEGACY_WORKFLOW_FILE") {
        if !legacy.is_empty() && legacy != workflow_file && have < lookback_n {
            let remain = lookback_n - have;
            if let Ok(leg_runs) =
                list_runs(&gh, &repo, &legacy, &branch, remain.to_string().as_bytes())
            {
                if !leg_runs.is_empty() {
                    runs = cat(&[&runs, b"\n", &leg_runs]);
                    source_note = cat(&[&workflow_file, b", then ", &legacy]);
                }
            }
        }
    }

    let run_lines: Vec<Vec<u8>> = shell_compat::lines(&runs)
        .into_iter()
        .filter(|l| !l.is_empty())
        .collect();
    if run_lines.is_empty() {
        return emit(
            b"{}",
            &cat(&[b"no push runs of ", &workflow_file, b" to read"]),
        );
    }

    // Pass 1: per job, its newest success
    let mut jobsucc: Vec<JobSuccess> = Vec::new();
    for (idx, run_line) in run_lines.iter().enumerate() {
        // `read -r run_id head_sha`: IFS-whitespace fields, the sha is the
        // rest; a line with no sha still counts (its jobs carry an empty sha).
        let fields = shell_compat::read_fields(run_line, b" \t\n", 2);
        let run_id: &[u8] = &fields[0];
        let head_sha: &[u8] = &fields[1];
        if run_id.is_empty() {
            continue;
        }

        let r = capture(
            162,
            Command::new(shell_compat::os(&gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"/repos/",
                    &repo,
                    b"/actions/runs/",
                    run_id,
                    b"/jobs",
                ])))
                .arg("--paginate")
                .arg("--jq")
                .arg(".jobs[] | select(.conclusion==\"success\") | .name"),
        );
        if !r.ok() {
            continue;
        }
        let jobs = subst(r.stdout);
        for job_line in shell_compat::lines(&jobs) {
            if job_line.is_empty() {
                continue;
            }
            // Strip " / <inner>" suffix from reusable-workflow jobs
            let job = if let Some(sep) = job_line.windows(3).position(|w| w == b" / ") {
                job_line[..sep].to_vec()
            } else {
                job_line
            };
            // First-writer-wins: skip if already have this job
            if jobsucc.iter().any(|js| js.job == job) {
                continue;
            }
            jobsucc.push(JobSuccess {
                job,
                run_index: idx,
                sha: head_sha.to_vec(),
            });
        }
    }

    // Pass 2: per unit, the oldest (largest run_index) of its rungs' newest successes
    let mut found: Vec<(Vec<u8>, Vec<u8>)> = Vec::new(); // (unit-name-with-dashes, sha)
    for uu in &units {
        let u: Vec<u8> = uu
            .iter()
            .map(|&c| if c == b'_' { b'-' } else { c })
            .collect();
        let mut worst_idx: Option<usize> = None;
        let mut worst_sha = Vec::new();
        let mut missing = false;
        let mut any = false;

        for (jid, cond) in &conds {
            // Check if condition references affected_<uu> with boundary
            let pat = cat(&[b"affected_", uu]);
            let cond_has = has_bounded_match(cond, &pat);
            if !cond_has {
                continue;
            }
            any = true;
            // Look up job in jobsucc
            let rec = jobsucc.iter().find(|js| js.job == *jid);
            match rec {
                None => {
                    missing = true;
                    break;
                }
                Some(js) => {
                    if worst_idx.map_or(true, |wi| js.run_index > wi) {
                        worst_idx = Some(js.run_index);
                        worst_sha = js.sha.clone();
                    }
                }
            }
        }
        if any && !missing && !worst_sha.is_empty() {
            found.push((u, worst_sha));
        }
    }

    // Build JSON
    let mut json = b"{".to_vec();
    let mut sep = false;
    for uu in &units {
        let u: Vec<u8> = uu
            .iter()
            .map(|&c| if c == b'_' { b'-' } else { c })
            .collect();
        if let Some((_, sha)) = found.iter().find(|(name, _)| *name == u) {
            if sep {
                json.push(b',');
            }
            json.push(b'"');
            json.extend_from_slice(&u);
            json.extend_from_slice(b"\":\"");
            json.extend_from_slice(sha);
            json.push(b'"');
            sep = true;
        }
    }
    json.push(b'}');

    emit(
        &json,
        &cat(&[
            b"per-unit bases from the last ",
            &lookback,
            b" push runs of ",
            &source_note,
        ]),
    )
}

fn has_bounded_match(text: &[u8], pattern: &[u8]) -> bool {
    let mut start = 0;
    while start + pattern.len() <= text.len() {
        if let Some(pos) = text[start..]
            .windows(pattern.len())
            .position(|w| w == pattern)
        {
            let abs = start + pos;
            let after = abs + pattern.len();
            let ok = after >= text.len()
                || !text[after].is_ascii_lowercase()
                    && !text[after].is_ascii_digit()
                    && text[after] != b'_';
            if ok {
                return true;
            }
            start = abs + 1;
        } else {
            break;
        }
    }
    false
}
