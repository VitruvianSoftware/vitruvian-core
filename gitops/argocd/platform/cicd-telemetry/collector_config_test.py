#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Invariants of the CI collector that must never silently regress.

Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
"""

import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    with open(os.path.join(HERE, "collector.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (col,) = [d for d in docs if d["kind"] == "OpenTelemetryCollector"]
    return col


class CollectorConfigTest(unittest.TestCase):
    def setUp(self):
        self.col = load()
        self.cfg = self.col["spec"]["config"]
        self.gh = self.cfg["receivers"]["github"]

    def test_webhook_secret_comes_from_the_required_secret(self):
        # An empty secret makes the receiver accept EVERY request.
        self.assertEqual(self.gh["webhook"]["secret"], "${env:GITHUB_WEBHOOK_SECRET}")
        (env,) = [
            e for e in self.col["spec"]["env"] if e["name"] == "GITHUB_WEBHOOK_SECRET"
        ]
        ref = env["valueFrom"]["secretKeyRef"]
        self.assertEqual(
            (ref["name"], ref["key"]), ("github-otel-webhook", "GITHUB_WEBHOOK_SECRET")
        )
        self.assertIs(ref.get("optional"), False)

    def test_raw_event_bodies_not_attached(self):
        self.assertIs(self.gh["webhook"].get("include_span_events"), False)

    def test_webhook_address(self):
        wh = self.gh["webhook"]
        self.assertEqual((wh["endpoint"], wh["path"]), ("0.0.0.0:19418", "/events"))

    def test_committer_identity_deleted(self):
        acts = self.cfg["processors"]["resource/drop-identity"]["attributes"]
        deleted = {a["key"] for a in acts if a["action"] == "delete"}
        self.assertEqual(
            deleted,
            {"vcs.ref.head.revision.author.name", "vcs.ref.head.revision.author.email"},
        )
        self.assertIn(
            "resource/drop-identity",
            self.cfg["service"]["pipelines"]["traces"]["processors"],
        )

    def test_metric_labels_are_exactly_the_approved_four(self):
        dims = [d["name"] for d in self.cfg["connectors"]["spanmetrics"]["dimensions"]]
        self.assertEqual(
            dims, ["cicd.pipeline.name", "ci.span.type", "ci.trigger", "ci.retry"]
        )

    def test_github_receiver_only_in_traces_pipeline(self):
        # In a metrics pipeline the scraper would start polling GitHub (phase 2).
        pipes = self.cfg["service"]["pipelines"]
        users = [
            name for name, p in pipes.items() if "github" in p.get("receivers", [])
        ]
        self.assertEqual(users, ["traces"])

    def test_survives_one_node_down(self):
        spec = self.col["spec"]
        self.assertEqual(spec["replicas"], 2)
        self.assertEqual(spec["podDisruptionBudget"]["minAvailable"], 1)
        self.assertTrue(
            spec["affinity"]["podAntiAffinity"][
                "requiredDuringSchedulingIgnoredDuringExecution"
            ]
        )

    def test_operator_does_not_write_its_own_network_policy(self):
        self.assertIs(self.col["spec"]["networkPolicy"]["enabled"], False)


if __name__ == "__main__":
    unittest.main()
