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

//! watch-pr.sh's `main`, phase for phase: resolve the PR, watch its checks,
//! watch it merge, then watch main's post-merge runs through
//! pipeline-status.

use crate::arith::{self, Vars};
use crate::checks::parse_checks_json;
use crate::post_merge::{decide, Decision, EXIT_TIMEOUT, POST_MERGE_GRACE};
use crate::queue::{self, Verdict};
use crate::sh::{
    self, capture, capture_merged, capture_or_echo, die, env_or, info, now, ok, on_path, prefix,
    read_fields, run_ids, test_cmp, warn,
};
use std::collections::HashMap;

pub const USAGE: &str = "watch-pr — Autonomous PR CI check, merge queue, and post-merge watchdog.

Usage:
  bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]

Arguments:
  <pr-number>         Pull request number (e.g. 2857 or #2857)
  <branch>            Branch name associated with an open or merged PR
  <sha>               Commit SHA associated with a PR

Options:
  --timeout <sec>     Max duration in seconds before giving up (default: 2700)
  --interval <sec>    Seconds between polling status queries (default: 15)
  --skip-post-merge   Exit once merged on main without waiting for post-merge pipeline
  --help, -h          Print this help message

Exit codes:
  0: Success (all checks passed, merged, post-merge green)
  1: Check or workflow failure (diagnostic logs printed)
  2: Timeout reached
  3: Invalid argument or configuration error
";

const PIPELINE_SCRIPT: &str = "tools/pipeline-status/pipeline-status.sh";

/// The script's shell variables that `$(( ))` and `eval` can see.
struct Shell {
    vars: HashMap<String, String>,
}

impl Shell {
    fn var(&self, name: &str) -> String {
        self.vars.get(name).cloned().unwrap_or_default()
    }

    fn set(&mut self, name: &str, value: &str) {
        self.vars.insert(name.to_string(), value.to_string());
    }
}

impl Vars for Shell {
    fn get(&self, name: &str) -> Option<String> {
        self.vars
            .get(name)
            .cloned()
            .or_else(|| std::env::var(name).ok())
    }
}

/// Split one line of shell into words, honouring '...', "..." and \.
fn shell_words(line: &str) -> Option<Vec<String>> {
    let mut words = Vec::new();
    let mut word = String::new();
    let mut in_word = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            ' ' | '\t' => {
                if in_word {
                    words.push(std::mem::take(&mut word));
                    in_word = false;
                }
            }
            '#' if !in_word => break,
            '\'' => {
                in_word = true;
                loop {
                    match chars.next() {
                        Some('\'') => break,
                        Some(ch) => word.push(ch),
                        None => return None,
                    }
                }
            }
            '"' => {
                in_word = true;
                loop {
                    match chars.next() {
                        Some('"') => break,
                        Some('\\') => match chars.next() {
                            Some(ch @ ('$' | '`' | '"' | '\\')) => word.push(ch),
                            Some(ch) => {
                                word.push('\\');
                                word.push(ch);
                            }
                            None => return None,
                        },
                        Some('$') | Some('`') => return None,
                        Some(ch) => word.push(ch),
                        None => return None,
                    }
                }
            }
            '\\' => {
                in_word = true;
                if let Some(ch) = chars.next() {
                    word.push(ch);
                }
            }
            '$' | '`' | ';' | '&' | '|' | '<' | '>' | '(' | ')' => return None,
            ch => {
                in_word = true;
                word.push(ch);
            }
        }
    }
    if in_word {
        words.push(word);
    }
    Some(words)
}

