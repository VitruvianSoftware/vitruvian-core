#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
"""Invariants of the CI collector that must never silently regress.

Spec: docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md
"""

import itertools
import os
import unittest

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))

# Real Dependabot run names (GitHub 'dynamic' runs, 2026-09-29): one per run.
DEPENDABOT_RUN_NAMES = [
    "Configured Graph Update: go_modules in /apps/cli/devx #1587192811",
    "Configured Graph Update: go_modules in /apps/suites/tabula/infra/app, /apps/suites/tabula/infra/build, /apps/suites/tabula/infra/data, /apps/suites/tabula/infra/identity, /apps/suites/tabula/infra/web, /apps/web/oauth-user-inspector/infra/app, /apps/web/oauth-user-inspector/infra/identity #1587193184",
    "Configured Graph Update: go_modules in /apps/suites/tabula/infra/data, /apps/suites/tabula/infra/identity #1582857905",
    "github_actions in /., /.github/actions/*, /apps/cli/devx/.github/workflows, /apps/cli/homelab/.github/workflows, /apps/desktop/nexus-agent/.github/workflows, /apps/mcp/slack/.github/workflows, /apps/web/gods-eye-view/.github/workflows, /packages/pulumi/examples/go-foundation/.github/workflows, /packages/pulumi/examples/go-foundation/build, /packages/pulumi/examples/ts-foundation/.github/workflows, /packages/pulumi/examples/ts-foundation/build, /packages/pulumi/library/.github/workflows - Update #1587170913",
    "go_modules in /apps/cli/devx - Update #1587170882",
    "go_modules in /apps/cli/homelab - Update #1587170990",
    "go_modules in /apps/suites/tabula/infra/**, /apps/web/oauth-user-inspector/infra/app, /apps/web/oauth-user-inspector/infra/identity, /infrastructure/pulumi/** - Update #1587170918",
    "npm_and_yarn in /. - Update #1587168571",
    "npm_and_yarn in /. for @octokit/plugin-paginate-rest, @octokit/request, @octokit/request-error, @opentelemetry/core, @opentelemetry/propagator-jaeger, adm-zip, adm-zip, body-parser, colord, d3-color, deepmerge-ts, elliptic, extract-zip, extract-zip, file-type, hono, hono, hono, js-yaml, js-yaml, locutus, locutus, locutus, locutus, lodash, lodash, minimatch, minimatch, minimatch, multer, multer, multer, multer, mysql2, mysql2, nanoid, prismjs, react-router, react-router, svgo, svgo, uuid - Update #1582538339",
    "npm_and_yarn in /. for @octokit/plugin-paginate-rest, @octokit/request, @octokit/request-error, @opentelemetry/core, @opentelemetry/propagator-jaeger, adm-zip, adm-zip, body-parser, colord, d3-color, deepmerge-ts, elliptic, extract-zip, extract-zip, file-type, hono, hono, hono, js-yaml, js-yaml, locutus, locutus, locutus, locutus, lodash, lodash, minimatch, minimatch, minimatch, multer, multer, multer, multer, mysql2, mysql2, nanoid, prismjs, react-router, react-router, svgo, svgo, uuid - Update #1582561233Graph Update: go_modules in /infrastructure/pulumi/accounts/personal #1582863532",
]

