// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust validators and E2E test runner for Grafana production dashboards.
//!
//! Provides 100% behavioral and output parity with the original Python test suites
//! (`tier1_schema_test.py`, `tier2_promql_test.py`, `tier3_integration_test.py`,
//! `tier4_telemetry_test.py`, `ci_pipelines_test.py`) and Bash orchestrator (`runner.sh`).

pub mod ci_pipelines;
pub mod runner;
pub mod tier1;
pub mod tier2;
pub mod tier3;
pub mod tier4;

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

/// All 6 dashboards validated by Tier 1 (Schema) and Tier 2 (PromQL).
pub const TARGET_DASHBOARDS_6: [&str; 6] = [
    "argocd.json",
    "envoy-gateway.json",
    "identity-mesh.json",
    "data-platform-dr.json",
    "agent-integrations.json",
    "ci-pipelines.json",
];

/// The 5 core platform dashboards validated by Tier 3 (Kustomize) and Tier 4 (Live Telemetry).
pub const TARGET_DASHBOARDS_5: [&str; 5] = [
    "argocd.json",
    "envoy-gateway.json",
    "identity-mesh.json",
    "data-platform-dr.json",
    "agent-integrations.json",
];

/// Locate the `gitops/argocd/platform/grafana-dashboards` directory across Bazel runfiles,
/// workspace roots, or parent directories, matching Python's `find_dashboards_dir()`.
pub fn find_dashboards_dir() -> Result<PathBuf, String> {
    if let Ok(override_dir) = env::var("GRAFANA_DASHBOARDS_DIR") {
        if !override_dir.is_empty() {
            let p = PathBuf::from(&override_dir);
            if p.is_dir() {
                return Ok(fs::canonicalize(&p).unwrap_or(p));
            }
        }
    }

    let test_srcdir = env::var("TEST_SRCDIR").ok().filter(|s| !s.is_empty());
    let test_ws = env::var("TEST_WORKSPACE")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "_main".to_string());
    let build_ws = env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_default();

    let mut candidates = vec![
        PathBuf::from("gitops/argocd/platform/grafana-dashboards"),
        PathBuf::from("_main/gitops/argocd/platform/grafana-dashboards"),
        PathBuf::from("../../../gitops/argocd/platform/grafana-dashboards"),
        PathBuf::from(&build_ws).join("gitops/argocd/platform/grafana-dashboards"),
    ];

    if let Some(ref srcdir) = test_srcdir {
        let base = PathBuf::from(srcdir);
        candidates.push(
            base.join(&test_ws)
                .join("gitops/argocd/platform/grafana-dashboards"),
        );
        candidates.push(base.join("_main/gitops/argocd/platform/grafana-dashboards"));
        candidates.push(base.join("gitops/argocd/platform/grafana-dashboards"));
    }

    for c in &candidates {
        if c.is_dir() {
            return Ok(fs::canonicalize(c).unwrap_or_else(|_| c.clone()));
        }
    }

    if let Ok(mut cur) = env::current_dir() {
        loop {
            let target = cur.join("gitops/argocd/platform/grafana-dashboards");
            if target.is_dir() {
                return Ok(fs::canonicalize(&target).unwrap_or(target));
            }
            let target_main = cur.join("_main/gitops/argocd/platform/grafana-dashboards");
            if target_main.is_dir() {
                return Ok(fs::canonicalize(&target_main).unwrap_or(target_main));
            }
            if !cur.pop() {
                break;
            }
        }
    }

    Err("Could not locate gitops/argocd/platform/grafana-dashboards directory".to_string())
}

/// Recursively collect all panels including nested row panels (`type == "row"`).
pub fn collect_all_panels(dashboard: &Value) -> Vec<&Value> {
    let mut panels = Vec::new();
    if let Some(arr) = dashboard.get("panels").and_then(Value::as_array) {
        for p in arr {
            panels.push(p);
            if p.get("type").and_then(Value::as_str) == Some("row") {
                if let Some(sub_panels) = p.get("panels").and_then(Value::as_array) {
                    for sub_p in sub_panels {
                        panels.push(sub_p);
                    }
                }
            }
        }
    }
    panels
}

/// Format a Python string `repr(s)` using single quotes by default (or double quotes if `s`
/// contains `'` and not `"`), matching Python's `repr()`.
pub fn py_str_repr(s: &str) -> String {
    if s.contains('\'') && !s.contains('"') {
        let escaped = s.replace('\\', "\\\\").replace('"', "\\\"");
        format!("\"{}\"", escaped)
    } else {
        let escaped = s.replace('\\', "\\\\").replace('\'', "\\'");
        format!("'{}'", escaped)
    }
}

