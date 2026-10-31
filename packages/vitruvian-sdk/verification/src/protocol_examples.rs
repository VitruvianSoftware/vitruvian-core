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

//! Native Rust port of `packages/vitruvian-sdk/protocol/protocol_examples_test.py`.
//! Validates all manifest and message examples against the Draft 2020-12 JSON schemas,
//! verifies 100% schema field coverage, checks `methods.json` parity, and runs a
//! live session against `reference-tool-2`.

use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use conformance_rs_lib::json::{self, Value};
use conformance_rs_lib::TempDir;

use crate::schema;
use crate::{find_package_dir, find_python3, is_executable, resolve_runfile};

pub const LINE_SECONDS: u64 = 10;
pub const ENVELOPES: &[&str] = &["request", "notice", "result", "failure"];
pub const REFUSALS_WITH_DATA: &[&str] = &["-32001", "-32003"];

fn py_bool(b: bool) -> &'static str {
    if b {
        "True"
    } else {
        "False"
    }
}

fn load_json(dir: &Path, rel: &str) -> Result<Value, String> {
    let path = dir.join(rel);
    let text = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    json::loads(&text).map_err(|e| format!("{}: {e}", path.display()))
}

fn apply_change(base: &Value, change: &Value) -> Value {
    let mut entries = base.as_obj().map(|s| s.to_vec()).unwrap_or_default();
    if let Some(changes) = change.as_obj() {
        for (key, val) in changes {
            if matches!(val, Value::Null) {
                entries.retain(|(k, _)| k != key);
            } else if let Some(existing) = entries.iter_mut().find(|(k, _)| k == key) {
                existing.1 = val.clone();
            } else {
                entries.push((key.clone(), val.clone()));
            }
        }
    }
    Value::Obj(entries)
}

pub fn manifest_problems(protocol_dir: &Path) -> Vec<String> {
    let schema_val = load_json(protocol_dir, "manifest.schema.json").expect("manifest.schema.json");
    schema::check_schema(&schema_val).expect("valid manifest.schema.json");
    let file = load_json(protocol_dir, "examples/manifests.json").expect("examples/manifests.json");
    let base = file.get("base").expect("base in manifests.json");
    let examples = file
        .get("examples")
        .and_then(|e| e.as_arr())
        .expect("examples in manifests.json");

    let mut problems = Vec::new();
    let mut seen = BTreeSet::new();

    for example in examples {
        let about = example.get("about").and_then(|a| a.as_str()).unwrap_or("");
        let change = example.get("change").expect("change in example");
        let manifest = apply_change(base, change);
        let accepted = schema::is_valid(&schema_val, &manifest);
        let is_valid_ex = example
            .get("valid")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let schema_false = example.get("schema").and_then(|v| v.as_bool()) == Some(false);
        let expected = is_valid_ex || schema_false;

        if accepted != expected {
            problems.push(format!(
                "manifest '{about}': the schema says {}, the example {}",
                py_bool(accepted),
                py_bool(expected)
            ));
        }
        if is_valid_ex {
            schema::cover(&schema_val, &manifest, &schema_val, &mut seen, "manifest");
        } else if !example.has("problem") {
            problems.push(format!(
                "manifest '{about}': an invalid example names its problem"
            ));
        }
    }

    for folder in ["reference-tool", "reference-tool-2"] {
        let rel = format!("../conformance/{folder}/vitruvian-tool.json");
        let reference = load_json(protocol_dir, &rel).expect("reference manifest");
        if !schema::is_valid(&schema_val, &reference) {
            problems.push(format!("the manifest of {folder} does not pass the schema"));
        }
    }

    problems.extend(schema::unused(&schema_val, "manifest", &seen));
    problems
}

pub fn kind_of(message: &Value) -> &'static str {
    if message.has("method") {
        if message.has("id") {
            "request"
        } else {
            "notice"
        }
    } else if message.has("error") {
        "failure"
    } else {
        "result"
    }
}

fn part_ref(def_name: &str) -> Value {
    Value::Obj(vec![(
        "$ref".into(),
        Value::Str(format!("#/$defs/{def_name}")),
    )])
}

