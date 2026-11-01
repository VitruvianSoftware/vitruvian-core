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

use shell_compat::{
    capture, cat, env, env_or, env_or_empty, err, out, status, status_with_input, subst, which, Ran,
};
use std::collections::HashMap;
use std::io::Write;
use std::process::{Command, Stdio};

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

/// Strict ISO 8601 parse: `YYYY-MM-DD[T ]HH:MM[:SS[.frac]][Z|+HH[:MM]|-HH[:MM]]`.
/// Anything else, and any out-of-range field, is `None`: a timestamp that cannot
/// be read must never be turned into a plausible old date.
fn parse_iso(iso: &[u8]) -> Option<i64> {
    let s = std::str::from_utf8(iso).ok()?.trim();
    let b = s.as_bytes();
    let num = |r: std::ops::Range<usize>| -> Option<i64> {
        let part = b.get(r)?;
        if part.is_empty() || !part.iter().all(|c| c.is_ascii_digit()) {
            return None;
        }
        std::str::from_utf8(part).ok()?.parse().ok()
    };
    if b.len() < 16
        || b[4] != b'-'
        || b[7] != b'-'
        || !(b[10] == b'T' || b[10] == b' ')
        || b[13] != b':'
    {
        return None;
    }
    let (year, month, day) = (num(0..4)?, num(5..7)?, num(8..10)?);
    let (hour, minute) = (num(11..13)?, num(14..16)?);
    let mut i = 16;
    let mut second = 0;
    if b.get(i) == Some(&b':') {
        second = num(i + 1..i + 3)?;
        i += 3;
        if b.get(i) == Some(&b'.') {
            let start = i + 1;
            let mut j = start;
            while b.get(j).is_some_and(|c| c.is_ascii_digit()) {
                j += 1;
            }
            if j == start {
                return None;
            }
            i = j;
        }
    }
    let tz = match b.get(i) {
        None => 0,
        Some(b'Z') if i + 1 == b.len() => 0,
        Some(&sign) if sign == b'+' || sign == b'-' => {
            let h = num(i + 1..i + 3)?;
            let rest = &b[i + 3..];
            let m = match rest {
                [] => 0,
                [b':', ..] if rest.len() == 3 => num(i + 4..i + 6)?,
                [_, _] => num(i + 3..i + 5)?,
                _ => return None,
            };
            if h > 23 || m > 59 {
                return None;
            }
            let off = h * 3600 + m * 60;
            if sign == b'+' {
                off
            } else {
                -off
            }
        }
        _ => return None,
    };
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    let dim = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => return None,
    };
    if year < 1970 || day < 1 || day > dim || hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    let (mut y, mut m) = (year, month);
    if m <= 2 {
        y -= 1;
        m += 12;
    }
    let days = 365 * y + y / 4 - y / 100 + y / 400 + (153 * (m - 3) + 2) / 5 + day - 719469;
    Some(days * 86400 + hour * 3600 + minute * 60 + second - tz)
}

/// A PR's own timestamp: unreadable means "age unknown", and the caller preserves.
fn iso_to_epoch(iso: &[u8]) -> i64 {
    parse_iso(iso).unwrap_or(0)
}

