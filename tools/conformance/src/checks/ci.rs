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

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

use crate::Context;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn indent(line: &str) -> usize {
    line.bytes().take_while(|&b| b == b' ').count()
}

fn strip(s: &str) -> &str {
    let s = s.trim_start_matches(|c: char| c == ' ' || c == '\t');
    let s = s.trim_end_matches(|c: char| c == ' ' || c == '\t' || c == '\r');
    s
}

fn unquote(s: &str) -> &str {
    let s = s.trim();
    if s.len() >= 2 {
        if (s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')) {
            return &s[1..s.len() - 1];
        }
    }
    s
}

fn list_workflows(dir: &str) -> Vec<String> {
    let mut result = Vec::new();
    let rd = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return result,
    };
    for entry in rd.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.ends_with(".yaml") || name.ends_with(".yml") {
            result.push(entry.path().to_string_lossy().to_string());
        }
    }
    result.sort();
    result
}

// ---------------------------------------------------------------------------
// CHECK: merge-queue required-check name consistency
// ---------------------------------------------------------------------------

fn strip_go_comment(line: &str) -> String {
    let mut result = String::new();
    let mut in_quote = false;
    let chars: Vec<char> = line.chars().collect();
    let len = chars.len();
    let mut i = 0;
    while i < len {
        let c = chars[i];
        if c == '"' {
            in_quote = !in_quote;
            result.push(c);
            i += 1;
            continue;
        }
        if !in_quote && c == '/' && i + 1 < len && chars[i + 1] == '/' {
            return result;
        }
        result.push(c);
        i += 1;
    }
    result
}

fn extract_required_checks(repo_config_main: &str) -> Vec<String> {
    let content = match fs::read_to_string(repo_config_main) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let mut grab = false;
    let mut checks = Vec::new();

    for raw_line in content.lines() {
        let line = raw_line.trim_end_matches('\r');
        if line.contains("checks = []string{") {
            grab = true;
        }
        if grab {
            let stripped = strip_go_comment(line);
            let mut rest = stripped.as_str();
            while let Some(start) = rest.find('"') {
                let after = &rest[start + 1..];
                if let Some(end) = after.find('"') {
                    checks.push(after[..end].to_string());
                    rest = &after[end + 1..];
                } else {
                    break;
                }
            }
            if stripped.contains('}') {
                break;
            }
        }
    }
    checks
}

struct ProducibleEntry {
    context: String,
    pr_paths: bool,
    pr_branches: bool,
}

