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

//! A tool's release starts its catalog update.
//!
//! catalog-bump starts when a release workflow named in its workflow_run list
//! finishes. That list has to match catalog/sources.json: a tool released from
//! this repository whose workflow is missing from it would wait for the hourly
//! run, which GitHub often drops. These tests read the live files, with no
//! network.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use crate::json::{self, Dict, Value};
use crate::{here, py};

const THIS_REPO: &str = "VitruvianSoftware/vitruvian-core";

/// Why `workflow` would not start when a change to the catalog merges,
/// or None. A merged bump changes catalog/tools.json, and that is when its
/// sibling bump pull requests stop merging and need rebuilding.
fn push_trigger_problem(workflow: &Value) -> Option<String> {
    let on = workflow.field("on")?;
    let push = match on.field("push") {
        Some(v) if v != &Value::Null => v,
        _ => return Some("catalog-bump has no push trigger".to_string()),
    };
    let expected_branches = Value::List(vec![py::s("main")]);
    if push.field("branches") != Some(&expected_branches) {
        let b = push.field("branches").cloned().unwrap_or(Value::Null);
        return Some(format!(
            "its push trigger must be for main only, not {}",
            b.py_repr()
        ));
    }
    let expected_paths = Value::List(vec![py::s("catalog/tools.json")]);
    if push.field("paths") != Some(&expected_paths) {
        let p = push.field("paths").cloned().unwrap_or(Value::Null);
        return Some(format!(
            "its push trigger must be filtered to catalog/tools.json alone, not {}: catalog-publish's own merges write only the website's copy, and any wider filter could start runs for nothing",
            p.py_repr()
        ));
    }
    None
}

fn strip_yaml_comment(line: &str) -> &str {
    let mut in_single = false;
    let mut in_double = false;
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if in_double => {
                i += 2;
                continue;
            }
            b'\'' if !in_double => in_single = !in_single,
            b'"' if !in_single => in_double = !in_double,
            b'#' if !in_single && !in_double => {
                if i == 0 || bytes[i - 1].is_ascii_whitespace() {
                    return line[..i].trim_end();
                }
            }
            _ => {}
        }
        i += 1;
    }
    line.trim_end()
}

fn parse_scalar(raw: &str) -> Value {
    let s = raw.trim();
    if s.is_empty() || s == "null" || s == "~" {
        return Value::Null;
    }
    if s == "true" {
        return Value::Bool(true);
    }
    if s == "false" {
        return Value::Bool(false);
    }
    if (s.starts_with('"') && s.ends_with('"') && s.len() >= 2)
        || (s.starts_with('\'') && s.ends_with('\'') && s.len() >= 2)
    {
        return Value::Str(s[1..s.len() - 1].to_string());
    }
    if s.starts_with('[') && s.ends_with(']') {
        let inner = s[1..s.len() - 1].trim();
        if inner.is_empty() {
            return Value::List(Vec::new());
        }
        let items = inner.split(',').map(|item| parse_scalar(item)).collect();
        return Value::List(items);
    }
    if let Ok(n) = s.parse::<i128>() {
        return Value::Int(n);
    }
    Value::Str(s.to_string())
}

fn split_key_val(text: &str) -> Option<(&str, &str)> {
    let bytes = text.as_bytes();
    let mut in_single = false;
    let mut in_double = false;
    for i in 0..bytes.len() {
        match bytes[i] {
            b'\'' if !in_double => in_single = !in_single,
            b'"' if !in_single => in_double = !in_double,
            b':' if !in_single && !in_double => {
                if i + 1 == bytes.len() || bytes[i + 1].is_ascii_whitespace() {
                    let key = text[..i].trim().trim_matches('"').trim_matches('\'');
                    let rest = text[i + 1..].trim();
                    return Some((key, rest));
                }
            }
            _ => {}
        }
    }
    None
}

