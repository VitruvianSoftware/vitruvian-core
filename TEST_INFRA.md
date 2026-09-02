# Test Infrastructure Specification: Grafana Production Dashboards

## 1. Overview & Architecture

The Grafana Dashboards E2E Testing Framework provides multi-tiered automated verification for all production Grafana dashboards deployed across the `k3s-lab` cluster fleet.

The test framework evaluates 5 core production dashboards:
1. **`argocd.json`**: GitOps & Progressive Delivery (ArgoCD, Argo Rollouts, ApplicationSets, Image Updater)
2. **`envoy-gateway.json`**: Envoy Gateway API & Traffic Observability (HTTPRoutes, Latencies, Resets, Circuit Breaking)
3. **`identity-mesh.json`**: Identity, Auth & Zero-Trust Mesh (Zitadel, Headscale, Cloudflare Tunnels)
4. **`data-platform-dr.json`**: Data Platform & Disaster Recovery SLA (CNPG Postgres, Backup Pipelines, MinIO, Storage)
5. **`agent-integrations.json`**: AI Assistant Tooling & Platform Automations (Antigravity, MCP Slack Bridge, Buzz Relay, Backstage, Tempo Distributed Traces)

```
========================================================================================
                                 TEST INFRASTRUCTURE TIERS
========================================================================================
 [ Tier 1: Schema & Structure ]       -> JSON Syntax, Schema >= 38, UIDs, Variables, Panels, gridPos
 [ Tier 2: PromQL & Metric Integrity ]-> Lexical PromQL Parse, Unit Accuracy (ms vs s), Rate Aggrs
 [ Tier 3: GitOps & Consistency ]     -> Kustomize ConfigMap Generator, Sidecar Labels, Dark Theme
 [ Tier 4: Live Telemetry Execution ] -> Real-time PromQL Execution against Thanos Querier in Cluster
========================================================================================
```

---

## 2. Test Tiers & Verification Methodology

### Tier 1: Schema, Structure, & Standard Variable Validation
- **Executable**: `tests/e2e/dashboards/tier1_schema_test.py`
- **Scope**:
  - Validates dashboard file existence and JSON parsing in `gitops/argocd/platform/grafana-dashboards/`.
  - Ensures `schemaVersion >= 38` for Grafana 10.x/11.x compatibility.
  - Enforces unique, deterministic UIDs (`argocd-gitops`, `envoy-gateway-api`, `identity-zero-trust`, `data-platform-dr`, `agent-integrations`).
  - Validates required top-level metadata: `title`, `tags`, `editable: true`, `time` range, and `refresh` interval.
  - Verifies presence of standard `$datasource` variable pointing to default Prometheus datasource (`Prometheus-Data`).
  - Verifies domain-specific template variables (`$project`, `$app`, `$route`, `$namespace`, `$host`, `$service`).
  - Checks panel geometry constraints: 24-column grid boundaries (`w` between 1..24, `x + w <= 24`, `h >= 1`, `y >= 0`), unique panel IDs, valid panel types (`timeseries`, `stat`, `table`, `bargauge`, `gauge`, `row`, `piechart`, `logs`, `traces`).

### Tier 2: PromQL Syntax & Metric Integrity Validation
- **Executable**: `tests/e2e/dashboards/tier2_promql_test.py`
- **Scope**:
  - Extracts and lexically parses every PromQL `expr` across all panel targets and template variable queries.
  - Validates bracket balancing (`()`, `[]`, `{}`), label matcher syntax, and PromQL built-in function usage.
  - Prevents PromQL anti-patterns (e.g. invalid `rate(sum(...))` instead of `sum(rate(...))`).
  - Validates `histogram_quantile` query formulations ensuring bucket rates are aggregated by `(le, ...)`.
  - Verifies metric unit accuracy:
    - Envoy latency metrics (`envoy_cluster_upstream_rq_time_bucket`, `envoy_http_downstream_rq_time_bucket`) are natively in **milliseconds (ms)**.
    - ArgoCD and database latency metrics are in **seconds (s)**.
    - Storage and memory metrics are in **bytes**.
    - Backup staleness calculates hours via `(time() - kube_cronjob_status_last_successful_time) / 3600`.
  - Asserts that all template variable references within PromQL expressions match defined variables.
  - Verifies fallback guards (`or vector(0)`, `clamp_min`) on single-stat cards to prevent empty/broken displays.

