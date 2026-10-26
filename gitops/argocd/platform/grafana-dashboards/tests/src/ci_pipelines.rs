// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! CI pipelines dashboard validator (`ci_pipelines_test.py` port).
//!
//! Ensures `ci-pipelines.json` excludes `cicd-telemetry smoke.*` runs from every query and
//! template variable, uses `max_over_time` instead of `rate()`/`increase()` on sparse CI
//! counters, avoids filtering job/step/queue spans by `$workflow`, groups run p95 histograms
//! by `cicd_pipeline_name`, and keeps the 5% experiment failure-rate threshold line.

use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::{find_dashboards_dir, load_json_file, py_repr};

pub const EXCLUDE: &str = "cicd_pipeline_name!~\"cicd-telemetry smoke.*\"";

/// Locate `ci-pipelines.json` across runfiles or workspace directories.
pub fn find_ci_pipelines_file() -> Result<PathBuf, String> {
    if let Ok(dir) = find_dashboards_dir() {
        let candidate = dir.join("ci-pipelines.json");
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    Err("FileNotFoundError: ci-pipelines.json".to_string())
}

/// Top-level panels plus those nested inside collapsed rows (`p.get("panels", [])`).
pub fn all_panels(d: &Value) -> Vec<&Value> {
    let mut out = Vec::new();
    if let Some(panels) = d.get("panels").and_then(Value::as_array) {
        for p in panels {
            out.push(p);
            if let Some(nested) = p.get("panels").and_then(Value::as_array) {
                for sub in nested {
                    out.push(sub);
                }
            }
        }
    }
    out
}

/// Match `re.search(r"sum by \([^)]*cicd_pipeline_name", e)`.
fn has_sum_by_cicd_pipeline_name(e: &str) -> bool {
    let needle = "sum by (";
    let mut idx = 0;
    while let Some(rel) = e[idx..].find(needle) {
        let start = idx + rel + needle.len();
        let rest = &e[start..];
        let close_pos = rest.find(')').unwrap_or(rest.len());
        if rest[..close_pos].contains("cicd_pipeline_name") {
            return true;
        }
        idx = start;
    }
    false
}

fn title_repr(p: &Value) -> String {
    match p.get("title") {
        Some(v) => py_repr(v),
        None => "None".to_string(),
    }
}

/// Validate a parsed `ci-pipelines.json` value, returning `(exit_code, formatted_output)`.
pub fn check_ci_pipelines_dashboard(d: &Value) -> (i32, String) {
    let panels = all_panels(d);
    let mut failures: Vec<String> = Vec::new();

    for p in &panels {
        if let Some(targets) = p.get("targets").and_then(Value::as_array) {
            for t in targets {
                if let Some(expr) = t.get("expr").and_then(Value::as_str) {
                    if !expr.contains(EXCLUDE) {
                        let ref_id = t.get("refId").and_then(Value::as_str).unwrap_or("");
                        failures.push(format!(
                            "smoke runs not excluded: panel {} ({})",
                            title_repr(p),
                            ref_id
                        ));
                    }
                }
            }
        }
    }

    for p in &panels {
        let title_str = p.get("title").and_then(Value::as_str).unwrap_or("");
        if let Some(targets) = p.get("targets").and_then(Value::as_array) {
            for t in targets {
                let e = t.get("expr").and_then(Value::as_str).unwrap_or("");
                if e.contains("cicd_") && (e.contains("rate(") || e.contains("increase(")) {
                    failures.push(format!("panel {} uses rate()/increase()", title_repr(p)));
                }
                if e.contains("cicd_") && !e.contains("max_over_time(") {
                    failures.push(format!(
                        "panel {} drops restarted pods' counts",
                        title_repr(p)
                    ));
                }
                if e.contains("$workflow")
                    && (e.contains("ci_span_type=\"job\"")
                        || e.contains("ci_span_type=\"queue\"")
                        || e.contains("ci_span_type=\"step\""))
                {
                    failures.push(format!(
                        "panel {} filters job/step spans by workflow",
                        title_repr(p)
                    ));
                }
                if e.contains("histogram_quantile(")
                    && e.contains("ci_span_type=\"run\"")
                    && !has_sum_by_cicd_pipeline_name(e)
                {
                    failures.push(format!(
                        "panel {} pools every workflow into one p95",
                        title_repr(p)
                    ));
                }
                if title_str.starts_with("Failure rate")
                    && !e.contains("STATUS_CODE_OK|STATUS_CODE_ERROR")
                {
                    failures.push(
                        "failure rate denominator includes skipped/cancelled runs".to_string(),
                    );
                }
            }
        }
    }

    for p in &panels {
        let title_str = p.get("title").and_then(Value::as_str).unwrap_or("");
        if title_str.starts_with("Failure rate per stage") {
            let steps = p
                .get("fieldConfig")
                .and_then(|fc| fc.get("defaults"))
                .and_then(|def| def.get("thresholds"))
                .and_then(|th| th.get("steps"))
                .and_then(Value::as_array);
            let has_005 = steps
                .map(|arr| {
                    arr.iter().any(|s| {
                        s.get("value")
                            .and_then(Value::as_f64)
                            .map(|v| (v - 0.05).abs() < 1e-12)
                            .unwrap_or(false)
                    })
                })
                .unwrap_or(false);
            if !has_005 {
                failures.push("experiment failure rate has no 5% stop-rule line".to_string());
            }
        }
    }

    if let Some(list) = d
        .get("templating")
        .and_then(|t| t.get("list"))
        .and_then(Value::as_array)
    {
        for v in list {
            let q = match v.get("query") {
                Some(Value::Object(obj)) => obj.get("query").and_then(Value::as_str).unwrap_or(""),
                Some(Value::String(s)) => s.as_str(),
                _ => "",
            };
            if v.get("name").and_then(Value::as_str) == Some("workflow") && !q.contains(EXCLUDE) {
                failures.push("smoke runs not excluded: variable 'workflow'".to_string());
            }
        }
    }

    let mut out = String::new();
    for f in &failures {
        out.push_str(&format!("FAIL  {}\n", f));
    }
    let verdict = if failures.is_empty() { "PASS" } else { "FAIL" };
    out.push_str(&format!(
        "{}  ci-pipelines checks ({} problems)\n",
        verdict,
        failures.len()
    ));
    let code = if failures.is_empty() { 0 } else { 1 };
    (code, out)
}

/// Validate a `ci-pipelines.json` file at `path`.
pub fn run_ci_pipelines_on_file(path: &Path) -> (i32, String) {
    match load_json_file(path) {
        Ok(d) => check_ci_pipelines_dashboard(&d),
        Err(e) => (1, format!("FAIL  {}\n", e)),
    }
}

/// Entry point matching `ci_pipelines_test.py`.
pub fn run_ci_pipelines_test() -> i32 {
    let path = match find_ci_pipelines_file() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{}", e);
            return 1;
        }
    };
    let (code, out) = run_ci_pipelines_on_file(&path);
    print!("{}", out);
    code
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_ci_pipelines_passes_on_real_dashboard() {
        let path = find_ci_pipelines_file().expect("ci-pipelines.json");
        let (code, out) = run_ci_pipelines_on_file(&path);
        assert_eq!(code, 0, "Output:\n{}", out);
        assert_eq!(out, "PASS  ci-pipelines checks (0 problems)\n");
    }

    #[test]
    fn test_ci_pipelines_catches_all_failure_modes() {
        let broken = json!({
            "panels": [
                {
                    "title": "Failure rate per stage",
                    "fieldConfig": {"defaults": {"thresholds": {"steps": [{"value": 0.1}]}}},
                    "targets": [
                        {
                            "refId": "A",
                            "expr": "rate(cicd_pipeline_run_count{ci_span_type=\"job\", workflow=\"$workflow\"}[5m])"
                        },
                        {
                            "refId": "B",
                            "expr": "histogram_quantile(0.95, sum by (le) (max_over_time(cicd_System{ci_span_type=\"run\", cicd_pipeline_name!~\"cicd-telemetry smoke.*\"}[5m])))"
                        }
                    ]
                }
            ],
            "templating": {
                "list": [
                    {"name": "workflow", "query": "label_values(cicd_pipeline_name)"}
                ]
            }
        });

        let (code, out) = check_ci_pipelines_dashboard(&broken);
        assert_eq!(code, 1);
        assert!(out.contains("FAIL  smoke runs not excluded: panel 'Failure rate per stage' (A)"));
        assert!(out.contains("FAIL  panel 'Failure rate per stage' uses rate()/increase()"));
        assert!(out.contains("FAIL  panel 'Failure rate per stage' drops restarted pods' counts"));
        assert!(
            out.contains("FAIL  panel 'Failure rate per stage' filters job/step spans by workflow")
        );
        assert!(
            out.contains("FAIL  panel 'Failure rate per stage' pools every workflow into one p95")
        );
        assert!(out.contains("FAIL  failure rate denominator includes skipped/cancelled runs"));
        assert!(out.contains("FAIL  experiment failure rate has no 5% stop-rule line"));
        assert!(out.contains("FAIL  smoke runs not excluded: variable 'workflow'"));
    }
}