fn parse_yaml_block(lines: &[(usize, String)], pos: &mut usize, min_indent: usize) -> Value {
    if *pos >= lines.len() || lines[*pos].0 < min_indent {
        return Value::Dict(Dict::new());
    }
    let block_indent = lines[*pos].0;
    if lines[*pos].1.starts_with("- ") || lines[*pos].1 == "-" {
        let mut list = Vec::new();
        while *pos < lines.len() && lines[*pos].0 == block_indent {
            let line = &lines[*pos].1;
            if !line.starts_with("- ") && line != "-" {
                break;
            }
            let after_dash = if line.len() > 2 { line[2..].trim() } else { "" };
            *pos += 1;
            if after_dash.is_empty() {
                list.push(parse_yaml_block(lines, pos, block_indent + 1));
            } else if let Some((k, v)) = split_key_val(after_dash) {
                let mut d = Dict::new();
                if v.is_empty() {
                    d.insert(k, parse_yaml_block(lines, pos, block_indent + 1));
                } else {
                    d.insert(k, parse_scalar(v));
                }
                while *pos < lines.len() && lines[*pos].0 > block_indent {
                    let sub_indent = lines[*pos].0;
                    let sub_line = lines[*pos].1.clone();
                    if let Some((sk, sv)) = split_key_val(&sub_line) {
                        *pos += 1;
                        if sv.is_empty() {
                            d.insert(sk, parse_yaml_block(lines, pos, sub_indent + 1));
                        } else {
                            d.insert(sk, parse_scalar(sv));
                        }
                    } else {
                        *pos += 1;
                    }
                }
                list.push(Value::Dict(d));
            } else {
                list.push(parse_scalar(after_dash));
            }
        }
        Value::List(list)
    } else {
        let mut dict = Dict::new();
        while *pos < lines.len() && lines[*pos].0 == block_indent {
            let line = lines[*pos].1.clone();
            if line.starts_with("- ") || line == "-" {
                break;
            }
            if let Some((k, v)) = split_key_val(&line) {
                *pos += 1;
                if v == "|" || v == ">" || v == "|-" || v == ">-" {
                    let mut block_text = String::new();
                    while *pos < lines.len() && lines[*pos].0 > block_indent {
                        if !block_text.is_empty() {
                            block_text.push('\n');
                        }
                        block_text.push_str(&lines[*pos].1);
                        *pos += 1;
                    }
                    dict.insert(k, Value::Str(block_text));
                } else if v.is_empty() {
                    dict.insert(k, parse_yaml_block(lines, pos, block_indent + 1));
                } else {
                    dict.insert(k, parse_scalar(v));
                }
            } else {
                *pos += 1;
            }
        }
        Value::Dict(dict)
    }
}

fn load_workflow(path: &Path) -> Value {
    let text = std::fs::read_to_string(path).unwrap();
    let mut lines: Vec<(usize, String)> = Vec::new();
    let mut block_scalar_indent: Option<usize> = None;
    for raw_line in text.lines() {
        let indent = raw_line.len() - raw_line.trim_start().len();
        if let Some(bs_indent) = block_scalar_indent {
            if raw_line.trim().is_empty() {
                continue;
            }
            if indent > bs_indent {
                lines.push((indent, raw_line.trim().to_string()));
                continue;
            } else {
                block_scalar_indent = None;
            }
        }
        let stripped = strip_yaml_comment(raw_line);
        let trimmed = stripped.trim();
        if trimmed.is_empty() || trimmed == "---" {
            continue;
        }
        if let Some((_, v)) = split_key_val(trimmed) {
            if v == "|" || v == ">" || v == "|-" || v == ">-" {
                block_scalar_indent = Some(indent);
            }
        }
        lines.push((indent, trimmed.to_string()));
    }
    let mut pos = 0;
    parse_yaml_block(&lines, &mut pos, 0)
}

struct Fixture {
    rows: Vec<Value>,
    bump: Value,
    by_name: BTreeMap<String, Vec<PathBuf>>,
}

