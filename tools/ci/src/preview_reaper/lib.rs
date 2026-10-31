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

//! preview-reaper — purge closed, merged, and TTL-expired ephemeral
//! preview environments across Cloud Run, Kubernetes, and Neon branches.

use shell_compat::{capture, cat, env, env_or, env_or_empty, err, out, status, subst, which};
use std::collections::HashMap;
use std::process::Command;

fn log(msg: &[u8]) {
    err(&cat(&[b"preview-reaper: ", msg, b"\n"]));
}

fn is_protected(name: &[u8]) -> bool {
    matches!(
        name,
        b"main"
            | b"master"
            | b"production"
            | b"prod"
            | b"nonproduction"
            | b"nonprod"
            | b"staging"
            | b"development"
            | b"dev"
            | b"default"
            | b"kube-system"
            | b"kube-public"
            | b"kube-node-lease"
            | b"argocd"
            | b"ingress-nginx"
    )
}

fn iso_to_epoch(iso: &[u8]) -> i64 {
    let s = match std::str::from_utf8(iso) {
        Ok(s) => s.trim(),
        Err(_) => return 0,
    };
    if s.is_empty() {
        return 0;
    }
    // Parse ISO 8601: 2026-01-02T15:04:05Z or 2026-01-02T15:04:05+00:00
    let s = s.replace('Z', "+00:00");
    // Split at T
    let (date_part, time_tz) = match s.find('T') {
        Some(i) => (&s[..i], &s[i + 1..]),
        None => return 0,
    };
    let date_parts: Vec<&str> = date_part.split('-').collect();
    if date_parts.len() != 3 {
        return 0;
    }
    let year: i64 = date_parts[0].parse().unwrap_or(0);
    let month: i64 = date_parts[1].parse().unwrap_or(0);
    let day: i64 = date_parts[2].parse().unwrap_or(0);

    // Split time from tz offset
    let (time_str, tz_offset_secs) = if let Some(plus) = time_tz[1..].find('+') {
        let p = plus + 1;
        let time_s = &time_tz[..p];
        let tz_s = &time_tz[p + 1..];
        let tz_parts: Vec<&str> = tz_s.split(':').collect();
        let h: i64 = tz_parts.first().and_then(|s| s.parse().ok()).unwrap_or(0);
        let m: i64 = tz_parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
        (time_s, h * 3600 + m * 60)
    } else if let Some(minus) = time_tz[1..].find('-') {
        let p = minus + 1;
        let time_s = &time_tz[..p];
        let tz_s = &time_tz[p + 1..];
        let tz_parts: Vec<&str> = tz_s.split(':').collect();
        let h: i64 = tz_parts.first().and_then(|s| s.parse().ok()).unwrap_or(0);
        let m: i64 = tz_parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
        (time_s, -(h * 3600 + m * 60))
    } else {
        (time_tz, 0i64)
    };

    let time_parts: Vec<&str> = time_str.split(':').collect();
    if time_parts.len() < 2 {
        return 0;
    }
    let hour: i64 = time_parts[0].parse().unwrap_or(0);
    let minute: i64 = time_parts[1].parse().unwrap_or(0);
    let second: i64 = time_parts
        .get(2)
        .and_then(|s| s.split('.').next())
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    // days since epoch
    let mut y = year;
    let mut m = month;
    if m <= 2 {
        y -= 1;
        m += 12;
    }
    let days = 365 * y + y / 4 - y / 100 + y / 400 + (153 * (m - 3) + 2) / 5 + day - 719469;
    days * 86400 + hour * 3600 + minute * 60 + second - tz_offset_secs
}

fn extract_pr_num_suffix(name: &[u8]) -> Option<Vec<u8>> {
    // Match: *-pr-<digits> at end
    let s = std::str::from_utf8(name).ok()?;
    let idx = s.rfind("-pr-")?;
    let num_part = &s[idx + 4..];
    if !num_part.is_empty() && num_part.chars().all(|c| c.is_ascii_digit()) {
        Some(num_part.as_bytes().to_vec())
    } else {
        None
    }
}

