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
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const APPSET_REL_PATH: &str = "gitops/argocd/platform/prometheus/applicationset.yaml";
const THIS_PKG_REL_DIR: &str = "tools/ci/prometheus-rule-tests";

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

# Every actionable rule must name the PagerDuty service it opens an incident
# on, and Alertmanager must have a pagerduty-<service> receiver for it.
# Without the label an alert still pages (the catch-all lands on cluster), but
# on the wrong service -- the thing per-source services exist to prevent.
am = parsed.get("alertmanager", {}).get("config", {})
pd_services = {r["name"][len("pagerduty-"):] for r in am.get("receivers", [])
               if r.get("name", "").startswith("pagerduty-")}
if not pd_services:
    raise SystemExit("no pagerduty-<service> receivers in alertmanager.config -- "
                     "extraction is broken, or PagerDuty routing was removed")
bad = []
for g in rules["groups"]:
    for r in g.get("rules", []):
        labels = r.get("labels") or {}
        if "alert" not in r or labels.get("severity") not in ("page", "warning"):
            continue
        svc = labels.get("pagerduty_service")
        if svc not in pd_services:
            bad.append(f"  {g['name']}/{r['alert']}: pagerduty_service={svc!r}")
if bad:
    raise SystemExit("actionable alert rules without a routable pagerduty_service label "
                     f"(want one of {sorted(pd_services)}):\n" + "\n".join(bad))

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

/// Make `p` absolute against `cwd` without resolving symlinks (so Bazel
/// `py_binary` wrappers keep their `.runfiles` sibling lookup).
fn make_abs_from(p: &Path, cwd: Option<&Path>) -> PathBuf {
    if p.is_absolute() {
        p.to_path_buf()
    } else if let Some(d) = cwd {
        d.join(p)
    } else {
        p.to_path_buf()
    }
}

fn make_abs(p: &Path) -> PathBuf {
    make_abs_from(p, std::env::current_dir().ok().as_deref())
}

fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
}

fn exe_runfiles(p: &Path, cwd: Option<&Path>) -> Option<PathBuf> {
    let abs = make_abs_from(p, cwd);
    let mut direct_os = abs.as_os_str().to_os_string();
    direct_os.push(".runfiles");
    let direct = PathBuf::from(direct_os);
    if direct.is_dir() {
        return Some(direct);
    }
    if let Ok(canon) = fs::canonicalize(&abs) {
        let mut canon_os = canon.as_os_str().to_os_string();
        canon_os.push(".runfiles");
        let rf = PathBuf::from(canon_os);
        if rf.is_dir() {
            return Some(rf);
        }
    }
    None
}

/// Locate Bazel's `*.runfiles` directory when `RUNFILES_DIR` is unset (as
/// happens under `bazel run`).
pub fn discover_runfiles_dir_with(
    env_rf: Option<&Path>,
    argv0: Option<&Path>,
    current_exe: Option<&Path>,
    cwd: Option<&Path>,
) -> Option<PathBuf> {
    if let Some(rf) = env_rf.filter(|p| p.is_dir()) {
        return Some(rf.to_path_buf());
    }
    if let Some(rf) = argv0.and_then(|p| exe_runfiles(p, cwd)) {
        return Some(rf);
    }
    if let Some(rf) = current_exe.and_then(|p| exe_runfiles(p, cwd)) {
        return Some(rf);
    }
    if let Some(dir) = cwd {
        for anc in dir.ancestors() {
            if anc
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.ends_with(".runfiles"))
                && anc.is_dir()
            {
                return Some(anc.to_path_buf());
            }
        }
    }
    None
}

pub fn discover_runfiles_dir(argv0: Option<&Path>) -> Option<PathBuf> {
    discover_runfiles_dir_with(
        env_path("RUNFILES_DIR").as_deref(),
        argv0,
        std::env::current_exe().ok().as_deref(),
        std::env::current_dir().ok().as_deref(),
    )
}

fn resolve_env_tool(p: &Path, rf_dir: Option<&Path>) -> Option<PathBuf> {
    let mut candidates = vec![make_abs(p)];
    if !p.is_absolute() {
        if let Some(rest) = p.to_str().and_then(|s| s.strip_prefix("external/")) {
            candidates.push(make_abs(&Path::new("..").join(rest)));
        }
        if let Some(rf) = rf_dir {
            candidates.push(rf.join("_main").join(p));
            candidates.push(rf.join(p));
            if let Some(rest) = p.to_str().and_then(|s| s.strip_prefix("external/")) {
                candidates.push(rf.join(rest));
            }
        }
    }
    candidates
        .into_iter()
        .find(|cand| which(cand.as_os_str().as_bytes()).is_some())
}