pub fn message_problems(protocol_dir: &Path) -> Vec<String> {
    let schema_val = load_json(protocol_dir, "messages.schema.json").expect("messages.schema.json");
    schema::check_schema(&schema_val).expect("valid messages.schema.json");
    let methods_file = load_json(protocol_dir, "methods.json").expect("methods.json");
    let methods_arr = methods_file
        .get("methods")
        .and_then(|m| m.as_arr())
        .expect("methods array");

    let mut table: HashMap<String, Value> = HashMap::new();
    let mut method_order: Vec<String> = Vec::new();
    for row in methods_arr {
        if let Some(m) = row.get("method").and_then(|v| v.as_str()) {
            method_order.push(m.to_string());
            table.insert(m.to_string(), row.clone());
        }
    }

    let examples_file =
        load_json(protocol_dir, "examples/messages.json").expect("examples/messages.json");
    let examples = examples_file
        .get("examples")
        .and_then(|e| e.as_arr())
        .expect("examples array");

    let mut problems = Vec::new();
    let mut seen = BTreeSet::new();
    let mut shown = BTreeSet::new();
    let mut answered = BTreeSet::new();

    for example in examples {
        let message = example.get("message").expect("message in example");
        let about = example.get("about").and_then(|a| a.as_str()).unwrap_or("");
        let mut accepted = schema::is_valid(&schema_val, message);
        let kind = kind_of(message);
        let row_key = example
            .get("answers")
            .and_then(|a| a.as_str())
            .or_else(|| message.get("method").and_then(|m| m.as_str()));
        let row = row_key.and_then(|k| table.get(k));

        if accepted && kind == "result" {
            if let Some(r) = row {
                let res_def = r.get("result").and_then(|v| v.as_str()).unwrap_or("");
                let res_val = message.get("result").unwrap_or(&Value::Null);
                accepted = schema::is_valid_with_root(&part_ref(res_def), res_val, &schema_val);
            }
        }
        let is_valid_ex = example
            .get("valid")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let schema_false = example.get("schema").and_then(|v| v.as_bool()) == Some(false);
        let expected = is_valid_ex || schema_false;

        if accepted != expected {
            problems.push(format!(
                "message '{about}': the schema says {}, the example {}",
                py_bool(accepted),
                py_bool(expected)
            ));
        }
        if !is_valid_ex {
            continue;
        }
        schema::cover(&schema_val, message, &schema_val, &mut seen, "message");
        schema::cover(&part_ref(kind), message, &schema_val, &mut seen, kind);

        if matches!(kind, "request" | "notice") {
            if let Some(r) = row {
                let m_name = r.get("method").and_then(|v| v.as_str()).unwrap_or("");
                shown.insert(m_name.to_string());
                let r_kind = r.get("kind").and_then(|v| v.as_str()).unwrap_or("");
                if r_kind != kind {
                    problems.push(format!(
                        "message '{about}': methods.json calls {m_name} a {r_kind}"
                    ));
                }
                if let Some(params_def) = r.get("params").and_then(|v| v.as_str()) {
                    if let Some(params_val) = message.get("params") {
                        schema::cover(
                            &part_ref(params_def),
                            params_val,
                            &schema_val,
                            &mut seen,
                            params_def,
                        );
                    }
                }
            }
        }
        if kind == "result" {
            if let Some(r) = row {
                let m_name = r.get("method").and_then(|v| v.as_str()).unwrap_or("");
                answered.insert(m_name.to_string());
                if let Some(res_def) = r.get("result").and_then(|v| v.as_str()) {
                    if let Some(res_val) = message.get("result") {
                        schema::cover(&part_ref(res_def), res_val, &schema_val, &mut seen, res_def);
                    }
                }
            }
        }
        if kind == "failure" {
            if let Some(err_obj) = message.get("error") {
                let code_str = err_obj.get("code").map(|c| c.py_str()).unwrap_or_default();
                if REFUSALS_WITH_DATA.contains(&code_str.as_str()) {
                    if let Some(data_val) = err_obj.get("data") {
                        schema::cover(
                            &part_ref("refusalData"),
                            data_val,
                            &schema_val,
                            &mut seen,
                            "refusalData",
                        );
                    }
                }
            }
        }
    }

    let defs = schema_val
        .get("$defs")
        .expect("$defs in messages.schema.json");
    for method in &method_order {
        let row = &table[method];
        if !shown.contains(method) {
            problems.push(format!("no valid example shows {method}"));
        }
        let r_kind = row.get("kind").and_then(|v| v.as_str()).unwrap_or("");
        if r_kind == "request" && !answered.contains(method) {
            problems.push(format!("no valid example answers {method}"));
        }
        let has_result = row.get("result").is_some_and(|v| !matches!(v, Value::Null));
        if (r_kind == "request") != has_result {
            problems.push(format!(
                "{method}: a request has a result and a notice has none"
            ));
        }
        for field in ["params", "result"] {
            if let Some(def_name) = row.get(field).and_then(|v| v.as_str()) {
                if !defs.has(def_name) {
                    problems.push(format!(
                        "{method}: messages.schema.json has no definition {def_name}"
                    ));
                }
            }
        }
    }

    let mut named = BTreeSet::new();
    for row in table.values() {
        for field in ["params", "result"] {
            if let Some(def_name) = row.get(field).and_then(|v| v.as_str()) {
                named.insert(def_name.to_string());
            }
        }
    }
    if let Some(defs_obj) = defs.as_obj() {
        for (name, _) in defs_obj {
            if (name.ends_with("Params") || name.ends_with("Result")) && !named.contains(name) {
                problems.push(format!("methods.json names no message that carries {name}"));
            }
        }
    }

    for envelope in ["request", "notice"] {
        let mut bound: HashMap<String, String> = HashMap::new();
        if let Some(branches) = defs
            .get(envelope)
            .and_then(|e| e.get("allOf"))
            .and_then(|a| a.as_arr())
        {
            for branch in branches {
                let m = branch
                    .get("if")
                    .and_then(|i| i.get("properties"))
                    .and_then(|p| p.get("method"))
                    .and_then(|m| m.get("const"))
                    .and_then(|c| c.as_str());
                let p_ref = branch
                    .get("then")
                    .and_then(|t| t.get("properties"))
                    .and_then(|p| p.get("params"))
                    .and_then(|p| p.get("$ref"))
                    .and_then(|r| r.as_str());
                if let (Some(m_str), Some(r_str)) = (m, p_ref) {
                    bound.insert(m_str.to_string(), r_str.to_string());
                }
            }
        }
        let mut wanted: HashMap<String, String> = HashMap::new();
        for (method, row) in &table {
            let r_kind = row.get("kind").and_then(|v| v.as_str()).unwrap_or("");
            if r_kind == envelope {
                if let Some(p_name) = row.get("params").and_then(|v| v.as_str()) {
                    wanted.insert(method.clone(), format!("#/$defs/{p_name}"));
                }
            }
        }
        if bound != wanted {
            problems.push(format!(
                "the {envelope} definition ties methods to params otherwise than methods.json does"
            ));
        }
    }

    problems.extend(schema::unused(&schema_val, "message", &seen));
    problems
}

