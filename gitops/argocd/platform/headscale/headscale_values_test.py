#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
"""Headscale must use database policy mode when Headplane runs in API-only mode.

Headplane (configmap-headplane.yaml) connects to Headscale via its gRPC/REST API
without a shared policy file on disk. Headscale defaults to policy.mode=file with
an empty policy.path (""), which causes /admin/acls in Headplane and
`headscale policy get` to fail with:
  reading policy from path "": open : no such file or directory
"""

import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def load_docs(filename):
    with open(os.path.join(HERE, filename)) as f:
        return [d for d in yaml.safe_load_all(f) if d]


def load_headscale_values():
    docs = load_docs("applicationset.yaml")
    (appset,) = [d for d in docs if d["kind"] == "ApplicationSet"]
    return yaml.safe_load(
        appset["spec"]["template"]["spec"]["source"]["helm"]["values"]
    )


def load_headplane_config():
    docs = load_docs("configmap-headplane.yaml")
    (cm,) = [d for d in docs if d["kind"] == "ConfigMap"]
    return yaml.safe_load(cm["data"]["config.yaml"])


class HeadscaleValuesTest(unittest.TestCase):
    def test_policy_mode_is_database_when_headplane_has_no_config_path(self):
        hp = load_headplane_config()
        if not hp.get("headscale", {}).get("config_path"):
            hs_env = load_headscale_values().get("env") or {}
            self.assertEqual(
                hs_env.get("HEADSCALE_POLICY_MODE"),
                "database",
                "Headplane in API-only mode requires HEADSCALE_POLICY_MODE=database "
                "so /admin/acls can read and update ACL policies via Headscale's API.",
            )

    def test_backend_traffic_policy_permits_tailscale_control_protocol(self):
        docs = load_docs("backendtrafficpolicy.yaml")
        (btp,) = [d for d in docs if d["kind"] == "BackendTrafficPolicy"]
        target_names = [t["name"] for t in btp["spec"]["targetRefs"]]
        self.assertIn("headscale", target_names)
        upgrade_types = [u["type"] for u in btp["spec"]["httpUpgrade"]]
        self.assertIn(
            "tailscale-control-protocol",
            upgrade_types,
            "Envoy Gateway must allow Upgrade: tailscale-control-protocol for Headscale TS2021.",
        )

    def test_headscale_dns_is_not_cloudflare_proxied(self):
        docs = load_docs("dnsendpoint.yaml")
        (dns,) = [d for d in docs if d["kind"] == "DNSEndpoint"]
        endpoints = {ep["dnsName"]: ep for ep in dns["spec"]["endpoints"]}
        hs_ep = endpoints["headscale.ipv1337.dev"]
        self.assertEqual(
            hs_ep["recordType"],
            "A",
            "headscale.ipv1337.dev must be a direct A record (not a Cloudflare Tunnel CNAME) "
            "because Cloudflare Edge strips Upgrade headers on HTTP POST /ts2021.",
        )
        proxied_props = {
            p["name"]: p["value"] for p in hs_ep.get("providerSpecific", [])
        }
        self.assertEqual(
            proxied_props.get("external-dns.alpha.kubernetes.io/cloudflare-proxied"),
            "false",
            "headscale.ipv1337.dev must have cloudflare-proxied=false so Cloudflare Edge "
            "does not strip TS2021 POST Upgrade headers.",
        )

    def test_headscale_tls_certificate_and_reference_grant_exist(self):
        docs = load_docs("certificate.yaml")
        (cert,) = [d for d in docs if d["kind"] == "Certificate"]
        self.assertEqual(cert["spec"]["secretName"], "headscale-tls")
        self.assertIn("headscale.ipv1337.dev", cert["spec"]["dnsNames"])

        (rg,) = [d for d in docs if d["kind"] == "ReferenceGrant"]
        to_names = [t.get("name") for t in rg["spec"]["to"]]
        self.assertIn("headscale-tls", to_names)

    def test_edge_tunnel_and_subnet_router_deployments_exist(self):
        tunnel_docs = load_docs("deployment-edge-tunnel.yaml")
        (tunnel,) = [d for d in tunnel_docs if d["kind"] == "Deployment"]
        self.assertEqual(tunnel["metadata"]["name"], "headscale-edge-tunnel")

        router_docs = load_docs("deployment-subnet-router.yaml")
        (router,) = [d for d in router_docs if d["kind"] == "Deployment"]
        self.assertEqual(router["metadata"]["name"], "headscale-subnet-router")
        env = {
            e["name"]: e.get("value")
            for e in router["spec"]["template"]["spec"]["containers"][0]["env"]
        }
        self.assertEqual(env.get("TS_USERSPACE"), "true")
        self.assertEqual(
            env.get("TS_KUBE_SECRET"),
            "",
            "TS_KUBE_SECRET must be empty so containerboot uses TS_STATE_DIR instead of Kubernetes Secret RBAC.",
        )
        self.assertEqual(
            env.get("KUBERNETES_SERVICE_HOST"),
            "",
            "KUBERNETES_SERVICE_HOST must be empty so containerboot does not attempt in-cluster Kubernetes client setup.",
        )
        self.assertFalse(
            router["spec"]["template"]["spec"].get(
                "automountServiceAccountToken", True
            ),
            "automountServiceAccountToken must be false so containerboot does not switch to Kubernetes state storage.",
        )
        router_spec = router["spec"]["template"]["spec"]
        self.assertTrue(
            router_spec.get("hostNetwork"),
            "headscale-subnet-router must use hostNetwork=true on a wired control-plane node.",
        )
        self.assertEqual(
            router_spec.get("dnsPolicy"),
            "ClusterFirstWithHostNet",
        )
        self.assertEqual(
            router_spec.get("nodeSelector"),
            {
                "node.ipv1337.dev/link": "wired",
                "node-role.kubernetes.io/control-plane": "true",
            },
            "headscale-subnet-router must be pinned to wired control-plane nodes so 192.168.86.0/24 does not loop through macOS Lima NAT.",
        )
        self.assertIn(
            "--advertise-routes=192.168.86.0/24,10.44.86.0/24",
            env.get("TS_EXTRA_ARGS", ""),
        )

        agent_docs = load_docs("daemonset-node-agent.yaml")
        (agent,) = [d for d in agent_docs if d["kind"] == "DaemonSet"]
        self.assertEqual(agent["metadata"]["name"], "headscale-node-agent")
        agent_spec = agent["spec"]["template"]["spec"]
        self.assertTrue(
            agent_spec.get("hostNetwork"),
            "headscale-node-agent must use hostNetwork=true so userspace netstack 127.0.0.1 dials reach host sshd (:22) and k3s (:6443).",
        )
        self.assertEqual(
            agent_spec.get("dnsPolicy"),
            "ClusterFirstWithHostNet",
        )

    def test_headscale_image_matches_headplane_schema_version(self):
        hs_vals = load_headscale_values()
        self.assertEqual(
            (hs_vals.get("image") or {}).get("tag"),
            "v0.26.1",
            "Headplane 0.6.x requires Headscale v0.26.1 so /api/v1/node includes route arrays.",
        )
        init_cmd = "\n".join(
            ((hs_vals.get("initContainers") or {}).get("config") or {}).get(
                "command", []
            )
        )
        self.assertIn(
            "k8s-api.lab.ipv1337.dev",
            init_cmd,
            "Headscale config must include extra_records for k8s-api.lab.ipv1337.dev so Headscale clients do not dial commercial Tailscale 100.x IPs.",
        )


if __name__ == "__main__":
    unittest.main()
