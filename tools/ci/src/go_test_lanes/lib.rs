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

//! //tools/ci:go_test_lanes — fail when a Go test exists that no CI lane runs.
//!
//! Go tests in this repo run in one of three ways, and a test outside all
//! three is dead: it compiles on a laptop and never executes (#4178, #4205):
//!
//! - **Bazel** (`bazel test //...`): the `_test.go` file is listed in a
//!   non-`manual` `go_test` in its directory's BUILD file.
//! - **go-test-infra**: `"$GO_TEST_WITH_RETRY"` with no arguments in ci.yaml,
//!   which tests every module under the IaC roots that
//!   //tools/ci:go_test_with_retry itself computes (`iac_roots_in`).
//! - **example-build** (or any other job): `"$GO_TEST_WITH_RETRY" --root <dir>`
//!   in ci.yaml, which tests every module under `<dir>`.
//!
//! The lanes are read from ci.yaml and from go_test_with_retry's own code,
//! never from a list kept here, so moving a root or dropping a step changes
//! the verdict. A test that is deliberately run by hand (an integration test
//! behind a build tag) goes in allowlist.txt with its reason; an entry that
//! no longer exists, or that a lane now covers, is itself an error.
//!
//! Not modelled (none hits a file today): a go_test excluded by
//! `--test_tag_filters` (`e2e`) or `target_compatible_with`, and a
//! `//go:build <tag>` file under a go_test_with_retry root, which plain
//! `go test ./...` skips. A `.bazelignore`d path never counts as Bazel.
//!
//! Directories Go itself ignores (`testdata`, `vendor`, dot- and
//! `_`-prefixed) are skipped, as are `node_modules` and the `bazel-*` links.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// Where a test file is run, or why it is not.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Cover {
    Bazel,
    /// `go_test_with_retry` in the named ci.yaml job.
    Job(String),
    Allowlisted,
    Uncovered,
}

#[derive(Debug, Default)]
pub struct Report {
    /// Every `_test.go` (repo-relative) and how it is covered.
    pub files: BTreeMap<String, Cover>,
    /// The roots each ci.yaml job hands go_test_with_retry.
    pub lanes: Vec<(String, Vec<String>)>,
    /// `"$GO_TEST_WITH_RETRY"` steps that do not count as lanes, and why
    /// (`if: false`, `continue-on-error`, `|| true`, ...).
    pub disabled: Vec<(String, String)>,
    /// Allowlist entries that are missing or now covered.
    pub stale: Vec<String>,
}

impl Report {
    pub fn uncovered(&self) -> Vec<&str> {
        self.files
            .iter()
            .filter(|(_, c)| **c == Cover::Uncovered)
            .map(|(f, _)| f.as_str())
            .collect()
    }
    pub fn ok(&self) -> bool {
        self.uncovered().is_empty() && self.stale.is_empty()
    }
}

fn skip_dir(name: &str) -> bool {
    name.starts_with('.')
        || name.starts_with('_')
        || name.starts_with("bazel-")
        || matches!(name, "testdata" | "vendor" | "node_modules")
}

/// Repo-relative go.mod directories ("" is the root) and `_test.go` files.
fn walk(repo: &Path, rel: &str, mods: &mut Vec<String>, tests: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(repo.join(rel)) else {
        return;
    };
    for e in entries.flatten() {
        let Ok(ft) = e.file_type() else { continue };
        let name = e.file_name().to_string_lossy().into_owned();
        let path = if rel.is_empty() {
            name.clone()
        } else {
            format!("{rel}/{name}")
        };
        if ft.is_dir() {
            if !skip_dir(&name) {
                walk(repo, &path, mods, tests);
            }
        } else if ft.is_file() {
            if name == "go.mod" {
                mods.push(rel.to_string());
            } else if name.ends_with("_test.go") {
                tests.push(path);
            }
        }
    }
}

fn under(path: &str, dir: &str) -> bool {
    dir.is_empty() || path == dir || path.starts_with(&format!("{dir}/"))
}

