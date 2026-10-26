// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Tempo must not split traces across replicas, or lose them on a restart.
//!
//! Tempo here is the single-binary chart. Its pods do not share a ring (no
//! memberlist peers), so with 2 replicas each write landed on one pod and each
//! search saw only one pod's recent data: 18/50 lookups via the Service found a
//! trace sent seconds earlier (measured 2026-09-29). And the WAL lived in the
//! container's scratch layer, so a restart lost every unflushed trace.

pub mod yaml;

use serde_json::Value;
use std::collections::{HashMap, HashSet};

pub const PKG_DIR: &str = "gitops/argocd/platform/tempo";

/// Load the parsed Helm values from `applicationset.yaml`.
pub fn load_values() -> Value {
    let path = yaml::resolve_data_path(PKG_DIR, "applicationset.yaml");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    load_values_from_str(&raw).expect("failed to parse Tempo ApplicationSet Helm values")
}

/// Parse the `ApplicationSet` document and its `spec.template.spec.source.helm.values` YAML string.
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

/// Check that replicas == 1 unless `tempo.memberlist.join_members` is non-empty.
pub fn check_single_replica_unless_pods_share_a_ring(v: &Value) -> Result<(), String> {
    let joined_non_empty = v
        .pointer("/tempo/memberlist/join_members")
        .map(|jm| match jm {
            Value::Null => false,
            Value::Bool(b) => *b,
            Value::Array(a) => !a.is_empty(),
            Value::String(s) => !s.is_empty(),
            Value::Object(o) => !o.is_empty(),
            Value::Number(_) => true,
        })
        .unwrap_or(false);
    if !joined_non_empty {
        let replicas = v.get("replicas").and_then(Value::as_i64).unwrap_or(1);
        if replicas != 1 {
            return Err(format!(
                "expected replicas == 1 when memberlist.join_members is unset, got {replicas}"
            ));
        }
    }
    Ok(())
}

/// Check that `tempo.ingester.flush_all_on_shutdown` is `true`.
pub fn check_flushes_to_backend_on_shutdown(v: &Value) -> Result<(), String> {
    let flush = v
        .pointer("/tempo/ingester/flush_all_on_shutdown")
        .and_then(Value::as_bool);
    if flush != Some(true) {
        return Err(format!(
            "expected tempo.ingester.flush_all_on_shutdown == true, got {flush:?}"
        ));
    }
    Ok(())
}

/// Check that `/var/tempo` is mounted in `tempo.extraVolumeMounts` and backed by `extraVolumes`.
pub fn check_wal_is_on_a_volume(v: &Value) -> Result<(), String> {
    let mut mounts: HashMap<String, String> = HashMap::new();
    if let Some(arr) = v
        .pointer("/tempo/extraVolumeMounts")
        .and_then(Value::as_array)
    {
        for m in arr {
            if let (Some(mp), Some(name)) = (
                m.get("mountPath").and_then(Value::as_str),
                m.get("name").and_then(Value::as_str),
            ) {
                mounts.insert(mp.to_string(), name.to_string());
            }
        }
    }
    let Some(wal_vol) = mounts.get("/var/tempo") else {
        return Err("expected '/var/tempo' in tempo.extraVolumeMounts".to_string());
    };
    let vols: HashSet<&str> = v
        .get("extraVolumes")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(|vol| vol.get("name").and_then(Value::as_str))
                .collect()
        })
        .unwrap_or_default();
    if !vols.contains(wal_vol.as_str()) {
        return Err(format!(
            "volume {wal_vol:?} for /var/tempo not found in extraVolumes: {vols:?}"
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_replica_unless_pods_share_a_ring() {
        let v = load_values();
        check_single_replica_unless_pods_share_a_ring(&v).unwrap();
    }

    #[test]
    fn test_flushes_to_backend_on_shutdown() {
        let v = load_values();
        check_flushes_to_backend_on_shutdown(&v).unwrap();
    }

    #[test]
    fn test_wal_is_on_a_volume() {
        let v = load_values();
        check_wal_is_on_a_volume(&v).unwrap();
    }

    #[test]
    fn test_rejects_multi_replica_without_ring() {
        let v = yaml::parse_doc(
            r#"
replicas: 2
tempo:
  ingester:
    flush_all_on_shutdown: true
"#,
        )
        .unwrap();
        let err = check_single_replica_unless_pods_share_a_ring(&v).unwrap_err();
        assert!(
            err.contains("expected replicas == 1"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn test_rejects_missing_flush_or_wal_volume() {
        let v = yaml::parse_doc(
            r#"
replicas: 1
tempo:
  ingester:
    flush_all_on_shutdown: false
  extraVolumeMounts:
    - name: wal
      mountPath: /var/tempo
extraVolumes: []
"#,
        )
        .unwrap();
        assert!(check_flushes_to_backend_on_shutdown(&v).is_err());
        assert!(check_wal_is_on_a_volume(&v).is_err());
    }
}