/// Format a `serde_json::Value` to match Python's `str(val)` / `repr(val)` formatting.
pub fn py_repr(v: &Value) -> String {
    match v {
        Value::Null => "None".to_string(),
        Value::Bool(true) => "True".to_string(),
        Value::Bool(false) => "False".to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => py_str_repr(s),
        Value::Array(arr) => {
            let items: Vec<String> = arr.iter().map(py_repr).collect();
            format!("[{}]", items.join(", "))
        }
        Value::Object(map) => {
            let items: Vec<String> = map
                .iter()
                .map(|(k, val)| format!("{}: {}", py_str_repr(k), py_repr(val)))
                .collect();
            format!("{{{}}}", items.join(", "))
        }
    }
}

/// Format an `Option<&Value>` as Python would in an f-string `{val}` (where `str` is unquoted at
/// top level, while `None`, `bool`, `list`, `dict` use `repr`).
pub fn py_display_opt(v: Option<&Value>) -> String {
    match v {
        None | Some(Value::Null) => "None".to_string(),
        Some(Value::String(s)) => s.clone(),
        Some(other) => py_repr(other),
    }
}

/// TAP version 13 test result accumulator matching the Python `TestContext` class.
pub struct TapContext {
    pub tests_run: usize,
    pub tests_passed: usize,
    pub failures: Vec<(String, String)>,
    pub output: String,
}

impl Default for TapContext {
    fn default() -> Self {
        Self::new()
    }
}

impl TapContext {
    pub fn new() -> Self {
        Self {
            tests_run: 0,
            tests_passed: 0,
            failures: Vec::new(),
            output: String::new(),
        }
    }

    pub fn println(&mut self, line: &str) {
        self.output.push_str(line);
        self.output.push('\n');
    }

    pub fn report_ok(&mut self, description: &str) {
        self.tests_run += 1;
        self.tests_passed += 1;
        self.println(&format!("ok {} - {}", self.tests_run, description));
    }

    pub fn report_fail(&mut self, description: &str, error_detail: &str) {
        self.tests_run += 1;
        self.failures
            .push((description.to_string(), error_detail.to_string()));
        self.println(&format!("not ok {} - {}", self.tests_run, description));
        self.println("  ---");
        self.println(&format!("  message: {}", error_detail));
        self.println("  ...");
    }

    pub fn report_skip(&mut self, description: &str, reason: &str) {
        self.tests_run += 1;
        self.tests_passed += 1;
        self.println(&format!(
            "ok {} - {} # SKIP {}",
            self.tests_run, description, reason
        ));
    }

    pub fn finish(&mut self, tier_num: usize, suite_title: &str) -> i32 {
        self.println(&format!(
            "# Tier {} Results: {}/{} tests passed",
            tier_num, self.tests_passed, self.tests_run
        ));
        if !self.failures.is_empty() {
            self.println(&format!("# FAILED {} test(s)", self.failures.len()));
            let failures = self.failures.clone();
            for (desc, err) in failures {
                self.println(&format!("# - {}: {}", desc, err));
            }
            return 1;
        }
        self.println(&format!("# {}: ALL TESTS PASSED", suite_title));
        0
    }
}

/// Helper to check whether `v` is a JSON integer (and not a boolean).
pub fn as_json_i64(v: Option<&Value>) -> Option<i64> {
    match v {
        Some(Value::Number(n)) => n.as_i64(),
        _ => None,
    }
}

/// Helper to load a JSON file preserving error semantics.
pub fn load_json_file(path: &Path) -> Result<Value, String> {
    let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
    serde_json::from_str(&raw).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_py_repr_formats_primitives_and_collections() {
        assert_eq!(py_repr(&Value::Null), "None");
        assert_eq!(py_repr(&Value::Bool(true)), "True");
        assert_eq!(py_repr(&Value::Bool(false)), "False");
        assert_eq!(py_repr(&json!(42)), "42");
        assert_eq!(
            py_repr(&json!(["kubernetes", "k3s-lab"])),
            "['kubernetes', 'k3s-lab']"
        );
    }

    #[test]
    fn test_collect_all_panels_flattens_row_panels() {
        let dash = json!({
            "panels": [
                {"id": 1, "type": "stat"},
                {
                    "id": 2,
                    "type": "row",
                    "panels": [
                        {"id": 3, "type": "timeseries"},
                        {"id": 4, "type": "table"}
                    ]
                }
            ]
        });
        let all = collect_all_panels(&dash);
        assert_eq!(all.len(), 4);
    }
}
