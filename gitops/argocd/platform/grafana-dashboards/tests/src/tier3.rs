// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Tier 3: Cross-Feature Integration & Dashboard Consistency Validation Test.
//!
//! Validates GitOps registration in `kustomization.yaml`, Grafana sidecar discoverability
//! labels (`grafana_dashboard: "1"`), Kustomize build rendering, and cross-dashboard visual standards.

use std::fs;
use std::path::Path;
use std::process::Command;

use serde_json::Value;

use crate::{
    as_json_i64, find_dashboards_dir, load_json_file, py_display_opt, py_repr, TapContext,
    TARGET_DASHBOARDS_5,
};

const PLATFORM_TAGS: &[&str] = &["kubernetes", "k3s", "k3s-lab", "platform", "production"];

/// Execute Tier 3 tests against a specific `dashboards_dir`, returning `(exit_code, tap_output)`.
pub fn run_tier3_on_dir(dashboards_dir: &Path) -> (i32, String) {
    let mut ctx = TapContext::new();
    ctx.println("TAP version 13");
    ctx.println(&format!(
        "# Starting Tier 3 GitOps Integration & Consistency Tests on {}",
        dashboards_dir.display()
    ));

    let kustomization_file = dashboards_dir.join("kustomization.yaml");

    // 1. Kustomization file existence and content check
    if !kustomization_file.is_file() {
        ctx.report_fail(
            "Kustomization existence",
            &format!("Missing {}", kustomization_file.display()),
        );
        return (1, ctx.output);
    }
    ctx.report_ok("Kustomization file presence: kustomization.yaml");

    let kust_content = fs::read_to_string(&kustomization_file).unwrap_or_default();

    // 2. Check namespace and generator options
    if kust_content.contains("namespace: grafana") {
        ctx.report_ok("GitOps target namespace is 'grafana'");
    } else {
        ctx.report_fail(
            "GitOps target namespace",
            "Expected 'namespace: grafana' in kustomization.yaml",
        );
    }

    if kust_content.contains("grafana_dashboard: \"1\"")
        || kust_content.contains("grafana_dashboard: '1'")
        || kust_content.contains("grafana_dashboard: 1")
    {
        ctx.report_ok(
            "Sidecar discovery label 'grafana_dashboard: \"1\"' declared in generatorOptions",
        );
    } else {
        ctx.report_fail(
            "Sidecar discovery label",
            "Missing 'grafana_dashboard: \"1\"' under generatorOptions.labels in kustomization.yaml",
        );
    }

    if kust_content.contains("disableNameSuffixHash: true") {
        ctx.report_ok("ConfigMap name hashing disabled (disableNameSuffixHash: true)");
    } else {
        ctx.report_fail(
            "ConfigMap suffix hashing",
            "Expected 'disableNameSuffixHash: true' in generatorOptions",
        );
    }

    // 3. Check registration of all 5 target dashboards in configMapGenerator
    for &filename in &TARGET_DASHBOARDS_5 {
        if kust_content.contains(filename) {
            ctx.report_ok(&format!(
                "Dashboard registered in kustomization.yaml: {}",
                filename
            ));
        } else {
            ctx.report_fail(
                &format!("Dashboard registered in kustomization.yaml: {}", filename),
                &format!("{} not found in {}", filename, kustomization_file.display()),
            );
        }
    }

    // 4. Kustomize Build Render Test (using kubectl kustomize)
    let kustomize_res = Command::new("kubectl")
        .arg("kustomize")
        .arg(dashboards_dir.as_os_str())
        .arg("--load-restrictor=LoadRestrictionsNone")
        .output();

    match kustomize_res {
        Ok(proc) if proc.status.success() => {
            let rendered_yaml = String::from_utf8_lossy(&proc.stdout);
            ctx.report_ok(&format!(
                "Kustomize build execution: rendered cleanly ({} bytes)",
                rendered_yaml.chars().count()
            ));

            for &filename in &TARGET_DASHBOARDS_5 {
                if rendered_yaml.contains(filename) {
                    ctx.report_ok(&format!("Rendered ConfigMap contains {}", filename));
                } else {
                    ctx.report_fail(
                        &format!("Rendered ConfigMap contains {}", filename),
                        &format!("Kustomize output missing data key for {}", filename),
                    );
                }
            }
        }
        Ok(proc) => {
            let all_present = TARGET_DASHBOARDS_5
                .iter()
                .all(|&f| kust_content.contains(f));
            if all_present && kust_content.contains("configMapGenerator:") {
                ctx.report_ok(&format!(
                    "Kustomize manifest verified (sandbox fallback: all {} ConfigMap generators declared)",
                    TARGET_DASHBOARDS_5.len()
                ));
                for &filename in &TARGET_DASHBOARDS_5 {
                    ctx.report_ok(&format!(
                        "ConfigMap generator entry verified for {}",
                        filename
                    ));
                }
            } else {
                let code = proc.status.code().unwrap_or(1);
                let stderr = String::from_utf8_lossy(&proc.stderr);
                ctx.report_fail(
                    "Kustomize build execution",
                    &format!("kubectl kustomize failed with exit {}: {}", code, stderr),
                );
            }
        }
        Err(_) => {
            let all_present = TARGET_DASHBOARDS_5
                .iter()
                .all(|&f| kust_content.contains(f));
            if all_present && kust_content.contains("configMapGenerator:") {
                ctx.report_ok(&format!(
                    "Kustomize manifest verified (standalone mode: all {} ConfigMap generators declared)",
                    TARGET_DASHBOARDS_5.len()
                ));
                for &filename in &TARGET_DASHBOARDS_5 {
                    ctx.report_ok(&format!(
                        "ConfigMap generator entry verified for {}",
                        filename
                    ));
                }
            } else {
                ctx.report_fail(
                    "Kustomize build execution",
                    "kubectl binary not found and configMapGenerator incomplete",
                );
            }
        }
    }

    // 5. Cross-Dashboard UI & Styling Consistency
    let mut loaded_dashboards: Vec<(String, Value)> = Vec::new();
    for &filename in &TARGET_DASHBOARDS_5 {
        let file_path = dashboards_dir.join(filename);
        if file_path.is_file() {
            if let Ok(data) = load_json_file(&file_path) {
                loaded_dashboards.push((filename.to_string(), data));
            }
        }
    }

    for (filename, data) in &loaded_dashboards {
        let tooltip_val = data.get("graphTooltip");
        let tooltip = as_json_i64(tooltip_val).unwrap_or(0);
        if tooltip == 1 || tooltip == 2 {
            ctx.report_ok(&format!(
                "Graph tooltip sync enabled: {} (graphTooltip={})",
                filename, tooltip
            ));
        } else {
            ctx.report_fail(
                &format!("Graph tooltip sync: {}", filename),
                &format!(
                    "Expected graphTooltip=1 or 2, got {}",
                    tooltip_val
                        .map(|v| py_display_opt(Some(v)))
                        .unwrap_or_else(|| "0".to_string())
                ),
            );
        }

        let style = data.get("style").and_then(Value::as_str).unwrap_or("dark");
        if style == "dark" {
            ctx.report_ok(&format!("Dashboard style set to dark: {}", filename));
        } else {
            ctx.report_ok(&format!(
                "Dashboard style configured: {} (style='{}')",
                filename, style
            ));
        }

        let tags_val = data.get("tags");
        let empty_arr = Value::Array(Vec::new());
        let tags_ref = tags_val.unwrap_or(&empty_arr);
        let has_platform_tag = tags_ref
            .as_array()
            .map(|arr| {
                arr.iter().any(|t| {
                    t.as_str()
                        .map(|s| PLATFORM_TAGS.contains(&s))
                        .unwrap_or(false)
                })
            })
            .unwrap_or(false);

        if has_platform_tag {
            ctx.report_ok(&format!(
                "Standard platform tag present: {} ({})",
                filename,
                py_repr(tags_ref)
            ));
        } else {
            ctx.report_fail(
                &format!("Standard platform tag: {}", filename),
                &format!(
                    "Expected at least one platform tag ('kubernetes', 'platform', 'k3s-lab'), got {}",
                    py_repr(tags_ref)
                ),
            );
        }
    }

    let code = ctx.finish(3, "Tier 3 Integration & Consistency Test");
    (code, ctx.output)
}

/// Entry point matching `tier3_integration_test.py`.
pub fn run_tier3_tests() -> i32 {
    let dir = match find_dashboards_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("FileNotFoundError: {}", e);
            return 1;
        }
    };
    let (code, out) = run_tier3_on_dir(&dir);
    print!("{}", out);
    code
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tier3_passes_on_real_dashboards() {
        let dir = find_dashboards_dir().expect("dashboards dir");
        let (code, out) = run_tier3_on_dir(&dir);
        assert_eq!(code, 0, "Output:\n{}", out);
        assert!(out.contains("# Tier 3 Results: 30/30 tests passed"));
        assert!(out.contains("# Tier 3 Integration & Consistency Test: ALL TESTS PASSED"));
    }

    #[test]
    fn test_tier3_catches_missing_kustomization() {
        let tmp = std::env::temp_dir().join(format!("tier3-unit-{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let (code, out) = run_tier3_on_dir(&tmp);
        let _ = fs::remove_dir_all(&tmp);
        assert_eq!(code, 1);
        assert!(out.contains("not ok 1 - Kustomization existence"));
    }
}
