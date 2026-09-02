# Project: k3s-lab Production Grafana Dashboards

## Architecture
- **GitOps Delivery**: ArgoCD monitors `gitops/argocd/platform/grafana-dashboards/kustomization.yaml`. Dashboards are generated as Kubernetes ConfigMaps in namespace `grafana` with label `grafana_dashboard: "1"` and `disableNameSuffixHash: true`.
- **Grafana Sidecar Discovery**: Grafana pod runs a `k8s-sidecar` container watching ConfigMaps with label `grafana_dashboard: "1"` in namespace `grafana`, automatically mounting them to `/tmp/dashboards` without requiring Grafana restarts.
- **Datasource Architecture**: Default Prometheus datasource UID is `Prometheus-Data` (pointing to Thanos Querier at `http://thanos-query.monitoring.svc.cluster.local:9090`). Traces datasource UID is `Tempo` (pointing to Tempo at `http://tempo.opentelemetry.svc.cluster.local:3200`).
- **Telemetry Sources**:
  - ArgoCD & Rollouts: `argocd_*`, `rollout_*`, `analysis_run_*` scraped from ArgoCD server/controller and Rollouts controller.
  - Envoy Gateway: `envoy_*` exported by Envoy proxy ingress (`httproute/<namespace>/<name>/rule/<index>`).
  - Identity & Mesh: `headscale_*` (port 9090), `cloudflared_tunnel_*` (port 2000), `envoy_cluster_upstream_*` for Zitadel routes.
  - Data Platform & DR: `cnpg_*` (port 9187 on `backstage-db`, `grafana-db`, `zitadel-db`, `cnpg-cluster`), `kube_cronjob_status_last_successful_time` (`pg-dump-nfs`, `prometheus-nas-backup`), `minio_cluster_capacity_*`, `kubelet_volume_stats_*`.
  - AI Assistant & Automations: `antigravity_*`, `buzz_*` (port 9102), `mcp-slack` ingress, `backstage` ingress & spanmetrics.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | ArgoCD App Sync & Health Status | App sync status (Synced, OutOfSync, Unknown) & health status (Healthy, Progressing, Degraded, Missing) across 52 apps | M1 | R1 |
| F2 | ArgoCD Reconcile & Sync Latency | Reconcile duration and sync execution latency histograms | M1 | R1 |
| F3 | ArgoCD Git Polling & API Errors | Git repo polling latency, fetch/clone rates, and API errors | M1 | R1 |
| F4 | Argo Rollout Canary & AnalysisRun | Canary progression, replica distribution, AnalysisRun phases (Successful, Failed, Inconclusive), rollback rates | M1 | R1 |
| F5 | Image Updater Promotion Tracking | Promotion frequencies & git fetch operations on target apps | M1 | R1 |
| F6 | Envoy HTTP Throughput & Status Codes | RPS and status code distribution (2xx, 4xx, 5xx) broken down by HTTPRoute (otel, grafana, argocd, backstage, zitadel, buzz, mcp-slack, etc.) | M2 | R2 |
| F7 | Envoy Upstream Latency Curves | P50, P95, P99 upstream response latency in milliseconds | M2 | R2 |
| F8 | Envoy Connection Pools & Resets | Downstream/upstream active connections, connect failures, tx/rx resets | M2 | R2 |
| F9 | Envoy Circuit Breaking & Timeouts | Circuit breaker triggers, pending/retry opens, upstream timeouts and retries | M2 | R2 |
| F10 | Zitadel Auth Volume & Failure Signals | Ingress auth RPS, token issuance traffic, 401/403 spikes, invalid credentials, HA pod readiness | M3 | R3 |
| F11 | Headscale Mesh Node Fleet Status | Connected vs offline nodes across the fleet, active users | M3 | R3 |
| F12 | Cloudflared Tunnel Health & Latency | HA tunnel connections, edge round-trip latency buckets, restarts | M3 | R3 |
| F13 | CNPG Postgres Replication & Connection Pools | Streaming replication lag, WAL archiving rates/failures, connection pool saturation for backstage-db, grafana-db, zitadel-db, cnpg-cluster | M4 | R4 |
| F14 | Disaster Recovery Backup SLA Tracker | "Hours since last successful backup" for pg-dump-nfs, prometheus-nas-backup, MinIO barman backups | M4 | R4 |
| F15 | Backup Job Duration & Archive Sizes | Backup job execution durations, archive sizes, and recoverability points | M4 | R4 |
| F16 | Storage Class & Persistent Volume Headroom | MinIO erasure-code usable capacity and NVMe/NFS PVC headroom (kubelet_volume_stats_*) | M4 | R4 |
| F17 | AI Assistant Tool Calls & Latency | MCP / Antigravity / Claude-Code tool invocation rates, tool execution latencies (slack_post_message, slack_get_channel_history, etc.), error rates, token usage | M5 | R5 |
| F18 | Buzz Event Relay & Automations | Webhook event processing rates, store/reject counters, WS connections, active users, DB/Redis connection pools, storage sweep | M5 | R5 |
| F19 | Backstage Portal & Distributed Traces | Backstage route traffic, DB backends, techdocs build latency, Tempo spanmetrics and TraceQL linking | M5 | R5 |
| F20 | GitOps Dashboard Registration | Register all 5 dashboard JSONs in kustomization.yaml with label `grafana_dashboard: "1"` and `disableNameSuffixHash: true` | M6 | R6 |
| F21 | Monorepo Manifest & Build Validation | Validate manifests with `tools/ci/gitops-validate.sh`, `appset-render`, `kustomize`, `bazel test //...` | M6 | R6 |
| F22 | E2E Test Suite (Tiers 1-4) Pass | Validate 100% of E2E test suite (JSON schemas, PromQL query syntax, panel layouts, live query population) | M7 | R6 |
| F23 | Adversarial Coverage Hardening (Tier 5) | White-box adversarial testing, edge-case PromQL fallback testing (`or vector(0)`), cross-variable filtering | M7 | R6 |
| F24 | PR, CI, Merge & Post-Merge Verification | Open PR with agent identity, drive CI green, land to origin/main, verify post-merge health and live Grafana sync | M7 | R6 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | GitOps & Progressive Delivery (`argocd.json`) | Features F1, F2, F3, F4, F5 | none | PLANNED |
| M2 | Envoy Gateway API & Traffic Observability (`envoy-gateway.json`) | Features F6, F7, F8, F9 | none | PLANNED |
| M3 | Identity, Auth & Zero-Trust Mesh (`identity-mesh.json`) | Features F10, F11, F12 | none | PLANNED |
| M4 | Data Platform & Disaster Recovery SLA (`data-platform-dr.json`) | Features F13, F14, F15, F16 | none | PLANNED |
| M5 | AI Assistant Tooling & Platform Automations (`agent-integrations.json`) | Features F17, F18, F19 | none | PLANNED |
| M6 | GitOps Integration & Manifest Validation | Features F20, F21 | M1, M2, M3, M4, M5 | PLANNED |
| M7 | Final Milestone: E2E Verification, Adversarial Hardening, Landing | Features F22, F23, F24 | M6, E2E Test Suite | PLANNED |