impl Fixture {
    fn load() -> Self {
        let here_dir = here::catalog_dir();
        let root = here_dir.parent().unwrap();
        let workflows_dir = root.join(".github/workflows");
        let sources_text = std::fs::read_to_string(here_dir.join("sources.json")).unwrap();
        let sources_val = json::loads(&sources_text).unwrap();
        let rows = match sources_val.field("sources") {
            Some(Value::List(l)) => l.clone(),
            _ => panic!("expected sources list"),
        };
        let bump = load_workflow(&workflows_dir.join("catalog-bump.yaml"));
        let mut workflow_paths: Vec<PathBuf> = std::fs::read_dir(&workflows_dir)
            .unwrap()
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| {
                p.extension()
                    .and_then(|e| e.to_str())
                    .map_or(false, |ext| ext == "yaml" || ext == "yml")
            })
            .collect();
        workflow_paths.sort();
        let mut by_name: BTreeMap<String, Vec<PathBuf>> = BTreeMap::new();
        for path in workflow_paths {
            let wf = load_workflow(&path);
            if let Some(Value::Str(name)) = wf.field("name") {
                if !name.is_empty() {
                    by_name.entry(name.clone()).or_default().push(path);
                }
            }
        }
        Fixture {
            rows,
            bump,
            by_name,
        }
    }

    fn trigger(&self) -> Value {
        self.bump
            .field("on")
            .and_then(|on| on.field("workflow_run"))
            .cloned()
            .unwrap_or_else(|| Value::Dict(Dict::new()))
    }
}

#[test]
fn test_every_tool_released_here_names_its_release_workflow() {
    let f = Fixture::load();
    for row in &f.rows {
        if row.field("repo") == Some(&py::s(THIS_REPO)) {
            let has_wf = row.field("releaseWorkflow").map_or(false, |v| v.truthy());
            let id = row.field("id").map(|v| v.py_str()).unwrap_or_default();
            assert!(
                has_wf,
                "{} is released from this repository but its row in catalog/sources.json has no releaseWorkflow, so its release would wait for the hourly run: name the workflow that uploads its zip, and add it to catalog-bump's workflow_run list",
                id
            );
        }
    }
}

#[test]
fn test_a_tool_released_elsewhere_names_none() {
    let f = Fixture::load();
    for row in &f.rows {
        if row.field("repo") != Some(&py::s(THIS_REPO)) {
            let id = row.field("id").map(|v| v.py_str()).unwrap_or_default();
            let repo = row.field("repo").map(|v| v.py_str()).unwrap_or_default();
            assert!(
                row.field("releaseWorkflow").is_none(),
                "{} is released from {}: no workflow there can start catalog-bump here; the hourly run covers it",
                id,
                repo
            );
        }
    }
}

#[test]
fn test_catalog_bump_starts_when_each_of_them_finishes() {
    let f = Fixture::load();
    let named: BTreeSet<String> = f
        .rows
        .iter()
        .filter_map(|r| match r.field("releaseWorkflow") {
            Some(Value::Str(s)) if !s.is_empty() => Some(s.clone()),
            _ => None,
        })
        .collect();
    let trigger = f.trigger();
    let workflows: BTreeSet<String> = match trigger.field("workflows") {
        Some(Value::List(l)) => l.iter().map(|v| v.py_str()).collect(),
        _ => BTreeSet::new(),
    };
    assert_eq!(
        workflows, named,
        "catalog-bump's workflow_run list must be exactly the releaseWorkflow column of catalog/sources.json"
    );
    assert_eq!(
        trigger.field("types"),
        Some(&Value::List(vec![py::s("completed")]))
    );
    assert_eq!(
        trigger.field("branches"),
        Some(&Value::List(vec![py::s("main")]))
    );
}

#[test]
fn test_each_named_workflow_is_one_workflow_here() {
    let f = Fixture::load();
    for row in &f.rows {
        if let Some(Value::Str(name)) = row.field("releaseWorkflow") {
            if !name.is_empty() {
                let id = row.field("id").map(|v| v.py_str()).unwrap_or_default();
                let found = f.by_name.get(name).cloned().unwrap_or_default();
                assert_eq!(
                    found.len(),
                    1,
                    "{}: exactly one workflow in .github/workflows must be named {:?}; found {:?}",
                    id,
                    name,
                    found
                );
            }
        }
    }
}