fn extract_producible_contexts(workflows_dir: &str) -> Vec<ProducibleEntry> {
    let workflows = list_workflows(workflows_dir);
    let mut all_entries: Vec<ProducibleEntry> = Vec::new();

    for wf in &workflows {
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let mut in_on = false;
        let mut has_mg = false;
        let mut in_pr = false;
        let mut pr_paths = false;
        let mut pr_branches = false;

        let mut in_jobs = false;
        let mut job_id = String::new();
        let mut job_name = String::new();
        let mut vals: Vec<String> = Vec::new();
        let mut collecting_block = false;

        let mut out: Vec<String> = Vec::new();

        let flush = |jid: &mut String,
                     jname: &mut String,
                     vs: &mut Vec<String>,
                     cb: &mut bool,
                     o: &mut Vec<String>| {
            if jid.is_empty() {
                return;
            }
            let display = if jname.is_empty() {
                jid.clone()
            } else {
                jname.clone()
            };
            if vs.is_empty() {
                o.push(display);
            } else {
                for v in vs.iter() {
                    o.push(format!("{} ({})", display, v));
                }
            }
            jid.clear();
            jname.clear();
            vs.clear();
            *cb = false;
        };

        for raw_line in content.lines() {
            let line = raw_line.trim_end_matches('\r');
            let ind = indent(line);
            let trimmed = strip(line);

            // Inline on: [...merge_group...]
            if line.starts_with("on:") && line.contains('[') && line.contains("merge_group") {
                has_mg = true;
            }

            // on: block start
            if line.starts_with("on:") && strip(&line["on:".len()..]).is_empty() {
                in_on = true;
                continue;
            }

            if in_on {
                if ind == 0 && !trimmed.is_empty() {
                    in_on = false;
                    in_pr = false;
                } else {
                    if trimmed.starts_with("merge_group:") || trimmed == "merge_group" {
                        has_mg = true;
                    }
                    if ind == 2 && trimmed.starts_with("pull_request:") {
                        in_pr = true;
                    } else if ind <= 2
                        && !trimmed.is_empty()
                        && !trimmed.starts_with("pull_request:")
                    {
                        if ind == 2 {
                            in_pr = false;
                        }
                    }
                    if in_pr && ind >= 4 {
                        if trimmed.starts_with("paths:") || trimmed.starts_with("paths-ignore:") {
                            pr_paths = true;
                        }
                        if trimmed.starts_with("branches:") {
                            pr_branches = true;
                        }
                    }
                }
            }

            // jobs: block
            if line.starts_with("jobs:") && strip(&line["jobs:".len()..]).is_empty() {
                in_jobs = true;
                continue;
            }

            if !in_jobs {
                continue;
            }

            if trimmed.starts_with('#') || trimmed.is_empty() {
                continue;
            }

            if ind == 0 && !trimmed.is_empty() && !trimmed.starts_with('#') {
                flush(
                    &mut job_id,
                    &mut job_name,
                    &mut vals,
                    &mut collecting_block,
                    &mut out,
                );
                in_jobs = false;
                continue;
            }

            // Job id at indent 2
            if ind == 2 && trimmed.ends_with(':') && !trimmed.starts_with('#') {
                flush(
                    &mut job_id,
                    &mut job_name,
                    &mut vals,
                    &mut collecting_block,
                    &mut out,
                );
                let id_part = trimmed.strip_suffix(':').unwrap_or(trimmed);
                let id_trimmed = id_part.trim();
                if !id_trimmed.contains(' ') {
                    job_id = id_trimmed.to_string();
                }
                continue;
            }

            if job_id.is_empty() {
                continue;
            }

            // name: at indent 4
            if ind == 4 && trimmed.starts_with("name:") {
                let val = trimmed.strip_prefix("name:").unwrap_or("").trim();
                job_name = unquote(val).to_string();
                continue;
            }

            // Inline matrix at indent 8: `key: [a, b, c]`
            if ind == 8 && trimmed.contains(": [") && trimmed.contains(']') {
                if !trimmed.starts_with("include:") && !trimmed.starts_with("exclude:") {
                    if let Some(bracket_start) = trimmed.find('[') {
                        if let Some(bracket_end) = trimmed.rfind(']') {
                            let inner = &trimmed[bracket_start + 1..bracket_end];
                            for item in inner.split(',') {
                                let v = unquote(item.trim());
                                if !v.is_empty() {
                                    vals.push(v.to_string());
                                }
                            }
                        }
                    }
                    continue;
                }
            }

            // Block matrix list start at indent 8
            if ind == 8
                && trimmed.ends_with(':')
                && !trimmed.starts_with("include:")
                && !trimmed.starts_with("exclude:")
            {
                collecting_block = true;
                continue;
            }

            if collecting_block {
                if ind >= 10 && trimmed.starts_with("- ") {
                    let v = unquote(trimmed.strip_prefix("- ").unwrap_or("").trim());
                    if !v.is_empty() {
                        vals.push(v.to_string());
                    }
                    continue;
                } else if !trimmed.is_empty() {
                    collecting_block = false;
                }
            }
        }

        flush(
            &mut job_id,
            &mut job_name,
            &mut vals,
            &mut collecting_block,
            &mut out,
        );

        if !has_mg {
            continue;
        }

        for ctx_name in &out {
            all_entries.push(ProducibleEntry {
                context: ctx_name.clone(),
                pr_paths,
                pr_branches,
            });
        }
    }

    // Deduplicate by context (LC_ALL=C sort -u)
    let mut seen = BTreeSet::new();
    all_entries.retain(|e| seen.insert(e.context.clone()));
    all_entries.sort_by(|a, b| a.context.as_bytes().cmp(b.context.as_bytes()));
    all_entries
}

fn strip_matrix_suffix(s: &str) -> String {
    if let Some(pos) = s.rfind(" (") {
        if s.ends_with(')') {
            return s[..pos].to_string();
        }
    }
    s.to_string()
}

pub fn check_merge_queue(ctx: &Context) {
    let repo_config = format!(
        "{}/infrastructure/pulumi/platform/repo-config/main.go",
        ctx.root
    );
    if !Path::new(&repo_config).is_file() || !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }

    let required = extract_required_checks(&repo_config);
    if required.is_empty() {
        return;
    }

    let entries = extract_producible_contexts(&ctx.workflows_dir);
    let producible: BTreeSet<String> = entries.iter().map(|e| e.context.clone()).collect();

    if producible.is_empty() {
        ctx.emit_fail(
            "mergeq",
            "(all)",
            "required",
            "MISSING",
            "extracted 0 merge_group check contexts from .github/workflows \u{2014} workflows or parser changed",
            "confirm ci.yaml/tidy-check.yaml/conformance-check.yaml still trigger on merge_group with the expected jobs",
        );
        return;
    }

    let bases: BTreeSet<String> = producible.iter().map(|c| strip_matrix_suffix(c)).collect();

    let prpaths_bases: BTreeSet<String> = entries
        .iter()
        .filter(|e| e.pr_paths)
        .map(|e| strip_matrix_suffix(&e.context))
        .collect();

    let prbranches_bases: BTreeSet<String> = entries
        .iter()
        .filter(|e| e.pr_branches)
        .map(|e| strip_matrix_suffix(&e.context))
        .collect();

    for rc in &required {
        if rc.is_empty() {
            continue;
        }
        if producible.contains(rc) {
            let rcbase = strip_matrix_suffix(rc);
            let mut hit = false;

            if prpaths_bases.contains(&rcbase) {
                ctx.emit_fail(
                    "mergeq", rc, "required", "PR-BLOCKED",
                    "workflow has a pull_request 'paths:' filter, so this required check does NOT report on PRs outside those paths \u{2014} wedging their mergeability",
                    "drop the workflow-level pull_request 'paths:' filter (gate the WORK via a step instead) so the check always reports",
                );
                hit = true;
            }
            if prbranches_bases.contains(&rcbase) {
                ctx.emit_fail(
                    "mergeq", rc, "required", "PR-RETARGET-BLOCKED",
                    "workflow has a pull_request 'branches:' filter, so this required check does NOT report on a PR whose base isn't in that list -- a stacked PR presents as fully green while this check silently never ran",
                    "drop the workflow-level pull_request 'branches:' filter so the check reports regardless of the PR's base",
                );
                hit = true;
            }
            if !hit {
                ctx.emit_ok(
                    "mergeq",
                    rc,
                    "required",
                    "producible",
                    "reports on merge_group + every PR",
                );
            }
        } else {
            let rcbase = strip_matrix_suffix(rc);
            if rcbase != *rc && bases.contains(&rcbase) {
                ctx.emit_warn(
                    "mergeq", rc, "required", "job ok",
                    &format!(
                        "job '{}' runs on merge_group but its matrix value is unconfirmed \u{2014} verify the matrix still emits this context",
                        rcbase
                    ),
                );
            } else {
                ctx.emit_fail(
                    "mergeq", rc, "required", "MISSING",
                    "no job produces this required check on the merge_group event \u{2014} the queue will wedge pending",
                    "align repo-config/main.go's required-check list or the workflow job name so they match",
                );
            }
        }
    }
}

