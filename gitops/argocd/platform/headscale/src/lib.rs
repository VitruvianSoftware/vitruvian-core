// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Headscale must use database policy mode when Headplane runs in API-only mode.
//!
//! Headplane (`configmap-headplane.yaml`) connects to Headscale via its gRPC/REST API
//! without a shared policy file on disk. Headscale defaults to `policy.mode=file` with
//! an empty `policy.path` (`""`), which causes `/admin/acls` in Headplane and
//! `headscale policy get` to fail with:
//!   `reading policy from path "": open : no such file or directory`

pub use gitops_values_yaml as yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/headscale";
pub const POLICY_FILENAME: &str = "policy.hujson";
pub const POLICY_CONFIGMAP_FILENAME: &str = "configmap-policy.yaml";
pub const POLICY_CONFIGMAP_NAME: &str = "headscale-policy";

const CONFIGMAP_MIT_HEADER: &str = "\
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the \"Software\"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
";

/// Render `configmap-policy.yaml` embedding `raw_policy` verbatim under `data["policy.hujson"]`.
pub fn render_policy_configmap(raw_policy: &str) -> String {
    let mut out = String::from(CONFIGMAP_MIT_HEADER);
    out.push_str(concat!(
        "#\n",
        "# Generated from policy.hujson by:\n",
        "#   bazel run //gitops/argocd/platform/headscale:policy-configmap\n",
        "# Do not edit by hand; edit policy.hujson and re-run the generator.\n",
        "apiVersion: v1\n",
        "kind: ConfigMap\n",
        "metadata:\n",
        "  name: headscale-policy\n",
        "  namespace: headscale\n",
        "data:\n",
    ));
    if raw_policy.is_empty() {
        out.push_str("  policy.hujson: \"\"\n");
        return out;
    }
    let first_non_empty_indented = raw_policy
        .split('\n')
        .find(|l| !l.is_empty())
        .is_some_and(|l| l.starts_with(' '));
    let indent_hint = if first_non_empty_indented { "2" } else { "" };
    let (chomp, body) = if let Some(stripped) = raw_policy.strip_suffix('\n') {
        if stripped.ends_with('\n') {
            ("+", stripped)
        } else {
            ("", stripped)
        }
    } else {
        ("-", raw_policy)
    };
    out.push_str(&format!("  policy.hujson: |{chomp}{indent_hint}\n"));
    for line in body.split('\n') {
        if line.is_empty() {
            out.push('\n');
        } else {
            out.push_str("    ");
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

/// Verify that `committed_cm` embeds `raw_policy` byte-for-byte and matches the generator output.
pub fn check_policy_configmap_drift(raw_policy: &str, committed_cm: &str) -> Result<(), String> {
    let docs = yaml::parse_all(committed_cm)
        .map_err(|e| format!("failed to parse {POLICY_CONFIGMAP_FILENAME}: {e}"))?;
    if docs.len() != 1 {
        return Err(format!(
            "expected exactly 1 ConfigMap document in {POLICY_CONFIGMAP_FILENAME}, found {}",
            docs.len()
        ));
    }
    let cm = &docs[0];
    if cm.get("kind").and_then(Value::as_str) != Some("ConfigMap") {
        return Err(format!(
            "{POLICY_CONFIGMAP_FILENAME} must have kind: ConfigMap"
        ));
    }
    if cm.pointer("/metadata/name").and_then(Value::as_str) != Some(POLICY_CONFIGMAP_NAME) {
        return Err(format!(
            "{POLICY_CONFIGMAP_FILENAME} must have metadata.name: {POLICY_CONFIGMAP_NAME}"
        ));
    }
    if cm.pointer("/metadata/namespace").and_then(Value::as_str) != Some("headscale") {
        return Err(format!(
            "{POLICY_CONFIGMAP_FILENAME} must have metadata.namespace: headscale"
        ));
    }
    let embedded = cm
        .pointer(&format!("/data/{POLICY_FILENAME}"))
        .and_then(Value::as_str)
        .ok_or_else(|| {
            format!("{POLICY_CONFIGMAP_FILENAME} is missing data['{POLICY_FILENAME}']")
        })?;
    if embedded.as_bytes() != raw_policy.as_bytes() {
        return Err(format!(
            "{POLICY_CONFIGMAP_FILENAME} data['{POLICY_FILENAME}'] has drifted from {POLICY_FILENAME} \
             (expected {} bytes, found {} bytes); run `bazel run //gitops/argocd/platform/headscale:policy-configmap`",
            raw_policy.len(),
            embedded.len()
        ));
    }
    let expected_cm = render_policy_configmap(raw_policy);
    if committed_cm.as_bytes() != expected_cm.as_bytes() {
        return Err(format!(
            "{POLICY_CONFIGMAP_FILENAME} does not match generated output from {POLICY_FILENAME}; \
             run `bazel run //gitops/argocd/platform/headscale:policy-configmap`"
        ));
    }
    Ok(())
}

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

const TUNNEL_ACTION: &str = ".github/actions/homelab-tunnel-setup/action.yml";
#[cfg(test)]
const ZITADEL_TUNNEL_ACTION: &str = ".github/actions/zitadel-tunnel-setup/action.yml";

fn load_tunnel_probe_port(marker: &str) -> String {
    let raw = read_root_file(TUNNEL_ACTION);
    let at = raw
        .find(marker)
        .unwrap_or_else(|| panic!("no {marker} probe in {TUNNEL_ACTION}"));
    raw[at + marker.len()..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect()
}

/// The HTTP port the tunnel action probes and tunnels to, from its
/// `"http://${ip}:PORT..."` health probe.
pub fn load_tunnel_http_port() -> String {
    load_tunnel_probe_port("http://${ip}:")
}

/// The HTTPS port the tunnel action probes and tunnels to, from its
/// `"https://${TARGET_HOSTNAME}:PORT..."` health probe.
pub fn load_tunnel_https_port() -> String {
    load_tunnel_probe_port("https://${TARGET_HOSTNAME}:")
}

fn load_envoy_nodeport(port_name: &str) -> String {
    let raw = read_root_file("gitops/argocd/platform/envoy-gateway/gateway/envoyproxy.yaml");
    let header = format!("- name: {port_name}");
    let mut lines = raw.lines().skip_while(|l| l.trim() != header);
    lines
        .next()
        .unwrap_or_else(|| panic!("no {port_name} port entry in envoyproxy.yaml"));
    lines
        .take_while(|l| !l.trim_start().starts_with("- "))
        .find_map(|l| {
            l.trim()
                .strip_prefix("nodePort:")
                .map(|v| v.trim().to_string())
        })
        .unwrap_or_else(|| panic!("{port_name} has no nodePort in envoyproxy.yaml"))
}

/// The Envoy gateway's pinned HTTP nodePort (the `http-80` port entry).
pub fn load_envoy_http_nodeport() -> String {
    load_envoy_nodeport("http-80")
}

/// The Envoy gateway's pinned HTTPS nodePort (the `https-443` port entry).
pub fn load_envoy_https_nodeport() -> String {
    load_envoy_nodeport("https-443")
}

/// The candidate gateway IPs the homelab tunnel action tries, from its
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
        let http_port = load_envoy_http_nodeport();
        let https_port = load_envoy_https_nodeport();
        let allowed_ports = [http_port.as_str(), https_port.as_str()];
        let mut expected_dst: Vec<String> = Vec::new();
        for host in hosts.keys() {
            for port in &allowed_ports {
                expected_dst.push(format!("{host}:{port}"));
            }
        }
        expected_dst.sort();

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
            let mut got_dst: Vec<String> = Vec::new();
            for d in rule["dst"]
                .as_array()
                .expect("dst")
                .iter()
                .filter_map(Value::as_str)
            {
                let (host, port) = d.rsplit_once(':').expect("dst host:port");
                assert!(
                    allowed_ports.contains(&port),
                    "tag:ci may reach only the Envoy gateway NodePorts ({allowed_ports:?}), not {d}"
                );
                assert!(
                    hosts.contains_key(host),
                    "tag:ci dst {host} is not a named host"
                );
                got_dst.push(d.to_string());
            }
            got_dst.sort();
            assert_eq!(
                got_dst, expected_dst,
                "tag:ci dst must cover every policy host on both Envoy gateway NodePorts"
            );
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
            "homelab-tunnel-setup's candidate nodes must be exactly the policy's hosts, \
             or CI would try a node the ACL blocks (or the ACL would open one CI never uses)"
        );
    }

    #[test]
    fn test_gateway_port_agrees_across_policy_tunnel_and_envoy() {
        let http_envoy = load_envoy_http_nodeport();
        let https_envoy = load_envoy_https_nodeport();
        assert_eq!(
            load_tunnel_http_port(),
            http_envoy,
            "homelab-tunnel-setup must probe the Envoy gateway's pinned HTTP nodePort"
        );
        assert_eq!(
            load_tunnel_https_port(),
            https_envoy,
            "homelab-tunnel-setup must probe the Envoy gateway's pinned HTTPS nodePort"
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
                    let port = d.rsplit_once(':').map(|(_, p)| p);
                    assert!(
                        port == Some(http_envoy.as_str()) || port == Some(https_envoy.as_str()),
                        "tag:ci dst {d} must use an Envoy gateway nodePort ({http_envoy} or {https_envoy})"
                    );
                }
            }
        }
    }

    #[test]
    fn test_zitadel_tunnel_delegates_to_homelab_tunnel() {
        let raw = read_root_file(ZITADEL_TUNNEL_ACTION);
        assert!(
            raw.contains("uses: ./.github/actions/homelab-tunnel-setup"),
            "{ZITADEL_TUNNEL_ACTION} must delegate to ./.github/actions/homelab-tunnel-setup"
        );
        assert!(
            raw.contains("hostname: auth.ipv1337.dev"),
            "{ZITADEL_TUNNEL_ACTION} must pin hostname: auth.ipv1337.dev"
        );
        assert!(
            raw.contains("health-path: /debug/healthz"),
            "{ZITADEL_TUNNEL_ACTION} must pin health-path: /debug/healthz"
        );
        assert!(
            raw.contains("gateway-scheme: http"),
            "{ZITADEL_TUNNEL_ACTION} must pin gateway-scheme: http"
        );
        assert!(
            raw.contains("gateway-env-var: ZITADEL_GATEWAY"),
            "{ZITADEL_TUNNEL_ACTION} must pin gateway-env-var: ZITADEL_GATEWAY"
        );
        assert!(
            raw.contains("tls-cert-bundle: /etc/auth-internal-ck.pem"),
            "{ZITADEL_TUNNEL_ACTION} must pin tls-cert-bundle: /etc/auth-internal-ck.pem"
        );
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

    #[test]
    fn test_policy_sync_sidecar_and_shared_volumes_configured() {
        let hs = load_headscale_values();

        assert_eq!(
            hs.pointer("/automountServiceAccountToken")
                .and_then(Value::as_bool),
            Some(false),
            "automountServiceAccountToken must be false: neither headscale nor policy-sync calls the Kubernetes API."
        );
        assert_eq!(
            hs.pointer("/env/HEADSCALE_POLICY_MODE")
                .and_then(Value::as_str),
            Some("database")
        );
        assert_eq!(
            hs.pointer("/env/HEADSCALE_UNIX_SOCKET_PERMISSION")
                .and_then(Value::as_str),
            Some("0770"),
            "HEADSCALE_UNIX_SOCKET_PERMISSION must use 0770 (without 0o prefix) so Go base-8 ParseUint permits non-root gid 0 sidecar access."
        );

        assert_eq!(
            hs.pointer("/persistence/socket/enabled")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            hs.pointer("/persistence/socket/type")
                .and_then(Value::as_str),
            Some("emptyDir")
        );
        assert_eq!(
            hs.pointer("/persistence/socket/mountPath")
                .and_then(Value::as_str),
            Some("/var/run/headscale")
        );

        assert_eq!(
            hs.pointer("/persistence/policy/enabled")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            hs.pointer("/persistence/policy/type")
                .and_then(Value::as_str),
            Some("configMap")
        );
        assert_eq!(
            hs.pointer("/persistence/policy/name")
                .and_then(Value::as_str),
            Some(POLICY_CONFIGMAP_NAME)
        );
        assert_eq!(
            hs.pointer("/persistence/policy/mountPath")
                .and_then(Value::as_str),
            Some("-"),
            "persistence.policy must use mountPath \"-\" so only policy-sync mounts the ConfigMap."
        );

        assert_eq!(
            hs.pointer("/persistence/cli-tmp/enabled")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            hs.pointer("/persistence/cli-tmp/type")
                .and_then(Value::as_str),
            Some("emptyDir")
        );
        assert_eq!(
            hs.pointer("/persistence/cli-tmp/mountPath")
                .and_then(Value::as_str),
            Some("-")
        );

        let sidecar = hs
            .pointer("/sidecars/policy-sync")
            .expect("missing sidecars.policy-sync");
        let main_tag = hs
            .pointer("/image/tag")
            .and_then(Value::as_str)
            .expect("missing image.tag");
        let sidecar_img = sidecar
            .get("image")
            .and_then(Value::as_str)
            .expect("missing sidecar image");
        let expected_prefix = format!("ghcr.io/juanfont/headscale:{main_tag}-debug@sha256:");
        assert!(
            sidecar_img.starts_with(&expected_prefix),
            "policy-sync image {sidecar_img} must match {main_tag}-debug and pin by @sha256 digest"
        );
        assert_eq!(
            sidecar
                .pointer("/env/HEADSCALE_DISABLE_CHECK_UPDATES")
                .and_then(Value::as_str),
            Some("true")
        );
        assert_eq!(
            sidecar
                .pointer("/env/HEADSCALE_CONFIG")
                .and_then(Value::as_str),
            Some("/tmp/headscale-cli.yaml")
        );

        let mounts = sidecar
            .get("volumeMounts")
            .and_then(Value::as_array)
            .expect("missing policy-sync volumeMounts");
        let find_mount = |name: &str| {
            mounts
                .iter()
                .find(|m| m.get("name").and_then(Value::as_str) == Some(name))
        };

        let policy_mount = find_mount("policy").expect("policy-sync must mount policy ConfigMap");
        assert_eq!(
            policy_mount.get("mountPath").and_then(Value::as_str),
            Some("/etc/headscale-policy")
        );
        assert_eq!(
            policy_mount.get("readOnly").and_then(Value::as_bool),
            Some(true)
        );
        assert!(
            policy_mount.get("subPath").is_none(),
            "policy ConfigMap must be directory-mounted (no subPath) so kubelet updates it in place"
        );

        let socket_mount =
            find_mount("socket").expect("policy-sync must share the headscale socket emptyDir");
        assert_eq!(
            socket_mount.get("mountPath").and_then(Value::as_str),
            Some("/var/run/headscale")
        );
        assert!(socket_mount.get("subPath").is_none());

        let tmp_mount = find_mount("cli-tmp").expect("policy-sync must mount cli-tmp at /tmp");
        assert_eq!(
            tmp_mount.get("mountPath").and_then(Value::as_str),
            Some("/tmp")
        );
        assert!(
            find_mount("config").is_none(),
            "policy-sync must not mount the headscale config/database PVC"
        );

        let sc = sidecar
            .get("securityContext")
            .expect("missing policy-sync securityContext");
        assert_eq!(sc.get("runAsNonRoot").and_then(Value::as_bool), Some(true));
        assert_eq!(sc.get("runAsUser").and_then(Value::as_i64), Some(65532));
        assert_eq!(sc.get("runAsGroup").and_then(Value::as_i64), Some(0));
        assert_eq!(
            sc.get("allowPrivilegeEscalation").and_then(Value::as_bool),
            Some(false)
        );
        assert_eq!(
            sc.get("readOnlyRootFilesystem").and_then(Value::as_bool),
            Some(true)
        );
        let dropped: Vec<&str> = sc
            .pointer("/capabilities/drop")
            .and_then(Value::as_array)
            .expect("missing capabilities.drop")
            .iter()
            .filter_map(Value::as_str)
            .collect();
        assert!(dropped.contains(&"ALL"));

        for path in [
            "/resources/requests/cpu",
            "/resources/requests/memory",
            "/resources/limits/memory",
        ] {
            assert!(
                sidecar
                    .pointer(path)
                    .and_then(Value::as_str)
                    .is_some_and(|s| !s.is_empty()),
                "policy-sync must specify {path}"
            );
        }
    }

    struct TempDir(std::path::PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            use std::sync::atomic::{AtomicU64, Ordering};
            static SEQ: AtomicU64 = AtomicU64::new(0);
            let n = SEQ.fetch_add(1, Ordering::Relaxed);
            let dir = std::env::temp_dir().join(format!(
                "headscale-policy-sync-{label}-{}-{n}",
                std::process::id()
            ));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).expect("create temp dir");
            Self(dir)
        }
        fn path(&self) -> &std::path::Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    fn policy_sync_script() -> String {
        let hs = load_headscale_values();
        let cmd = hs
            .pointer("/sidecars/policy-sync/command")
            .and_then(Value::as_array)
            .expect("missing sidecars.policy-sync.command");
        assert_eq!(cmd.len(), 3);
        assert_eq!(cmd[0].as_str(), Some("/busybox/sh"));
        assert_eq!(cmd[1].as_str(), Some("-c"));
        cmd[2]
            .as_str()
            .expect("missing policy-sync script")
            .to_string()
    }

    fn install_fake_headscale(dir: &std::path::Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let bin_dir = dir.join("bin");
        std::fs::create_dir_all(&bin_dir).unwrap();
        let fake = bin_dir.join("headscale");
        let body = r#"#!/bin/sh
set -u
printf '%s\n' "$*" >>"$FAKE_CALLS"
sub="$1 $2"
case "$sub" in
  "policy get")
    case "$FAKE_GET_MODE" in
      in_sync|diff)
        cat "$FAKE_LIVE_FILE"
        printf '\n'
        exit 0
        ;;
      not_ready)
        echo "Could not connect: dial unix /var/run/headscale/headscale.sock: connect: no such file or directory" >&2
        exit 1
        ;;
      not_found)
        echo "Failed loading ACL Policy: rpc error: code = Unknown desc = loading ACL from database: acl policy not found" >&2
        exit 1
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  "policy check")
    file="$4"
    if [ -n "${FAKE_CHECK_FAIL_ONCE:-}" ] && [ -f "$FAKE_CHECK_FAIL_ONCE" ]; then
      rm -f "$FAKE_CHECK_FAIL_ONCE"
      if [ -n "${FAKE_SWAP_VALID_FROM:-}" ]; then
        cp "$FAKE_SWAP_VALID_FROM" "$POLICY_FILE"
      fi
      echo "Error parsing the policy file: syntax error" >&2
      exit 1
    fi
    if [ "${FAKE_CHECK_FAIL:-0}" = "1" ]; then
      echo "Error parsing the policy file: syntax error" >&2
      exit 1
    fi
    echo "Policy is valid"
    exit 0
    ;;
  "policy set")
    file="$4"
    cp "$file" "$FAKE_APPLIED_FILE"
    echo "Policy updated."
    exit 0
    ;;
  *)
    echo "unexpected args: $*" >&2
    exit 2
    ;;
