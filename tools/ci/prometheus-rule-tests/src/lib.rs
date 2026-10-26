// Copyright (c) 2026 VitruvianSoftware
//
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

//! Rust port of `tools/ci/prometheus-rule-tests/run.sh`.
//!
//! Extracts Prometheus alerting rules from
//! `gitops/argocd/platform/prometheus/applicationset.yaml` at run time,
//! validates them with `promtool check rules`, and runs `promtool test rules`
//! across every `*.test.yml` suite alongside the runner.

use shell_compat::{err, out, status_code, which};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const APPSET_REL_PATH: &str = "gitops/argocd/platform/prometheus/applicationset.yaml";

const EXTRACT_PY_SCRIPT: &[u8] = br#"import re, sys, yaml

appset, out = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(appset))
values = doc["spec"]["template"]["spec"]["source"]["helm"]["values"].strip()
values = re.sub(r"^\{\{`\s*\n", "", values)
values = re.sub(r"\n\s*`\}\}$", "", values)
parsed = yaml.safe_load(values)

rules = parsed.get("serverFiles", {}).get("alerting_rules.yml")
if not rules or not rules.get("groups"):
    raise SystemExit("no alerting_rules.yml groups found -- extraction is broken, "
                     "not the rules; fix this script rather than deleting the test")
yaml.safe_dump(rules, open(out, "w"), default_flow_style=False)
print(f"prometheus-rule-tests: extracted {len(rules['groups'])} rule group(s)")
"#;

fn fail(msg: &str) -> i32 {
    err(format!("prometheus-rule-tests: {msg}\n").as_bytes());
    1
}

/// Strip Go raw-string template delimiters `{{`\n` and `\n`}}` around a Helm
/// values block, matching `run.sh`'s regex stripping.
pub fn strip_gotemplate_delimiters(raw: &str) -> String {
    let trimmed = raw.trim();
    let without_open = if let Some(rest) = trimmed.strip_prefix("{{`") {
        let rest = rest.trim_start_matches(|c: char| c.is_whitespace() && c != '\n');
        rest.strip_prefix('\n').unwrap_or(rest)
    } else {
        trimmed
    };
    if let Some(prefix) = without_open.strip_suffix("`}}") {
        if let Some(nl_pos) = prefix.rfind('\n') {
            if prefix[nl_pos + 1..].chars().all(char::is_whitespace) {
                return prefix[..nl_pos].to_string();
            }
        }
    }
    without_open.to_string()
}

/// Resolve the directory containing `*.test.yml` files, mirroring
/// `HERE="$(cd "$(dirname "$0")" && pwd)"` with fallbacks for Bazel runfiles
/// and workspace roots.
pub fn resolve_here_dir(argv0: Option<&Path>) -> PathBuf {
    if let Some(p) = argv0 {
        let parent = p
            .parent()
            .filter(|d| !d.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        if let Ok(canon) = fs::canonicalize(parent) {
            if !list_test_yml_files(&canon).is_empty() {
                return canon;
            }
            // Check Bazel runfiles beside binary
            if let Some(bin_name) = p.file_name() {
                let rf = canon
                    .join(format!("{}.runfiles", bin_name.to_string_lossy()))
                    .join("_main/tools/ci/prometheus-rule-tests");
                if !list_test_yml_files(&rf).is_empty() {
                    return rf;
                }
            }
        }
    }
    let rel = PathBuf::from("tools/ci/prometheus-rule-tests");
    if let Ok(canon) = fs::canonicalize(&rel) {
        if !list_test_yml_files(&canon).is_empty() {
            return canon;
        }
    }
    if let Some(p) = argv0 {
        let parent = p
            .parent()
            .filter(|d| !d.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        if let Ok(canon) = fs::canonicalize(parent) {
            return canon;
        }
        return parent.to_path_buf();
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// Return sorted `*.test.yml` paths in `dir`, matching bash's lexicographical
/// glob expansion `"${HERE}"/*.test.yml`.
pub fn list_test_yml_files(dir: &Path) -> Vec<PathBuf> {
    let mut out_files = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".test.yml") && path.is_file() {
                    out_files.push(path);
                }
            }
        }
    }
    out_files.sort();
    out_files
}

