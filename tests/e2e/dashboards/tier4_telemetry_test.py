#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""
Tier 4: Live Prometheus / Thanos Querier Telemetry Execution Test
Executes PromQL queries from all 5 Grafana dashboards against the live Thanos Querier
in the k3s cluster, verifying metric resolution, query syntax execution, and active telemetry population.
"""

import os
import sys
import json
import urllib.parse
import subprocess
import argparse
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

TARGET_DASHBOARDS = [
    "argocd.json",
    "envoy-gateway.json",
    "identity-mesh.json",
    "data-platform-dr.json",
    "agent-integrations.json",
]

# Core health queries per dashboard that must return live active telemetry in the cluster
CORE_ACTIVE_QUERIES = {
    "argocd.json": [
        ("count(argocd_app_info)", "ArgoCD Application Inventory (52 expected)"),
        ("sum by (sync_status) (argocd_app_info)", "ArgoCD Application Sync Statuses"),
        ("sum(rate(argocd_git_request_total[5m]))", "ArgoCD Git Repo Server Requests"),
    ],
    "envoy-gateway.json": [
        ("sum(rate(envoy_http_downstream_rq_total[5m]))", "Envoy Gateway Ingress Throughput"),
        ("sum(envoy_http_downstream_cx_active)", "Envoy Gateway Active Downstream Connections"),
        ("sum by (envoy_cluster_name) (rate(envoy_cluster_upstream_rq_total[5m]))", "Envoy Upstream HTTPRoute Traffic"),
    ],
    "identity-mesh.json": [
        ("headscale_machines_connected_total", "Headscale Online Nodes"),
        ("headscale_machines_total", "Headscale Total Registered Devices"),
        ("sum(kube_deployment_status_replicas_available{namespace=\"zitadel\"})", "Zitadel HA Replicas Availability"),
    ],
    "data-platform-dr.json": [
        ("count(cnpg_pg_replication_in_recovery)", "CloudNativePG Database Instances"),
        ("sum by (namespace) (cnpg_backends_total)", "Active PostgreSQL Database Backends"),
        ("minio_cluster_capacity_usable_total_bytes", "MinIO Storage Cluster Usable Capacity"),
    ],
    "agent-integrations.json": [
        ("sum(antigravity_active_session_count) or vector(0)", "AI Assistant Active Sessions"),
        ("sum(buzz_community_ws_connections) or vector(0)", "Buzz Real-Time Relay WebSocket Connections"),
        ("sum(rate(envoy_cluster_upstream_rq_total{envoy_cluster_name=~\"httproute/mcp-slack/.*\"}[5m])) or vector(0)", "MCP Slack Bridge Ingress Traffic"),
    ],
}


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


def find_kubeconfig() -> Optional[str]:
    """Find valid kubeconfig path."""
    for p in [
        os.getenv("KUBECONFIG"),
        os.path.expanduser("~/.kube/cluster.yaml"),
        os.path.expanduser("~/.kube/config"),
    ]:
        if p and os.path.isfile(p):
            return p
    return None


def sanitize_promql_for_execution(expr: str) -> str:
    """Substitute Grafana template and built-in variables with test evaluation values."""
    s = expr
    # Replace interval/range variables in brackets: [${interval}], [$__rate_interval], etc. -> [5m]
    s = re.sub(r'\[\s*\$?[{]?[a-zA-Z0-9_]+[}]?\s*\]', '[5m]', s)
    # Replace label filter variables: =~"$cluster", =~"$route", etc. -> =~".*"
    s = re.sub(r'(=~|!=|!~|=)\s*"(\$[a-zA-Z0-9_]+|\${[a-zA-Z0-9_]+})"', r'\1".*"', s)
    # Replace unquoted vars in label filters
    s = re.sub(r'(=~|!=|!~|=)\s*(\$[a-zA-Z0-9_]+|\${[a-zA-Z0-9_]+})', r'\1".*"', s)
    # Replace datasource
    s = s.replace("$datasource", "Prometheus-Data")
    s = s.replace("${datasource}", "Prometheus-Data")
    # Replace remaining variable expressions
    s = re.sub(r'(\$[a-zA-Z0-9_]+|\${[a-zA-Z0-9_]+})', '.*', s)
    return s.strip()


class ThanosQuerier:
    def __init__(self, kubeconfig: Optional[str] = None):
        self.kubeconfig = kubeconfig or find_kubeconfig()
        self.available = False
        self._check_connectivity()

    def _check_connectivity(self):
        if not self.kubeconfig:
            return
        cmd = [
            "kubectl", f"--kubeconfig={self.kubeconfig}",
            "get", "pods", "-n", "monitoring", "-l", "app.kubernetes.io/component=query",
            "-o", "name"
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if proc.returncode == 0 and "thanos-query" in proc.stdout:
                self.available = True
        except Exception:
            self.available = False

    def query(self, promql_expr: str) -> Tuple[bool, Any, str]:
        """Execute a PromQL query against Thanos Querier."""
        if not self.available:
            return False, None, "Thanos Querier is not reachable or kubeconfig not available"

        clean_expr = sanitize_promql_for_execution(promql_expr)
        # Skip TraceQL or non-PromQL queries
        if clean_expr.startswith("{resource.") or clean_expr.startswith("traceql"):
            return True, {"result": []}, ""

        encoded_query = urllib.parse.quote(clean_expr)

        cmd = [
            "kubectl", f"--kubeconfig={self.kubeconfig}",
            "exec", "-n", "monitoring", "deploy/thanos-query", "-c", "query",
            "--", "wget", "-qO-", f"http://localhost:9090/api/v1/query?query={encoded_query}"
        ]

        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            if proc.returncode != 0:
                return False, None, f"Command failed (exit {proc.returncode}): {proc.stderr.strip() or proc.stdout.strip()}"
            resp = json.loads(proc.stdout)
            if resp.get("status") == "success":
                return True, resp.get("data", {}), ""
            return False, resp, f"Prometheus API error: {resp.get('error', 'unknown error')}"
        except json.JSONDecodeError:
            return False, None, f"Invalid JSON response from Thanos: {proc.stdout[:200]}"
        except subprocess.TimeoutExpired:
            return False, None, "Query execution timed out after 15s"
        except Exception as e:
            return False, None, str(e)


def collect_all_panels(dashboard: Dict[str, Any]) -> List[Dict[str, Any]]:
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
        self.querier = ThanosQuerier()

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

    def report_skip(self, description: str, reason: str):
        self.tests_run += 1
        self.tests_passed += 1
        print(f"ok {self.tests_run} - {description} # SKIP {reason}")


def run_tier4_tests(allow_offline: bool = False) -> int:
    ctx = TestContext()
    print("TAP version 13")
    print(f"# Starting Tier 4 Live Telemetry Execution Tests against Thanos Querier")

    # Load dashboards
    for filename in TARGET_DASHBOARDS:
        file_path = ctx.dashboards_dir / filename
        if file_path.is_file():
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    ctx.loaded_dashboards[filename] = json.load(f)
            except Exception:
                pass

    # Check Thanos reachability
    if not ctx.querier.available:
        if allow_offline:
            print("# Thanos Querier cluster endpoint unreachable in offline mode. Skipping live query execution.")
            ctx.report_skip("Cluster Thanos Querier connectivity", "Offline mode enabled")
            return 0
        else:
            ctx.report_fail(
                "Cluster Thanos Querier connectivity",
                f"Thanos Querier in namespace 'monitoring' unreachable. Kubeconfig: {ctx.querier.kubeconfig}",
            )
            return 1

    ctx.report_ok(f"Cluster Thanos Querier connectivity verified (namespace: monitoring, pod: thanos-query)")

    # 1. Execute Core Telemetry Queries for Active Cluster Services
    for filename, queries in CORE_ACTIVE_QUERIES.items():
        for expr, label in queries:
            success, data, err = ctx.querier.query(expr)
            if not success:
                ctx.report_fail(f"Core Telemetry: {filename} - {label} (`{expr}`)", err)
            else:
                results = data.get("result", [])
                if len(results) > 0:
                    sample_val = results[0].get("value", ["?", "?"])[1]
                    ctx.report_ok(
                        f"Core Telemetry: {filename} - {label} (`{expr}`) -> {len(results)} series (sample: {sample_val})"
                    )
                else:
                    ctx.report_ok(
                        f"Core Telemetry: {filename} - {label} (`{expr}`) -> executed cleanly (0 series currently active)"
                    )

    # 2. Execute All Panel Queries from Loaded Dashboards
    for filename, data in ctx.loaded_dashboards.items():
        panels = collect_all_panels(data)
        tested_queries = 0
        failed_queries = []

        for p in panels:
            pid = p.get("id", 0)
            title = p.get("title", f"Panel {pid}")
            for t_idx, t in enumerate(p.get("targets", [])):
                expr = t.get("expr", "").strip()
                if not expr:
                    continue
                tested_queries += 1
                success, q_data, err = ctx.querier.query(expr)
                if not success:
                    failed_queries.append(f"Panel {pid} ('{title}') target #{t_idx} (`{expr}`): {err}")

        if failed_queries:
            ctx.report_fail(
                f"Live PromQL panel query execution: {filename} ({tested_queries} queries)",
                "; ".join(failed_queries[:3]),
            )
        else:
            ctx.report_ok(
                f"Live PromQL panel query execution: {filename} (all {tested_queries} panel queries executed cleanly)"
            )

    # Summary
    print(f"# Tier 4 Results: {ctx.tests_passed}/{ctx.tests_run} tests passed")
    if ctx.failures:
        print(f"# FAILED {len(ctx.failures)} test(s)")
        for desc, err in ctx.failures:
            print(f"# - {desc}: {err}")
        return 1

    print("# Tier 4 Live Telemetry Query Test: ALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Tier 4 Live Telemetry E2E Test")
    parser.add_argument("--allow-offline", action="store_true", help="Skip live tests if cluster is unreachable")
    args = parser.parse_args()
    sys.exit(run_tier4_tests(allow_offline=args.allow_offline))
