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


def flag_value(args, name):
    """The integer value of the one --name=value entry in args."""
    values = [a.split("=", 1)[1] for a in args if a.startswith(name + "=")]
    if len(values) != 1:
        raise AssertionError(f"expected exactly one {name}=..., found {values}")
    return int(values[0])


# The Querier's samples cap. The Prometheus sidecar cap must stay above it,
# and ../prometheus/prometheus_values_test.py repeats this number to check
# that. Change both together.
QUERY_SAMPLES_CAP = 12_000_000


class ThanosValuesTest(unittest.TestCase):
    def setUp(self):
        self.v = load_values()

    def test_query_memory_limit(self):
        lim = (
            self.v.get("query", {}).get("resources", {}).get("limits", {}).get("memory")
        )
        self.assertEqual(lim, "2Gi")

    def test_storegateway_memory_limit(self):
        lim = (
            self.v.get("storegateway", {})
            .get("resources", {})
            .get("limits", {})
            .get("memory")
        )
        self.assertEqual(lim, "2Gi")

    def test_compactor_memory_limit(self):
        lim = (
            self.v.get("compactor", {})
            .get("resources", {})
            .get("limits", {})
            .get("memory")
        )
        self.assertEqual(lim, "2Gi")

    # Per-query guardrails. The Querier must refuse a query it cannot serve
    # instead of being OOM-killed by it (2026-09-29 and 2026-10-10).
    def test_query_has_guardrails_and_keeps_log_level(self):
        args = self.v.get("query", {}).get("extraArgs", [])
        # The Go collector runs before the kernel kills the container.
        self.assertIn("--enable-auto-gomemlimit", args)
        # A series cap, a samples cap and a concurrency cap are all set.
        self.assertGreater(flag_value(args, "--store.limits.request-series"), 0)
        self.assertGreater(flag_value(args, "--store.limits.request-samples"), 0)
        self.assertGreater(flag_value(args, "--query.max-concurrent"), 0)
        # extraArgs replaces the chart default list; keep its log level.
        self.assertIn("--log.level=info", args)

    def test_query_checks_the_caps_while_reading(self):
        # Without it the caps fire only after every store's whole answer is
        # in memory: one 7-day select held 1.5 GB before it was refused
        # (2026-10-10).
        args = self.v.get("query", {}).get("extraArgs", [])
        self.assertIn("--grpc.proxy-strategy=lazy", args)

    def test_query_samples_cap_is_the_one_the_sidecar_test_assumes(self):
        args = self.v.get("query", {}).get("extraArgs", [])
        self.assertEqual(
            flag_value(args, "--store.limits.request-samples"), QUERY_SAMPLES_CAP
        )

    def test_query_refuses_before_a_store_truncates(self):
        """The Querier's series cap is strictly below the per-store cap.

        A store that hits its own cap first hands back a cut-off result, and
        the Querier (partial response is on) passes it along as a success
        with a warning: a wrong number. When the Querier's cap is the lower
        one, the query fails outright instead.
        """
        query = flag_value(
            self.v.get("query", {}).get("extraArgs", []),
            "--store.limits.request-series",
        )
        store = flag_value(
            self.v.get("storegateway", {}).get("extraArgs", []),
            "--store.limits.request-series",
        )
        self.assertLess(query, store)

    def test_query_series_cap_is_below_the_select_that_killed_it(self):
        # 86,000 is the size of the select that OOM-killed both Queriers 56
        # times on 2026-10-10: cicd_duration_seconds_bucket{ci_span_type="step"}
        # (86,336 series), read three times by one dashboard panel. Raising
        # the cap past it needs issue #2606 (cut that metric's cardinality)
        # done first; until then that select has to be refused.
        cap = flag_value(
            self.v.get("query", {}).get("extraArgs", []),
            "--store.limits.request-series",
        )
        self.assertLess(cap, 86_000)

    def test_storegateway_has_series_cap_and_memory_guard(self):
        args = self.v.get("storegateway", {}).get("extraArgs", [])
        self.assertIn("--store.limits.request-series=150000", args)
        self.assertIn("--enable-auto-gomemlimit", args)


if __name__ == "__main__":
    unittest.main()
