#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Tempo must not split traces across replicas, or lose them on a restart.

Tempo here is the single-binary chart. Its pods do not share a ring (no
memberlist peers), so with 2 replicas each write landed on one pod and each
search saw only one pod's recent data: 18/50 lookups via the Service found a
trace sent seconds earlier (measured 2026-09-29). And the WAL lived in the
container's scratch layer, so a restart lost every unflushed trace.
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


class TempoValuesTest(unittest.TestCase):
    def setUp(self):
        self.v = load_values()

    def test_single_replica_unless_pods_share_a_ring(self):
        joined = (self.v.get("tempo", {}).get("memberlist") or {}).get("join_members")
        if not joined:
            self.assertEqual(self.v.get("replicas", 1), 1)

    def test_flushes_to_backend_on_shutdown(self):
        ing = self.v["tempo"].get("ingester") or {}
        self.assertIs(ing.get("flush_all_on_shutdown"), True)

    def test_wal_is_on_a_volume(self):
        mounts = {
            m["mountPath"]: m["name"]
            for m in self.v["tempo"].get("extraVolumeMounts", [])
        }
        self.assertIn("/var/tempo", mounts)
        vols = {v["name"] for v in self.v.get("extraVolumes", [])}
        self.assertIn(mounts["/var/tempo"], vols)


if __name__ == "__main__":
    unittest.main()
