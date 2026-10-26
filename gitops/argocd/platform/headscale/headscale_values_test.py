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


if __name__ == "__main__":
    unittest.main()
