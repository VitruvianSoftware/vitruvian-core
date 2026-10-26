// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Tier 4: Live Prometheus / Thanos Querier Telemetry Execution Test.
//!
//! Executes PromQL queries from all 5 Grafana dashboards against the live Thanos Querier
//! in the k3s cluster, verifying metric resolution, query syntax execution, and active telemetry population.

use std::env;
use std::path::Path;
use std::process::Command;

use serde_json::{json, Value};

use crate::{
    as_json_i64, collect_all_panels, find_dashboards_dir, load_json_file, TapContext,
    TARGET_DASHBOARDS_5,
};

pub const CORE_ACTIVE_QUERIES: &[(&str, &[(&str, &str)])] = &[
    (
        "argocd.json",
        &[
            (
                "count(argocd_app_info)",
                "ArgoCD Application Inventory (52 expected)",
            ),
            (
                "sum by (sync_status) (argocd_app_info)",
                "ArgoCD Application Sync Statuses",
            ),
            (
                "sum(rate(argocd_git_request_total[5m]))",
                "ArgoCD Git Repo Server Requests",
            ),
        ],
    ),
    (
        "envoy-gateway.json",
        &[
            (
                "sum(rate(envoy_http_downstream_rq_total[5m]))",
                "Envoy Gateway Ingress Throughput",
            ),
            (
                "sum(envoy_http_downstream_cx_active)",
                "Envoy Gateway Active Downstream Connections",
            ),
            (
                "sum by (envoy_cluster_name) (rate(envoy_cluster_upstream_rq_total[5m]))",
                "Envoy Upstream HTTPRoute Traffic",
            ),
        ],
    ),
    (
        "identity-mesh.json",
        &[
            ("headscale_machines_connected_total", "Headscale Online Nodes"),
            ("headscale_machines_total", "Headscale Total Registered Devices"),
            (
                "sum(kube_deployment_status_replicas_available{namespace=\"zitadel\"})",
                "Zitadel HA Replicas Availability",
            ),
        ],
    ),
    (
        "data-platform-dr.json",
        &[
            (
                "count(cnpg_pg_replication_in_recovery)",
                "CloudNativePG Database Instances",
            ),
            (
                "sum by (namespace) (cnpg_backends_total)",
                "Active PostgreSQL Database Backends",
            ),
            (
                "minio_cluster_capacity_usable_total_bytes",
                "MinIO Storage Cluster Usable Capacity",
            ),
        ],
    ),
    (
        "agent-integrations.json",
        &[
            (
                "sum(antigravity_active_session_count) or vector(0)",
                "AI Assistant Active Sessions",
            ),
            (
                "sum(buzz_community_ws_connections) or vector(0)",
                "Buzz Real-Time Relay WebSocket Connections",
            ),
            (
                "sum(rate(envoy_cluster_upstream_rq_total{envoy_cluster_name=~\"httproute/mcp-slack/.*\"}[5m])) or vector(0)",
                "MCP Slack Bridge Ingress Traffic",
            ),
        ],
    ),
];

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// Find valid kubeconfig path matching `find_kubeconfig()` in `tier4_telemetry_test.py`.
pub fn find_kubeconfig() -> Option<String> {
    if let Ok(kc) = env::var("KUBECONFIG") {
        if !kc.is_empty() && Path::new(&kc).is_file() {
            return Some(kc);
        }
    }
    if let Ok(home) = env::var("HOME") {
        for rel in [".kube/cluster.yaml", ".kube/config"] {
            let p = Path::new(&home).join(rel);
            if p.is_file() {
                return Some(p.to_string_lossy().into_owned());
            }
        }
    }
    None
}

/// Parse a `$var` or `${var}` token at the start of `s`, returning the byte length consumed.
fn match_var_token(s: &str) -> Option<usize> {
    let bytes = s.as_bytes();
    if bytes.first() != Some(&b'$') {
        return None;
    }
    if bytes.get(1) == Some(&b'{') {
        let mut end = 2;
        while end < bytes.len() && is_ident_char(bytes[end] as char) {
            end += 1;
        }
        if end > 2 && bytes.get(end) == Some(&b'}') {
            return Some(end + 1);
        }
        None
    } else {
        let mut end = 1;
        while end < bytes.len() && is_ident_char(bytes[end] as char) {
            end += 1;
        }
        if end > 1 {
            Some(end)
        } else {
            None
        }
    }
}

