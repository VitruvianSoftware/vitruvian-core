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
// CHECK: Bazel repository cache saves only in bazel-repo-cache.yaml;
//        setup-bazel and other workflows restore only; LLVM saves on hosted main
// ---------------------------------------------------------------------------
//
// Only `.github/workflows/bazel-repo-cache.yaml` may save the Bazel repository
// cache (archives only, after a clean-state offline completeness check, keyed
// with `-repository-full-`). `.github/actions/setup-bazel/action.yml` is
// strictly restore-only (`cache-save: false`, `repository-cache: false`) so no
// partial job (e.g. Copybara export), PR branch, merge-queue ref, or slow
// self-hosted runner ever poisons or evicts the shared repository cache.

/// The guard the LLVM cache composite must carry: main only, GitHub-hosted only.
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

/// Every non-comment value for lines starting with `key:`.
pub(crate) fn yaml_values_of(content: &str, key: &str) -> Vec<String> {
    let prefix = format!("{}:", key);
    content
        .lines()
        .map(strip)
        .filter(|l| !l.starts_with('#') && l.starts_with(&prefix))
        .map(|l| l[prefix.len()..].trim().to_string())
        .collect()
}

/// True when a non-comment line in `content` uses setup-bazel directly.
pub(crate) fn uses_setup_bazel_directly(content: &str) -> bool {
    content
        .lines()
        .map(strip)
        .any(|l| !l.starts_with('#') && l.contains("bazel-contrib/setup-bazel@"))
}

/// The guard on `setup-bazel/action.yml`'s `actions/cache/restore` step:
/// every GitHub-hosted job (including main) restores the `full-` entry;
/// self-hosted queue runners mount their persistent `vitruvian-queue-cache`
/// PVC instead of downloading over WAN.
pub(crate) fn repo_restore_step_guarded(expr: &str) -> bool {
    let norm: String = expr.split_whitespace().collect::<Vec<_>>().join(" ");
    let bare = norm.trim_start_matches("${{").trim_end_matches("}}").trim();
    bare == "runner.environment == 'github-hosted'"
}

fn has_full_repo_hash_key(key: &str) -> bool {
    key.contains("-repository-full-")
        && key.contains("hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion')")
}

/// Extract non-comment `restore-keys:` entries from YAML content.
fn restore_keys_lines(content: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut in_rk = false;
    let mut rk_indent = 0usize;
    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        let s = strip(line);
        if s.is_empty() || s.starts_with('#') {
            continue;
        }
        let ind = indent(line);
        if s.starts_with("restore-keys:") {
            let inline = s["restore-keys:".len()..].trim();
            if inline != "|" && inline != ">" && !inline.is_empty() {
                out.push(inline.to_string());
                in_rk = false;
            } else {
                in_rk = true;
                rk_indent = ind;
            }
            continue;
        }
        if in_rk {
            if ind > rk_indent {
                out.push(s.to_string());
            } else {
                in_rk = false;
            }
        }
    }
    out
}

/// What is wrong with how `.github/actions/setup-bazel/action.yml` restores
/// the repository cache (restore-only), as (found, want, why) triples.
pub(crate) fn repository_restore_problems(content: &str) -> Vec<(String, String, String)> {
    let mut problems = Vec::new();
    match yaml_value_of(content, "repository-cache") {
        Some(v) if v == "false" => {}
        found => problems.push((
            format!("repository-cache: {}", found.as_deref().unwrap_or("unset (true)")),
            "repository-cache: false".to_string(),
            "setup-bazel is restore-only; letting bazel-contrib/setup-bazel touch the repository cache restores legacy keys, saves partial caches, or hangs on stalled downloads".to_string(),
        )),
    }
    match yaml_value_of(content, "cache-save") {
        Some(v) if v == "false" => {}
        found => problems.push((
            format!("cache-save: {}", found.as_deref().unwrap_or("unset (true)")),
            "cache-save: false".to_string(),
            "setup-bazel must never save caches; only .github/workflows/bazel-repo-cache.yaml may save the repository cache".to_string(),
        )),
    }
    let lines: Vec<&str> = content
        .lines()
        .map(strip)
        .filter(|l| !l.starts_with('#'))
        .collect();
    let steps = composite_steps(content);
    let save_steps = steps
        .iter()
        .filter(|s| {
            s.uses.starts_with("actions/cache/save@") || s.uses.starts_with("actions/cache@")
        })
        .count();
    if save_steps > 0 {
        problems.push((
            format!("{} actions/cache save step(s)", save_steps),
            "0 save steps in setup-bazel".to_string(),
            "setup-bazel is strictly restore-only and must never call actions/cache or actions/cache/save".to_string(),
        ));
    }
    let restore_steps: Vec<&StepMeta> = steps
        .iter()
        .filter(|s| s.uses.starts_with("actions/cache/restore@"))
        .collect();
    if restore_steps.is_empty() {
        problems.push((
            "no actions/cache/restore step".to_string(),
            "actions/cache/restore of ~/.cache/bazel-repo".to_string(),
            "GitHub-hosted jobs would start with no repository cache at all".to_string(),
        ));
    } else {
        match restore_steps[0].if_expr.as_deref() {
            Some(if_expr) if repo_restore_step_guarded(if_expr) => {}
            found => problems.push((
                format!("restore if: {}", found.unwrap_or("unset (always)")),
                "restore if: ${{ runner.environment == 'github-hosted' }}".to_string(),
                "actions/cache/restore must run on all GitHub-hosted jobs (including main) and skip self-hosted queue runners that mount the persistent vitruvian-queue-cache PVC".to_string(),
            )),
        }
        match restore_steps[0].key.as_deref() {
            Some(k) if has_full_repo_hash_key(k) => {}
            found => problems.push((
                format!("restore key: {}", found.unwrap_or("unset")),
                "setup-bazel-1-...-repository-full-${{ hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion') }}".to_string(),
                "setup-bazel must restore the verified `-repository-full-` key keyed on MODULE.bazel, MODULE.bazel.lock, and .bazelversion, never the old partial `-repository-` key".to_string(),
            )),
        }
    }
    let rk_lines = restore_keys_lines(content);
    if !rk_lines.iter().any(|l| l.contains("-repository-full-"))
        || rk_lines.iter().any(|l| l.ends_with("-repository-"))
    {
        problems.push((
            format!("restore-keys: {:?}", rk_lines),
            "prefix ending in -repository-full-".to_string(),
            "restore-keys must fall back only to `-repository-full-` so consumers never read legacy partial `-repository-<hash>` entries".to_string(),
        ));
    }
    if lines
        .iter()
        .any(|l| l.starts_with("path:") && l.contains("~/"))
    {
        problems.push((
            "path: ~/...".to_string(),
            "path: $HOME/.cache/bazel-repo, absolute, as bazel-repo-cache.yaml saves it".to_string(),
            "an Actions cache entry's version is a hash of its path strings, so `~/` never matches what bazel-repo-cache.yaml saved: every restore misses".to_string(),
        ));
    }
    let timeout = lines
        .iter()
        .find_map(|l| l.strip_prefix("SEGMENT_DOWNLOAD_TIMEOUT_MINS:"))
        .map(|v| {
            v.trim()
                .trim_matches('"')
                .trim_matches('\'')
                .parse::<u32>()
                .ok()
        });
    match timeout {
        Some(Some(minutes)) if (1..=5).contains(&minutes) => {}
        found => problems.push((
            format!("SEGMENT_DOWNLOAD_TIMEOUT_MINS: {}", match found {
                None => "unset (10)".to_string(),
                Some(None) => "not a number".to_string(),
                Some(Some(m)) => m.to_string(),
            }),
            "SEGMENT_DOWNLOAD_TIMEOUT_MINS: 1 to 5".to_string(),
            "a stalled download would hold the restore past the 15-minute jobs' timeout before it gives up".to_string(),
        )),
    }
    problems
}

/// Parsed step metadata from a composite action or workflow `steps:` list.
#[derive(Debug, Default)]
struct StepMeta {
    uses: String,
    if_expr: Option<String>,
    key: Option<String>,
    name: Option<String>,
    continue_on_error: Option<String>,
    runs_capacity_guard: bool,
    runs_prune: bool,
    warm_mode: Option<String>,
}

/// Every step's `uses:`, `if:`, `with.key:`, `name:`, and `continue-on-error:`
/// across a workflow or composite action.
fn composite_steps(content: &str) -> Vec<StepMeta> {
    let mut steps: Vec<StepMeta> = Vec::new();
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
                if rest.starts_with("uses:")
                    || rest.starts_with("name:")
                    || rest.starts_with("id:")
                    || rest.starts_with("if:")
                    || rest.starts_with("run:")
                    || rest.starts_with("env:")
                    || rest.starts_with("with:")
                    || rest.starts_with("shell:")
                    || rest.starts_with("continue-on-error:")
                {
                    step_indent = Some(ind);
                    steps.push(StepMeta::default());
                    let last = steps.last_mut().unwrap();
                    if rest.contains("cache_capacity_guard.py") {
                        last.runs_capacity_guard = true;
                    }
                    if rest.contains("cache_prune.py") {
                        last.runs_prune = true;
                    }
                    apply_step_key(last, rest);
                    continue;
                }
            }
        }
        if let (Some(si), Some(last)) = (step_indent, steps.last_mut()) {
            if ind > si {
                if s.contains("cache_capacity_guard.py") {
                    last.runs_capacity_guard = true;
                }
                if s.contains("cache_prune.py") {
                    last.runs_prune = true;
                }
                if ind == si + 2 {
                    apply_step_key(last, s);
                } else if ind == si + 4 && (s.starts_with("key:") || s.starts_with("mode:")) {
                    apply_step_key(last, s);
                }
            } else if ind <= si && !s.starts_with("- ") {
                step_indent = None;
            }
        }
    }
    steps
}

