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

//! Native Rust port of `packages/vitruvian-sdk/samples/go_template_test.py`.
//! Runs `go vet ./...` on the Go kit in an isolated module and optionally
//! tests `vitruvian-tool init --template go --sdk` end-to-end.

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use conformance_rs_lib::{check_to, TempDir};

use crate::resolve_runfile;

fn run_cmd(
    words: &[String],
    cwd: Option<&Path>,
    environment: &HashMap<String, String>,
) -> (i32, String) {
    let (prog, args) = words.split_first().expect("non-empty command");
    let mut cmd = Command::new(prog);
    cmd.args(args).env_clear().envs(environment);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
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
}

pub fn built_tool(
    tool: &Path,
    sdk: &Path,
    root: &Path,
    environment: &HashMap<String, String>,
) -> Vec<String> {
    let folder = root.join("fresh");
    let tool_str = tool.to_string_lossy().into_owned();
    let folder_str = folder.to_string_lossy().into_owned();
    let sdk_str = sdk.to_string_lossy().into_owned();

    let (status, printed) = run_cmd(
        &[
            tool_str.clone(),
            "init".into(),
            folder_str,
            "--id".into(),
            "com.example.fresh".into(),
            "--name".into(),
            "Fresh".into(),
            "--publisher".into(),
            "Example".into(),
            "--template".into(),
            "go".into(),
            "--sdk".into(),
            sdk_str,
        ],
        None,
        environment,
    );
    if status != 0 || !printed.contains("wrote    go.mod") {
        return vec![format!("init did not write the Go template:\n{printed}")];
    }

    let build_sh = folder.join("build.sh").to_string_lossy().into_owned();
    let (status, printed) = run_cmd(&[build_sh], None, environment);
    if status != 0 {
        return vec![format!("build.sh did not build:\n{printed}")];
    }

    let built = folder.join("tool");
    let built_str = built.to_string_lossy().into_owned();
    let (status, printed) = run_cmd(
        &[tool_str.clone(), "validate".into(), built_str.clone()],
        None,
        environment,
    );
    if status != 0 {
        return vec![format!("validate does not pass what was built:\n{printed}")];
    }

    let mut said = Vec::new();
    let status = check_to(&built, None, true, &mut said).unwrap_or(1);
    if status != 0 {
        let said_str = String::from_utf8_lossy(&said);
        return vec![format!(
            "what was built does not pass conformance:\n{said_str}"
        )];
    }

    let (status, printed) = run_cmd(
        &[
            tool_str,
            "run".into(),
            built_str,
            "--command".into(),
            "hello".into(),
            "--command".into(),
            "count".into(),
        ],
        None,
        environment,
    );
    if status != 0 || !printed.contains("run: OK") {
        return vec![format!("what was built does not run:\n{printed}")];
    }
    Vec::new()
}

pub fn main_with_args(raw_args: &[String]) -> i32 {
    let mut args = raw_args.to_vec();
    let mut tool: Option<PathBuf> = None;
    if let Some(at) = args.iter().position(|a| a == "--tool") {
        if at + 1 < args.len() {
            tool = Some(resolve_runfile(&args[at + 1]));
            args.drain(at..=at + 1);
        }
    }
    if args.len() < 2 {
        eprintln!("usage: go_template_test <go> <go.mod> <sources...> [--tool <vitruvian-tool>]");
        return 1;
    }

    let go = resolve_runfile(&args[0]);
    let module = resolve_runfile(&args[1]);
    let sources = &args[2..];

    let mut problems = Vec::new();
    let temp = TempDir::new("vitruvian-go-").expect("temp dir");
    let root = temp.path();

    let go_dir = go.parent().unwrap_or_else(|| Path::new("."));
    let goroot = go_dir.parent().unwrap_or_else(|| Path::new("."));
    let cur_path = env::var("PATH").unwrap_or_default();

    let mut environment: HashMap<String, String> = HashMap::new();
    environment.insert("PATH".into(), format!("{}:{cur_path}", go_dir.display()));
    environment.insert("GOROOT".into(), goroot.to_string_lossy().into_owned());
    environment.insert("HOME".into(), root.to_string_lossy().into_owned());
    environment.insert(
        "GOCACHE".into(),
        root.join("cache").to_string_lossy().into_owned(),
    );
    environment.insert(
        "GOPATH".into(),
        root.join("path").to_string_lossy().into_owned(),
    );
    environment.insert("GOWORK".into(), "off".into());
    environment.insert("GOPROXY".into(), "off".into());
    environment.insert("GOTOOLCHAIN".into(), "local".into());
    environment.insert("GOFLAGS".into(), "-mod=mod".into());
    environment.insert("CGO_ENABLED".into(), "0".into());

    for name in ["RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "TMPDIR"] {
        if let Ok(val) = env::var(name) {
            environment.insert(name.into(), val);
        }
    }

    let sdk = root.join("sdk");
    let kit = sdk.join("go");
    fs::create_dir_all(kit.join("toolkit")).unwrap();
    fs::copy(&module, kit.join("go.mod")).unwrap();

    for source in sources {
        let src_path = resolve_runfile(source);
        let inside = source
            .split_once("/go/toolkit/")
            .or_else(|| source.split_once("go/toolkit/"))
            .map(|(_, rel)| rel)
            .unwrap_or(source.as_str());
        let dst = kit.join("toolkit").join(inside);
        if let Some(parent) = dst.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::copy(&src_path, &dst).unwrap();
    }

    let (status, printed) = run_cmd(
        &[
            go.to_string_lossy().into_owned(),
            "vet".into(),
            "./...".into(),
        ],
        Some(&kit),
        &environment,
    );
    if status != 0 {
        problems.push(format!(
            "go vet fails the kit as its own module:\n{printed}"
        ));
    }

    if let Some(ref tool_path) = tool {
        if problems.is_empty() {
            problems.extend(built_tool(tool_path, &sdk, root, &environment));
        }
    }

    for problem in &problems {
        eprintln!("{problem}");
    }
    println!("go: {}", if problems.is_empty() { "OK" } else { "FAILED" });
    if problems.is_empty() {
        0
    } else {
        1
    }
}