/// The Rust `reference-tool-2` the session runs against.
///
/// Both builds hand it over, as `CARGO_BIN_EXE_reference-tool-2`, which the
/// test binary passes in as `cargo_bin`: Cargo sets it for the bin it builds
/// for its integration tests, and rules_rust sets it (a runfiles-relative
/// path) for a `rust_binary` in the test's `data`. The runfiles lookups below
/// are the second way in under Bazel. So a missing binary is always a broken
/// path, never a reason to test something else: this used to fall back to the
/// Python reference tool, and a path that pointed nowhere still passed,
/// testing the wrong program.
fn find_default_reference_2(
    protocol_dir: &Path,
    cargo_bin: Option<&Path>,
) -> Result<String, String> {
    let mut looked: Vec<PathBuf> = Vec::new();
    if let Some(bin) = cargo_bin {
        // The session runs the tool from a temporary folder, so a relative
        // path (rules_rust's) must be made absolute against ours first.
        let bin = if bin.is_relative() {
            std::env::current_dir()
                .map(|d| d.join(bin))
                .unwrap_or_else(|_| bin.to_path_buf())
        } else {
            bin.to_path_buf()
        };
        if is_executable(&bin) {
            return Ok(bin.to_string_lossy().into_owned());
        }
        looked.push(bin);
    }
    for cand in [
        resolve_runfile("packages/vitruvian-sdk/reference-tool-2"),
        resolve_runfile("reference-tool-2"),
        protocol_dir
            .parent()
            .unwrap_or(protocol_dir)
            .join("reference-tool-2"),
    ] {
        if is_executable(&cand) {
            let abs = std::env::current_dir()
                .map(|d| d.join(&cand))
                .unwrap_or(cand);
            return Ok(abs.to_string_lossy().into_owned());
        }
        looked.push(cand);
    }
    let looked: Vec<String> = looked.iter().map(|p| p.display().to_string()).collect();
    Err(format!(
        "the Rust reference-tool-2 binary is missing (looked at: {}). Under Bazel it is a data dependency of this test; under Cargo the test passes CARGO_BIN_EXE_reference-tool-2. Fix the path rather than testing another program.",
        looked.join(", ")
    ))
}

