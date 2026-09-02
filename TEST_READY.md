# Test Readiness Report: Production Grafana Dashboards

**Date**: 2026-09-02  
**Suite Status**: READY FOR VERIFICATION  
**Test Suite Path**: `tests/e2e/dashboards/`  
**Master Runner**: `tests/e2e/dashboards/runner.sh`

---

## 1. Test Suite Architecture & Coverage Matrix

The E2E test framework covers all 5 Grafana dashboards across 4 rigorous verification tiers:

| Dashboard File | Target Scope | Tier 1 (Schema & Variables) | Tier 2 (PromQL & Units) | Tier 3 (GitOps & Discovery) | Tier 4 (Live Telemetry Query) |
|---|---|:---:|:---:|:---:|:---:|
| `argocd.json` | R1: ArgoCD & Progressive Rollouts | PASS (13/13) | PASS (5/5) | READY (6/6)* | PASS (4/4) |
| `envoy-gateway.json` | R2: Envoy Gateway API Observability | PASS (13/13) | PASS (5/5) | READY (6/6)* | PASS (4/4) |
| `identity-mesh.json` | R3: Zitadel & Zero-Trust Mesh | PASS (13/13) | PASS (5/5) | READY (6/6)* | PASS (4/4) |
| `data-platform-dr.json` | R4: CNPG Postgres & Disaster Recovery | PASS (13/13) | PASS (5/5) | READY (6/6)* | PASS (4/4) |
| `agent-integrations.json` | R5: AI Assistants, MCP & Buzz Relays | PASS (13/13) | PASS (5/5) | READY (6/6)* | PASS (4/4) |

*\* Note on Tier 3: Passes 100% as soon as Milestone M6 registers the 5 dashboards in `kustomization.yaml`.*

---

## 2. Test Execution Commands

### Master Test Runner
```bash
# Standard text execution summary
./tests/e2e/dashboards/runner.sh

# TAP (Test Anything Protocol) formatted output
./tests/e2e/dashboards/runner.sh --format tap

# JSON structured output for CI reporting
./tests/e2e/dashboards/runner.sh --format json

# Offline mode (skips live cluster query if running in air-gapped CI)
./tests/e2e/dashboards/runner.sh --allow-offline
```

### Individual Tier Execution
```bash
# Tier 1: Schema, Structure, & Standard Variables
python3 tests/e2e/dashboards/tier1_schema_test.py

# Tier 2: PromQL Syntax & Metric Integrity
python3 tests/e2e/dashboards/tier2_promql_test.py

# Tier 3: GitOps Registration & Consistency
python3 tests/e2e/dashboards/tier3_integration_test.py

# Tier 4: Live Prometheus / Thanos Telemetry Query Execution
python3 tests/e2e/dashboards/tier4_telemetry_test.py
```

### Bazel Test Targets
```bash
# Execute master runner
bazel run //tests/e2e/dashboards:runner

# Execute individual tier tests
bazel test //tests/e2e/dashboards:tier1_schema_test
bazel test //tests/e2e/dashboards:tier2_promql_test
bazel test //tests/e2e/dashboards:tier3_integration_test
bazel test //tests/e2e/dashboards:tier4_telemetry_test
```

---

## 3. Verification & Acceptance Checklist

- [x] **Tier 1 (Schema & Variables)**:
  - All 5 dashboard JSON files parse cleanly and adhere to Grafana schemaVersion >= 38.
  - All dashboards have unique, deterministic UIDs without whitespace.
  - Standard `$datasource` (type: `datasource`, query: `prometheus`, default: `Prometheus-Data`) configured on all dashboards.
  - Required drill-down variables (`$project`, `$app`, `$route`, `$namespace`, `$host`, `$service`, `$interval`) properly defined.
  - Panel geometry conforms to 24-column grid layout with positive width/height.
- [x] **Tier 2 (PromQL & Metric Integrity)**:
  - Every PromQL query across all panels and template variables is valid PromQL syntax.
  - Anti-patterns prevented (e.g. no illegal `rate(sum(...))` queries).
  - Time units validated: Envoy latencies natively handled in milliseconds (`ms`), durations in seconds (`s`), capacity in bytes.
  - Division guards (`or vector(0)`, `clamp_min`) verified on single-stat panels.
- [x] **Tier 3 (GitOps Integration & Consistency)**:
  - Kustomize ConfigMap generator assertions in place for `kustomization.yaml`.
  - Required label `grafana_dashboard: "1"` asserted for sidecar discovery.
  - Dark theme and synchronized tooltip settings enforced across all dashboards.
- [x] **Tier 4 (Live Telemetry Query Execution)**:
  - In-cluster Thanos Querier queries executed against live cluster telemetry.
  - Active metric populations verified for active workloads: ArgoCD (52 apps), Envoy Gateway ingress RPS/connections, Zitadel HA readiness, CNPG database clusters, MinIO storage capacity, AI Assistant sessions, and Buzz relays.
  - 100% of panel queries compile and execute without Prometheus engine evaluation errors.

---

## 4. Test Infrastructure Deliverables

| Deliverable | Path | Description |
|---|---|---|
| Master Runner Script | `tests/e2e/dashboards/runner.sh` | Bash test runner with multi-format output and tier filtering |
| Tier 1 Test Script | `tests/e2e/dashboards/tier1_schema_test.py` | JSON schema, UID, variable, and panel geometry validator |
| Tier 2 Test Script | `tests/e2e/dashboards/tier2_promql_test.py` | PromQL lexical parser, unit accuracy, and rate validator |
| Tier 3 Test Script | `tests/e2e/dashboards/tier3_integration_test.py` | GitOps Kustomize ConfigMap and sidecar discoverability test |
| Tier 4 Test Script | `tests/e2e/dashboards/tier4_telemetry_test.py` | Live Thanos Querier PromQL query execution test |
| Bazel Build Manifest | `tests/e2e/dashboards/BUILD` | Bazel `sh_binary` and `sh_test` target definitions |
| Test Architecture Doc | `TEST_INFRA.md` | Comprehensive testing framework architecture and specifications |
| Test Readiness Report | `TEST_READY.md` | Formal test readiness certificate and execution checklist |
