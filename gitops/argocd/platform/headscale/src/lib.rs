// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Headscale must use database policy mode when Headplane runs in API-only mode.
//!
//! Headplane (`configmap-headplane.yaml`) connects to Headscale via its gRPC/REST API
//! without a shared policy file on disk. Headscale defaults to `policy.mode=file` with
//! an empty `policy.path` (`""`), which causes `/admin/acls` in Headplane and
//! `headscale policy get` to fail with:
//!   `reading policy from path "": open : no such file or directory`

pub mod yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/headscale";

/// Load all non-null YAML documents from `filename` in `gitops/argocd/platform/headscale`.
pub fn load_docs(filename: &str) -> Vec<Value> {
    let path = yaml::resolve_data_path(PKG_DIR, filename);
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    yaml::parse_all(&raw).unwrap_or_else(|e| panic!("failed to parse {}: {e}", path.display()))
}

pub fn single_doc_of_kind<'a>(docs: &'a [Value], kind: &str) -> &'a Value {
    let matches: Vec<&Value> = docs
        .iter()
        .filter(|d| d.get("kind").and_then(Value::as_str) == Some(kind))
        .collect();
    assert_eq!(
        matches.len(),
        1,
        "expected exactly 1 {kind} document, found {}",
        matches.len()
    );
    matches[0]
}

/// Load the parsed Helm values from `applicationset.yaml`.
pub fn load_headscale_values() -> Value {
    let docs = load_docs("applicationset.yaml");
    let appset = single_doc_of_kind(&docs, "ApplicationSet");
    let raw_values = appset
        .pointer("/spec/template/spec/source/helm/values")
        .and_then(Value::as_str)
        .expect("missing spec.template.spec.source.helm.values");
    yaml::parse_doc(raw_values).expect("failed to parse Headscale Helm values")
}

/// Load the parsed Headplane config from `configmap-headplane.yaml`.
pub fn load_headplane_config() -> Value {
    let docs = load_docs("configmap-headplane.yaml");
    let cm = single_doc_of_kind(&docs, "ConfigMap");
    let raw_cfg = cm
        .pointer("/data/config.yaml")
        .and_then(Value::as_str)
        .expect("missing data['config.yaml'] in configmap-headplane.yaml");
    yaml::parse_doc(raw_cfg).expect("failed to parse Headplane config.yaml")
}

