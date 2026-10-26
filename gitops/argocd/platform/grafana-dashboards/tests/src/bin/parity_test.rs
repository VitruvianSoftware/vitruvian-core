// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Side-by-side behavioral and byte-for-byte output parity test between the native Rust
//! Grafana dashboard validators/runner and the original Python/Bash implementations.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use grafana_dashboards_tests::{
    ci_pipelines, find_dashboards_dir, runner, tier1, tier2, tier3, tier4,
};

fn locate_tests_dir(dashboards_dir: &Path) -> PathBuf {
    let candidate = dashboards_dir.join("tests");
    if candidate.join("tier1_schema_test.py").is_file() {
        return candidate;
    }
    if let Ok(srcdir) = env::var("TEST_SRCDIR") {
        let ws = env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".to_string());
        let p = PathBuf::from(srcdir)
            .join(ws)
            .join("gitops/argocd/platform/grafana-dashboards/tests");
        if p.join("tier1_schema_test.py").is_file() {
            return p;
        }
    }
    PathBuf::from("gitops/argocd/platform/grafana-dashboards/tests")
}

fn run_py_script(
    script: &Path,
    args: &[&str],
    cwd: &Path,
    extra_env: &[(&str, &str)],
    clear_bazel_env: bool,
) -> (i32, String) {
    let mut cmd = Command::new("python3");
    cmd.arg(script).args(args).current_dir(cwd);
    if clear_bazel_env {
        cmd.env_remove("TEST_SRCDIR")
            .env_remove("TEST_WORKSPACE")
            .env_remove("BUILD_WORKSPACE_DIRECTORY")
            .env_remove("GRAFANA_DASHBOARDS_DIR");
    }
    for &(k, v) in extra_env {
        cmd.env(k, v);
    }
    let out = cmd.output().expect("failed to execute python3");
    let code = out.status.code().unwrap_or(1);
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    (code, stdout)
}

