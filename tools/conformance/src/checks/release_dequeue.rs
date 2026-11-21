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

//! Release-PR dequeue guard. GitHub refuses a ref update to a branch whose PR
//! is in the merge queue, so when a product fix lands on main while that
//! product's release PR is queued, release-please cannot refresh the release
//! branch ("Error updating ref heads/release-please--branches--main--...").
//! The release PR then merges with stale notes and a tag that already holds
//! the newer code: Courier 0.3.32 shipped #5268 and #5264 and listed neither
//! (run 44839928601).
//!
//! `release_pr_dequeue` takes a stale release PR out of the queue before
//! release-please runs, and `release_pr_dequeue rearm` puts it back after
//! (release-please pushes only when the PR's text changes, so a PR dequeued for
//! a chore would otherwise sit out of the queue). This check makes every job
//! that runs googleapis/release-please-action do both, in the right order, with
//! the right component, and under the same `if:` as release-please itself.

use std::fs;
use std::path::Path;

use crate::Context;

const GROUP: &str = "RELEASEDEQ";
const RELEASE_PLEASE: &str = "googleapis/release-please-action@";
const BUILD_TOOL: &str = "./.github/actions/build-ci-tool";

/// Workflows whose release PR is re-queued by something other than `rearm`.
/// release-beta-gate.yaml owns the Atrium release PR's auto-merge and queues it
/// once the beta DMG exists for the new code, so a `rearm` here would merge it
/// before that build.
const REARM_EXEMPT: &[&str] = &["vitruvian-atrium-release.yaml"];

/// A problem as (found, wanted, why).
pub(crate) type Problem = (String, String, String);

#[derive(Debug, Default, Clone)]
pub(crate) struct Step {
    pub job: String,
    pub id: String,
    pub uses: String,
    pub cond: Option<String>,
    pub run: String,
    pub env: Vec<(String, String)>,
    pub with: Vec<(String, String)>,
}

impl Step {
    fn env(&self, k: &str) -> Option<&str> {
        self.env
            .iter()
            .find(|(n, _)| n == k)
            .map(|(_, v)| v.as_str())
    }
    fn with(&self, k: &str) -> Option<&str> {
        self.with
            .iter()
            .find(|(n, _)| n == k)
            .map(|(_, v)| v.as_str())
    }
}

fn indent(line: &str) -> usize {
    line.bytes().take_while(|&b| b == b' ').count()
}