esac
"#;
        std::fs::write(&fake, body).unwrap();
        let mut perms = std::fs::metadata(&fake).unwrap().permissions();
        perms.set_mode(0o755);
        std::fs::set_permissions(&fake, perms).unwrap();
        bin_dir
    }

    fn run_policy_sync(
        tmp: &TempDir,
        bin_dir: &std::path::Path,
        policy_path: &std::path::Path,
        extra_env: &[(&str, &str)],
    ) -> (std::process::Output, std::path::PathBuf, std::path::PathBuf) {
        let calls = tmp.path().join("calls.log");
        let applied = tmp.path().join("applied.hujson");
        let work_tmp = tmp.path().join("work-tmp");
        std::fs::create_dir_all(&work_tmp).unwrap();
        let orig_path = std::env::var("PATH").unwrap_or_default();
        let path_env = format!("{}:{orig_path}", bin_dir.display());
        let mut cmd = std::process::Command::new("/bin/sh");
        cmd.arg("-c")
            .arg(policy_sync_script())
            .env("PATH", path_env)
            .env("POLICY_FILE", policy_path)
            .env("TMP_DIR", &work_tmp)
            .env("HEADSCALE_CONFIG", work_tmp.join("headscale-cli.yaml"))
            .env("FAKE_CALLS", &calls)
            .env("FAKE_APPLIED_FILE", &applied);
        for (k, v) in extra_env {
            cmd.env(k, v);
        }
        let out = cmd.output().expect("run policy-sync script");
        (out, calls, applied)
    }

    #[test]
    fn test_policy_sync_script_in_sync_with_println_trailing_newline() {
        let tmp = TempDir::new("in-sync");
        let bin_dir = install_fake_headscale(tmp.path());
        let real_policy =
            std::fs::read_to_string(yaml::resolve_data_path(PKG_DIR, POLICY_FILENAME))
                .expect("read policy.hujson");
        let mounted = tmp.path().join("mounted.hujson");
        let live = tmp.path().join("live.hujson");
        std::fs::write(&mounted, &real_policy).unwrap();
        std::fs::write(&live, &real_policy).unwrap();

        let (out, calls, applied) = run_policy_sync(
            &tmp,
            &bin_dir,
            &mounted,
            &[
                ("POLICY_SYNC_ONCE", "1"),
                ("FAKE_GET_MODE", "in_sync"),
                ("FAKE_LIVE_FILE", live.to_str().unwrap()),
            ],
        );
        assert!(out.status.success(), "{out:?}");
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(stdout.contains("policy-sync: in sync"), "stdout: {stdout}");
        let log = std::fs::read_to_string(&calls).unwrap();
        assert_eq!(log.lines().collect::<Vec<_>>(), vec!["policy get"]);
        assert!(!applied.exists());
    }

    #[test]
    fn test_policy_sync_script_applies_on_diff_after_check() {
        let tmp = TempDir::new("diff");
        let bin_dir = install_fake_headscale(tmp.path());
        let real_policy =
            std::fs::read_to_string(yaml::resolve_data_path(PKG_DIR, POLICY_FILENAME))
                .expect("read policy.hujson");
        let mounted = tmp.path().join("mounted.hujson");
        let live = tmp.path().join("live.hujson");
        std::fs::write(&mounted, &real_policy).unwrap();
        std::fs::write(&live, "{\"acls\": []}\n").unwrap();

        let (out, calls, applied) = run_policy_sync(
            &tmp,
            &bin_dir,
            &mounted,
            &[
                ("POLICY_SYNC_ONCE", "1"),
                ("FAKE_GET_MODE", "diff"),
                ("FAKE_LIVE_FILE", live.to_str().unwrap()),
            ],
        );
        assert!(out.status.success(), "{out:?}");
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(stdout.contains("policy-sync: applied "), "stdout: {stdout}");
        let recorded: Vec<String> = std::fs::read_to_string(&calls)
            .unwrap()
            .lines()
            .map(str::to_string)
            .collect();
        assert_eq!(recorded.len(), 3, "calls: {recorded:?}");
        assert_eq!(recorded[0], "policy get");
        assert!(recorded[1].starts_with("policy check -f "));
        assert!(recorded[2].starts_with("policy set -f "));
        assert_eq!(std::fs::read(&applied).unwrap(), real_policy.as_bytes());
    }

    #[test]
    fn test_policy_sync_script_check_failure_keeps_live_policy_and_survives() {
        let tmp = TempDir::new("check-fail");
        let bin_dir = install_fake_headscale(tmp.path());
        let mounted = tmp.path().join("mounted.hujson");
        let valid = tmp.path().join("valid.hujson");
        let live = tmp.path().join("live.hujson");
        let fail_once = tmp.path().join("fail-once.flag");
        std::fs::write(&mounted, "{\"acls\": [broken}\n").unwrap();
        std::fs::write(
            &valid,
            "{\"acls\": [{\"action\":\"accept\",\"src\":[\"james@\"],\"dst\":[\"*:*\"]}]}\n",
        )
        .unwrap();
        std::fs::write(&live, "{\"acls\": []}\n").unwrap();
        std::fs::write(&fail_once, "1").unwrap();

        let (out, calls, applied) = run_policy_sync(
            &tmp,
            &bin_dir,
            &mounted,
            &[
                ("POLICY_SYNC_MAX_LOOPS", "2"),
                ("POLICY_SYNC_INTERVAL", "0"),
                ("FAKE_GET_MODE", "diff"),
                ("FAKE_LIVE_FILE", live.to_str().unwrap()),
                ("FAKE_CHECK_FAIL_ONCE", fail_once.to_str().unwrap()),
                ("FAKE_SWAP_VALID_FROM", valid.to_str().unwrap()),
            ],
        );
        assert!(out.status.success(), "{out:?}");
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(
            stdout.contains("policy-sync: check FAILED")
                && stdout.contains("live policy unchanged"),
            "stdout: {stdout}"
        );
        assert!(
            stdout.contains("policy-sync: applied "),
            "expected loop to survive failed check and apply on tick 2: {stdout}"
        );
        let recorded: Vec<String> = std::fs::read_to_string(&calls)
            .unwrap()
            .lines()
            .map(str::to_string)
            .collect();
        // Tick 1: get, check (fails, no set); Tick 2: get, check, set
        assert_eq!(recorded.len(), 5, "calls: {recorded:?}");
        assert!(recorded[1].starts_with("policy check -f "));
        assert!(recorded[2] == "policy get");
        assert!(recorded[3].starts_with("policy check -f "));
        assert!(recorded[4].starts_with("policy set -f "));
        assert_eq!(
            std::fs::read(&applied).unwrap(),
            std::fs::read(&valid).unwrap()
        );
    }

    #[test]
    fn test_policy_sync_script_skips_when_policy_get_fails() {
        let tmp = TempDir::new("not-ready");
        let bin_dir = install_fake_headscale(tmp.path());
        let mounted = tmp.path().join("mounted.hujson");
        std::fs::write(&mounted, "{}\n").unwrap();

        let (out, calls, applied) = run_policy_sync(
            &tmp,
            &bin_dir,
            &mounted,
            &[("POLICY_SYNC_ONCE", "1"), ("FAKE_GET_MODE", "not_ready")],
        );
        assert!(out.status.success(), "{out:?}");
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(
            stdout.contains("policy-sync: headscale not ready")
                && stdout.contains("live policy unchanged"),
            "stdout: {stdout}"
        );
        let recorded: Vec<String> = std::fs::read_to_string(&calls)
            .unwrap()
            .lines()
            .map(str::to_string)
            .collect();
        assert_eq!(recorded, vec!["policy get"]);
        assert!(!applied.exists());
    }

    #[test]
    fn test_policy_sync_script_bootstraps_when_db_has_no_policy_yet() {
        let tmp = TempDir::new("bootstrap");
        let bin_dir = install_fake_headscale(tmp.path());
        let mounted = tmp.path().join("mounted.hujson");
        std::fs::write(&mounted, "{\"acls\": []}\n").unwrap();

        let (out, calls, applied) = run_policy_sync(
            &tmp,
            &bin_dir,
            &mounted,
            &[("POLICY_SYNC_ONCE", "1"), ("FAKE_GET_MODE", "not_found")],
        );
        assert!(out.status.success(), "{out:?}");
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(stdout.contains("policy-sync: applied "), "stdout: {stdout}");
        let recorded: Vec<String> = std::fs::read_to_string(&calls)
            .unwrap()
            .lines()
            .map(str::to_string)
            .collect();
        assert_eq!(recorded.len(), 3, "calls: {recorded:?}");
        assert_eq!(recorded[0], "policy get");
        assert!(recorded[1].starts_with("policy check -f "));
        assert!(recorded[2].starts_with("policy set -f "));
        assert_eq!(std::fs::read(&applied).unwrap(), b"{\"acls\": []}\n");
    }
}
