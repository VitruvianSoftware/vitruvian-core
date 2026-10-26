// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Prometheus Thanos sidecar must have sufficient memory headroom to avoid OOM kills,
//! and alerting/recording/scrape rules must preserve cluster invariants.

pub mod yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/prometheus";

/// 12,000,000 is the Querier's `--store.limits.request-samples`, set in
/// `../thanos/applicationset.yaml` and pinned as `QUERY_SAMPLES_CAP` in
/// `../thanos/thanos_values_test`. Change all three together.
pub const QUERIER_SAMPLES_CAP: i64 = 12_000_000;

/// Load the parsed Helm values from `applicationset.yaml` (stripping Go raw string template delimiters).
pub fn load_values() -> Value {
    let path = yaml::resolve_data_path(PKG_DIR, "applicationset.yaml");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    load_values_from_str(&raw).expect("failed to parse Prometheus ApplicationSet Helm values")
}

/// Parse `ApplicationSet` and its `spec.template.spec.source.helm.values`.
pub fn load_values_from_str(appset_yaml: &str) -> Result<Value, String> {
    let docs = yaml::parse_all(appset_yaml)?;
    let appsets: Vec<&Value> = docs
        .iter()
        .filter(|d| d.get("kind").and_then(Value::as_str) == Some("ApplicationSet"))
        .collect();
    if appsets.len() != 1 {
        return Err(format!(
            "expected exactly 1 ApplicationSet document, found {}",
            appsets.len()
        ));
    }
    let raw_values = appsets[0]
        .pointer("/spec/template/spec/source/helm/values")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing spec.template.spec.source.helm.values string".to_string())?;
    let cleaned = raw_values.replace("{{`", "").replace("`}}", "");
    yaml::parse_doc(&cleaned)
}

pub fn resource_job(v: &Value) -> Value {
    let raw = v
        .get("extraScrapeConfigs")
        .and_then(Value::as_str)
        .expect("missing extraScrapeConfigs string");
    let jobs = yaml::parse_doc(raw).expect("failed to parse extraScrapeConfigs YAML");
    let arr = jobs
        .as_array()
        .expect("expected extraScrapeConfigs to be a YAML list");
    let matches: Vec<&Value> = arr
        .iter()
        .filter(|j| j.get("job_name").and_then(Value::as_str) == Some("kubernetes-nodes-resource"))
        .collect();
    assert_eq!(
        matches.len(),
        1,
        "expected exactly 1 kubernetes-nodes-resource job"
    );
    matches[0].clone()
}

/// Evaluate a Prometheus anchored regex (`fullmatch`) supporting `.`, `.*`, `.+`, and literals.
pub fn prometheus_regex_fullmatch(pattern: &str, text: &str) -> bool {
    let p_chars: Vec<char> = pattern
        .strip_prefix('^')
        .unwrap_or(pattern)
        .strip_suffix('$')
        .unwrap_or(pattern)
        .chars()
        .collect();
    let t_chars: Vec<char> = text.chars().collect();
    match_here(&p_chars, 0, &t_chars, 0)
}

fn match_here(p: &[char], pi: usize, t: &[char], ti: usize) -> bool {
    if pi == p.len() {
        return ti == t.len();
    }
    if pi + 1 < p.len() && (p[pi + 1] == '*' || p[pi + 1] == '+') {
        let quant = p[pi + 1];
        let mut cur_t = if quant == '+' {
            if ti < t.len() && char_matches(p[pi], t[ti]) {
                ti + 1
            } else {
                return false;
            }
        } else {
            ti
        };
        let mut positions = vec![cur_t];
        while cur_t < t.len() && char_matches(p[pi], t[cur_t]) {
            cur_t += 1;
            positions.push(cur_t);
        }
        for &pos in positions.iter().rev() {
            if match_here(p, pi + 2, t, pos) {
                return true;
            }
        }
        return false;
    }
    if ti < t.len() && char_matches(p[pi], t[ti]) {
        return match_here(p, pi + 1, t, ti + 1);
    }
    false
}