fn apply_step_key(step: &mut StepMeta, kv: &str) {
    if let Some(v) = kv.strip_prefix("uses:") {
        step.uses = v.split('#').next().unwrap_or("").trim().to_string();
    } else if let Some(v) = kv.strip_prefix("if:") {
        step.if_expr = Some(v.split(" #").next().unwrap_or("").trim().to_string());
    } else if let Some(v) = kv.strip_prefix("key:") {
        step.key = Some(v.trim().to_string());
    } else if let Some(v) = kv.strip_prefix("mode:") {
        step.warm_mode = Some(unquote(v.split(" #").next().unwrap_or("")).to_string());
    } else if let Some(v) = kv.strip_prefix("name:") {
        step.name = Some(unquote(v.split(" #").next().unwrap_or("")).to_string());
    } else if let Some(v) = kv.strip_prefix("continue-on-error:") {
        step.continue_on_error = Some(v.split(" #").next().unwrap_or("").trim().to_string());
    }
}

fn has_top_level_or(expr: &str) -> bool {
    let bytes = expr.as_bytes();
    let mut depth = 0i32;
    let mut in_single = false;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\'' => in_single = !in_single,
            b'(' if !in_single => depth += 1,
            b')' if !in_single => depth -= 1,
            b'|' if !in_single && depth == 0 && i + 1 < bytes.len() && bytes[i + 1] == b'|' => {
                return true;
            }
            _ => {}
        }
        i += 1;
    }
    false
}

/// True when a save job's `if:` requires `github.ref == 'refs/heads/main'`
/// without a top-level `||` escape hatch.
pub(crate) fn save_job_if_guarded(expr: &str) -> bool {
    let norm: String = expr
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .replace('"', "'");
    let bare = norm.trim_start_matches("${{").trim_end_matches("}}").trim();
    (bare.contains("github.ref == 'refs/heads/main'")
        || bare.contains("'refs/heads/main' == github.ref"))
        && !has_top_level_or(bare)
}

#[derive(Debug, Default)]
struct WarmJobInfo {
    id: String,
    if_expr: Option<String>,
    permissions: Vec<(String, String)>,
    steps: Vec<StepMeta>,
}

struct ParsedWarmWorkflow {
    workflow_permissions: Vec<(String, String)>,
    jobs: Vec<WarmJobInfo>,
}

fn parse_perm_kv(s: &str) -> Option<(String, String)> {
    let (k, v) = s.split_once(':')?;
    let key = k.trim().to_string();
    let val = v.split('#').next().unwrap_or("").trim().to_string();
    if key.is_empty() || val.is_empty() {
        return None;
    }
    Some((key, val))
}

fn parse_repo_cache_workflow(content: &str) -> ParsedWarmWorkflow {
    let mut workflow_permissions = Vec::new();
    let mut jobs = Vec::new();

    let mut in_top_perms = false;
    let mut in_jobs = false;
    let mut current_job: Option<WarmJobInfo> = None;
    let mut in_job_perms = false;
    let mut in_job_steps = false;
    let mut step_indent: Option<usize> = None;

    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        let ind = indent(line);
        let s = strip(line);
        if s.is_empty() || s.starts_with('#') {
            continue;
        }

        if ind == 0 {
            in_top_perms = false;
            if let Some(j) = current_job.take() {
                jobs.push(j);
            }
            in_jobs = false;
            in_job_perms = false;
            in_job_steps = false;
            step_indent = None;

            if s.starts_with("permissions:") {
                if strip(&s["permissions:".len()..]).is_empty() {
                    in_top_perms = true;
                }
            } else if s.starts_with("jobs:") && strip(&s["jobs:".len()..]).is_empty() {
                in_jobs = true;
            }
            continue;
        }

        if in_top_perms {
            if let Some(kv) = parse_perm_kv(s) {
                workflow_permissions.push(kv);
            }
            continue;
        }

        if !in_jobs {
            continue;
        }

        if ind == 2 && s.ends_with(':') {
            if let Some(j) = current_job.take() {
                jobs.push(j);
            }
            let id = s.trim_end_matches(':').trim().to_string();
            current_job = Some(WarmJobInfo {
                id,
                ..WarmJobInfo::default()
            });
            in_job_perms = false;
            in_job_steps = false;
            step_indent = None;
            continue;
        }

        let Some(job) = current_job.as_mut() else {
            continue;
        };

        if ind == 4 {
            in_job_perms = false;
            in_job_steps = false;
            step_indent = None;
            if let Some(rest) = s.strip_prefix("if:") {
                job.if_expr = Some(rest.split(" #").next().unwrap_or("").trim().to_string());
            } else if s.starts_with("permissions:") && strip(&s["permissions:".len()..]).is_empty()
            {
                in_job_perms = true;
            } else if s.starts_with("steps:") && strip(&s["steps:".len()..]).is_empty() {
                in_job_steps = true;
            }
            continue;
        }

        if in_job_perms && ind >= 6 {
            if let Some(kv) = parse_perm_kv(s) {
                job.permissions.push(kv);
            }
            continue;
        }

        if in_job_steps && ind >= 6 {
            if let Some(rest) = s.strip_prefix("- ") {
                if step_indent.is_none() || step_indent == Some(ind) {
                    step_indent = Some(ind);
                    job.steps.push(StepMeta::default());
                    let last = job.steps.last_mut().unwrap();
                    if rest.contains("cache_capacity_guard.py") {
                        last.runs_capacity_guard = true;
                    }
                    if rest.contains("cache_prune.py") {
                        last.runs_prune = true;
                    }
                    apply_step_key(last, rest);
                    continue;
                }
            }
            if let (Some(si), Some(last)) = (step_indent, job.steps.last_mut()) {
                if ind > si {
                    if s.contains("cache_capacity_guard.py") {
                        last.runs_capacity_guard = true;
                    }
                    if s.contains("cache_prune.py") {
                        last.runs_prune = true;
                    }
                    if ind == si + 2 {
                        apply_step_key(last, s);
                    } else if ind == si + 4 && (s.starts_with("key:") || s.starts_with("mode:")) {
                        apply_step_key(last, s);
                    }
                }
            }
        }
    }

    if let Some(j) = current_job.take() {
        jobs.push(j);
    }

    ParsedWarmWorkflow {
        workflow_permissions,
        jobs,
    }
}

/// Validate `.github/workflows/bazel-repo-cache.yaml` split verify/save jobs,
/// `actions: write` isolation, and `refs/heads/main` gating.
pub(crate) fn repo_cache_warm_workflow_problems(content: &str) -> Vec<(String, String, String)> {
    let mut problems = Vec::new();
    let parsed = parse_repo_cache_workflow(content);

    for v in yaml_values_of(content, "cache-save") {
        if v != "false" {
            problems.push((
                format!("cache-save: {}", v),
                "cache-save: false".to_string(),
                "setup-bazel inside bazel-repo-cache.yaml must not auto-save; only the verified actions/cache/save step may write".to_string(),
            ));
        }
    }
    for v in yaml_values_of(content, "repository-cache") {
        if v != "false" {
            problems.push((
                format!("repository-cache: {}", v),
                "repository-cache: false".to_string(),
                "bazel-repo-cache.yaml must start from an empty repository cache instead of restoring via setup-bazel".to_string(),
            ));
        }
    }

    if parsed
        .workflow_permissions
        .iter()
        .any(|(k, v)| k == "actions" && v == "write")
    {
        problems.push((
            "workflow permissions actions: write".to_string(),
            "workflow permissions actions: read".to_string(),
            "top-level workflow permissions must never grant actions: write; only the main-only save jobs may hold actions: write".to_string(),
        ));
    }

    let mut save_jobs = 0usize;
    let mut verify_jobs = 0usize;

    for job in &parsed.jobs {
        let has_save_step = job.steps.iter().any(|s| {
            s.uses.starts_with("actions/cache/save@") || s.uses.starts_with("actions/cache@")
        });
        let has_prune_step = job.steps.iter().any(|s| s.runs_prune);
        let warm_modes: Vec<&str> = job
            .steps
            .iter()
            .filter(|s| s.uses == "./.github/actions/bazel-repo-cache-warm")
            .map(|s| s.warm_mode.as_deref().unwrap_or(""))
            .collect();
        let calls_warm_save = warm_modes.iter().any(|&m| m != "verify");
        let is_save_job = has_save_step || has_prune_step || calls_warm_save;
        let is_verify_job =
            job.id.contains("verify") || (!calls_warm_save && warm_modes.contains(&"verify"));
        let has_actions_write = job
            .permissions
            .iter()
            .any(|(k, v)| k == "actions" && v == "write");

        if is_save_job {
            save_jobs += 1;
        }
        if is_verify_job {
            verify_jobs += 1;
        }

        if has_actions_write {
            if is_verify_job {
                problems.push((
                    format!("{} permissions actions: write", job.id),
                    "actions: read".to_string(),
                    "verify jobs must never hold actions: write".to_string(),
                ));
            }
            if !job.if_expr.as_deref().is_some_and(save_job_if_guarded) {
                problems.push((
                    format!(
                        "{} if: {}",
                        job.id,
                        job.if_expr.as_deref().unwrap_or("unset")
                    ),
                    "if containing github.ref == 'refs/heads/main'".to_string(),
                    "any job holding actions: write must be gated to refs/heads/main so PRs and branch dispatches never hold write power".to_string(),
                ));
            }
        }

        if is_save_job {
            if !job.if_expr.as_deref().is_some_and(save_job_if_guarded) {
                problems.push((
                    format!(
                        "{} if: {}",
                        job.id,
                        job.if_expr.as_deref().unwrap_or("unset")
                    ),
                    "if containing github.ref == 'refs/heads/main'".to_string(),
                    "save and prune jobs must only run on refs/heads/main (never on pull_request or branch workflow_dispatch)".to_string(),
                ));
            }
            let exact_save_perms = job.permissions.len() == 2
                && job
                    .permissions
                    .iter()
                    .any(|(k, v)| k == "actions" && v == "write")
                && job
                    .permissions
                    .iter()
                    .any(|(k, v)| k == "contents" && v == "read");
            if !exact_save_perms {
                problems.push((
                    format!("{} permissions: {:?}", job.id, job.permissions),
                    "contents: read, actions: write".to_string(),
                    "save jobs must declare exact permissions contents: read and actions: write"
                        .to_string(),
                ));
            }
        }

        if is_verify_job && (has_save_step || has_prune_step || calls_warm_save) {
            problems.push((
                format!("{} saves or prunes caches", job.id),
                "mode: verify without save or prune".to_string(),
                "verify jobs must never save or delete caches".to_string(),
            ));
        }
    }

    if save_jobs < 2 {
        problems.push((
            format!("{} save job(s)", save_jobs),
            "2 save jobs (warm-linux-save and warm-macos-save)".to_string(),
            "bazel-repo-cache.yaml must define main-only save jobs for both Linux and macOS"
                .to_string(),
        ));
    }
    if verify_jobs < 2 {
        problems.push((
            format!("{} verify job(s)", verify_jobs),
            "2 verify jobs (warm-linux-verify and warm-macos-verify)".to_string(),
            "bazel-repo-cache.yaml must define read-only verify jobs for both Linux and macOS"
                .to_string(),
        ));
    }

    problems
}