/// Substitute Grafana template and built-in variables with test evaluation values,
/// matching `sanitize_promql_for_execution(expr)` in `tier4_telemetry_test.py`.
pub fn sanitize_promql_for_execution(expr: &str) -> String {
    // 1. Replace interval/range variables in brackets: `\[\s*\$?[{]?[a-zA-Z0-9_]+[}]?\s*\]` -> `[5m]`
    let mut s1 = String::with_capacity(expr.len());
    let mut i = 0;
    while i < expr.len() {
        let rest = &expr[i..];
        if let Some(after_open) = rest.strip_prefix('[') {
            if let Some(close_idx) = after_open.find(']') {
                let inside = after_open[..close_idx].trim();
                let inside_no_dollar = inside.strip_prefix('$').unwrap_or(inside);
                let inside_no_open = inside_no_dollar
                    .strip_prefix('{')
                    .unwrap_or(inside_no_dollar);
                let core = inside_no_open.strip_suffix('}').unwrap_or(inside_no_open);
                if !core.is_empty() && core.chars().all(is_ident_char) {
                    s1.push_str("[5m]");
                    i += 1 + close_idx + 1;
                    continue;
                }
            }
        }
        let ch = rest.chars().next().unwrap();
        s1.push(ch);
        i += ch.len_utf8();
    }

    // 2 & 3. Replace label filter variables: `(=~|!=|!~|=)\s*"?(\$var|\${var})"?` -> `\1".*"`
    let mut s2 = String::with_capacity(s1.len());
    let mut j = 0;
    while j < s1.len() {
        let rest = &s1[j..];
        let op = if rest.starts_with("=~") {
            Some("=~")
        } else if rest.starts_with("!=") {
            Some("!=")
        } else if rest.starts_with("!~") {
            Some("!~")
        } else if rest.starts_with('=') {
            Some("=")
        } else {
            None
        };

        if let Some(op_str) = op {
            let after_op = &rest[op_str.len()..];
            let trimmed = after_op.trim_start();
            let ws_len = after_op.len() - trimmed.len();
            // Quoted form: `"$var"` or `"${var}"`
            if let Some(after_q) = trimmed.strip_prefix('"') {
                if let Some(vlen) = match_var_token(after_q) {
                    if after_q[vlen..].starts_with('"') {
                        s2.push_str(op_str);
                        s2.push_str("\".*\"");
                        j += op_str.len() + ws_len + 1 + vlen + 1;
                        continue;
                    }
                }
            }
            // Unquoted form: `$var` or `${var}`
            if let Some(vlen) = match_var_token(trimmed) {
                s2.push_str(op_str);
                s2.push_str("\".*\"");
                j += op_str.len() + ws_len + vlen;
                continue;
            }
        }

        let ch = rest.chars().next().unwrap();
        s2.push(ch);
        j += ch.len_utf8();
    }

    // 4. Replace datasource
    let s3 = s2
        .replace("$datasource", "Prometheus-Data")
        .replace("${datasource}", "Prometheus-Data");

    // 5. Replace remaining variable expressions `(\$[a-zA-Z0-9_]+|\${[a-zA-Z0-9_]+})` -> `.*`
    let mut s4 = String::with_capacity(s3.len());
    let mut k = 0;
    while k < s3.len() {
        let rest = &s3[k..];
        if let Some(vlen) = match_var_token(rest) {
            s4.push_str(".*");
            k += vlen;
            continue;
        }
        let ch = rest.chars().next().unwrap();
        s4.push(ch);
        k += ch.len_utf8();
    }

    s4.trim().to_string()
}

