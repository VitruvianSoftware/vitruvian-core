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

//! pipeline-status.sh's `main`, step for step.

use crate::batch::{resolve, Outcome};
use crate::evaluate::{
    list_failed, list_in_flight, runs_query, settle_secs_from_env, EMPTY_RETURN_STATUS,
};
use crate::sh::{self, capture, capture_or_echo, die, env_or, info, ok, on_path, prefix, warn};

const DEFAULT_REPO: &str = "VitruvianSoftware/vitruvian-core";

/// `^#?[0-9]+$`.
fn is_pr_number(target: &str) -> bool {
    let digits = target.strip_prefix('#').unwrap_or(target);
    !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())
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

/// Turn the argument into a commit SHA the way the script does; "" if none.
fn resolve_sha(target: &str, repo: &str) -> String {
    if is_pr_number(target) {
        let pr = target.strip_prefix('#').unwrap_or(target);
        let view = |field: &str| {
            capture(
                "gh",
                &[
                    "pr",
                    "view",
                    pr,
                    "--repo",
                    repo,
                    "--json",
                    field,
                    "-q",
                    &format!(
                        ".{field}{} // empty",
                        if field == "mergeCommit" { ".oid" } else { "" }
                    ),
                ],
            )
            .out
        };
        let mut sha = view("mergeCommit");
        if sha.is_empty() {
            sha = view("headRefOid");
        }
        if sha.is_empty() {
            sh::run_quiet("git", &["fetch", "origin", "main", "-q"]);
            sha = last_squash_on_main(pr);
        }
        sha
    } else if target == "HEAD" {
        capture("git", &["rev-parse", "HEAD"]).out
    } else {
        capture_or_echo("git", &["rev-parse", target], target)
    }
}

/// Run pipeline-status with `args` (no program name); the exit status.
pub fn run(script: &str, args: &[String]) -> i32 {
    let target = match args.first() {
        Some(t) if !t.is_empty() => t.clone(),
        _ => "HEAD".to_string(),
    };
    let repo = env_or("PIPELINE_REPO", DEFAULT_REPO);

    let workspace = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(dir) if !dir.is_empty() => dir,
        _ => capture_or_echo("git", &["rev-parse", "--show-toplevel"], "."),
    };
    if !sh::cd(&workspace, script, 101) {
        die("cannot find a workspace to run in");
        return 3;
    }

    if !on_path("gh") {
        die("gh CLI not found on PATH");
        return 3;
    }
    // The script also stops here when neither jq nor python3 is on PATH: it
    // needs one of them to read JSON. This port reads JSON itself.

    let sha = resolve_sha(&target, &repo);
    if sha.is_empty() {
        die(&format!(
            "Could not resolve target '{target}' to a valid commit SHA"
        ));
        return 3;
    }
    let short = prefix(&sha, 8);

    info(&format!(
        "Checking GitHub Actions pipeline status for commit {short} in {repo}..."
    ));

    // Only the push to the branch counts, and only once it has settled.
    let branch = env_or("PIPELINE_BRANCH", "main");
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let gh_api = |path: &str| -> Result<String, String> {
        let got = capture("gh", &["api", path]);
        if got.status == 0 {
            Ok(got.out)
        } else {
            Err(format!("gh api {path} failed (exit {})", got.status))
        }
    };
    let activity = || {
        gh_api(&format!(
            "repos/{repo}/activity?ref=refs/heads/{branch}&per_page=100"
        ))
    };
    let range = |before: &str, after: &str| {
        gh_api(&format!(
            "repos/{repo}/compare/{before}...{after}?per_page=100"
        ))
    };
    let runs_for = |commit: &str| gh_api(&runs_query(&repo, commit, &branch));
    let resolved = match resolve(
        &sha,
        &branch,
        now,
        settle_secs_from_env(),
        &activity,
        &range,
        &runs_for,
    ) {
        Outcome::Judged(r) => r,
        Outcome::Waiting(why) => {
            // No verdict, and never green: the caller keeps waiting.
            warn(&format!("No verdict yet for commit {short}: {why}"));
            return 3;
        }
    };
    if let Some(note) = &resolved.note {
        info(note);
    }
    let evaluation = resolved.evaluation;
    let runs_json = resolved.runs_json;
    sh::err_text(&evaluation.stderr);
    if evaluation.status == EMPTY_RETURN_STATUS {
        // What bash 3.2 says as `return ""` fails.
        sh::err_text(&format!(
            "{script}: line 50: return: : numeric argument required\n"
        ));
    }
    let eval_output = sh::subst_text(evaluation.stdout.as_bytes());

    match evaluation.status {
        0 => {
            ok(&format!(
                "All post-merge workflows for {short} are GREEN ({eval_output})"
            ));
            0
        }
        1 => {
            die(&format!(
                "Pipeline FAILED for commit {short} ({eval_output})"
            ));
            let (out, err) = list_failed(&runs_json);
            sh::err_text(&err);
            sh::err_text(&out);
            1
        }
        2 => {
            warn(&format!(
                "Pipeline is currently IN PROGRESS for commit {short} ({eval_output})"
            ));
            let (out, err) = list_in_flight(&runs_json);
            sh::err_text(&err);
            // While only the settle window holds green back nothing is in
            // flight; the warning above already says why.
            if !out.is_empty() {
                sh::out_line(&out);
            }
            2
        }
        _ => {
            warn(&format!("No workflow runs found yet for commit {short}"));
            3
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pr_numbers() {
        for yes in ["1", "#42", "007"] {
            assert!(is_pr_number(yes), "{yes}");
        }
        for no in ["", "#", "##1", "1a", "abc", "HEAD", "-1", "1 "] {
            assert!(!is_pr_number(no), "{no}");
        }
    }
}
