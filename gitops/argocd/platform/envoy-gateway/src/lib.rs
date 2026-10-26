// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! EnvoyProxy StrategicMerge Service patch invariant tests (`envoyproxy_test.py` port).
//!
//! Kubernetes `ServiceSpec.ports` declares `port` (not `name`) as its strategic merge
//! patch key. Omitting `port` causes Envoy Gateway's infrastructure runner to fail
//! Service reconciliation.

pub mod yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/envoy-gateway";

/// Validate that every `EnvoyProxy` with a `StrategicMerge` Service patch includes
/// `port` on every port item.
pub fn validate_envoyproxy_docs(docs: &[Value]) -> Result<(), String> {
    let ep_docs: Vec<&Value> = docs
        .iter()
        .filter(|d| d.get("kind").and_then(Value::as_str) == Some("EnvoyProxy"))
        .collect();
    if ep_docs.len() != 1 {
        return Err(format!(
            "expected exactly 1 EnvoyProxy document, found {}",
            ep_docs.len()
        ));
    }
    let ep = ep_docs[0];
    let svc = ep
        .get("spec")
        .and_then(|s| s.get("provider"))
        .and_then(|p| p.get("kubernetes"))
        .and_then(|k| k.get("envoyService"))
        .ok_or_else(|| "missing spec.provider.kubernetes.envoyService".to_string())?;

    if let Some(patch) = svc.get("patch").and_then(Value::as_object) {
        if patch.get("type").and_then(Value::as_str) == Some("StrategicMerge") {
            let ports = patch
                .get("value")
                .and_then(|v| v.get("spec"))
                .and_then(|s| s.get("ports"))
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            for p in &ports {
                let has_port = p
                    .as_object()
                    .and_then(|obj| obj.get("port"))
                    .map_or(false, |v| !v.is_null());
                if !has_port {
                    return Err(format!(
                        "Port patch entry {p} must define 'port' (the Kubernetes ServiceSpec.ports strategic merge key)."
                    ));
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
    fn test_strategic_merge_service_ports_define_port_merge_key() {
        let path = yaml::resolve_data_path(PKG_DIR, "gateway/envoyproxy.yaml");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
        let docs = yaml::parse_all(&raw).expect("valid YAML in gateway/envoyproxy.yaml");
        validate_envoyproxy_docs(&docs).expect("envoyproxy.yaml passes StrategicMerge port check");
    }

    #[test]
    fn test_synthetic_valid_envoyproxy_passes() {
        let src = r#"
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: platform
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: LoadBalancer
        patch:
          type: StrategicMerge
          value:
            spec:
              ports:
                - name: http-80
                  port: 80
                  nodePort: 30265
                - name: https-443
                  port: 443
                  targetPort: 10443
"#;
        let docs = yaml::parse_all(src).unwrap();
        assert!(validate_envoyproxy_docs(&docs).is_ok());
    }

    #[test]
    fn test_synthetic_missing_port_merge_key_fails() {
        let src = r#"
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: platform
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        patch:
          type: StrategicMerge
          value:
            spec:
              ports:
                - name: http-80
                  nodePort: 30265
"#;
        let docs = yaml::parse_all(src).unwrap();
        let err = validate_envoyproxy_docs(&docs).unwrap_err();
        assert!(
            err.contains("must define 'port'"),
            "unexpected error: {err}"
        );
    }
}