/// URL-encode query string matching Python's `urllib.parse.quote(s)`.
pub fn urllib_quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 2);
    for &b in s.as_bytes() {
        let safe = b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b'-' | b'~' | b'/');
        if safe {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

pub struct ThanosQuerier {
    pub kubeconfig: Option<String>,
    pub available: bool,
}

impl ThanosQuerier {
    pub fn new(kubeconfig: Option<String>) -> Self {
        let kc = kubeconfig.or_else(find_kubeconfig);
        let mut q = Self {
            kubeconfig: kc,
            available: false,
        };
        q.check_connectivity();
        q
    }

    fn check_connectivity(&mut self) {
        if env::var("TIER4_FORCE_OFFLINE").ok().as_deref() == Some("1") {
            self.available = false;
            return;
        }
        let kc = match &self.kubeconfig {
            Some(k) => k,
            None => return,
        };
        let out = Command::new("kubectl")
            .arg(format!("--kubeconfig={}", kc))
            .args([
                "get",
                "pods",
                "-n",
                "monitoring",
                "-l",
                "app.kubernetes.io/component=query",
                "-o",
                "name",
            ])
            .output();
        if let Ok(proc) = out {
            let stdout = String::from_utf8_lossy(&proc.stdout);
            if proc.status.success() && stdout.contains("thanos-query") {
                self.available = true;
            }
        }
    }

    pub fn query(&self, promql_expr: &str) -> (bool, Value, String) {
        if !self.available {
            return (
                false,
                Value::Null,
                "Thanos Querier is not reachable or kubeconfig not available".to_string(),
            );
        }

        let clean_expr = sanitize_promql_for_execution(promql_expr);
        if clean_expr.starts_with("{resource.") || clean_expr.starts_with("traceql") {
            return (true, json!({"result": []}), String::new());
        }

        let encoded_query = urllib_quote(&clean_expr);
        let kc = self.kubeconfig.as_deref().unwrap_or("");
        let out = Command::new("kubectl")
            .arg(format!("--kubeconfig={}", kc))
            .args([
                "exec",
                "-n",
                "monitoring",
                "deploy/thanos-query",
                "-c",
                "query",
                "--",
                "wget",
                "-qO-",
                &format!("http://localhost:9090/api/v1/query?query={}", encoded_query),
            ])
            .output();

        match out {
            Ok(proc) => {
                let stdout = String::from_utf8_lossy(&proc.stdout);
                let stderr = String::from_utf8_lossy(&proc.stderr);
                if !proc.status.success() {
                    let code = proc.status.code().unwrap_or(1);
                    let detail = if !stderr.trim().is_empty() {
                        stderr.trim()
                    } else {
                        stdout.trim()
                    };
                    return (
                        false,
                        Value::Null,
                        format!("Command failed (exit {}): {}", code, detail),
                    );
                }
                match serde_json::from_str::<Value>(&stdout) {
                    Ok(resp) => {
                        if resp.get("status").and_then(Value::as_str) == Some("success") {
                            let data = resp.get("data").cloned().unwrap_or_else(|| json!({}));
                            (true, data, String::new())
                        } else {
                            let err_msg = resp
                                .get("error")
                                .and_then(Value::as_str)
                                .unwrap_or("unknown error");
                            (
                                false,
                                resp.clone(),
                                format!("Prometheus API error: {}", err_msg),
                            )
                        }
                    }
                    Err(_) => {
                        let preview: String = stdout.chars().take(200).collect();
                        (
                            false,
                            Value::Null,
                            format!("Invalid JSON response from Thanos: {}", preview),
                        )
                    }
                }
            }
            Err(e) => (false, Value::Null, e.to_string()),
        }
    }
}

/// Execute Tier 4 tests against a specific `dashboards_dir`, returning `(exit_code, tap_output)`.
pub fn run_tier4_on_dir(dashboards_dir: &Path, allow_offline: bool) -> (i32, String) {
    let mut ctx = TapContext::new();
    let querier = ThanosQuerier::new(None);

    ctx.println("TAP version 13");
    ctx.println("# Starting Tier 4 Live Telemetry Execution Tests against Thanos Querier");

    let mut loaded_dashboards: Vec<(String, Value)> = Vec::new();
    for &filename in &TARGET_DASHBOARDS_5 {
        let file_path = dashboards_dir.join(filename);
        if file_path.is_file() {
            if let Ok(data) = load_json_file(&file_path) {
                loaded_dashboards.push((filename.to_string(), data));
            }
        }
    }

    if !querier.available {
        if allow_offline {
            ctx.println(
                "# Thanos Querier cluster endpoint unreachable in offline mode. Skipping live query execution.",
            );
            ctx.report_skip(
                "Cluster Thanos Querier connectivity",
                "Offline mode enabled",
            );
            return (0, ctx.output);
        } else {
            let kc_disp = querier.kubeconfig.as_deref().unwrap_or("None");
            ctx.report_fail(
                "Cluster Thanos Querier connectivity",
                &format!(
                    "Thanos Querier in namespace 'monitoring' unreachable. Kubeconfig: {}",
                    kc_disp
                ),
            );
            return (1, ctx.output);
        }
    }

    ctx.report_ok(
        "Cluster Thanos Querier connectivity verified (namespace: monitoring, pod: thanos-query)",
    );

    // 1. Execute Core Telemetry Queries for Active Cluster Services
    for &(filename, queries) in CORE_ACTIVE_QUERIES {
        for &(expr, label) in queries {
            let (success, data, err) = querier.query(expr);
            if !success {
                ctx.report_fail(
                    &format!("Core Telemetry: {} - {} (`{}`)", filename, label, expr),
                    &err,
                );
            } else {
                let results = data
                    .get("result")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                if !results.is_empty() {
                    let sample_val = results[0]
                        .get("value")
                        .and_then(Value::as_array)
                        .and_then(|arr| arr.get(1))
                        .map(|v| match v {
                            Value::String(s) => s.clone(),
                            other => other.to_string(),
                        })
                        .unwrap_or_else(|| "?".to_string());
                    ctx.report_ok(&format!(
                        "Core Telemetry: {} - {} (`{}`) -> {} series (sample: {})",
                        filename,
                        label,
                        expr,
                        results.len(),
                        sample_val
                    ));
                } else {
                    ctx.report_ok(&format!(
                        "Core Telemetry: {} - {} (`{}`) -> executed cleanly (0 series currently active)",
                        filename, label, expr
                    ));
                }
            }
        }
    }

    // 2. Execute All Panel Queries from Loaded Dashboards
    for (filename, data) in &loaded_dashboards {
        let panels = collect_all_panels(data);
        let mut tested_queries = 0usize;
        let mut failed_queries: Vec<String> = Vec::new();

        for p in panels {
            let pid = as_json_i64(p.get("id")).unwrap_or(0);
            let default_title = format!("Panel {}", pid);
            let title = p
                .get("title")
                .and_then(Value::as_str)
                .unwrap_or(&default_title);
            if let Some(targets) = p.get("targets").and_then(Value::as_array) {
                for (t_idx, t) in targets.iter().enumerate() {
                    let expr = t.get("expr").and_then(Value::as_str).unwrap_or("").trim();
                    if expr.is_empty() {
                        continue;
                    }
                    tested_queries += 1;
                    let (success, _, err) = querier.query(expr);
                    if !success {
                        failed_queries.push(format!(
                            "Panel {} ('{}') target #{} (`{}`): {}",
                            pid, title, t_idx, expr, err
                        ));
                    }
                }
            }
        }

        if !failed_queries.is_empty() {
            let first3: Vec<&str> = failed_queries.iter().take(3).map(String::as_str).collect();
            ctx.report_fail(
                &format!(
                    "Live PromQL panel query execution: {} ({} queries)",
                    filename, tested_queries
                ),
                &first3.join("; "),
            );
        } else {
            ctx.report_ok(&format!(
                "Live PromQL panel query execution: {} (all {} panel queries executed cleanly)",
                filename, tested_queries
            ));
        }
    }

    let code = ctx.finish(4, "Tier 4 Live Telemetry Query Test");
    (code, ctx.output)
}

/// Entry point matching `tier4_telemetry_test.py`.
pub fn run_tier4_tests(allow_offline: bool) -> i32 {
    let dir = match find_dashboards_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("FileNotFoundError: {}", e);
            return 1;
        }
    };
    let (code, out) = run_tier4_on_dir(&dir, allow_offline);
    print!("{}", out);
    code
}