fn apply_runfiles_env(cmd: &mut Command, rf_dir: Option<&Path>) {
    if env_path("RUNFILES_DIR").is_none() && env_path("RUNFILES_MANIFEST_FILE").is_none() {
        if let Some(rf) = rf_dir {
            cmd.env("RUNFILES_DIR", rf);
        }
    }
}

/// Resolve `gitops/argocd/platform/prometheus/applicationset.yaml`, preferring
/// `BUILD_WORKSPACE_DIRECTORY` under `bazel run`, then local workspace/runfiles.
pub fn resolve_appset_path_with(
    ws_dir: Option<&Path>,
    rf_dir: Option<&Path>,
    argv0: Option<&Path>,
) -> PathBuf {
    if let Some(ws) = ws_dir {
        let p = ws.join(APPSET_REL_PATH);
        if p.is_file() {
            return p;
        }
    }
    if let Some(rf) = rf_dir {
        let p = rf.join("_main").join(APPSET_REL_PATH);
        if p.is_file() {
            return p;
        }
    }
    let rel = Path::new(APPSET_REL_PATH);
    if rel.is_file() {
        return make_abs(rel);
    }
    if let Some(p) = argv0 {
        let parent = p
            .parent()
            .filter(|d| !d.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new("."));
        if let Ok(canon) = fs::canonicalize(parent) {
            if let Some(bin_name) = p.file_name() {
                let rf = canon
                    .join(format!("{}.runfiles", bin_name.to_string_lossy()))
                    .join("_main")
                    .join(APPSET_REL_PATH);
                if rf.is_file() {
                    return rf;
                }
            }
        }
    }
    PathBuf::from(APPSET_REL_PATH)
}

pub fn resolve_appset_path(argv0: Option<&Path>) -> PathBuf {
    let rf_dir = discover_runfiles_dir(argv0);
    resolve_appset_path_with(
        env_path("BUILD_WORKSPACE_DIRECTORY").as_deref(),
        rf_dir.as_deref(),
        argv0,
    )
}

