#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""CI pipelines dashboard: smoke-test runs never show up.

//tools/gitops:cicd-telemetry-smoke sends events whose workflow is named
"cicd-telemetry smoke <run id>" (one unique name per run, so the gate can
prove it saw THIS run). Every query and the workflow dropdown must exclude
them, or each smoke run adds a fake workflow to the charts.
"""

import json
import os
import sys
from pathlib import Path

EXCLUDE = 'cicd_pipeline_name!~"cicd-telemetry smoke.*"'


def find() -> Path:
    here = Path(__file__).resolve().parent
    for c in (
        here.parent / "ci-pipelines.json",
        Path(os.getenv("TEST_SRCDIR", ""))
        / "_main/gitops/argocd/platform/grafana-dashboards/ci-pipelines.json",
    ):
        if c.is_file():
            return c
    raise FileNotFoundError("ci-pipelines.json")


def main() -> int:
    d = json.loads(find().read_text())
    failures = []
    for p in d["panels"]:
        for t in p.get("targets", []):
            if "expr" in t and EXCLUDE not in t["expr"]:
                failures.append(f"panel {p.get('title')!r} ({t['refId']})")
    for v in d["templating"]["list"]:
        q = v.get("query")
        q = q.get("query", "") if isinstance(q, dict) else (q or "")
        if v["name"] == "workflow" and EXCLUDE not in q:
            failures.append("variable 'workflow'")
    for f in failures:
        print(f"FAIL  smoke runs not excluded: {f}")
    print(
        f"{'PASS' if not failures else 'FAIL'}  ci-pipelines smoke exclusion ({len(failures)} missing)"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