/// Parse CLI args (`--allow-offline`, `-h`/`--help`) for `tier4_telemetry_test`.
pub fn run_tier4_cli(args: &[String]) -> i32 {
    let mut allow_offline = false;
    for arg in args {
        match arg.as_str() {
            "--allow-offline" => allow_offline = true,
            "-h" | "--help" => {
                println!("usage: tier4_telemetry_test [-h] [--allow-offline]");
                println!();
                println!("Tier 4 Live Telemetry E2E Test");
                println!();
                println!("options:");
                println!("  -h, --help       show this help message and exit");
                println!("  --allow-offline  Skip live tests if cluster is unreachable");
                return 0;
            }
            other => {
                eprintln!(
                    "tier4_telemetry_test: error: unrecognized arguments: {}",
                    other
                );
                return 2;
            }
        }
    }
    run_tier4_tests(allow_offline)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sanitize_promql_for_execution() {
        let raw = r#"sum(rate(envoy_cluster_upstream_rq_total{namespace=~"$namespace", cluster="$cluster"}[$__rate_interval]))"#;
        let sanitized = sanitize_promql_for_execution(raw);
        assert_eq!(
            sanitized,
            r#"sum(rate(envoy_cluster_upstream_rq_total{namespace=~".*", cluster=".*"}[5m]))"#
        );
    }

    #[test]
    fn test_urllib_quote_matches_python() {
        assert_eq!(
            urllib_quote("count(argocd_app_info)"),
            "count%28argocd_app_info%29"
        );
        assert_eq!(
            urllib_quote("httproute/mcp-slack/.*"),
            "httproute/mcp-slack/.%2A"
        );
    }
}
