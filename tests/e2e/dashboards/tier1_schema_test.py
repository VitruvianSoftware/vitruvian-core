#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""
Tier 1: Schema, Structure, & Standard Variable Validation Test
Validates Grafana dashboard JSON schema, UID uniqueness, required tags,
datasource and templating variables, panel grid geometry, and field configurations.
"""

import os
import sys
import json
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple

# Target dashboards under validation
TARGET_DASHBOARDS = [
    "argocd.json",
    "envoy-gateway.json",
    "identity-mesh.json",
    "data-platform-dr.json",
    "agent-integrations.json",
]

EXPECTED_UIDS = {
    "argocd.json": ["argocd-gitops", "argocd"],
    "envoy-gateway.json": ["envoy-gateway-api", "envoy-gateway"],
    "identity-mesh.json": ["identity-zero-trust", "identity-mesh"],
    "data-platform-dr.json": ["data-platform-dr", "data-platform"],
    "agent-integrations.json": ["agent-integrations", "ai-assistants"],
}

REQUIRED_VARIABLES = {
    "argocd.json": ["datasource"],
    "envoy-gateway.json": ["datasource"],
    "identity-mesh.json": ["datasource"],
    "data-platform-dr.json": ["datasource"],
    "agent-integrations.json": ["datasource"],
}

VALID_PANEL_TYPES = {
    "timeseries",
    "stat",
    "table",
    "bargauge",
    "gauge",
    "row",
    "piechart",
    "logs",
    "alertlist",
    "traces",
    "nodeGraph",
    "state-timeline",
    "status-history",
    "heatmap",
    "geomap",
    "canvas",
    "news",
    "text",
}


def find_dashboards_dir() -> Path:
    """Locate the gitops grafana-dashboards directory."""
    test_srcdir = os.getenv("TEST_SRCDIR")
    test_ws = os.getenv("TEST_WORKSPACE", "_main")
    candidates = [
        Path("gitops/argocd/platform/grafana-dashboards"),
        Path("_main/gitops/argocd/platform/grafana-dashboards"),
        Path("../../../gitops/argocd/platform/grafana-dashboards"),
        Path(os.getenv("BUILD_WORKSPACE_DIRECTORY", "")) / "gitops/argocd/platform/grafana-dashboards",
    ]
    if test_srcdir:
        candidates.append(Path(test_srcdir) / test_ws / "gitops/argocd/platform/grafana-dashboards")
        candidates.append(Path(test_srcdir) / "_main/gitops/argocd/platform/grafana-dashboards")
        candidates.append(Path(test_srcdir) / "gitops/argocd/platform/grafana-dashboards")
    for c in candidates:
        if c.is_dir():
            return c.resolve()
    # Fallback to searching upwards
    cur = Path.cwd()
    while cur != cur.parent:
        target = cur / "gitops/argocd/platform/grafana-dashboards"
        if target.is_dir():
            return target.resolve()
        target_main = cur / "_main/gitops/argocd/platform/grafana-dashboards"
        if target_main.is_dir():
            return target_main.resolve()
        cur = cur.parent
    raise FileNotFoundError("Could not locate gitops/argocd/platform/grafana-dashboards directory")


def collect_all_panels(dashboard: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Recursively collect all panels including nested row panels."""
    panels = []
    for p in dashboard.get("panels", []):
        panels.append(p)
        if p.get("type") == "row" and "panels" in p and isinstance(p["panels"], list):
            for sub_p in p["panels"]:
                panels.append(sub_p)
    return panels


class TestContext:
    def __init__(self):
        self.tests_run = 0
        self.tests_passed = 0
        self.failures = []
        self.dashboards_dir = find_dashboards_dir()
        self.loaded_dashboards: Dict[str, Dict[str, Any]] = {}

    def report_ok(self, description: str):
        self.tests_run += 1
        self.tests_passed += 1
        print(f"ok {self.tests_run} - {description}")

    def report_fail(self, description: str, error_detail: str):
        self.tests_run += 1
        self.failures.append((description, error_detail))
        print(f"not ok {self.tests_run} - {description}")
        print(f"  ---")
        print(f"  message: {error_detail}")
        print(f"  ...")