#[test]
fn test_each_named_workflow_uploads_and_checks_the_zip() {
    let f = Fixture::load();
    for row in &f.rows {
        let Some(Value::Str(name)) = row.field("releaseWorkflow") else {
            continue;
        };
        let Some(paths) = f.by_name.get(name) else {
            continue;
        };
        if paths.len() != 1 {
            continue;
        }
        let text = std::fs::read_to_string(&paths[0]).unwrap();
        let asset = row.field("asset").map(|v| v.py_str()).unwrap_or_default();
        let zip_name = asset.replace("{version}", "${version}");
        let id = row.field("id").map(|v| v.py_str()).unwrap_or_default();
        assert!(
            text.contains(&zip_name),
            "{} does not name {}: is it the workflow that uploads {}'s zip?",
            name,
            zip_name,
            id
        );
    }
}

#[test]
fn test_the_hourly_backup_stays() {
    let f = Fixture::load();
    let schedule = f
        .bump
        .field("on")
        .and_then(|on| on.field("schedule"))
        .cloned()
        .unwrap_or(Value::List(vec![]));
    let crons: Vec<String> = match schedule {
        Value::List(l) => l
            .iter()
            .filter_map(|s| s.field("cron").map(|c| c.py_str()))
            .collect(),
        _ => vec![],
    };
    assert_eq!(
        crons,
        vec!["17 * * * *".to_string()],
        "catalog-bump lost its hourly schedule"
    );
}

#[test]
fn test_every_run_shares_one_lane() {
    let f = Fixture::load();
    let concurrency = f
        .bump
        .field("concurrency")
        .cloned()
        .unwrap_or_else(|| Value::Dict(Dict::new()));
    assert_eq!(
        concurrency.field("group"),
        Some(&py::s("catalog-bump")),
        "every catalog-bump run, whatever started it, must share one fixed concurrency group"
    );
    assert_eq!(
        concurrency.field("cancel-in-progress"),
        Some(&Value::Bool(false))
    );
}

#[test]
fn test_a_catalog_change_on_main_starts_it() {
    let f = Fixture::load();
    assert_eq!(push_trigger_problem(&f.bump), None);
}

#[test]
fn test_the_push_check_bites() {
    let f = Fixture::load();
    let mut gone = f.bump.clone();
    if let Some(Value::Dict(on)) = gone.field_mut("on") {
        on.0.retain(|(k, _)| k != "push");
    }
    assert!(push_trigger_problem(&gone).is_some());

    let mut unfiltered = f.bump.clone();
    if let Some(Value::Dict(on)) = unfiltered.field_mut("on") {
        if let Some(Value::Dict(push)) = on.get_mut("push") {
            push.0.retain(|(k, _)| k != "paths");
        }
    }
    assert!(push_trigger_problem(&unfiltered).is_some());

    let mut wider = f.bump.clone();
    if let Some(Value::Dict(on)) = wider.field_mut("on") {
        on.insert(
            "push",
            py::obj(vec![
                ("branches", Value::List(vec![py::s("main")])),
                ("paths", Value::List(vec![py::s("catalog/**")])),
            ]),
        );
    }
    assert!(push_trigger_problem(&wider).is_some());

    let mut branchless = f.bump.clone();
    if let Some(Value::Dict(on)) = branchless.field_mut("on") {
        on.insert(
            "push",
            py::obj(vec![(
                "paths",
                Value::List(vec![py::s("catalog/tools.json")]),
            )]),
        );
    }
    assert!(push_trigger_problem(&branchless).is_some());
}

#[test]
fn test_the_trigger_list_is_exact() {
    let f = Fixture::load();
    let keys: BTreeSet<String> = match f.bump.field("on") {
        Some(Value::Dict(on)) => on.keys().cloned().collect(),
        _ => BTreeSet::new(),
    };
    let expected: BTreeSet<String> = ["workflow_run", "push", "schedule", "workflow_dispatch"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    assert_eq!(keys, expected);
}

#[test]
fn test_no_run_is_empty() {
    let f = Fixture::load();
    let plan = f
        .bump
        .field("jobs")
        .and_then(|j| j.field("plan"))
        .expect("jobs.plan exists");
    assert!(plan.field("if").is_none());
}
