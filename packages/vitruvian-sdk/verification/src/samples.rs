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

//! Native Rust port of `packages/vitruvian-sdk/samples/samples_test.py`.
//! Validates all sample manifests, checks SDK version parity across all 13 kit
//! and sample files, and runs sample tools in-process against `conformance_rs_lib`.

use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use conformance_rs_lib::json::{self, Value};
use conformance_rs_lib::{check_to, pystr, Link, Run, TempDir, Transport};

use crate::schema;
use crate::{find_package_dir, find_python3, hermetic_node, resolve_runfile};

pub const OLDER: &str = "an older app: answered the hello, ";

pub fn wanted_groups(name: &str) -> Option<Vec<Vec<String>>> {
    let panel_older = format!(
        "{OLDER}ran addOne, drew counter, drew settings and left with 0; it sent no ui/status"
    );
    let panel_groups = || {
        vec![
            vec!["a command: addOne: ran, and set the status: ok".to_string()],
            vec![
                "a panel: counter: a page of 6 blocks, and a new page after a tap on add; settings: a page of 2 blocks".to_string(),
            ],
            vec![panel_older.clone()],
        ]
    };
    let hello_groups = || {
        vec![
            vec!["a command: hello: ran".to_string()],
            vec!["refusals: 1 refused".to_string()],
        ]
    };

    match name {
        "hello-python" | "hello-swift" | "hello-typescript" | "hello-python-kit" | "hello-go"
        | "hello-rust" => Some(hello_groups()),
        "hello-panel-swift"
        | "hello-panel-typescript"
        | "hello-panel-python"
        | "hello-panel-go"
        | "hello-panel-rust" => Some(panel_groups()),
        "front-window" => Some(vec![vec![
            "a command: showTitle: ran".to_string(),
            "a command: showTitle: refused, Accessibility is not granted".to_string(),
            "a command: showTitle: refused, no app is in front".to_string(),
            "a command: showTitle: refused, the app in front has no window".to_string(),
        ]]),
        _ => None,
    }
}

pub const ALL_SAMPLE_NAMES: &[&str] = &[
    "front-window",
    "hello-go",
    "hello-panel-go",
    "hello-panel-python",
    "hello-panel-rust",
    "hello-panel-swift",
    "hello-panel-typescript",
    "hello-python",
    "hello-python-kit",
    "hello-rust",
    "hello-swift",
    "hello-typescript",
];

pub fn check(folder: &Path, via: Option<&str>, expect_refusal: bool) -> (i32, String) {
    let mut buf = Vec::new();
    let status = check_to(folder, via, expect_refusal, &mut buf).unwrap_or(1);
    let printed = String::from_utf8_lossy(&buf).into_owned();
    (status, printed)
}

pub fn conforms(folder: &Path, via: Option<&str>, expect_refusal: bool) -> Vec<String> {
    let manifest_path = folder.join("vitruvian-tool.json");
    let manifest_text = fs::read_to_string(&manifest_path).expect("vitruvian-tool.json");
    let manifest = json::loads(&manifest_text).expect("valid manifest JSON");
    let id = manifest.get("id").and_then(|v| v.as_str()).unwrap_or("");
    let name = id.rsplit('.').next().unwrap_or(id);

    let (status, printed) = check(folder, via, expect_refusal);
    let mut problems = Vec::new();
    if status != 0 {
        problems.push(format!("{name} does not pass:\n{printed}"));
    }
    if let Some(groups) = wanted_groups(name) {
        for group in groups {
            let seen: Vec<&String> = group
                .iter()
                .filter(|line| printed.contains(line.as_str()))
                .collect();
            if seen.is_empty() {
                let group_repr =
                    Value::Arr(group.iter().map(|s| Value::Str(s.clone())).collect()).py_repr();
                problems.push(format!("{name}: none of {group_repr} in:\n{printed}"));
            } else {
                println!("{name}: {}", seen[0]);
            }
        }
    }
    problems
}

fn format_seen_pairs(pairs: &[(String, Option<String>)]) -> String {
    let inner: Vec<String> = pairs
        .iter()
        .map(|(t, sub)| {
            let t_repr = pystr::repr_str(t);
            let sub_repr = match sub {
                Some(s) => pystr::repr_str(s),
                None => "None".to_string(),
            };
            format!("({t_repr}, {sub_repr})")
        })
        .collect();
    format!("[{}]", inner.join(", "))
}

