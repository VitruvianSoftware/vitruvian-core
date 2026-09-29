#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Prometheus Thanos sidecar must have sufficient memory headroom to avoid OOM kills."""

import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def load_values():
    with open(os.path.join(HERE, "applicationset.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (appset,) = [d for d in docs if d["kind"] == "ApplicationSet"]
    raw_values = appset["spec"]["template"]["spec"]["source"]["helm"]["values"]
    cleaned = raw_values.replace("{{`", "").replace("`}}", "")
    return yaml.safe_load(cleaned)


class PrometheusValuesTest(unittest.TestCase):
    def setUp(self):
        self.v = load_values()

    def test_thanos_sidecar_memory_limit(self):
        sidecars = self.v.get("server", {}).get("sidecarContainers", {})
        sidecar = sidecars.get("thanos-sidecar", {})
        lim = sidecar.get("resources", {}).get("limits", {}).get("memory")
        self.assertEqual(lim, "2Gi")


if __name__ == "__main__":
    unittest.main()
