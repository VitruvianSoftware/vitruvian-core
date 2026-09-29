#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Thanos components must have sufficient memory headroom to avoid OOM kills.

The Querier merges series and dedupes across sidecars and storegateways,
the StoreGateway caches block indexes, and the Compactor processes blocks.
Limits below 2Gi cause flapping and OOM kills under load.
"""

import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def load_values():
    with open(os.path.join(HERE, "applicationset.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (appset,) = [d for d in docs if d["kind"] == "ApplicationSet"]
    return yaml.safe_load(
        appset["spec"]["template"]["spec"]["source"]["helm"]["values"]
    )


class ThanosValuesTest(unittest.TestCase):
    def setUp(self):
        self.v = load_values()

    def test_query_memory_limit(self):
        lim = self.v.get("query", {}).get("resources", {}).get("limits", {}).get("memory")
        self.assertEqual(lim, "2Gi")

    def test_storegateway_memory_limit(self):
        lim = self.v.get("storegateway", {}).get("resources", {}).get("limits", {}).get("memory")
        self.assertEqual(lim, "2Gi")

    def test_compactor_memory_limit(self):
        lim = self.v.get("compactor", {}).get("resources", {}).get("limits", {}).get("memory")
        self.assertEqual(lim, "2Gi")


if __name__ == "__main__":
    unittest.main()