fn extract_pr_num_prefix(name: &[u8]) -> Option<Vec<u8>> {
    // Match: pr-<digits> at start
    let s = std::str::from_utf8(name).ok()?;
    let rest = s.strip_prefix("pr-")?;
    if !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()) {
        Some(rest.as_bytes().to_vec())
    } else {
        None
    }
}

fn extract_pr_num_anywhere(name: &[u8]) -> Option<Vec<u8>> {
    // Match `pr-([0-9]+)` anywhere, leftmost occurrence that is followed by a
    // digit (an earlier "pr-" with no digits after it does not stop the search).
    let s = std::str::from_utf8(name).ok()?;
    let mut from = 0;
    while let Some(i) = s[from..].find("pr-") {
        let rest = &s[from + i + 3..];
        let num: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
        if !num.is_empty() {
            return Some(num.into_bytes());
        }
        from += i + 3;
    }
    None
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let repo = env_or("REPO", b"VitruvianSoftware/vitruvian-core");
    let gh = env_or("GH", b"gh");
    let gcloud = env_or("GCLOUD", b"gcloud");
    let kubectl = env_or("KUBECTL", b"kubectl");
    let curl_bin = env_or("CURL", b"curl");
    let gcp_project = env_or_empty("GCP_PROJECT");
    let gcp_region = env_or("GCP_REGION", b"us-central1");
    let neon_api_key = env_or_empty("NEON_API_KEY");
    let neon_project_id = env_or_empty("NEON_PROJECT_ID");
    let ttl_hours: i64 = std::str::from_utf8(&env_or("PREVIEW_TTL_HOURS", b"24"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(24);
    let dry_run = env_or_empty("DRY_RUN");
    let now_epoch: i64 = match env("NOW_EPOCH") {
        Some(v) if !v.is_empty() => std::str::from_utf8(&v)
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or_else(|| {
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs() as i64)
                    .unwrap_or(0)
            }),
        _ => std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0),
    };
    let only_pr = if !args.is_empty() {
        args[0].clone()
    } else {
        Vec::new()
    };

    if !only_pr.is_empty() {
        if !only_pr.iter().all(|c| c.is_ascii_digit()) {
            log(&cat(&[
                b"ERROR: PR number must be positive integer, got '",
                &only_pr,
                b"'",
            ]));
            return 2;
        }
    }

    let mut pr_cache: HashMap<Vec<u8>, Vec<u8>> = HashMap::new();

    let should_reap =
        |num: &[u8], resource_epoch: i64, cache: &mut HashMap<Vec<u8>, Vec<u8>>| -> bool {
            if !only_pr.is_empty() && num == only_pr.as_slice() {
                return true;
            }
            let pr_json = if let Some(v) = cache.get(num) {
                v.clone()
            } else {
                let r = capture(
                    110,
                    Command::new(shell_compat::os(&gh))
                        .arg("pr")
                        .arg("view")
                        .arg(shell_compat::os(num))
                        .arg("--repo")
                        .arg(shell_compat::os(&repo))
                        .arg("--json")
                        .arg("state,createdAt,updatedAt"),
                );
                let v = if r.ok() {
                    subst(r.stdout)
                } else {
                    b"{\"state\":\"UNKNOWN\",\"createdAt\":\"\"}".to_vec()
                };
                cache.insert(num.to_vec(), v.clone());
                v
            };

            // Simple JSON field extraction
            let state = json_string_field(&pr_json, b"state");
            let created_at = json_string_field(&pr_json, b"createdAt");

            match state.as_slice() {
                b"MERGED" | b"CLOSED" => {
                    log(&cat(&[
                        b"PR #",
                        num,
                        b" is ",
                        &state,
                        b" \xe2\x80\x94 marked for reap",
                    ]));
                    true
                }
                b"OPEN" => {
                    let pr_epoch = iso_to_epoch(&created_at);
                    let ref_epoch = if resource_epoch > 0 {
                        resource_epoch
                    } else {
                        pr_epoch
                    };
                    if ref_epoch > 0 {
                        let age_secs = now_epoch - ref_epoch;
                        let ttl_secs = ttl_hours * 3600;
                        if age_secs > ttl_secs {
                            log(&cat(&[
                                b"PR #",
                                num,
                                b" is OPEN but age (",
                                (age_secs / 3600).to_string().as_bytes(),
                                b"h) exceeds TTL (",
                                ttl_hours.to_string().as_bytes(),
                                b"h) \xe2\x80\x94 marked for reap",
                            ]));
                            true
                        } else {
                            log(&cat(&[
                                b"PR #",
                                num,
                                b" is OPEN and active (",
                                (age_secs / 3600).to_string().as_bytes(),
                                b"h / ",
                                ttl_hours.to_string().as_bytes(),
                                b"h) \xe2\x80\x94 preserving",
                            ]));
                            false
                        }
                    } else {
                        log(&cat(&[
                            b"PR #",
                            num,
                            b" is OPEN (unknown age) \xe2\x80\x94 preserving",
                        ]));
                        false
                    }
                }
                _ => {
                    log(&cat(&[
                        b"PR #",
                        num,
                        b" state is ",
                        &state,
                        b" (unverifiable) \xe2\x80\x94 preserving as fail-safe",
                    ]));
                    false
                }
            }
        };

    let mut reaped_cloudrun: u64 = 0;
    let mut reaped_k8s: u64 = 0;
    let mut reaped_neon: u64 = 0;

    // 1. Cloud Run
    if which(&gcloud).is_some() && !gcp_project.is_empty() {
        log(&cat(&[
            b"Scanning Cloud Run preview services in project ",
            &gcp_project,
            b"...",
        ]));
        let r = capture(
            185,
            Command::new(shell_compat::os(&gcloud))
                .arg("run")
                .arg("services")
                .arg("list")
                .arg(shell_compat::os(&cat(&[b"--project=", &gcp_project])))
                .arg("--format=value(metadata.name,metadata.creationTimestamp)"),
        );
        let services = subst(r.stdout);
        for line in shell_compat::lines(&services) {
            if line.is_empty() {
                continue;
            }
            let fields: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
            let svc_name = fields[0];
            let creation_ts = if fields.len() > 1 { fields[1] } else { b"" };
            if is_protected(svc_name) {
                continue;
            }
            if let Some(pr_num) = extract_pr_num_suffix(svc_name) {
                if !only_pr.is_empty() && pr_num != only_pr {
                    continue;
                }
                let svc_epoch = iso_to_epoch(creation_ts);
                if should_reap(&pr_num, svc_epoch, &mut pr_cache) {
                    if !dry_run.is_empty() {
                        log(&cat(&[
                            b"[DRY_RUN] Would delete Cloud Run service '",
                            svc_name,
                            b"' (PR #",
                            &pr_num,
                            b")",
                        ]));
                        reaped_cloudrun += 1;
                    } else {
                        log(&cat(&[
                            b"Deleting Cloud Run service '",
                            svc_name,
                            b"' (PR #",
                            &pr_num,
                            b")...",
                        ]));
                        let rc = status(
                            211,
                            Command::new(shell_compat::os(&gcloud))
                                .arg("run")
                                .arg("services")
                                .arg("delete")
                                .arg(shell_compat::os(svc_name))
                                .arg(shell_compat::os(&cat(&[b"--project=", &gcp_project])))
                                .arg(shell_compat::os(&cat(&[b"--region=", &gcp_region])))
                                .arg("--quiet")
                                .stdout(std::process::Stdio::null())
                                .stderr(std::process::Stdio::null()),
                            true,
                        );
                        if rc == 0 {
                            reaped_cloudrun += 1;
                        } else {
                            log(&cat(&[
                                b"WARNING: Failed to delete Cloud Run service '",
                                svc_name,
                                b"'",
                            ]));
                        }
                    }
                }
            }
        }
    } else {
        log(b"gcloud not found or GCP_PROJECT unset \xe2\x80\x94 skipping Cloud Run reap");
    }

    // 2. Kubernetes
    if which(&kubectl).is_some() {
        log(b"Scanning Kubernetes preview namespaces...");
        let r = capture(
            233,
            Command::new(shell_compat::os(&kubectl))
                .arg("get")
                .arg("namespaces")
                .arg("-o")
                .arg("jsonpath={range .items[*]}{.metadata.name}{\"\\t\"}{.metadata.creationTimestamp}{\"\\n\"}{end}"),
        );
        let namespaces = subst(r.stdout);
        for line in shell_compat::lines(&namespaces) {
            if line.is_empty() {
                continue;
            }
            let fields: Vec<&[u8]> = line.splitn(2, |&c| c == b'\t').collect();
            let ns = fields[0];
            let creation_ts = if fields.len() > 1 { fields[1] } else { b"" };
            if is_protected(ns) {
                continue;
            }
            if let Some(pr_num) = extract_pr_num_prefix(ns) {
                if !only_pr.is_empty() && pr_num != only_pr {
                    continue;
                }
                let ns_epoch = iso_to_epoch(creation_ts);
                if should_reap(&pr_num, ns_epoch, &mut pr_cache) {
                    if !dry_run.is_empty() {
                        log(&cat(&[
                            b"[DRY_RUN] Would delete K8s namespace '",
                            ns,
                            b"' (PR #",
                            &pr_num,
                            b")",
                        ]));
                        reaped_k8s += 1;
                    } else {
                        log(&cat(&[
                            b"Deleting K8s namespace '",
                            ns,
                            b"' (PR #",
                            &pr_num,
                            b")...",
                        ]));
                        let rc = status(
                            259,
                            Command::new(shell_compat::os(&kubectl))
                                .arg("delete")
                                .arg("namespace")
                                .arg(shell_compat::os(ns))
                                .arg("--timeout=60s")
                                .arg("--ignore-not-found")
                                .stdout(std::process::Stdio::null())
                                .stderr(std::process::Stdio::null()),
                            true,
                        );
                        if rc == 0 {
                            reaped_k8s += 1;
                        } else {
                            log(&cat(&[
                                b"WARNING: Failed to delete K8s namespace '",
                                ns,
                                b"'",
                            ]));
                        }
                    }
                }
            }
        }
    } else {
        log(b"kubectl not found \xe2\x80\x94 skipping K8s namespace reap");
    }

    // 3. Neon
    if which(&curl_bin).is_none() {
        log(&cat(&[
            b"ERROR: curl binary '",
            &curl_bin,
            b"' not found \xe2\x80\x94 skipping Neon branch reap",
        ]));
        if shell_compat::env_set_nonempty("GITHUB_ACTIONS") {
            err(&cat(&[
                b"::error title=Neon Reaper Error::curl binary '",
                &curl_bin,
                b"' not found\n",
            ]));
        }
        // The original script aborted here (`set -e`): no summary and none of
        // the four output lines, alongside a failed step.
        return 1;
    } else if neon_api_key.is_empty() || neon_project_id.is_empty() {
        log(b"WARNING: Neon credentials missing (NEON_API_KEY and/or NEON_PROJECT_ID empty) \xe2\x80\x94 skipping Neon branch reap");
        if shell_compat::env_set_nonempty("GITHUB_ACTIONS") {
            err(b"::warning title=Neon Branch Reap Skipped::NEON_API_KEY or NEON_PROJECT_ID is empty \xe2\x80\x94 skipping Neon branch reap\n");
        }
    } else {
        log(&cat(&[
            b"Scanning Neon Postgres branches for project ",
            &neon_project_id,
            b"...",
        ]));
        let r = capture(
            292,
            Command::new(shell_compat::os(&curl_bin))
                .arg("-s")
                .arg("-H")
                .arg(shell_compat::os(&cat(&[
                    b"Authorization: Bearer ",
                    &neon_api_key,
                ])))
                .arg(shell_compat::os(&cat(&[
                    b"https://console.neon.tech/api/v2/projects/",
                    &neon_project_id,
                    b"/branches",
                ]))),
        );
        let response = subst(r.stdout);
        // Parse branches from JSON using simple extraction
        let branches = parse_neon_branches(&response);
        for (branch_id, branch_name, created_at, is_primary) in &branches {
            if branch_id.is_empty() {
                continue;
            }
            if *is_primary || is_protected(branch_name) {
                continue;
            }
            if let Some(pr_num) = extract_pr_num_anywhere(branch_name) {
                if !only_pr.is_empty() && pr_num != only_pr {
                    continue;
                }
                let branch_epoch = iso_to_epoch(created_at);
                if should_reap(&pr_num, branch_epoch, &mut pr_cache) {
                    if !dry_run.is_empty() {
                        log(&cat(&[
                            b"[DRY_RUN] Would delete Neon branch '",
                            branch_name,
                            b"' (",
                            branch_id,
                            b") (PR #",
                            &pr_num,
                            b")",
                        ]));
                        reaped_neon += 1;
                    } else {
                        log(&cat(&[
                            b"Deleting Neon branch '",
                            branch_name,
                            b"' (",
                            branch_id,
                            b")...",
                        ]));
                        let rc = status(
                            334,
                            Command::new(shell_compat::os(&curl_bin))
                                .arg("-s")
                                .arg("-X")
                                .arg("DELETE")
                                .arg("-H")
                                .arg(shell_compat::os(&cat(&[
                                    b"Authorization: Bearer ",
                                    &neon_api_key,
                                ])))
                                .arg(shell_compat::os(&cat(&[
                                    b"https://console.neon.tech/api/v2/projects/",
                                    &neon_project_id,
                                    b"/branches/",
                                    branch_id,
                                ])))
                                .stdout(std::process::Stdio::null())
                                .stderr(std::process::Stdio::null()),
                            true,
                        );
                        if rc == 0 {
                            reaped_neon += 1;
                        } else {
                            log(&cat(&[
                                b"WARNING: Failed to delete Neon branch '",
                                branch_name,
                                b"'",
                            ]));
                        }
                    }
                }
            }
        }
    }

    let total = reaped_cloudrun + reaped_k8s + reaped_neon;
    log(&cat(&[
        b"Summary: reaped ",
        reaped_cloudrun.to_string().as_bytes(),
        b" Cloud Run services, ",
        reaped_k8s.to_string().as_bytes(),
        b" K8s namespaces, ",
        reaped_neon.to_string().as_bytes(),
        b" Neon branches (total ",
        total.to_string().as_bytes(),
        b")",
    ]));

    out(&cat(&[
        b"reaped_cloudrun=",
        reaped_cloudrun.to_string().as_bytes(),
        b"\n",
    ]));
    out(&cat(&[
        b"reaped_k8s=",
        reaped_k8s.to_string().as_bytes(),
        b"\n",
    ]));
    out(&cat(&[
        b"reaped_neon=",
        reaped_neon.to_string().as_bytes(),
        b"\n",
    ]));
    out(&cat(&[
        b"total_reaped=",
        total.to_string().as_bytes(),
        b"\n",
    ]));

    0
}