/// The module a file belongs to: its nearest enclosing go.mod directory.
fn owner<'a>(file: &str, mods: &'a [String]) -> Option<&'a str> {
    mods.iter()
        .filter(|m| under(file, m))
        .max_by_key(|m| m.len())
        .map(String::as_str)
}

/// A BUILD file's text with its `#` comments blanked out. Strings ("...",
/// '...', and the triple-quoted forms) are kept intact, so a `#` inside one
/// is not a comment; a commented-out `go_test(...)` disappears.
pub fn strip_starlark_comments(text: &str) -> String {
    let b = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c == b'#' {
            while i < b.len() && b[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if c == b'"' || c == b'\'' {
            let triple = i + 2 < b.len() && b[i + 1] == c && b[i + 2] == c;
            let q = if triple { 3 } else { 1 };
            let start = i;
            i += q;
            while i < b.len() {
                if b[i] == b'\\' {
                    i += 2;
                    continue;
                }
                if b[i] == c && (!triple || (i + 2 < b.len() && b[i + 1] == c && b[i + 2] == c)) {
                    i += q;
                    break;
                }
                if !triple && b[i] == b'\n' {
                    break;
                }
                i += 1;
            }
            out.push_str(&text[start..i.min(b.len())]);
            continue;
        }
        let len = text[i..].chars().next().map_or(1, char::len_utf8);
        out.push_str(&text[i..i + len]);
        i += len;
    }
    out
}

/// Every `go_test(...)` call in a BUILD file's text (comments already
/// stripped).
fn go_test_blocks(build: &str) -> Vec<&str> {
    let mut blocks = Vec::new();
    let mut rest = build;
    let mut offset = 0;
    while let Some(i) = rest.find("go_test(") {
        let start = offset + i;
        let open = start + "go_test".len();
        let bytes = build.as_bytes();
        let (mut depth, mut j, mut in_str) = (0usize, open, false);
        while j < bytes.len() {
            match bytes[j] {
                b'"' => in_str = !in_str,
                b'(' if !in_str => depth += 1,
                b')' if !in_str => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                _ => {}
            }
            j += 1;
        }
        let end = (j + 1).min(build.len());
        blocks.push(&build[start..end]);
        offset = end;
        rest = &build[end..];
    }
    blocks
}

/// True when a `glob(...)` in the block matches test files (`*_test.go`).
/// A `data = glob(["testdata/**"])` beside listed srcs does not count.
fn globs_tests(block: &str) -> bool {
    block.match_indices("glob(").any(|(i, _)| {
        let rest = &block[i..];
        let call = &rest[..rest.find(')').map_or(rest.len(), |j| j + 1)];
        call.contains("_test.go")
    })
}

/// True when the file's directory BUILD lists it in a go_test that
/// `bazel test //...` runs (not tagged manual).
fn in_bazel_go_test(repo: &Path, file: &str) -> bool {
    let p = Path::new(file);
    let dir = p.parent().unwrap_or(Path::new(""));
    let base = p.file_name().unwrap_or_default().to_string_lossy();
    let quoted = format!("\"{base}\"");
    for build_name in ["BUILD.bazel", "BUILD"] {
        let Ok(raw) = fs::read_to_string(repo.join(dir).join(build_name)) else {
            continue;
        };
        let text = strip_starlark_comments(&raw);
        return go_test_blocks(&text)
            .iter()
            .any(|b| !b.contains("\"manual\"") && (b.contains(&quoted) || globs_tests(b)));
    }
    false
}

const CALL: &str = "\"$GO_TEST_WITH_RETRY\"";

fn indent(line: &str) -> usize {
    line.len() - line.trim_start().len()
}

/// A YAML scalar with its trailing ` # comment` and quotes removed.
fn scalar(v: &str) -> String {
    let v = match v.find(" #") {
        Some(i) => &v[..i],
        None => v,
    };
    v.trim()
        .trim_matches('"')
        .trim_matches('\'')
        .trim()
        .to_string()
}

/// The value of `key:` among `lines` at exactly `at` spaces of indent (a
/// step's first line is passed with its `- ` already blanked). A block
/// scalar (`>-`, `|`) is joined from its deeper lines.
fn key_value(lines: &[String], at: usize, key: &str) -> Option<String> {
    let prefix = format!("{key}:");
    for (i, l) in lines.iter().enumerate() {
        if indent(l) != at || !l.trim_start().starts_with(&prefix) {
            continue;
        }
        let v = l.trim_start()[prefix.len()..].trim();
        if v.starts_with('>') || v.starts_with('|') {
            let body: Vec<&str> = lines[i + 1..]
                .iter()
                .take_while(|n| n.trim().is_empty() || indent(n) > at)
                .map(|n| n.trim())
                .collect();
            return Some(body.join(" ").trim().to_string());
        }
        return Some(scalar(v));
    }
    None
}

/// True for an `if:` that can never be true: `false`, `${{ false }}`,
/// `0`, an empty string, or `false && ...` / `... && false`.
fn constant_false(cond: &str) -> bool {
    let mut c = cond.trim().to_string();
    if let Some(inner) = c.strip_prefix("${{").and_then(|x| x.strip_suffix("}}")) {
        c = inner.trim().to_string();
    }
    let c = c
        .trim()
        .trim_matches('(')
        .trim_matches(')')
        .trim()
        .to_lowercase();
    matches!(
        c.as_str(),
        "false" | "0" | "''" | "\"\"" | "null" | "!true" | "! true"
    ) || c.starts_with("false &&")
        || c.starts_with("false&&")
        || c.ends_with("&& false")
        || c.ends_with("&&false")
        || c.contains("&& false &&")
}

/// Why a ci.yaml `"$GO_TEST_WITH_RETRY"` step could pass with failing tests,
/// or None when its failure fails the job.
fn why_disabled(
    job_lines: &[String],
    step_lines: &[String],
    run: &[String],
    call_at: usize,
) -> Option<String> {
    if let Some(c) = key_value(job_lines, 4, "if") {
        if constant_false(&c) {
            return Some(format!("job `if: {c}` never runs"));
        }
    }
    if let Some(v) = key_value(job_lines, 4, "continue-on-error") {
        if v != "false" {
            return Some(format!("job `continue-on-error: {v}`"));
        }
    }
    if let Some(c) = key_value(step_lines, 8, "if") {
        if constant_false(&c) {
            return Some(format!("step `if: {c}` never runs"));
        }
    }
    if let Some(v) = key_value(step_lines, 8, "continue-on-error") {
        if v != "false" {
            return Some(format!("step `continue-on-error: {v}`"));
        }
    }
    // The command itself, with `\` continuations joined: anything after the
    // call that is not an argument can swallow its status (`|| true`,
    // `; true`, `|| :`, `| tee` without pipefail, `&`).
    let mut cmd = run[call_at].clone();
    let mut k = call_at;
    while cmd.trim_end().ends_with('\\') && k + 1 < run.len() {
        k += 1;
        cmd = format!(
            "{} {}",
            cmd.trim_end().trim_end_matches('\\'),
            run[k].trim()
        );
    }
    let tail = &cmd[cmd.find(CALL).unwrap() + CALL.len()..];
    let tail = match tail.find(" #") {
        Some(i) => &tail[..i],
        None => tail,
    };
    if tail.contains(['|', ';', '&']) {
        return Some(format!("its status can be swallowed: `{}`", cmd.trim()));
    }
    // GitHub runs bash with -e; a `set +e` before the call turns that off, so
    // a later command decides the step's status.
    if run[..call_at].iter().any(|l| {
        let t = l.trim();
        !t.starts_with('#') && (t.contains("set +e") || t.contains("set +o errexit"))
    }) && run[k + 1..]
        .iter()
        .any(|l| !l.trim().is_empty() && !l.trim().starts_with('#'))
    {
        return Some("`set +e` before it, and later commands decide the step's status".into());
    }
    None
}

/// The `"$GO_TEST_WITH_RETRY"` steps of ci.yaml, by job: each with the roots
/// it tests (its `--root` arguments, or go_test_with_retry's IaC roots when
/// it passes none) and, if it cannot fail the build, why not.
pub fn lanes_from_workflow(
    repo: &Path,
    ci_yaml: &str,
) -> Vec<(String, Vec<String>, Option<String>)> {
    let lines: Vec<String> = ci_yaml.lines().map(str::to_string).collect();
    let mut lanes = Vec::new();
    let Some(jobs_at) = lines.iter().position(|l| l.trim_end() == "jobs:") else {
        return lanes;
    };
    let is_job = |l: &str| {
        indent(l) == 2
            && l.trim_end().ends_with(':')
            && !l.trim_start().starts_with('#')
            && !l.trim().contains(' ')
    };
    let mut i = jobs_at + 1;
    while i < lines.len() {
        if !is_job(&lines[i]) {
            i += 1;
            continue;
        }
        let job = lines[i].trim().trim_end_matches(':').to_string();
        let end = (i + 1..lines.len())
            .find(|&j| is_job(&lines[j]) || (indent(&lines[j]) == 0 && !lines[j].trim().is_empty()))
            .unwrap_or(lines.len());
        let job_lines = &lines[i + 1..end];
        // Steps: each starts at `      - ` (6 spaces).
        let starts: Vec<usize> = (0..job_lines.len())
            .filter(|&j| indent(&job_lines[j]) == 6 && job_lines[j].trim_start().starts_with("- "))
            .collect();
        for (n, &st) in starts.iter().enumerate() {
            let se = starts.get(n + 1).copied().unwrap_or_else(|| {
                (st + 1..job_lines.len())
                    .find(|&j| !job_lines[j].trim().is_empty() && indent(&job_lines[j]) <= 4)
                    .unwrap_or(job_lines.len())
            });
            let mut step: Vec<String> = job_lines[st..se].to_vec();
            step[0] = step[0].replacen("- ", "  ", 1);
            // The run script: an inline `run: cmd`, or the block under `run: |`.
            let Some(ri) = step
                .iter()
                .position(|l| indent(l) == 8 && l.trim_start().starts_with("run:"))
            else {
                continue;
            };
            let inline = step[ri].trim_start()["run:".len()..].trim().to_string();
            let run: Vec<String> = if inline.starts_with('|') || inline.starts_with('>') {
                step[ri + 1..]
                    .iter()
                    .take_while(|l| l.trim().is_empty() || indent(l) > 8)
                    .cloned()
                    .collect()
            } else {
                vec![inline]
            };
            for (c, line) in run.iter().enumerate() {
                let code = line.trim_start();
                if code.starts_with('#') || !code.contains(CALL) {
                    continue;
                }
                let args: Vec<&str> = code[code.find(CALL).unwrap() + CALL.len()..]
                    .split_whitespace()
                    .collect();
                let mut roots: Vec<String> = Vec::new();
                let mut k = 0;
                while k < args.len() {
                    if args[k] == "--root" && k + 1 < args.len() {
                        roots.push(
                            args[k + 1]
                                .trim_matches('"')
                                .trim_end_matches('/')
                                .to_string(),
                        );
                        k += 2;
                    } else {
                        k += 1;
                    }
                }
                if roots.is_empty() {
                    let base = repo.to_string_lossy().into_owned();
                    roots = go_test_with_retry::iac_roots_in(base.as_bytes())
                        .into_iter()
                        .map(|r| String::from_utf8_lossy(&r).into_owned())
                        .collect();
                }
                let why = why_disabled(job_lines, &step, &run, c);
                lanes.push((job.clone(), roots, why));
            }
        }
        i = end;
    }
    lanes
}

/// The allowlist's paths: one per line, `#` starts a comment.
pub fn parse_allowlist(text: &str) -> Vec<String> {
    text.lines()
        .map(|l| l.split('#').next().unwrap_or("").trim())
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect()
}

pub fn check(repo: &Path, ci_yaml: &str, allowlist: &str) -> Result<Report, String> {
    let all = lanes_from_workflow(repo, ci_yaml);
    let disabled: Vec<(String, String)> = all
        .iter()
        .filter_map(|(j, _, why)| why.clone().map(|w| (j.clone(), w)))
        .collect();
    let lanes: Vec<(String, Vec<String>)> = all
        .into_iter()
        .filter(|(_, _, why)| why.is_none())
        .map(|(j, r, _)| (j, r))
        .collect();
    if lanes.is_empty() && disabled.is_empty() {
        return Err(
            "no \"$GO_TEST_WITH_RETRY\" step in ci.yaml: cannot tell which Go modules CI tests"
                .into(),
        );
    }
    let mut mods = Vec::new();
    let mut tests = Vec::new();
    walk(repo, "", &mut mods, &mut tests);
    let allow = parse_allowlist(allowlist);
    // Bazel never loads a package under a .bazelignore path, so a go_test
    // there is not run by `bazel test //...`.
    let bazel_ignored: Vec<String> = fs::read_to_string(repo.join(".bazelignore"))
        .unwrap_or_default()
        .lines()
        .map(|l| l.trim().trim_end_matches('/').to_string())
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .collect();

    let mut report = Report {
        lanes: lanes.clone(),
        disabled,
        ..Report::default()
    };
    for file in &tests {
        let module = owner(file, &mods);
        let job = module.and_then(|m| {
            lanes
                .iter()
                .find(|(_, roots)| roots.iter().any(|r| !r.is_empty() && under(m, r)))
                .map(|(j, _)| j.clone())
        });
        let cover = if !bazel_ignored.iter().any(|d| under(file, d)) && in_bazel_go_test(repo, file)
        {
            Cover::Bazel
        } else if let Some(j) = job {
            Cover::Job(j)
        } else if allow.contains(file) {
            Cover::Allowlisted
        } else {
            Cover::Uncovered
        };
        report.files.insert(file.clone(), cover);
    }
    for a in &allow {
        match report.files.get(a) {
            Some(Cover::Allowlisted) => {}
            Some(_) => report.stale.push(format!(
                "{a}: a lane covers it now; drop it from the allowlist"
            )),
            None => report
                .stale
                .push(format!("{a}: no such _test.go; drop it from the allowlist")),
        }
    }
    Ok(report)
}

pub const ALLOWLIST: &str = include_str!("allowlist.txt");

pub fn run(args: &[Vec<u8>]) -> i32 {
    // `bazel run` starts in the runfiles tree; check the checkout instead.
    let repo = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(d) if !d.is_empty() => d,
        _ => match args.first() {
            Some(a) => String::from_utf8_lossy(a).into_owned(),
            None => ".".to_string(),
        },
    };
    let repo = Path::new(&repo);
    let ci = match fs::read_to_string(repo.join(".github/workflows/ci.yaml")) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("::error::go_test_lanes: cannot read .github/workflows/ci.yaml: {e}");
            return 1;
        }
    };
    let report = match check(repo, &ci, ALLOWLIST) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("::error::go_test_lanes: {e}");
            return 1;
        }
    };
    for (job, roots) in &report.lanes {
        println!("lane {job}: go_test_with_retry over {}", roots.join(" "));
    }
    for (job, why) in &report.disabled {
        println!("NOT a lane: the go_test_with_retry step in {job}: {why}");
    }
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for c in report.files.values() {
        let k = match c {
            Cover::Bazel => "bazel test //...".to_string(),
            Cover::Job(j) => j.clone(),
            Cover::Allowlisted => "allowlisted".to_string(),
            Cover::Uncovered => "UNCOVERED".to_string(),
        };
        *counts.entry(k).or_default() += 1;
    }
    for (k, n) in &counts {
        println!("{n:>5} _test.go file(s): {k}");
    }
    for f in report.uncovered() {
        eprintln!(
            "::error file={f}::{f} is a Go test no CI lane runs: add it to a go_test (bazel run //:gazelle), move its module under a go_test_with_retry root, or allowlist it with a reason in tools/ci/src/go_test_lanes/allowlist.txt"
        );
    }
    for s in &report.stale {
        eprintln!("::error::go_test_lanes: stale allowlist entry {s}");
    }
    if report.ok() {
        println!("go_test_lanes: every Go test is run by a CI lane");
        0
    } else {
        1
    }
}

#[cfg(test)]
mod tests;
