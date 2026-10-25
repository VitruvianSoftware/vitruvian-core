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

//! lint-naming-rs-probe: calls the port's rule functions one at a time, for
//! lint_naming_rs_parity_test to compare with the Python functions the test
//! suites call. Not a user-facing tool.
//!
//! Each line of stdin is one call: the function's name, then its arguments,
//! tab-separated, each hex-encoded (UTF-8, surrogates as CESU-8). Each line
//! of stdout is the result as Python's repr() of it.

use lint_naming::pystr::{repr, surrogate_char};
use lint_naming::rules::{bazel, configs, directories, environment, migration, source_files};
use lint_naming::scanner::{format_report, LineCache, Scanner};
use lint_naming::violation::{Severity, Violation};
use std::collections::HashMap;
use std::io::{BufRead, Write};

fn unhex(s: &str) -> String {
    let bytes: Vec<u8> = (0..s.len() / 2)
        .map(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).expect("hex"))
        .collect();
    // UTF-8, except that ED A0..BF xx is a surrogate.
    let mut out = String::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0xED && i + 2 < bytes.len() && (0xA0..=0xBF).contains(&bytes[i + 1]) {
            let v = (((bytes[i] & 0x0F) as u32) << 12)
                | (((bytes[i + 1] & 0x3F) as u32) << 6)
                | ((bytes[i + 2] & 0x3F) as u32);
            out.push(surrogate_char(v));
            i += 3;
            continue;
        }
        let len = match bytes[i] {
            0x00..=0x7F => 1,
            0xC0..=0xDF => 2,
            0xE0..=0xEF => 3,
            _ => 4,
        };
        out.push_str(std::str::from_utf8(&bytes[i..i + len]).expect("utf-8"));
        i += len;
    }
    out
}

fn opt_int(s: &str) -> Option<i64> {
    if s == "-" {
        None
    } else {
        Some(s.parse().expect("int"))
    }
}

fn py_opt_str(s: &Option<String>) -> String {
    s.as_ref().map(|x| repr(x)).unwrap_or_else(|| "None".into())
}

fn py_violations(v: &[Violation]) -> String {
    let items: Vec<String> = v
        .iter()
        .map(|x| {
            format!(
                "({}, {}, {}, {}, {}, {})",
                repr(&x.rule_id),
                repr(&x.file_path),
                x.line_number
                    .map(|n| n.to_string())
                    .unwrap_or_else(|| "None".into()),
                repr(x.severity.as_str()),
                repr(&x.message),
                py_opt_str(&x.suggested_fix)
            )
        })
        .collect();
    format!("[{}]", items.join(", "))
}

