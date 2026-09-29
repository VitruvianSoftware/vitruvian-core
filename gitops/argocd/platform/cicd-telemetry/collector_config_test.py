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
        dims = [d["name"] for d in self.cfg["connectors"]["span_metrics"]["dimensions"]]
        self.assertEqual(
            dims, ["cicd.pipeline.name", "ci.span.type", "ci.trigger", "ci.retry"]
        )

    def test_duration_buckets_fine_enough_for_ci(self):
        # A percentile is interpolated inside one bucket; with 10m -> 20m a
        # 641s run read as 900s. Between 1m and 60m (where CI runs live) each
        # bucket may be at most 1.5x the previous, so p50/p95 stay within ~25%.
        units = {"s": 1, "m": 60}
        buckets = [
            float(b[:-1]) * units[b[-1]]
            for b in self.cfg["connectors"]["span_metrics"]["histogram"]["explicit"][
                "buckets"
            ]
        ]
        inside = [b for b in buckets if 60 <= b <= 3600]
        for lo, hi in zip(inside, inside[1:]):
            self.assertLessEqual(hi / lo, 1.5, f"bucket gap {lo}s -> {hi}s too wide")

    def _statements(self):
        groups = self.cfg["processors"]["transform/ci-labels"]["trace_statements"]
        return [st for g in groups for st in g["statements"]]

    def test_dependabot_run_names_collapse_per_ecosystem(self):
        # Dependabot names each run "<ecosystem> in <dir> for <deps> - Update
        # #<id>": a new metric series per run, forever (seen live). Collapse to
        # "dependabot <ecosystem>", on the resource AND the run span's name
        # (span_name is a metric label too). Behaviour verified with the real
        # 0.160 collector in docker.
        sts = self._statements()
        self.assertIn(
            r'replace_pattern(resource.attributes["cicd.pipeline.name"], '
            r'"^([a-z_]+) in \\S+ for .*$", "dependabot $$1")',
            sts,
        )
        self.assertIn(
            'set(span.name, resource.attributes["cicd.pipeline.name"]) '
            "where span.kind == SPAN_KIND_SERVER",
            sts,
        )

    def test_ottl_paths_carry_their_context(self):
        # 0.160 rewrites unprefixed paths and logs it; unprefixed paths are on
        # the way out. Every attribute/name/kind reference names its context.
        import re

        for st in self._statements():
            bare = re.findall(r"(?<![\w.])(attributes|name|kind)(?=[\[ ,)])", st)
            self.assertFalse(bare, f"unprefixed path in: {st}")

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

    def test_no_deprecated_component_names(self):
        # 0.160 logs these old aliases as deprecated; they will be removed.
        names = [
            *self.cfg["connectors"],
            *self.cfg["exporters"],
            *self.cfg["receivers"],
        ]
        for old in ("spanmetrics", "prometheusremotewrite", "otlp"):
            self.assertFalse(
                [n for n in names if n.split("/")[0] == old],
                f"deprecated component name {old!r} in use",
            )

    def test_argocd_sees_real_config_changes(self):
        # ServerSideDiff=true on this app hid a REAL config change (#2575's
        # buckets never deployed; Argo CD reported Synced). Proven on a scratch
        # app: with ports declared exactly as the operator's webhook stores
        # them, plain server-side apply stays Synced AND deploys real changes.
        app_path = os.path.join(HERE, "..", "..", "applications", "cicd-telemetry.yaml")
        with open(app_path) as f:
            app = yaml.safe_load(f)
        ann = app["metadata"].get("annotations", {})
        self.assertNotIn(
            "ServerSideDiff=true",
            ann.get("argocd.argoproj.io/compare-options", ""),
        )

    def test_ports_declare_the_webhook_default(self):
        # The webhook adds targetPort: 0 to every port. ports is compared as a
        # whole list, so leaving it out makes Argo CD report drift forever.
        for port in self.col["spec"]["ports"]:
            self.assertIn("targetPort", port, f"port {port['name']} lacks targetPort")

    def test_operator_does_not_write_its_own_network_policy(self):
        self.assertIs(self.col["spec"]["networkPolicy"]["enabled"], False)


if __name__ == "__main__":
    unittest.main()