/// Validate `.github/actions/bazel-repo-cache-warm/action.yml` shared composite.
pub(crate) fn repo_cache_warm_composite_problems(content: &str) -> Vec<(String, String, String)> {
    let mut problems = Vec::new();
    let steps = composite_steps(content);

    if content
        .lines()
        .map(strip)
        .any(|l| !l.starts_with('#') && l.starts_with("permissions:"))
    {
        problems.push((
            "permissions: in composite".to_string(),
            "no permissions block in composite".to_string(),
            "composite actions must not declare permissions; permissions belong to the calling job"
                .to_string(),
        ));
    }

    let cache_saves = yaml_values_of(content, "cache-save");
    if cache_saves.is_empty() {
        problems.push((
            "cache-save: unset".to_string(),
            "cache-save: ${{ inputs.mode == 'save' }}".to_string(),
            "bazel-repo-cache-warm must set cache-save: ${{ inputs.mode == 'save' }} so only main save jobs refresh the bazelisk cache".to_string(),
        ));
    } else {
        for v in cache_saves {
            let norm: String = v.split_whitespace().collect::<Vec<_>>().join(" ");
            if norm != "${{ inputs.mode == 'save' }}" {
                problems.push((
                    format!("cache-save: {}", v),
                    "cache-save: ${{ inputs.mode == 'save' }}".to_string(),
                    "bazel-repo-cache-warm must set cache-save: ${{ inputs.mode == 'save' }} so verify jobs never save and save jobs keep bazelisk fresh".to_string(),
                ));
            }
        }
    }
    let bazelisk_caches = yaml_values_of(content, "bazelisk-cache");
    if bazelisk_caches.is_empty() {
        problems.push((
            "bazelisk-cache: unset".to_string(),
            "bazelisk-cache: true".to_string(),
            "bazel-repo-cache-warm must enable bazelisk-cache: true so the bazelisk binary cache stays fresh".to_string(),
        ));
    } else {
        for v in bazelisk_caches {
            if v != "true" {
                problems.push((
                    format!("bazelisk-cache: {}", v),
                    "bazelisk-cache: true".to_string(),
                    "bazel-repo-cache-warm must keep bazelisk-cache: true so the bazelisk binary cache stays fresh".to_string(),
                ));
            }
        }
    }
    for v in yaml_values_of(content, "repository-cache") {
        if v != "false" {
            problems.push((
                format!("repository-cache: {}", v),
                "repository-cache: false".to_string(),
                "bazel-repo-cache-warm must start from an empty repository cache instead of restoring via setup-bazel".to_string(),
            ));
        }
    }

    if !content.contains("--repo_contents_cache=") {
        problems.push((
            "missing --repo_contents_cache=".to_string(),
            "--repo_contents_cache= outside REPO".to_string(),
            "warm composite must keep extracted contents outside the saved archive directory"
                .to_string(),
        ));
    }
    if !content.contains("--repository_disable_download") {
        problems.push((
            "missing --repository_disable_download".to_string(),
            "--repository_disable_download".to_string(),
            "warm composite must prove offline completeness before saving".to_string(),
        ));
    }

    let lookup_steps: Vec<&StepMeta> = steps
        .iter()
        .filter(|s| s.uses.starts_with("actions/cache/restore@"))
        .collect();
    if lookup_steps.is_empty()
        || !lookup_steps.iter().all(|s| {
            s.key.as_deref().is_some_and(has_full_repo_hash_key)
                && s.if_expr
                    .as_deref()
                    .is_some_and(|e| e.contains("inputs.mode == 'save'"))
        })
    {
        problems.push((
            "missing or unguarded lookup step".to_string(),
            "actions/cache/restore lookup-only with inputs.mode == 'save' and -repository-full- key".to_string(),
            "warm composite must check for an existing exact `-repository-full-` entry in save mode".to_string(),
        ));
    }

    let save_indices: Vec<usize> = steps
        .iter()
        .enumerate()
        .filter(|(_, s)| s.uses.starts_with("actions/cache/save@"))
        .map(|(i, _)| i)
        .collect();
    if save_indices.len() != 1 {
        problems.push((
            format!("{} actions/cache/save step(s)", save_indices.len()),
            "1 actions/cache/save step".to_string(),
            "warm composite must contain one verified actions/cache/save step".to_string(),
        ));
        return problems;
    }

    let save_idx = save_indices[0];
    let save_step = &steps[save_idx];
    let save_if_ok = save_step.if_expr.as_deref().is_some_and(|e| {
        e.contains("inputs.mode == 'save'")
            && e.contains("cache-hit != 'true'")
            && e.contains("allow_save == 'true'")
    });
    if !save_if_ok {
        problems.push((
            format!(
                "save if: {}",
                save_step.if_expr.as_deref().unwrap_or("unset")
            ),
            "if: inputs.mode == 'save' && ...cache-hit != 'true' && ...allow_save == 'true'"
                .to_string(),
            "save step must run only in save mode on a cache miss when capacity guard allows it"
                .to_string(),
        ));
    }
    if !save_step.key.as_deref().is_some_and(has_full_repo_hash_key) {
        problems.push((
            format!("save key: {}", save_step.key.as_deref().unwrap_or("unset")),
            "setup-bazel-1-...-repository-full-${{ hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion') }}".to_string(),
            "warm composite must save under the `-repository-full-` key matching setup-bazel"
                .to_string(),
        ));
    }

    let guard_ok = save_idx > 0 && {
        let guard = &steps[save_idx - 1];
        guard.name.as_deref() == Some("Check Actions cache capacity before saving")
            && guard.runs_capacity_guard
            && guard.continue_on_error.as_deref() != Some("true")
            && guard.if_expr.as_deref().is_some_and(|e| {
                e.contains("inputs.mode == 'save'") && e.contains("cache-hit != 'true'")
            })
    };
    if !guard_ok {
        problems.push((
            "missing or misplaced capacity guard".to_string(),
            "Check Actions cache capacity before saving (cache_capacity_guard.py) immediately before actions/cache/save".to_string(),
            "actions/cache/save in bazel-repo-cache-warm must be immediately preceded by the capacity guard".to_string(),
        ));
    }

    let prune_indices: Vec<usize> = steps
        .iter()
        .enumerate()
        .filter(|(_, s)| s.runs_prune)
        .map(|(i, _)| i)
        .collect();
    if prune_indices.len() != 1 {
        problems.push((
            format!("{} prune step(s)", prune_indices.len()),
            "1 cache_prune.py step after actions/cache/save".to_string(),
            "warm composite must confirm and prune superseded entries after saving".to_string(),
        ));
    } else {
        let prune_idx = prune_indices[0];
        let prune_step = &steps[prune_idx];
        if prune_idx <= save_idx {
            problems.push((
                "prune runs before save".to_string(),
                "prune step strictly after actions/cache/save".to_string(),
                "superseded entries must never be deleted before the new entry is saved and confirmed".to_string(),
            ));
        }
        let prune_if_ok = prune_step.if_expr.as_deref().is_some_and(|e| {
            e.contains("inputs.mode == 'save'")
                && e.contains("cache-hit != 'true'")
                && e.contains("allow_save == 'true'")
        });
        if !prune_if_ok {
            problems.push((
                format!(
                    "prune if: {}",
                    prune_step.if_expr.as_deref().unwrap_or("unset")
                ),
                "if: inputs.mode == 'save' && ...cache-hit != 'true' && ...allow_save == 'true'"
                    .to_string(),
                "prune step must run only after an allowed save in save mode".to_string(),
            ));
        }
    }

    problems
}

