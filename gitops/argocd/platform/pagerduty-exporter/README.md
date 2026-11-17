# pagerduty-exporter

[webdevops/pagerduty-exporter](https://github.com/webdevops/pagerduty-exporter)
turns the PagerDuty account into Prometheus metrics: open incidents, 90-day
incident counts, time to acknowledge and resolve, who is on call. They feed the
**PagerDuty** Grafana dashboard (`grafana-dashboards/pagerduty.json`).

- **Read-only.** It uses the read-only REST API key in the `pagerduty-exporter`
  Secret, sealed with `bazel run //tools/gitops:seal-pagerduty-readonly` (key
  on stdin). The same tool seals the copy Backstage's PagerDuty plugin reads.
- **Free plan.** `--pagerduty.disable-teams` (no Teams on Free) and a 90-day
  summary window (Free keeps 3 months of history).
- **Scraped** through its Service's `prometheus.io/*` annotations
  (job `kubernetes-service-endpoints`).
- **Checks:** `bazel test //gitops/argocd/platform/pagerduty-exporter:exporter_test`
  pins the settings above and that every dashboard query uses a metric the
  exporter exports.

To rotate the key: create a new read-only key in PagerDuty, save it in
Bitwarden (`vitruviansoftware.pagerduty.com`, field `PAGERDUTY_RO_API_KEY`),
pipe it into the seal tool and commit both SealedSecrets.
