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

    def test_thanos_sidecar_has_series_cap(self):
        sidecar = self.v["server"]["sidecarContainers"]["thanos-sidecar"]
        self.assertIn("--store.limits.request-series=150000", sidecar["args"])

    def test_repeated_oom_kill_alert_exists(self):
        rules = [
            r
            for g in self.v["serverFiles"]["alerting_rules.yml"]["groups"]
            for r in g.get("rules", [])
        ]
        (rule,) = [
            r for r in rules if r.get("alert") == "KubeContainerOOMKilledRepeatedly"
        ]
        self.assertIn('reason="OOMKilled"', rule["expr"])
        self.assertEqual(rule["labels"]["severity"], "warning")

    def test_repeated_oom_kill_alert_clears_once_container_is_stable(self):
        """The alert must stop firing once the container has run cleanly for 30m.

        Without the recency guard, a container that OOM'd twice and then
        stabilised stays red for the whole 6h restart lookback window.
        """
        rules = [
            r
            for g in self.v["serverFiles"]["alerting_rules.yml"]["groups"]
            for r in g.get("rules", [])
        ]
        (rule,) = [
            r for r in rules if r.get("alert") == "KubeContainerOOMKilledRepeatedly"
        ]
        expr = " ".join(rule["expr"].split())
        self.assertIn("kube_pod_container_state_started", expr)
        self.assertIn("time() - kube_pod_container_state_started < 30 * 60", expr)
        # The 6h restart lookback is still the "repeatedly" signal.
        self.assertIn("kube_pod_container_status_restarts_total[6h]", expr)


if __name__ == "__main__":
    unittest.main()
