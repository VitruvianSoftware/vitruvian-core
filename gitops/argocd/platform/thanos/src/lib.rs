// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Thanos components must have sufficient memory headroom to avoid OOM kills.
//!
//! The Querier merges series and dedupes across sidecars and storegateways,
//! the StoreGateway caches block indexes, and the Compactor processes blocks.
//! Limits below 2Gi cause flapping and OOM kills under load.

pub mod yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/thanos";

/// The Querier's samples cap. The Prometheus sidecar cap must stay above it,
/// and `../prometheus/prometheus_values_test` repeats this number to check
/// that. Change both together.
pub const QUERY_SAMPLES_CAP: i64 = 12_000_000;

/// Load the parsed Helm values from `applicationset.yaml`.
pub fn load_values() -> Value {
    let path = yaml::resolve_data_path(PKG_DIR, "applicationset.yaml");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    load_values_from_str(&raw).expect("failed to parse Thanos ApplicationSet Helm values")
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
    yaml::parse_doc(raw_values)
}

/// Extract the integer value of the single `--name=value` entry in `args`.
pub fn flag_value(args: &[String], name: &str) -> Result<i64, String> {
    let prefix = format!("{name}=");
    let values: Vec<&str> = args
        .iter()
        .filter_map(|a| a.strip_prefix(&prefix))
        .collect();
    if values.len() != 1 {
        return Err(format!("expected exactly one {name}=..., found {values:?}"));
    }
    values[0]
        .parse::<i64>()
        .map_err(|e| format!("failed to parse {name} value {:?}: {e}", values[0]))
}

pub fn extra_args(v: &Value, component: &str) -> Vec<String> {
    v.pointer(&format!("/{component}/extraArgs"))
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect()
        })
        .unwrap_or_default()
}

pub fn memory_limit<'a>(v: &'a Value, component: &str) -> Option<&'a str> {
    v.pointer(&format!("/{component}/resources/limits/memory"))
        .and_then(Value::as_str)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_query_memory_limit() {
        let v = load_values();
        assert_eq!(memory_limit(&v, "query"), Some("2Gi"));
    }

    #[test]
    fn test_storegateway_memory_limit() {
        let v = load_values();
        assert_eq!(memory_limit(&v, "storegateway"), Some("2Gi"));
    }

    #[test]
    fn test_compactor_memory_limit() {
        let v = load_values();
        assert_eq!(memory_limit(&v, "compactor"), Some("2Gi"));
    }

    #[test]
    fn test_query_has_guardrails_and_keeps_log_level() {
        let v = load_values();
        let args = extra_args(&v, "query");
        assert!(args.iter().any(|a| a == "--enable-auto-gomemlimit"));
        assert!(flag_value(&args, "--store.limits.request-series").unwrap() > 0);
        assert!(flag_value(&args, "--store.limits.request-samples").unwrap() > 0);
        assert!(flag_value(&args, "--query.max-concurrent").unwrap() > 0);
        assert!(args.iter().any(|a| a == "--log.level=info"));
    }

    #[test]
    fn test_query_checks_the_caps_while_reading() {
        let v = load_values();
        let args = extra_args(&v, "query");
        assert!(args.iter().any(|a| a == "--grpc.proxy-strategy=lazy"));
    }

    #[test]
    fn test_query_samples_cap_is_the_one_the_sidecar_test_assumes() {
        let v = load_values();
        let args = extra_args(&v, "query");
        assert_eq!(
            flag_value(&args, "--store.limits.request-samples").unwrap(),
            QUERY_SAMPLES_CAP
        );
    }

    #[test]
    fn test_query_refuses_before_a_store_truncates() {
        let v = load_values();
        let query = flag_value(&extra_args(&v, "query"), "--store.limits.request-series").unwrap();
        let store = flag_value(
            &extra_args(&v, "storegateway"),
            "--store.limits.request-series",
        )
        .unwrap();
        assert!(query < store, "expected query ({query}) < store ({store})");
    }

    #[test]
    fn test_query_series_cap_is_below_the_select_that_killed_it() {
        let v = load_values();
        let cap = flag_value(&extra_args(&v, "query"), "--store.limits.request-series").unwrap();
        assert!(cap < 86_000, "expected query series cap {cap} < 86_000");
    }

    #[test]
    fn test_storegateway_has_series_cap_and_memory_guard() {
        let v = load_values();
        let args = extra_args(&v, "storegateway");
        assert!(args
            .iter()
            .any(|a| a == "--store.limits.request-series=150000"));
        assert!(args.iter().any(|a| a == "--enable-auto-gomemlimit"));
    }

    #[test]
    fn test_flag_value_rejects_missing_or_duplicate_flags() {
        let empty: Vec<String> = vec![];
        assert!(flag_value(&empty, "--store.limits.request-series").is_err());
        let dup = vec![
            "--store.limits.request-series=100".to_string(),
            "--store.limits.request-series=200".to_string(),
        ];
        assert!(flag_value(&dup, "--store.limits.request-series").is_err());
    }
}