fn is_name(s: &str) -> bool {
    let mut chars = s.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// `eval "$(bazel run //tools/agent-app -- env <agent>)"`: agent-app prints
/// `export NAME=value` lines, which this applies. Lines that are anything
/// else are not run (this is not a shell).
fn apply_exports(text: &str, shell: &mut Shell) {
    for line in text.lines() {
        let Some(words) = shell_words(line) else {
            continue;
        };
        let (export, assignments) = match words.first().map(String::as_str) {
            Some("export") => (true, &words[1..]),
            _ => (false, &words[..]),
        };
        if assignments.is_empty() {
            continue;
        }
        let parsed: Option<Vec<(String, String)>> = assignments
            .iter()
            .map(|w| {
                let (name, value) = w.split_once('=')?;
                is_name(name).then(|| (name.to_string(), value.to_string()))
            })
            .collect();
        let Some(parsed) = parsed else { continue };
        for (name, value) in parsed {
            if export || std::env::var_os(&name).is_some() {
                std::env::set_var(&name, &value);
            }
            shell.set(&name, &value);
        }
    }
}

fn last_squash_on_main(pr: &str) -> String {
    capture(
        "git",
        &[
            "log",
            "-1",
            "--grep",
            &format!("(#{pr})"),
            "--format=%H",
            "origin/main",
        ],
    )
    .out
}

fn fetch_main() {
    sh::run_quiet("git", &["fetch", "origin", "main", "-q"]);
}

/// `$(echo "$json" | grep -o '"key":"[^"]*"' | cut -d'"' -f4 || true)`.
fn field(json: &str, key: &str) -> String {
    sh::subst_text(sh::json_field_values(json, key).0.join("\n").as_bytes())
}

fn pr_view(pr: &str, repo: &str) -> String {
    capture(
        "gh",
        &[
            "pr",
            "view",
            pr,
            "--repo",
            repo,
            "--json",
            "state,mergeStateStatus,mergeCommit",
        ],
    )
    .out
}

/// Consecutive unreadable polls of the queue phase before giving up. A
/// failed read is never shown as a state (it once printed "QUEUED", which
/// GitHub has no such value for, for an hour after the PR left the queue).
const MAX_READ_FAILURES: u32 = 5;

/// Re-mint the agent token this long after minting it: they last an hour.
const TOKEN_REFRESH_SECS: i64 = 45 * 60;

/// The PR's queue state from GitHub, or why it could not be read.
fn queue_status(pr: &str, repo: &str) -> Result<queue::Status, String> {
    let (owner, name) = repo.split_once('/').unwrap_or((repo, ""));
    let got = capture_merged(
        "gh",
        &[
            "api",
            "graphql",
            "-f",
            &format!("query={}", queue::QUERY),
            "-F",
            &format!("owner={owner}"),
            "-F",
            &format!("name={name}"),
            "-F",
            &format!("number={pr}"),
        ],
    );
    if got.status != 0 {
        let first = got.out.lines().next().unwrap_or("").trim();
        return Err(format!("gh api graphql exited {}: {first}", got.status));
    }
    queue::parse(&got.out)
}

/// The token watch-pr minted for itself (as scout), so it can mint a new
/// one before the hour runs out. None when the caller brought its own.
struct MintedToken {
    at: i64,
}

fn mint_token(shell: &mut Shell) -> bool {
    let exports = capture("bazel", &["run", "//tools/agent-app", "--", "env", "scout"]).out;
    apply_exports(&exports, shell);
    !exports.is_empty()
}

/// Re-mint our own token when it is old, or when `force` (a read failed).
fn refresh_token(minted: &mut Option<MintedToken>, shell: &mut Shell, force: bool) {
    let Some(token) = minted.as_mut() else { return };
    let t = now();
    if !force && t - token.at < TOKEN_REFRESH_SECS {
        return;
    }
    if mint_token(shell) {
        info("Minted a fresh GitHub token (agent tokens last an hour).");
        token.at = t;
    } else {
        warn("Could not mint a fresh GitHub token.");
    }
}

/// Run watch-pr with `args` (no program name); the exit status.
pub fn run(script: &str, args: &[String]) -> i32 {
    let mut shell = Shell {
        vars: HashMap::new(),
    };
    shell.set(
        "REPO",
        &env_or("WATCH_PR_REPO", "VitruvianSoftware/vitruvian-core"),
    );
    shell.set("TIMEOUT", &env_or("WATCH_PR_TIMEOUT", "2700"));
    shell.set("INTERVAL", &env_or("WATCH_PR_INTERVAL", "15"));
    shell.set(
        "SKIP_POST_MERGE",
        &env_or("WATCH_PR_SKIP_POST_MERGE", "false"),
    );

    let mut target = String::new();
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_str();
        match arg {
            "-h" | "--help" => {
                sh::out_text(USAGE);
                return 0;
            }
            "--timeout" | "--interval" => {
                let Some(value) = args.get(i + 1) else {
                    let line = if arg == "--timeout" { 128 } else { 132 };
                    sh::err_text(&format!("{script}: line {line}: $2: unbound variable\n"));
                    return 1;
                };
                let name = if arg == "--timeout" {
                    "TIMEOUT"
                } else {
                    "INTERVAL"
                };
                shell.set(name, value);
                i += 2;
            }
            "--skip-post-merge" => {
                shell.set("SKIP_POST_MERGE", "true");
                i += 1;
            }
            _ if arg.starts_with('-') => {
                die(&format!("Unknown option: {arg}"));
                sh::out_text(USAGE);
                return 3;
            }
            _ => {
                if target.is_empty() {
                    target = arg.to_string();
                    i += 1;
                } else {
                    die(&format!("Unexpected extra argument: {arg}"));
                    return 3;
                }
            }
        }
    }

    if target.is_empty() {
        die("Missing target pull request number, branch, or commit SHA.");
        sh::out_text(USAGE);
        return 3;
    }
    shell.set("target", &target);

    let workspace = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(dir) if !dir.is_empty() => dir,
        _ => capture_or_echo("git", &["rev-parse", "--show-toplevel"], "."),
    };
    if !sh::cd(&workspace, script, 162) {
        die("Cannot find a repository workspace to run in.");
        return 3;
    }

    if !on_path("gh") {
        die("gh CLI not found on PATH");
        return 3;
    }

    let mut minted = None;
    if std::env::var("GH_TOKEN")
        .map(|t| t.is_empty())
        .unwrap_or(true)
        && sh::is_file("tools/agent-app/BUILD")
        && on_path("bazel")
    {
        mint_token(&mut shell);
        minted = Some(MintedToken { at: now() });
        target = shell.var("target");
    }

    let repo = shell.var("REPO");
    let mut pr = if let Some(rest) = target.strip_prefix('#') {
        rest.to_string()
    } else if target.bytes().any(|b| !b.is_ascii_digit()) {
        let mut pr = capture(
            "gh",
            &[
                "pr",
                "list",
                "--repo",
                &repo,
                "--head",
                &target,
                "--state",
                "all",
                "--json",
                "number,createdAt",
                "-q",
                "sort_by(.createdAt)|last|.number",
            ],
        )
        .out;
        if pr.is_empty() || pr == "null" {
            pr = capture(
                "gh",
                &[
                    "api",
                    &format!("repos/{repo}/commits/{target}/pulls"),
                    "-q",
                    "sort_by(.created_at)|last|.number",
                ],
            )
            .out;
        }
        pr
    } else {
        target.clone()
    };

    if pr.is_empty() || pr == "null" {
        let on_main = last_squash_on_main(&target);
        if on_main.is_empty() {
            die(&format!(
                "Could not resolve '{target}' to a valid pull request in {repo}."
            ));
            return 3;
        }
        shell.set("commit_on_main", &on_main);
        pr = target.clone();
    }
    shell.set("pr", &pr);

    let timeout = shell.var("TIMEOUT");
    let interval = shell.var("INTERVAL");
    info(&format!(
        "Starting autonomous watchdog for PR #{pr} in {repo} (timeout: {timeout}s, interval: {interval}s)..."
    ));

    let start_time = now();
    shell.set("start_time", &start_time.to_string());
    let deadline = match arith::variable("TIMEOUT", &shell) {
        Ok(t) => start_time.wrapping_add(t),
        Err(e) => {
            sh::err_text(&format!("{script}: line 209: {}\n", e.message));
            return e.status;
        }
    };

    // ── Phase 1: Watch PR CI Checks ──────────────────────────────────────────
    let mut pr_merged = false;
    loop {
        let now = now();
        if now >= deadline {
            die(&format!(
                "Watchdog timed out after {timeout}s waiting for PR #{pr}."
            ));
            return EXIT_TIMEOUT;
        }
        let elapsed = now - start_time;
        refresh_token(&mut minted, &mut shell, false);

        if field(&pr_view(&pr, &repo), "state") == "MERGED" {
            ok(&format!("PR #{pr} has already merged into main!"));
            pr_merged = true;
            break;
        }

        let checks_json = capture(
            "gh",
            &[
                "pr",
                "checks",
                &pr,
                "--repo",
                &repo,
                "--json",
                "name,state,bucket,workflow,link",
            ],
        )
        .out;

        if checks_json.is_empty() || checks_json == "[]" || checks_json == "null" {
            let local_match = last_squash_on_main(&pr);
            if !local_match.is_empty() {
                ok(&format!(
                    "PR #{pr} squashed commit {} already detected on origin/main!",
                    prefix(&local_match, 8)
                ));
                pr_merged = true;
                break;
            }
            warn(&format!(
                "Waiting for PR #{pr} checks to be registered by GitHub Actions... ({elapsed}s elapsed)"
            ));
            sh::sleep(&interval);
            continue;
        }

        let parsed = parse_checks_json(&checks_json);
        sh::err_text(&parsed.stderr);
        let parsed_output = sh::subst_text(parsed.stdout.as_bytes());
        let stats_line = parsed_output.split('\n').next().unwrap_or("");
        let fields = read_fields(stats_line, ':', 4);
        let (p, s, pend, f) = (&fields[0], &fields[1], &fields[2], &fields[3]);

        if test_cmp(f, "-gt", "0", script, 263) {
            die(&format!(
                "Check failure detected on PR #{pr}: {f} failing check(s)!"
            ));
            for line in parsed_output.split('\n') {
                if !line.starts_with("FAILED_ITEM:") {
                    continue;
                }
                let item = read_fields(line, '|', 3);
                let name = item[0].strip_prefix("FAILED_ITEM:").unwrap_or(&item[0]);
                let (workflow, link) = (&item[1], &item[2]);
                die(&format!("  - {name} ({workflow}): {link}"));
                let run_id = run_ids(link);
                if !run_id.is_empty() {
                    info(&format!("Fetching failure logs for run {run_id}:"));
                    sh::run_tail(
                        "gh",
                        &["run", "view", &run_id, "--repo", &repo, "--log-failed"],
                        25,
                    );
                }
            }
            return 1;
        }

        if test_cmp(pend, "-eq", "0", script, 279) && test_cmp(p, "-gt", "0", script, 279) {
            ok(&format!(
                "All PR #{pr} checks PASSED ({p} passed, {s} skipped) in {elapsed}s!"
            ));
            break;
        }

        warn(&format!(
            "PR #{pr} checks in progress: {p} passed, {s} skipped, {pend} pending, 0 failed ({elapsed}s elapsed)"
        ));
        sh::sleep(&interval);
    }

    // ── Phase 2: Watch Merge Queue / Squash Merge into main ──────────────────
    if !pr_merged {
        info(&format!(
            "Monitoring merge queue / squash merge for PR #{pr} into main..."
        ));
        let mut read_failures = 0;
        loop {
            let now = now();
            if now >= deadline {
                die(&format!(
                    "Watchdog timed out after {timeout}s waiting for PR #{pr} to merge."
                ));
                return 2;
            }
            let elapsed = now - start_time;

            fetch_main();
            let local_match = last_squash_on_main(&pr);
            if !local_match.is_empty() {
                ok(&format!(
                    "PR #{pr} squashed commit {} detected on origin/main!",
                    prefix(&local_match, 8)
                ));
                break;
            }

            refresh_token(&mut minted, &mut shell, false);
            let status = match queue_status(&pr, &repo) {
                Ok(status) => {
                    read_failures = 0;
                    status
                }
                Err(why) => {
                    read_failures += 1;
                    if read_failures >= MAX_READ_FAILURES {
                        die(&format!(
                            "Could not read PR #{pr}'s merge-queue state from GitHub {read_failures} times in a row; giving up rather than guessing. Last error: {why}"
                        ));
                        return 1;
                    }
                    warn(&format!(
                        "Could not read PR #{pr}'s merge-queue state ({read_failures}/{MAX_READ_FAILURES}): {why}"
                    ));
                    refresh_token(&mut minted, &mut shell, true);
                    sh::sleep(&interval);
                    continue;
                }
            };
            let merge = if status.merge_state.is_empty() {
                "unknown".to_string()
            } else {
                status.merge_state.clone()
            };
            match status.verdict {
                Verdict::Merged => {
                    ok(&format!("PR #{pr} is marked MERGED in GitHub!"));
                    break;
                }
                Verdict::Closed => {
                    die(&format!("PR #{pr} was closed without being merged!"));
                    return 1;
                }
                Verdict::Removed { reason, at } => {
                    die(&format!(
                        "PR #{pr} was removed from the merge queue at {at} (reason: {reason}) and is not queued now. Fix the cause and enqueue it again."
                    ));
                    return 1;
                }
                Verdict::Queued { state, position } => info(&format!(
                    "PR #{pr} is in the merge queue (position {position}, {state}; mergeStateStatus: {merge}). Waiting for squash merge... ({elapsed}s elapsed)"
                )),
                Verdict::Merging => info(&format!(
                    "PR #{pr} left the merge queue as merged; waiting for GitHub to mark it MERGED... ({elapsed}s elapsed)"
                )),
                Verdict::AutoMergeArmed => info(&format!(
                    "PR #{pr} is not in the merge queue yet; auto-merge is armed (mergeStateStatus: {merge}). Waiting... ({elapsed}s elapsed)"
                )),
                Verdict::NotQueued => warn(&format!(
                    "PR #{pr} is OPEN but not in the merge queue and auto-merge is not armed (mergeStateStatus: {merge}). Waiting for it to be enqueued... ({elapsed}s elapsed)"
                )),
            }
            sh::sleep(&interval);
        }
    }

    // ── Phase 3: Verify Landed & Post-Merge Pipeline Status ──────────────────
    if shell.var("SKIP_POST_MERGE") == "true" {
        ok(&format!(
            "PR #{pr} has merged into main! (Skipping post-merge pipeline check as requested)."
        ));
        return 0;
    }

    let mut squashed = capture(
        "gh",
        &[
            "pr",
            "view",
            &pr,
            "--repo",
            &repo,
            "--json",
            "mergeCommit",
            "-q",
            ".mergeCommit.oid // empty",
        ],
    )
    .out;
    if squashed.is_empty() {
        fetch_main();
        squashed = last_squash_on_main(&pr);
    }
    if squashed.is_empty() {
        die(&format!(
            "Could not resolve squashed commit SHA for PR #{pr}."
        ));
        return 3;
    }
    let short = prefix(&squashed, 8);

    ok(&format!(
        "PR #{pr} resolved to squashed commit {short} on main."
    ));
    info(&format!(
        "Monitoring post-merge push workflows on main for commit {short}..."
    ));

    let post_merge_start = now();
    loop {
        let now = now();
        if now >= deadline {
            die(&format!(
                "Watchdog timed out after {timeout}s waiting for post-merge pipeline on commit {short}."
            ));
            return EXIT_TIMEOUT;
        }
        let elapsed = now - start_time;

        // Like the script: the checkout's own pipeline-status.sh when there is
        // one, else `bazel run //tools/pipeline-status` (now the Rust port).
        let status = if sh::is_file(PIPELINE_SCRIPT) {
            capture_merged("bash", &[PIPELINE_SCRIPT, &squashed])
        } else if on_path("bazel") {
            capture_merged(
                "bazel",
                &["run", "//tools/pipeline-status", "--", &squashed],
            )
        } else {
            warn("Neither pipeline-status.sh nor bazel available; skipping post-merge pipeline check.");
            return 0;
        };

        let post_elapsed = now - post_merge_start;
        let decision = decide(status.status, post_elapsed);
        match decision {
            Decision::Green => {
                ok(&format!(
                    "All post-merge push workflows for commit {short} are GREEN!"
                ));
                for line in status.out.split('\n') {
                    if line.contains('✓') || line.contains("passed") {
                        sh::out_text(&format!("{line}\n"));
                    }
                }
                ok(&format!(
                    "PR #{pr} successfully watched from submission to green post-merge pipeline on main! (Total time: {elapsed}s)"
                ));
            }
            Decision::Failed => {
                die(&format!(
                    "Post-merge pipeline FAILED on main for commit {short}!"
                ));
                sh::err_text(&format!("{}\n", status.out));
            }
            Decision::InProgress => {
                warn(&format!(
                    "Post-merge push workflows are currently IN PROGRESS / QUEUED... ({elapsed}s elapsed)"
                ));
                sh::sleep(&interval);
            }
            Decision::AwaitRegistration => {
                info(&format!(
                    "Waiting for GitHub Actions to register push workflows for {short}... ({post_elapsed}s/{POST_MERGE_GRACE}s grace period)"
                ));
                sh::sleep(&interval);
            }
            Decision::NoRunsStillWaiting => {
                // Never green on zero runs: a push to main always starts
                // workflows, so none after the grace period means they have
                // not registered (or the API is lagging). Keep waiting; the
                // deadline above ends the loop with a timeout, not a pass.
                warn(&format!(
                    "No push workflow runs registered for {short} after {post_elapsed}s; still waiting ({elapsed}s elapsed)..."
                ));
                sh::sleep(&interval);
            }
            Decision::Unexpected(rc) => {
                warn(&format!(
                    "Unexpected pipeline-status return code ({rc}). Retrying in {interval}s..."
                ));
                sh::sleep(&interval);
            }
        }
        // The exit code comes from the decision alone: only Green is 0, Failed
        // is 1, and every waiting state keeps polling.
        if let Some(code) = decision.exit_code() {
            return code;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WATCH_PR_SH_HEADER: &str = r#"#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# watch-pr — Autonomous, robust monitoring of GitHub Actions CI checks,
# merge queue ingestion, squash landing, and post-merge pipeline health.
#
# Usage:
#   bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]
#
# Options:
#   --timeout <sec>      Max time to wait before timing out (default: 2700 / 45m).
#   --interval <sec>     Polling interval between checks (default: 15).
#   --skip-post-merge    Exit immediately after landing on main, skipping post-merge pipeline.
#   --help, -h           Show this help message.
#
# Exit codes:
#   0: Successfully verified: PR checks passed, landed on main, and post-merge workflows green.
#   1: Failure detected in CI checks, merge queue, or post-merge workflows (diagnostics printed).
#   2: Timeout reached.
#   3: Invalid argument or configuration error.
set -uo pipefail

REPO="${WATCH_PR_REPO:-VitruvianSoftware/vitruvian-core}"
TIMEOUT="${WATCH_PR_TIMEOUT:-2700}"
INTERVAL="${WATCH_PR_INTERVAL:-15}"
SKIP_POST_MERGE="${WATCH_PR_SKIP_POST_MERGE:-false}"

info() { printf '\033[36m[%s] →\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf '\033[32m[%s] ✓\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[33m[%s] ⏳\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf '\033[31m[%s] ✗\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

usage() {
  cat <<'EOF'
watch-pr — Autonomous PR CI check, merge queue, and post-merge watchdog.

Usage:
  bazel run //tools/watch-pr -- <pr-number|branch|sha> [options]

Arguments:
  <pr-number>         Pull request number (e.g. 2857 or #2857)
  <branch>            Branch name associated with an open or merged PR
  <sha>               Commit SHA associated with a PR

Options:
  --timeout <sec>     Max duration in seconds before giving up (default: 2700)
  --interval <sec>    Seconds between polling status queries (default: 15)
  --skip-post-merge   Exit once merged on main without waiting for post-merge pipeline
  --help, -h          Print this help message

Exit codes:
  0: Success (all checks passed, merged, post-merge green)
  1: Check or workflow failure (diagnostic logs printed)
  2: Timeout reached
  3: Invalid argument or configuration error
EOF
}
"#;

    #[test]
    fn usage_matches_the_script() {
        let start =
            WATCH_PR_SH_HEADER.find("cat <<'EOF'\n").expect("heredoc") + "cat <<'EOF'\n".len();
        let end = WATCH_PR_SH_HEADER[start..].find("\nEOF\n").expect("EOF") + start + 1;
        assert_eq!(&WATCH_PR_SH_HEADER[start..end], USAGE);
    }

    #[test]
    fn agent_app_exports() {
        let mut shell = Shell {
            vars: HashMap::new(),
        };
        apply_exports(
            "export WATCH_PR_TEST_TOKEN=ghs_abc\nexport WATCH_PR_TEST_NAME='scout[bot]'\nnot a line\n",
            &mut shell,
        );
        assert_eq!(std::env::var("WATCH_PR_TEST_TOKEN").unwrap(), "ghs_abc");
        assert_eq!(std::env::var("WATCH_PR_TEST_NAME").unwrap(), "scout[bot]");
        assert_eq!(
            shell_words(r#"a "b c" 'd e' f\ g"#).unwrap(),
            ["a", "b c", "d e", "f g"]
        );
        assert!(shell_words("echo $(id)").is_none());
    }
}