fn create_temp_work_dir() -> Result<PathBuf, std::io::Error> {
    let out = Command::new("mktemp")
        .arg("-d")
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()?;
    if !out.status.success() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "mktemp -d failed",
        ));
    }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    Ok(PathBuf::from(s))
}

struct TempDirGuard(PathBuf);

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let argv0 = std::env::args_os().next().map(PathBuf::from);
    let here = resolve_here_dir(argv0.as_deref());

    if which(b"promtool").is_none() {
        return fail("promtool not found on PATH (install prometheus, or use the CI job)");
    }

    let py_check = Command::new("python3")
        .arg("-c")
        .arg("import yaml")
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::null())
        .status();
    if !py_check.map(|s| s.success()).unwrap_or(false) {
        return fail("PyYAML not importable -- pip install pyyaml");
    }

    let appset_path = Path::new(APPSET_REL_PATH);
    if !appset_path.is_file() {
        return fail(&format!(
            "{APPSET_REL_PATH} not found (run from the repo root)"
        ));
    }

    let work = match create_temp_work_dir() {
        Ok(d) => d,
        Err(_) => return 1,
    };
    let _guard = TempDirGuard(work.clone());

    let rules_yml = work.join("rules.yml");
    let mut py_child = match Command::new("python3")
        .arg("-")
        .arg(APPSET_REL_PATH)
        .arg(&rules_yml)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(c) => c,
        Err(_) => return 1,
    };
    if let Some(mut stdin) = py_child.stdin.take() {
        let _ = stdin.write_all(EXTRACT_PY_SCRIPT);
    }
    match py_child.wait() {
        Ok(st) if st.success() => {}
        Ok(st) => return status_code(st),
        Err(_) => return 1,
    }

    let check_st = Command::new("promtool")
        .arg("check")
        .arg("rules")
        .arg(&rules_yml)
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .status();
    if !check_st.map(|s| s.success()).unwrap_or(false) {
        return fail("extracted rules are not valid");
    }

    let src_tests = list_test_yml_files(&here);
    if src_tests.is_empty() {
        // Mirror `cp "${HERE}"/*.test.yml "${WORK}/"` failing under `set -eu` when no files match.
        let cp_st = Command::new("cp")
            .arg(here.join("*.test.yml"))
            .arg(&work)
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        return cp_st.map(status_code).unwrap_or(1);
    }

    for src in &src_tests {
        if let Some(fname) = src.file_name() {
            if fs::copy(src, work.join(fname)).is_err() {
                return 1;
            }
        }
    }

    let work_tests = list_test_yml_files(&work);
    let mut rc = 0;
    for t in &work_tests {
        let base = t
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        out(format!("prometheus-rule-tests: {base}\n").as_bytes());
        let st = Command::new("promtool")
            .arg("test")
            .arg("rules")
            .arg(&base)
            .current_dir(&work)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        if !st.map(|s| s.success()).unwrap_or(false) {
            rc = 1;
        }
    }

    if rc != 0 {
        return fail("rule unit tests failed");
    }

    out(b"prometheus-rule-tests: all rule unit tests pass\n");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_go_template_delimiters_correctly() {
        let input = "  {{`  \nserverFiles:\n  alerting_rules.yml:\n    groups: []\n  `}}  ";
        let stripped = strip_gotemplate_delimiters(input);
        assert_eq!(
            stripped,
            "serverFiles:\n  alerting_rules.yml:\n    groups: []"
        );
    }

    #[test]
    fn preserves_plain_yaml_without_gotemplate_delimiters() {
        let input = "serverFiles:\n  alerting_rules.yml:\n    groups: []";
        assert_eq!(strip_gotemplate_delimiters(input), input);
    }

    #[test]
    fn lists_test_yml_files_in_sorted_order() {
        let dir = std::env::temp_dir().join(format!("prom-rule-test-unit-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("oom.test.yml"), "tests: []\n").unwrap();
        fs::write(dir.join("argocd.test.yml"), "tests: []\n").unwrap();
        fs::write(dir.join("mcp-slack.test.yml"), "tests: []\n").unwrap();
        fs::write(dir.join("ignored.yml"), "tests: []\n").unwrap();

        let files = list_test_yml_files(&dir);
        let names: Vec<String> = files
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            vec!["argocd.test.yml", "mcp-slack.test.yml", "oom.test.yml"]
        );
        let _ = fs::remove_dir_all(&dir);
    }
}
