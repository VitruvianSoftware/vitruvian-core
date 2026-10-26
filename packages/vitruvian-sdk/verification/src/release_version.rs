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

//! Native Rust port of `packages/vitruvian-sdk/release_version_test.py`.
//! Verifies that `.release-please-manifest.json`, `release-please-config.json`,
//! `Sources/VitruvianToolCLI/Words.swift`, `BUILD` visibility rules, and all
//! kit/sample `extra-files` entries agree on a single version and consumer boundary.

use std::fs;
use std::path::Path;

use conformance_rs_lib::json::{self, Value};

use crate::find_package_dir;

pub const PATH: &str = "packages/vitruvian-sdk";
pub const WORDS: &str = "Sources/VitruvianToolCLI/Words.swift";
pub const CONSUMERS: &str = "packages/vitruvian-sdk/consumers";

pub const TOOLS_ONLY: &[&str] = &[
    "name = \"VitruvianToolKit\"",
    "name = \"vitruvian-tool\"",
    "[\"conformance/conformance.py\"]",
];

pub const KIT_PLACES: &[(&str, &str, Option<&str>)] = &[
    ("json", "kits/typescript/package.json", Some("$.version")),
    (
        "toml",
        "kits/python/pyproject.toml",
        Some("$.project.version"),
    ),
    (
        "json",
        "samples/hello-typescript/package.json",
        Some("$.dependencies['@vitruviansoftware/tool-kit']"),
    ),
    ("generic", "samples/hello-python-kit/requirements.txt", None),
    (
        "json",
        "samples/hello-panel-typescript/package.json",
        Some("$.dependencies['@vitruviansoftware/tool-kit']"),
    ),
    (
        "generic",
        "samples/hello-panel-python/requirements.txt",
        None,
    ),
    ("generic", "go/toolkit/version.go", None),
    ("toml", "kits/rust/Cargo.toml", Some("$.package.version")),
    ("generic", "samples/hello-go/go.mod", None),
    ("generic", "samples/hello-panel-go/go.mod", None),
    (
        "toml",
        "samples/hello-rust/Cargo.toml",
        Some("$.dependencies['vitruvian-tool-kit'].version"),
    ),
    (
        "toml",
        "samples/hello-panel-rust/Cargo.toml",
        Some("$.dependencies['vitruvian-tool-kit'].version"),
    ),
];