/// Validate that any file OTHER than `.github/workflows/bazel-repo-cache.yaml`,
/// `.github/actions/bazel-repo-cache-warm/action.yml`, and
/// `.github/actions/pins/action.yml` does not save via `actions/cache`,
/// `actions/cache/save`, or `cache-save: != false` (while `actions/cache/restore`
/// remains allowed everywhere).
pub(crate) fn unexpected_cache_save_problems(
    rel: &str,
    content: &str,
) -> Vec<(String, String, String)> {
    let mut problems = Vec::new();
    for v in yaml_values_of(content, "cache-save") {
        if v != "false" {
            problems.push((
                format!("cache-save: {}", v),
                "cache-save: false (or omit)".to_string(),
                "only .github/workflows/bazel-repo-cache.yaml may save the Bazel repository cache"
                    .to_string(),
            ));
        }
    }
    let steps = composite_steps(content);
    let save_steps: Vec<&StepMeta> = steps
        .iter()
        .filter(|s| {
            s.uses.starts_with("actions/cache/save@") || s.uses.starts_with("actions/cache@")
        })
        .collect();
    if !save_steps.is_empty() {
        // Generated presubmit.yaml saves the non-Bazel pipeline-rdeps-map JSON.
        let allowed_presubmit_rdeps = rel == ".github/workflows/presubmit.yaml"
            && save_steps.iter().all(|s| {
                s.uses.starts_with("actions/cache/save@")
                    && s.key
                        .as_deref()
                        .is_some_and(|k| k.starts_with("pipeline-rdeps-map-v1-"))
            });
        // LLVM toolchain extraction cache has its own MAY_SAVE conformance check (section 1a).
        let allowed_llvm_composite = rel == ".github/actions/llvm-cache-restore/action.yml"
            && save_steps
                .iter()
                .all(|s| s.uses.starts_with("actions/cache@"));
        // ESP32 PlatformIO toolchain cache in vitruvian-deck workflows.
        let allowed_platformio_cache = (rel == ".github/workflows/delivery-vitruvian-deck.yaml"
            || rel == ".github/workflows/iot-vitruvian-deck.yaml")
            && save_steps.iter().all(|s| {
                s.uses.starts_with("actions/cache@")
                    && s.key
                        .as_deref()
                        .is_some_and(|k| k.starts_with("platformio-"))
            });
        if !allowed_presubmit_rdeps && !allowed_llvm_composite && !allowed_platformio_cache {
            let found_uses = save_steps
                .iter()
                .map(|s| s.uses.split('@').next().unwrap_or(&s.uses))
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>()
                .join(", ");
            problems.push((
                found_uses,
                "only in .github/workflows/bazel-repo-cache.yaml".to_string(),
                "only bazel-repo-cache.yaml (and its composite) may call actions/cache or actions/cache/save; other workflows must use actions/cache/restore".to_string(),
            ));
        }
    }
    problems
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
            "steps.mode.outputs.readonly == 'true' && runner.environment == 'github-hosted'",
            "the read-only restore must branch on the save decision (or a job barred from saving ends up with no restore, or with both) and run only on GitHub-hosted runners: a self-hosted queue runner keeps the extracted toolchain on its shared volume, so the 2.3 GB download is thrown away after a median 197 s on the home line (27 queue plan jobs, 2026-11-16)",
        ),
    ];
    for (uses, want, why) in checks {
        let matching: Vec<&StepMeta> = steps.iter().filter(|s| s.uses.starts_with(uses)).collect();
        if matching.len() != 1 {
            problems.push((
                format!("{} {} step(s)", matching.len(), uses.trim_end_matches('@')),
                format!("exactly 1, if: {}", want),
                why.to_string(),
            ));
            continue;
        }
        let got = matching[0].if_expr.as_deref().map(norm).unwrap_or_default();
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

    // 1. setup-bazel/action.yml is restore-only (never saves; restores -repository-full- on hosted runners).
    let setup_rel = ".github/actions/setup-bazel/action.yml";
    match fs::read_to_string(format!("{}/setup-bazel/action.yml", actions_dir)) {
        Ok(content) => {
            for (found, want, why) in repository_restore_problems(&content) {
                ctx.emit_fail(
                    "cachesave", setup_rel, &found, &want, &why,
                    "keep setup-bazel restore-only (cache-save: false, repository-cache: false) and restore -repository-full- on GitHub-hosted runners",
                );
                ok = false;
            }
        }
        Err(_) => {
            ctx.emit_fail(
                "cachesave",
                setup_rel,
                "missing",
                "restore-only setup-bazel",
                "the shared setup-bazel composite is missing",
                "restore .github/actions/setup-bazel/action.yml",
            );
            ok = false;
        }
    }

    // 1a. llvm-cache-restore/action.yml saves only on GitHub-hosted main.
    let llvm_rel = ".github/actions/llvm-cache-restore/action.yml";
    match fs::read_to_string(format!("{}/llvm-cache-restore/action.yml", actions_dir)) {
        Ok(content) => {
            match yaml_value_of(&content, "MAY_SAVE") {
                Some(v) if cache_save_expr_guarded(&v) => {}
                found => {
                    ctx.emit_fail(
                        "cachesave", llvm_rel, found.as_deref().unwrap_or("unset"),
                        "main && github-hosted",
                        "LLVM caches would be saved from merge-queue/PR refs or self-hosted runners",
                        "set 'MAY_SAVE: ${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}'",
                    );
                    ok = false;
                }
            }
            for problem in llvm_restore_branch_problems(&content) {
                ctx.emit_fail(
                    "cachesave", llvm_rel, &problem.0, &problem.1, &problem.2,
                    "branch both restore steps on steps.mode.outputs.readonly: `!= 'true'` on actions/cache, `== 'true'` on actions/cache/restore",
                );
                ok = false;
            }
        }
        Err(_) => {
            ctx.emit_fail(
                "cachesave", llvm_rel, "missing", "guarded save",
                "the shared LLVM cache composite is gone, so nothing bounds where its caches are saved",
                "restore .github/actions/llvm-cache-restore/action.yml",
            );
            ok = false;
        }
    }

    // 1b. .github/workflows/bazel-repo-cache.yaml is the ONLY writer of the Bazel repository cache.
    let warm_rel = ".github/workflows/bazel-repo-cache.yaml";
    match fs::read_to_string(format!("{}/bazel-repo-cache.yaml", ctx.workflows_dir)) {
        Ok(content) => {
            for (found, want, why) in repo_cache_warm_workflow_problems(&content) {
                ctx.emit_fail(
                    "cachesave", warm_rel, &found, &want, &why,
                    "split verify/save jobs, grant actions: write only to main save jobs, and call ./.github/actions/bazel-repo-cache-warm",
                );
                ok = false;
            }
        }
        Err(_) => {
            ctx.emit_fail(
                "cachesave", warm_rel, "missing", "verified warm workflow",
                "the dedicated repository cache warm workflow is gone, so nothing writes -repository-full-",
                "restore .github/workflows/bazel-repo-cache.yaml",
            );
            ok = false;
        }
    }

    // 1c. .github/actions/bazel-repo-cache-warm/action.yml shares the warm/verify/save steps.
    let warm_comp_rel = ".github/actions/bazel-repo-cache-warm/action.yml";
    match fs::read_to_string(format!("{}/bazel-repo-cache-warm/action.yml", actions_dir)) {
        Ok(content) => {
            for (found, want, why) in repo_cache_warm_composite_problems(&content) {
                ctx.emit_fail(
                    "cachesave", warm_comp_rel, &found, &want, &why,
                    "keep bazel-repo-cache-warm permission-free, offline-verified, capacity-guarded, and pruning only after confirmed save",
                );
                ok = false;
            }
        }
        Err(_) => {
            ctx.emit_fail(
                "cachesave",
                warm_comp_rel,
                "missing",
                "warm composite",
                "the shared bazel-repo-cache-warm composite action is missing",
                "restore .github/actions/bazel-repo-cache-warm/action.yml",
            );
            ok = false;
        }
    }

    // 2. No other workflow or action bypasses setup-bazel or saves caches.
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
        let rel = ctx.rel(f);
        let content = match fs::read_to_string(f) {
            Ok(c) => c,
            Err(_) => continue,
        };
        if rel != warm_rel && rel != warm_comp_rel && uses_setup_bazel_directly(&content) {
            ctx.emit_fail(
                "cachesave",
                &rel,
                "bazel-contrib/setup-bazel",
                "./.github/actions/setup-bazel",
                "calls setup-bazel directly instead of the restore-only composite action",
                "use './.github/actions/setup-bazel' instead",
            );
            ok = false;
        }
        if rel != warm_rel && rel != warm_comp_rel && rel != ".github/actions/pins/action.yml" {
            for (found, want, why) in unexpected_cache_save_problems(&rel, &content) {
                ctx.emit_fail(
                    "cachesave", &rel, &found, &want, &why,
                    "remove actions/cache, actions/cache/save, and cache-save: true; use actions/cache/restore",
                );
                ok = false;
            }
        }
    }

    if ok {
        ctx.emit_ok(
            "cachesave", ".github", "bazel-repo-cache.yaml only", "-repository-full-",
            "only bazel-repo-cache.yaml saves the Bazel repository cache; setup-bazel and all other workflows restore only",
        );
    }
}

// ---------------------------------------------------------------------------
// CHECK: CI Go module fetches fall back when proxy.golang.org fails
// ---------------------------------------------------------------------------
//
// gazelle's go_repository fetches every go.mod dependency with `go mod
// download` (its fetch_repo tool), outside Bazel's downloader, so Bazel's
// retry flags and the restored repository cache never cover it. On 2026-11-01
// a proxy.golang.org "TLS handshake timeout" failed the macOS vitruvian-courier units
// twice in the merge queue (#4187). setup-bazel now sets a GOPROXY list joined
// with `|`, which Go falls through on ANY error; Go's default joins with `,`,
// which falls through only on a 404/410 answer. This check keeps the pipe.

/// Why a GOPROXY value does not fall back on a network error, or None when
/// it does: two or more distinct entries, joined only with `|`.
pub(crate) fn goproxy_fallback_problem(value: &str) -> Option<String> {
    if value.contains(',') {
        return Some(
            "a ',' falls through only on a 404/410 answer, so a timeout still fails the fetch"
                .to_string(),
        );
    }
    let entries: Vec<&str> = value.split('|').map(str::trim).collect();
    if entries.iter().any(|e| e.is_empty() || *e == "off") {
        return Some("an empty or 'off' entry ends the list".to_string());
    }
    let distinct: BTreeSet<&str> = entries.iter().copied().collect();
    if distinct.len() < 2 {
        return Some(
            "needs a second, different entry: Go tries the same URL only once, so repeating it is not a retry"
                .to_string(),
        );
    }
    None
}