// ---------------------------------------------------------------------------
// CHECK: postsubmit concurrency keying
// ---------------------------------------------------------------------------

pub fn check_postsubmit_concurrency(ctx: &Context) {
    if !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }

    let workflows = list_workflows(&ctx.workflows_dir);
    let mut found_any = 0u32;

    for wf in &workflows {
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let wf_name = Path::new(wf)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy();
        let wf_rel = format!(".github/workflows/{}", wf_name);

        // Verification signature: push-to-main + merge_group
        let mut in_on = false;
        let mut has_mg = false;
        let mut in_push = false;
        let mut push_main = false;

        for raw_line in content.lines() {
            let line = raw_line.trim_end_matches('\r');
            let ind = indent(line);
            let trimmed = strip(line);

            if trimmed.starts_with('#') {
                if in_on {
                    continue;
                }
            }

            if line.starts_with("on:") && strip(&line["on:".len()..]).is_empty() {
                in_on = true;
                continue;
            }
            if in_on {
                if trimmed.starts_with('#') {
                    continue;
                }
                if ind == 0 && !trimmed.is_empty() {
                    in_on = false;
                    in_push = false;
                    continue;
                }
                if trimmed.starts_with("merge_group:") || trimmed == "merge_group" {
                    has_mg = true;
                }
                if trimmed.starts_with("push:") {
                    in_push = true;
                    continue;
                }
                if in_push && ind == 2 && !trimmed.is_empty() && !trimmed.starts_with("push:") {
                    // AWK: `in_on && in_push && /^  [A-Za-z_]/ { in_push=0 }`
                    if let Some(first) = trimmed.chars().next() {
                        if first.is_ascii_alphabetic() || first == '_' {
                            in_push = false;
                        }
                    }
                }
                if in_push && trimmed.contains("branches:") && trimmed.contains("main") {
                    push_main = true;
                }
            }
        }

        if !(has_mg && push_main) {
            continue;
        }
        found_any += 1;

        // Extract top-level concurrency group
        let mut in_conc = false;
        let mut group_text = String::new();

        for raw_line in content.lines() {
            let line = raw_line.trim_end_matches('\r');
            let ind = indent(line);
            let trimmed = strip(line);

            if line.starts_with("concurrency:") && strip(&line["concurrency:".len()..]).is_empty() {
                in_conc = true;
                continue;
            }
            if in_conc {
                if ind == 0 && !trimmed.is_empty() {
                    in_conc = false;
                    continue;
                }
                if trimmed.starts_with("group:") {
                    group_text = trimmed
                        .strip_prefix("group:")
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    break;
                }
            }
        }

        if group_text.is_empty() {
            ctx.emit_ok(
                "concur",
                &wf_rel,
                "none",
                "per-commit",
                "no concurrency group \u{2014} every push/merge_group run keeps its verdict",
            );
            continue;
        }

        let has_ref = group_text.contains("github.ref");
        let has_sha = group_text.contains("github.sha");

        if has_ref {
            if has_sha {
                ctx.emit_ok(
                    "concur",
                    &wf_rel,
                    "ref+sha",
                    "per-commit",
                    "PR lane supersedes by ref; push/merge_group key on sha",
                );
            } else {
                ctx.emit_fail(
                    "concur", &wf_rel, "ref-only", "per-commit",
                    "every push-to-main run shares one group \u{2014} a merge burst evicts the middle commits' PENDING runs, landing them with no verdict",
                    "key non-PR events on the commit: group: ${{ github.workflow }}-${{ github.event_name }}-${{ github.event_name == 'pull_request' && github.ref || github.sha }}",
                );
            }
        } else if has_sha {
            ctx.emit_ok(
                "concur",
                &wf_rel,
                "sha",
                "per-commit",
                "keyed on the commit \u{2014} no cross-commit eviction",
            );
        } else {
            ctx.emit_fail(
                "concur", &wf_rel, "constant", "per-commit",
                "a constant group serializes every run into one lane \u{2014} queued runs get evicted by newer ones",
                "key non-PR events on the commit (add ${{ github.sha }} to the group)",
            );
        }
    }

    if found_any == 0 {
        ctx.emit_fail(
            "concur",
            ".github/workflows",
            "0 matched",
            ">=1",
            "no workflow matched the push-to-main + merge_group signature \u{2014} the parser or the workflow layout changed",
            "confirm ci.yaml still triggers on both 'push: branches: [main]' and 'merge_group:'",
        );
    }
}