pub fn session_problems(protocol_dir: &Path, custom_program: Option<&Path>) -> Vec<String> {
    session_problems_with(protocol_dir, custom_program, None)
}

/// `session_problems`, with the Rust reference tool Cargo built (if any).
pub fn session_problems_with(
    protocol_dir: &Path,
    custom_program: Option<&Path>,
    cargo_bin: Option<&Path>,
) -> Vec<String> {
    let schema_val = load_json(protocol_dir, "messages.schema.json").expect("messages.schema.json");
    let methods_file = load_json(protocol_dir, "methods.json").expect("methods.json");
    let mut table: HashMap<String, Value> = HashMap::new();
    if let Some(arr) = methods_file.get("methods").and_then(|m| m.as_arr()) {
        for row in arr {
            if let Some(m) = row.get("method").and_then(|v| v.as_str()) {
                table.insert(m.to_string(), row.clone());
            }
        }
    }

    let (prog, prog_args) = match custom_program {
        Some(p) => {
            let p_str = p.to_string_lossy().into_owned();
            if p_str.ends_with(".py") {
                (find_python3(), vec![p_str])
            } else {
                (p_str, Vec::new())
            }
        }
        None => match find_default_reference_2(protocol_dir, cargo_bin) {
            Ok(p) => (p, Vec::new()),
            Err(e) => return vec![format!("reference-tool-2: {e}")],
        },
    };

    let mut problems: Vec<String> = Vec::new();
    let mut pages: Vec<Value> = Vec::new();
    let mut asked: HashMap<i64, String> = HashMap::new();

    let temp_dir = TempDir::new("vitruvian-proto-examples-").expect("temp dir");
    let data_folder = temp_dir.path().to_string_lossy().into_owned();

    let mut child = match Command::new(&prog)
        .args(&prog_args)
        .current_dir(temp_dir.path())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            return vec![format!("reference-tool-2: failed to spawn {prog}: {e}")];
        }
    };

    let mut child_stdin = child.stdin.take();
    let child_stdout = child.stdout.take().expect("stdout piped");
    let (tx, rx) = mpsc::channel::<String>();
    thread::spawn(move || {
        let reader = BufReader::new(child_stdout);
        for line in reader.lines() {
            match line {
                Ok(mut l) => {
                    l.push('\n');
                    let _ = tx.send(l);
                }
                Err(_) => break,
            }
        }
        let _ = tx.send(String::new());
    });

    let write_msg =
        |stdin_opt: &mut Option<std::process::ChildStdin>, msg: &Value| -> Result<(), String> {
            let stdin = stdin_opt
                .as_mut()
                .ok_or_else(|| "stdin already closed".to_string())?;
            let mut s = msg.dumps_compact();
            s.push('\n');
            stdin
                .write_all(s.as_bytes())
                .and_then(|_| stdin.flush())
                .map_err(|e| e.to_string())
        };

    let judge = |line: &str,
                 asked: &HashMap<i64, String>,
                 problems: &mut Vec<String>,
                 pages: &mut Vec<Value>|
     -> Result<Value, String> {
        let message = json::loads(line).map_err(|e| format!("ValueError({e:?})"))?;
        if let Some(err) = schema::first_error(&schema_val, &message, &schema_val) {
            problems.push(format!(
                "the tool wrote a line the schema refuses: {} ({err})",
                line.trim()
            ));
            return Ok(message);
        }
        let kind = kind_of(&message);
        if kind == "result" {
            if let Some(id_num) = message.get("id").and_then(|v| match v {
                Value::Int(s) => s.parse::<i64>().ok(),
                _ => None,
            }) {
                if let Some(answering) = asked.get(&id_num) {
                    let res_def = table
                        .get(answering)
                        .and_then(|r| r.get("result"))
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    let res_val = message.get("result").unwrap_or(&Value::Null);
                    if let Some(err) = schema::first_error(&part_ref(res_def), res_val, &schema_val)
                    {
                        problems.push(format!(
                            "the tool's answer to {answering} is not one: {err}"
                        ));
                    }
                    if let Some(tree_val) = res_val.get("tree") {
                        pages.push(tree_val.clone());
                    }
                }
            }
        }
        if kind == "notice" && message.get("method").and_then(|m| m.as_str()) == Some("ui/render") {
            if let Some(tree_val) = message.get("params").and_then(|p| p.get("tree")) {
                pages.push(tree_val.clone());
            }
        }
        Ok(message)
    };

    let call_step = |stdin_opt: &mut Option<std::process::ChildStdin>,
                     asked: &mut HashMap<i64, String>,
                     problems: &mut Vec<String>,
                     pages: &mut Vec<Value>,
                     number: i64,
                     method: &str,
                     params: Value|
     -> Result<(), String> {
        asked.insert(number, method.to_string());
        let req = Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("id".into(), Value::Int(number.to_string())),
            ("method".into(), Value::Str(method.into())),
            ("params".into(), params),
        ]);
        write_msg(stdin_opt, &req)?;
        loop {
            let line = rx
                .recv_timeout(Duration::from_secs(LINE_SECONDS))
                .map_err(|_| "Empty()".to_string())?;
            if line.is_empty() {
                return Err(format!(
                    "RuntimeError('the tool exited before it answered {method}')"
                ));
            }
            let message = judge(&line, asked, problems, pages)?;
            if kind_of(&message) == "request" {
                let id_val = message.get("id").cloned().unwrap_or(Value::Null);
                let reply = Value::Obj(vec![
                    ("jsonrpc".into(), Value::Str("2.0".into())),
                    ("id".into(), id_val),
                    ("result".into(), Value::Obj(Vec::new())),
                ]);
                write_msg(stdin_opt, &reply)?;
            } else if message
                .get("id")
                .is_some_and(|id| json::py_eq(id, &Value::Int(number.to_string())))
            {
                return Ok(());
            }
        }
    };

    let session_res: Result<(), String> = (|| {
        call_step(
            &mut child_stdin,
            &mut asked,
            &mut problems,
            &mut pages,
            1,
            "initialize",
            Value::Obj(vec![
                (
                    "protocolVersions".into(),
                    Value::Arr(vec![Value::Str("1".into()), Value::Str("2".into())]),
                ),
                ("language".into(), Value::Str("en-US".into())),
                ("dataFolder".into(), Value::Str(data_folder)),
            ]),
        )?;
        call_step(
            &mut child_stdin,
            &mut asked,
            &mut problems,
            &mut pages,
            2,
            "command/run",
            Value::Obj(vec![("command".into(), Value::Str("hello".into()))]),
        )?;
        call_step(
            &mut child_stdin,
            &mut asked,
            &mut problems,
            &mut pages,
            3,
            "ui/open",
            Value::Obj(vec![("panel".into(), Value::Str("hello".into()))]),
        )?;
        call_step(
            &mut child_stdin,
            &mut asked,
            &mut problems,
            &mut pages,
            4,
            "ui/event",
            Value::Obj(vec![
                ("panel".into(), Value::Str("hello".into())),
                ("block".into(), Value::Str("press".into())),
                ("event".into(), Value::Str("tap".into())),
            ]),
        )?;
        write_msg(
            &mut child_stdin,
            &Value::Obj(vec![
                ("jsonrpc".into(), Value::Str("2.0".into())),
                ("method".into(), Value::Str("ui/close".into())),
                (
                    "params".into(),
                    Value::Obj(vec![("panel".into(), Value::Str("hello".into()))]),
                ),
            ]),
        )?;
        write_msg(
            &mut child_stdin,
            &Value::Obj(vec![
                ("jsonrpc".into(), Value::Str("2.0".into())),
                ("method".into(), Value::Str("shutdown".into())),
            ]),
        )?;
        drop(child_stdin.take());
        loop {
            let line = rx
                .recv_timeout(Duration::from_secs(LINE_SECONDS))
                .map_err(|_| "Empty()".to_string())?;
            if line.is_empty() {
                break;
            }
            judge(&line, &asked, &mut problems, &mut pages)?;
        }
        let deadline = Instant::now() + Duration::from_secs(LINE_SECONDS);
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let code = status.code().unwrap_or(1);
                    if code != 0 {
                        problems.push(format!("the tool exited with {code}"));
                    }
                    break;
                }
                Ok(None) => {
                    if Instant::now() >= deadline {
                        return Err("TimeoutExpired()".to_string());
                    }
                    thread::sleep(Duration::from_millis(1));
                }
                Err(e) => return Err(e.to_string()),
            }
        }
        Ok(())
    })();

    if let Err(failure) = session_res {
        problems.push(format!("the session with the tool broke off: {failure}"));
    }
    let _ = child.kill();
    let _ = child.wait();

    let tree_ref = part_ref("uiTree");
    for page in &pages {
        if let Some(err) = schema::first_error(&tree_ref, page, &schema_val) {
            problems.push(format!("a page the tool sent is not one: {err}"));
        }
    }
    if pages.len() != 2 || json::py_eq(&pages[0], &pages[1]) {
        let pages_repr = Value::Arr(pages.clone()).py_repr();
        problems.push(format!(
            "the tool did not send a first page and a new one: {pages_repr}"
        ));
    }

    problems
        .into_iter()
        .map(|p| format!("reference-tool-2: {p}"))
        .collect()
}

