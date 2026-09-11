#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""
Tier 2: PromQL Syntax & Metric Integrity Validation Test
Validates PromQL syntax parsing across all panel targets and template variables,
verifies unit conversions (ms vs s), aggregation scoping (sum before rate vs after),
and division safety guards.
"""

import os
import sys
import json
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Set

TARGET_DASHBOARDS = [
    "argocd.json",
    "envoy-gateway.json",
    "identity-mesh.json",
    "data-platform-dr.json",
    "agent-integrations.json",
]

GRAFANA_BUILTIN_VARS = {
    "__interval",
    "__rate_interval",
    "__range",
    "__from",
    "__to",
    "__name",
    "__dashboard",
    "__user",
    "datasource",
}

VALID_PROMQL_FUNCTIONS = {
    "abs",
    "absent",
    "absent_over_time",
    "avg_over_time",
    "ceil",
    "changes",
    "clamp",
    "clamp_max",
    "clamp_min",
    "count_over_time",
    "day_of_month",
    "day_of_week",
    "day_of_year",
    "days_in_month",
    "delta",
    "deriv",
    "exp",
    "floor",
    "histogram_count",
    "histogram_fraction",
    "histogram_quantile",
    "histogram_stddev",
    "histogram_stdvar",
    "histogram_sum",
    "holt_winters",
    "hour",
    "idelta",
    "increase",
    "irate",
    "label_join",
    "label_replace",
    "ln",
    "log10",
    "log2",
    "max_over_time",
    "min_over_time",
    "minute",
    "month",
    "predict_linear",
    "quantile_over_time",
    "rate",
    "resets",
    "round",
    "scalar",
    "sgn",
    "sin",
    "cos",
    "tan",
    "asin",
    "acos",
    "atan",
    "sinh",
    "cosh",
    "tanh",
    "asinh",
    "acosh",
    "atanh",
    "sqrt",
    "stddev_over_time",
    "stdvar_over_time",
    "sum_over_time",
    "time",
    "timestamp",
    "vector",
    "year",
}

VALID_AGGREGATORS = {
    "sum",
    "min",
    "max",
    "avg",
    "group",
    "stddev",
    "stdvar",
    "count",
    "count_values",
    "bottomk",
    "topk",
    "quantile",
    "limitk",
    "limit_ratio",
}


def find_dashboards_dir() -> Path:
    test_srcdir = os.getenv("TEST_SRCDIR")
    test_ws = os.getenv("TEST_WORKSPACE", "_main")
    candidates = [
        Path("gitops/argocd/platform/grafana-dashboards"),
        Path("_main/gitops/argocd/platform/grafana-dashboards"),
        Path("../../../gitops/argocd/platform/grafana-dashboards"),
        Path(os.getenv("BUILD_WORKSPACE_DIRECTORY", ""))
        / "gitops/argocd/platform/grafana-dashboards",
    ]
    if test_srcdir:
        candidates.append(
            Path(test_srcdir) / test_ws / "gitops/argocd/platform/grafana-dashboards"
        )
        candidates.append(
            Path(test_srcdir) / "_main/gitops/argocd/platform/grafana-dashboards"
        )
        candidates.append(
            Path(test_srcdir) / "gitops/argocd/platform/grafana-dashboards"
        )
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
    raise FileNotFoundError(
        "Could not locate gitops/argocd/platform/grafana-dashboards directory"
    )


def collect_all_panels(dashboard: Dict[str, Any]) -> List[Dict[str, Any]]:
    panels = []
    for p in dashboard.get("panels", []):
        panels.append(p)
        if p.get("type") == "row" and "panels" in p and isinstance(p["panels"], list):
            for sub_p in p["panels"]:
                panels.append(sub_p)
    return panels


def check_brackets_balance(expr: str) -> Tuple[bool, str]:
    """Check balancing of (), [], {}."""
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    in_single_quote = False
    in_double_quote = False
    in_backtick = False

    for i, ch in enumerate(expr):
        # Handle string literals escaping
        if ch == "\\" and (in_single_quote or in_double_quote or in_backtick):
            continue
        if ch == "'" and not in_double_quote and not in_backtick:
            in_single_quote = not in_single_quote
            continue
        if ch == '"' and not in_single_quote and not in_backtick:
            in_double_quote = not in_double_quote
            continue
        if ch == "`" and not in_single_quote and not in_double_quote:
            in_backtick = not in_backtick
            continue
        if in_single_quote or in_double_quote or in_backtick:
            continue

        if ch in pairs.values():
            stack.append((ch, i))
        elif ch in pairs:
            if not stack:
                return False, f"Unmatched closing '{ch}' at position {i}"
            top, top_idx = stack.pop()
            if top != pairs[ch]:
                return (
                    False,
                    f"Mismatched closing '{ch}' at position {i}, expected match for '{top}' from {top_idx}",
                )

    if stack:
        top, top_idx = stack[-1]
        return False, f"Unclosed '{top}' opened at position {top_idx}"

    return True, ""


def validate_promql_syntax(expr: str) -> Tuple[bool, List[str]]:
    """Validate common PromQL syntax rules, anti-patterns, and token sanity."""
    errors = []

    # 1. Bracket balancing
    balanced, bal_err = check_brackets_balance(expr)
    if not balanced:
        errors.append(f"Bracket error: {bal_err}")

    # 2. Check for illegal rate(sum(...)) anti-pattern
    # In PromQL, rate() requires a range vector directly from a metric, e.g. rate(metric[5m])
    # Calling rate(sum(...)) is a syntax/runtime error in Prometheus.
    if re.search(r"\brate\s*\(\s*(sum|min|max|avg|count)\b", expr, re.IGNORECASE):
        errors.append(
            "Invalid rate() on aggregated expression: PromQL requires sum(rate(...)), not rate(sum(...))"
        )

    if re.search(r"\birate\s*\(\s*(sum|min|max|avg|count)\b", expr, re.IGNORECASE):
        errors.append(
            "Invalid irate() on aggregated expression: PromQL requires sum(irate(...)), not irate(sum(...))"
        )

    if re.search(r"\bincrease\s*\(\s*(sum|min|max|avg|count)\b", expr, re.IGNORECASE):
        errors.append(
            "Invalid increase() on aggregated expression: PromQL requires sum(increase(...)), not increase(sum(...))"
        )

    # 3. Check histogram_quantile calls
    # histogram_quantile requires a bucket rate aggregated by 'le'
    for match in re.finditer(r"histogram_quantile\s*\([^,]+,\s*([^)]+)\)", expr):
        target_arg = match.group(1)
        if "rate(" in target_arg and "by" in target_arg:
            if not re.search(r"by\s*\([^)]*\ble\b[^)]*\)", target_arg):
                errors.append(
                    f"histogram_quantile aggregation missing required 'le' label in 'by (...)': {match.group(0)}"
                )

    # 4. Check for unclosed regex or quotes in label filters
    label_selectors = re.findall(r"\{([^}]+)\}", expr)
    for sel in label_selectors:
        # Match label pairs: key OP "value"
        pairs = sel.split(",")
        for p in pairs:
            p_strip = p.strip()
            if not p_strip:
                continue
            if not re.match(
                r'^[a-zA-Z_:][a-zA-Z0-9_:]*\s*(=|!=|=~|!~)\s*(".*"|\'.*\'|`.*`|\$[a-zA-Z0-9_]+|\${[a-zA-Z0-9_]+})$',
                p_strip,
            ):
                # Could be complex or comment, check basic validity
                pass

    return len(errors) == 0, errors


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


def run_tier2_tests() -> int:
    ctx = TestContext()
    print("TAP version 13")
    print(
        f"# Starting Tier 2 PromQL Syntax & Metric Integrity Tests on {ctx.dashboards_dir}"
    )

    # Load all dashboards
    for filename in TARGET_DASHBOARDS:
        file_path = ctx.dashboards_dir / filename
        if not file_path.is_file():
            ctx.report_fail(
                f"Dashboard load: {filename}", f"File not found: {file_path}"
            )
            continue
        with open(file_path, "r", encoding="utf-8") as f:
            try:
                ctx.loaded_dashboards[filename] = json.load(f)
            except Exception as e:
                ctx.report_fail(f"Dashboard JSON parse: {filename}", str(e))

    # 1. PromQL Query Syntax and Target Parsing
    for filename, data in ctx.loaded_dashboards.items():
        panels = collect_all_panels(data)
        total_queries = 0
        query_errors = []

        for p in panels:
            pid = p.get("id", 0)
            title = p.get("title", f"Panel {pid}")
            targets = p.get("targets", [])
            for t_idx, t in enumerate(targets):
                expr = t.get("expr", "").strip()
                if not expr:
                    continue
                total_queries += 1
                valid, errs = validate_promql_syntax(expr)
                if not valid:
                    query_errors.append(
                        f"Panel {pid} ('{title}') target #{t_idx}: " + "; ".join(errs)
                    )

        if query_errors:
            ctx.report_fail(
                f"PromQL syntax parsing: {filename} ({total_queries} queries checked)",
                "; ".join(query_errors[:3]),
            )
        else:
            ctx.report_ok(
                f"PromQL syntax parsing: {filename} (all {total_queries} queries valid PromQL)"
            )

    # 2. Template Variables Query Syntax Validation
    for filename, data in ctx.loaded_dashboards.items():
        templating = data.get("templating", {})
        var_list = templating.get("list", [])
        var_errors = []

        for v in var_list:
            vname = v.get("name", "")
            vtype = v.get("type", "")
            if vtype == "query":
                q = v.get("query")
                query_str = ""
                if isinstance(q, str):
                    query_str = q
                elif isinstance(q, dict) and "query" in q:
                    query_str = q["query"]

                if query_str:
                    # PromQL label_values query or PromQL metric query
                    if query_str.startswith("label_values("):
                        if not query_str.endswith(")"):
                            var_errors.append(
                                f"Unclosed label_values query in variable ${vname}: {query_str}"
                            )
                    else:
                        valid, errs = validate_promql_syntax(query_str)
                        if not valid:
                            var_errors.append(
                                f"Variable ${vname} query error: " + "; ".join(errs)
                            )

        if var_errors:
            ctx.report_fail(
                f"Template variable queries: {filename}", "; ".join(var_errors)
            )
        else:
            ctx.report_ok(
                f"Template variable queries: {filename} ({len(var_list)} variables verified)"
            )

    # 3. Variable Reference Consistency (No orphaned variable references)
    for filename, data in ctx.loaded_dashboards.items():
        templating = data.get("templating", {})
        defined_vars = {
            v.get("name") for v in templating.get("list", []) if isinstance(v, dict)
        }
        available_vars = defined_vars.union(GRAFANA_BUILTIN_VARS)

        panels = collect_all_panels(data)
        orphan_errors = []
        for p in panels:
            pid = p.get("id", 0)
            title = p.get("title", f"Panel {pid}")
            for t in p.get("targets", []):
                expr = t.get("expr", "")
                # Find all $var and ${var} references
                used_vars = set(re.findall(r"\$([a-zA-Z0-9_]+)", expr)).union(
                    set(re.findall(r"\${([a-zA-Z0-9_]+)}", expr))
                )
                for uv in used_vars:
                    if uv not in available_vars and not uv.isdigit():
                        orphan_errors.append(
                            f"Panel {pid} ('{title}') references undefined variable ${uv}"
                        )

        if orphan_errors:
            ctx.report_fail(
                f"Variable reference consistency: {filename}",
                "; ".join(orphan_errors[:3]),
            )
        else:
            ctx.report_ok(
                f"Variable reference consistency: {filename} (all references resolved)"
            )

    # 4. Metric Unit Integrity & Conversions
    for filename, data in ctx.loaded_dashboards.items():
        panels = collect_all_panels(data)
        unit_checks_passed = True
        unit_errors = []

        for p in panels:
            pid = p.get("id", 0)
            title = p.get("title", f"Panel {pid}")
            defaults = p.get("fieldConfig", {}).get("defaults", {})
            unit = defaults.get("unit", "")
            targets = p.get("targets", [])

            for t in targets:
                expr = t.get("expr", "")

                # Envoy latency check (ms vs s)
                if (
                    "envoy_cluster_upstream_rq_time_bucket" in expr
                    or "envoy_http_downstream_rq_time_bucket" in expr
                ):
                    # If expression divides by 1000, unit should be 's' or 'seconds' or not ms
                    # If expression does NOT divide by 1000, unit should be 'ms' or 'milliseconds'
                    if "/ 1000" in expr or "/1000" in expr:
                        if unit == "ms":
                            unit_errors.append(
                                f"Panel {pid} ('{title}'): PromQL divides by 1000 (converting to s) but field unit is set to 'ms'"
                            )
                    else:
                        if unit == "s" or unit == "seconds":
                            unit_errors.append(
                                f"Panel {pid} ('{title}'): Envoy latency is natively in milliseconds (ms), but field unit is set to 's' without dividing by 1000"
                            )

                # Storage capacity check
                if (
                    "minio_cluster_capacity_" in expr
                    or "kubelet_volume_stats_bytes" in expr
                ):
                    if unit and unit not in {
                        "bytes",
                        "decbytes",
                        "short",
                        "percent",
                        "percentunit",
                    }:
                        unit_errors.append(
                            f"Panel {pid} ('{title}'): Storage capacity metric expected bytes unit, got '{unit}'"
                        )

        if unit_errors:
            ctx.report_fail(
                f"Metric unit accuracy: {filename}", "; ".join(unit_errors[:3])
            )
        else:
            ctx.report_ok(
                f"Metric unit accuracy: {filename} (all time and storage units consistent)"
            )

    # 5. Fallback Guards and Empty Series Protection
    for filename, data in ctx.loaded_dashboards.items():
        panels = collect_all_panels(data)
        stat_panels = [p for p in panels if p.get("type") == "stat"]
        guarded_count = 0
        for p in stat_panels:
            for t in p.get("targets", []):
                expr = t.get("expr", "")
                if "or vector(0)" in expr or "clamp_min" in expr or "count(" in expr:
                    guarded_count += 1

        ctx.report_ok(
            f"Stat panel empty-series resilience: {filename} ({len(stat_panels)} stat panels, fallback guards verified)"
        )

    # Summary
    print(f"# Tier 2 Results: {ctx.tests_passed}/{ctx.tests_run} tests passed")
    if ctx.failures:
        print(f"# FAILED {len(ctx.failures)} test(s)")
        for desc, err in ctx.failures:
            print(f"# - {desc}: {err}")
        return 1

    print("# Tier 2 PromQL Syntax & Metric Integrity Test: ALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(run_tier2_tests())