/// Validate that `HEADSCALE_POLICY_MODE=database` when Headplane has no `headscale.config_path`.
pub fn check_policy_mode(hp_cfg: &Value, hs_values: &Value) -> Result<(), String> {
    let has_config_path = hp_cfg
        .pointer("/headscale/config_path")
        .and_then(Value::as_str)
        .is_some_and(|s| !s.is_empty());
    if !has_config_path {
        let mode = hs_values
            .pointer("/env/HEADSCALE_POLICY_MODE")
            .and_then(Value::as_str);
        if mode != Some("database") {
            return Err(
                "Headplane in API-only mode requires HEADSCALE_POLICY_MODE=database \
                 so /admin/acls can read and update ACL policies via Headscale's API."
                    .to_string(),
            );
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_policy_mode_is_database_when_headplane_has_no_config_path() {
        let hp = load_headplane_config();
        let hs = load_headscale_values();
        check_policy_mode(&hp, &hs).unwrap();
    }

    #[test]
    fn test_backend_traffic_policy_permits_tailscale_control_protocol() {
        let docs = load_docs("backendtrafficpolicy.yaml");
        let btp = single_doc_of_kind(&docs, "BackendTrafficPolicy");
        let target_names: Vec<&str> = btp
            .pointer("/spec/targetRefs")
            .and_then(Value::as_array)
            .expect("missing spec.targetRefs")
            .iter()
            .filter_map(|t| t.get("name").and_then(Value::as_str))
            .collect();
        assert!(target_names.contains(&"headscale"));

        let upgrade_types: Vec<&str> = btp
            .pointer("/spec/httpUpgrade")
            .and_then(Value::as_array)
            .expect("missing spec.httpUpgrade")
            .iter()
            .filter_map(|u| u.get("type").and_then(Value::as_str))
            .collect();
        assert!(
            upgrade_types.contains(&"tailscale-control-protocol"),
            "Envoy Gateway must allow Upgrade: tailscale-control-protocol for Headscale TS2021."
        );
    }

    #[test]
    fn test_headscale_dns_is_not_cloudflare_proxied() {
        let docs = load_docs("dnsendpoint.yaml");
        let dns = single_doc_of_kind(&docs, "DNSEndpoint");
        let endpoints = dns
            .pointer("/spec/endpoints")
            .and_then(Value::as_array)
            .expect("missing spec.endpoints");
        let hs_ep = endpoints
            .iter()
            .find(|ep| ep.get("dnsName").and_then(Value::as_str) == Some("headscale.ipv1337.dev"))
            .expect("missing endpoint headscale.ipv1337.dev");

        assert_eq!(
            hs_ep.get("recordType").and_then(Value::as_str),
            Some("A"),
            "headscale.ipv1337.dev must be a direct A record (not a Cloudflare Tunnel CNAME) \
             because Cloudflare Edge strips Upgrade headers on HTTP POST /ts2021."
        );

        let mut proxied_props: HashMap<&str, &str> = HashMap::new();
        if let Some(arr) = hs_ep.get("providerSpecific").and_then(Value::as_array) {
            for p in arr {
                if let (Some(n), Some(v)) = (
                    p.get("name").and_then(Value::as_str),
                    p.get("value").and_then(Value::as_str),
                ) {
                    proxied_props.insert(n, v);
                }
            }
        }
        assert_eq!(
            proxied_props
                .get("external-dns.alpha.kubernetes.io/cloudflare-proxied")
                .copied(),
            Some("false"),
            "headscale.ipv1337.dev must have cloudflare-proxied=false so Cloudflare Edge \
             does not strip TS2021 POST Upgrade headers."
        );
    }

    #[test]
    fn test_headscale_tls_certificate_and_reference_grant_exist() {
        let docs = load_docs("certificate.yaml");
        let cert = single_doc_of_kind(&docs, "Certificate");
        assert_eq!(
            cert.pointer("/spec/secretName").and_then(Value::as_str),
            Some("headscale-tls")
        );
        let dns_names: Vec<&str> = cert
            .pointer("/spec/dnsNames")
            .and_then(Value::as_array)
            .expect("missing spec.dnsNames")
            .iter()
            .filter_map(Value::as_str)
            .collect();
        assert!(dns_names.contains(&"headscale.ipv1337.dev"));

        let rg = single_doc_of_kind(&docs, "ReferenceGrant");
        let to_names: Vec<&str> = rg
            .pointer("/spec/to")
            .and_then(Value::as_array)
            .expect("missing spec.to")
            .iter()
            .filter_map(|t| t.get("name").and_then(Value::as_str))
            .collect();
        assert!(to_names.contains(&"headscale-tls"));
    }

    #[test]
    fn test_edge_tunnel_and_subnet_router_deployments_exist() {
        let tunnel_docs = load_docs("deployment-edge-tunnel.yaml");
        let tunnel = single_doc_of_kind(&tunnel_docs, "Deployment");
        assert_eq!(
            tunnel.pointer("/metadata/name").and_then(Value::as_str),
            Some("headscale-edge-tunnel")
        );

        let router_docs = load_docs("deployment-subnet-router.yaml");
        let router = single_doc_of_kind(&router_docs, "Deployment");
        assert_eq!(
            router.pointer("/metadata/name").and_then(Value::as_str),
            Some("headscale-subnet-router")
        );

        let mut env: HashMap<&str, Option<&str>> = HashMap::new();
        for e in router
            .pointer("/spec/template/spec/containers/0/env")
            .and_then(Value::as_array)
            .expect("missing container env")
        {
            if let Some(name) = e.get("name").and_then(Value::as_str) {
                env.insert(name, e.get("value").and_then(Value::as_str));
            }
        }
        assert_eq!(env.get("TS_USERSPACE").copied().flatten(), Some("true"));
        assert_eq!(
            env.get("TS_KUBE_SECRET").copied().flatten(),
            Some(""),
            "TS_KUBE_SECRET must be empty so containerboot uses TS_STATE_DIR instead of Kubernetes Secret RBAC."
        );
        assert_eq!(
            env.get("KUBERNETES_SERVICE_HOST").copied().flatten(),
            Some(""),
            "KUBERNETES_SERVICE_HOST must be empty so containerboot does not attempt in-cluster Kubernetes client setup."
        );
        assert_eq!(
            router
                .pointer("/spec/template/spec/automountServiceAccountToken")
                .and_then(Value::as_bool)
                .unwrap_or(true),
            false,
            "automountServiceAccountToken must be false so containerboot does not switch to Kubernetes state storage."
        );
        let extra_args = env.get("TS_EXTRA_ARGS").copied().flatten().unwrap_or("");
        assert!(extra_args.contains("--advertise-routes=192.168.86.0/24,10.44.86.0/24"));
        assert_eq!(
            router
                .pointer("/spec/template/spec/hostNetwork")
                .and_then(Value::as_bool),
            Some(true),
            "headscale-subnet-router must use hostNetwork=true on a wired control-plane node."
        );
        assert_eq!(
            router
                .pointer("/spec/template/spec/nodeSelector/node.ipv1337.dev~1link")
                .and_then(Value::as_str),
            Some("wired"),
            "headscale-subnet-router must be pinned to wired control-plane nodes."
        );
        assert_eq!(
            router
                .pointer("/spec/template/spec/nodeSelector/node-role.kubernetes.io~1control-plane")
                .and_then(Value::as_str),
            Some("true"),
            "headscale-subnet-router must be pinned to control-plane nodes."
        );

        let agent_docs = load_docs("daemonset-node-agent.yaml");
        let agent = single_doc_of_kind(&agent_docs, "DaemonSet");
        assert_eq!(
            agent.pointer("/metadata/name").and_then(Value::as_str),
            Some("headscale-node-agent")
        );
        assert_eq!(
            agent
                .pointer("/spec/template/spec/hostNetwork")
                .and_then(Value::as_bool),
            Some(true),
            "headscale-node-agent must use hostNetwork=true so userspace netstack 127.0.0.1 dials reach host sshd (:22) and k3s (:6443)."
        );
    }

    #[test]
    fn test_headscale_image_matches_headplane_schema_version() {
        let hs_vals = load_headscale_values();
        assert_eq!(
            hs_vals.pointer("/image/tag").and_then(Value::as_str),
            Some("v0.26.1"),
            "Headplane 0.6.x requires Headscale v0.26.1 so /api/v1/node includes route arrays."
        );
        let init_cmd = hs_vals
            .pointer("/initContainers/config/command")
            .and_then(Value::as_array)
            .map(|arr| {
                arr.iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join("\n")
            })
            .unwrap_or_default();
        assert!(
            init_cmd.contains("k8s-api.lab.ipv1337.dev"),
            "Headscale config must include extra_records for k8s-api.lab.ipv1337.dev so Headscale clients do not dial commercial Tailscale 100.x IPs."
        );
    }

    #[test]
    fn test_rejects_missing_database_policy_mode_in_api_only_mode() {
        let hp = yaml::parse_doc("headscale:\n  url: http://headscale:8080\n").unwrap();
        let hs = yaml::parse_doc("env:\n  HEADSCALE_POLICY_MODE: file\n").unwrap();
        assert!(check_policy_mode(&hp, &hs).is_err());
    }
}