fn is_rule_open_line(line: &str) -> bool {
    let Some(prefix) = line.strip_suffix('(') else {
        return false;
    };
    !prefix.is_empty()
        && prefix
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

/// Finds the first top-level rule block `^\w+\(\n...\n^\)` in `build` containing `target`.
pub fn find_rule_block(build: &str, target: &str) -> String {
    let lines: Vec<&str> = build.split('\n').collect();
    let mut i = 0;
    while i < lines.len() {
        if is_rule_open_line(lines[i]) {
            let start = i;
            let mut end = None;
            let mut j = i + 1;
            while j < lines.len() {
                if lines[j] == ")" {
                    end = Some(j);
                    break;
                }
                j += 1;
            }
            if let Some(end_idx) = end {
                let block = lines[start..=end_idx].join("\n");
                if block.contains(target) {
                    return block;
                }
                i = end_idx + 1;
                continue;
            }
        }
        i += 1;
    }
    String::new()
}

pub fn consumer_problems(package: &Value, build: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let exclude_paths = package
        .get("exclude-paths")
        .and_then(|v| v.as_arr())
        .unwrap_or(&[]);
    let has_consumers = exclude_paths.iter().any(|v| v.as_str() == Some(CONSUMERS));
    if !has_consumers {
        problems.push(format!(
            "{CONSUMERS} is not in exclude-paths: letting a new tool use the SDK would cut an SDK release with nothing in it"
        ));
    }

    let named: Vec<&str> = build
        .split('\n')
        .filter(|line| line.contains("\"//apps/") && !line.trim_start().starts_with('#'))
        .map(|line| line.trim())
        .collect();
    if !named.is_empty() {
        problems.push(format!(
            "BUILD names another product's folder ({}): say who may use a target in consumers/BUILD, which a release does not count, and name the group here",
            named.join(", ")
        ));
    }

    let want_vis = format!("\"//{CONSUMERS}:tools\"");
    let forbid_vis = format!("//{CONSUMERS}:app");
    for &target in TOOLS_ONLY {
        let text = find_rule_block(build, target);
        if !text.contains(&want_vis) || text.contains(&forbid_vis) {
            problems.push(format!(
                "{target} must be visible to //{CONSUMERS}:tools and not to //{CONSUMERS}:app: the app may not use what tools are written with"
            ));
        }
    }
    problems
}

fn extract_semver(line: &str) -> Option<String> {
    const PREFIX: &str = "static let version = \"";
    let idx = line.find(PREFIX)?;
    let after = &line[idx + PREFIX.len()..];
    let end_q = after.find('"')?;
    let ver = &after[..end_q];
    let parts: Vec<&str> = ver.split('.').collect();
    if parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
    {
        Some(ver.to_string())
    } else {
        None
    }
}

pub fn run_in(package_dir: &Path) -> (i32, Vec<String>, String) {
    let config_path = package_dir.join("release-please-config.json");
    let manifest_path = package_dir.join(".release-please-manifest.json");

    let config_text = match fs::read_to_string(&config_path) {
        Ok(t) => t,
        Err(_) => {
            return (
                1,
                vec![format!(
                    "version: FAILED, {} is missing",
                    config_path.display()
                )],
                String::new(),
            );
        }
    };
    let manifest_text = match fs::read_to_string(&manifest_path) {
        Ok(t) => t,
        Err(_) => {
            return (
                1,
                vec![format!(
                    "version: FAILED, {} is missing",
                    manifest_path.display()
                )],
                String::new(),
            );
        }
    };

    let config = json::loads(&config_text).expect("valid release-please-config.json");
    let manifest = json::loads(&manifest_text).expect("valid .release-please-manifest.json");

    let Some(package) = config.get("packages").and_then(|p| p.get(PATH)) else {
        return (
            1,
            vec![format!("version: FAILED, the config has no package {PATH}")],
            String::new(),
        );
    };

    let mut problems = Vec::new();
    for (key, wanted) in [
        ("release-type", Value::Str("simple".into())),
        ("include-component-in-tag", Value::Bool(true)),
    ] {
        let got = config.get(key).cloned().unwrap_or(Value::Null);
        if !json::py_eq(&got, &wanted) {
            problems.push(format!(
                "{key} is {}, not {}",
                got.py_repr(),
                wanted.py_repr()
            ));
        }
    }

    if package.get("component").and_then(|c| c.as_str()) != Some("vitruvian-sdk") {
        problems.push(
            "the component is not vitruvian-sdk: the tag would not be vitruvian-sdk-vX.Y.Z"
                .to_string(),
        );
    }

    let extra_files = package
        .get("extra-files")
        .and_then(|v| v.as_arr())
        .unwrap_or(&[]);
    let has_words = extra_files.iter().any(|e| e.as_str() == Some(WORDS));
    if !has_words {
        problems.push(format!(
            "{WORDS} is not in extra-files: --version would not follow a release"
        ));
    }

    for &(kind, path, jsonpath) in KIT_PLACES {
        let entry = extra_files
            .iter()
            .find(|e| e.is_dict() && e.get("path").and_then(|p| p.as_str()) == Some(path));
        let want = match jsonpath {
            Some(jp) => format!("{kind} at {jp}"),
            None => kind.to_string(),
        };
        let valid_entry = entry.is_some_and(|e| {
            e.get("type").and_then(|t| t.as_str()) == Some(kind)
                && jsonpath
                    .map(|jp| e.get("jsonpath").and_then(|j| j.as_str()) == Some(jp))
                    .unwrap_or(true)
        });
        if !valid_entry {
            problems.push(format!(
                "{path} is not in extra-files as {want}: a release would bump Words.swift and not it, and samples_test would fail the release"
            ));
        } else if !package_dir.join(path).exists() {
            problems.push(format!("extra-files names {path}, which is not there"));
        }
    }

    let exclude_paths = package
        .get("exclude-paths")
        .and_then(|v| v.as_arr())
        .unwrap_or(&[]);
    let gh_path = format!("{PATH}/.github");
    if !exclude_paths.iter().any(|e| e.as_str() == Some(&gh_path)) {
        problems.push(format!(
            "{gh_path} is not in exclude-paths: a change to the mirror's CI would cut a release"
        ));
    }

    let build_text = fs::read_to_string(package_dir.join("BUILD")).unwrap_or_default();
    problems.extend(consumer_problems(package, &build_text));

    let words_text = fs::read_to_string(package_dir.join(WORDS)).unwrap_or_default();
    let marked: Vec<&str> = words_text
        .split('\n')
        .filter(|line| line.contains("x-release-please-version"))
        .collect();
    let found: Vec<Option<String>> = marked.iter().map(|line| extract_semver(line)).collect();

    let words_ver = if marked.len() != 1 || found[0].is_none() {
        let marked_repr = Value::Arr(
            marked
                .iter()
                .map(|s| Value::Str((*s).to_string()))
                .collect(),
        )
        .py_repr();
        problems.push(format!(
            "{WORDS} must hold one `static let version = \"X.Y.Z\" // x-release-please-version` line, not {marked_repr}"
        ));
        None
    } else {
        found[0].clone()
    };

    let released = manifest.get(PATH).and_then(|v| v.as_str()).unwrap_or("");
    let expected = if released == "0.0.0" {
        package
            .get("initial-version")
            .and_then(|v| v.as_str())
            .unwrap_or("")
    } else {
        released
    };

    if let Some(ref w) = words_ver {
        if w != expected {
            let suffix = if released == "0.0.0" {
                format!(" with initial-version {expected}")
            } else {
                String::new()
            };
            problems.push(format!(
                "Words.swift says {w}, and the manifest says {released}{suffix}"
            ));
        }
    }

    let status_line = if problems.is_empty() {
        format!("version: OK, {}\n", words_ver.as_deref().unwrap_or("None"))
    } else {
        "version: FAILED\n".to_string()
    };
    let code = if problems.is_empty() { 0 } else { 1 };
    (code, problems, status_line)
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
    if !stdout_text.is_empty() {
        print!("{stdout_text}");
    }
    code
}