fn unquote(s: &str) -> String {
    let s = s.trim();
    if s.len() >= 2
        && ((s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')))
    {
        return s[1..s.len() - 1].to_string();
    }
    s.to_string()
}

/// `${{ a  &&  b }}` and `a && b` compare equal; quotes are not significant.
fn norm_expr(s: &str) -> String {
    let s = unquote(s);
    let s = s.trim();
    let s = s.strip_prefix("${{").unwrap_or(s);
    let s = s.strip_suffix("}}").unwrap_or(s);
    s.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .replace('"', "'")
}

fn value_of(line: &str) -> (String, String) {
    match line.split_once(':') {
        Some((k, v)) => {
            let v = v.trim();
            // A trailing ` # comment` is not part of the value.
            let v = match v.find(" #") {
                Some(i) if !v.starts_with('\'') && !v.starts_with('"') => v[..i].trim(),
                _ => v,
            };
            (k.trim().to_string(), v.to_string())
        }
        None => (line.trim().to_string(), String::new()),
    }
}

/// Every step of every job, in order. Not a YAML parser: it reads the shape
/// the workflows in this repo have (jobs at one indent, `steps:` then a
/// `- ` list, one-level `env:` and `with:` maps, inline or block `run:`).
pub(crate) fn parse_steps(content: &str) -> Vec<Step> {
    let mut steps: Vec<Step> = Vec::new();
    let mut in_jobs = false;
    let mut job_indent: Option<usize> = None;
    let mut job = String::new();
    let mut steps_key: Option<usize> = None;
    let mut step_indent: Option<usize> = None;
    // The key block (`env`/`with`/`run`) the lines being read belong to.
    let mut block: Option<(String, usize)> = None;

    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        let t = line.trim();
        if line.starts_with("jobs:") {
            in_jobs = true;
            continue;
        }
        if !in_jobs {
            continue;
        }
        if t.is_empty() {
            continue;
        }
        let ind = indent(line);
        if t.starts_with('#') {
            continue;
        }
        if ind == 0 {
            in_jobs = false;
            continue;
        }
        let ji = *job_indent.get_or_insert(ind);
        if ind == ji && t.ends_with(':') && !t.starts_with('-') {
            job = t.trim_end_matches(':').to_string();
            steps_key = None;
            step_indent = None;
            block = None;
            continue;
        }
        if job.is_empty() {
            continue;
        }
        if step_indent.is_none() {
            if ind > ji && t == "steps:" {
                steps_key = Some(ind);
            } else if let Some(sk) = steps_key {
                if ind >= sk && t.starts_with("- ") {
                    step_indent = Some(ind);
                } else if ind <= sk {
                    steps_key = None;
                }
            }
        }
        let Some(si) = step_indent else { continue };
        if ind < si || (ind == si && !t.starts_with("- ")) {
            // Back out of the steps list (e.g. a job key after it).
            step_indent = None;
            steps_key = None;
            block = None;
            continue;
        }
        let key_indent = si + 2;
        let mut body = t;
        if ind == si && t.starts_with("- ") {
            steps.push(Step {
                job: job.clone(),
                ..Step::default()
            });
            block = None;
            body = t[2..].trim_start();
        }
        let Some(cur) = steps.last_mut() else {
            continue;
        };
        let at_key = ind == si || ind == key_indent;
        if at_key {
            let (k, v) = value_of(body);
            block = None;
            match k.as_str() {
                "id" => cur.id = unquote(&v),
                "uses" => cur.uses = unquote(&v),
                "if" => cur.cond = Some(v),
                "run" => {
                    cur.run = if v == "|" || v == ">" || v == "|-" || v == ">-" {
                        String::new()
                    } else {
                        unquote(&v)
                    };
                    block = Some(("run".to_string(), key_indent));
                }
                "env" | "with" => block = Some((k, key_indent)),
                _ => {}
            }
            continue;
        }
        if let Some((name, bi)) = &block {
            if ind > *bi {
                match name.as_str() {
                    "run" => {
                        cur.run.push_str(t);
                        cur.run.push('\n');
                    }
                    "env" if ind == bi + 2 => {
                        let (k, v) = value_of(body);
                        cur.env.push((k, unquote(&v)));
                    }
                    "with" if ind == bi + 2 => {
                        let (k, v) = value_of(body);
                        cur.with.push((k, unquote(&v)));
                    }
                    _ => {}
                }
            }
        }
    }
    steps
}

/// `(package path, component)` of a single-package release-please config.
pub(crate) fn package_of(config_json: &str) -> Option<(String, String)> {
    let v: serde_json::Value = serde_json::from_str(config_json).ok()?;
    let pkgs = v.get("packages")?.as_object()?;
    if pkgs.len() != 1 {
        return None;
    }
    let (path, p) = pkgs.iter().next()?;
    let component = p.get("component")?.as_str()?;
    Some((path.clone(), component.to_string()))
}

fn bare(run: &str) -> String {
    run.trim().replace('"', "").replace('\'', "")
}

fn p(found: impl Into<String>, wanted: impl Into<String>, why: impl Into<String>) -> Problem {
    (found.into(), wanted.into(), why.into())
}

/// Every way `content` runs googleapis/release-please-action without the
/// dequeue and rearm steps around it. `config_of` reads a repo-relative
/// release-please config. `rearm_exempt` is true for the one workflow whose
/// release PR is re-queued elsewhere.
pub(crate) fn dequeue_problems(
    content: &str,
    rearm_exempt: bool,
    config_of: &dyn Fn(&str) -> Option<String>,
) -> Vec<Problem> {
    let steps = parse_steps(content);
    let mut problems = Vec::new();
    let mut jobs: Vec<&str> = Vec::new();
    for s in &steps {
        if s.uses.starts_with(RELEASE_PLEASE) && !jobs.contains(&s.job.as_str()) {
            jobs.push(&s.job);
        }
    }
    for job in jobs {
        let js: Vec<&Step> = steps.iter().filter(|s| s.job == job).collect();
        let rp_at = js
            .iter()
            .position(|s| s.uses.starts_with(RELEASE_PLEASE))
            .unwrap();
        let rp = js[rp_at];
        let guard = rp.cond.as_deref().map(norm_expr);
        let who = format!("job '{job}'");

        // 1. Build the tool, before release-please, under release-please's own `if:`.
        let build = js[..rp_at].iter().find(|s| {
            s.uses.starts_with(BUILD_TOOL) && s.with("tool") == Some("release_pr_dequeue")
        });
        let Some(build) = build else {
            problems.push(p(
                format!("{who}: no step builds release_pr_dequeue before release-please"),
                "a ./.github/actions/build-ci-tool step with tool: release_pr_dequeue, then the dequeue step, then release-please",
                "without it a queued release PR cannot be refreshed: release-please's push to the release branch is refused and the release ships stale notes",
            ));
            continue;
        };
        let build_at = js.iter().position(|s| std::ptr::eq(*s, *build)).unwrap();
        if build.id.is_empty() {
            problems.push(p(
                format!("{who}: the build step has no id"),
                "id: dequeue-bin",
                "the dequeue step reads the binary's path from this step's output",
            ));
            continue;
        }
        let want_path = format!("steps.{}.outputs.path", build.id);
        let same_guard = |s: &Step| s.cond.as_deref().map(norm_expr) == guard;
        let guard_text = guard.clone().unwrap_or_else(|| "no if:".to_string());
        if !same_guard(build) {
            problems.push(p(
                format!(
                    "{who}: build step if: {}",
                    build.cond.as_deref().map(norm_expr).unwrap_or_else(|| "none".into())
                ),
                format!("if: {guard_text} (release-please's own)"),
                "the dequeue must run exactly when release-please does: the workflow_dispatch tag path runs no release-please",
            ));
        }

        // 2. The dequeue step: between the build and release-please.
        let dq = js[build_at + 1..rp_at]
            .iter()
            .find(|s| bare(&s.run) == "$DEQUEUE_BIN");
        match dq {
            None => problems.push(p(
                format!(
                    "{who}: no step runs \"$DEQUEUE_BIN\" between the build and release-please"
                ),
                "run: '\"$DEQUEUE_BIN\"'",
                "the tool is built but never run before release-please",
            )),
            Some(dq) => {
                if !same_guard(dq) {
                    problems.push(p(
                        format!(
                            "{who}: dequeue step if: {}",
                            dq.cond
                                .as_deref()
                                .map(norm_expr)
                                .unwrap_or_else(|| "none".into())
                        ),
                        format!("if: {guard_text} (release-please's own)"),
                        "the dequeue must run exactly when release-please does",
                    ));
                }
                problems.extend(env_problems(
                    &who, "dequeue", dq, rp, &want_path, true, config_of,
                ));
            }
        }

        // 3. The rearm step: after release-please, even when it failed.
        if !rearm_exempt {
            let rearm = js[rp_at + 1..].iter().find(|s| {
                let r = bare(&s.run);
                r == "$DEQUEUE_BIN rearm"
            });
            match rearm {
                None => problems.push(p(
                    format!("{who}: no step runs \"$DEQUEUE_BIN\" rearm after release-please"),
                    "run: '\"$DEQUEUE_BIN\" rearm'",
                    "release-please pushes only when the release PR's text changes; a PR dequeued for a chore or docs commit is never pushed to, so nothing puts it back in the queue",
                )),
                Some(re) => {
                    let ok = format!("steps.{}.outcome == 'success'", build.id);
                    let want = match &guard {
                        Some(g) => format!("!cancelled() && {ok} && ({g})"),
                        None => format!("!cancelled() && {ok}"),
                    };
                    let got = re.cond.as_deref().map(norm_expr);
                    if got.as_deref() != Some(want.as_str()) {
                        problems.push(p(
                            format!("{who}: rearm step if: {}", got.unwrap_or_else(|| "none".into())),
                            format!("if: {want}"),
                            "rearm must run even when release-please failed (the PR is still out of the queue), but not when the tool was never built or the run was cancelled",
                        ));
                    }
                    problems.extend(env_problems(&who, "rearm", re, rp, &want_path, false, config_of));
                    if let Some(dq) = dq {
                        if dq.env("COMPONENT") != re.env("COMPONENT") {
                            problems.push(p(
                                format!(
                                    "{who}: rearm COMPONENT {:?} but dequeue COMPONENT {:?}",
                                    re.env("COMPONENT").unwrap_or(""),
                                    dq.env("COMPONENT").unwrap_or("")
                                ),
                                "the same COMPONENT in both steps",
                                "rearm would look at a different release PR than the one dequeued",
                            ));
                        }
                    }
                }
            }
        }
    }
    problems
}

/// Env checks shared by the dequeue and rearm steps.
fn env_problems(
    who: &str,
    what: &str,
    step: &Step,
    rp: &Step,
    want_path: &str,
    full: bool,
    config_of: &dyn Fn(&str) -> Option<String>,
) -> Vec<Problem> {
    let mut out = Vec::new();
    let need: &[&str] = if full {
        &[
            "REPO",
            "COMPONENT",
            "CODE_PATH",
            "MAIN_SHA",
            "GH_TOKEN",
            "DEQUEUE_BIN",
        ]
    } else {
        &["REPO", "COMPONENT", "GH_TOKEN", "DEQUEUE_BIN"]
    };
    for k in need {
        if step.env(k).map(|v| v.trim().is_empty()).unwrap_or(true) {
            out.push(p(
                format!("{who}: {what} step has no {k}"),
                format!("{k} set in the step's env"),
                "the tool refuses to run without it, and a wrong or missing value is a silent no-op",
            ));
        }
    }
    if let Some(v) = step.env("DEQUEUE_BIN") {
        if !norm_expr(v).contains(want_path) {
            out.push(p(
                format!("{who}: {what} DEQUEUE_BIN {v}"),
                format!("${{{{ {want_path} }}}}"),
                "must be the path the build step output",
            ));
        }
    }
    if let (Some(tok), Some(want)) = (step.env("GH_TOKEN"), rp.with("token")) {
        if norm_expr(tok) != norm_expr(want) {
            out.push(p(
                format!("{who}: {what} GH_TOKEN {tok}"),
                format!("the release-please token ({want})"),
                "the App token is the one allowed to dequeue and to arm auto-merge; GITHUB_TOKEN cannot",
            ));
        }
    }
    if full {
        if let Some(v) = step.env("MAIN_SHA") {
            if norm_expr(v) != "github.sha" {
                out.push(p(
                    format!("{who}: MAIN_SHA {v}"),
                    "${{ github.sha }}",
                    "the commit this run was triggered for, which the tool compares with the release PR",
                ));
            }
        }
    }
    // COMPONENT and CODE_PATH must be the release-please package's own, so the
    // tool looks at the right branch and path. A templated config-file (a
    // matrix) cannot be checked here: its component is looked up at run time.
    let cfg = rp.with("config-file").unwrap_or("");
    if !cfg.contains("${{") && !cfg.is_empty() {
        match config_of(cfg).as_deref().and_then(package_of) {
            None => out.push(p(
                format!("{who}: {cfg} is not a single-package release-please config"),
                "one package with a component",
                "the check cannot confirm COMPONENT and CODE_PATH against it",
            )),
            Some((path, component)) => {
                if let Some(v) = step.env("COMPONENT") {
                    if v != component {
                        out.push(p(
                            format!("{who}: {what} COMPONENT {v}"),
                            component.clone(),
                            format!("release-please names the release branch release-please--branches--main--components--{component} (from {cfg}); another name finds no PR and the dequeue silently does nothing"),
                        ));
                    }
                }
                if full {
                    if let Some(v) = step.env("CODE_PATH") {
                        if v != path {
                            out.push(p(
                                format!("{who}: CODE_PATH {v}"),
                                path.clone(),
                                format!("the package path in {cfg}"),
                            ));
                        }
                    }
                }
            }
        }
    } else if cfg.contains("${{") {
        // Matrix: both must come from the matrix, not be a fixed value.
        for k in if full {
            vec!["COMPONENT", "CODE_PATH"]
        } else {
            vec!["COMPONENT"]
        } {
            if let Some(v) = step.env(k) {
                if !v.contains("${{") {
                    out.push(p(
                        format!("{who}: {what} {k} is the fixed value {v}"),
                        "a value taken from the matrix (the config-file is templated)",
                        "one fixed value would be wrong for every other matrix entry",
                    ));
                }
            }
        }
    }
    out
}

pub fn check_release_dequeue(ctx: &Context) {
    if !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }
    let config_of = |rel: &str| fs::read_to_string(format!("{}/{}", ctx.root, rel)).ok();
    let mut seen = 0u32;
    let mut names: Vec<String> = fs::read_dir(&ctx.workflows_dir)
        .map(|rd| {
            rd.flatten()
                .map(|e| e.file_name().to_string_lossy().to_string())
                .filter(|n| n.ends_with(".yaml") || n.ends_with(".yml"))
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    for name in names {
        let Ok(content) = fs::read_to_string(format!("{}/{}", ctx.workflows_dir, name)) else {
            continue;
        };
        if !content.contains(RELEASE_PLEASE) {
            continue;
        }
        seen += 1;
        let rel = format!(".github/workflows/{name}");
        let problems =
            dequeue_problems(&content, REARM_EXEMPT.contains(&name.as_str()), &config_of);
        if problems.is_empty() {
            ctx.emit_ok(
                GROUP,
                &rel,
                "dequeue before release-please",
                "dequeue + rearm",
                "a queued release PR is taken out of the queue before release-please, and put back after",
            );
        }
        for (found, wanted, why) in problems {
            ctx.emit_fail(
                GROUP,
                &rel,
                &found,
                &wanted,
                &why,
                "copy the 'Build //tools/ci:release_pr_dequeue', 'Take a stale release PR out of the merge queue' and rearm steps from vitruvian-courier-release.yaml, with this workflow's own COMPONENT and CODE_PATH",
            );
        }
    }
    if seen == 0 {
        ctx.emit_fail(
            GROUP,
            ".github/workflows",
            "0 workflows",
            ">=1",
            "no workflow runs googleapis/release-please-action: the check or the workflow layout changed",
            "confirm the release workflows still use googleapis/release-please-action",
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONFIG: &str = r#"{"packages":{"apps/desktop/vitruvian-courier":{"package-name":"vitruvian-courier","component":"vitruvian-courier"}}}"#;

    fn config(_: &str) -> Option<String> {
        Some(CONFIG.to_string())
    }

    /// vitruvian-courier-release.yaml's release-please job, as it must be.
    const GOOD: &str = "\
name: vitruvian-courier-release
on:
  push:
    branches: [main]
jobs:
  release-please:
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@abc # v7.0.1
        with:
          persist-credentials: false

      - name: Mint App token for the release PR
        id: app-token
        uses: ./.github/actions/mint-sync-app-token

      # A comment between steps.
      - name: Build //tools/ci:release_pr_dequeue (no Bazel on this job)
        id: dequeue-bin
        if: ${{ inputs.tag == '' }}
        uses: ./.github/actions/build-ci-tool
        with:
          tool: release_pr_dequeue

      - name: Take a stale release PR out of the merge queue
        if: ${{ inputs.tag == '' }}
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          REPO: ${{ github.repository }}
          COMPONENT: vitruvian-courier
          CODE_PATH: apps/desktop/vitruvian-courier
          MAIN_SHA: ${{ github.sha }}
          DEQUEUE_BIN: ${{ steps.dequeue-bin.outputs.path }}
        run: '\"$DEQUEUE_BIN\"'

      - uses: googleapis/release-please-action@45996ed # v5.0.0
        id: release
        if: ${{ inputs.tag == '' }}
        with:
          token: ${{ steps.app-token.outputs.token }}
          config-file: apps/desktop/vitruvian-courier/release-please-config.json
          manifest-file: apps/desktop/vitruvian-courier/.release-please-manifest.json
          target-branch: main

      - name: Put the release PR back in the merge queue
        if: ${{ !cancelled() && steps.dequeue-bin.outcome == 'success' && (inputs.tag == '') }}
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          REPO: ${{ github.repository }}
          COMPONENT: vitruvian-courier
          DEQUEUE_BIN: ${{ steps.dequeue-bin.outputs.path }}
        run: '\"$DEQUEUE_BIN\" rearm'

  publish-package:
    needs: release-please
    runs-on: xcode-27
    steps:
      - run: echo publish
";

    fn bad(from: &str, to: &str) -> Vec<Problem> {
        assert!(GOOD.contains(from), "fixture lacks {from:?}");
        dequeue_problems(&GOOD.replacen(from, to, 1), false, &config)
    }

    #[test]
    fn the_good_job_has_no_problems() {
        let p = dequeue_problems(GOOD, false, &config);
        assert!(p.is_empty(), "{p:?}");
    }

    #[test]
    fn parse_steps_reads_each_step_of_each_job() {
        let s = parse_steps(GOOD);
        let rp: Vec<&Step> = s.iter().filter(|s| s.job == "release-please").collect();
        assert_eq!(rp.len(), 6);
        assert_eq!(rp[2].id, "dequeue-bin");
        assert_eq!(rp[2].with("tool"), Some("release_pr_dequeue"));
        assert_eq!(rp[3].env("COMPONENT"), Some("vitruvian-courier"));
        assert_eq!(bare(&rp[3].run), "$DEQUEUE_BIN");
        assert_eq!(
            rp[4].with("token"),
            Some("${{ steps.app-token.outputs.token }}")
        );
        assert_eq!(bare(&rp[5].run), "$DEQUEUE_BIN rearm");
        assert_eq!(s.iter().filter(|s| s.job == "publish-package").count(), 1);
    }

    /// The state on main before this check: release-please with nothing around it.
    #[test]
    fn a_release_please_job_with_no_dequeue_fails() {
        let start = GOOD.find("      # A comment between steps.").unwrap();
        let end = GOOD.find("      - uses: googleapis").unwrap();
        let rearm = GOOD.find("      - name: Put the release PR back").unwrap();
        let tail = GOOD.find("  publish-package:").unwrap();
        let none = format!(
            "{}{}{}",
            &GOOD[..start],
            &GOOD[end..rearm],
            &GOOD[tail - 1..]
        );
        let p = dequeue_problems(&none, false, &config);
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("no step builds release_pr_dequeue")),
            "{p:?}"
        );
    }

    #[test]
    fn building_the_tool_after_release_please_does_not_count() {
        let p = dequeue_problems(
            &GOOD.replace("tool: release_pr_dequeue", "tool: other_tool"),
            false,
            &config,
        );
        assert!(
            p.iter().any(|(f, _, _)| f.contains("no step builds")),
            "{p:?}"
        );
    }

    #[test]
    fn the_tool_built_but_never_run_fails() {
        let p = bad("run: '\"$DEQUEUE_BIN\"'", "run: echo skip");
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("no step runs \"$DEQUEUE_BIN\" between")),
            "{p:?}"
        );
    }

    #[test]
    fn a_dequeue_after_release_please_does_not_count() {
        // Move the dequeue's run to a step after release-please.
        let moved = GOOD.replacen("run: '\"$DEQUEUE_BIN\"'", "run: echo", 1)
            + "      - env:\n          X: y\n        run: '\"$DEQUEUE_BIN\"'\n";
        let p = dequeue_problems(&moved, false, &config);
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("no step runs \"$DEQUEUE_BIN\" between")),
            "{p:?}"
        );
    }

    #[test]
    fn the_dequeue_must_follow_release_pleases_guard() {
        // Unguarded: it would run on the workflow_dispatch tag path.
        let unguarded = GOOD.replacen(
            "        if: ${{ inputs.tag == '' }}\n        env:",
            "        env:",
            1,
        );
        let p = dequeue_problems(&unguarded, false, &config);
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("dequeue step if: none")),
            "{p:?}"
        );
        let p = bad(
            "        if: ${{ inputs.tag == '' }}\n        uses: ./.github/actions/build-ci-tool",
            "        uses: ./.github/actions/build-ci-tool",
        );
        assert!(
            p.iter().any(|(f, _, _)| f.contains("build step if: none")),
            "{p:?}"
        );
    }

    #[test]
    fn a_wrong_component_or_code_path_fails() {
        // The silent failure: another name finds no release PR and does nothing.
        let p = bad(
            "COMPONENT: vitruvian-courier\n          CODE_PATH",
            "COMPONENT: courier\n          CODE_PATH",
        );
        assert!(
            p.iter()
                .any(|(f, w, _)| f.contains("COMPONENT courier") && w == "vitruvian-courier"),
            "{p:?}"
        );
        let p = bad(
            "CODE_PATH: apps/desktop/vitruvian-courier",
            "CODE_PATH: apps/desktop/courier",
        );
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("CODE_PATH apps/desktop/courier")),
            "{p:?}"
        );
    }

    #[test]
    fn missing_env_fails() {
        for k in [
            "REPO",
            "COMPONENT",
            "CODE_PATH",
            "MAIN_SHA",
            "GH_TOKEN",
            "DEQUEUE_BIN",
        ] {
            let mut lines: Vec<&str> = GOOD.lines().collect();
            let at = lines
                .iter()
                .position(|l| l.trim_start().starts_with(&format!("{k}:")))
                .unwrap();
            lines.remove(at);
            let p = dequeue_problems(&lines.join("\n"), false, &config);
            assert!(
                p.iter().any(|(f, _, _)| f.contains(&format!("no {k}"))),
                "{k}: {p:?}"
            );
        }
    }

    #[test]
    fn the_token_must_be_the_release_please_token() {
        let p = bad(
            "GH_TOKEN: ${{ steps.app-token.outputs.token }}\n          REPO: ${{ github.repository }}\n          COMPONENT: vitruvian-courier\n          CODE_PATH",
            "GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n          REPO: ${{ github.repository }}\n          COMPONENT: vitruvian-courier\n          CODE_PATH",
        );
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("GH_TOKEN ${{ secrets.GITHUB_TOKEN }}")),
            "{p:?}"
        );
    }

    #[test]
    fn the_binary_path_must_come_from_the_build_step() {
        let p = bad(
            "DEQUEUE_BIN: ${{ steps.dequeue-bin.outputs.path }}\n        run: '\"$DEQUEUE_BIN\"'",
            "DEQUEUE_BIN: ${{ steps.other.outputs.path }}\n        run: '\"$DEQUEUE_BIN\"'",
        );
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("DEQUEUE_BIN ${{ steps.other.outputs.path }}")),
            "{p:?}"
        );
    }

    #[test]
    fn main_sha_must_be_the_triggering_commit() {
        let p = bad("MAIN_SHA: ${{ github.sha }}", "MAIN_SHA: main");
        assert!(
            p.iter().any(|(f, _, _)| f.contains("MAIN_SHA main")),
            "{p:?}"
        );
    }

    #[test]
    fn a_missing_rearm_fails_unless_exempt() {
        let cut = GOOD.find("      - name: Put the release PR back").unwrap();
        let end = GOOD.find("  publish-package:").unwrap();
        let none = format!("{}\n{}", &GOOD[..cut], &GOOD[end..]);
        let p = dequeue_problems(&none, false, &config);
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("rearm after release-please")),
            "{p:?}"
        );
        assert!(dequeue_problems(&none, true, &config).is_empty());
    }

    #[test]
    fn rearm_must_run_after_a_failed_release_please_but_not_a_cancelled_run() {
        // `success()` (the default) would skip it exactly when release-please failed.
        let p = bad(
            "if: ${{ !cancelled() && steps.dequeue-bin.outcome == 'success' && (inputs.tag == '') }}",
            "if: ${{ inputs.tag == '' }}",
        );
        assert!(
            p.iter()
                .any(|(f, _, _)| f.starts_with("job 'release-please': rearm step if:")),
            "{p:?}"
        );
        let p = bad("!cancelled() && ", "");
        assert!(
            p.iter().any(|(f, _, _)| f.contains("rearm step if:")),
            "{p:?}"
        );
    }

    #[test]
    fn rearm_and_dequeue_must_name_the_same_component() {
        let at = GOOD.rfind("COMPONENT: vitruvian-courier").unwrap();
        let changed = format!(
            "{}COMPONENT: vitruvian-other{}",
            &GOOD[..at],
            &GOOD[at + "COMPONENT: vitruvian-courier".len()..]
        );
        let p = dequeue_problems(&changed, false, &config);
        assert!(
            p.iter().any(|(f, _, _)| f.contains("rearm COMPONENT")),
            "{p:?}"
        );
    }

    const MATRIX: &str = "\
jobs:
  release-please:
    strategy:
      matrix:
        app: ${{ fromJson(needs.setup.outputs.matrix) }}
    steps:
      - id: dequeue-bin
        uses: ./.github/actions/build-ci-tool
        with:
          tool: release_pr_dequeue
      - env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          REPO: ${{ github.repository }}
          COMPONENT: ${{ steps.component.outputs.name }}
          CODE_PATH: ${{ matrix.app }}
          MAIN_SHA: ${{ github.sha }}
          DEQUEUE_BIN: ${{ steps.dequeue-bin.outputs.path }}
        run: '\"$DEQUEUE_BIN\"'
      - uses: googleapis/release-please-action@45996ed # v5.0.0
        with:
          token: ${{ steps.app-token.outputs.token }}
          config-file: ${{ matrix.app }}/release-please-config.json
      - if: ${{ !cancelled() && steps.dequeue-bin.outcome == 'success' }}
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          REPO: ${{ github.repository }}
          COMPONENT: ${{ steps.component.outputs.name }}
          DEQUEUE_BIN: ${{ steps.dequeue-bin.outputs.path }}
        run: '\"$DEQUEUE_BIN\" rearm'