pub fn run_in(package_dir: &Path, custom_program: Option<&Path>) -> (i32, Vec<String>, String) {
    run_in_with(package_dir, custom_program, None)
}

/// `run_in`, with the Rust reference tool Cargo built (if any).
pub fn run_in_with(
    package_dir: &Path,
    custom_program: Option<&Path>,
    cargo_bin: Option<&Path>,
) -> (i32, Vec<String>, String) {
    let protocol_dir = package_dir.join("protocol");
    let mut problems = manifest_problems(&protocol_dir);
    problems.extend(message_problems(&protocol_dir));
    problems.extend(session_problems_with(
        &protocol_dir,
        custom_program,
        cargo_bin,
    ));
    let status_word = if problems.is_empty() { "OK" } else { "FAILED" };
    let stdout_text = format!("protocol examples: {status_word}\n");
    let code = if problems.is_empty() { 0 } else { 1 };
    (code, problems, stdout_text)
}

pub fn main_with_args(args: &[String]) -> i32 {
    main_with_reference(args, None)
}

/// The test's entry point. `cargo_bin` is `CARGO_BIN_EXE_reference-tool-2`
/// when Cargo built the test, and None under Bazel (runfiles carry it).
pub fn main_with_reference(args: &[String], cargo_bin: Option<&Path>) -> i32 {
    let package_dir = match find_package_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };
    let custom_prog = args.first().map(|s| resolve_runfile(s));
    let (code, problems, stdout_text) =
        run_in_with(&package_dir, custom_prog.as_deref(), cargo_bin);
    for problem in problems {
        eprintln!("{problem}");
    }
    print!("{stdout_text}");
    code
}
