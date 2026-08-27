# Service Operational Maturity Scorecards & Governance

This document codifies the operational maturity tiers (Bronze, Silver, Gold) evaluated for all components and services in the Backstage Software Catalog.

## Operational Maturity Tiers

### 🥉 Bronze Tier (Baseline Quality)
Every service registered in the catalog must meet Bronze tier before landing in production:
- **Ownership**: `spec.owner` assigned to a valid GitHub team in `.github/CODEOWNERS` (e.g. `platform-team`, `tabula-team`, `devx-team`).
- **Lifecycle & System**: Valid `spec.lifecycle` (`experimental`, `development`, `production`) and valid `spec.system` assignment.
- **Description**: Clear, non-empty `metadata.description` describing what the service does.
- **Documentation**: `backstage.io/techdocs-ref` pointing to working markdown documentation.

---

### 🥈 Silver Tier (Production Ready)
Required for any workload serving live internal or developer traffic:
- **All Bronze Requirements Satisfied**.
- **CI/CD Pipeline**: Declared CI/CD release workflow (`vitruvian.dev/release-workflow` or GitHub Actions pipeline).
- **Runtime Environment Binding**:
  - Cloud Run services: explicit `vitruvian.dev/cloud-run-services` mappings.
  - Kubernetes workloads: `backstage.io/kubernetes-id`, `backstage.io/kubernetes-namespace`, and `backstage.io/kubernetes-label-selector`.
- **Observability**: Direct Grafana dashboard binding (`grafana/dashboard-selector`) or metrics endpoint.
- **Artifact Publishing**: Container image (GHCR) or npm/Go binary release link.

---

### 🥇 Gold Tier (Operational Excellence)
Required for mission-critical core platforms and public-facing SaaS applications:
- **All Silver Requirements Satisfied**.
- **Live Health & Uptime**: Configured Uptime Kuma monitoring with public status link (`status.ipv1337.dev`).
- **Incident Response**: Direct link to the standardized Incident Triage Runbook (`docs/operations/incident-triage-runbook.md`).
- **API Contract Registration**: Component declares provided and consumed `kind: API` definitions (`spec.providesApis`, `spec.consumesApis`).
- **Infrastructure Dependency Topology**: Downstream dependencies explicitly declared via `spec.dependsOn`.
- **Progressive Delivery**: Canary deployment with automated metric analysis where applicable (Argo Rollouts).

---

## Component Maturity Audit Matrix

| Component | Owner | Lifecycle | System | TechDocs | Runtime / CI | APIs & Topology | Incident Runbook | Tier |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **`backstage`** | `platform-team` | `production` | `developer-portal` | ✅ | ✅ (k3s / ArgoCD) | ✅ (`backstage-mcp-api`) | ✅ | **Gold** |
| **`tabula`** | `tabula-team` | `production` | `tabula-platform` | ✅ | ✅ (Cloud Run) | ✅ (`tabula-api`) | ✅ | **Gold** |
| **`oauth-user-inspector`** | `oauth-user-inspector-team` | `production` | `oauth-user-inspector` | ✅ | ✅ (Cloud Run) | ✅ (`oauth-inspector-api`) | ✅ | **Gold** |
| **`buzz`** | `platform-team` | `production` | `buzz-relay` | ✅ | ✅ (k3s / Helm) | ✅ (`buzz-relay-api`) | ✅ | **Gold** |
| **`mcp-slack`** | `mcp-slack-team` | `production` | `mcp-slack` | ✅ | ✅ (k3s / npm) | ✅ (`mcp-slack-api`) | ✅ | **Gold** |
| **`devx`** | `devx-team` | `production` | `devx-suite` | ✅ | ✅ (GoReleaser) | N/A (CLI Tool) | N/A (CLI) | **Silver** |
| **`homelab`** | `homelab-team` | `production` | `devx-suite` | ✅ | ✅ (GoReleaser) | N/A (CLI Tool) | N/A (CLI) | **Silver** |
| **`nexus-agent`** | `nexus-agent-team` | `production` | `nexus-agent` | ✅ | ✅ (DMG / npm) | ✅ (`consumesApis`) | N/A (Desktop) | **Silver** |
| **`whoami`** | `platform-team` | `production` | `reference-workloads` | ✅ | ✅ (k3s / Rollouts) | N/A (Echo) | ✅ | **Silver** |
| **`storybook`** | `platform-team` | `production` | `reference-workloads` | ✅ | ✅ (k3s / ArgoCD) | N/A (Static) | ✅ | **Silver** |