fn char_matches(pat: char, ch: char) -> bool {
    pat == '.' || pat == ch
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::{HashMap, HashSet};

    #[test]
    fn test_thanos_sidecar_memory_limit() {
        let v = load_values();
        let lim = v
            .pointer("/server/sidecarContainers/thanos-sidecar/resources/limits/memory")
            .and_then(Value::as_str);
        assert_eq!(lim, Some("2Gi"));
    }

    #[test]
    fn test_thanos_sidecar_has_series_cap() {
        let v = load_values();
        let args = v
            .pointer("/server/sidecarContainers/thanos-sidecar/args")
            .and_then(Value::as_array)
            .expect("missing sidecar args");
        assert!(args
            .iter()
            .any(|a| a.as_str() == Some("--store.limits.request-series=150000")));
    }

    #[test]
    fn test_thanos_sidecar_samples_cap_is_above_the_querier_cap() {
        let v = load_values();
        let args = v
            .pointer("/server/sidecarContainers/thanos-sidecar/args")
            .and_then(Value::as_array)
            .expect("missing sidecar args");
        let prefix = "--store.limits.request-samples=";
        let values: Vec<&str> = args
            .iter()
            .filter_map(Value::as_str)
            .filter_map(|a| a.strip_prefix(prefix))
            .collect();
        assert_eq!(values.len(), 1, "unexpected values: {values:?}");
        let cap: i64 = values[0].parse().expect("invalid samples cap integer");
        assert!(cap > QUERIER_SAMPLES_CAP);
    }

    #[test]
    fn test_thanos_sidecar_has_memory_guard() {
        let v = load_values();
        let args = v
            .pointer("/server/sidecarContainers/thanos-sidecar/args")
            .and_then(Value::as_array)
            .expect("missing sidecar args");
        assert!(args
            .iter()
            .any(|a| a.as_str() == Some("--enable-auto-gomemlimit")));
    }

    fn oom_alert_rule(v: &Value) -> Value {
        let groups = v
            .pointer("/serverFiles/alerting_rules.yml/groups")
            .and_then(Value::as_array)
            .expect("missing alerting_rules.yml groups");
        let rules: Vec<&Value> = groups
            .iter()
            .filter_map(|g| g.get("rules").and_then(Value::as_array))
            .flatten()
            .filter(|r| {
                r.get("alert").and_then(Value::as_str) == Some("KubeContainerOOMKilledRepeatedly")
            })
            .collect();
        assert_eq!(
            rules.len(),
            1,
            "expected exactly 1 KubeContainerOOMKilledRepeatedly rule"
        );
        rules[0].clone()
    }

    #[test]
    fn test_repeated_oom_kill_alert_exists() {
        let v = load_values();
        let rule = oom_alert_rule(&v);
        let expr = rule.get("expr").and_then(Value::as_str).unwrap_or("");
        assert!(expr.contains(r#"reason="OOMKilled""#));
        assert_eq!(
            rule.pointer("/labels/severity").and_then(Value::as_str),
            Some("warning")
        );
    }

    #[test]
    fn test_repeated_oom_kill_alert_clears_once_container_is_stable() {
        let v = load_values();
        let rule = oom_alert_rule(&v);
        let raw_expr = rule.get("expr").and_then(Value::as_str).unwrap_or("");
        let expr = raw_expr.split_whitespace().collect::<Vec<_>>().join(" ");
        assert!(expr.contains("kube_pod_container_state_started"));
        assert!(expr.contains("time() - kube_pod_container_state_started < 30 * 60"));
        assert!(expr.contains("kube_pod_container_status_restarts_total[6h]"));
    }

    #[test]
    fn test_resource_job_scrapes_only_docker_nodes() {
        let v = load_values();
        let job = resource_job(&v);
        assert_eq!(
            job.get("kubernetes_sd_configs"),
            Some(&json!([{"role": "node"}]))
        );
        let first = job
            .pointer("/relabel_configs/0")
            .expect("missing first relabel_config");
        assert_eq!(first.get("action").and_then(Value::as_str), Some("keep"));
        assert_eq!(
            first.get("source_labels"),
            Some(&json!([
                "__meta_kubernetes_node_annotation_k3s_io_node_args"
            ]))
        );
        let regex = first
            .get("regex")
            .and_then(Value::as_str)
            .expect("missing regex");
        let docker = r#"["agent","--node-name","james-mbp","--docker"]"#;
        let containerd = r#"["server","--tls-san","k8s-api.lab.ipv1337.dev"]"#;
        assert!(prometheus_regex_fullmatch(regex, docker));
        assert!(!prometheus_regex_fullmatch(regex, containerd));
        assert!(!prometheus_regex_fullmatch(regex, ""));
    }

    #[test]
    fn test_resource_job_goes_through_the_api_server_proxy() {
        let v = load_values();
        let job = resource_job(&v);
        assert_eq!(job.get("scheme").and_then(Value::as_str), Some("https"));
        let mut by_target: HashMap<&str, &Value> = HashMap::new();
        for r in job
            .get("relabel_configs")
            .and_then(Value::as_array)
            .expect("missing relabel_configs")
        {
            if let Some(tl) = r.get("target_label").and_then(Value::as_str) {
                by_target.insert(tl, r);
            }
        }
        assert_eq!(
            by_target["__address__"]
                .get("replacement")
                .and_then(Value::as_str),
            Some("kubernetes.default.svc:443")
        );
        assert_eq!(
            by_target["__metrics_path__"]
                .get("replacement")
                .and_then(Value::as_str),
            Some("/api/v1/nodes/$1/proxy/metrics/resource")
        );
    }

    #[test]
    fn test_resource_job_keeps_only_container_cpu_and_memory() {
        let v = load_values();
        let job = resource_job(&v);
        let rules = job
            .get("metric_relabel_configs")
            .and_then(Value::as_array)
            .expect("missing metric_relabel_configs");
        assert_eq!(rules.len(), 1);
        let rule = &rules[0];
        assert_eq!(rule.get("action").and_then(Value::as_str), Some("keep"));
        assert_eq!(rule.get("source_labels"), Some(&json!(["__name__"])));
        let actual: HashSet<&str> = rule
            .get("regex")
            .and_then(Value::as_str)
            .expect("missing regex")
            .split('|')
            .collect();
        let expected: HashSet<&str> = [
            "container_cpu_usage_seconds_total",
            "container_memory_working_set_bytes",
        ]
        .into_iter()
        .collect();
        assert_eq!(actual, expected);
    }

    #[test]
    fn test_extra_scrape_configs_survive_helm_tpl() {
        let v = load_values();
        let raw = v
            .get("extraScrapeConfigs")
            .and_then(Value::as_str)
            .expect("missing extraScrapeConfigs");
        assert!(!raw.contains("{{"));
    }

    #[test]
    fn test_app_cpu_graphs_do_not_filter_on_image() {
        let v = load_values();
        let groups = v
            .pointer("/serverFiles/recording_rules.yml/groups")
            .and_then(Value::as_array)
            .expect("missing recording_rules.yml groups");
        let bg_groups: Vec<&Value> = groups
            .iter()
            .filter(|g| g.get("name").and_then(Value::as_str) == Some("backstage-graphs"))
            .collect();
        assert_eq!(bg_groups.len(), 1);
        let rules: Vec<&Value> = bg_groups[0]
            .get("rules")
            .and_then(Value::as_array)
            .expect("missing rules")
            .iter()
            .filter(|r| {
                r.get("record").and_then(Value::as_str).is_some_and(|rec| {
                    rec.ends_with(":cpu_cores") || rec.ends_with(":memory_bytes")
                })
            })
            .collect();
        let apps: HashSet<&str> = rules
            .iter()
            .filter_map(|r| r.get("record").and_then(Value::as_str))
            .map(|rec| rec.split(':').next().unwrap_or(rec))
            .collect();
        let expected_apps: HashSet<&str> =
            ["backstage", "buzz", "mcp_slack", "storybook", "whoami"]
                .into_iter()
                .collect();
        assert_eq!(apps, expected_apps);
        assert_eq!(rules.len(), 10);
        for r in rules {
            let rec = r.get("record").and_then(Value::as_str).unwrap_or("");
            let expr = r.get("expr").and_then(Value::as_str).unwrap_or("");
            assert!(!expr.contains("image"), "rule {rec} filters on image");
            assert!(
                !expr.contains("node_namespace_pod_container"),
                "rule {rec} references node_namespace_pod_container"
            );
        }
    }
}
