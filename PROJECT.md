# Project: Antigravity & AGY Telemetry Solution

## Architecture
- **Grafana Dashboard**: Deployed via ArgoCD ConfigMap generator in `gitops/argocd/platform/grafana-dashboards/`, loaded by Grafana sidecar into `grafana` namespace. Datasources: `Prometheus-Data` (Prometheus/Thanos) and `Tempo` (Tempo Traces).
- **OpenTelemetry Pipeline**: Cluster receiver at `https://otel.lab.ipv1337.dev` (Envoy Gateway -> OTel Collector) remote-writes metrics to dual Prometheus replicas and traces to Tempo.
- **Telemetry Tooling**: `tools/antigravity-telemetry/` provides lifecycle hooks and OTLP exporter tagging events with `host.name` and sending to `https://otel.lab.ipv1337.dev`.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Antigravity Dashboard JSON | Replace `gemini-cli.json` with `antigravity.json` (UID: `antigravity`, Title: "Antigravity & AGY Telemetry", $host variable, 5 panel groups) | M1 | Survey |
| 2 | GitOps Kustomization | Update `gitops/argocd/platform/grafana-dashboards/kustomization.yaml` to deploy `antigravity.json` | M1 | Survey |
| 3 | Telemetry Exporter & Lifecycle Hooks | Implement `tools/antigravity-telemetry` capturing tokens, models, tool latencies, sessions, subagents | M2 | Survey |
| 4 | Developer Setup Automation | Provide `setup`, `status`, `emit` subcommands configuring `~/.gemini/settings.json` and hooks | M2 | Survey |
| 5 | Monorepo Validation & CI | License checks, prometheus rule tests, gazelle, gitops validation, unit tests | M3 | Survey |
| 6 | PR & Landing Workflow | Open PR, drive CI green, peer review, merge to main, verify landed and post-merge health | M3 | Survey |
| 7 | Live Telemetry & Verification | Emit telemetry to `https://otel.lab.ipv1337.dev`, verify Prometheus metrics and Grafana panels | M3 | Survey |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1_Dashboard_GitOps | `antigravity.json` dashboard & `kustomization.yaml` update | none | DONE |
| 2 | M2_Telemetry_Tooling | `tools/antigravity-telemetry/` exporter, hooks, setup & tests | none | DONE |
| 3 | M3_E2E_Validation_PR | Monorepo CI gates, PR lifecycle, landing & live verification | M1, M2 | IN_PROGRESS |

## Interface Contracts
### Telemetry Exporter ↔ Prometheus / Grafana
- Metric Names:
  - `antigravity_token_usage_total{host=~"$host", token_type=~"input|output|thinking|cached", model="..."}`
  - `antigravity_api_request_count_total{host=~"$host", model="...", status_code="..."}`
  - `antigravity_tool_call_count_total{host=~"$host", tool_name="...", status=~"success|error"}`
  - `antigravity_tool_call_latency_milliseconds_bucket{host=~"$host", tool_name="...", le="..."}`
  - `antigravity_session_count_total{host=~"$host", status="..."}`
  - `antigravity_turn_count_total{host=~"$host", model="..."}`
  - `antigravity_subagent_spawn_count_total{host=~"$host", subagent_type="..."}`
- Traces:
  - `{resource.service.name=~"antigravity|agy"}`

## Code Layout
- `gitops/argocd/platform/grafana-dashboards/antigravity.json` (Dashboard definition)
- `gitops/argocd/platform/grafana-dashboards/kustomization.yaml` (GitOps Kustomization)
- `tools/antigravity-telemetry/BUILD.bazel` (Bazel target definitions)
- `tools/antigravity-telemetry/antigravity_telemetry.py` (CLI & OTLP client implementation)
- `tools/antigravity-telemetry/telemetry_hook.py` (Lifecycle hook script)
- `tools/antigravity-telemetry/antigravity_telemetry_test.py` (Hermetic tests)
- `docs/reference/bazel-targets.md` (Tool target catalog entry)