// ---------------------------------------------------------------------------
// CHECK: job timeouts (#209)
// ---------------------------------------------------------------------------

struct JobInfo {
    id: String,
    has_timeout: bool,
    is_call: bool,
}

fn parse_workflow_jobs(content: &str) -> Vec<JobInfo> {
    let mut result = Vec::new();
    let mut in_jobs = false;
    let mut job_indent: i32 = -1;
    let mut key_indent: i32 = -1;
    let mut job_id = String::new();
    let mut has_timeout = false;
    let mut is_call = false;

    let flush =
        |id: &mut String, to: &mut bool, call: &mut bool, ki: &mut i32, out: &mut Vec<JobInfo>| {
            if !id.is_empty() {
                out.push(JobInfo {
                    id: id.clone(),
                    has_timeout: *to,
                    is_call: *call,
                });
            }
            id.clear();
            *to = false;
            *call = false;
            *ki = -1;
        };

    for raw_line in content.lines() {
        let line = raw_line.trim_end_matches('\r');
        let ind = indent(line);
        let trimmed = strip(line);

        if line.starts_with("jobs:") && strip(&line["jobs:".len()..]).is_empty() {
            in_jobs = true;
            continue;
        }

        if !in_jobs {
            continue;
        }

        if trimmed.starts_with('#') || trimmed.is_empty() {
            continue;
        }

        if ind == 0 {
            flush(
                &mut job_id,
                &mut has_timeout,
                &mut is_call,
                &mut key_indent,
                &mut result,
            );
            in_jobs = false;
            continue;
        }

        if job_indent < 0 {
            job_indent = ind as i32;
        }

        // Job id: bare "<name>:" at the discovered job-id indent
        if ind == job_indent as usize {
            let is_job_id = trimmed.ends_with(':') && !trimmed.starts_with('#') && {
                let before_colon = trimmed.trim_end_matches(':');
                before_colon
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-' || b == b'.')
            };
            if is_job_id {
                flush(
                    &mut job_id,
                    &mut has_timeout,
                    &mut is_call,
                    &mut key_indent,
                    &mut result,
                );
                job_id = trimmed.strip_suffix(':').unwrap_or(trimmed).to_string();
                continue;
            }
        }

        if job_id.is_empty() {
            continue;
        }

        if key_indent < 0 && (ind as i32) > job_indent {
            key_indent = ind as i32;
        }

        if ind == key_indent as usize {
            if trimmed.starts_with("timeout-minutes:") {
                has_timeout = true;
            }
            if trimmed.starts_with("uses:") {
                is_call = true;
            }
        }
    }

    flush(
        &mut job_id,
        &mut has_timeout,
        &mut is_call,
        &mut key_indent,
        &mut result,
    );
    result
}

pub fn check_job_timeouts(ctx: &Context) {
    if !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }

    let workflows = list_workflows(&ctx.workflows_dir);
    let mut seen_jobs: u32 = 0;
    let mut missing: Vec<(String, String)> = Vec::new();

    for wf in &workflows {
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let wf_name = Path::new(wf)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy();
        let wf_rel = format!(".github/workflows/{}", wf_name);
        let jobs = parse_workflow_jobs(&content);

        for job in &jobs {
            seen_jobs += 1;
            if job.is_call {
                continue;
            }
            if !job.has_timeout {
                missing.push((wf_rel.clone(), job.id.clone()));
            }
        }
    }

    if !missing.is_empty() {
        for (wfr, jid) in &missing {
            ctx.emit_fail(
                "timeout", wfr, jid, "timeout-minutes",
                "job has no timeout-minutes \u{2014} it inherits GitHub's 360-minute default, so a hung step burns a runner for 6h",
                &format!("add a 'timeout-minutes:' to the '{}' job sized to its normal runtime plus headroom", jid),
            );
        }
    }

    if seen_jobs == 0 {
        ctx.emit_fail(
            "timeout",
            ".github/workflows",
            "0 jobs",
            ">=1",
            "no workflow jobs parsed \u{2014} the parser or the workflow layout changed",
            "confirm .github/workflows/*.yaml still declare jobs under a top-level 'jobs:' key",
        );
    } else if missing.is_empty() {
        ctx.emit_ok(
            "timeout",
            ".github/workflows",
            &format!("{} jobs", seen_jobs),
            "all bounded",
            "every non-delegating job declares timeout-minutes",
        );
    }
}

// ---------------------------------------------------------------------------
// CHECK: scheduled full-sweep backstop
// ---------------------------------------------------------------------------

