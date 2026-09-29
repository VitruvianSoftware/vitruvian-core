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
import re
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
                failures.append(
                    f"smoke runs not excluded: panel {p.get('title')!r} ({t['refId']})"
                )
    for p in d["panels"]:
        for t in p.get("targets", []):
            e = t.get("expr", "")
            # rate()/increase() drop a series' first observation, and every
            # collector restart starts new series (new collector_instance_id),
            # so with sparse CI data they undercount. Panels use
            # max_over_time(x[W]) - (x offset W or ... * 0): exact per series,
            # and a pod that died inside the window still counts.
            if "cicd_" in e and ("rate(" in e or "increase(" in e):
                failures.append(f"panel {p.get('title')!r} uses rate()/increase()")
            if "cicd_" in e and "max_over_time(" not in e:
                failures.append(
                    f"panel {p.get('title')!r} drops restarted pods' counts"
                )
            # Job/queue/step spans carry the JOB name in cicd_pipeline_name
            # (the receiver doesn't pass the workflow name on), so filtering
            # them by $workflow empties the panel for any real selection.
            if "$workflow" in e and any(
                f'ci_span_type="{k}"' in e for k in ("job", "queue", "step")
            ):
                failures.append(
                    f"panel {p.get('title')!r} filters job/step spans by workflow"
                )
            # A p95 over whole runs must be per workflow: pooling every
            # workflow's runs mixes 30s lint runs with 30min builds, and the
            # number matches no real wait (the merge-queue panel said ~10min
            # while its slowest workflow's p95 was ~30min).
            if (
                "histogram_quantile(" in e
                and 'ci_span_type="run"' in e
                and not re.search(r"sum by \([^)]*cicd_pipeline_name", e)
            ):
                failures.append(
                    f"panel {p.get('title')!r} pools every workflow into one p95"
                )
            # Failure rate: failed / (succeeded + failed). Skipped/cancelled
            # runs must not dilute it.
            if (
                p.get("title") == "Failure rate by workflow"
                and "STATUS_CODE_OK|STATUS_CODE_ERROR" not in e
            ):
                failures.append(
                    "failure rate denominator includes skipped/cancelled runs"
                )
    for v in d["templating"]["list"]:
        q = v.get("query")
        q = q.get("query", "") if isinstance(q, dict) else (q or "")
        if v["name"] == "workflow" and EXCLUDE not in q:
            failures.append("smoke runs not excluded: variable 'workflow'")
    for f in failures:
        print(f"FAIL  {f}")
    print(
        f"{'PASS' if not failures else 'FAIL'}  ci-pipelines checks ({len(failures)} problems)"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
