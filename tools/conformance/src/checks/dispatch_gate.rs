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

//! CHECK `DISPATCHGATE`: a hand-started run of a branch never reaches a
//! GitHub Environment.
//!
//! A `workflow_dispatch` run executes the workflow file and the code of the
//! ref it is started on, which can be any branch. Anyone who can push a branch
//! could otherwise run that branch's code in a job holding an Environment's
//! deploy secrets (a Stripe or PagerDuty key, a deploy identity). The
//! Environments' deployment-branch policies (repo-config) refuse that too, but
//! an Environment GitHub creates on first use has no policy at all, so every
//! such job also carries `github.ref == 'refs/heads/main'` in its `if:`
//! (precedent: `_repo-config-apply.yaml`, #5448).
//!
//! In a workflow with a `workflow_dispatch` trigger, the check covers every
//! job that binds `environment:`, and every job that calls a local reusable
//! workflow (`uses: ./.github/workflows/…`) one of whose jobs binds one: a
//! reusable workflow runs with its caller's ref, so the caller carries the
//! gate. Jobs that only read repository-level secrets are out of scope: any
//! branch can already read those through its own `push` workflow, so a ref
//! gate would protect nothing. The check reads text, not expressions: it
//! catches a forgotten gate, not one written to defeat it.

use crate::Context;

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

const GROUP: &str = "dispatchgate";

/// The gate, as written. GitHub expressions only take single-quoted strings.
const GATE: &str = "github.ref == 'refs/heads/main'";

#[derive(Debug, Default, PartialEq)]
pub(crate) struct Job {
    pub id: String,
    pub binds_environment: bool,
    pub uses: Option<String>,
    pub condition: String,
}

#[derive(Debug, Default, PartialEq)]
pub(crate) struct Workflow {
    pub dispatchable: bool,
    pub jobs: Vec<Job>,
}

fn indent(line: &str) -> usize {
    line.bytes().take_while(|&b| b == b' ').count()
}

/// Strips a trailing ` # comment` that is not inside quotes.
fn strip_comment(s: &str) -> &str {
    let (mut single, mut double) = (false, false);
    let bytes = s.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        match b {
            b'\'' if !double => single = !single,
            b'"' if !single => double = !double,
            b'#' if !single && !double && (i == 0 || bytes[i - 1] == b' ') => {
                return s[..i].trim_end();
            }
            _ => {}
        }
    }
    s.trim_end()
}

fn is_block_scalar(v: &str) -> bool {
    matches!(v, "|" | "|-" | "|+" | ">" | ">-" | ">+")
}

/// Parses the parts of a workflow this check needs. Line-based, like the other
/// workflow checks here: it understands block mappings, inline `on:` values
/// and block-scalar `if:` values, which is every form this repo writes.
pub(crate) fn parse(content: &str) -> Workflow {
    let lines: Vec<&str> = content.lines().map(|l| l.trim_end_matches('\r')).collect();
    let mut wf = Workflow::default();
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        let t = strip_comment(line.trim_start());
        if indent(line) != 0 || t.is_empty() {
            i += 1;
            continue;
        }
        if let Some(rest) = t
            .strip_prefix("on:")
            .or_else(|| t.strip_prefix("\"on\":"))
            .or_else(|| t.strip_prefix("'on':"))
        {
            let inline = rest.trim();
            if !inline.is_empty() {
                wf.dispatchable = inline
                    .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                    .any(|w| w == "workflow_dispatch");
            }
            i += 1;
            while i < lines.len() && (indent(lines[i]) > 0 || lines[i].trim().is_empty()) {
                let k = strip_comment(lines[i].trim_start());
                let k = k.strip_prefix("- ").unwrap_or(k);
                if k == "workflow_dispatch" || k.starts_with("workflow_dispatch:") {
                    wf.dispatchable = true;
                }
                i += 1;
            }
            continue;
        }
        if t == "jobs:" {
            i = parse_jobs(&lines, i + 1, &mut wf.jobs);
            continue;
        }
        i += 1;
    }
    wf
}