pub fn settings_pages(folder: &Path, via: Option<&str>) -> Vec<String> {
    let manifest_path = folder.join("vitruvian-tool.json");
    let manifest_text = fs::read_to_string(&manifest_path).expect("vitruvian-tool.json");
    let manifest = json::loads(&manifest_text).expect("valid manifest JSON");
    let id = manifest.get("id").and_then(|v| v.as_str()).unwrap_or("");
    let name = id.rsplit('.').next().unwrap_or(id);

    let has_settings = manifest
        .get("contributes")
        .and_then(|c| c.get("panels"))
        .and_then(|p| p.as_arr())
        .is_some_and(|arr| {
            arr.iter()
                .any(|p| p.get("id").and_then(|i| i.as_str()) == Some("settings"))
        });
    if !has_settings {
        return Vec::new();
    }

    let exec_rel = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .unwrap_or("");
    let program = folder.join(exec_rel).to_string_lossy().into_owned();
    let command: Vec<String> = match via {
        Some(v) => vec![v.to_string(), program],
        None => vec![program],
    };

    let wanted_this = vec![
        ("heading".to_string(), Some("section".to_string())),
        ("toggle".to_string(), Some("help".to_string())),
    ];
    let wanted_older = vec![("toggle".to_string(), None), ("text".to_string(), None)];

    let mut problems = Vec::new();
    for (app, features, wanted) in [
        ("this app", Run::<Link>::default_features(), &wanted_this),
        ("an older app", None, &wanted_older),
    ] {
        let temp = TempDir::new("vitruvian-samples-").expect("temp dir");
        let data_folder = temp.path().to_string_lossy().into_owned();
        let link = match Link::spawn(&command, temp.path()) {
            Ok(l) => l,
            Err(e) => {
                problems.push(format!("{name}: settings, opened by {app}: {e}"));
                continue;
            }
        };
        let mut run = Run::new(link, &manifest, data_folder, features);
        let page_res = run
            .handshake()
            .and_then(|_| run.opened_page("settings"))
            .and_then(|page| {
                let _ = run.shutdown();
                Ok(page)
            });
        run.link.close();

        let page = match page_res {
            Ok(p) => p,
            Err(failure) => {
                problems.push(format!("{name}: settings, opened by {app}: {failure}"));
                continue;
            }
        };

        let blocks = page.get("blocks").and_then(|b| b.as_arr()).unwrap_or(&[]);
        let seen: Vec<(String, Option<String>)> = blocks
            .iter()
            .map(|b| {
                let b_type = b
                    .get("type")
                    .and_then(|t| t.as_str())
                    .unwrap_or("")
                    .to_string();
                let tag = if b.get("section").and_then(|s| s.as_bool()) == Some(true) {
                    Some("section".to_string())
                } else if b.has("help") {
                    Some("help".to_string())
                } else {
                    None
                };
                (b_type, tag)
            })
            .collect();

        let seen_repr = format_seen_pairs(&seen);
        if &seen != wanted {
            problems.push(format!("{name}: settings, opened by {app}, is {seen_repr}"));
        } else {
            println!("{name}: settings, opened by {app}: {seen_repr}");
        }
    }
    problems
}