pub fn check_sweep_backstop(ctx: &Context) {
    let sweep = format!("{}/periodic-full-sweep.yaml", ctx.workflows_dir);
    let sweep_rel = ".github/workflows/periodic-full-sweep.yaml";

    if !Path::new(&sweep).is_file() {
        ctx.emit_fail(
            "sweep", sweep_rel, "missing", "scheduled //... sweep",
            "ci.yaml merge_group/push lanes are affected-scoped but the whole-graph backstop workflow is gone",
            "restore periodic-full-sweep.yaml (scheduled full bazel build+test //...) or revert the lanes to unconditional full sweeps",
        );
        return;
    }

    let content = match fs::read_to_string(&sweep) {
        Ok(c) => c,
        Err(_) => return,
    };

    let mut ok = true;

    let has_schedule = content.lines().any(|l| {
        let t = strip(l);
        t.starts_with("schedule:")
    });
    let has_cron = content.lines().any(|l| {
        let t = strip(l);
        t.starts_with("- cron:") || t.starts_with("-cron:")
    });

    if !has_schedule || !has_cron {
        ctx.emit_fail(
            "sweep", sweep_rel, "no schedule", "cron schedule",
            "the backstop workflow exists but has no schedule/cron trigger \u{2014} it would never run on its own",
            "restore the schedule: cron trigger (nightly) in periodic-full-sweep.yaml",
        );
        ok = false;
    }

    let has_build_all = content
        .lines()
        .any(|l| l.contains("bazel") && l.contains("build") && l.contains("//..."));
    let has_test_all = content
        .lines()
        .any(|l| l.contains("bazel") && l.contains("test") && l.contains("//..."));

    if !has_build_all || !has_test_all {
        ctx.emit_fail(
            "sweep",
            sweep_rel,
            "narrowed",
            "build+test //...",
            "the backstop workflow no longer builds AND tests the whole //... graph",
            "keep both 'bazel build //...' and 'bazel test //...' in periodic-full-sweep.yaml",
        );
        ok = false;
    }

    if ok {
        ctx.emit_ok(
            "sweep", sweep_rel, "scheduled", "build+test //...",
            "whole-graph backstop present \u{2014} affected-scoped merge_group/push lanes are covered",
        );
    }
}

// ---------------------------------------------------------------------------
// CHECK: Actions cache saves only from GitHub-hosted jobs on main
// ---------------------------------------------------------------------------
//
// On 2026-10-31 two merge-queue Conformance Check runs passed in 6 minutes,
// then spent 38 minutes in setup-bazel's post step uploading a 5.7 GB
// repository cache from a self-hosted queue runner (~1.8 MB/s) and hit the
// job timeout, cancelling a required check. A cache saved on a merge-queue ref
// is unreadable by any other ref, and every save evicts main's entries from
// the shared 10 GiB budget. The fix restricts saving to GitHub-hosted jobs on
// main in the two shared composites; this check keeps it that way.

/// The guard every cache save must carry: main only, GitHub-hosted only.
pub(crate) fn cache_save_expr_guarded(expr: &str) -> bool {
    let e: String = expr.split_whitespace().collect::<Vec<_>>().join(" ");
    e.contains("github.ref == 'refs/heads/main'")
        && e.contains("runner.environment == 'github-hosted'")
        && !e.contains("||")
}

/// The value of the first non-comment line starting with `key:` (e.g.
/// `cache-save:` or `MAY_SAVE:`), or None when there is none.
pub(crate) fn yaml_value_of(content: &str, key: &str) -> Option<String> {
    let prefix = format!("{}:", key);
    content
        .lines()
        .map(strip)
        .filter(|l| !l.starts_with('#'))
        .find(|l| l.starts_with(&prefix))
        .map(|l| l[prefix.len()..].trim().to_string())
}

/// True when a non-comment line in `content` uses setup-bazel directly.
pub(crate) fn uses_setup_bazel_directly(content: &str) -> bool {
    content
        .lines()
        .map(strip)
        .any(|l| !l.starts_with('#') && l.contains("bazel-contrib/setup-bazel@"))
}

/// The `uses:` and `if:` of every step in a composite action, in order.
fn composite_steps(content: &str) -> Vec<(String, Option<String>)> {
    let mut steps: Vec<(String, Option<String>)> = Vec::new();
    let mut step_indent: Option<usize> = None;
    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        let s = strip(line);
        if s.is_empty() || s.starts_with('#') {
            continue;
        }
        let ind = indent(line);
        if let Some(rest) = s.strip_prefix("- ") {
            if step_indent.is_none() || step_indent == Some(ind) {
                step_indent = Some(ind);
                steps.push((String::new(), None));
                apply_step_key(steps.last_mut().unwrap(), rest);
                continue;
            }
        }
        if let (Some(si), Some(last)) = (step_indent, steps.last_mut()) {
            if ind == si + 2 {
                apply_step_key(last, s);
            } else if ind <= si && !s.starts_with("- ") {
                step_indent = None;
            }
        }
    }
    steps
}

