# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Checks for pagerduty-exporter's manifests and the PagerDuty dashboard.

The exporter only runs in the cluster, so these pin what a mistake there would
break silently: a key that can write, a scrape that never happens, Teams calls
the free plan refuses, or a dashboard that queries a metric nobody exports.
"""

import json
import pathlib
import re
import unittest

HERE = pathlib.Path(__file__).parent
DEPLOYMENT = (HERE / "deployment.yaml").read_text()
SERVICE = (HERE / "service.yaml").read_text()
DASHBOARD = json.loads(
    (HERE.parent / "grafana-dashboards" / "pagerduty.json").read_text()
)
KUSTOMIZATION = (HERE.parent / "grafana-dashboards" / "kustomization.yaml").read_text()

# Every metric webdevops/pagerduty-exporter 26.10.0 registers that the
# dashboard may use (metrics_*.go), plus Prometheus's own `up`.
EXPORTED = {
    "pagerduty_incident_info",
    "pagerduty_incident_status",
    "pagerduty_service_info",
    "pagerduty_schedule_oncall",
    "pagerduty_user_info",
    "pagerduty_api_counter",
    "pagerduty_summary_incident_count",
    "pagerduty_summary_incident_statuschange_count",
    "pagerduty_summary_incident_resolve_duration_bucket",
    "pagerduty_summary_incident_resolve_duration_sum",
    "pagerduty_summary_incident_resolve_duration_count",
    "pagerduty_summary_incident_acknowledge_duration_bucket",
    "pagerduty_summary_incident_acknowledge_duration_sum",
    "pagerduty_summary_incident_acknowledge_duration_count",
    "up",
}


def exprs(panels):
    for p in panels:
        yield from exprs(p.get("panels", []))
        for t in p.get("targets", []):
            yield p.get("title", ""), t["expr"]


class Deployment(unittest.TestCase):
    def test_image_is_pinned_by_digest(self):
        self.assertRegex(
            DEPLOYMENT,
            r"image: webdevops/pagerduty-exporter:[0-9.]+@sha256:[0-9a-f]{64}\n",
        )

    def test_token_comes_from_the_sealed_secret_file(self):
        self.assertIn("--pagerduty.authtokenfile=/etc/pagerduty/api-token", DEPLOYMENT)
        self.assertIn("secretName: pagerduty-exporter", DEPLOYMENT)
        self.assertNotIn("PAGERDUTY_AUTH_TOKEN\n", DEPLOYMENT)

    def test_non_root_user_can_read_the_token_file(self):
        # A root-owned 0400 file is unreadable by runAsUser 1000: the
        # exporter then crashes at start. fsGroup + a group-readable mode fix it.
        user = re.search(r"runAsUser: (\d+)", DEPLOYMENT).group(1)
        self.assertIn(f"fsGroup: {user}", DEPLOYMENT)
        mode = re.search(r"defaultMode: (0[0-7]{3})", DEPLOYMENT).group(1)
        self.assertTrue(
            int(mode, 8) & 0o040, f"defaultMode {mode} is not group-readable"
        )

    def test_free_plan_settings(self):
        # The free plan has no Teams and keeps 3 months of history.
        self.assertIn("--pagerduty.disable-teams", DEPLOYMENT)
        self.assertIn("--pagerduty.summary.since=2160h", DEPLOYMENT)

    def test_runs_on_wired_nodes_without_privileges(self):
        self.assertIn("node.ipv1337.dev/link: wired", DEPLOYMENT)
        self.assertIn("readOnlyRootFilesystem: true", DEPLOYMENT)
        self.assertIn("automountServiceAccountToken: false", DEPLOYMENT)

    def test_prometheus_scrapes_the_port_it_listens_on(self):
        listen = re.search(r"--server\.bind=:(\d+)", DEPLOYMENT).group(1)
        self.assertIn(f'prometheus.io/port: "{listen}"', SERVICE)
        self.assertIn('prometheus.io/scrape: "true"', SERVICE)
        self.assertIn(f"containerPort: {listen}", DEPLOYMENT)


class Dashboard(unittest.TestCase):
    def test_is_provisioned(self):
        self.assertIn("- pagerduty.json", KUSTOMIZATION)
        self.assertEqual(DASHBOARD["uid"], "pagerduty")

    def test_every_query_uses_exported_metrics(self):
        found = False
        for title, e in exprs(DASHBOARD["panels"]):
            # Metric names: identifiers not followed by "(" (functions) and
            # not inside {...} label matchers or quotes.
            stripped = re.sub(r"\{[^}]*\}|\"[^\"]*\"|\[[^\]]*\]", "", e)
            names = set(re.findall(r"\b([a-z_][a-z0-9_]*)\b(?!\s*\()", stripped))
            keywords = {
                "by",
                "on",
                "group_left",
                "or",
                "and",
                "vector",
                "le",
                "serviceName",
                "serviceID",
                "urgency",
                "userID",
                "userName",
                "name",
            }
            metrics = {n for n in names - keywords if "_" in n or n == "up"}
            unknown = metrics - EXPORTED
            self.assertFalse(unknown, f"panel {title!r} queries {unknown}")
            found = found or bool(metrics)
        self.assertTrue(found)

    def test_queries_use_the_datasource_variable(self):
        for p in DASHBOARD["panels"]:
            if p["type"] == "row":
                continue
            self.assertEqual(p["datasource"]["uid"], "${datasource}", p["title"])

    def test_service_names_join_on_service_id(self):
        joined = [e for _, e in exprs(DASHBOARD["panels"]) if "serviceName" in e]
        self.assertTrue(joined)
        for e in joined:
            if "pagerduty_service_info" in e:
                self.assertIn("on (serviceID) group_left (serviceName)", e)


if __name__ == "__main__":
    unittest.main()