pub fn manifests(package_dir: &Path) -> Vec<String> {
    let schema_text =
        fs::read_to_string(package_dir.join("protocol/manifest.schema.json")).unwrap();
    let schema_val = json::loads(&schema_text).unwrap();
    let samples_dir = package_dir.join("samples");

    let mut found: Vec<PathBuf> = fs::read_dir(&samples_dir)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .map(|e| e.path().join("vitruvian-tool.json"))
        .filter(|p| p.is_file())
        .collect();
    found.sort();

    let mut names: Vec<String> = found
        .iter()
        .filter_map(|p| {
            p.parent()
                .and_then(|d| d.file_name())
                .and_then(|n| n.to_str())
                .map(String::from)
        })
        .collect();
    names.sort();

    let wanted_names: Vec<String> = ALL_SAMPLE_NAMES.iter().map(|s| (*s).to_string()).collect();
    let mut problems = if names == wanted_names {
        Vec::new()
    } else {
        let names_repr = Value::Arr(names.into_iter().map(Value::Str).collect()).py_repr();
        vec![format!("the samples are {names_repr}")]
    };

    for path in found {
        let text = fs::read_to_string(&path).unwrap_or_default();
        let manifest = json::loads(&text).unwrap();
        for err in schema::iter_errors(&schema_val, &manifest) {
            problems.push(format!("{}: {err}", path.display()));
        }
        let name = path
            .parent()
            .and_then(|d| d.file_name())
            .and_then(|n| n.to_str())
            .unwrap_or("");
        let expected_id = format!("dev.vitruvian.samples.{name}");
        if manifest.get("id").and_then(|v| v.as_str()) != Some(&expected_id) {
            problems.push(format!(
                "{}: the id does not end with the folder's name",
                path.display()
            ));
        }
    }
    problems
}

fn find_line_starting_with_prefix<'a>(
    text: &'a str,
    prefix: &str,
    suffix: &str,
) -> Option<&'a str> {
    for line in text.lines() {
        if let Some(after) = line.strip_prefix(prefix) {
            if suffix.is_empty() {
                let ver: &str = after.split_whitespace().next().unwrap_or("");
                if !ver.is_empty() {
                    return Some(ver);
                }
            } else if let Some(idx) = after.find(suffix) {
                return Some(&after[..idx]);
            }
        }
    }
    None
}

pub fn versions(package_dir: &Path) -> Vec<String> {
    let read =
        |rel: &str| -> String { fs::read_to_string(package_dir.join(rel)).unwrap_or_default() };
    let mut found: BTreeMap<String, String> = BTreeMap::new();

    if let Some(v) =
        find_line_starting_with_prefix(&read("go/toolkit/version.go"), "const Version = \"", "\"")
    {
        found.insert("go/toolkit/version.go".into(), v.into());
    }
    if let Some(v) =
        find_line_starting_with_prefix(&read("kits/rust/Cargo.toml"), "version = \"", "\"")
    {
        found.insert("kits/rust/Cargo.toml".into(), v.into());
    }
    if let Some(v) = find_line_starting_with_prefix(
        &read("samples/hello-go/go.mod"),
        "require github.com/VitruvianSoftware/vitruvian-sdk/go v",
        "",
    ) {
        found.insert("samples/hello-go/go.mod".into(), v.into());
    }
    if let Some(v) = find_line_starting_with_prefix(
        &read("samples/hello-panel-go/go.mod"),
        "require github.com/VitruvianSoftware/vitruvian-sdk/go v",
        "",
    ) {
        found.insert("samples/hello-panel-go/go.mod".into(), v.into());
    }
    if let Some(v) = find_line_starting_with_prefix(
        &read("samples/hello-rust/Cargo.toml"),
        "vitruvian-tool-kit = { version = \"",
        "\"",
    ) {
        found.insert("samples/hello-rust/Cargo.toml".into(), v.into());
    }
    if let Some(v) = find_line_starting_with_prefix(
        &read("samples/hello-panel-rust/Cargo.toml"),
        "vitruvian-tool-kit = { version = \"",
        "\"",
    ) {
        found.insert("samples/hello-panel-rust/Cargo.toml".into(), v.into());
    }
    if let Ok(pkg) = json::loads(&read("kits/typescript/package.json")) {
        if let Some(v) = pkg.get("version").and_then(|v| v.as_str()) {
            found.insert("kits/typescript/package.json".into(), v.into());
        }
    }
    if let Some(v) =
        find_line_starting_with_prefix(&read("kits/python/pyproject.toml"), "version = \"", "\"")
    {
        found.insert("kits/python/pyproject.toml".into(), v.into());
    }
    if let Ok(pkg) = json::loads(&read("samples/hello-typescript/package.json")) {
        if let Some(v) = pkg
            .get("dependencies")
            .and_then(|d| d.get("@vitruviansoftware/tool-kit"))
            .and_then(|v| v.as_str())
        {
            found.insert("samples/hello-typescript/package.json".into(), v.into());
        }
    }
    if let Ok(pkg) = json::loads(&read("samples/hello-panel-typescript/package.json")) {
        if let Some(v) = pkg
            .get("dependencies")
            .and_then(|d| d.get("@vitruviansoftware/tool-kit"))
            .and_then(|v| v.as_str())
        {
            found.insert(
                "samples/hello-panel-typescript/package.json".into(),
                v.into(),
            );
        }
    }
    for rel in [
        "samples/hello-panel-python/requirements.txt",
        "samples/hello-python-kit/requirements.txt",
    ] {
        let text = read(rel);
        if let Some(pos) = text.find("vitruvian-tool-kit==") {
            let after = &text[pos + 20..];
            let ver: String = after.chars().take_while(|c| !c.is_whitespace()).collect();
            if !ver.is_empty() {
                found.insert(rel.into(), ver);
            }
        }
    }

    let cli_dir = package_dir.join("Sources").join("VitruvianToolCLI");
    let mut swift_files: Vec<PathBuf> = fs::read_dir(&cli_dir)
        .ok()
        .into_iter()
        .flatten()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("swift"))
        .collect();
    swift_files.sort();
    for path in swift_files {
        let text = fs::read_to_string(&path).unwrap_or_default();
        const SUFFIX: &str = "\" // x-release-please-version";
        for line in text.lines() {
            if let Some(idx) = line.find(SUFFIX) {
                let before = &line[..idx];
                if let Some(q_idx) = before.rfind('"') {
                    let ver = &before[q_idx + 1..];
                    let rel = format!(
                        "Sources/VitruvianToolCLI/{}",
                        path.file_name().unwrap().to_string_lossy()
                    );
                    found.insert(rel, ver.to_string());
                }
            }
        }
    }

    let unique: BTreeSet<&String> = found.values().collect();
    if unique.len() == 1 && found.len() == 13 {
        let ver = &found["kits/typescript/package.json"];
        println!("versions: {ver}, in {} places", found.len());
        return Vec::new();
    }
    let found_obj = Value::Obj(found.into_iter().map(|(k, v)| (k, Value::Str(v))).collect());
    vec![format!(
        "one version of the SDK in thirteen places, and these differ or are missing: {}",
        found_obj.py_repr()
    )]
}