# Every workflow name in .github/workflows at the time: must NOT be rewritten.
WORKFLOW_NAMES = [
    "Auto-merge release PRs",
    "Backstage image update PR",
    "Buzz image update PR",
    "CI",
    "Changelog Summary Test",
    "Conformance Check",
    "Copybara Config Smoke Test",
    "Copybara Export (devx)",
    "Copybara Export (homelab)",
    "Copybara Export (mcp-slack)",
    "Copybara Export (nexus-agent)",
    "Copybara Export (oauth-user-inspector)",
    "Copybara Export (pulumi-library)",
    "Copybara Export (pulumi_go-example-foundation)",
    "Copybara Export (pulumi_ts-example-foundation)",
    "Copybara Export (reusable)",
    "Copybara Import PR",
    "Copybara Import PR auto-close mirror",
    "Dependabot Bazel reconcile",
    "Dependabot Lock Rebase Test",
    "Dependabot auto-merge",
    "Dependabot lock rebase",
    "Deploy Affected Test",
    "Foundation App Digest Guard Test",
    "Foundation App-Infra Deploy",
    "Foundation Environment Deploy",
    "Foundation Network Deploy",
    "Foundation Preview",
    "Foundation Projects Deploy",
    "Foundation Pulumi Summary Test",
    "Foundation Release & Deploy",
    "GCP Secret Or Fail Test",
    "Go Test With Retry Test",
    "LLVM Cache Key Test",
    "Notify CI Issues Test",
    "Periodic Full Sweep",
    "Presubmit",
    "Pulumi Preview",
    "Release Hold Test",
    "Relevant Paths Test",
    "Repo Config Apply",
    "Repo Config Preview",
    "Require Dev Soak Test",
    "Resolve Deploy Base Test",
    "Secret Scan Test",
    "Site Verification Test",
    "Supply Chain",
    "Tabula Deploy Preflight Test",
    "Tidy Check",
    "_deploy-cloud-run",
    "_oauth-identity-apply",
    "_tabula-identity-apply",
    "_zitadel-apps-apply",
    "actionlint",
    "apps-release",
    "backstage-image",
    "chart-render",
    "culprit-finder",
    "delivery",
    "delivery-drift",
    "gitops-validate",
    "gods-eye-view-image",
    "home-speaker-release",
    "iot-esp32-s3",
    "iot-esp32-s3-release",
    "mcp-slack image update PR",
    "mcp-slack-image",
    "migration-safety",
    "notify-ci-issues",
    "preview-teardown",
    "prune-pr-caches",
    "pulumi-library-release",
    "pulumi-stack-reset",
    "release-hold",
    "renovate",
    "storybook-image",
    "tabula Data Stack Deploy",
    "tabula-e2e",
    "tabula-release",
    "zitadel-apps-mcp-slack-apply",
]


def load():
    with open(os.path.join(HERE, "collector.yaml")) as f:
        docs = [d for d in yaml.safe_load_all(f) if d]
    (col,) = [d for d in docs if d["kind"] == "OpenTelemetryCollector"]
    return col