fn apply_step_key(step: &mut (String, Option<String>), kv: &str) {
    if let Some(v) = kv.strip_prefix("uses:") {
        step.0 = v.split('#').next().unwrap_or("").trim().to_string();
    } else if let Some(v) = kv.strip_prefix("if:") {
        step.1 = Some(v.split(" #").next().unwrap_or("").trim().to_string());
    }
}

/// (found, wanted, why) for each way the LLVM composite's restore steps stop
/// honouring the save decision. Empty when both branch on `readonly`.
pub(crate) fn llvm_restore_branch_problems(content: &str) -> Vec<(String, String, String)> {
    let norm = |s: &str| {
        s.split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .replace('"', "'")
    };
    let mut problems = Vec::new();
    let steps = composite_steps(content);
    let checks: &[(&str, &str, &str)] = &[
        (
            "actions/cache@",
            "steps.mode.outputs.readonly != 'true'",
            "the read+write restore does not branch on the save decision, so it saves wherever its `if:` lets it run -- MAY_SAVE is computed and then ignored",
        ),
        (
            "actions/cache/restore@",
            "steps.mode.outputs.readonly == 'true'",
            "the read-only restore does not branch on the save decision, so a job barred from saving can end up with no restore, or with both",
        ),
    ];
    for (uses, want, why) in checks {
        let matching: Vec<&(String, Option<String>)> =
            steps.iter().filter(|(u, _)| u.starts_with(uses)).collect();
        if matching.len() != 1 {
            problems.push((
                format!("{} {} step(s)", matching.len(), uses.trim_end_matches('@')),
                format!("exactly 1, if: {}", want),
                why.to_string(),
            ));
            continue;
        }
        let got = matching[0].1.as_deref().map(norm).unwrap_or_default();
        let got_bare = got
            .trim_start_matches("${{")
            .trim_end_matches("}}")
            .trim()
            .to_string();
        if got_bare != *want {
            problems.push((
                if got.is_empty() {
                    "no if:".to_string()
                } else {
                    format!("if: {}", got)
                },
                format!("if: {}", want),
                why.to_string(),
            ));
        }
    }
    let mode_reads_may_save = content.contains("$MAY_SAVE");
    if !mode_reads_may_save {
        problems.push((
            "MAY_SAVE unused".to_string(),
            "mode step reads $MAY_SAVE".to_string(),
            "the mode step no longer consults MAY_SAVE, so readonly no longer follows the main-and-GitHub-hosted guard".to_string(),
        ));
    }
    problems
}

pub fn check_cache_save(ctx: &Context) {
    let actions_dir = format!("{}/.github/actions", ctx.root);
    let mut ok = true;

    // 1. The two shared composites carry the guard.
    let guarded: &[(&str, &str)] = &[
        ("setup-bazel/action.yml", "cache-save"),
        ("llvm-cache-restore/action.yml", "MAY_SAVE"),
    ];
    for (file, key) in guarded {
        let rel = format!(".github/actions/{}", file);
        let content = match fs::read_to_string(format!("{}/{}", actions_dir, file)) {
            Ok(c) => c,
            Err(_) => {
                ctx.emit_fail(
                    "cachesave", &rel, "missing", "guarded save",
                    "the shared cache composite is gone, so nothing bounds where its caches are saved",
                    "restore the composite, or move this check to wherever the caches are now set up",
                );
                ok = false;
                continue;
            }
        };
        match yaml_value_of(&content, key) {
            Some(v) if cache_save_expr_guarded(&v) => {}
            found => {
                ctx.emit_fail(
                    "cachesave", &rel, found.as_deref().unwrap_or("unset"),
                    "main && github-hosted",
                    "caches would be saved from merge-queue/PR refs or self-hosted runners: unreadable elsewhere, evicts main's entries, and a slow upload can time out a required check (2026-10-31 queue incident)",
                    &format!("set '{}: ${{{{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}}}'", key),
                );
                ok = false;
            }
        }
    }

    // 1b. MAY_SAVE only matters if the restore steps act on it. The `mode`
    //     step folds it into `readonly`; the read+write actions/cache step
    //     must run only when readonly is false and the read-only one only
    //     when it is true. Pointing the read+write step back at
    //     `inputs.restore-only` would leave MAY_SAVE in place and saving
    //     from every ref and runner again.
    let llvm_rel = ".github/actions/llvm-cache-restore/action.yml";
    if let Ok(content) =
        fs::read_to_string(format!("{}/llvm-cache-restore/action.yml", actions_dir))
    {
        for problem in llvm_restore_branch_problems(&content) {
            ctx.emit_fail(
                "cachesave", llvm_rel, &problem.0, &problem.1, &problem.2,
                "branch both restore steps on steps.mode.outputs.readonly: `!= 'true'` on actions/cache, `== 'true'` on actions/cache/restore",
            );
            ok = false;
        }
    }

    // 2. Nobody bypasses the shared setup action.
    let mut files = list_workflows(&ctx.workflows_dir);
    if let Ok(rd) = fs::read_dir(&actions_dir) {
        for entry in rd.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name == "setup-bazel" {
                continue;
            }
            for f in ["action.yml", "action.yaml"] {
                let p = entry.path().join(f);
                if p.is_file() {
                    files.push(p.to_string_lossy().to_string());
                }
            }
        }
    }
    for f in &files {
        let content = match fs::read_to_string(f) {
            Ok(c) => c,
            Err(_) => continue,
        };
        if uses_setup_bazel_directly(&content) {
            ctx.emit_fail(
                "cachesave", &ctx.rel(f), "bazel-contrib/setup-bazel", "./.github/actions/setup-bazel",
                "calls setup-bazel directly, which saves its caches from every ref and runner by default",
                "use './.github/actions/setup-bazel' instead, which carries the save guard",
            );
            ok = false;
        }
    }

    if ok {
        ctx.emit_ok(
            "cachesave", ".github/actions", "guarded", "main && github-hosted",
            "setup-bazel and the LLVM cache save only from GitHub-hosted jobs on main; no workflow bypasses them",
        );
    }
}