## Dual Track: E2E Testing Track
- **E2E Testing Orchestrator**: Runs in parallel with Implementation Milestones.
- Scope:
  - Tier 1: Schema & Structure Validation (valid Grafana JSON, standard template variables `$datasource`, `$interval`, `$host`/`$route`, panels have titles, targets, and fieldConfig).
  - Tier 2: PromQL Syntax & Metric Integrity (every PromQL query parses cleanly, handles missing/empty series gracefully, uses correct units e.g. ms vs s, handles multi-replica summing).
  - Tier 3: Cross-Feature Integration & Dashboard Consistency (standard UID conventions, tag conventions `["kubernetes", "k3s-lab", "production"]`, consistent color palettes, sidecar discoverability).
  - Tier 4: Real-World Telemetry Execution (live query execution against Thanos Querier to verify non-empty series for active cluster services).
  - Publishes `TEST_READY.md` upon completion.

## Code Layout & File Ownership Boundaries
- `gitops/argocd/platform/grafana-dashboards/argocd.json` -> Owned exclusively by Milestone M1 Worker
- `gitops/argocd/platform/grafana-dashboards/envoy-gateway.json` -> Owned exclusively by Milestone M2 Worker
- `gitops/argocd/platform/grafana-dashboards/identity-mesh.json` -> Owned exclusively by Milestone M3 Worker
- `gitops/argocd/platform/grafana-dashboards/data-platform-dr.json` -> Owned exclusively by Milestone M4 Worker
- `gitops/argocd/platform/grafana-dashboards/agent-integrations.json` -> Owned exclusively by Milestone M5 Worker
- `gitops/argocd/platform/grafana-dashboards/kustomization.yaml` -> Owned exclusively by Milestone M6 Worker
- `tests/e2e/dashboards/` -> Owned exclusively by E2E Testing Track Worker / Test Writer

## Interface Contracts
- **Dashboard JSON Standards**:
  - `schemaVersion`: >= 38
  - `uid`: Unique, deterministic (e.g. `argocd-gitops`, `envoy-gateway-api`, `identity-zero-trust`, `data-platform-dr`, `agent-integrations`)
  - `tags`: `["kubernetes", "k3s-lab", "platform"]`
  - `templating.list`:
    - `datasource`: `{"name": "datasource", "type": "datasource", "query": "prometheus", "current": {"text": "Prometheus-Data", "value": "Prometheus-Data"}}`
    - Standard drill-down variables (`interval`, `app`, `route`, `cluster`, `namespace`, `host` where relevant)
  - `editable`: `true`
  - `time`: `{"from": "now-6h", "to": "now"}`
  - `refresh`: `"30s"`
- **GitOps ConfigMap Format**:
  - Namespace: `grafana`
  - Labels: `grafana_dashboard: "1"`
  - `disableNameSuffixHash: true`
