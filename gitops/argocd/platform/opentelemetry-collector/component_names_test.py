#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""The main collector's config uses current component names only.

otelcol-contrib 0.160 logs these old names as deprecated aliases, and the
chart (0.173.1) only rewrites `otlp` for us "for this release". Once either
drops the alias, the collector fails to start. Same fix as the CI collector
(gitops/argocd/platform/cicd-telemetry, #2571).
"""

import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))

# old type -> new type (component ids may carry a "/name" suffix)
DEPRECATED = {
    "otlp": "otlp_grpc",  # exporter only; the otlp RECEIVER is not renamed
    "otlphttp": "otlp_http",
    "prometheusremotewrite": "prometheus_remote_write",
    "spanmetrics": "span_metrics",
}


def load_config():
    with open(os.path.join(HERE, "applicationset.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (appset,) = [d for d in docs if d["kind"] == "ApplicationSet"]
    values = yaml.safe_load(
        appset["spec"]["template"]["spec"]["source"]["helm"]["values"]
    )
    return values["config"]


class ComponentNamesTest(unittest.TestCase):
    def setUp(self):
        self.cfg = load_config()

    def _ids(self, section):
        return list((self.cfg.get(section) or {}).keys())

    def test_exporters_and_connectors_use_current_names(self):
        for section in ("exporters", "connectors"):
            for cid in self._ids(section):
                typ = cid.split("/")[0]
                self.assertNotIn(
                    typ, DEPRECATED, f"{section}.{cid}: use {DEPRECATED.get(typ)}"
                )

    def test_pipelines_reference_current_names(self):
        for name, p in self.cfg["service"]["pipelines"].items():
            for kind in ("exporters", "receivers"):
                for ref in p.get(kind, []):
                    typ = ref.split("/")[0]
                    if kind == "receivers" and typ == "otlp":
                        continue  # the otlp receiver keeps its name
                    self.assertNotIn(typ, DEPRECATED, f"pipeline {name} {kind}: {ref}")


if __name__ == "__main__":
    unittest.main()