pub fn main_with_args(arguments: &[String]) -> i32 {
    let mut problems = Vec::new();
    if !arguments.is_empty() {
        if let Ok(node) = env::var("VITRUVIAN_NODE") {
            if !node.is_empty() {
                match hermetic_node(&node) {
                    None => {
                        problems.push(format!(
                            "the hermetic Node is not where VITRUVIAN_NODE says: {node}"
                        ));
                    }
                    Some(found) => {
                        if let Some(node_dir) = found.parent() {
                            let cur_path = env::var("PATH").unwrap_or_default();
                            env::set_var("PATH", format!("{}:{cur_path}", node_dir.display()));
                        }
                    }
                }
            }
        }
        let py_exe = find_python3();
        for manifest_arg in arguments {
            let manifest_path = resolve_runfile(manifest_arg);
            let folder = manifest_path
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| PathBuf::from("."));
            let manifest_text = fs::read_to_string(&manifest_path).unwrap_or_default();
            let manifest = json::loads(&manifest_text).unwrap();
            let program = manifest
                .get("runtime")
                .and_then(|r| r.get("exec"))
                .and_then(|e| e.as_str())
                .unwrap_or("");
            let via = if program.ends_with(".py") {
                Some(py_exe.as_str())
            } else {
                None
            };
            problems.extend(conforms(&folder, via, false));
            problems.extend(settings_pages(&folder, via));
        }
    } else {
        let package_dir = match find_package_dir() {
            Ok(d) => d,
            Err(e) => {
                eprintln!("{e}");
                return 1;
            }
        };
        problems.extend(manifests(&package_dir));
        problems.extend(versions(&package_dir));
        let py_exe = find_python3();
        let hello_py_folder = package_dir.join("samples").join("hello-python");
        problems.extend(conforms(&hello_py_folder, Some(&py_exe), true));
    }

    for problem in &problems {
        eprintln!("{problem}");
    }
    println!(
        "samples: {}",
        if problems.is_empty() { "OK" } else { "FAILED" }
    );
    if problems.is_empty() {
        0
    } else {
        1
    }
}