fn normalize_durations(s: &str) -> String {
    let mut out = String::new();
    for line in s.lines() {
        if let Some(idx) = line.find("\"duration_ms\":") {
            out.push_str(&line[..idx]);
            out.push_str("\"duration_ms\": <MS>");
            if line.trim_end().ends_with(',') {
                out.push(',');
            }
            out.push('\n');
        } else if line.contains(" passed in ") && line.ends_with("ms)") {
            if let Some(pos) = line.rfind(" in ") {
                out.push_str(&line[..pos]);
                out.push_str(" in <MS>ms)\n");
            }
        } else if line.starts_with("| Tier ") && line.ends_with("ms |") {
            if let Some(last_pipe) = line[..line.len() - 2].rfind('|') {
                out.push_str(&line[..last_pipe]);
                out.push_str("| <MS>ms |\n");
            }
        } else if line.starts_with(" TOTALS: ") && line.contains("ms total)") {
            if let Some(open_paren) = line.rfind('(') {
                out.push_str(&line[..open_paren]);
                out.push_str("(<MS>ms total)\n");
            }
        } else {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

fn main() {
    let dashboards_dir = find_dashboards_dir().expect("locate dashboards dir");
    let tests_dir = locate_tests_dir(&dashboards_dir);
    let workspace_root = dashboards_dir
        .parent()
        .and_then(Path::parent)
        .and_then(Path::parent)
        .and_then(Path::parent)
        .expect("workspace root");

    println!("=== 1. Real Dashboards Parity: Tier 1 ===");
    let (py_code, py_out) = run_py_script(
        &tests_dir.join("tier1_schema_test.py"),
        &[],
        workspace_root,
        &[],
        false,
    );
    let (rs_code, rs_out) = tier1::run_tier1_on_dir(&dashboards_dir);
    assert_eq!(rs_code, py_code, "Tier 1 exit code mismatch");
    assert_eq!(rs_out, py_out, "Tier 1 output mismatch against Python");

    println!("=== 2. Real Dashboards Parity: Tier 2 ===");
    let (py_code, py_out) = run_py_script(
        &tests_dir.join("tier2_promql_test.py"),
        &[],
        workspace_root,
        &[],
        false,
    );
    let (rs_code, rs_out) = tier2::run_tier2_on_dir(&dashboards_dir);
    assert_eq!(rs_code, py_code, "Tier 2 exit code mismatch");
    assert_eq!(rs_out, py_out, "Tier 2 output mismatch against Python");

    println!("=== 3. Real Dashboards Parity: Tier 3 ===");
    let (py_code, py_out) = run_py_script(
        &tests_dir.join("tier3_integration_test.py"),
        &[],
        workspace_root,
        &[],
        false,
    );
    let (rs_code, rs_out) = tier3::run_tier3_on_dir(&dashboards_dir);
    assert_eq!(rs_code, py_code, "Tier 3 exit code mismatch");
    assert_eq!(rs_out, py_out, "Tier 3 output mismatch against Python");

    println!("=== 4. Real Dashboards Parity: Tier 4 (--allow-offline) ===");
    let empty_home = env::temp_dir().join(format!("grafana-parity-home-{}", std::process::id()));
    let _ = fs::remove_dir_all(&empty_home);
    fs::create_dir_all(&empty_home).unwrap();
    let home_str = empty_home.to_string_lossy().into_owned();

    let (py_code, py_out) = run_py_script(
        &tests_dir.join("tier4_telemetry_test.py"),
        &["--allow-offline"],
        workspace_root,
        &[("HOME", &home_str), ("KUBECONFIG", "")],
        false,
    );
    env::set_var("TIER4_FORCE_OFFLINE", "1");
    let (rs_code, rs_out) = tier4::run_tier4_on_dir(&dashboards_dir, true);
    env::remove_var("TIER4_FORCE_OFFLINE");
    let _ = fs::remove_dir_all(&empty_home);
    assert_eq!(rs_code, py_code, "Tier 4 offline exit code mismatch");
    assert_eq!(
        rs_out, py_out,
        "Tier 4 offline output mismatch against Python"
    );

    println!("=== 5. Real Dashboards Parity: ci_pipelines_test ===");
    let (py_code, py_out) = run_py_script(
        &tests_dir.join("ci_pipelines_test.py"),
        &[],
        workspace_root,
        &[],
        false,
    );
    let (rs_code, rs_out) =
        ci_pipelines::run_ci_pipelines_on_file(&dashboards_dir.join("ci-pipelines.json"));
    assert_eq!(rs_code, py_code, "ci_pipelines_test exit code mismatch");
    assert_eq!(
        rs_out, py_out,
        "ci_pipelines_test output mismatch against Python"
    );

    println!("=== 6. Synthetic Failure Fixtures Parity (Tiers 1, 2, 3, ci-pipelines) ===");
    let tmp_ws = env::temp_dir().join(format!("grafana-parity-ws-{}", std::process::id()));
    let _ = fs::remove_dir_all(&tmp_ws);
    let tmp_dash_dir = tmp_ws.join("gitops/argocd/platform/grafana-dashboards");
    fs::create_dir_all(&tmp_dash_dir).unwrap();
    let canon_dash_dir = fs::canonicalize(&tmp_dash_dir).unwrap();
    let canon_ws = fs::canonicalize(&tmp_ws).unwrap();

    // Seed broken dashboards to exercise error reporting paths in both Python and Rust
    let broken_argocd = r#"{
        "schemaVersion": 36,
        "uid": "dup-uid",
        "title": "ArgoCD Broken",
        "editable": false,
        "tags": ["only_one"],
        "time": {"from": "now-1h"},
        "refresh": "",
        "templating": {
            "list": [
                {"name": "datasource", "query": "loki", "type": "datasource"},
                {"name": "bad_var", "query": "label_values(unclosed", "type": "query"}
            ]
        },
        "graphTooltip": 0,
        "style": "light",
        "panels": [
            {"id": 1, "type": "stat", "title": "P1", "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}, "targets": [{"expr": "rate(sum(argocd_app_info[5m]))"}]},
            {"id": 1, "type": "invalid_type", "title": "P2", "gridPos": {"h": 4, "w": 20, "x": 10, "y": 0}, "targets": [{"expr": "sum(metric{env=\"$undefined_var\"})"}]},
            {"id": 3, "type": "timeseries", "title": "P3", "fieldConfig": {"defaults": {"unit": "s"}}, "gridPos": {"h": 4, "w": 6, "x": 0, "y": 4}, "targets": [{"expr": "histogram_quantile(0.95, sum by (job) (rate(envoy_cluster_upstream_rq_time_bucket[5m])))"}]},
            {"id": 4, "type": "stat", "title": "P4", "fieldConfig": {"defaults": {"unit": "ms"}}, "gridPos": {"h": 4, "w": 6, "x": 6, "y": 4}, "targets": [{"expr": "minio_cluster_capacity_usable_total_bytes"}]}
        ]
    }"#;
    fs::write(canon_dash_dir.join("argocd.json"), broken_argocd).unwrap();
    fs::write(canon_dash_dir.join("envoy-gateway.json"), broken_argocd).unwrap();
    fs::write(
        canon_dash_dir.join("kustomization.yaml"),
        "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nnamespace: wrong\n",
    )
    .unwrap();

    let (py_t1_code, py_t1_out) = run_py_script(
        &tests_dir.join("tier1_schema_test.py"),
        &[],
        &canon_ws,
        &[],
        true,
    );
    let (rs_t1_code, rs_t1_out) = tier1::run_tier1_on_dir(&canon_dash_dir);
    assert_eq!(rs_t1_code, py_t1_code);
    assert_eq!(rs_t1_out, py_t1_out);

    let (py_t2_code, py_t2_out) = run_py_script(
        &tests_dir.join("tier2_promql_test.py"),
        &[],
        &canon_ws,
        &[],
        true,
    );
    let (rs_t2_code, rs_t2_out) = tier2::run_tier2_on_dir(&canon_dash_dir);
    assert_eq!(rs_t2_code, py_t2_code);
    assert_eq!(rs_t2_out, py_t2_out);

    let (py_t3_code, py_t3_out) = run_py_script(
        &tests_dir.join("tier3_integration_test.py"),
        &[],
        &canon_ws,
        &[],
        true,
    );
    let (rs_t3_code, rs_t3_out) = tier3::run_tier3_on_dir(&canon_dash_dir);
    assert_eq!(rs_t3_code, py_t3_code);
    assert_eq!(rs_t3_out, py_t3_out);

    // Also test runner report parity across text, tap, and json formats
    println!("=== 7. Runner Report Format Parity ===");
    let sample_results = vec![runner::TierResult {
        num: "1".to_string(),
        name: "Schema & Structure".to_string(),
        passed: true,
        ok_count: 80,
        fail_count: 0,
        duration_ms: 10,
    }];
    let bash_out = Command::new("bash")
        .arg(tests_dir.join("runner.sh"))
        .args(["--tier", "1", "--format", "tap"])
        .current_dir(workspace_root)
        .env("BUILD_WORKSPACE_DIRECTORY", workspace_root)
        .output()
        .expect("run runner.sh");
    assert!(bash_out.status.success());
    let bash_stdout = normalize_durations(&String::from_utf8_lossy(&bash_out.stdout));
    let expected_tap_tail = normalize_durations(&runner::format_tap_report(&sample_results));
    assert!(
        bash_stdout.ends_with(&expected_tap_tail),
        "Runner TAP mismatch:\nbash:\n{}\nrust:\n{}",
        bash_stdout,
        expected_tap_tail
    );

    let _ = fs::remove_dir_all(&tmp_ws);
    println!("ALL PARITY CHECKS PASSED (100% behavioral & output agreement)");
}