/// Resolve the directory containing `*.test.yml` files, preferring
/// `BUILD_WORKSPACE_DIRECTORY` under `bazel run`, then runfiles / cwd fallbacks.
pub fn resolve_here_dir_with(
    ws_dir: Option<&Path>,
    rf_dir: Option<&Path>,
    argv0: Option<&Path>,
) -> PathBuf {
    if let Some(ws) = ws_dir {
        let p = ws.join(THIS_PKG_REL_DIR);
        if !list_test_yml_files(&p).is_empty() {
            return p;
        }
    }
    if let Some(rf) = rf_dir {
        let p = rf.join("_main").join(THIS_PKG_REL_DIR);
        if !list_test_yml_files(&p).is_empty() {
            return p;
        }
    }
    let rel = PathBuf::from(THIS_PKG_REL_DIR);
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
            if !list_test_yml_files(&canon).is_empty() {
                return canon;
            }
            // Check Bazel runfiles beside binary
            if let Some(bin_name) = p.file_name() {
                let rf = canon
                    .join(format!("{}.runfiles", bin_name.to_string_lossy()))
                    .join("_main")
                    .join(THIS_PKG_REL_DIR);
                if !list_test_yml_files(&rf).is_empty() {
                    return rf;
                }
            }
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

pub fn resolve_here_dir(argv0: Option<&Path>) -> PathBuf {
    let rf_dir = discover_runfiles_dir(argv0);
    resolve_here_dir_with(
        env_path("BUILD_WORKSPACE_DIRECTORY").as_deref(),
        rf_dir.as_deref(),
        argv0,
    )
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
    let rf_dir = discover_runfiles_dir(argv0.as_deref());
    let here = resolve_here_dir(argv0.as_deref());

    let promtool = match env_path("PROMTOOL") {
        Some(raw) => match resolve_env_tool(&raw, rf_dir.as_deref()) {
            Some(p) => p,
            None => {
                return fail(&format!(
                    "PROMTOOL={} not found or not executable",
                    raw.display()
                ))
            }
        },
        None => match which(b"promtool") {
            Some(p) => p,
            None => {
                return fail(
                    "promtool not found on PATH (install prometheus, or use the Bazel target)",
                )
            }
        },
    };
    let python = match env_path("PYYAML_PYTHON") {
        Some(raw) => match resolve_env_tool(&raw, rf_dir.as_deref()) {
            Some(p) => p,
            None => {
                return fail(&format!(
                    "PYYAML_PYTHON={} not found or not executable",
                    raw.display()
                ))
            }
        },
        None => PathBuf::from("python3"),
    };

    let mut py_check_cmd = Command::new(&python);
    py_check_cmd
        .arg("-c")
        .arg("import yaml")
        .stdin(Stdio::null());
    apply_runfiles_env(&mut py_check_cmd, rf_dir.as_deref());
    match py_check_cmd.output() {
        Ok(out) if out.status.success() => {}
        Ok(out) => {
            let detail = String::from_utf8_lossy(&out.stderr);
            let detail = detail.trim();
            if detail.is_empty() {
                return fail("PyYAML not importable -- pip install pyyaml");
            }
            return fail(&format!(
                "PyYAML not importable -- pip install pyyaml ({detail})"
            ));
        }
        Err(e) => {
            return fail(&format!(
                "PyYAML not importable -- pip install pyyaml ({e})"
            ))
        }
    }

    let appset_path = resolve_appset_path(argv0.as_deref());
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
    let mut py_cmd = Command::new(&python);
    py_cmd
        .arg("-")
        .arg(&appset_path)
        .arg(&rules_yml)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    apply_runfiles_env(&mut py_cmd, rf_dir.as_deref());
    let mut py_child = match py_cmd.spawn() {
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

    let check_st = Command::new(&promtool)
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
        let st = Command::new(&promtool)
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
        fs::write(dir.join("vitruvian-slack-mcp.test.yml"), "tests: []\n").unwrap();
        fs::write(dir.join("ignored.yml"), "tests: []\n").unwrap();

        let files = list_test_yml_files(&dir);
        let names: Vec<String> = files
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            vec![
                "argocd.test.yml",
                "oom.test.yml",
                "vitruvian-slack-mcp.test.yml"
            ]
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolves_appset_and_tests_from_workspace_dir_first() {
        let dir = std::env::temp_dir().join(format!("prom-rule-ws-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let ws = dir.join("ws");
        let rf = dir.join("rf");
        let ws_appset = ws.join(APPSET_REL_PATH);
        let rf_appset = rf.join("_main").join(APPSET_REL_PATH);
        let ws_tests = ws.join(THIS_PKG_REL_DIR);
        let rf_tests = rf.join("_main").join(THIS_PKG_REL_DIR);
        fs::create_dir_all(ws_appset.parent().unwrap()).unwrap();
        fs::create_dir_all(rf_appset.parent().unwrap()).unwrap();
        fs::create_dir_all(&ws_tests).unwrap();
        fs::create_dir_all(&rf_tests).unwrap();
        fs::write(&ws_appset, "ws").unwrap();
        fs::write(&rf_appset, "rf").unwrap();
        fs::write(ws_tests.join("headscale.test.yml"), "tests: []\n").unwrap();
        fs::write(rf_tests.join("headscale.test.yml"), "tests: []\n").unwrap();

        assert_eq!(
            resolve_appset_path_with(Some(&ws), Some(&rf), None),
            ws_appset
        );
        assert_eq!(resolve_here_dir_with(Some(&ws), Some(&rf), None), ws_tests);
        assert_eq!(resolve_appset_path_with(None, Some(&rf), None), rf_appset);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn discovers_runfiles_dir_when_unset_under_bazel_run() {
        use std::os::unix::fs::{symlink, PermissionsExt};
        let base = fs::canonicalize(std::env::temp_dir()).unwrap_or_else(|_| std::env::temp_dir());
        let dir = base.join(format!("prom-rule-rf-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let bin_dir = dir.join("bin");
        let exe = bin_dir.join("run");
        let rf_dir = bin_dir.join("run.runfiles");
        let rf_main_cwd = rf_dir.join("_main");
        let rf_pkg = rf_main_cwd.join(THIS_PKG_REL_DIR);
        fs::create_dir_all(&rf_pkg).unwrap();
        fs::write(&exe, "#!/bin/sh\nexit 0\n").unwrap();
        let mut perms = fs::metadata(&exe).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&exe, perms).unwrap();
        let symlink_in_rf = rf_pkg.join("run");
        symlink(&exe, &symlink_in_rf).unwrap();

        assert_eq!(
            discover_runfiles_dir_with(None, Some(&exe), None, None),
            Some(rf_dir.clone())
        );
        assert_eq!(
            discover_runfiles_dir_with(None, Some(&symlink_in_rf), None, None),
            Some(rf_dir.clone())
        );
        assert_eq!(
            discover_runfiles_dir_with(None, None, None, Some(&rf_main_cwd)),
            Some(rf_dir)
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn committed_prometheus_rule_suites_pass() {
        assert_eq!(run(&[]), 0);
    }
}