fn parse_jobs(lines: &[&str], mut i: usize, out: &mut Vec<Job>) -> usize {
    let mut job_indent = 0;
    let mut key_indent = 0;
    while i < lines.len() {
        let line = lines[i];
        let t = strip_comment(line.trim_start());
        if t.is_empty() {
            i += 1;
            continue;
        }
        let ind = indent(line);
        if ind == 0 {
            return i;
        }
        if job_indent == 0 {
            job_indent = ind;
        }
        if ind == job_indent {
            if let Some(id) = t.strip_suffix(':') {
                out.push(Job {
                    id: id.trim_matches(|c| c == '"' || c == '\'').to_string(),
                    ..Job::default()
                });
                key_indent = 0;
            }
            i += 1;
            continue;
        }
        let Some(job) = out.last_mut() else {
            i += 1;
            continue;
        };
        if key_indent == 0 {
            key_indent = ind;
        }
        if ind != key_indent {
            i += 1;
            continue;
        }
        if t == "environment:" || t.starts_with("environment:") {
            job.binds_environment = true;
        } else if let Some(v) = t.strip_prefix("uses:") {
            job.uses = Some(v.trim().trim_matches(|c| c == '"' || c == '\'').to_string());
        } else if let Some(v) = t.strip_prefix("if:") {
            let v = v.trim();
            if is_block_scalar(v) {
                let mut parts = Vec::new();
                i += 1;
                while i < lines.len()
                    && (lines[i].trim().is_empty() || indent(lines[i]) > key_indent)
                {
                    parts.push(lines[i].trim());
                    i += 1;
                }
                job.condition = parts.join(" ");
                continue;
            }
            job.condition = v.to_string();
        }
        i += 1;
    }
    i
}

fn has_gate(condition: &str) -> bool {
    condition.contains(GATE)
}

/// `./.github/workflows/<name>` → `<name>`, for local reusable workflows only.
fn local_workflow(uses: &str) -> Option<&str> {
    uses.strip_prefix("./.github/workflows/")
}

/// Every (workflow, job) that holds an Environment, can be started by hand and
/// does not require main. `workflows` is (file name, parsed workflow).
pub(crate) fn problems(workflows: &[(String, Workflow)]) -> (usize, Vec<(String, String, String)>) {
    let binds: BTreeSet<&str> = workflows
        .iter()
        .filter(|(_, w)| w.jobs.iter().any(|j| j.binds_environment))
        .map(|(n, _)| n.as_str())
        .collect();
    let mut checked = 0;
    let mut out = Vec::new();
    for (name, wf) in workflows.iter().filter(|(_, w)| w.dispatchable) {
        for job in &wf.jobs {
            let why = if job.binds_environment {
                "binds a GitHub Environment".to_string()
            } else if let Some(callee) = job.uses.as_deref().and_then(local_workflow) {
                if !binds.contains(callee) {
                    continue;
                }
                format!("calls {callee}, which binds a GitHub Environment")
            } else {
                continue;
            };
            checked += 1;
            if !has_gate(&job.condition) {
                out.push((name.clone(), job.id.clone(), why));
            }
        }
    }
    (checked, out)
}