fn json_string_field(json: &[u8], field: &[u8]) -> Vec<u8> {
    let needle = cat(&[b"\"", field, b"\":"]);
    if let Some(pos) = json
        .windows(needle.len())
        .position(|w| w == needle.as_slice())
    {
        let rest = &json[pos + needle.len()..];
        let rest = rest
            .iter()
            .position(|&c| c == b'"')
            .map(|i| &rest[i + 1..])
            .unwrap_or(b"");
        if let Some(end) = rest.iter().position(|&c| c == b'"') {
            return rest[..end].to_vec();
        }
    }
    Vec::new()
}

fn parse_neon_branches(json: &[u8]) -> Vec<(Vec<u8>, Vec<u8>, Vec<u8>, bool)> {
    // Use python3 for JSON parsing (same as the script)
    let r = capture(
        295,
        Command::new("python3")
            .arg("-c")
            .arg("import sys, json\ntry:\n    data = json.loads(sys.argv[1])\n    branches = data.get('branches', [])\n    for b in branches:\n        b_id = b.get('id', '')\n        b_name = b.get('name', '')\n        b_created = b.get('created_at', '')\n        b_prim = b.get('primary', False)\n        print(f'{b_id}\\t{b_name}\\t{b_created}\\t{b_prim}')\nexcept Exception:\n    pass")
            .arg(shell_compat::os(json)),
    );
    let output = subst(r.stdout);
    let mut result = Vec::new();
    for line in shell_compat::lines(&output) {
        if line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(4, |&c| c == b'\t').collect();
        if fields.len() < 4 {
            continue;
        }
        let is_primary = fields[3] == b"True" || fields[3] == b"true";
        result.push((
            fields[0].to_vec(),
            fields[1].to_vec(),
            fields[2].to_vec(),
            is_primary,
        ));
    }
    result
}
