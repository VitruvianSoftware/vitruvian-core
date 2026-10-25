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


def load_headscale_values():
    with open(os.path.join(HERE, "applicationset.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (appset,) = [d for d in docs if d["kind"] == "ApplicationSet"]
    return yaml.safe_load(
        appset["spec"]["template"]["spec"]["source"]["helm"]["values"]
    )


def load_headplane_config():
    with open(os.path.join(HERE, "configmap-headplane.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
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


if __name__ == "__main__":
    unittest.main()
