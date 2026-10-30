// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! The mirror workflow check behind `:mirror_workflows_test`.
//! Parses `.github/workflows/{ci,kits,release}.yml`, executes the `detect` and
//! `Write the release notes` steps in temporary git repositories with `bash`,
//! and verifies workflow permissions, commit-pinned actions, credential persistence,
//! and PEP 740 PyPI attestation ordering.

use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::thread;

use conformance_rs_lib::json::{self, Value};
use conformance_rs_lib::{pystr, TempDir};

use crate::find_package_dir;

pub const NOTES_STEP: &str = "Write the release notes";
pub const NO_CHANGES: &str = "has no section for 0.9.0";

pub const FIRST: &str = "\
# Changelog

## 0.9.0 (2026-10-13)


### Features

* **vitruvian-sdk:** publish the SDK, version 0.9.0 ([#1](https://x/1)) ([abc1234](https://x/c))
";

pub const LATER: &str = "\
# Changelog

## [0.10.0](https://x/compare/v0.9.0...v0.10.0) (2026-11-01)


### Features

* the kits

## [0.9.0](https://x/compare/v0.8.0...v0.9.0) (2026-10-13)


### Bug Fixes

* a fix in 0.9.0

## 0.8.0 (2026-10-01)


### Features

* older work
";

pub const OTHER: &str = "\
# Changelog

## 0.8.0 (2026-10-01)


### Features

* older work
";

fn unquote_yaml(s: &str) -> String {
    let t = s.trim();
    if t.len() >= 2
        && ((t.starts_with('"') && t.ends_with('"')) || (t.starts_with('\'') && t.ends_with('\'')))
    {
        t[1..t.len() - 1].to_string()
    } else {
        t.to_string()
    }
}

fn strip_yaml_comment(s: &str) -> &str {
    let mut in_single = false;
    let mut in_double = false;
    let bytes = s.as_bytes();
    for i in 0..bytes.len() {
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
    }
    s.trim_end()
}

fn parse_yaml_scalar(raw: &str) -> Value {
    let s = strip_yaml_comment(raw).trim();
    if s == "true" {
        return Value::Bool(true);
    }
    if s == "false" {
        return Value::Bool(false);
    }
    if s == "null" || s == "~" {
        return Value::Null;
    }
    if s.starts_with('[') && s.ends_with(']') {
        let inner = &s[1..s.len() - 1];
        if inner.trim().is_empty() {
            return Value::Arr(Vec::new());
        }
        let items = inner
            .split(',')
            .map(|part| parse_yaml_scalar(part.trim()))
            .collect();
        return Value::Arr(items);
    }
    Value::Str(unquote_yaml(s))
}

fn split_yaml_key_val(line: &str) -> Option<(&str, &str)> {
    let mut in_single = false;
    let mut in_double = false;
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        match bytes[i] {
            b'\'' if !in_double => in_single = !in_single,
            b'"' if !in_single => in_double = !in_double,
            b':' if !in_single && !in_double => {
                if i + 1 == bytes.len() || bytes[i + 1].is_ascii_whitespace() {
                    let key = line[..i].trim();
                    let val = line[i + 1..].trim_start();
                    return Some((key, val));
                }
            }
            _ => {}
        }
    }
    None
}

fn parse_literal_block(lines: &[&str], idx: &mut usize, parent_indent: usize) -> Value {
    let mut collected: Vec<&str> = Vec::new();
    while *idx < lines.len() {
        let line = lines[*idx];
        if line.trim().is_empty() {
            collected.push("");
            *idx += 1;
            continue;
        }
        let indent = line.len() - line.trim_start_matches(' ').len();
        if indent <= parent_indent {
            break;
        }
        collected.push(line);
        *idx += 1;
    }
    while collected.last().is_some_and(|l| l.is_empty()) {
        collected.pop();
    }
    let block_indent = collected
        .iter()
        .filter(|l| !l.is_empty())
        .map(|l| l.len() - l.trim_start_matches(' ').len())
        .min()
        .unwrap_or(0);
    let mut out = String::new();
    for line in collected {
        if line.len() >= block_indent {
            out.push_str(&line[block_indent..]);
        }
        out.push('\n');
    }
    Value::Str(out)
}

fn skip_ignorable(lines: &[&str], idx: &mut usize) {
    while *idx < lines.len() {
        let t = lines[*idx].trim();
        if t.is_empty() || t.starts_with('#') {
            *idx += 1;
        } else {
            break;
        }
    }
}

fn parse_yaml_val_or_nested(
    lines: &[&str],
    idx: &mut usize,
    key_indent: usize,
    v_rest: &str,
) -> Value {
    let cleaned = strip_yaml_comment(v_rest).trim();
    if cleaned == "|" {
        parse_literal_block(lines, idx, key_indent)
    } else if cleaned.is_empty() {
        parse_yaml_node(lines, idx, key_indent + 1)
    } else {
        parse_yaml_scalar(cleaned)
    }
}

fn parse_yaml_mapping_entries(
    lines: &[&str],
    idx: &mut usize,
    map_indent: usize,
) -> Vec<(String, Value)> {
    let mut entries = Vec::new();
    loop {
        skip_ignorable(lines, idx);
        if *idx >= lines.len() {
            break;
        }
        let line = lines[*idx];
        let indent = line.len() - line.trim_start_matches(' ').len();
        if indent != map_indent {
            break;
        }
        let trimmed = line.trim_start_matches(' ');
        if trimmed.starts_with("- ") || trimmed == "-" {
            break;
        }
        let Some((key, v_rest)) = split_yaml_key_val(trimmed) else {
            break;
        };
        *idx += 1;
        let val = parse_yaml_val_or_nested(lines, idx, map_indent, v_rest);
        entries.push((unquote_yaml(key), val));
    }
    entries
}

fn parse_yaml_node(lines: &[&str], idx: &mut usize, min_indent: usize) -> Value {
    skip_ignorable(lines, idx);
    if *idx >= lines.len() {
        return Value::Null;
    }
    let line = lines[*idx];
    let indent = line.len() - line.trim_start_matches(' ').len();
    if indent < min_indent {
        return Value::Null;
    }
    let trimmed = line.trim_start_matches(' ');
    if trimmed.starts_with("- ") || trimmed == "-" {
        let seq_indent = indent;
        let mut items = Vec::new();
        loop {
            skip_ignorable(lines, idx);
            if *idx >= lines.len() {
                break;
            }
            let cur = lines[*idx];
            let cur_indent = cur.len() - cur.trim_start_matches(' ').len();
            if cur_indent != seq_indent {
                break;
            }
            let cur_trimmed = cur.trim_start_matches(' ');
            if !(cur_trimmed.starts_with("- ") || cur_trimmed == "-") {
                break;
            }
            let after_dash = cur_trimmed[1..].trim_start_matches(' ');
            *idx += 1;
            if after_dash.is_empty() {
                items.push(parse_yaml_node(lines, idx, seq_indent + 1));
            } else if let Some((k, v_rest)) = split_yaml_key_val(after_dash) {
                let item_indent = cur.len() - after_dash.len();
                let mut map_entries = Vec::new();
                let first_val = parse_yaml_val_or_nested(lines, idx, item_indent, v_rest);
                map_entries.push((unquote_yaml(k), first_val));
                map_entries.extend(parse_yaml_mapping_entries(lines, idx, item_indent));
                items.push(Value::Obj(map_entries));
            } else {
                items.push(parse_yaml_scalar(after_dash));
            }
        }
        Value::Arr(items)
    } else {
        Value::Obj(parse_yaml_mapping_entries(lines, idx, indent))
    }
}

/// Parses a GitHub Actions workflow YAML document into a `Value`.
pub fn parse_yaml(text: &str) -> Value {
    let lines: Vec<&str> = text.lines().collect();
    let mut idx = 0;
    parse_yaml_node(&lines, &mut idx, 0)
}

pub fn load_workflow(workflows_dir: &Path, name: &str) -> Value {
    let path = workflows_dir.join(name);
    let text = fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    parse_yaml(&text)
}

pub fn detect_step(release: &Value) -> String {
    let steps = release
        .get("jobs")
        .and_then(|j| j.get("detect"))
        .and_then(|d| d.get("steps"))
        .and_then(|s| s.as_arr())
        .expect("release.jobs.detect.steps");
    for step in steps {
        if step.get("id").and_then(|v| v.as_str()) == Some("detect") {
            if let Some(run) = step.get("run").and_then(|r| r.as_str()) {
                return run.to_string();
            }
        }
    }
    panic!("release.yml has no step with the id detect");
}

pub fn detect(script: &str, manifest: Option<&str>, tags: &[&str]) -> (i32, String, String) {
    let temp = TempDir::new("vitruvian-detect-").expect("temp dir");
    let root = temp.path();

    let run_git = |args: &[&str]| {
        let status = Command::new("git")
            .args(["-c", "user.name=t", "-c", "user.email=t@t"])
            .args(args)
            .current_dir(root)
            .output()
            .expect("git command");
        assert!(status.status.success(), "git {:?} failed", args);
    };

    run_git(&["init", "-q"]);
    if let Some(m_ver) = manifest {
        let obj = Value::Obj(vec![(
            "packages/vitruvian-sdk".into(),
            Value::Str(m_ver.into()),
        )]);
        fs::write(
            root.join(".release-please-manifest.json"),
            obj.dumps_compact(),
        )
        .unwrap();
    }
    fs::write(root.join("README.md"), "x\n").unwrap();
    run_git(&["add", "-A"]);
    run_git(&["commit", "-q", "-m", "m"]);
    for &tag in tags {
        run_git(&["tag", tag]);
    }
    let output_path = root.join(".output");
    fs::write(&output_path, "").unwrap();

    let path_env = env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_string());
    let done = Command::new("bash")
        .args(["--noprofile", "--norc", "-eo", "pipefail", "-c", script])
        .current_dir(root)
        .env_clear()
        .env("PATH", path_env)
        .env("GITHUB_OUTPUT", &output_path)
        .output()
        .expect("bash command");

    let status = done.status.code().unwrap_or(1);
    let got = fs::read_to_string(&output_path)
        .unwrap_or_default()
        .trim()
        .to_string();
    let printed = format!(
        "{}{}",
        String::from_utf8_lossy(&done.stdout),
        String::from_utf8_lossy(&done.stderr)
    );
    (status, got, printed)
}