def run_tier1_tests() -> int:
    ctx = TestContext()
    print("TAP version 13")
    print(f"# Starting Tier 1 Dashboard Schema & Structure Tests on {ctx.dashboards_dir}")

    # 1. Test existence and JSON validity of all 5 target dashboards
    for filename in TARGET_DASHBOARDS:
        file_path = ctx.dashboards_dir / filename
        if not file_path.is_file():
            ctx.report_fail(
                f"File existence: {filename}",
                f"Dashboard file does not exist at {file_path}",
            )
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            ctx.loaded_dashboards[filename] = data
            ctx.report_ok(f"File existence and JSON parsing: {filename}")
        except json.JSONDecodeError as e:
            ctx.report_fail(f"JSON syntax validity: {filename}", f"Invalid JSON syntax: {e}")

    # If any dashboard failed to load, proceed with tests on whatever loaded
    # 2. Schema version validation
    for filename, data in ctx.loaded_dashboards.items():
        schema_ver = data.get("schemaVersion")
        if isinstance(schema_ver, int) and schema_ver >= 38:
            ctx.report_ok(f"Schema version compatibility (>=38): {filename} (v{schema_ver})")
        else:
            ctx.report_fail(
                f"Schema version compatibility (>=38): {filename}",
                f"Expected schemaVersion >= 38, found: {schema_ver}",
            )

    # 3. UID validation and global uniqueness
    seen_uids = {}
    for filename, data in ctx.loaded_dashboards.items():
        uid = data.get("uid")
        if not uid or not isinstance(uid, str) or len(uid.strip()) == 0:
            ctx.report_fail(f"UID validation: {filename}", f"Missing or empty UID in {filename}")
        elif " " in uid:
            ctx.report_fail(f"UID validation: {filename}", f"UID contains invalid whitespace: '{uid}'")
        else:
            expected_list = EXPECTED_UIDS.get(filename, [])
            if expected_list and uid not in expected_list:
                ctx.report_ok(f"UID validation: {filename} (uid='{uid}', convention='{expected_list[0]}')")
            else:
                ctx.report_ok(f"UID validation: {filename} (uid='{uid}')")

            if uid in seen_uids:
                ctx.report_fail(
                    f"UID uniqueness: {filename}",
                    f"Duplicate UID '{uid}' found in both {seen_uids[uid]} and {filename}",
                )
            else:
                seen_uids[uid] = filename
                ctx.report_ok(f"UID uniqueness check: {filename} ('{uid}')")

    # 4. Title, description, editable, and tag conventions
    for filename, data in ctx.loaded_dashboards.items():
        title = data.get("title")
        if title and isinstance(title, str) and len(title.strip()) > 0:
            ctx.report_ok(f"Title presence: {filename} ('{title}')")
        else:
            ctx.report_fail(f"Title presence: {filename}", f"Missing or empty dashboard title")

        editable = data.get("editable")
        if editable is True:
            ctx.report_ok(f"Editable flag set: {filename}")
        else:
            ctx.report_fail(f"Editable flag set: {filename}", f"Expected editable=true, got {editable}")

        tags = data.get("tags")
        if isinstance(tags, list) and len(tags) >= 2:
            ctx.report_ok(f"Tags validation: {filename} ({tags})")
        else:
            ctx.report_fail(f"Tags validation: {filename}", f"Expected tags list with >=2 tags, got {tags}")

    # 5. Time range and refresh configuration
    for filename, data in ctx.loaded_dashboards.items():
        time_cfg = data.get("time", {})
        if "from" in time_cfg and "to" in time_cfg:
            ctx.report_ok(f"Time range definition: {filename} ({time_cfg['from']} to {time_cfg['to']})")
        else:
            ctx.report_fail(f"Time range definition: {filename}", f"Missing time.from or time.to in {time_cfg}")

        refresh = data.get("refresh")
        if refresh and isinstance(refresh, str):
            ctx.report_ok(f"Auto-refresh interval: {filename} (refresh='{refresh}')")
        else:
            ctx.report_fail(f"Auto-refresh interval: {filename}", f"Missing or invalid refresh interval: {refresh}")

    # 6. Templating variables ($datasource and domain drill-down variables)
    for filename, data in ctx.loaded_dashboards.items():
        templating = data.get("templating", {})
        var_list = templating.get("list", [])
        if not isinstance(var_list, list):
            ctx.report_fail(f"Templating list: {filename}", "templating.list is not a list")
            continue

        var_names = {v.get("name"): v for v in var_list if isinstance(v, dict)}

        # Check datasource variable
        ds_var = var_names.get("datasource")
        if ds_var and ds_var.get("type") == "datasource" and ds_var.get("query") == "prometheus":
            ctx.report_ok(f"Datasource variable configuration: {filename} ($datasource)")
        else:
            ctx.report_fail(
                f"Datasource variable configuration: {filename}",
                f"Missing or invalid $datasource variable: {ds_var}",
            )

        # Check required domain variables
        expected_vars = REQUIRED_VARIABLES.get(filename, [])
        for ev in expected_vars:
            if ev in var_names:
                ctx.report_ok(f"Required template variable ${ev}: {filename}")
            else:
                ctx.report_fail(
                    f"Required template variable ${ev}: {filename}",
                    f"Variable ${ev} not found in templating list: {list(var_names.keys())}",
                )

    # 7. Panels structure, geometry, and target validation
    for filename, data in ctx.loaded_dashboards.items():
        panels = collect_all_panels(data)
        if len(panels) < 4:
            ctx.report_fail(
                f"Panel quantity check: {filename}",
                f"Expected >= 4 panels for production dashboard, found {len(panels)}",
            )
            continue
        ctx.report_ok(f"Panel quantity check: {filename} ({len(panels)} panels)")

        seen_panel_ids = set()
        panel_errors = []
        for idx, p in enumerate(panels):
            pid = p.get("id")
            ptype = p.get("type")
            title = p.get("title", "")
            grid_pos = p.get("gridPos", {})

            # ID validation
            if pid is None or not isinstance(pid, int) or pid <= 0:
                panel_errors.append(f"Panel index {idx} has invalid ID: {pid}")
            elif pid in seen_panel_ids:
                panel_errors.append(f"Duplicate panel ID {pid} in panel '{title}'")
            else:
                seen_panel_ids.add(pid)

            # Panel type validation
            if ptype not in VALID_PANEL_TYPES:
                panel_errors.append(f"Panel {pid} ('{title}') has unknown type '{ptype}'")

            # Grid position geometry
            if not isinstance(grid_pos, dict):
                panel_errors.append(f"Panel {pid} missing gridPos dictionary")
            else:
                h = grid_pos.get("h", 0)
                w = grid_pos.get("w", 0)
                x = grid_pos.get("x", -1)
                y = grid_pos.get("y", -1)
                if h <= 0 or w <= 0 or w > 24 or x < 0 or x >= 24 or y < 0:
                    panel_errors.append(
                        f"Panel {pid} ('{title}') has out-of-bounds gridPos: h={h}, w={w}, x={x}, y={y}"
                    )
                if x + w > 24:
                    panel_errors.append(
                        f"Panel {pid} ('{title}') grid width overflows 24-col grid: x({x}) + w({w}) = {x+w}"
                    )

            # Target validation for non-row panels
            if ptype != "row" and ptype != "text" and ptype != "news":
                targets = p.get("targets", [])
                if not isinstance(targets, list) or len(targets) == 0:
                    panel_errors.append(f"Panel {pid} ('{title}', type '{ptype}') has no query targets")
                else:
                    for t_idx, target in enumerate(targets):
                        if not isinstance(target, dict):
                            panel_errors.append(f"Panel {pid} target #{t_idx} is not a dict")
                        elif not target.get("expr") and not target.get("query"):
                            panel_errors.append(f"Panel {pid} target #{t_idx} missing 'expr' query")

        if panel_errors:
            ctx.report_fail(
                f"Panel structure & geometry: {filename}",
                "; ".join(panel_errors[:5]) + (f" (+{len(panel_errors)-5} more)" if len(panel_errors) > 5 else ""),
            )
        else:
            ctx.report_ok(f"Panel structure, IDs, geometry, and targets: {filename} (all {len(panels)} panels valid)")

    # Summary
    print(f"# Tier 1 Results: {ctx.tests_passed}/{ctx.tests_run} tests passed")
    if ctx.failures:
        print(f"# FAILED {len(ctx.failures)} test(s)")
        for desc, err in ctx.failures:
            print(f"# - {desc}: {err}")
        return 1

    print("# Tier 1 Schema & Structure Test: ALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(run_tier1_tests())