/// The value of the first `--repo_env=GOPROXY=` on a non-comment line.
pub(crate) fn repo_env_goproxy(content: &str) -> Option<String> {
    const FLAG: &str = "--repo_env=GOPROXY=";
    content
        .lines()
        .map(strip)
        .filter(|l| !l.starts_with('#'))
        .find_map(|l| {
            let at = l.find(FLAG)?;
            let rest = &l[at + FLAG.len()..];
            Some(rest.split_whitespace().next().unwrap_or("").to_string())
        })
}

pub fn check_goproxy_fallback(ctx: &Context) {
    let rel = ".github/actions/setup-bazel/action.yml";
    let content =
        match fs::read_to_string(format!("{}/{}", ctx.root, rel)) {
            Ok(c) => c,
            Err(_) => {
                ctx.emit_fail(
                "goproxy", rel, "missing", "--repo_env=GOPROXY=https://proxy.golang.org|direct",
                "the shared setup action is gone, so nothing sets the Go module fallback for CI",
                "restore the composite, or move this check to wherever CI's bazelrc is now written",
            );
                return;
            }
        };
    let want = "--repo_env=GOPROXY=https://proxy.golang.org|direct";
    match repo_env_goproxy(&content) {
        None => ctx.emit_fail(
            "goproxy", rel, "unset", want,
            "Go's default GOPROXY (',' separated) fails a go_repository fetch on any proxy.golang.org timeout, ejecting the merge-queue head (#4187)",
            &format!("add 'common {}' to the action's bazelrc", want),
        ),
        Some(v) => match goproxy_fallback_problem(&v) {
            None => ctx.emit_ok(
                "goproxy", rel, &v, want,
                "go_repository fetches fall through to the next source on a proxy timeout; go.sum still pins the bytes",
            ),
            Some(why) => ctx.emit_fail(
                "goproxy", rel, &v, want, &why,
                &format!("set 'common {}'", want),
            ),
        },
    }
}

// ---------------------------------------------------------------------------
// CHECK: CI gate list consistency
// ---------------------------------------------------------------------------

pub fn check_ci_gate_lists_match(ctx: &Context) {
    let deploy_affected = format!("{}/tools/ci/src/deploy_affected/lib.rs", ctx.root);
    let affected_targets = format!("{}/tools/ci/src/affected_targets/lib.rs", ctx.root);

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
                    "tools/ci gate allowlists",
                    "identical",
                    "identical",
                    "the deploy gate and the test gate agree on global-impact paths",
                );
            } else {
                ctx.emit_fail(
                    "gate",
                    "tools/ci gate allowlists",
                    "diverged",
                    "identical",
                    "the deploy gate (tools/ci/src/deploy_affected/lib.rs) and the test gate (tools/ci/src/affected_targets/lib.rs) disagree on the global-impact allowlist, so CI and deploy disagree about what a change can affect",
                    "make the '^tools/(...)' patterns identical in both files",
                );
            }
        }
        _ => {
            ctx.emit_fail(
                "gate",
                "tools/ci gate allowlists",
                "pattern not found",
                "one per file",
                "could not locate the global-impact allowlist in one of the gate scripts - the guard cannot verify them",
                "check the '^tools/(...)' pattern still exists in both tools/ci/src/deploy_affected/lib.rs and tools/ci/src/affected_targets/lib.rs",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// CHECK: container image workflow triggers (*-image.yaml)
// ---------------------------------------------------------------------------
//
// Container-image workflows (e.g. vitruvian-slack-mcp-image.yaml) build with
// Docker/Cargo/pnpm rather than Bazel. Using a broad `<app>/**` path filter
// without negations causes Bazel BUILD edits, docs updates, or chart edits
// (e.g. #5095 removing a visibility line in apps/mcp/vitruvian-slack-mcp/BUILD)
// to publish new image digests and open spurious image-bump PRs (#5117).

/// Strip an unquoted trailing YAML comment (` # ...` or `#...` at start).
fn strip_yaml_inline_comment(s: &str) -> &str {
    let bytes = s.as_bytes();
    let mut in_single = false;
    let mut in_double = false;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\'' if !in_double => in_single = !in_single,
            b'"' if !in_single => in_double = !in_double,
            b'#' if !in_single && !in_double => {
                if i == 0 || bytes[i - 1].is_ascii_whitespace() {
                    return s[..i].trim_end();
                }
            }
            _ => {}
        }
        i += 1;
    }
    s.trim()
}

/// Extract `(paths, has_paths_ignore)` for `on.<event>` (`push` or `pull_request`).
pub(crate) fn extract_event_paths(content: &str, event: &str) -> (Vec<String>, bool) {
    let mut in_on = false;
    let mut event_indent: Option<usize> = None;
    let mut in_event = false;
    let mut paths_indent: Option<usize> = None;
    let mut has_paths_ignore = false;
    let mut out = Vec::new();
    let event_key = format!("{}:", event);

    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        let ind = indent(line);
        let trimmed = strip(line);
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if line.starts_with("on:") && strip(&line["on:".len()..]).is_empty() {
            in_on = true;
            continue;
        }
        if !in_on {
            continue;
        }
        if ind == 0 {
            break;
        }
        if event_indent.is_none() {
            event_indent = Some(ind);
        }
        if Some(ind) == event_indent {
            in_event = trimmed.starts_with(&event_key);
            paths_indent = None;
            continue;
        }
        if !in_event {
            continue;
        }
        if let Some(pi) = paths_indent {
            if ind > pi && trimmed.starts_with("- ") {
                let item = strip_yaml_inline_comment(trimmed.strip_prefix("- ").unwrap_or(""));
                let clean = unquote(item).to_string();
                if !clean.is_empty() {
                    out.push(clean);
                }
                continue;
            }
            if ind <= pi {
                paths_indent = None;
            }
        }
        if trimmed.starts_with("paths-ignore:") {
            has_paths_ignore = true;
        } else if trimmed.starts_with("paths:") {
            paths_indent = Some(ind);
        }
    }
    (out, has_paths_ignore)
}