class CollectorConfigTest(unittest.TestCase):
    def setUp(self):
        self.col = load()
        self.cfg = self.col["spec"]["config"]
        self.gh = self.cfg["receivers"]["github"]

    def test_webhook_secret_comes_from_the_required_secret(self):
        # An empty secret makes the receiver accept EVERY request.
        self.assertEqual(self.gh["webhook"]["secret"], "${env:GITHUB_WEBHOOK_SECRET}")
        (env,) = [
            e for e in self.col["spec"]["env"] if e["name"] == "GITHUB_WEBHOOK_SECRET"
        ]
        ref = env["valueFrom"]["secretKeyRef"]
        self.assertEqual(
            (ref["name"], ref["key"]), ("github-otel-webhook", "GITHUB_WEBHOOK_SECRET")
        )
        self.assertIs(ref.get("optional"), False)

    def test_raw_event_bodies_not_attached(self):
        self.assertIs(self.gh["webhook"].get("include_span_events"), False)

    def test_webhook_address(self):
        wh = self.gh["webhook"]
        self.assertEqual((wh["endpoint"], wh["path"]), ("0.0.0.0:19418", "/events"))

    def test_committer_identity_deleted(self):
        acts = self.cfg["processors"]["resource/drop-identity"]["attributes"]
        deleted = {a["key"] for a in acts if a["action"] == "delete"}
        self.assertEqual(
            deleted,
            {"vcs.ref.head.revision.author.name", "vcs.ref.head.revision.author.email"},
        )
        self.assertIn(
            "resource/drop-identity",
            self.cfg["service"]["pipelines"]["traces"]["processors"],
        )

    def test_metric_labels_are_exactly_the_approved_four(self):
        dims = [d["name"] for d in self.cfg["connectors"]["span_metrics"]["dimensions"]]
        self.assertEqual(
            dims, ["cicd.pipeline.name", "ci.span.type", "ci.trigger", "ci.retry"]
        )

    def test_duration_buckets_fine_enough_for_ci(self):
        # A percentile is interpolated inside one bucket; with 10m -> 20m a
        # 641s run read as 900s. Between 1m and 60m (where CI runs live) each
        # bucket may be at most 1.5x the previous, so p50/p95 stay within ~25%.
        units = {"s": 1, "m": 60}
        buckets = [
            float(b[:-1]) * units[b[-1]]
            for b in self.cfg["connectors"]["span_metrics"]["histogram"]["explicit"][
                "buckets"
            ]
        ]
        inside = [b for b in buckets if 60 <= b <= 3600]
        for lo, hi in itertools.pairwise(inside):
            self.assertLessEqual(hi / lo, 1.5, f"bucket gap {lo}s -> {hi}s too wide")

    def _statements(self):
        groups = self.cfg["processors"]["transform/ci-labels"]["trace_statements"]
        return [st for g in groups for st in g["statements"]]

    def _collapse(self, name):
        # Apply the resource-context replace_pattern statements the way OTTL
        # would (RE2 and Python re agree on these patterns).
        import re

        for st in self._statements():
            m = re.match(
                r'replace_pattern\(resource\.attributes\["cicd\.pipeline\.name"\], "(.*)", "(.*)"\)$',
                st,
            )
            if m:
                pat = m.group(1).replace("\\\\", "\\")
                repl = m.group(2).replace("$$", "\\")
                name = re.sub(pat, repl, name)
        return name

    def test_every_real_dependabot_run_name_collapses(self):
        # Dependabot names each run uniquely ("... #<id>"): a new metric series
        # per run, forever. The first rule missed 53 of 79 real names (seen in
        # review). Version updates and graph updates stay distinct families.
        out = {n: self._collapse(n) for n in DEPENDABOT_RUN_NAMES}
        for name, got in out.items():
            self.assertRegex(got, r"^dependabot (graph )?[a-z_]+$", name)
        self.assertEqual(
            sorted(set(out.values())),
            [
                "dependabot github_actions",
                "dependabot go_modules",
                "dependabot graph go_modules",
                "dependabot npm_and_yarn",
            ],
        )

    def test_real_workflow_names_are_untouched(self):
        for name in WORKFLOW_NAMES:
            self.assertEqual(self._collapse(name), name)

    def test_run_span_name_follows_the_collapsed_name(self):
        self.assertIn(
            'set(span.name, resource.attributes["cicd.pipeline.name"]) '
            "where span.kind == SPAN_KIND_SERVER",
            self._statements(),
        )

    def test_metrics_add_up_across_runs(self):
        # Every event carries its own run id/branch/sha as resource attributes,
        # so span_metrics kept one counter per EVENT: every cicd_* counter was
        # stuck at 1 (seen live and in review). Key metrics by service only,
        # and keep only service.name on the metrics' resource -- which also
        # stops per-run labels leaking into Prometheus via target_info.
        sm = self.cfg["connectors"]["span_metrics"]
        self.assertEqual(sm["resource_metrics_key_attributes"], ["service.name"])
        mp = self.cfg["service"]["pipelines"]["metrics"]
        self.assertIn("transform/metrics-resource", mp["processors"])
        sts = [
            st
            for g in self.cfg["processors"]["transform/metrics-resource"][
                "metric_statements"
            ]
            for st in g["statements"]
        ]
        self.assertIn('keep_keys(resource.attributes, ["service.name"])', sts)

    def test_timeouts_and_startup_failures_count_as_failures(self):
        # The receiver leaves these Unset; a reasonable reader counts a
        # timed-out run as failed.
        self.assertIn(
            'set(span.status.code, STATUS_CODE_ERROR) where span.status.message == "timed_out" '
            'or span.status.message == "startup_failure"',
            self._statements(),
        )

    def test_prometheus_can_scrape_the_collector(self):
        # The policy blocked Prometheus from the collector's own metrics (8888):
        # two PrometheusTargetDown alerts fired.
        with open(os.path.join(HERE, "network-policy.yaml")) as f:
            pol = next(d for d in yaml.safe_load_all(f) if d)
        ok = False
        for rule in pol["spec"]["ingress"]:
            src = [e.get("matchLabels", {}) for e in rule.get("fromEndpoints", [])]
            ports = [p["port"] for tp in rule.get("toPorts", []) for p in tp["ports"]]
            if (
                any(
                    m.get("io.kubernetes.pod.namespace") == "monitoring"
                    and m.get("app.kubernetes.io/name") == "prometheus"
                    for m in src
                )
                and "8888" in ports
            ):
                ok = True
        self.assertTrue(ok, "no ingress rule lets monitoring/prometheus reach :8888")

    def test_ottl_paths_carry_their_context(self):
        # 0.160 rewrites unprefixed paths and logs it; unprefixed paths are on
        # the way out. Every attribute/name/kind reference names its context.
        import re

        for st in self._statements():
            bare = re.findall(r"(?<![\w.])(attributes|name|kind)(?=[\[ ,)])", st)
            self.assertFalse(bare, f"unprefixed path in: {st}")

    def test_github_receiver_only_in_traces_pipeline(self):
        # In a metrics pipeline the scraper would start polling GitHub (phase 2).
        pipes = self.cfg["service"]["pipelines"]
        users = [
            name for name, p in pipes.items() if "github" in p.get("receivers", [])
        ]
        self.assertEqual(users, ["traces"])

    def test_survives_one_node_down(self):
        spec = self.col["spec"]
        self.assertEqual(spec["replicas"], 2)
        self.assertEqual(spec["podDisruptionBudget"]["minAvailable"], 1)
        self.assertTrue(
            spec["affinity"]["podAntiAffinity"][
                "requiredDuringSchedulingIgnoredDuringExecution"
            ]
        )

    def test_no_deprecated_component_names(self):
        # 0.160 logs these old aliases as deprecated; they will be removed.
        names = [
            *self.cfg["connectors"],
            *self.cfg["exporters"],
            *self.cfg["receivers"],
        ]
        for old in ("spanmetrics", "prometheusremotewrite", "otlp"):
            self.assertFalse(
                [n for n in names if n.split("/")[0] == old],
                f"deprecated component name {old!r} in use",
            )

    def test_argocd_sees_real_config_changes(self):
        # ServerSideDiff=true on this app hid a REAL config change (#2575's
        # buckets never deployed; Argo CD reported Synced). Proven on a scratch
        # app: with ports declared exactly as the operator's webhook stores
        # them, plain server-side apply stays Synced AND deploys real changes.
        app_path = os.path.join(HERE, "..", "..", "applications", "cicd-telemetry.yaml")
        with open(app_path) as f:
            app = yaml.safe_load(f)
        ann = app["metadata"].get("annotations", {})
        self.assertNotIn(
            "ServerSideDiff=true",
            ann.get("argocd.argoproj.io/compare-options", ""),
        )

    def test_ports_declare_the_webhook_default(self):
        # The webhook adds targetPort: 0 to every port. ports is compared as a
        # whole list, so leaving it out makes Argo CD report drift forever.
        for port in self.col["spec"]["ports"]:
            self.assertIn("targetPort", port, f"port {port['name']} lacks targetPort")

    def test_operator_does_not_write_its_own_network_policy(self):
        self.assertIs(self.col["spec"]["networkPolicy"]["enabled"], False)


if __name__ == "__main__":
    unittest.main()