fn call(f: &[String]) -> String {
    let a = |i: usize| f[i + 1].clone();
    match f[0].as_str() {
        "dir" => py_violations(&directories::validate_directory_name(&a(0), a(1) == "1")),
        "file" => py_violations(&source_files::validate_file_name(&a(0))),
        "config" => py_violations(&configs::validate_config_file_name(&a(0))),
        "workflow" => py_violations(&configs::validate_workflow_yaml_content(&a(0), &a(1))),
        "k8s" => py_violations(&configs::validate_k8s_resource_name(
            &a(0),
            &a(1),
            opt_int(&a(2)).unwrap(),
        )),
        "pulumi" => py_violations(&configs::validate_pulumi_config_key(
            &a(0),
            &a(1),
            opt_int(&a(2)).unwrap(),
        )),
        "target" => py_violations(&bazel::validate_bazel_target_name(
            &a(0),
            &a(1),
            &a(2),
            opt_int(&a(3)),
        )),
        "starlark" => py_violations(&bazel::validate_starlark_file_name(&a(0))),
        "build" => {
            let r = bazel::validate_build_file_content(&a(0), &a(1));
            let w: Vec<String> = r
                .warnings
                .iter()
                .map(|w| format!("({}, {})", w.line, repr(&w.message)))
                .collect();
            format!("({}, [{}])", py_violations(&r.violations), w.join(", "))
        }
        "pyast" => {
            let parsed = lint_naming::pyast::parse(&a(0));
            let w: Vec<String> = parsed
                .warnings
                .iter()
                .map(|w| format!("({}, {})", w.line, repr(&w.message)))
                .collect();
            let calls = match &parsed.calls {
                None => "None".to_string(),
                Some(cs) => {
                    let items: Vec<String> = cs
                        .iter()
                        .map(|c| {
                            let kws: Vec<String> = c
                                .keywords
                                .iter()
                                .map(|k| {
                                    format!(
                                        "({}, {}, {})",
                                        py_opt_str(&k.arg),
                                        k.line,
                                        py_opt_str(&k.str_value)
                                    )
                                })
                                .collect();
                            format!("({}, [{}])", py_opt_str(&c.rule_type), kws.join(", "))
                        })
                        .collect();
                    format!("[{}]", items.join(", "))
                }
            };
            format!("({}, [{}])", calls, w.join(", "))
        }
        "where" => format!("{:?}", lint_naming::pyast::failure_point(&a(0))),
        "env" => py_violations(&environment::validate_env_var_name(
            &a(0),
            &a(1),
            opt_int(&a(2)),
        )),
        "flag" => py_violations(&environment::validate_cli_flag_name(
            &a(0),
            &a(1),
            opt_int(&a(2)),
        )),
        "risk" => repr(migration::assess_rename_risk(&a(0), &a(1)).as_str()),
        "alias" => {
            let mut m = HashMap::new();
            let mut i = 3;
            while i + 1 < f.len() {
                m.insert(f[i].clone(), f[i + 1].clone());
                i += 2;
            }
            py_violations(&migration::validate_alias_compatibility(&a(0), &a(1), &m))
        }
        "symlink" => py_violations(&migration::validate_symlink_alias(&a(0), &a(1))),
        "scan" | "ignore" | "rootdir" => {
            // root, ignore_violation_fixtures, then "default" or the ignores.
            let ignores = if f.len() > 3 && f[3] == "default" {
                None
            } else {
                Some(f[3..].to_vec())
            };
            let ignores = if f[0] == "ignore" {
                if f.len() > 4 && f[4] == "default" {
                    None
                } else {
                    Some(f[4..].to_vec())
                }
            } else {
                ignores
            };
            let s = Scanner::new(&a(0), ignores, a(1) == "1");
            match f[0].as_str() {
                "scan" => {
                    let mut cache = LineCache::default();
                    py_violations(&s.scan(&mut cache, &mut |_| {}))
                }
                "ignore" => (if s.should_ignore(&a(2)) {
                    "True"
                } else {
                    "False"
                })
                .to_string(),
                _ => repr(&s.root_dir),
            }
        }
        "format" => {
            // output_format, then six fields per violation.
            let mut v = Vec::new();
            let mut i = 2;
            while i + 5 < f.len() {
                v.push(Violation {
                    rule_id: f[i].clone(),
                    file_path: f[i + 1].clone(),
                    line_number: opt_int(&f[i + 2]),
                    severity: Severity::parse(&f[i + 3]).expect("severity"),
                    message: f[i + 4].clone(),
                    suggested_fix: if f[i + 5] == "-" {
                        None
                    } else {
                        Some(f[i + 5].clone())
                    },
                });
                i += 6;
            }
            repr(&format_report(&v, &a(0)))
        }
        other => panic!("unknown call {}", other),
    }
}

fn main() {
    lint_naming::with_big_stack(|| {
        let stdin = std::io::stdin();
        let stdout = std::io::stdout();
        let mut out = stdout.lock();
        for line in stdin.lock().lines() {
            let line = line.expect("stdin");
            if line.is_empty() {
                continue;
            }
            // The verb and numbers stay plain; strings are hex.
            let fields: Vec<String> = line
                .split('\t')
                .enumerate()
                .map(|(i, x)| {
                    if i == 0 || x.starts_with('=') {
                        x.trim_start_matches('=').to_string()
                    } else {
                        unhex(x)
                    }
                })
                .collect();
            let result = call(&fields);
            let _ = writeln!(out, "{}", result);
        }
    });
}
