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

//! Native Rust port of `packages/vitruvian-sdk/samples/init_test.py`.
//! Verifies that `vitruvian-tool init` scaffolds working tools for the Python,
//! Python kit, TypeScript, and Swift templates, and passes `validate`,
//! `conformance_rs_lib`, and `run`.

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

use conformance_rs_lib::json::Value;
use conformance_rs_lib::{check_to, TempDir};

use crate::{copy_dir_all, find_package_dir, find_python3, hermetic_node, resolve_runfile};

pub fn main_with_args(arguments: &[String]) -> i32 {
    let Some(arg0) = arguments.first() else {
        eprintln!("usage: init_test <vitruvian-tool>");
        return 1;
    };
    let command = resolve_runfile(arg0);
    let package_dir = match find_package_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };

    let mut problems = Vec::new();
    let py_exe = find_python3();
    let mut environment: HashMap<String, String> = env::vars().collect();

    if let Some(py_dir) = Path::new(&py_exe).parent() {
        let cur_path = environment.get("PATH").cloned().unwrap_or_default();
        environment.insert("PATH".into(), format!("{}:{cur_path}", py_dir.display()));
    }

    if let Ok(node_var) = env::var("VITRUVIAN_NODE") {
        if !node_var.is_empty() {
            let node_path = hermetic_node(&node_var).unwrap_or_else(|| resolve_runfile(&node_var));
            if let Some(node_dir) = node_path.parent() {
                let cur_env_path = environment.get("PATH").cloned().unwrap_or_default();
                let updated = format!("{}:{cur_env_path}", node_dir.display());
                environment.insert("PATH".into(), updated);
                let cur_proc_path = env::var("PATH").unwrap_or_default();
                env::set_var("PATH", format!("{}:{cur_proc_path}", node_dir.display()));
            }
        }
    }

    let run_tool = |words: &[&str]| -> (i32, String) {
        let mut cmd = Command::new(&command);
        cmd.args(words).env_clear().envs(&environment);
        match cmd.output() {
            Ok(done) => {
                let code = done.status.code().unwrap_or(1);
                let out = format!(
                    "{}{}",
                    String::from_utf8_lossy(&done.stdout),
                    String::from_utf8_lossy(&done.stderr)
                );
                (code, out)
            }
            Err(e) => (1, e.to_string()),
        }
    };

    let temp = TempDir::new("vitruvian-init-").expect("temp dir");
    let root = temp.path();
    let fresh = root.join("fresh");
    let fresh_str = fresh.to_string_lossy().into_owned();
    let named = [
        "--id",
        "com.example.fresh",
        "--name",
        "Fresh",
        "--publisher",
        "Example",
    ];

    let mut init_args = vec!["init", &fresh_str];
    init_args.extend_from_slice(&named);
    let (status, printed) = run_tool(&init_args);
    if status != 0 || !printed.contains("wrote    bin/tool.py") {
        problems.push(format!(
            "init did not write the Python template:\n{printed}"
        ));
    }

    let (status, printed) = run_tool(&["validate", &fresh_str]);
    if status != 0 || !printed.contains("ok       manifest: com.example.fresh 0.1.0") {
        problems.push(format!(
            "validate does not pass what init wrote:\n{printed}"
        ));
    }

    let mut said = Vec::new();
    let status = check_to(&fresh, Some(&py_exe), true, &mut said).unwrap_or(1);
    if status != 0 {
        let said_str = String::from_utf8_lossy(&said);
        problems.push(format!(
            "what init wrote does not pass conformance:\n{said_str}"
        ));
    }

    let (status, printed) = run_tool(&[
        "run",
        &fresh_str,
        "--command",
        "hello",
        "--command",
        "copyTime",
    ]);
    if status != 0 || !printed.contains("ran      copyTime") || !printed.contains("run: OK") {
        problems.push(format!("what init wrote does not run:\n{printed}"));
    }

    let (status, printed) = run_tool(&init_args);
    if status != 1 || !printed.contains("Nothing was written.") {
        problems.push(format!(
            "init wrote over a folder that was there:\n{printed}"
        ));
    }

    let swift = root.join("swift");
    let swift_str = swift.to_string_lossy().into_owned();
    let pkg_str = package_dir.to_string_lossy().into_owned();
    let mut swift_args = vec!["init", &swift_str];
    swift_args.extend_from_slice(&named);
    swift_args.extend_from_slice(&["--template", "swift", "--sdk", &pkg_str]);
    let (status, printed) = run_tool(&swift_args);
    let wanted_files = [
        "Package.swift",
        "Sources/Tool/main.swift",
        "tool/vitruvian-tool.json",
        "build.sh",
    ];
    let missing: Vec<String> = wanted_files
        .iter()
        .filter(|rel| !swift.join(rel).is_file())
        .map(|s| (*s).to_string())
        .collect();
    if status != 0 || !missing.is_empty() {
        let missing_repr = Value::Arr(missing.into_iter().map(Value::Str).collect()).py_repr();
        problems.push(format!(
            "init did not write the Swift template, missing {missing_repr}:\n{printed}"
        ));
    }

    let swift_tool_str = swift.join("tool").to_string_lossy().into_owned();
    let (status, printed) = run_tool(&["validate", &swift_tool_str]);
    if status != 1 || !printed.contains("the program `bin/tool` is not a file in the folder") {
        problems.push(format!(
            "an unbuilt Swift tool is not told its program is missing:\n{printed}"
        ));
    }

    let (status, raw_version) = run_tool(&["--version"]);
    let version = raw_version.trim();
    if status != 0 || version.matches('.').count() != 2 {
        problems.push(format!("--version did not print a version:\n{version}"));
    }

    let published = root.join("published");
    let published_str = published.to_string_lossy().into_owned();
    let mut pub_args = vec!["init", &published_str];
    pub_args.extend_from_slice(&named);
    pub_args.extend_from_slice(&["--template", "swift"]);
    let (status, printed) = run_tool(&pub_args);
    let wanted_dep = format!(
        ".package(url: \"https://github.com/VitruvianSoftware/vitruvian-sdk\", from: \"{version}\")"
    );
    let pkg_swift = published.join("Package.swift");
    let text = fs::read_to_string(&pkg_swift).unwrap_or_default();
    if status != 0 || !text.contains(&wanted_dep) {
        problems.push(format!(
            "init without --sdk does not depend on the published SDK {version}:\n{printed}\n{text}"
        ));
    }

    let ts_kit_env = env::var("VITRUVIAN_TOOL_KIT_TYPESCRIPT").ok();
    let kits: &[(&str, Vec<&str>, Option<String>, Option<&str>)] = &[
        (
            "python-kit",
            vec!["--sdk", &pkg_str],
            None,
            Some(py_exe.as_str()),
        ),
        ("typescript", Vec::new(), ts_kit_env, None),
    ];

    for (template, extra, kit_opt, via_opt) in kits {
        let folder = root.join(template);
        let folder_str = folder.to_string_lossy().into_owned();
        let mut t_args = vec!["init", &folder_str];
        t_args.extend_from_slice(&named);
        t_args.extend_from_slice(&["--template", template]);
        t_args.extend_from_slice(extra);
        let (status, printed) = run_tool(&t_args);
        if status != 0 {
            problems.push(format!(
                "init did not write the {template} template:\n{printed}"
            ));
            continue;
        }
        if let Some(kit_rel) = kit_opt {
            if !kit_rel.is_empty() {
                let kit_src = resolve_runfile(kit_rel);
                let dst = folder
                    .join("node_modules")
                    .join("@vitruviansoftware")
                    .join("tool-kit");
                copy_dir_all(&kit_src, &dst).unwrap();
            }
        }
        let (status, printed) = run_tool(&["validate", &folder_str]);
        if status != 0 {
            problems.push(format!(
                "validate does not pass the {template} template:\n{printed}"
            ));
        }
        let mut said = Vec::new();
        let status = check_to(&folder, *via_opt, true, &mut said).unwrap_or(1);
        if status != 0 {
            let said_str = String::from_utf8_lossy(&said);
            problems.push(format!(
                "the {template} template does not pass conformance:\n{said_str}"
            ));
        }
        let (status, printed) = run_tool(&[
            "run",
            &folder_str,
            "--command",
            "hello",
            "--command",
            "count",
        ]);
        if status != 0 || !printed.contains("ran      count") || !printed.contains("run: OK") {
            problems.push(format!("the {template} template does not run:\n{printed}"));
        }
    }

    for problem in &problems {
        eprintln!("{problem}");
    }
    println!(
        "init: {}",
        if problems.is_empty() { "OK" } else { "FAILED" }
    );
    if problems.is_empty() {
        0
    } else {
        1
    }
}
