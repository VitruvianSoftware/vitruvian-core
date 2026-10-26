// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! The main collector's config uses current component names only.
//!
//! otelcol-contrib 0.160 logs these old names as deprecated aliases, and the
//! chart (0.173.1) only rewrites `otlp` for us "for this release". Once either
//! drops the alias, the collector fails to start. Same fix as the CI collector
//! (gitops/argocd/platform/cicd-telemetry, #2571).

pub mod yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/opentelemetry-collector";

/// Old type -> new type (component IDs may carry a `/name` suffix).
pub const DEPRECATED: &[(&str, &str)] = &[
    ("otlp", "otlp_grpc"), // exporter only; the otlp RECEIVER is not renamed
    ("otlphttp", "otlp_http"),
    ("prometheusremotewrite", "prometheus_remote_write"),
    ("spanmetrics", "span_metrics"),
];

pub fn deprecated_replacement(typ: &str) -> Option<&'static str> {
    DEPRECATED
        .iter()
        .find_map(|&(old, new)| (old == typ).then_some(new))
}

/// Load the collector `config` object from `applicationset.yaml`.
pub fn load_config() -> Value {
    let path = yaml::resolve_data_path(PKG_DIR, "applicationset.yaml");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    load_config_from_str(&raw).expect("failed to load OpenTelemetry Collector config")
}

/// Parse `ApplicationSet` from `appset_yaml` and extract `values["config"]`.
pub fn load_config_from_str(appset_yaml: &str) -> Result<Value, String> {
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
    let values = yaml::parse_doc(raw_values)?;
    values
        .get("config")
        .cloned()
        .ok_or_else(|| "missing config section in Helm values".to_string())
}

/// Check that `exporters` and `connectors` only use current component names.
pub fn check_exporters_and_connectors_use_current_names(cfg: &Value) -> Result<(), String> {
    for section in ["exporters", "connectors"] {
        if let Some(obj) = cfg.get(section).and_then(Value::as_object) {
            for cid in obj.keys() {
                let typ = cid.split('/').next().unwrap_or(cid);
                if let Some(replacement) = deprecated_replacement(typ) {
                    return Err(format!("{section}.{cid}: use {replacement}"));
                }
            }
        }
    }
    Ok(())
}

/// Check that `service.pipelines` only reference current component names (allowing `otlp` receiver).
pub fn check_pipelines_reference_current_names(cfg: &Value) -> Result<(), String> {
    let Some(pipelines) = cfg.pointer("/service/pipelines").and_then(Value::as_object) else {
        return Err("missing service.pipelines object".to_string());
    };
    for (name, p) in pipelines {
        for kind in ["exporters", "receivers"] {
            if let Some(arr) = p.get(kind).and_then(Value::as_array) {
                for r in arr {
                    let Some(ref_str) = r.as_str() else {
                        continue;
                    };
                    let typ = ref_str.split('/').next().unwrap_or(ref_str);
                    if kind == "receivers" && typ == "otlp" {
                        continue; // the otlp receiver keeps its name
                    }
                    if deprecated_replacement(typ).is_some() {
                        return Err(format!("pipeline {name} {kind}: {ref_str}"));
                    }
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exporters_and_connectors_use_current_names() {
        let cfg = load_config();
        check_exporters_and_connectors_use_current_names(&cfg).unwrap();
    }

    #[test]
    fn test_pipelines_reference_current_names() {
        let cfg = load_config();
        check_pipelines_reference_current_names(&cfg).unwrap();
    }

    #[test]
    fn test_rejects_deprecated_exporter_and_pipeline_refs() {
        let bad_cfg = yaml::parse_doc(
            r#"
exporters:
  otlphttp/loki:
    endpoint: http://loki:3100/otlp
connectors:
  spanmetrics: {}
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/tempo]
"#,
        )
        .unwrap();
        let err1 = check_exporters_and_connectors_use_current_names(&bad_cfg).unwrap_err();
        assert!(err1.contains("use otlp_http") || err1.contains("use span_metrics"));
        let err2 = check_pipelines_reference_current_names(&bad_cfg).unwrap_err();
        assert!(err2.contains("pipeline traces exporters: otlp/tempo"));
    }
}