pub fn detect_problems(release: &Value) -> Vec<String> {
    let script = detect_step(release);
    let cases: &[(Option<&str>, &[&str], i32, &str)] = &[
        (None, &[], 0, ""),
        (Some("0.0.0"), &[], 0, ""),
        (Some("0.9.0"), &[], 0, "version=0.9.0"),
        (Some("0.9.0"), &["v0.9.0"], 0, ""),
        (
            Some("0.9.0"),
            &["go/v0.9.0", "vitruvian-sdk-v0.9.0"],
            0,
            "version=0.9.0",
        ),
        (Some("0.9"), &[], 1, ""),
    ];

    let results: Vec<Option<String>> = thread::scope(|s| {
        let handles: Vec<_> = cases
            .iter()
            .map(|&(manifest, tags, status, wanted)| {
                let script_ref = &script;
                s.spawn(move || {
                    let (got_status, got, printed) = detect(script_ref, manifest, tags);
                    if (got_status, got.as_str()) != (status, wanted) {
                        let manifest_disp = manifest.unwrap_or("None");
                        let tags_repr = Value::Arr(
                            tags.iter().map(|t| Value::Str((*t).to_string())).collect(),
                        )
                        .py_repr();
                        Some(format!(
                            "detect with manifest {manifest_disp} and tags {tags_repr}: exit {got_status} and {}, want exit {status} and {}\n{printed}",
                            pystr::repr_str(&got),
                            pystr::repr_str(wanted)
                        ))
                    } else {
                        None
                    }
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });

    results.into_iter().flatten().collect()
}

pub fn notes_step(release: &Value) -> String {
    let steps = release
        .get("jobs")
        .and_then(|j| j.get("release"))
        .and_then(|r| r.get("steps"))
        .and_then(|s| s.as_arr())
        .expect("release.jobs.release.steps");
    for step in steps {
        if step.get("name").and_then(|v| v.as_str()) == Some(NOTES_STEP) {
            if let Some(run) = step.get("run").and_then(|r| r.as_str()) {
                return run.to_string();
            }
        }
    }
    panic!("release.yml's release job has no step named {NOTES_STEP:?}");
}

pub fn notes(script: &str, changelog: Option<&str>) -> (i32, String, String) {
    let temp = TempDir::new("vitruvian-notes-").expect("temp dir");
    let root = temp.path();
    if let Some(cl) = changelog {
        fs::write(root.join("CHANGELOG.md"), cl).unwrap();
    }
    let path_env = env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_string());
    let done = Command::new("bash")
        .args(["--noprofile", "--norc", "-eo", "pipefail", "-c", script])
        .current_dir(root)
        .env_clear()
        .env("PATH", path_env)
        .env("RUNNER_TEMP", root)
        .env("V", "0.9.0")
        .output()
        .expect("bash command");

    let status = done.status.code().unwrap_or(1);
    let written = root.join("notes.md");
    let text = fs::read_to_string(written).unwrap_or_default();
    let printed = format!(
        "{}{}",
        String::from_utf8_lossy(&done.stdout),
        String::from_utf8_lossy(&done.stderr)
    );
    (status, text, printed)
}

pub fn notes_problems(release: &Value) -> Vec<String> {
    let script = notes_step(release);
    let cases: &[(&str, Option<&str>, &[&str], &[&str])] = &[
        ("no CHANGELOG.md", None, &[NO_CHANGES], &[]),
        (
            "a first release",
            Some(FIRST),
            &["## Features", "publish the SDK"],
            &[NO_CHANGES],
        ),
        (
            "a later release",
            Some(LATER),
            &["## Bug Fixes", "a fix in 0.9.0"],
            &[NO_CHANGES, "the kits", "older work"],
        ),
        (
            "no section for 0.9.0",
            Some(OTHER),
            &[NO_CHANGES],
            &["older work"],
        ),
    ];

    let results: Vec<Vec<String>> = thread::scope(|s| {
        let handles: Vec<_> = cases
            .iter()
            .map(|&(name, changelog, wanted, unwanted)| {
                let script_ref = &script;
                s.spawn(move || {
                    let mut probs = Vec::new();
                    let (status, text, printed) = notes(script_ref, changelog);
                    if status != 0 {
                        probs.push(format!("notes with {name}: exit {status}\n{printed}"));
                        return probs;
                    }
                    let mut all_wanted = vec!["brew install VitruvianSoftware/tap/vitruvian-tool"];
                    all_wanted.extend_from_slice(wanted);
                    for line in all_wanted {
                        if !text.contains(line) {
                            probs.push(format!(
                                "notes with {name}: no {}\n{text}",
                                pystr::repr_str(line)
                            ));
                        }
                    }
                    for &line in unwanted {
                        if text.contains(line) {
                            probs.push(format!(
                                "notes with {name}: has {}\n{text}",
                                pystr::repr_str(line)
                            ));
                        }
                    }
                    probs
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });

    results.into_iter().flatten().collect()
}

fn is_pinned_action(uses: &str) -> bool {
    let Some((repo_path, sha)) = uses.split_once('@') else {
        return false;
    };
    if sha.len() != 40
        || !sha
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return false;
    }
    let Some((owner, rest)) = repo_path.split_once('/') else {
        return false;
    };
    !owner.is_empty()
        && owner
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.' || b == b'-')
        && !rest.is_empty()
        && rest
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.' || b == b'/' || b == b'-')
}

pub fn limit_problems(name: &str, workflow: &Value) -> Vec<String> {
    let mut problems = Vec::new();
    let wanted_perms = Value::Obj(vec![("contents".into(), Value::Str("read".into()))]);
    let got_perms = workflow.get("permissions").cloned().unwrap_or(Value::Null);
    if !json::py_eq(&got_perms, &wanted_perms) {
        problems.push(format!(
            "{name}: the workflow's permissions are not contents: read"
        ));
    }

    if let Some(jobs) = workflow.get("jobs").and_then(|j| j.as_obj()) {
        for (job_name, job) in jobs {
            let mut writes: Vec<String> = job
                .get("permissions")
                .and_then(|p| p.as_obj())
                .into_iter()
                .flatten()
                .filter(|(_, v)| v.as_str() == Some("write"))
                .map(|(k, _)| k.clone())
                .collect();
            writes.sort();

            let allowed: Vec<String> = match (name, job_name.as_str()) {
                ("release.yml", "release") => vec!["contents".to_string()],
                ("release.yml", "publish-npm-kit")
                | ("release.yml", "publish-pypi-kit")
                | ("release.yml", "crates-publish") => vec!["id-token".to_string()],
                _ => Vec::new(),
            };
            if writes != allowed {
                let writes_repr =
                    Value::Arr(writes.into_iter().map(Value::Str).collect()).py_repr();
                let allowed_repr =
                    Value::Arr(allowed.into_iter().map(Value::Str).collect()).py_repr();
                problems.push(format!(
                    "{name}: job {job_name} may write {writes_repr}, not {allowed_repr}"
                ));
            }

            if let Some(steps) = job.get("steps").and_then(|s| s.as_arr()) {
                for step in steps {
                    let Some(uses) = step.get("uses").and_then(|u| u.as_str()) else {
                        continue;
                    };
                    if !is_pinned_action(uses) {
                        problems.push(format!("{name}: {uses} is not pinned to a commit"));
                    }
                    if uses.starts_with("actions/checkout@") {
                        let persist = step
                            .get("with")
                            .and_then(|w| w.get("persist-credentials"))
                            .and_then(|p| p.as_bool());
                        if persist != Some(false) {
                            problems.push(format!(
                                "{name}: job {job_name} checks out with its credentials kept"
                            ));
                        }
                    }
                }
            }
        }
    }
    problems
}

pub fn attest_problems(release: &Value) -> Vec<String> {
    let steps = release
        .get("jobs")
        .and_then(|j| j.get("publish-pypi-kit"))
        .and_then(|p| p.get("steps"))
        .and_then(|s| s.as_arr())
        .expect("publish-pypi-kit steps");

    let publish: Vec<usize> = steps
        .iter()
        .enumerate()
        .filter(|(_, s)| {
            s.get("run")
                .and_then(|r| r.as_str())
                .is_some_and(|r| r.contains("uv publish"))
        })
        .map(|(i, _)| i)
        .collect();

    let attest: Vec<usize> = steps
        .iter()
        .enumerate()
        .filter(|(_, s)| {
            s.get("uses")
                .and_then(|u| u.as_str())
                .is_some_and(|u| u.starts_with("astral-sh/attest-action@"))
        })
        .map(|(i, _)| i)
        .collect();

    if publish.len() != 1 {
        return vec![format!(
            "release.yml: publish-pypi-kit has {} `uv publish` steps, not one",
            publish.len()
        )];
    }

    let mut problems = Vec::new();
    if attest.len() != 1 || attest[0] > publish[0] {
        problems.push(
            "release.yml: publish-pypi-kit does not attest the files before `uv publish`: PyPI would have nothing public to say about who published them".to_string(),
        );
    } else {
        let paths_val = steps[attest[0]]
            .get("with")
            .and_then(|w| w.get("paths"))
            .and_then(|p| p.as_str());
        if paths_val != Some("kits/python/dist/*") {
            problems.push(
                "release.yml: the attest step does not attest kits/python/dist/*, which is what `uv publish` uploads".to_string(),
            );
        }
    }

    let pub_run = steps[publish[0]]
        .get("run")
        .and_then(|r| r.as_str())
        .unwrap_or("");
    if pub_run.contains("--no-attestations") {
        problems.push("release.yml: `uv publish` is told not to upload attestations".to_string());
    }
    problems
}

pub fn run_in(package_dir: &Path) -> (i32, Vec<String>, String) {
    let workflows_dir = package_dir.join(".github").join("workflows");
    let release = load_workflow(&workflows_dir, "release.yml");
    let ci = load_workflow(&workflows_dir, "ci.yml");
    let kits = load_workflow(&workflows_dir, "kits.yml");

    let (mut problems, notes_probs) = thread::scope(|s| {
        let h_detect = s.spawn(|| detect_problems(&release));
        let h_notes = s.spawn(|| notes_problems(&release));
        (h_detect.join().unwrap(), h_notes.join().unwrap())
    });
    problems.extend(notes_probs);
    problems.extend(attest_problems(&release));
    for (name, wf) in [
        ("ci.yml", &ci),
        ("kits.yml", &kits),
        ("release.yml", &release),
    ] {
        problems.extend(limit_problems(name, wf));
    }

    let status_word = if problems.is_empty() { "OK" } else { "FAILED" };
    let stdout_text = format!("mirror workflows: {status_word}\n");
    let code = if problems.is_empty() { 0 } else { 1 };
    (code, problems, stdout_text)
}

pub fn main() -> i32 {
    let package_dir = match find_package_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };
    let (code, problems, stdout_text) = run_in(&package_dir);
    for problem in problems {
        eprintln!("{problem}");
    }
    print!("{stdout_text}");
    code
}
