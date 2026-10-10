#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Prometheus Thanos sidecar must have sufficient memory headroom to avoid OOM kills."""

import os
import re
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))


def load_values():
    with open(os.path.join(HERE, "applicationset.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (appset,) = [d for d in docs if d["kind"] == "ApplicationSet"]
    raw_values = appset["spec"]["template"]["spec"]["source"]["helm"]["values"]
    cleaned = raw_values.replace("{{`", "").replace("`}}", "")
    return yaml.safe_load(cleaned)


class PrometheusValuesTest(unittest.TestCase):
    def setUp(self):
        self.v = load_values()

    def test_thanos_sidecar_memory_limit(self):
        sidecars = self.v.get("server", {}).get("sidecarContainers", {})
        sidecar = sidecars.get("thanos-sidecar", {})
        lim = sidecar.get("resources", {}).get("limits", {}).get("memory")
        self.assertEqual(lim, "2Gi")

    def test_thanos_sidecar_has_series_cap(self):
        sidecar = self.v["server"]["sidecarContainers"]["thanos-sidecar"]
        self.assertIn("--store.limits.request-series=150000", sidecar["args"])

    def test_thanos_sidecar_samples_cap_is_above_the_querier_cap(self):
        """A sidecar that stops at its cap has already sent more than the
        Querier accepts, so the query is refused, not cut off."""
        # 12,000,000 is the Querier's --store.limits.request-samples, set in
        # ../thanos/applicationset.yaml and pinned as QUERY_SAMPLES_CAP in
        # ../thanos/thanos_values_test.py. Change all three together.
        querier_samples_cap = 12_000_000
        sidecar = self.v["server"]["sidecarContainers"]["thanos-sidecar"]
        name = "--store.limits.request-samples="
        values = [a[len(name) :] for a in sidecar["args"] if a.startswith(name)]
        self.assertEqual(len(values), 1, values)
        self.assertGreater(int(values[0]), querier_samples_cap)

    def test_thanos_sidecar_has_memory_guard(self):
        # The sidecar was OOM-killed alongside the Querier on 2026-10-10.
        sidecar = self.v["server"]["sidecarContainers"]["thanos-sidecar"]
        self.assertIn("--enable-auto-gomemlimit", sidecar["args"])

    def test_repeated_oom_kill_alert_exists(self):
        rules = [
            r
            for g in self.v["serverFiles"]["alerting_rules.yml"]["groups"]
            for r in g.get("rules", [])
        ]
        (rule,) = [
            r for r in rules if r.get("alert") == "KubeContainerOOMKilledRepeatedly"
        ]
        self.assertIn('reason="OOMKilled"', rule["expr"])
        self.assertEqual(rule["labels"]["severity"], "warning")

    def test_repeated_oom_kill_alert_clears_once_container_is_stable(self):
        """The alert must stop firing once the container has run cleanly for 30m.

        Without the recency guard, a container that OOM'd twice and then
        stabilised stays red for the whole 6h restart lookback window.
        """
        rules = [
            r
            for g in self.v["serverFiles"]["alerting_rules.yml"]["groups"]
            for r in g.get("rules", [])
        ]
        (rule,) = [
            r for r in rules if r.get("alert") == "KubeContainerOOMKilledRepeatedly"
        ]
        expr = " ".join(rule["expr"].split())
        self.assertIn("kube_pod_container_state_started", expr)
        self.assertIn("time() - kube_pod_container_state_started < 30 * 60", expr)
        # The 6h restart lookback is still the "repeatedly" signal.
        self.assertIn("kube_pod_container_status_restarts_total[6h]", expr)

    def _resource_job(self):
        jobs = yaml.safe_load(self.v["extraScrapeConfigs"])
        (job,) = [j for j in jobs if j["job_name"] == "kubernetes-nodes-resource"]
        return job

    def test_resource_job_scrapes_only_docker_nodes(self):
        """The kubelet resource endpoint is scraped on the Docker nodes only.

        The containerd nodes already get the same two series from cAdvisor.
        Without the keep rule every container there would have two series
        and every sum over them would double.
        """
        job = self._resource_job()
        self.assertEqual(job["kubernetes_sd_configs"], [{"role": "node"}])
        first = job["relabel_configs"][0]
        self.assertEqual(first["action"], "keep")
        self.assertEqual(
            first["source_labels"],
            ["__meta_kubernetes_node_annotation_k3s_io_node_args"],
        )
        # Prometheus anchors relabel regexes at both ends, so fullmatch.
        docker = '["agent","--node-name","james-mbp","--docker"]'
        containerd = '["server","--tls-san","k8s-api.lab.ipv1337.dev"]'
        self.assertTrue(re.fullmatch(first["regex"], docker))
        self.assertFalse(re.fullmatch(first["regex"], containerd))
        # A node with no such annotation presents an empty value.
        self.assertFalse(re.fullmatch(first["regex"], ""))

    def test_resource_job_goes_through_the_api_server_proxy(self):
        job = self._resource_job()
        self.assertEqual(job["scheme"], "https")
        by_target = {r.get("target_label"): r for r in job["relabel_configs"]}
        self.assertEqual(
            by_target["__address__"]["replacement"], "kubernetes.default.svc:443"
        )
        self.assertEqual(
            by_target["__metrics_path__"]["replacement"],
            "/api/v1/nodes/$1/proxy/metrics/resource",
        )

    def test_resource_job_keeps_only_container_cpu_and_memory(self):
        (rule,) = self._resource_job()["metric_relabel_configs"]
        self.assertEqual(rule["action"], "keep")
        self.assertEqual(rule["source_labels"], ["__name__"])
        self.assertEqual(
            set(rule["regex"].split("|")),
            {
                "container_cpu_usage_seconds_total",
                "container_memory_working_set_bytes",
            },
        )

    def test_extra_scrape_configs_survive_helm_tpl(self):
        """The chart renders extraScrapeConfigs through tpl.

        A double open brace in it would be run as a Helm template.
        """
        self.assertNotIn("{{", self.v["extraScrapeConfigs"])

    def test_app_cpu_graphs_do_not_filter_on_image(self):
        """App CPU and memory graphs must work for pods on Docker nodes.

        Series from the resource endpoint carry no image label, so a rule
        that filters on image, or builds on the k8s.rules rule that does,
        shows nothing for a pod scheduled on a Docker node.
        """
        groups = self.v["serverFiles"]["recording_rules.yml"]["groups"]
        (group,) = [g for g in groups if g["name"] == "backstage-graphs"]
        rules = [
            r
            for r in group["rules"]
            if r["record"].endswith((":cpu_cores", ":memory_bytes"))
        ]
        apps = {r["record"].split(":")[0] for r in rules}
        self.assertEqual(
            apps, {"backstage", "buzz", "mcp_slack", "storybook", "whoami"}
        )
        self.assertEqual(len(rules), 10)
        for r in rules:
            self.assertNotIn("image", r["expr"], r["record"])
            self.assertNotIn("node_namespace_pod_container", r["expr"], r["record"])


if __name__ == "__main__":
    unittest.main()