pub fn check_dispatch_gate(ctx: &Context) {
    let dir = Path::new(&ctx.workflows_dir);
    let Ok(rd) = fs::read_dir(dir) else {
        return;
    };
    let mut workflows: Vec<(String, Workflow)> = rd
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().to_string();
            if !(name.ends_with(".yaml") || name.ends_with(".yml")) {
                return None;
            }
            let content = fs::read_to_string(e.path()).ok()?;
            Some((name, parse(&content)))
        })
        .collect();
    workflows.sort_by(|a, b| a.0.cmp(&b.0));

    let (checked, bad) = problems(&workflows);
    for (wf, job, why) in &bad {
        ctx.emit_fail(
            GROUP,
            &format!(".github/workflows/{wf}"),
            job,
            "github.ref == 'refs/heads/main'",
            &format!(
                "job can be started by hand from any branch and {why}: that branch's code would run with the Environment's secrets"
            ),
            &format!(
                "add github.ref == 'refs/heads/main' to the '{job}' job's if: (in a generated delivery-*.yaml, the generator's dispatch arm writes it)"
            ),
        );
    }
    if checked == 0 {
        ctx.emit_fail(
            GROUP,
            ".github/workflows",
            "0 jobs",
            ">=1",
            "no hand-startable job that binds an Environment was found \u{2014} the parser or the workflow layout changed",
            "confirm delivery-stripe.yaml still has workflow_dispatch and an environment: job",
        );
    } else if bad.is_empty() {
        ctx.emit_ok(
            GROUP,
            ".github/workflows",
            &format!("{checked} jobs"),
            "main only",
            "every hand-startable job that holds an Environment requires main",
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wfs(files: &[(&str, &str)]) -> Vec<(String, Workflow)> {
        files
            .iter()
            .map(|(n, c)| (n.to_string(), parse(c)))
            .collect()
    }

    const UNGATED: &str = "\
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        type: string
jobs:
  build:
    runs-on: ubuntu-26.04
  deploy:
    # comment at key indent
    needs: build
    environment: stripe-production
    steps:
      - run: echo hi
";

    #[test]
    fn ungated_environment_job_fails() {
        let (n, bad) = problems(&wfs(&[("d.yaml", UNGATED)]));
        assert_eq!(n, 1);
        assert_eq!(bad.len(), 1);
        assert_eq!(bad[0].0, "d.yaml");
        assert_eq!(bad[0].1, "deploy");
    }

    #[test]
    fn the_input_named_environment_is_not_a_binding() {
        let wf = parse(UNGATED);
        let build = wf.jobs.iter().find(|j| j.id == "build").unwrap();
        assert!(!build.binds_environment);
        assert_eq!(wf.jobs.len(), 2);
    }

    #[test]
    fn gated_job_passes_in_every_written_form() {
        for cond in [
            "    if: github.ref == 'refs/heads/main'\n",
            "    if: ${{ github.ref == 'refs/heads/main' && inputs.confirm == inputs.stack }}\n",
            "    if: >-\n      always() &&\n      github.ref == 'refs/heads/main'\n",
            "    if: (github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main' && inputs.unit == 'x') # trailing\n",
        ] {
            let c = UNGATED.replace("    needs: build\n", &format!("    needs: build\n{cond}"));
            let (n, bad) = problems(&wfs(&[("d.yaml", &c)]));
            assert_eq!((n, bad.len()), (1, 0), "{cond}");
        }
    }

    #[test]
    fn a_gate_in_a_step_does_not_count() {
        let c = UNGATED.replace(
            "      - run: echo hi\n",
            "      - if: github.ref == 'refs/heads/main'\n        run: echo hi\n",
        );
        assert_eq!(problems(&wfs(&[("d.yaml", &c)])).1.len(), 1);
    }

    #[test]
    fn not_dispatchable_is_out_of_scope() {
        let c = UNGATED.replace(
            "  workflow_dispatch:\n    inputs:\n      environment:\n        type: string\n",
            "",
        );
        assert!(!parse(&c).dispatchable);
        assert_eq!(problems(&wfs(&[("d.yaml", &c)])), (0, vec![]));
    }

    #[test]
    fn inline_triggers_are_read() {
        assert!(parse("on: workflow_dispatch\njobs: {}\n").dispatchable);
        assert!(parse("on: [push, workflow_dispatch]\n").dispatchable);
        assert!(!parse("on: [push, workflow_call]\n").dispatchable);
        assert!(parse("on:\n  - push\n  - workflow_dispatch\n").dispatchable);
    }

    #[test]
    fn caller_of_an_environment_binding_reusable_workflow_must_gate() {
        let callee = "on:\n  workflow_call:\njobs:\n  apply:\n    environment: ${{ inputs.env }}\n";
        let other = "on:\n  workflow_call:\njobs:\n  sum:\n    runs-on: x\n";
        let caller = "\
on:
  workflow_dispatch:
jobs:
  deploy:
    uses: ./.github/workflows/_apply.yaml
    secrets: inherit
  summary:
    uses: ./.github/workflows/_summary.yaml
  gated:
    if: github.ref == 'refs/heads/main'
    uses: ./.github/workflows/_apply.yaml
";
        let (n, bad) = problems(&wfs(&[
            ("_apply.yaml", callee),
            ("_summary.yaml", other),
            ("caller.yaml", caller),
        ]));
        assert_eq!(n, 2, "deploy and gated; summary's callee binds nothing");
        assert_eq!(bad.len(), 1);
        assert_eq!(bad[0].1, "deploy");
        assert!(bad[0].2.contains("_apply.yaml"));
    }

    /// The real workflows: every hand-startable job that holds an Environment
    /// requires main. Read from the source tree so this test fails in
    /// `bazel test` too, not only in `bazel run //tools/conformance:check`.
    #[test]
    fn the_repository_workflows_pass() {
        let Some(root) = repo_root() else {
            // Under Bazel the workflows are a data dep, so not finding them
            // is a broken test, not a reason to pass.
            assert!(
                std::env::var_os("TEST_SRCDIR").is_none(),
                "//:workflow_files is not in the test's runfiles"
            );
            eprintln!("no source tree visible; covered by :check in CI");
            return;
        };
        let dir = root.join(".github/workflows");
        let mut all = Vec::new();
        for e in fs::read_dir(&dir).unwrap().flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if name.ends_with(".yaml") || name.ends_with(".yml") {
                all.push((name, parse(&fs::read_to_string(e.path()).unwrap())));
            }
        }
        let (n, bad) = problems(&all);
        assert!(
            n >= 10,
            "only {n} jobs checked: the parser lost the workflows"
        );
        assert!(bad.is_empty(), "ungated jobs: {bad:?}");
    }

    fn repo_root() -> Option<std::path::PathBuf> {
        let candidates = [
            std::env::var("BUILD_WORKSPACE_DIRECTORY").ok(),
            std::env::var("TEST_SRCDIR")
                .ok()
                .map(|s| format!("{s}/_main")),
            Some(".".to_string()),
        ];
        candidates
            .into_iter()
            .flatten()
            .map(std::path::PathBuf::from)
            .find(|p| p.join(".github/workflows/delivery-stripe.yaml").is_file())
    }
}