### Tier 3: Cross-Feature Integration & Dashboard Consistency Validation
- **Executable**: `tests/e2e/dashboards/tier3_integration_test.py`
- **Scope**:
  - Validates GitOps declaration in `gitops/argocd/platform/grafana-dashboards/kustomization.yaml`.
  - Verifies generator options: `namespace: grafana`, `disableNameSuffixHash: true`, `labels.grafana_dashboard: "1"`.
  - Asserts that all 5 target dashboards are registered in `configMapGenerator`.
  - Executes `kubectl kustomize` to prove end-to-end manifest rendering and ConfigMap data generation.
  - Enforces cross-dashboard UX standards: dark theme (`style: "dark"`), shared crosshair (`graphTooltip: 1` or `2`), and standard platform tags (`kubernetes`, `k3s-lab`, `platform`).

### Tier 4: Live Telemetry Query Verification
- **Executable**: `tests/e2e/dashboards/tier4_telemetry_test.py`
- **Scope**:
  - Direct live query execution against the cluster Thanos Querier (`http://localhost:9090` via `deploy/thanos-query` in namespace `monitoring`).
  - Substitutes template and range variables (`$datasource`, `$__rate_interval`, `$__interval`, `$__range`, `$route`, `$app`, `$namespace`, `$host`, `$service`) with evaluation values.
  - Validates HTTP 200 responses and PromQL `status == "success"`.
  - Asserts non-empty series population for all active cluster services:
    - ArgoCD Application inventory (`count(argocd_app_info) == 52`)
    - Envoy Gateway Ingress RPS (`envoy_http_downstream_rq_total`) and active connections (`envoy_http_downstream_cx_active`)
    - Zitadel HA pod readiness (`kube_deployment_status_replicas_available{namespace="zitadel"}`)
    - CloudNativePG database clusters (`count(cnpg_pg_replication_in_recovery)` and `cnpg_backends_total`)
    - MinIO storage capacity (`minio_cluster_capacity_usable_total_bytes`)
    - AI Assistant sessions (`antigravity_active_session_count`), Buzz relays (`buzz_community_ws_connections`), and MCP Slack bridge.
  - Executes all panel queries from loaded dashboards to prove live query execution without Prometheus evaluation errors.

---

## 3. Test Runner & Execution Guide

### Running the Complete Test Suite
```bash
# Run all tiers with text summary
./tests/e2e/dashboards/runner.sh

# Run all tiers with TAP output
./tests/e2e/dashboards/runner.sh --format tap

# Run all tiers with JSON output
./tests/e2e/dashboards/runner.sh --format json

# Run in offline mode (gracefully skip live queries if cluster unreachable)
./tests/e2e/dashboards/runner.sh --allow-offline
```

### Running Specific Test Tiers
```bash
# Run Tier 1 (Schema & Structure)
./tests/e2e/dashboards/runner.sh --tier 1
# or direct:
python3 tests/e2e/dashboards/tier1_schema_test.py

# Run Tier 2 (PromQL Syntax & Metric Integrity)
./tests/e2e/dashboards/runner.sh --tier 2
# or direct:
python3 tests/e2e/dashboards/tier2_promql_test.py

# Run Tier 3 (GitOps Integration & Consistency)
./tests/e2e/dashboards/runner.sh --tier 3
# or direct:
python3 tests/e2e/dashboards/tier3_integration_test.py

# Run Tier 4 (Live Telemetry Verification)
./tests/e2e/dashboards/runner.sh --tier 4
# or direct:
python3 tests/e2e/dashboards/tier4_telemetry_test.py
```

### Running with Bazel
```bash
# Run test runner via Bazel
bazel run //tests/e2e/dashboards:runner

# Run individual tier test targets
bazel test //tests/e2e/dashboards:tier1_schema_test
bazel test //tests/e2e/dashboards:tier2_promql_test
bazel test //tests/e2e/dashboards:tier3_integration_test
bazel test //tests/e2e/dashboards:tier4_telemetry_test
```
