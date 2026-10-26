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
"""EnvoyProxy StrategicMerge Service patch must include `port` on every port item.

Kubernetes ServiceSpec.ports declares `port` (not `name`) as its strategic merge
patch key. Omitting `port` causes Envoy Gateway's infrastructure runner to fail
Service reconciliation with:
  error during strategic merge: map: map[name:http-80 nodePort:30265] does not
  contain declared merge key: port
"""

import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


class EnvoyProxyTest(unittest.TestCase):
    def test_strategic_merge_service_ports_define_port_merge_key(self):
        with open(os.path.join(HERE, "gateway", "envoyproxy.yaml")) as f:
            docs = [d for d in yaml.safe_load_all(f) if d]
        (ep,) = [d for d in docs if d["kind"] == "EnvoyProxy"]
        svc = ep["spec"]["provider"]["kubernetes"]["envoyService"]
        patch = svc.get("patch") or {}
        if patch.get("type") == "StrategicMerge":
            ports = patch.get("value", {}).get("spec", {}).get("ports") or []
            for p in ports:
                self.assertIn(
                    "port",
                    p,
                    f"Port patch entry {p} must define 'port' (the Kubernetes "
                    "ServiceSpec.ports strategic merge key).",
                )


if __name__ == "__main__":
    unittest.main()