/// A resource's creation timestamp. Absent is fine (the PR's age is used);
/// present but unreadable is `Err`, and the resource is skipped, never reaped.
fn resource_epoch(kind: &str, name: &[u8], ts: &[u8]) -> Result<i64, ()> {
    if std::str::from_utf8(ts)
        .map(|t| t.trim().is_empty())
        .unwrap_or(false)
    {
        return Ok(0);
    }
    match parse_iso(ts) {
        Some(v) => Ok(v),
        None => {
            log(&cat(&[
                b"WARNING: ",
                kind.as_bytes(),
                b" '",
                name,
                b"' has an unreadable creation timestamp '",
                ts,
                b"' \xe2\x80\x94 skipping it (never reaped on an unreadable age)",
            ]));
            Err(())
        }
    }
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
    // Trimmed once, here: curl is sent this key and the redaction looks for
    // this key, so an API echoing it back is hidden even when the secret was
    // written with a trailing newline (`echo`).
    let neon_api_key = trim_ascii_whitespace(&env_or_empty("NEON_API_KEY")).to_vec();
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
    // A provider whose resources could not be listed: reported, and the run
    // fails, so an outage or a lost credential is never read as "nothing to
    // reap" (which is a green run that reaps nothing, indefinitely).
    let mut list_failed = false;

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
        let services = if r.ok() {
            subst(r.stdout)
        } else {
            // Not even what it printed before failing is acted on.
            listing_failed(
                "Preview Reaper Error",
                "Cloud Run services",
                "gcloud",
                &r,
                b"",
            );
            list_failed = true;
            Vec::new()
        };
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
                let svc_epoch = match resource_epoch("Cloud Run service", svc_name, creation_ts) {
                    Ok(v) => v,
                    Err(()) => continue,
                };
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

    // 2. Kubernetes. kubectl with no current context (a hosted runner ships
    // kubectl but no kubeconfig) is "not configured" and skipped, as Cloud
    // Run is without a project; a configured cluster that cannot be listed
    // fails the run.
    let kube_configured = which(&kubectl).is_some()
        && status(
            232,
            Command::new(shell_compat::os(&kubectl))
                .arg("config")
                .arg("current-context")
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        ) == 0;
    if kube_configured {
        log(b"Scanning Kubernetes preview namespaces...");
        let r = capture(
            233,
            Command::new(shell_compat::os(&kubectl))
                .arg("get")
                .arg("namespaces")
                .arg("-o")
                .arg("jsonpath={range .items[*]}{.metadata.name}{\"\\t\"}{.metadata.creationTimestamp}{\"\\n\"}{end}"),
        );
        let namespaces = if r.ok() {
            subst(r.stdout)
        } else {
            listing_failed("Preview Reaper Error", "K8s namespaces", "kubectl", &r, b"");
            list_failed = true;
            Vec::new()
        };
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
                let ns_epoch = match resource_epoch("K8s namespace", ns, creation_ts) {
                    Ok(v) => v,
                    Err(()) => continue,
                };
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
        log(
            b"kubectl not found or has no current context \xe2\x80\x94 skipping K8s namespace reap",
        );
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
    } else if neon_auth_config(&neon_api_key).is_none() {
        log(b"ERROR: NEON_API_KEY holds a control character (a line break?) \xe2\x80\x94 refusing to send it; no Neon branch was reaped");
        if shell_compat::env_set_nonempty("GITHUB_ACTIONS") {
            err(b"::error title=Neon Reaper Error::NEON_API_KEY holds a control character\n");
        }
        list_failed = true;
    } else {
        // The key reaches curl on its stdin (`--config -`), never on its
        // command line, which every local user can read (`ps`, /proc).
        let auth = neon_auth_config(&neon_api_key).unwrap_or_default();
        log(&cat(&[
            b"Scanning Neon Postgres branches for project ",
            &neon_project_id,
            b"...",
        ]));
        // -sS: quiet, but say why if curl itself fails. --fail-with-body:
        // an HTTP error status (a bad key, an outage) is a failure, not an
        // error body that parses as an empty branch list.
        let r = capture_with_input(
            Command::new(shell_compat::os(&curl_bin))
                .arg("-sS")
                .arg("--fail-with-body")
                .arg("--config")
                .arg("-")
                .arg(shell_compat::os(&cat(&[
                    b"https://console.neon.tech/api/v2/projects/",
                    &neon_project_id,
                    b"/branches",
                ]))),
            &auth,
        );
        let branches = if r.ok() {
            match parse_neon_branches(&r.stdout) {
                Ok(b) => b,
                Err(why) => {
                    log(&cat(&[
                        b"ERROR: could not read the Neon branch list: ",
                        &failure_detail(&why, b"", &neon_api_key),
                        b" \xe2\x80\x94 no Neon branch was reaped",
                    ]));
                    if shell_compat::env_set_nonempty("GITHUB_ACTIONS") {
                        err(b"::error title=Neon Reaper Error::could not read the Neon branch list\n");
                    }
                    list_failed = true;
                    Vec::new()
                }
            }
        } else {
            let code = r.status.to_string();
            log(&cat(&[
                b"ERROR: could not list Neon branches (curl exit ",
                code.as_bytes(),
                b"): ",
                &failure_detail(&r.stderr, &r.stdout, &neon_api_key),
                b" \xe2\x80\x94 no Neon branch was reaped",
            ]));
            if shell_compat::env_set_nonempty("GITHUB_ACTIONS") {
                err(&cat(&[
                    b"::error title=Neon Reaper Error::could not list Neon branches (curl exit ",
                    code.as_bytes(),
                    b")\n",
                ]));
            }
            list_failed = true;
            Vec::new()
        };
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
                let branch_epoch = match resource_epoch("Neon branch", branch_name, created_at) {
                    Ok(v) => v,
                    Err(()) => continue,
                };
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
                        let rc = status_with_input(
                            334,
                            Command::new(shell_compat::os(&curl_bin))
                                .arg("-sf")
                                .arg("-X")
                                .arg("DELETE")
                                .arg("--config")
                                .arg("-")
                                .arg(shell_compat::os(&cat(&[
                                    b"https://console.neon.tech/api/v2/projects/",
                                    &neon_project_id,
                                    b"/branches/",
                                    branch_id,
                                ])))
                                .stdout(std::process::Stdio::null())
                                .stderr(std::process::Stdio::null()),
                            &auth,
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

    // Reported above, after the counts of what was reaped: the step fails so
    // a broken listing is not mistaken for nothing to reap.
    if list_failed {
        return 1;
    }
    0
}

/// What a failed command said, for one log line: its stderr, else its
/// output (the error body `--fail-with-body` keeps), on one line, at most
/// 500 bytes, with `secret` hidden should either echo it.
fn failure_detail(stderr: &[u8], stdout: &[u8], secret: &[u8]) -> Vec<u8> {
    let said = if stderr.iter().any(|c| !c.is_ascii_whitespace()) {
        stderr
    } else {
        stdout
    };
    let mut one_line: Vec<u8> = said
        .iter()
        .map(|&c| if c == b'\n' || c == b'\r' { b' ' } else { c })
        .collect();
    if !secret.is_empty() {
        let mut hidden = Vec::with_capacity(one_line.len());
        let mut i = 0;
        while i < one_line.len() {
            if one_line[i..].starts_with(secret) {
                hidden.extend_from_slice(b"<redacted>");
                i += secret.len();
            } else {
                hidden.push(one_line[i]);
                i += 1;
            }
        }
        one_line = hidden;
    }
    let start = one_line
        .iter()
        .position(|c| !c.is_ascii_whitespace())
        .unwrap_or(one_line.len());
    let end = one_line
        .iter()
        .rposition(|c| !c.is_ascii_whitespace())
        .map_or(start, |i| i + 1);
    let trimmed = &one_line[start..end];
    if trimmed.is_empty() {
        return b"(no output)".to_vec();
    }
    trimmed[..trimmed.len().min(500)].to_vec()
}

/// Log (and annotate, in Actions) that `what` could not be listed by `tool`.
fn listing_failed(title: &str, what: &str, tool: &str, r: &Ran, secret: &[u8]) {
    let code = r.status.to_string();
    log(&cat(&[
        b"ERROR: could not list ",
        what.as_bytes(),
        b" (",
        tool.as_bytes(),
        b" exit ",
        code.as_bytes(),
        b"): ",
        &failure_detail(&r.stderr, &r.stdout, secret),
        b" \xe2\x80\x94 none of them was reaped",
    ]));
    if shell_compat::env_set_nonempty("GITHUB_ACTIONS") {
        err(&cat(&[
            b"::error title=",
            title.as_bytes(),
            b"::could not list ",
            what.as_bytes(),
            b" (",
            tool.as_bytes(),
            b" exit ",
            code.as_bytes(),
            b")\n",
        ]));
    }
}

/// `v` without leading or trailing ASCII whitespace.
fn trim_ascii_whitespace(v: &[u8]) -> &[u8] {
    let start = v
        .iter()
        .position(|c| !c.is_ascii_whitespace())
        .unwrap_or(v.len());
    let end = v
        .iter()
        .rposition(|c| !c.is_ascii_whitespace())
        .map_or(start, |i| i + 1);
    &v[start..end]
}

/// The curl config (read with `--config -`) that sends `key` as the Neon
/// bearer token: one `header = "..."` line, `"` and `\` escaped as curl's
/// config syntax requires. `key` arrives trimmed (a secret written with
/// `echo` ends in a newline). `None` for a key still holding a control
/// character: a line break would start a second curl option.
fn neon_auth_config(key: &[u8]) -> Option<Vec<u8>> {
    if key.iter().any(|c| c.is_ascii_control()) {
        return None;
    }
    let mut v = b"header = \"Authorization: Bearer ".to_vec();
    for &c in key {
        if c == b'"' || c == b'\\' {
            v.push(b'\\');
        }
        v.push(c);
    }
    v.extend_from_slice(b"\"\n");
    Some(v)
}

/// Run `cmd` with `input` on its stdin, stdout and stderr captured. A child
/// that exits without reading its input fails (141, as `printf | cmd` does
/// under pipefail): curl that never read its `--config -` sent no key.
fn capture_with_input(cmd: &mut Command, input: &[u8]) -> Ran {
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            return Ran {
                status: shell_compat::spawn_failure_status(&e),
                stdout: Vec::new(),
                stderr: shell_compat::spawn_diag(292, cmd, &e),
            }
        }
    };
    // The config is one short line, far below a pipe's buffer, so writing
    // it before reading the output cannot deadlock.
    let wrote = child
        .stdin
        .take()
        .map_or(false, |mut sin| sin.write_all(input).is_ok());
    match child.wait_with_output() {
        Ok(o) => {
            let status = shell_compat::status_code(o.status);
            Ran {
                status: if status == 0 && !wrote { 141 } else { status },
                stdout: o.stdout,
                stderr: o.stderr,
            }
        }
        Err(e) => Ran {
            status: 1,
            stdout: Vec::new(),
            stderr: e.to_string().into_bytes(),
        },
    }
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

/// The branches in a Neon `GET /branches` response: (id, name, created_at,
/// primary). Anything that is not a JSON object whose `branches` is a list
/// of objects (an HTML error page from a proxy, a truncated body, an error
/// object) is `Err` with the reason, never an empty list: an empty list
/// means nothing to reap, and the run would pass.
fn parse_neon_branches(json: &[u8]) -> Result<Vec<(Vec<u8>, Vec<u8>, Vec<u8>, bool)>, Vec<u8>> {
    // python3 parses the JSON (as the original script did). The body goes
    // on stdin, not argv: a long branch list must not hit ARG_MAX.
    const PARSE: &str = r#"import sys, json
try:
    data = json.loads(sys.stdin.buffer.read())
except ValueError as e:
    sys.exit('not JSON: %s' % e)
if not isinstance(data, dict) or not isinstance(data.get('branches'), list):
    sys.exit('no "branches" list in the response')
for b in data['branches']:
    if not isinstance(b, dict):
        sys.exit('a branch that is not an object')
    print('%s\t%s\t%s\t%s' % (b.get('id', ''), b.get('name', ''), b.get('created_at', ''), b.get('primary', False)))
"#;

    let r = capture_with_input(Command::new("python3").arg("-c").arg(PARSE), json);
    if !r.ok() {
        let why = if r.stderr.iter().any(|c| !c.is_ascii_whitespace()) {
            r.stderr
        } else {
            cat(&[b"python3 exit ", r.status.to_string().as_bytes()])
        };
        return Err(why);
    }
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
    Ok(result)
}