fn seg_match(pat: &[u8], text: &[u8]) -> bool {
    let (mut pi, mut ti) = (0usize, 0usize);
    let (mut star_p, mut star_t) = (None, 0usize);
    while ti < text.len() {
        if pi < pat.len() && (pat[pi] == b'?' || pat[pi] == text[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < pat.len() && pat[pi] == b'*' {
            star_p = Some(pi);
            star_t = ti;
            pi += 1;
        } else if let Some(sp) = star_p {
            pi = sp + 1;
            star_t += 1;
            ti = star_t;
        } else {
            return false;
        }
    }
    while pi < pat.len() && pat[pi] == b'*' {
        pi += 1;
    }
    pi == pat.len()
}

fn match_segments(pat: &[&str], path: &[&str]) -> bool {
    if pat.is_empty() {
        return path.is_empty();
    }
    if pat[0] == "**" {
        if pat.len() == 1 {
            // Trailing `/**` matches one or more path segments underneath the directory.
            return !path.is_empty();
        }
        if match_segments(&pat[1..], path) {
            return true;
        }
        return !path.is_empty() && match_segments(pat, &path[1..]);
    }
    if path.is_empty() {
        return false;
    }
    seg_match(pat[0].as_bytes(), path[0].as_bytes()) && match_segments(&pat[1..], &path[1..])
}

/// Evaluate a GitHub Actions `paths:` filter list against a repo-relative path.
pub(crate) fn workflow_paths_match(patterns: &[String], candidate: &str) -> bool {
    let cand_segs: Vec<&str> = candidate.split('/').collect();
    let mut matched = false;
    for raw in patterns {
        let (is_neg, pat) = match raw.strip_prefix('!') {
            Some(p) => (true, p),
            None => (false, raw.as_str()),
        };
        let pat_segs: Vec<&str> = pat.split('/').collect();
        if match_segments(&pat_segs, &cand_segs) {
            matched = !is_neg;
        }
    }
    matched
}

fn derive_image_roots(patterns: &[String]) -> Vec<String> {
    let mut roots = BTreeSet::new();
    for p in patterns {
        if p.starts_with('!') || p.starts_with(".github/workflows/") {
            continue;
        }
        if let Some(dir) = p.strip_suffix("/**") {
            if !dir.is_empty() && !dir.contains('*') {
                roots.insert(dir.to_string());
            }
            continue;
        }
        for suffix in [
            "/Dockerfile",
            "/Cargo.toml",
            "/Cargo.lock",
            "/.dockerignore",
        ] {
            if let Some(dir) = p.strip_suffix(suffix) {
                if !dir.is_empty() && !dir.contains('*') {
                    roots.insert(dir.to_string());
                }
                break;
            }
        }
    }
    roots.into_iter().collect()
}

/// Validate a `*-image.yaml` workflow's `on.push.paths` and `on.pull_request.paths`.
/// Returns `(found, wanted, why)` triples; empty when clean.
pub(crate) fn image_workflow_problems(
    wf_rel: &str,
    content: &str,
) -> Vec<(String, String, String)> {
    let mut problems = Vec::new();
    let (push_paths, push_ignore) = extract_event_paths(content, "push");
    let (pr_paths, pr_ignore) = extract_event_paths(content, "pull_request");

    if push_ignore || pr_ignore {
        problems.push((
            "paths-ignore".to_string(),
            "paths: with ! exclusions".to_string(),
            "workflow uses paths-ignore alongside paths (rejected by actionlint or hides exclusions)".to_string(),
        ));
    }
    if push_paths.is_empty() || pr_paths.is_empty() {
        problems.push((
            format!("push={} pr={}", push_paths.len(), pr_paths.len()),
            "non-empty push.paths and pull_request.paths".to_string(),
            "image workflow runs unconditionally on every push or PR instead of scoping to image inputs".to_string(),
        ));
        return problems;
    }
    if push_paths != pr_paths {
        problems.push((
            "push != pull_request".to_string(),
            "identical paths:".to_string(),
            "push and pull_request paths lists diverged, so PR verification and main publishing trigger on different files".to_string(),
        ));
    }

    if !workflow_paths_match(&push_paths, wf_rel) {
        problems.push((
            format!("{} ignored", wf_rel),
            "matches self".to_string(),
            "workflow file itself does not match its paths filter, so changes to the image build never run".to_string(),
        ));
    }

    let roots = derive_image_roots(&push_paths);
    if roots.is_empty() {
        problems.push((
            "0 app/package roots".to_string(),
            ">=1 image root".to_string(),
            "no app/package root pattern found in push.paths".to_string(),
        ));
        return problems;
    }

    // Verify at least one real build/source path outside .github/workflows matches.
    let mut any_runtime_match = false;
    for p in &push_paths {
        if p.starts_with('!') || p.starts_with(".github/workflows/") {
            continue;
        }
        let probe = if let Some(prefix) = p.strip_suffix("/**") {
            format!("{}/src/main.rs", prefix)
        } else {
            p.clone()
        };
        if workflow_paths_match(&push_paths, &probe) {
            any_runtime_match = true;
            break;
        }
    }
    if !any_runtime_match {
        problems.push((
            "over-negated".to_string(),
            "matches source/Dockerfile".to_string(),
            "paths filter excludes every source and Dockerfile input".to_string(),
        ));
    }

    for root in &roots {
        let mut inert_candidates = vec![
            format!("{}/BUILD", root),
            format!("{}/BUILD.bazel", root),
            format!("{}/OWNERS", root),
            format!("{}/README.md", root),
        ];
        if !root.ends_with("/src") && !root.starts_with("tools/ci/src/") {
            inert_candidates.push(format!("{}/mkdocs.yml", root));
            inert_candidates.push(format!("{}/deploy/chart/Chart.yaml", root));
            inert_candidates.push(format!("{}/deploy/chart/values.yaml", root));
        }
        for cand in inert_candidates {
            if workflow_paths_match(&push_paths, &cand) {
                problems.push((
                    cand,
                    "ignored".to_string(),
                    "non-image file (Bazel BUILD, docs, OWNERS, or Helm chart) triggers an image rebuild and digest bump".to_string(),
                ));
            }
        }
    }

    problems
}

pub fn check_image_workflow_paths(ctx: &Context) {
    if !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }
    let mut count = 0u32;
    for wf in &list_workflows(&ctx.workflows_dir) {
        let wf_name = Path::new(wf)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy();
        if !wf_name.ends_with("-image.yaml") {
            continue;
        }
        count += 1;
        let wf_rel = format!(".github/workflows/{}", wf_name);
        let Ok(content) = fs::read_to_string(wf) else {
            continue;
        };
        let problems = image_workflow_problems(&wf_rel, &content);
        if problems.is_empty() {
            ctx.emit_ok(
                "imgpaths",
                &wf_rel,
                "scoped",
                "push == PR, inert excluded",
                "triggers only on Docker/source inputs; BUILD, docs, OWNERS, and charts excluded",
            );
        } else {
            for (found, want, why) in problems {
                ctx.emit_fail(
                    "imgpaths",
                    &wf_rel,
                    &found,
                    &want,
                    &why,
                    &format!("scope push.paths and pull_request.paths identically in {} and exclude BUILD/OWNERS/docs/deploy", wf_rel),
                );
            }
        }
    }
    if count == 0 {
        ctx.emit_fail(
            "imgpaths",
            ".github/workflows",
            "0 matched",
            ">=1 *-image.yaml",
            "no *-image.yaml workflow found — the filename convention or workflow directory moved",
            "update check_image_workflow_paths in tools/conformance/src/checks/ci.rs",
        );
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

    const SETUP_BAZEL_GOOD: &str = "\
runs:
  using: composite
  steps:
    - name: Restore the Bazel repository cache
      if: ${{ runner.environment == 'github-hosted' }}
      uses: actions/cache/restore@abc # v6
      env:
        SEGMENT_DOWNLOAD_TIMEOUT_MINS: \"4\"
      with:
        path: ${{ steps.repo-cache.outputs.path }}
        key: setup-bazel-1-${{ runner.os == 'macOS' && 'darwin' || 'linux' }}-${{ runner.arch == 'ARM64' && 'arm64' || 'x64' }}-repository-full-${{ hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion') }}
        restore-keys: |
          setup-bazel-1-${{ runner.os == 'macOS' && 'darwin' || 'linux' }}-${{ runner.arch == 'ARM64' && 'arm64' || 'x64' }}-repository-full-
    - uses: bazel-contrib/setup-bazel@abc # 0.19.2
      with:
        repository-cache: false
        cache-save: false
";

    #[test]
    fn repository_restore_accepts_the_bounded_restore() {
        assert_eq!(repository_restore_problems(SETUP_BAZEL_GOOD), Vec::new());
    }

    #[test]
    fn repository_restore_rejects_old_state_and_save_regressions() {
        // Exact pre-stage-2 setup-bazel/action.yml shape must fail every changed invariant.
        let old_state = "\
runs:
  using: composite
  steps:
    - name: Restore the Bazel repository cache
      if: ${{ runner.environment == 'github-hosted' && github.ref != 'refs/heads/main' }}
      uses: actions/cache/restore@abc # v6
      env:
        SEGMENT_DOWNLOAD_TIMEOUT_MINS: \"4\"
      with:
        path: ${{ steps.repo-cache.outputs.path }}
        key: setup-bazel-1-linux-x64-repository-${{ hashFiles('MODULE.bazel', 'WORKSPACE.bazel', 'WORKSPACE.bzlmod', 'WORKSPACE') }}
        restore-keys: |
          setup-bazel-1-linux-x64-repository-
    - uses: bazel-contrib/setup-bazel@abc # 0.19.2
      with:
        repository-cache: ${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}
        cache-save: ${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}
";
        let old_found: Vec<String> = repository_restore_problems(old_state)
            .into_iter()
            .map(|p| p.0)
            .collect();
        assert_eq!(old_found.len(), 5, "{old_found:?}");

        let self_hosted_too = SETUP_BAZEL_GOOD.replace(
            "if: ${{ runner.environment == 'github-hosted' }}",
            "if: ${{ !(github.ref == 'refs/heads/main' && runner.environment == 'github-hosted') }}",
        );
        assert_eq!(
            repository_restore_problems(&self_hosted_too)[0].0,
            "restore if: ${{ !(github.ref == 'refs/heads/main' && runner.environment == 'github-hosted') }}"
        );

        let regain_save = SETUP_BAZEL_GOOD.replace("cache-save: false", "cache-save: true");
        assert_eq!(
            repository_restore_problems(&regain_save)[0].0,
            "cache-save: true"
        );

        let with_cache_save_step = format!(
            "{SETUP_BAZEL_GOOD}    - uses: actions/cache/save@abc\n      with:\n        path: x\n        key: y\n"
        );
        assert!(repository_restore_problems(&with_cache_save_step)
            .iter()
            .any(|p| p.0.contains("actions/cache save step")));
    }

    #[test]
    fn repository_restore_rejects_the_incident_shape() {
        // The 2026-11-06 shape: setup-bazel restores and saves everywhere, nothing else does.
        let incident = "\
    - uses: bazel-contrib/setup-bazel@abc # 0.19.1
      with:
        repository-cache: true
        cache-save: ${{ github.ref == 'refs/heads/main' && runner.environment == 'github-hosted' }}
";
        let found: Vec<String> = repository_restore_problems(incident)
            .into_iter()
            .map(|p| p.0)
            .collect();
        assert!(
            found.contains(&"repository-cache: true".to_string()),
            "{found:?}"
        );
        assert!(
            found.iter().any(|f| f.starts_with("cache-save:")),
            "{found:?}"
        );
        assert!(
            found.contains(&"no actions/cache/restore step".to_string()),
            "{found:?}"
        );
        assert!(
            found.contains(&"SEGMENT_DOWNLOAD_TIMEOUT_MINS: unset (10)".to_string()),
            "{found:?}"
        );
    }

    #[test]
    fn repository_restore_rejects_an_unbounded_or_slow_timeout() {
        let dropped =
            SETUP_BAZEL_GOOD.replace("        SEGMENT_DOWNLOAD_TIMEOUT_MINS: \"4\"\n", "");
        assert_eq!(repository_restore_problems(&dropped).len(), 1);
        let slow = SETUP_BAZEL_GOOD.replace("\"4\"", "\"12\"");
        assert_eq!(
            repository_restore_problems(&slow)[0].0,
            "SEGMENT_DOWNLOAD_TIMEOUT_MINS: 12"
        );
        // `~/` never matched bazel-repo-cache.yaml's $HOME path.
        let tilde = SETUP_BAZEL_GOOD.replace(
            "${{ steps.repo-cache.outputs.path }}",
            "~/.cache/bazel-repo",
        );
        assert_eq!(repository_restore_problems(&tilde)[0].0, "path: ~/...");
        let unguarded =
            SETUP_BAZEL_GOOD.replace("repository-cache: false", "repository-cache: true");
        assert_eq!(
            repository_restore_problems(&unguarded)[0].0,
            "repository-cache: true"
        );
    }

    const WARM_WORKFLOW_GOOD: &str = "\
permissions:
  contents: read
  actions: read

jobs:
  warm-linux-verify:
    if: github.event_name == 'pull_request' || github.ref != 'refs/heads/main'
    permissions:
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@abc
      - uses: ./.github/actions/bazel-repo-cache-warm
        with:
          mode: verify
          platform-os: linux
          platform-arch: x64
          targets: //...
  warm-linux-save:
    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')
    permissions:
      contents: read
      actions: write
    steps:
      - uses: actions/checkout@abc
      - uses: ./.github/actions/bazel-repo-cache-warm
        with:
          mode: save
          platform-os: linux
          platform-arch: x64
          targets: //...
  warm-macos-verify:
    if: github.event_name == 'pull_request' || github.ref != 'refs/heads/main'
    permissions:
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@abc
      - uses: ./.github/actions/bazel-repo-cache-warm
        with:
          mode: verify
          platform-os: darwin
          platform-arch: arm64
          targets: //apps/desktop/...
  warm-macos-save:
    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')
    permissions:
      contents: read
      actions: write
    steps:
      - uses: actions/checkout@abc
      - uses: ./.github/actions/bazel-repo-cache-warm
        with:
          mode: save
          platform-os: darwin
          platform-arch: arm64
          targets: //apps/desktop/...
";

    const WARM_COMPOSITE_GOOD: &str = "\
runs:
  using: composite
  steps:
    - uses: bazel-contrib/setup-bazel@abc # 0.19.2
      with:
        repository-cache: false
        cache-save: ${{ inputs.mode == 'save' }}
        bazelisk-cache: true
    - run: bazel --output_base=\"$OB\" build --nobuild --repository_cache=\"$REPO\" --repo_contents_cache=\"$CONTENTS\" //...
    - run: bazel --output_base=\"$OB2\" build --nobuild --repository_disable_download --repository_cache=\"$REPO\" --repo_contents_cache=\"$CONTENTS2\" //...
    - id: cache-lookup
      if: inputs.mode == 'save'
      uses: actions/cache/restore@abc # v6
      with:
        lookup-only: true
        path: ${{ env.REPO }}
        key: setup-bazel-1-${{ inputs.platform-os }}-${{ inputs.platform-arch }}-repository-full-${{ hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion') }}
    - name: Check Actions cache capacity before saving
      id: capacity-guard
      if: inputs.mode == 'save' && steps.cache-lookup.outputs.cache-hit != 'true'
      shell: bash
      run: |
        python3 .github/actions/setup-bazel/cache_capacity_guard.py
    - id: cache-save
      if: inputs.mode == 'save' && steps.cache-lookup.outputs.cache-hit != 'true' && steps.capacity-guard.outputs.allow_save == 'true'
      uses: actions/cache/save@abc # v6
      with:
        path: ${{ env.REPO }}
        key: setup-bazel-1-${{ inputs.platform-os }}-${{ inputs.platform-arch }}-repository-full-${{ hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion') }}
    - name: Confirm saved cache and prune superseded same-platform entries
      if: inputs.mode == 'save' && steps.cache-lookup.outputs.cache-hit != 'true' && steps.capacity-guard.outputs.allow_save == 'true' && steps.cache-save.outcome == 'success'
      shell: bash
      run: |
        python3 .github/actions/setup-bazel/cache_prune.py
";

    #[test]
    fn repo_cache_warm_workflow_accepts_good_shape_and_rejects_drifts() {
        assert_eq!(
            repo_cache_warm_workflow_problems(WARM_WORKFLOW_GOOD),
            Vec::new()
        );

        let top_level_write = WARM_WORKFLOW_GOOD.replacen("  actions: read", "  actions: write", 1);
        assert!(repo_cache_warm_workflow_problems(&top_level_write)
            .iter()
            .any(|p| p.0 == "workflow permissions actions: write"));

        let branch_dispatch_saves = WARM_WORKFLOW_GOOD.replacen(
            "if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')",
            "if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'",
            1,
        );
        assert!(repo_cache_warm_workflow_problems(&branch_dispatch_saves)
            .iter()
            .any(|p| p.0.starts_with("warm-linux-save if:")));

        let or_bypass = WARM_WORKFLOW_GOOD.replacen(
            "if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')",
            "if: github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch'",
            1,
        );
        assert!(repo_cache_warm_workflow_problems(&or_bypass)
            .iter()
            .any(|p| p.0.starts_with("warm-linux-save if:")));

        let save_without_write = WARM_WORKFLOW_GOOD.replacen(
            "  warm-linux-save:\n    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')\n    permissions:\n      contents: read\n      actions: write",
            "  warm-linux-save:\n    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')\n    permissions:\n      contents: read\n      actions: read",
            1,
        );
        assert!(repo_cache_warm_workflow_problems(&save_without_write)
            .iter()
            .any(|p| p.0.starts_with("warm-linux-save permissions:")));

        let verify_with_write = WARM_WORKFLOW_GOOD.replacen(
            "  warm-linux-verify:\n    if: github.event_name == 'pull_request' || github.ref != 'refs/heads/main'\n    permissions:\n      contents: read\n      actions: read",
            "  warm-linux-verify:\n    if: github.event_name == 'pull_request' || github.ref != 'refs/heads/main'\n    permissions:\n      contents: read\n      actions: write",
            1,
        );
        assert!(repo_cache_warm_workflow_problems(&verify_with_write)
            .iter()
            .any(|p| p.0 == "warm-linux-verify permissions actions: write"));

        let verify_runs_save =
            WARM_WORKFLOW_GOOD.replacen("          mode: verify", "          mode: save", 1);
        assert!(repo_cache_warm_workflow_problems(&verify_runs_save)
            .iter()
            .any(|p| p.0 == "warm-linux-verify saves or prunes caches"));
    }

    #[test]
    fn repo_cache_warm_composite_accepts_good_shape_and_rejects_drifts() {
        assert_eq!(
            repo_cache_warm_composite_problems(WARM_COMPOSITE_GOOD),
            Vec::new()
        );

        let with_perms = format!("permissions:\n  actions: write\n{WARM_COMPOSITE_GOOD}");
        assert!(repo_cache_warm_composite_problems(&with_perms)
            .iter()
            .any(|p| p.0 == "permissions: in composite"));

        let old_key = WARM_COMPOSITE_GOOD.replace("-repository-full-", "-repository-");
        assert!(repo_cache_warm_composite_problems(&old_key)
            .iter()
            .any(|p| p.0.starts_with("save key:")));

        let pr_saves = WARM_COMPOSITE_GOOD.replace(
            "if: inputs.mode == 'save' && steps.cache-lookup.outputs.cache-hit != 'true' && steps.capacity-guard.outputs.allow_save == 'true'",
            "if: steps.cache-lookup.outputs.cache-hit != 'true'",
        );
        assert!(repo_cache_warm_composite_problems(&pr_saves)
            .iter()
            .any(|p| p.0.starts_with("save if:")));

        let no_offline = WARM_COMPOSITE_GOOD.replace("--repository_disable_download ", "");
        assert!(repo_cache_warm_composite_problems(&no_offline)
            .iter()
            .any(|p| p.0 == "missing --repository_disable_download"));

        let setup_saves = WARM_COMPOSITE_GOOD.replace(
            "cache-save: ${{ inputs.mode == 'save' }}",
            "cache-save: true",
        );
        assert!(repo_cache_warm_composite_problems(&setup_saves)
            .iter()
            .any(|p| p.0 == "cache-save: true"));

        let setup_never_saves = WARM_COMPOSITE_GOOD.replace(
            "cache-save: ${{ inputs.mode == 'save' }}",
            "cache-save: false",
        );
        assert!(repo_cache_warm_composite_problems(&setup_never_saves)
            .iter()
            .any(|p| p.0 == "cache-save: false"));

        let setup_cache_save_unset =
            WARM_COMPOSITE_GOOD.replace("        cache-save: ${{ inputs.mode == 'save' }}\n", "");
        assert!(repo_cache_warm_composite_problems(&setup_cache_save_unset)
            .iter()
            .any(|p| p.0 == "cache-save: unset"));

        let bazelisk_disabled =
            WARM_COMPOSITE_GOOD.replace("bazelisk-cache: true", "bazelisk-cache: false");
        assert!(repo_cache_warm_composite_problems(&bazelisk_disabled)
            .iter()
            .any(|p| p.0 == "bazelisk-cache: false"));

        let bazelisk_unset = WARM_COMPOSITE_GOOD.replace("        bazelisk-cache: true\n", "");
        assert!(repo_cache_warm_composite_problems(&bazelisk_unset)
            .iter()
            .any(|p| p.0 == "bazelisk-cache: unset"));

        let continue_guard = WARM_COMPOSITE_GOOD.replace(
            "      shell: bash\n      run: |\n        python3 .github/actions/setup-bazel/cache_capacity_guard.py",
            "      continue-on-error: true\n      shell: bash\n      run: |\n        python3 .github/actions/setup-bazel/cache_capacity_guard.py",
        );
        assert!(repo_cache_warm_composite_problems(&continue_guard)
            .iter()
            .any(|p| p.0 == "missing or misplaced capacity guard"));

        let prune_before_save = WARM_COMPOSITE_GOOD.replace(
            "    - id: cache-save",
            "    - name: Early prune\n      if: inputs.mode == 'save'\n      run: python3 .github/actions/setup-bazel/cache_prune.py\n    - id: cache-save",
        );
        assert!(repo_cache_warm_composite_problems(&prune_before_save)
            .iter()
            .any(|p| p.0.contains("prune")));
    }

    #[test]
    fn unexpected_cache_save_rejects_actions_cache_and_save_outside_warm_workflow() {
        let rogue_save = "\
    - uses: actions/cache/save@abc # v6
      with:
        path: ~/.cache/bazel-repo
        key: x
";
        let rogue_rw = "\
    - uses: actions/cache@abc # v6
      with:
        path: ~/.cache/bazel-repo
        key: x
";
        let restore_only = "\
    - uses: actions/cache/restore@abc # v6
      with:
        path: ~/.cache/bazel-repo
        key: x
";
        assert!(
            !unexpected_cache_save_problems(".github/workflows/ci.yaml", rogue_save).is_empty()
        );
        assert!(!unexpected_cache_save_problems(".github/workflows/ci.yaml", rogue_rw).is_empty());
        assert_eq!(
            unexpected_cache_save_problems(".github/workflows/ci.yaml", restore_only),
            Vec::new()
        );
        assert!(!unexpected_cache_save_problems(
            ".github/workflows/ci.yaml",
            "        cache-save: true\n"
        )
        .is_empty());

        let presubmit_ok = "\
      - name: Save it for PRs based on this commit
        uses: actions/cache/save@abc # v6
        with:
          path: ${{ runner.temp }}/pipeline-rdeps-map.json
          key: pipeline-rdeps-map-v1-${{ github.sha }}
";
        assert_eq!(
            unexpected_cache_save_problems(".github/workflows/presubmit.yaml", presubmit_ok),
            Vec::new()
        );
        let presubmit_repo = format!("{presubmit_ok}{rogue_save}");
        assert!(!unexpected_cache_save_problems(
            ".github/workflows/presubmit.yaml",
            &presubmit_repo
        )
        .is_empty());
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
      if: steps.mode.outputs.readonly == 'true' && runner.environment == 'github-hosted'
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
        let bad = LLVM_GOOD.replace(
            "      if: steps.mode.outputs.readonly == 'true' && runner.environment == 'github-hosted'\n",
            "",
        );
        let p = llvm_restore_branch_problems(&bad);
        assert_eq!(p.len(), 1, "{:?}", p);
        assert_eq!(p[0].0, "no if:");
    }

    #[test]
    fn llvm_readonly_restore_must_skip_self_hosted_runners() {
        // The download the queue runners threw away: 2.3 GB per job, unused.
        let bad = LLVM_GOOD.replace(
            "if: steps.mode.outputs.readonly == 'true' && runner.environment == 'github-hosted'",
            "if: steps.mode.outputs.readonly == 'true'",
        );
        let p = llvm_restore_branch_problems(&bad);
        assert_eq!(p.len(), 1, "{:?}", p);
        assert_eq!(p[0].0, "if: steps.mode.outputs.readonly == 'true'");
        assert!(p[0].2.contains("self-hosted"), "{:?}", p);
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
    fn goproxy_pipe_list_is_accepted() {
        assert_eq!(
            goproxy_fallback_problem("https://proxy.golang.org|direct"),
            None
        );
        assert_eq!(
            goproxy_fallback_problem("https://proxy.golang.org|https://goproxy.example|direct"),
            None
        );
    }

    #[test]
    fn goproxy_shapes_that_do_not_fall_back_are_rejected() {
        // Go's default: a timeout on the proxy never reaches `direct`.
        assert!(goproxy_fallback_problem("https://proxy.golang.org,direct").is_some());
        // One source: nothing to fall back to.
        assert!(goproxy_fallback_problem("https://proxy.golang.org").is_some());
        // The same URL twice is tried once, so it is not a retry.
        assert!(
            goproxy_fallback_problem("https://proxy.golang.org|https://proxy.golang.org").is_some()
        );
        assert!(goproxy_fallback_problem("https://proxy.golang.org|off").is_some());
        assert!(goproxy_fallback_problem("https://proxy.golang.org|").is_some());
    }

    #[test]
    fn repo_env_goproxy_reads_the_bazelrc_line() {
        let content = "\
        bazelrc: |
          # common --repo_env=GOPROXY=https://commented.example
          common --show_timestamps
          common --repo_env=GOPROXY=https://proxy.golang.org|direct --other
";
        assert_eq!(
            repo_env_goproxy(content).as_deref(),
            Some("https://proxy.golang.org|direct")
        );
        assert_eq!(repo_env_goproxy("common --show_timestamps\n"), None);
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

    #[test]
    fn workflow_paths_match_handles_wildcards_and_negations() {
        let pats: Vec<String> = [
            "apps/mcp/vitruvian-slack-mcp/Dockerfile",
            "apps/mcp/vitruvian-slack-mcp/.dockerignore",
            "apps/mcp/vitruvian-slack-mcp/rs/**",
            "!apps/mcp/vitruvian-slack-mcp/rs/**/BUILD",
            "!apps/mcp/vitruvian-slack-mcp/rs/**/BUILD.bazel",
            "!apps/mcp/vitruvian-slack-mcp/rs/**/OWNERS",
            "!apps/mcp/vitruvian-slack-mcp/rs/**/*.md",
            "!apps/mcp/vitruvian-slack-mcp/rs/rustfmt.toml",
            "packages/mcp-auth/Cargo.toml",
            "packages/mcp-auth/src/**",
            "!packages/mcp-auth/**/*.md",
            ".github/workflows/vitruvian-slack-mcp-image.yaml",
        ]
        .iter()
        .map(|s| (*s).to_string())
        .collect();

        assert!(workflow_paths_match(
            &pats,
            "apps/mcp/vitruvian-slack-mcp/rs/src/lib.rs"
        ));
        assert!(workflow_paths_match(
            &pats,
            "apps/mcp/vitruvian-slack-mcp/Dockerfile"
        ));
        assert!(workflow_paths_match(&pats, "packages/mcp-auth/src/lib.rs"));
        assert!(workflow_paths_match(
            &pats,
            ".github/workflows/vitruvian-slack-mcp-image.yaml"
        ));

        assert!(!workflow_paths_match(
            &pats,
            "apps/mcp/vitruvian-slack-mcp/BUILD"
        ));
        assert!(!workflow_paths_match(&pats, "packages/mcp-auth/BUILD"));
        assert!(!workflow_paths_match(
            &pats,
            "apps/mcp/vitruvian-slack-mcp/deploy/chart/values.yaml"
        ));
        assert!(!workflow_paths_match(
            &pats,
            "apps/mcp/vitruvian-slack-mcp/README.md"
        ));
        assert!(!workflow_paths_match(
            &pats,
            "apps/mcp/vitruvian-slack-mcp/rs/README.md"
        ));
    }

    #[test]
    fn image_workflow_problems_rejects_unscoped_dir_glob() {
        let pre_fix = r#"
on:
  workflow_dispatch: {}
  push:
    branches: [main]
    paths:
      - 'apps/mcp/vitruvian-slack-mcp/**'
      - 'packages/mcp-auth/**'
      - '.github/workflows/vitruvian-slack-mcp-image.yaml'
  pull_request:
    paths:
      - 'apps/mcp/vitruvian-slack-mcp/**'
      - 'packages/mcp-auth/**'
      - '.github/workflows/vitruvian-slack-mcp-image.yaml'
"#;
        let probs =
            image_workflow_problems(".github/workflows/vitruvian-slack-mcp-image.yaml", pre_fix);
        let found: Vec<&str> = probs.iter().map(|p| p.0.as_str()).collect();
        assert!(
            found.contains(&"apps/mcp/vitruvian-slack-mcp/BUILD"),
            "{found:?}"
        );
        assert!(found.contains(&"packages/mcp-auth/BUILD"), "{found:?}");
        assert!(
            found.contains(&"apps/mcp/vitruvian-slack-mcp/deploy/chart/Chart.yaml"),
            "{found:?}"
        );
    }

    #[test]
    fn image_workflow_problems_rejects_push_pr_drift() {
        let drifted = r#"
on:
  push:
    branches: [main]
    paths:
      - 'tools/ci-runner/Dockerfile'
      - 'tools/ci-runner/src/**'
      - '!tools/ci-runner/**/*.md'
      - '.github/workflows/ci-runner-image.yaml'
  pull_request:
    paths:
      - 'tools/ci-runner/Dockerfile'
      - '.github/workflows/ci-runner-image.yaml'
"#;
        let probs = image_workflow_problems(".github/workflows/ci-runner-image.yaml", drifted);
        assert!(
            probs.iter().any(|p| p.0 == "push != pull_request"),
            "{probs:?}"
        );
    }

    #[test]
    fn image_workflow_problems_accepts_scoped_shapes() {
        let good_slack = r#"
on:
  workflow_dispatch: {}
  push:
    branches: [main]
    paths:
      - 'apps/mcp/vitruvian-slack-mcp/Dockerfile'
      - 'apps/mcp/vitruvian-slack-mcp/.dockerignore'
      - 'apps/mcp/vitruvian-slack-mcp/rs/**'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/BUILD'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/BUILD.bazel'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/OWNERS'
      - '!apps/mcp/vitruvian-slack-mcp/rs/deploy/**'
      - '!apps/mcp/vitruvian-slack-mcp/rs/mkdocs.yml'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/*.md'
      - 'packages/mcp-auth/Cargo.toml'
      - 'packages/mcp-auth/src/**'
      - '!packages/mcp-auth/**/BUILD'
      - '!packages/mcp-auth/**/BUILD.bazel'
      - '!packages/mcp-auth/**/OWNERS'
      - '!packages/mcp-auth/**/*.md'
      - '.github/workflows/vitruvian-slack-mcp-image.yaml'
  pull_request:
    paths:
      - 'apps/mcp/vitruvian-slack-mcp/Dockerfile'
      - 'apps/mcp/vitruvian-slack-mcp/.dockerignore'
      - 'apps/mcp/vitruvian-slack-mcp/rs/**'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/BUILD'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/BUILD.bazel'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/OWNERS'
      - '!apps/mcp/vitruvian-slack-mcp/rs/deploy/**'
      - '!apps/mcp/vitruvian-slack-mcp/rs/mkdocs.yml'
      - '!apps/mcp/vitruvian-slack-mcp/rs/**/*.md'
      - 'packages/mcp-auth/Cargo.toml'
      - 'packages/mcp-auth/src/**'
      - '!packages/mcp-auth/**/BUILD'
      - '!packages/mcp-auth/**/BUILD.bazel'
      - '!packages/mcp-auth/**/OWNERS'
      - '!packages/mcp-auth/**/*.md'
      - '.github/workflows/vitruvian-slack-mcp-image.yaml'
"#;
        assert_eq!(
            image_workflow_problems(
                ".github/workflows/vitruvian-slack-mcp-image.yaml",
                good_slack
            ),
            Vec::new()
        );
    }
}