// ---------------------------------------------------------------------------
// CHECK: CI gate list consistency
// ---------------------------------------------------------------------------

pub fn check_ci_gate_lists_match(ctx: &Context) {
    let deploy_affected = format!("{}/tools/ci/deploy-affected.sh", ctx.root);
    let affected_targets = format!("{}/tools/ci/affected-targets.sh", ctx.root);

    let extract_pattern = |path: &str| -> Option<String> {
        let content = fs::read_to_string(path).ok()?;
        for line in content.lines() {
            if let Some(start) = line.find("^tools/(") {
                let rest = &line[start..];
                if let Some(end) = rest.find('\'').or_else(|| rest.find('"')) {
                    return Some(rest[..end].to_string());
                }
                let end = rest.find(')').map(|p| p + 1).unwrap_or(rest.len());
                return Some(rest[..end].to_string());
            }
        }
        None
    };

    let a = extract_pattern(&deploy_affected);
    let b = extract_pattern(&affected_targets);

    match (a, b) {
        (Some(ref a_val), Some(ref b_val)) => {
            if a_val == b_val {
                ctx.emit_ok_uncounted(
                    "gate",
                    "tools/ci/*-affected*.sh",
                    "identical",
                    "identical",
                    "the deploy gate and the test gate agree on global-impact paths",
                );
            } else {
                ctx.emit_fail(
                    "gate",
                    "tools/ci/*-affected*.sh",
                    "diverged",
                    "identical",
                    "deploy-affected.sh and affected-targets.sh disagree on the global-impact allowlist, so CI and deploy disagree about what a change can affect",
                    "make the '^tools/(...)' patterns identical in both files",
                );
            }
        }
        _ => {
            ctx.emit_fail(
                "gate",
                "tools/ci/*-affected*.sh",
                "pattern not found",
                "one per file",
                "could not locate the global-impact allowlist in one of the gate scripts - the guard cannot verify them",
                "check the '^tools/(...)' pattern still exists in both deploy-affected.sh and affected-targets.sh",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_go_comment_preserves_quoted() {
        let line = r#"  "gate/all-required (Go)", // the gate check"#;
        let stripped = strip_go_comment(line);
        assert!(stripped.contains("gate/all-required (Go)"));
        assert!(!stripped.contains("the gate check"));
    }

    #[test]
    fn strip_go_comment_no_comment() {
        let line = r#"  "gate/check","#;
        assert_eq!(strip_go_comment(line), line);
    }

    #[test]
    fn strip_matrix_suffix_works() {
        assert_eq!(
            strip_matrix_suffix("gate/all-required (Go)"),
            "gate/all-required"
        );
        assert_eq!(
            strip_matrix_suffix("conformance-check"),
            "conformance-check"
        );
    }

    #[test]
    fn parse_workflow_jobs_basic() {
        let content = "\
name: CI
on: push

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - run: echo hello

  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo test

  call-other:
    uses: ./.github/workflows/other.yaml
";
        let jobs = parse_workflow_jobs(content);
        assert_eq!(jobs.len(), 3);
        assert_eq!(jobs[0].id, "build");
        assert!(jobs[0].has_timeout);
        assert!(!jobs[0].is_call);
        assert_eq!(jobs[1].id, "test");
        assert!(!jobs[1].has_timeout);
        assert!(!jobs[1].is_call);
        assert_eq!(jobs[2].id, "call-other");
        assert!(!jobs[2].has_timeout);
        assert!(jobs[2].is_call);
    }

    #[test]
    fn parse_workflow_jobs_discovers_indent() {
        let content = "\
name: 4-space
on: push

jobs:
    build:
        runs-on: ubuntu-latest
        timeout-minutes: 10
        steps:
            - run: echo hi
    nobounds:
        runs-on: ubuntu-latest
        steps:
            - run: echo hi
";
        let jobs = parse_workflow_jobs(content);
        assert_eq!(jobs.len(), 2);
        assert_eq!(jobs[0].id, "build");
        assert!(jobs[0].has_timeout);
        assert_eq!(jobs[1].id, "nobounds");
        assert!(!jobs[1].has_timeout);
    }

    #[test]
    fn cache_save_guard_accepts_main_and_github_hosted() {
        assert!(cache_save_expr_guarded(
            "${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}"
        ));
        assert!(cache_save_expr_guarded(
            "${{ runner.environment == 'github-hosted'  &&  github.ref == 'refs/heads/main' }}"
        ));
    }

    #[test]
    fn cache_save_guard_rejects_the_incident_shapes() {
        // setup-bazel's default, which saved 5.7 GB from a merge-queue runner.
        assert!(!cache_save_expr_guarded("true"));
        // Main only is not enough: main pushes also run on the slow queue runners.
        assert!(!cache_save_expr_guarded(
            "${{ github.ref == 'refs/heads/main' }}"
        ));
        // Excluding merge_group alone still saves from PR refs and self-hosted runners.
        assert!(!cache_save_expr_guarded(
            "${{ github.event_name != 'merge_group' }}"
        ));
        // An `||` escape hatch re-opens every ref.
        assert!(!cache_save_expr_guarded(
            "${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' || github.event_name == 'merge_group' }}"
        ));
    }

    const LLVM_GOOD: &str = "\
runs:
  using: composite
  steps:
    - name: Decide whether this job may save
      id: mode
      shell: bash
      env:
        MAY_SAVE: ${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}
      run: |
        if [ \"$MAY_SAVE\" != \"true\" ]; then echo readonly=true; fi

    - name: Restore the extracted LLVM toolchain
      id: restore-rw
      if: steps.mode.outputs.readonly != 'true'
      uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
      with:
        path: x

    - name: Restore the extracted LLVM toolchain (read-only)
      id: restore-ro
      if: steps.mode.outputs.readonly == 'true'
      uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
      with:
        path: x
";

    #[test]
    fn llvm_restore_branches_on_readonly() {
        assert!(
            llvm_restore_branch_problems(LLVM_GOOD).is_empty(),
            "{:?}",
            llvm_restore_branch_problems(LLVM_GOOD)
        );
    }

    #[test]
    fn llvm_restore_pointed_back_at_restore_only_fails() {
        // The gap aegis found: MAY_SAVE stays, the read+write step ignores it.
        let bad = LLVM_GOOD.replace(
            "if: steps.mode.outputs.readonly != 'true'",
            "if: inputs.restore-only != 'true'",
        );
        let p = llvm_restore_branch_problems(&bad);
        assert_eq!(p.len(), 1, "{:?}", p);
        assert!(p[0].0.contains("inputs.restore-only"));
    }

    #[test]
    fn llvm_readonly_step_must_branch_too() {
        let bad = LLVM_GOOD.replace("      if: steps.mode.outputs.readonly == 'true'\n", "");
        let p = llvm_restore_branch_problems(&bad);
        assert_eq!(p.len(), 1, "{:?}", p);
        assert_eq!(p[0].0, "no if:");
    }

    #[test]
    fn llvm_mode_must_read_may_save() {
        let bad = LLVM_GOOD.replace("\"$MAY_SAVE\"", "\"$OTHER\"");
        assert_eq!(llvm_restore_branch_problems(&bad).len(), 1);
    }

    #[test]
    fn yaml_value_of_skips_comments() {
        let content = "\
    # cache-save: true
    - uses: bazel-contrib/setup-bazel@abc # 0.19.1
      with:
        cache-save: ${{ github.ref == 'refs/heads/main' }}
";
        assert_eq!(
            yaml_value_of(content, "cache-save").as_deref(),
            Some("${{ github.ref == 'refs/heads/main' }}")
        );
        assert_eq!(yaml_value_of(content, "repository-cache"), None);
    }

    #[test]
    fn direct_setup_bazel_use_is_detected() {
        assert!(uses_setup_bazel_directly(
            "      - uses: bazel-contrib/setup-bazel@104e3eea # 0.19.1\n"
        ));
        assert!(!uses_setup_bazel_directly(
            "      # bazel-contrib/setup-bazel@x is wrapped by ./.github/actions/setup-bazel\n      - uses: ./.github/actions/setup-bazel\n"
        ));
    }

    #[test]
    fn unquote_strips() {
        assert_eq!(unquote("\"hello\""), "hello");
        assert_eq!(unquote("'hello'"), "hello");
        assert_eq!(unquote("hello"), "hello");
    }

    #[test]
    fn extract_required_checks_basic() {
        let tmp = std::env::temp_dir().join(format!("rc_main_{}", std::process::id()));
        std::fs::write(
            &tmp,
            r#"
package main

var (
    checks = []string{
        "ci",                    // the ci check
        "tidy-check",
        "gate/all-required (Go)", // go check
    }
)
"#,
        )
        .unwrap();
        let checks = extract_required_checks(tmp.to_str().unwrap());
        assert_eq!(checks, vec!["ci", "tidy-check", "gate/all-required (Go)"]);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn extract_required_checks_strips_comments() {
        let tmp = std::env::temp_dir().join(format!("rc_comment_{}", std::process::id()));
        std::fs::write(
            &tmp,
            r#"
    checks = []string{
        "real", // this mentions "pending" which should NOT be extracted
    }
"#,
        )
        .unwrap();
        let checks = extract_required_checks(tmp.to_str().unwrap());
        assert_eq!(checks, vec!["real"]);
        let _ = std::fs::remove_file(&tmp);
    }
}
