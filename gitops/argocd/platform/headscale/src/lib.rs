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

/// Parse `policy.hujson` text as JSON. The file keeps to whole-line `//`
/// comments and no trailing commas, so this needs no HuJSON parser; comment
/// lines are blanked rather than dropped so an error's line number is the
/// file's. Headscale's own check is
/// `bazel run //tools/gitops:headscale-policy-check`.
pub fn parse_policy(raw: &str) -> Result<Value, String> {
    let json: String = raw
        .lines()
        .map(|l| {
            if l.trim_start().starts_with("//") {
                ""
            } else {
                l
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    serde_json::from_str(&json).map_err(|e| {
        format!(
            "policy.hujson line {}: {e} \
             (keep comments on lines of their own, and no trailing commas)",
            e.line()
        )
    })
}

/// Load and parse `policy.hujson`.
pub fn load_policy() -> Value {
    let path = yaml::resolve_data_path(PKG_DIR, "policy.hujson");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    parse_policy(&raw).unwrap_or_else(|e| panic!("{e}"))
}

fn read_root_file(rel: &str) -> String {
    let path = yaml::resolve_data_path(PKG_DIR, rel);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()))
}

const TUNNEL_ACTION: &str = ".github/actions/zitadel-tunnel-setup/action.yml";

/// The port the tunnel action probes and tunnels to, from its
/// `"http://${ip}:PORT/..."` healthz URL.
pub fn load_tunnel_port() -> String {
    let raw = read_root_file(TUNNEL_ACTION);
    let marker = "http://${ip}:";
    let at = raw
        .find(marker)
        .unwrap_or_else(|| panic!("no {marker} probe in {TUNNEL_ACTION}"));
    raw[at + marker.len()..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect()
}

/// The Envoy gateway's pinned HTTP nodePort (the `http-80` port entry).
pub fn load_envoy_http_nodeport() -> String {
    let raw = read_root_file("gitops/argocd/platform/envoy-gateway/gateway/envoyproxy.yaml");
    let mut lines = raw.lines().skip_while(|l| l.trim() != "- name: http-80");
    lines
        .next()
        .expect("no http-80 port entry in envoyproxy.yaml");
    lines
        .take_while(|l| !l.trim_start().starts_with("- "))
        .find_map(|l| {
            l.trim()
                .strip_prefix("nodePort:")
                .map(|v| v.trim().to_string())
        })
        .expect("http-80 has no nodePort in envoyproxy.yaml")
}

/// The candidate gateway IPs the Zitadel tunnel action tries, from its
/// `candidates="..."` line.
pub fn load_tunnel_candidates() -> Vec<String> {
    let rel = TUNNEL_ACTION;
    let raw = read_root_file(rel);
    let line = raw
        .lines()
        .map(str::trim)
        .find(|l| l.starts_with("candidates=\""))
        .unwrap_or_else(|| panic!("no candidates=\"...\" line in {rel}"));
    line.trim_start_matches("candidates=\"")
        .trim_end_matches('"')
        .split_whitespace()
        .map(str::to_string)
        .collect()
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
    fn test_policy_has_no_wildcard_source() {
        let policy = load_policy();
        for rule in policy["acls"].as_array().expect("acls") {
            let src: Vec<&str> = rule["src"]
                .as_array()
                .expect("src")
                .iter()
                .filter_map(Value::as_str)
                .collect();
            assert!(
                !src.contains(&"*"),
                "an ACL with src \"*\" would also cover tag:ci runners; name the sources instead: {rule}"
            );
        }
    }

    #[test]
    fn test_ci_tag_reaches_only_the_gateway_nodeport() {
        let policy = load_policy();
        assert!(
            policy
                .pointer("/tagOwners/tag:ci")
                .and_then(Value::as_array)
                .is_some_and(|o| !o.is_empty()),
            "tag:ci needs a tagOwners entry"
        );
        let hosts = policy["hosts"].as_object().expect("hosts");
        let mut ci_rules = 0;
        for rule in policy["acls"].as_array().expect("acls") {
            let src: Vec<&str> = rule["src"]
                .as_array()
                .expect("src")
                .iter()
                .filter_map(Value::as_str)
                .collect();
            if !src.contains(&"tag:ci") {
                continue;
            }
            ci_rules += 1;
            assert_eq!(src, vec!["tag:ci"], "keep tag:ci in a rule of its own");
            assert_eq!(
                rule.get("proto").and_then(Value::as_str),
                Some("tcp"),
                "the tag:ci rule must be TCP-only (no UDP or ICMP to the nodes)"
            );
            for d in rule["dst"]
                .as_array()
                .expect("dst")
                .iter()
                .filter_map(Value::as_str)
            {
                let (host, port) = d.rsplit_once(':').expect("dst host:port");
                assert_eq!(
                    port, "30265",
                    "tag:ci may reach only the Envoy gateway NodePort, not {d}"
                );
                assert!(
                    hosts.contains_key(host),
                    "tag:ci dst {host} is not a named host"
                );
            }
        }
        assert_eq!(ci_rules, 1, "expected exactly one tag:ci rule");
    }

    #[test]
    fn test_tunnel_candidates_match_policy_hosts() {
        let policy = load_policy();
        let mut hosts: Vec<String> = policy["hosts"]
            .as_object()
            .expect("hosts")
            .values()
            .filter_map(Value::as_str)
            .map(|c| c.trim_end_matches("/32").to_string())
            .collect();
        let mut candidates = load_tunnel_candidates();
        hosts.sort();
        candidates.sort();
        assert_eq!(
            candidates, hosts,
            "zitadel-tunnel-setup's candidate nodes must be exactly the policy's hosts, \
             or CI would try a node the ACL blocks (or the ACL would open one CI never uses)"
        );
    }

    #[test]
    fn test_gateway_port_agrees_across_policy_tunnel_and_envoy() {
        let envoy = load_envoy_http_nodeport();
        assert_eq!(
            load_tunnel_port(),
            envoy,
            "zitadel-tunnel-setup must probe the Envoy gateway's pinned HTTP nodePort"
        );
        let policy = load_policy();
        for rule in policy["acls"].as_array().expect("acls") {
            if rule["src"]
                .as_array()
                .expect("src")
                .iter()
                .any(|s| s == "tag:ci")
            {
                for d in rule["dst"]
                    .as_array()
                    .expect("dst")
                    .iter()
                    .filter_map(Value::as_str)
                {
                    assert_eq!(
                        d.rsplit_once(':').map(|(_, p)| p),
                        Some(envoy.as_str()),
                        "tag:ci dst {d} must use the Envoy gateway nodePort {envoy}"
                    );
                }
            }
        }
    }

    #[test]
    fn test_policy_parse_errors_name_the_real_line() {
        let raw = "// header\n// more\n{\n  \"acls\": [],\n}\n";
        let err = parse_policy(raw).unwrap_err();
        assert!(err.starts_with("policy.hujson line 5:"), "{err}");
        assert!(err.contains("trailing commas"), "{err}");
    }

    #[test]
    fn test_rejects_missing_database_policy_mode_in_api_only_mode() {
        let hp = yaml::parse_doc("headscale:\n  url: http://headscale:8080\n").unwrap();
        let hs = yaml::parse_doc("env:\n  HEADSCALE_POLICY_MODE: file\n").unwrap();
        assert!(check_policy_mode(&hp, &hs).is_err());
    }
}