";

    #[test]
    fn a_matrix_job_takes_component_and_path_from_the_matrix() {
        let nothing = |_: &str| -> Option<String> { None };
        let p = dequeue_problems(MATRIX, false, &nothing);
        assert!(p.is_empty(), "{p:?}");
        let fixed = MATRIX.replacen(
            "CODE_PATH: ${{ matrix.app }}",
            "CODE_PATH: apps/cli/vitruvian-devx",
            1,
        );
        let p = dequeue_problems(&fixed, false, &nothing);
        assert!(
            p.iter()
                .any(|(f, _, _)| f.contains("CODE_PATH is the fixed value")),
            "{p:?}"
        );
    }

    #[test]
    fn package_of_reads_one_package_only() {
        assert_eq!(
            package_of(CONFIG),
            Some((
                "apps/desktop/vitruvian-courier".into(),
                "vitruvian-courier".into()
            ))
        );
        assert_eq!(
            package_of(r#"{"packages":{"a":{"component":"x"},"b":{"component":"y"}}}"#),
            None
        );
        assert_eq!(package_of(r#"{"packages":{"a":{}}}"#), None);
        assert_eq!(package_of("not json"), None);
    }

    #[test]
    fn a_workflow_without_release_please_is_not_checked() {
        assert!(dequeue_problems(
            "jobs:\n  a:\n    steps:\n      - run: echo\n",
            false,
            &config
        )
        .is_empty());
    }
}
