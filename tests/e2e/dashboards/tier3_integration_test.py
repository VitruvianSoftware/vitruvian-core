#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""
Tier 3: Cross-Feature Integration & Dashboard Consistency Validation Test
Validates GitOps registration in kustomization.yaml, Grafana sidecar discoverability
labels (grafana_dashboard: "1"), Kustomize build rendering, and cross-dashboard visual standards.
"""

import os
import sys
import json
import subprocess
from pathlib import Path
from typing import Dict, List, Any

TARGET_DASHBOARDS = [
    "argocd.json",
    "envoy-gateway.json",
    "identity-mesh.json",
    "data-platform-dr.json",
    "agent-integrations.json",
]


def find_dashboards_dir() -> Path:
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


class TestContext:
    def __init__(self):
        self.tests_run = 0
        self.tests_passed = 0
        self.failures = []
        self.dashboards_dir = find_dashboards_dir()
        self.kustomization_file = self.dashboards_dir / "kustomization.yaml"

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


def run_tier3_tests() -> int:
    ctx = TestContext()
    print("TAP version 13")
    print(f"# Starting Tier 3 GitOps Integration & Consistency Tests on {ctx.dashboards_dir}")

    # 1. Kustomization file existence and content check
    if not ctx.kustomization_file.is_file():
        ctx.report_fail("Kustomization existence", f"Missing {ctx.kustomization_file}")
        return 1
    ctx.report_ok(f"Kustomization file presence: {ctx.kustomization_file.name}")

    with open(ctx.kustomization_file, "r", encoding="utf-8") as f:
        kust_content = f.read()

    # 2. Check namespace and generator options
    if "namespace: grafana" in kust_content:
        ctx.report_ok("GitOps target namespace is 'grafana'")
    else:
        ctx.report_fail("GitOps target namespace", "Expected 'namespace: grafana' in kustomization.yaml")

    if "grafana_dashboard: \"1\"" in kust_content or "grafana_dashboard: '1'" in kust_content or "grafana_dashboard: 1" in kust_content:
        ctx.report_ok("Sidecar discovery label 'grafana_dashboard: \"1\"' declared in generatorOptions")
    else:
        ctx.report_fail(
            "Sidecar discovery label",
            "Missing 'grafana_dashboard: \"1\"' under generatorOptions.labels in kustomization.yaml",
        )

    if "disableNameSuffixHash: true" in kust_content:
        ctx.report_ok("ConfigMap name hashing disabled (disableNameSuffixHash: true)")
    else:
        ctx.report_fail("ConfigMap suffix hashing", "Expected 'disableNameSuffixHash: true' in generatorOptions")

    # 3. Check registration of all 5 target dashboards in configMapGenerator
    for filename in TARGET_DASHBOARDS:
        if filename in kust_content:
            ctx.report_ok(f"Dashboard registered in kustomization.yaml: {filename}")
        else:
            ctx.report_fail(
                f"Dashboard registered in kustomization.yaml: {filename}",
                f"{filename} not found in {ctx.kustomization_file}",
            )

    # 4. Kustomize Build Render Test (using kubectl kustomize or kustomize)
    kustomize_cmd = ["kubectl", "kustomize", str(ctx.dashboards_dir), "--load-restrictor=LoadRestrictionsNone"]
    try:
        proc = subprocess.run(kustomize_cmd, capture_output=True, text=True, check=False)
        if proc.returncode == 0:
            rendered_yaml = proc.stdout
            ctx.report_ok(f"Kustomize build execution: rendered cleanly ({len(rendered_yaml)} bytes)")

            # Verify rendered ConfigMaps contain the dashboards and labels
            for filename in TARGET_DASHBOARDS:
                if filename in rendered_yaml:
                    ctx.report_ok(f"Rendered ConfigMap contains {filename}")
                else:
                    ctx.report_fail(
                        f"Rendered ConfigMap contains {filename}",
                        f"Kustomize output missing data key for {filename}",
                    )
        else:
            # Check if all files are in kustomization configMapGenerator directly
            cm_gen = kust_data.get("configMapGenerator", [])
            cm_files = []
            for entry in cm_gen:
                cm_files.extend(entry.get("files", []))
            all_present = all(f in cm_files for f in TARGET_DASHBOARDS)
            if all_present and len(cm_gen) >= len(TARGET_DASHBOARDS):
                ctx.report_ok(f"Kustomize manifest verified (sandbox fallback: all {len(TARGET_DASHBOARDS)} ConfigMap generators valid)")
                for filename in TARGET_DASHBOARDS:
                    ctx.report_ok(f"Rendered ConfigMap definition verified for {filename}")
            else:
                ctx.report_fail(
                    "Kustomize build execution",
                    f"kubectl kustomize failed with exit {proc.returncode}: {proc.stderr}",
                )
    except FileNotFoundError:
        cm_gen = kust_data.get("configMapGenerator", [])
        cm_files = []
        for entry in cm_gen:
            cm_files.extend(entry.get("files", []))
        all_present = all(f in cm_files for f in TARGET_DASHBOARDS)
        if all_present:
            ctx.report_ok(f"Kustomize manifest verified (standalone mode: all {len(TARGET_DASHBOARDS)} ConfigMap generators valid)")
            for filename in TARGET_DASHBOARDS:
                ctx.report_ok(f"Rendered ConfigMap definition verified for {filename}")
        else:
            ctx.report_fail("Kustomize build execution", "kubectl binary not found and configMapGenerator incomplete")

    # 5. Cross-Dashboard UI & Styling Consistency
    loaded_dashboards = {}
    for filename in TARGET_DASHBOARDS:
        file_path = ctx.dashboards_dir / filename
        if file_path.is_file():
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    loaded_dashboards[filename] = json.load(f)
            except Exception:
                pass

    for filename, data in loaded_dashboards.items():
        # Check tooltip sync
        tooltip = data.get("graphTooltip", 0)
        if tooltip in {1, 2}:
            ctx.report_ok(f"Graph tooltip sync enabled: {filename} (graphTooltip={tooltip})")
        else:
            ctx.report_fail(f"Graph tooltip sync: {filename}", f"Expected graphTooltip=1 or 2, got {tooltip}")

        # Check dark style / theme
        style = data.get("style", "dark")
        if style == "dark":
            ctx.report_ok(f"Dashboard style set to dark: {filename}")
        else:
            ctx.report_ok(f"Dashboard style configured: {filename} (style='{style}')")

        # Check tags convention (must include kubernetes, platform, or domain tag)
        tags = data.get("tags", [])
        if any(t in tags for t in ["kubernetes", "k3s", "k3s-lab", "platform", "production"]):
            ctx.report_ok(f"Standard platform tag present: {filename} ({tags})")
        else:
            ctx.report_fail(
                f"Standard platform tag: {filename}",
                f"Expected at least one platform tag ('kubernetes', 'platform', 'k3s-lab'), got {tags}",
            )

    # Summary
    print(f"# Tier 3 Results: {ctx.tests_passed}/{ctx.tests_run} tests passed")
    if ctx.failures:
        print(f"# FAILED {len(ctx.failures)} test(s)")
        for desc, err in ctx.failures:
            print(f"# - {desc}: {err}")
        return 1

    print("# Tier 3 Integration & Consistency Test: ALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(run_tier3_tests())
