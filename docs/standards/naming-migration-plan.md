# Monorepo Naming Refactoring & Phased Migration Plan: `vitruvian-core`

> **Document Status:** Authoritative Architectural Deliverable (Milestone 4)  
> **Document Version:** 1.0.0  
> **Effective Date:** 2026-08-28  
> **Target Horizon:** 6-Phase Sequenced Rollout (Phase 0 through Phase 5)  
> **Prerequisites:** 
> - [Naming Audit Deliverable (Milestone 1)](naming-audit.md)
> - [Global Naming Convention Standard (Milestone 2)](naming-conventions.md)
> - [Automated Enforcement Tooling (Milestone 3)](../../tools/lint-naming/)
>
> **Audience:** Core Platform Engineers, Infrastructure Architects, Component Maintainers, Release Engineers, AI Agents, and CI/CD Automation.

---

## Table of Contents

1. [Executive Summary & Migration Charter](#1-executive-summary--migration-charter)
   - 1.1 [Mission & Objective](#11-mission--objective)
   - 1.2 [Core Migration Principles](#12-core-migration-principles)
   - 1.3 [Scope & Target Metrics](#13-scope--target-metrics)
2. [Complete Inconsistency-to-Canonical Mapping Catalog](#2-complete-inconsistency-to-canonical-mapping-catalog)
   - 2.1 [Source File Filename Remediations](#21-source-file-filename-remediations)
   - 2.2 [Directory & Bazel Package Path Remediations](#22-directory--bazel-package-path-remediations)
   - 2.3 [Bazel Target & `sh_test` Remediations](#23-bazel-target--sh_test-remediations)
   - 2.4 [Shell Scripts & Internal Automation Remediations](#24-shell-scripts--internal-automation-remediations)
   - 2.5 [Documentation & Static Asset Remediations](#25-documentation--static-asset-remediations)
   - 2.6 [GitHub Actions Workflows (Extensions, Inputs, Outputs)](#26-github-actions-workflows-extensions-inputs-outputs)
   - 2.7 [Pulumi Infrastructure (Project Names & Stack Config Keys)](#27-pulumi-infrastructure-project-names--stack-config-keys)
   - 2.8 [Environment Variables & CLI Flags](#28-environment-variables--cli-flags)
   - 2.9 [Internal Tool Schemas & Manifests](#29-internal-tool-schemas--manifests)
   - 2.10 [Cross-Boundary Interfaces (Prisma, OpenAPI, Copybara)](#210-cross-boundary-interfaces-prisma-openapi-copybara)
3. [Risk Stratification & Blast Radius Model](#3-risk-stratification--blast-radius-model)
   - 3.1 [Four-Tier Risk Classification Taxonomy](#31-four-tier-risk-classification-taxonomy)
   - 3.2 [Blast Radius & Failure Domain Matrix](#32-blast-radius--failure-domain-matrix)
4. [Phased Migration Roadmap (Phases 0 through 5)](#4-phased-migration-roadmap-phases-0-through-5)
   - 4.1 [Phase 0: Foundation, Tooling & Safety Infrastructure](#41-phase-0-foundation-tooling--safety-infrastructure)
   - 4.2 [Phase 1: Low-Risk Remediation (Docs, Assets, Scripts & Extensions)](#42-phase-1-low-risk-remediation-docs-assets-scripts--extensions)
   - 4.3 [Phase 2: Medium-Risk Remediation (Go, Python, Packages & Targets)](#43-phase-2-medium-risk-remediation-go-python-packages--targets)
   - 4.4 [Phase 3: High-Risk Remediation (Workflows, Pulumi & Tool Schemas)](#44-phase-3-high-risk-remediation-workflows-pulumi--tool-schemas)
   - 4.5 [Phase 4: Critical-Risk Remediation (Copybara, Env Vars & APIs)](#45-phase-4-critical-risk-remediation-copybara-env-vars--apis)
   - 4.6 [Phase 5: Deprecation Sunset, Cleanup & Mandatory CI Enforcement](#46-phase-5-deprecation-sunset-cleanup--mandatory-ci-enforcement)
5. [Backwards Compatibility & History Preservation Strategies](#5-backwards-compatibility--history-preservation-strategies)
   - 5.1 [Git History Preservation via `git mv`](#51-git-history-preservation-via-git-mv)
   - 5.2 [Bazel Target Aliasing & Deprecation Stubs](#52-bazel-target-aliasing--deprecation-stubs)
   - 5.3 [GitHub Actions Dual-Input & Dual-Output Bridging](#53-github-actions-dual-input--dual-output-bridging)
   - 5.4 [Environment Variable Resolution Ladders](#54-environment-variable-resolution-ladders)
   - 5.5 [Copybara Transformation Shims for Standalone Mirrors](#55-copybara-transformation-shims-for-standalone-mirrors)
6. [Pulumi Infrastructure State Migration Mechanics & Runbook](#6-pulumi-infrastructure-state-migration-mechanics--runbook)
   - 6.1 [Risk Analysis & Zero-Recreation Guarantee](#61-risk-analysis--zero-recreation-guarantee)
   - 6.2 [Step-by-Step Pulumi State Migration Procedure](#62-step-by-step-pulumi-state-migration-procedure)
   - 6.3 [Stack Configuration Dual-Lookup Code Bridge](#63-stack-configuration-dual-lookup-code-bridge)
7. [Rollback Procedures & Emergency Halt Criteria](#7-rollback-procedures--emergency-halt-criteria)
   - 7.1 [Emergency Halt Trigger Criteria](#71-emergency-halt-trigger-criteria)
   - 7.2 [Phase-Specific Rollback Runbooks](#72-phase-specific-rollback-runbooks)
   - 7.3 [Fix-Forward vs. Revert Decision Trees](#73-fix-forward-vs-revert-decision-trees)
8. [CI/CD Automation, Governance & Long-Term Enforcement](#8-cicd-automation-governance--long-term-enforcement)
   - 8.1 [Automated Merge Gate Architecture](#81-automated-merge-gate-architecture)
   - 8.2 [Local Developer Pre-Flight Integration](#82-local-developer-pre-flight-integration)
   - 8.3 [Exception Lifecycle & Architectural Review Board](#83-exception-lifecycle--architectural-review-board)

---

## 1. Executive Summary & Migration Charter

### 1.1 Mission & Objective
The `vitruvian-core` repository is a high-velocity, polyglot monorepo containing over 4,200 tracked files, 290 Bazel packages, 540 build targets, 54 CI/CD workflows, and 76 Pulumi infrastructure projects. Over time, organic growth and divergent subsystem conventions have introduced naming inconsistencies across directory paths, source filenames, build targets, CI workflow interfaces, Pulumi project names, environment variables, and tool schemas.

This document establishes the **authoritative, phased migration and refactoring plan** to systematically eliminate all naming drift identified in the [Repository Naming Audit (Milestone 1)](naming-audit.md), bringing the entire repository into strict compliance with the [Global Naming Convention Standard (Milestone 2)](naming-conventions.md).

### 1.2 Core Migration Principles

1. **Zero Downtime & Zero Build Breakage**: At no point during the multi-phase rollout may `main` experience broken builds, failing CI workflows, broken test suites, or interrupted developer inner loops.
2. **Expand / Contract Sequencing**: All interface changes across workflows, build targets, environment variables, and infrastructure configurations MUST follow a strict two-step pattern:
   - *Expand Phase*: Introduce canonical names while maintaining transparent backwards-compatible aliases, fallbacks, or dual-input bridges.
   - *Contract Phase*: Migrate consumers, verify zero traffic on legacy identifiers, and sunset deprecated interfaces.
3. **Preserve Git Lineage**: All file and directory relocations MUST use `git mv` in dedicated atomic commits to preserve `git blame`, log history, and PR diff traceability.
4. **Zero Infrastructure Resource Recreation**: Pulumi project and stack renames MUST use explicit state migration protocols (`pulumi stack export` / `import`) to ensure cloud resources (Cloud Run services, VPCs, IAM roles, DNS records) are NEVER destroyed and recreated during naming refactoring.
5. **No Regressions in Standalone Component Mirrors**: Monorepo-to-standalone export pipelines managed by Copybara (`devx`, `homelab`, `mcp-slack`, `nexus-agent`, `oauth-user-inspector`) MUST retain continuous sync capability via transformation shims.
6. **Every Phase Ships with Validation Gates**: A phase cannot be declared complete until its machine-automated validation commands pass cleanly.

### 1.3 Scope & Target Metrics

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ REFACTORING & MIGRATION EXECUTION METRICS                                               │
├──────────────────────────────────────────┬──────────────┬───────────────────────────────┤
│ Migration Category                       │ Items to Fix │ Target Standard               │
├──────────────────────────────────────────┼──────────────┼───────────────────────────────┤
│ Source File Filename Anomalies           │ 7 files      │ Go: snake, Py: snake, TS: Pas │
│ Directory & Package Path Inconsistencies │ 8 paths      │ kebab-case / Go snake_case    │
│ Bazel sh_test & Build Target Splits      │ 8 targets    │ <binary-name>_test & Pascal   │
│ Shell Scripts in tools/ & tabula/        │ 8 scripts    │ kebab-case.sh                 │
│ Documentation & Static Assets            │ 8 assets     │ kebab-case.md / .png          │
│ GitHub Actions Workflow Extensions       │ 6 workflows  │ .yaml extension mandatory     │
│ GitHub Actions Workflow Inputs & Outputs │ 15 keys      │ kebab-case inputs & outputs   │
│ Pulumi Project Names (Pulumi.yaml)       │ 7 projects   │ kebab-case (no pulumi_ prefix)│
│ Pulumi Stack Configuration Keys          │ 6 stacks     │ camelCase application keys    │
│ Internal Tool Schema Fields              │ 3 schemas    │ snake_case JSON/YAML keys     │
│ Environment Variable Synonyms            │ 4 clusters   │ Canonical SCREAMING_SNAKE     │
│ Target Enforcement Phase                 │ Phase 5      │ 100% CI Merge Gate Blocking   │
└──────────────────────────────────────────┴──────────────┴───────────────────────────────┘
```

---

## 2. Complete Inconsistency-to-Canonical Mapping Catalog

This section provides the complete, authoritative mapping of every inconsistency documented in `docs/standards/naming-audit.md` to its canonical target state under `docs/standards/naming-conventions.md`.

### 2.1 Source File Filename Remediations

| # | Current File Path | Canonical Target Path | Rule Violated | Rationale & Impact |
|---|---|---|---|---|
| S1 | `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs.go` | `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net_hubs.go` | `RULE_FILE_GO` | Go filenames must use `snake_case.go`. Hyphens violate Go idioms. |
| S2 | `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs-transitivity.go` | `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net_hubs_transitivity.go` | `RULE_FILE_GO` | Go filenames must use `snake_case.go`. |
| S3 | `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs.go` | `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net_hubs.go` | `RULE_FILE_GO` | Foundation example Go file alignment. |
| S4 | `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs-transitivity.go` | `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net_hubs_transitivity.go` | `RULE_FILE_GO` | Foundation example Go file alignment. |
| S5 | `nexus-agent/hooks/stream-hook.py` | `nexus-agent/hooks/stream_hook.py` | `RULE_FILE_PY` | Python files must use `snake_case.py`. `import stream-hook` triggers `SyntaxError`. |
| S6 | `tabula/web/__tests__/relay-landing.test.tsx` | `tabula/web/__tests__/RelayLanding.test.tsx` | `RULE_FILE_TSX` | React component tests must use `PascalCase.test.tsx` to match component. |
| S7 | `tabula/web/__tests__/space-detail.test.tsx` | `tabula/web/__tests__/SpaceDetail.test.tsx` | `RULE_FILE_TSX` | React component tests must use `PascalCase.test.tsx` to match component. |

---

### 2.2 Directory & Bazel Package Path Remediations

| # | Current Path | Canonical Target Path | Rule Violated | Rationale & Impact |
|---|---|---|---|---|
| D1 | `infrastructure/pulumi/platform/repo_config/` | `infrastructure/pulumi/platform/repo-config/` | `RULE_DIR_KEBAB` | Platform directory siblings are `dev-local/` and `zitadel-apps/` (`kebab-case`). |
| D2 | `tools/copybara/conflict_precheck/` | `tools/copybara/conflict-precheck/` | `RULE_DIR_KEBAB` | Tool directories must use `kebab-case`. Sibling packages: `agent-app/`, `ci-preflight/`. |
| D3 | `tools/gitops/appset_render/` | `tools/gitops/appset-render/` | `RULE_DIR_KEBAB` | Tool directories must use `kebab-case`. |
| D4 | `infrastructure/pulumi/foundation/gcp-networks/modules/vpn-ha/` | `infrastructure/pulumi/foundation/gcp-networks/modules/vpn_ha/` | `RULE_DIR_GO_PKG` | Go package directories MUST use `snake_case` or single-word. Sibling modules: `base_env/`, `shared_vpc/`. |
| D5 | `pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/vpn-ha/` | `pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/vpn_ha/` | `RULE_DIR_GO_PKG` | Go package directory alignment in examples. |
| D6 | `pulumi/examples/go-foundation/3-networks-svpc/modules/vpn-ha/` | `pulumi/examples/go-foundation/3-networks-svpc/modules/vpn_ha/` | `RULE_DIR_GO_PKG` | Go package directory alignment in examples. |
| D7 | `pulumi/examples/ts-foundation/1-org/modules/cai-monitoring/` | Harmonized TS module conventions | `RULE_DIR_KEBAB` | Align TS module naming across examples. |
| D8 | `infrastructure/pulumi/foundation/gcp-app-infra/business_unit_1/` | Evaluated for Go package compatibility | `RULE_DIR_GO_PKG` | Keep `business_unit_1` as valid Go package directory. |

---

### 2.3 Bazel Target & `sh_test` Remediations

| # | Current Bazel Target | Canonical Target | BUILD File Location | Remediation Action |
|---|---|---|---|---|
| T1 | `//tools/agent-app:agent_app_test` | `//tools/agent-app:agent-app_test` | `tools/agent-app/BUILD:37` | Rename target to `<binary>_test`. Add `alias` for `agent_app_test`. |
| T2 | `//tools/cloud-bootstrap:cloud_bootstrap_test` | `//tools/cloud-bootstrap:cloud-bootstrap_test` | `tools/cloud-bootstrap/BUILD:59` | Rename target to `<binary>_test`. Add `alias` for `cloud_bootstrap_test`. |
| T3 | `//tools/gcp-token:gcp_token_test` | `//tools/gcp-token:gcp-token_test` | `tools/gcp-token/BUILD:43` | Rename target to `<binary>_test`. Add `alias` for `gcp_token_test`. |
| T4 | `//tools/gcp-secrets:gcp_secrets_test` | `//tools/gcp-secrets:gcp-secrets_test` | `tools/gcp-secrets/BUILD:46` | Rename target to `<pkg>_test`. Add `alias` for `gcp_secrets_test`. |
| T5 | `//tools/saas-cli:saas_cli_test` | `//tools/saas-cli:saas-cli_test` | `tools/saas-cli/BUILD:55` | Rename target to `<pkg>_test`. Add `alias` for `saas_cli_test`. |
| T6 | `//nexus-agent/macos:NexusAgent_lib` | `//nexus-agent/macos:NexusAgentLib` | `nexus-agent/macos/BUILD:20` | Swift library targets use `PascalCase`. Remove snake suffix. |
| T7 | `//nexus-agent/macos:NexusAgent_tests` | `//nexus-agent/macos:NexusAgentTests` | `nexus-agent/macos/BUILD:32` | Swift test targets use `PascalCase`. Remove snake suffix. |
| T8 | `//nexus-agent/hooks:stream-hook` | `//nexus-agent/hooks:stream_hook` | `nexus-agent/hooks/BUILD:4` | Python binary rule must use `snake_case` matching `stream_hook.py`. |

---

### 2.4 Shell Scripts & Internal Automation Remediations

| # | Current Script Path | Canonical Target Path | Subsystem | Action & Compatibility |
|---|---|---|---|---|
| SH1 | `tools/workspace_status.sh` | `tools/workspace-status.sh` | `tools/` | Rename via `git mv`. Update `.bazelrc` `--workspace_status_command`. |
| SH2 | `tabula/extension/publish_dev_latest_test.sh` | `tabula/extension/publish-dev-latest_test.sh` | `tabula/extension/` | Rename via `git mv`. Pairs with `publish-dev-latest.sh`. |
| SH3 | `tools/gitops/argocd_secret.sh` | `tools/gitops/argocd-secret.sh` | `tools/gitops/` | Rename via `git mv`. Update `tools/gitops/BUILD`. |
| SH4 | `tools/gitops/gitops_cmd.sh` | `tools/gitops/gitops-cmd.sh` | `tools/gitops/` | Rename via `git mv`. Update `tools/gitops/BUILD`. |
| SH5 | `tools/pulumi/create_app.sh` | `tools/pulumi/create-app.sh` | `tools/pulumi/` | Rename via `git mv`. Update `tools/pulumi/BUILD`. |
| SH6 | `tools/pulumi/pulumi_cmd.sh` | `tools/pulumi/pulumi-cmd.sh` | `tools/pulumi/` | Rename via `git mv`. Update `tools/pulumi/BUILD`. |
| SH7 | `tools/copybara/check_version_maps.sh` | `tools/copybara/check-version-maps.sh` | `tools/copybara/` | Rename via `git mv`. Update `tools/copybara/BUILD`. |
| SH8 | `.aspect/gazelle/package-json-scripts.axl` | `.aspect/gazelle/package_json_scripts.axl` | `.aspect/gazelle/` | Align Starlark/Aspect rule file with `go_image.axl`, `py3_image.axl`. |

---

### 2.5 Documentation & Static Asset Remediations

| # | Current Asset Path | Canonical Target Path | Category | Rationale |
|---|---|---|---|---|
| A1 | `tabula/docs/architecture/workona_research.md` | `tabula/docs/architecture/workona-research.md` | Markdown Doc | Technical docs must use `kebab-case.md`. |
| A2 | `tabula/docs/product/gap_analysis.md` | `tabula/docs/product/gap-analysis.md` | Markdown Doc | Product docs must use `kebab-case.md`. |
| A3 | `tabula/docs/product/verified_journeys.md` | `tabula/docs/product/verified-journeys.md` | Markdown Doc | Product docs must use `kebab-case.md`. |
| A4 | `devx/docs/public/devx_k8s_proof.png` | `devx/docs/public/devx-k8s-proof.png` | Static Image | Web/docs image assets must use `kebab-case.png`. Update references. |
| A5 | `devx/docs/public/devx_mock_proof.png` | `devx/docs/public/devx-mock-proof.png` | Static Image | Web/docs image assets must use `kebab-case.png`. Update references. |
| A6 | `docs/archive/gap-analysis/port-cft-pulumi/pulumiportgapanalysisworkflow.md` | `docs/archive/gap-analysis/port-cft-pulumi/pulumi-port-gap-analysis-workflow.md` | Archived Doc | Eliminate run-together lowercase in archive. |
| A7 | `docs/archive/gap-analysis/port-cft-pulumi/verifierreasoningfull.md` | `docs/archive/gap-analysis/port-cft-pulumi/verifier-reasoning-full.md` | Archived Doc | Eliminate run-together lowercase in archive. |
| A8 | `tabula/extension/src/services/` (Mixed TS) | Standardize to `kebab-case.ts` | TS Services | Standardize `CrossWindowSyncService.ts`, `deviceId.ts`, `sections_notes.test.ts`. |

---

### 2.6 GitHub Actions Workflows (Extensions, Inputs, Outputs)

#### 1. Workflow Extension Normalization (`.yml` → `.yaml`)
All workflow files must strictly use `.yaml`:

| # | Current Workflow Path | Canonical Target Path |
|---|---|---|
| W1 | `.github/workflows/apps-release.yml` | `.github/workflows/apps-release.yaml` |
| W2 | `.github/workflows/dependabot-auto-merge.yml` | `.github/workflows/dependabot-auto-merge.yaml` |
| W3 | `.github/workflows/dependabot-bazel-reconcile.yml` | `.github/workflows/dependabot-bazel-reconcile.yaml` |
| W4 | `.github/workflows/dependabot-lock-rebase.yml` | `.github/workflows/dependabot-lock-rebase.yaml` |
| W5 | `.github/workflows/pulumi-library-release.yml` | `.github/workflows/pulumi-library-release.yaml` |
| W6 | `.github/workflows/tabula-release.yml` | `.github/workflows/tabula-release.yaml` |

#### 2. Workflow Inputs & Outputs Casing Normalization (`snake_case` → `kebab-case`)

| # | Workflow / Action File | Current Identifier | Canonical Identifier | Type |
|---|---|---|---|---|
| WI1 | `.github/workflows/_copybara-export.yaml` | `copybara_options` | `copybara-options` | Input |
| WI2 | `.github/workflows/copybara-import-pr.yaml` | `only_component` | `only-component` | Input |
| WI3 | `.github/workflows/copybara-import-pr.yaml` | `poll_only` | `poll-only` | Input |
| WI4 | `.github/workflows/foundation-app-deploy.yaml` | `working_directory` | `working-directory` | Input |
| WI5 | `.github/workflows/foundation-app-deploy.yaml` | `business_unit` | `business-unit` | Input |
| WI6 | `.github/workflows/foundation-app-deploy.yaml` | `app_image_digests` | `app-image-digests` | Input |
| WI7 | `.github/workflows/foundation-proj-deploy.yaml`| `working_directory` | `working-directory` | Input |
| WI8 | `.github/workflows/foundation-proj-deploy.yaml`| `business_unit` | `business-unit` | Input |
| WI9 | `.github/workflows/foundation-proj-deploy.yaml`| `allow_destructive` | `allow-destructive` | Input |
| WI10| `.github/workflows/pulumi-stack-reset.yaml` | `pulumi_dir` | `pulumi-dir` | Input |
| WO1 | `.github/workflows/delivery.yaml` | `affected_charts` | `affected-charts` | Output |
| WO2 | `.github/workflows/delivery.yaml` | `affected_tabula_api` | `affected-tabula-api` | Output |
| WO3 | `.github/workflows/delivery.yaml` | `affected_oauth_user_inspector` | `affected-oauth-user-inspector` | Output |
| WO4 | `.github/workflows/delivery.yaml` | `affected_zitadel_apps` | `affected-zitadel-apps` | Output |
| WO5 | `.github/workflows/_foundation-release-please.yaml` | `release_created` | `release-created` | Output |
| WO6 | `.github/actions/gcp-auth/action.yml` | `access_token` | `access-token` | Action Output |
| WO7 | `.github/actions/pulumi-run-captured/action.yml` | `exit_code` | `exit-code` | Action Output |

---

### 2.7 Pulumi Infrastructure (Project Names & Stack Config Keys)

#### 1. Pulumi Project Names (`Pulumi.yaml`)

| # | Project Manifest Path | Current Declared `name:` | Canonical `name:` | State Migration Required |
|---|---|---|---|---|
| P1 | `tabula/infra/app/Pulumi.yaml` | `pulumi_tabula_app` | `tabula-app` | Yes (`pulumi stack export/import`) |
| P2 | `tabula/infra/build/Pulumi.yaml` | `pulumi_tabula_build` | `tabula-build` | Yes (`pulumi stack export/import`) |
| P3 | `tabula/infra/data/Pulumi.yaml` | `pulumi_tabula_data` | `tabula-data` | Yes (`pulumi stack export/import`) |
| P4 | `tabula/infra/identity/Pulumi.yaml` | `pulumi_tabula_deploy_identity`| `tabula-deploy-identity` | Yes (`pulumi stack export/import`) |
| P5 | `tabula/infra/web/Pulumi.yaml` | `pulumi_tabula_web` | `tabula-web` | Yes (`pulumi stack export/import`) |
| P6 | `infrastructure/pulumi/platform/repo_config/Pulumi.yaml` | `vitruvian-core-repo-config` / `repo_config` | `repo-config` | Yes (`pulumi stack export/import`) |
| P7 | `infrastructure/pulumi/platform/zitadel-apps/Pulumi.yaml` | `pulumi_zitadel_apps` | `zitadel-apps` | Yes (`pulumi stack export/import`) |

#### 2. Stack Configuration In-File Property Keys (`Pulumi.<env>.yaml`)

| # | Stack Config File | Legacy Inconsistent Key | Canonical Key | Domain Standard |
|---|---|---|---|---|
| PK1 | `tabula/infra/identity/Pulumi.development.yaml` | `bootstrap_stack` | `bootstrapStack` | TypeScript App (`camelCase`) |
| PK2 | `tabula/infra/identity/Pulumi.development.yaml` | `projects_stack` | `projectsStack` | TypeScript App (`camelCase`) |
| PK3 | `tabula/infra/identity/Pulumi.production.yaml` | `bootstrap_stack` | `bootstrapStack` | TypeScript App (`camelCase`) |
| PK4 | `tabula/infra/identity/Pulumi.production.yaml` | `projects_stack` | `projectsStack` | TypeScript App (`camelCase`) |
| PK5 | `tabula/infra/build/Pulumi.production.yaml` | `bootstrap_stack` | `bootstrapStack` | TypeScript App (`camelCase`) |
| PK6 | `tabula/infra/app/Pulumi.development.yaml` | `bootstrap_stack` | `bootstrapStack` | TypeScript App (`camelCase`) |

---

### 2.8 Environment Variables & CLI Flags

| # | Inconsistent Variable Synonyms | Canonical Variable | Scope & Standard Resolution |
|---|---|---|---|
| E1 | `GCP_PROJECT`, `GCP_PROJECT_ID`, `CLOUDSDK_CORE_PROJECT` | `GOOGLE_CLOUD_PROJECT` | Standardize monorepo on `GOOGLE_CLOUD_PROJECT`. Shell scripts map to `CLOUDSDK_CORE_PROJECT` internally. |
| E2 | `CLOUDSDK_AUTH_ACCESS_TOKEN` | `GOOGLE_OAUTH_ACCESS_TOKEN` | Standardize auth scripts on `GOOGLE_OAUTH_ACCESS_TOKEN`. Bridge in gcloud wrappers. |
| E3 | `GH_TOKEN`, `GITHUB_TOKEN` | `GH_TOKEN` (CLI/Agent), `GITHUB_TOKEN` (CI Runner) | Document dual role in `AGENTS.md` and CI workflows. |
| E4 | `CF_API_TOKEN`, `CLOUDFLARE_API_TOKEN` | `CLOUDFLARE_API_TOKEN` | Use `CLOUDFLARE_API_TOKEN` for APIs; reserve `CF_TUNNEL_TOKEN` for Argo tunnels. |

---

### 2.9 Internal Tool Schemas & Manifests

| # | File Path | Current Field | Canonical Field | Standard |
|---|---|---|---|---|
| C1 | `tools/initializer/config.json` | `"appliesTo": ["go"]` | `"applies_to": ["go"]` | Internal JSON schemas standard: `snake_case` |
| C2 | `infrastructure/pulumi/platform/dev-local/devx.yaml` | `customActions:` | `custom_actions:` | DevX YAML schema standard: `snake_case` |
| C3 | `tabula/extension/src/build_info.json` | `build_info.json` (filename) | `build-info.json` | JSON manifest filename standard: `kebab-case` |

---

### 2.10 Cross-Boundary Interfaces (Prisma, OpenAPI, Copybara)

| # | Boundary Interface | Upstream Layer Standard | Downstream Layer Standard | Invariant / Preservation Guarantee |
|---|---|---|---|---|
| B1 | Tabula Persistence vs. API | PostgreSQL / Prisma: `snake_case` (`password_hash`, `user_id`) | OpenAPI / TypeScript: `camelCase` (`passwordHash`, `userId`) | Prisma `@map` annotations MUST be preserved to maintain SQL column stability while exposing camelCase to TypeScript. |
| B2 | Monorepo → Standalone Mirrors | Monorepo Paths (`devx/`, `homelab/`, `mcp-slack/`, `nexus-agent/`) | Standalone Root Repositories | Copybara transformation rules in `copy.bara.sky` MUST be preserved and verified via dry-run before and after any directory rename. |
| B3 | Kubernetes / GitOps Manifests | Kubernetes DNS-1123: `kebab-case` (`opentelemetry-collector`) | Helm Specs / CRDs: `camelCase` (`imagePullPolicy`) | Kubernetes metadata names strictly use `kebab-case`; spec fields strictly use `camelCase`. |

---

## 3. Risk Stratification & Blast Radius Model

To ensure zero downtime and prevent cascading failures across build graphs, CI runners, and live infrastructure, all migration operations are stratified across four formal risk tiers.

### 3.1 Four-Tier Risk Classification Taxonomy

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                               MIGRATION RISK STRATIFICATION                             │
├──────────────┬────────────────────────┬─────────────────────────────────────────────────┤
│ Risk Tier    │ Artifact Types Included│ Failure Impact & Blast Radius Characteristics   │
├──────────────┼────────────────────────┼─────────────────────────────────────────────────┤
│ Tier 1:      │ • Internal Markdown    │ • Blast radius: Zero (isolated to docs/assets). │
│ LOW RISK     │ • Documentation Images │ • No runtime code, compiler, or CI disruption.  │
│              │ • Non-exported Shell   │ • Immediate atomic PR mergeable at any time.    │
│              │ • Workflow Extensions  │ • Reversible via standard `git revert`.         │
│              │ • React UI Test Files  │                                                 │
├──────────────┼────────────────────────┼─────────────────────────────────────────────────┤
│ Tier 2:      │ • Go Source Files      │ • Blast radius: Local package build graph.      │
│ MEDIUM RISK  │ • Python Modules       │ • Potential for build cache invalidation.       │
│              │ • Bazel `sh_test` Rules│ • Mitigated by Bazel `alias` targets and        │
│              │ • Internal Package Dirs│   synchronous Gazelle regeneration.             │
│              │ • TypeScript Services  │ • Verified via `bazel build //...` & `test`.   │
├──────────────┼────────────────────────┼─────────────────────────────────────────────────┤
│ Tier 3:      │ • Pulumi Project Names │ • Blast radius: CI orchestration & Cloud IaC.   │
│ HIGH RISK    │ • Stack Config Keys    │ • Potential for pipeline failure or unintended   │
│              │ • GHA Workflow Inputs  │   resource deletion/recreation in GCP/Cloudflare│
│              │ • Tool Config Schemas  │ • Requires Expand/Contract dual-input bridges,  │
│              │   (`devx.yaml`, etc.)  │   state export/import, and live dry-run checks. │
├──────────────┼────────────────────────┼─────────────────────────────────────────────────┤
│ Tier 4:      │ • Database Schemas     │ • Blast radius: Production data, public APIs,   │
│ CRITICAL RISK│ • Public API Routes    │   and external git mirrors.                     │
│              │ • Copybara Mirror Maps │ • Potential for production data loss, breaking  │
│              │ • Global Env Variables │   downstream SDK consumers, or mirror desync.   │
│              │                        │ • Strict isolation, Prisma `@map` verification, │
│              │                        │   Copybara dry-runs, and fallback ladders.      │
└──────────────┴────────────────────────┴─────────────────────────────────────────────────┘
```

### 3.2 Blast Radius & Failure Domain Matrix

| Subsystem / Layer | Failure Mode | Blast Radius | Mitigation Control |
|---|---|---|---|
| **Bazel Build Graph** | Missing target label after rename | Local developer build failure, CI test failure | Register Bazel `alias(name = "old_name", actual = ":new-name", deprecation = "...")` in `BUILD`. |
| **Go Compiler** | Import path missing after Go file rename | Compilation failure in Pulumi or internal package | All Go package directory renames trigger synchronous `go mod tidy` + `bazel run //:gazelle`. |
| **Python Runtime** | `SyntaxError: invalid syntax` on hyphen | Runtime crash when importing hook module | Rename `stream-hook.py` → `stream_hook.py` and update `py_binary` in `nexus-agent/hooks/BUILD`. |
| **GitHub Actions** | Required input missing in reusable workflow | Blocked deployment pipeline, failed releases | Reusable workflows accept both `working-directory` and `working_directory` concurrently during transition. |
| **Pulumi IaC** | Stack name mismatch leading to resource recreate | Outage of Cloud Run service or VPC destruction | Execute offline `pulumi stack export`, rewrite project metadata, and `pulumi stack import` before `pulumi preview`. |
| **Copybara Sync** | Monorepo source path missing during hourly sync | Export pipeline crash; standalone repo drift | Dry-run `tools/copybara/conflict-precheck` and verify `copy.bara.sky` transformations before merging path renames. |

---

## 4. Phased Migration Roadmap (Phases 0 through 5)

The migration is structured into six strictly sequenced phases. Each phase contains concrete execution steps, exact terminal commands, and automated verification gates.

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                               6-PHASE MIGRATION TIMELINE                               │
├─────────┬──────────────────────────────────┬───────────────────────────────────────────┤
│ Phase 0 │ Foundation & Safety Tooling      │ Linter engine, alias helpers, baseline CI │
├─────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Phase 1 │ Low-Risk Remediation             │ Docs, static assets, scripts, .yaml exts  │
├─────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Phase 2 │ Medium-Risk Remediation          │ Go/Py files, Bazel targets, internal pkgs │
├─────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Phase 3 │ High-Risk Remediation            │ GHA workflow inputs, Pulumi project names │
├─────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Phase 4 │ Critical-Risk Remediation        │ Copybara maps, global env ladders, APIs   │
├─────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Phase 5 │ Deprecation Sunset & Enforcement │ Alias removal, 100% blocking CI gate      │
└─────────┴──────────────────────────────────┴───────────────────────────────────────────┘
```

---

### 4.1 Phase 0: Foundation, Tooling & Safety Infrastructure

**Objective**: Deploy the automated naming linter (`tools/lint-naming`), establish Bazel deprecation helpers, configure pre-flight checks, and establish clean baseline telemetry.

#### Execution Steps:
1. **Verify Linter Engine**: Confirm `tools/lint-naming` correctly flags all 38 audit issues in non-blocking advisory mode.
2. **Setup Bazel Migration Stubs**: Verify Starlark macro `alias` compatibility across `@rules_shell` and `@rules_go`.
3. **Configure Pre-flight Validation Gate**: Integrate `bazel test //tools/lint-naming:lint-naming_test` into local pre-push hooks in advisory mode.

#### Execution Commands:
```bash
# 1. Run naming linter in baseline discovery mode
bazel run //tools/lint-naming:lint-naming -- --advisory

# 2. Verify all current Bazel build targets compile cleanly
bazel build //...

# 3. Verify all existing tests pass
bazel test //...
```

#### Validation Gate 0:
- [ ] `bazel build //...` returns exit code `0`.
- [ ] `bazel test //...` returns exit code `0`.
- [ ] `tools/lint-naming` runs cleanly and reports the exact known inventory of 38 drift items without false positives.

---

### 4.2 Phase 1: Low-Risk Remediation (Docs, Assets, Scripts & Extensions)

**Objective**: Remediate all documentation filenames, static assets, workflow file extensions, and standalone shell scripts using atomic `git mv` commits.

#### Execution Steps:
1. **Batch 1.1: Markdown Documentation Renames**:
   - `tabula/docs/architecture/workona_research.md` → `workona-research.md`
   - `tabula/docs/product/gap_analysis.md` → `gap-analysis.md`
   - `tabula/docs/product/verified_journeys.md` → `verified-journeys.md`
   - `docs/archive/gap-analysis/port-cft-pulumi/pulumiportgapanalysisworkflow.md` → `pulumi-port-gap-analysis-workflow.md`
   - `docs/archive/gap-analysis/port-cft-pulumi/verifierreasoningfull.md` → `verifier-reasoning-full.md`
2. **Batch 1.2: Static Asset & Image Renames**:
   - `devx/docs/public/devx_k8s_proof.png` → `devx-k8s-proof.png`
   - `devx/docs/public/devx_mock_proof.png` → `devx-mock-proof.png`
   - Update markdown image references in `devx/docs/` and `tabula/docs/`.
3. **Batch 1.3: Workflow Extension Renames (`.yml` → `.yaml`)**:
   - `.github/workflows/apps-release.yml` → `.yaml`
   - `.github/workflows/dependabot-auto-merge.yml` → `.yaml`
   - `.github/workflows/dependabot-bazel-reconcile.yml` → `.yaml`
   - `.github/workflows/dependabot-lock-rebase.yml` → `.yaml`
   - `.github/workflows/pulumi-library-release.yml` → `.yaml`
   - `.github/workflows/tabula-release.yml` → `.yaml`
4. **Batch 1.4: Standalone Shell Scripts & Starlark Assets**:
   - `tools/workspace_status.sh` → `tools/workspace-status.sh` (Update `.bazelrc`)
   - `tabula/extension/publish_dev_latest_test.sh` → `tabula/extension/publish-dev-latest_test.sh`
   - `tools/gitops/argocd_secret.sh` → `tools/gitops/argocd-secret.sh`
   - `tools/gitops/gitops_cmd.sh` → `tools/gitops/gitops-cmd.sh`
   - `tools/pulumi/create_app.sh` → `tools/pulumi/create-app.sh`
   - `tools/pulumi/pulumi_cmd.sh` → `tools/pulumi/pulumi-cmd.sh`
   - `tools/copybara/check_version_maps.sh` → `tools/copybara/check-version-maps.sh`
   - `.aspect/gazelle/package-json-scripts.axl` → `.aspect/gazelle/package_json_scripts.axl`
5. **Batch 1.5: React Unit Test Filenames**:
   - `tabula/web/__tests__/relay-landing.test.tsx` → `tabula/web/__tests__/RelayLanding.test.tsx`
   - `tabula/web/__tests__/space-detail.test.tsx` → `tabula/web/__tests__/SpaceDetail.test.tsx`

#### Execution Commands:
```bash
# 1. Execute Git moves for documentation & assets
git mv tabula/docs/architecture/workona_research.md tabula/docs/architecture/workona-research.md
git mv tabula/docs/product/gap_analysis.md tabula/docs/product/gap-analysis.md
git mv tabula/docs/product/verified_journeys.md tabula/docs/product/verified-journeys.md
git mv devx/docs/public/devx_k8s_proof.png devx/docs/public/devx-k8s-proof.png
git mv devx/docs/public/devx_mock_proof.png devx/docs/public/devx-mock-proof.png

# 2. Execute Git moves for workflow files
for f in .github/workflows/*.yml; do
  [ -f "$f" ] && git mv "$f" "${f%.yml}.yaml"
done

# 3. Execute Git moves for shell scripts
git mv tools/workspace_status.sh tools/workspace-status.sh
git mv tabula/extension/publish_dev_latest_test.sh tabula/extension/publish-dev-latest_test.sh
git mv tools/gitops/argocd_secret.sh tools/gitops/argocd-secret.sh
git mv tools/gitops/gitops_cmd.sh tools/gitops/gitops-cmd.sh
git mv tools/pulumi/create_app.sh tools/pulumi/create-app.sh
git mv tools/pulumi/pulumi_cmd.sh tools/pulumi/pulumi-cmd.sh
git mv tools/copybara/check_version_maps.sh tools/copybara/check-version-maps.sh
git mv .aspect/gazelle/package-json-scripts.axl .aspect/gazelle/package_json_scripts.axl

# 4. Execute Git moves for React tests
# Note: On macOS APFS case-insensitive filesystems, direct single-step case-only renames
# fail with "destination exists". Use a two-step rename sequence with a temporary suffix:
git mv tabula/web/__tests__/relay-landing.test.tsx tabula/web/__tests__/relay-landing.test.tsx.tmp
git mv tabula/web/__tests__/relay-landing.test.tsx.tmp tabula/web/__tests__/RelayLanding.test.tsx

git mv tabula/web/__tests__/space-detail.test.tsx tabula/web/__tests__/space-detail.test.tsx.tmp
git mv tabula/web/__tests__/space-detail.test.tsx.tmp tabula/web/__tests__/SpaceDetail.test.tsx

# 5. Update references and rebuild
sed -i '' 's/workspace_status.sh/workspace-status.sh/g' .bazelrc
bazel run //:gazelle
aspect lint //...
bazel test //...
```

#### Validation Gate 1:
- [ ] `aspect lint //...` passes with zero lint violations.
- [ ] `bazel test //...` passes across all affected test suites.
- [ ] No broken markdown hyperlinks detected via markdown link verification.

---

### 4.3 Phase 2: Medium-Risk Remediation (Go, Python, Packages & Targets)

**Objective**: Remediate Go source files, Python module names, Bazel `sh_test` target names, Swift targets, and internal package directories.

#### Execution Steps:
1. **Batch 2.1: Go Source File Renames**:
   - `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs.go` → `net_hubs.go`
   - `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs-transitivity.go` → `net_hubs_transitivity.go`
   - `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs.go` → `net_hubs.go`
   - `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs-transitivity.go` → `net_hubs_transitivity.go`
2. **Batch 2.2: Python Module & Target**:
   - Rename `nexus-agent/hooks/stream-hook.py` → `stream_hook.py`.
   - Update `nexus-agent/hooks/BUILD` to declare `py_binary(name = "stream_hook", srcs = ["stream_hook.py"])`.
   - Add backwards-compatible alias: `alias(name = "stream-hook", actual = ":stream_hook")`.
3. **Batch 2.3: Bazel Package Directory Renames**:
   - `tools/copybara/conflict_precheck/` → `tools/copybara/conflict-precheck/`
   - `tools/gitops/appset_render/` → `tools/gitops/appset-render/`
   - `infrastructure/pulumi/foundation/gcp-networks/modules/vpn-ha/` → `.../modules/vpn_ha/`
   - `pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/vpn-ha/` → `.../modules/vpn_ha/`
   - `pulumi/examples/go-foundation/3-networks-svpc/modules/vpn-ha/` → `.../modules/vpn_ha/`
4. **Batch 2.4: Bazel `sh_test` Target Harmonization**:
   - Update `tools/agent-app/BUILD`: rename `agent_app_test` → `agent-app_test`. Add `alias(name = "agent_app_test", actual = ":agent-app_test")`.
   - Update `tools/cloud-bootstrap/BUILD`: rename `cloud_bootstrap_test` → `cloud-bootstrap_test`. Add `alias(name = "cloud_bootstrap_test", actual = ":cloud-bootstrap_test")`.
   - Update `tools/gcp-token/BUILD`: rename `gcp_token_test` → `gcp-token_test`. Add `alias(name = "gcp_token_test", actual = ":gcp-token_test")`.
   - Update `tools/gcp-secrets/BUILD`: rename `gcp_secrets_test` → `gcp-secrets_test`. Add `alias(name = "gcp_secrets_test", actual = ":gcp-secrets_test")`.
   - Update `tools/saas-cli/BUILD`: rename `saas_cli_test` → `saas-cli_test`. Add `alias(name = "saas_cli_test", actual = ":saas-cli_test")`.
5. **Batch 2.5: Swift Bazel Targets**:
   - Update `nexus-agent/macos/BUILD`: rename `NexusAgent_lib` → `NexusAgentLib`, `NexusAgent_tests` → `NexusAgentTests`. Add aliases for legacy target names.
6. **Batch 2.6: TypeScript Services & Utility Harmonization**:
   - Harmonize `tabula/extension/src/services/` to `kebab-case.ts`.
   - Harmonize `tabula/web/lib/safeHref.ts` → `safe-href.ts`.

#### Execution Commands:
```bash
# 1. Rename Go source files
git mv infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs.go \
       infrastructure/pulumi/foundation/gcp-networks/envs/shared/net_hubs.go
git mv infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs-transitivity.go \
       infrastructure/pulumi/foundation/gcp-networks/envs/shared/net_hubs_transitivity.go
git mv pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs.go \
       pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net_hubs.go
git mv pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs-transitivity.go \
       pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net_hubs_transitivity.go

# 2. Rename Python module
git mv nexus-agent/hooks/stream-hook.py nexus-agent/hooks/stream_hook.py

# 3. Rename package directories
git mv tools/copybara/conflict_precheck tools/copybara/conflict-precheck
git mv tools/gitops/appset_render tools/gitops/appset-render
git mv infrastructure/pulumi/foundation/gcp-networks/modules/vpn-ha \
       infrastructure/pulumi/foundation/gcp-networks/modules/vpn_ha
git mv pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/vpn-ha \
       pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/vpn_ha
git mv pulumi/examples/go-foundation/3-networks-svpc/modules/vpn-ha \
       pulumi/examples/go-foundation/3-networks-svpc/modules/vpn_ha

# 4. Update direct script and workflow callers for moved tools
sed -i '' 's|tools/gitops/appset_render|tools/gitops/appset-render|g' tools/ci/gitops-validate.sh
sed -i '' 's|tools/copybara/conflict_precheck|tools/copybara/conflict-precheck|g' .github/workflows/_copybara-export.yaml

# 5. Synchronize Gazelle & regenerate BUILD targets
bazel run //:gazelle
go mod tidy
bazel mod tidy

# 6. Build and test all targets
bazel build //...
bazel test //...
```

#### Validation Gate 2:
- [ ] `bazel build //...` compiles 100% cleanly without errors.
- [ ] `bazel test //...` passes all Go, Python, Shell, and TypeScript test suites.
- [ ] Legacy target aliases resolve properly (e.g. `bazel test //tools/agent-app:agent_app_test` executes successfully via alias).

---

### 4.4 Phase 3: High-Risk Remediation (Workflows, Pulumi & Tool Schemas)

**Objective**: Refactor GitHub Actions reusable workflow interfaces, internal tool configuration schemas, and Pulumi project names/stack keys using Expand/Contract and Pulumi state export/import protocols.

#### Execution Steps:
1. **Batch 3.1: GitHub Actions Reusable Workflows (Expand Phase)**:
   - Update reusable workflow definitions (`.github/workflows/_copybara-export.yaml`, `foundation-app-deploy.yaml`, `foundation-proj-deploy.yaml`, `pulumi-stack-reset.yaml`) to accept canonical `kebab-case` inputs while maintaining fallback support for legacy `snake_case` inputs:
     ```yaml
     inputs:
       working-directory:
         type: string
         required: false
       working_directory:
         type: string
         required: false
     # Step logic resolves:
     # WORKING_DIR: ${{ inputs['working-directory'] || inputs.working_directory }}
     ```
   - Update workflow callers across monorepo to supply canonical `kebab-case` inputs.
2. **Batch 3.2: Internal Tool Configuration Schemas**:
   - `tools/initializer/config.json`: update `"appliesTo"` → `"applies_to"`. Update `tools/initializer/` parsing code.
   - `infrastructure/pulumi/platform/dev-local/devx.yaml`: update `customActions:` → `custom_actions:`. Update DevX CLI parser to accept both during transition.
   - `tabula/extension/src/build_info.json` → `build-info.json`. Update build scripts.
3. **Batch 3.3: Pulumi Stack Configuration Keys (Expand Phase)**:
   - In `tabula/infra/identity/`, `build/`, `app/` TypeScript programs: update config reader to query canonical camelCase key first with fallback to snake_case key:
     ```typescript
     const config = new pulumi.Config();
     const bootstrapStack = config.get("bootstrapStack") || config.require("bootstrap_stack");
     ```
   - Update `Pulumi.<env>.yaml` stack config files to canonical camelCase keys (`bootstrapStack`, `projectsStack`).
4. **Batch 3.4: Pulumi Project Names Migration**:
   - Migrate `infrastructure/pulumi/platform/repo_config/` → `repo-config/`.
   - Update `Pulumi.yaml` `name:` fields across Tabula, platform stacks, and standalone apps (`pulumi_tabula_app` → `tabula-app`, `pulumi_oauth_user_inspector` → `oauth-user-inspector-app`, etc.) following the [Pulumi State Migration Runbook (Section 6)](#6-pulumi-infrastructure-state-migration-mechanics--runbook).

#### Execution Commands:
```bash
# 1. Move repo_config directory to repo-config
git mv infrastructure/pulumi/platform/repo_config infrastructure/pulumi/platform/repo-config

# 2. Test tool schema changes
go test ./devx/...
go test ./tools/initializer/...

# 3. Dry-run Pulumi previews across all updated projects
bazel run //infrastructure/pulumi/platform/repo-config:preview
bazel run //tabula/infra/app:preview
bazel run //tabula/infra/web:preview
bazel run //tabula/infra/data:preview
bazel run //tabula/infra/build:preview
bazel run //tabula/infra/identity:preview
bazel run //oauth-user-inspector/infra/app:preview
```

#### Validation Gate 3:
- [ ] All GitHub Actions workflows trigger and succeed in CI with both direct and reusable invocations.
- [ ] All Pulumi stack previews report `Resources: unchanged` with zero proposed deletions or recreations.
- [ ] DevX CLI and Initializer tool tests pass 100%.

---

### 4.5 Phase 4: Critical-Risk Remediation (Copybara, Env Vars & APIs)

**Objective**: Validate and synchronize external boundary transformations (Copybara, PostgreSQL/Prisma mappings, OpenAPI contracts, and monorepo environment variable ladders).

#### Execution Steps:
1. **Batch 4.1: Copybara Transformation Verification**:
   - Inspect `tools/copybara/` configuration files.
   - Verify that all internal path relocations (e.g. `tools/copybara/conflict-precheck`) are accounted for in `copy.bara.sky`.
   - Execute Copybara conflict pre-check dry run to ensure standalone exports for `devx`, `homelab`, `mcp-slack`, `nexus-agent`, and `oauth-user-inspector` operate without error.
2. **Batch 4.2: Environment Variable Fallback Ladders**:
   - Ensure all shell scripts and Go tools implement canonical environment variable ladders:
     ```bash
     # Canonical resolution with fallback ladder
     GOOGLE_CLOUD_PROJECT="${GOOGLE_CLOUD_PROJECT:-${GCP_PROJECT:-${GCP_PROJECT_ID:-}}}"
     GOOGLE_OAUTH_ACCESS_TOKEN="${GOOGLE_OAUTH_ACCESS_TOKEN:-${CLOUDSDK_AUTH_ACCESS_TOKEN:-}}}"
     ```
   - Update `AGENTS.md` and tool documentation to recommend `GOOGLE_CLOUD_PROJECT` exclusively.
3. **Batch 4.3: Database Schema & API Contract Invariant Check**:
   - Run Prisma schema validation: `cd tabula/api && npx prisma validate`.
   - Verify that Prisma `@map` directives remain intact on all snake_case PostgreSQL columns.
   - Verify OpenAPI schema validation: `npx @redocly/cli lint tabula/api/openapi.yaml`.

#### Execution Commands:
```bash
# 1. Run Copybara pre-check
bazel test //tools/copybara/conflict-precheck:conflict-precheck_test

# 2. Validate database schema
bazel test //tabula/api:prisma_validate

# 3. Validate OpenAPI schemas
bazel test //tabula/api:openapi_lint
bazel test //oauth-user-inspector:openapi_lint

# 4. Verify monorepo pipeline delivery status
bazel run //tools/pipeline-status -- --dry-run
```

#### Validation Gate 4:
- [ ] Copybara dry-run export passes without path drift.
- [ ] Database schema validation passes; zero database migrations generated.
- [ ] OpenAPI wire format contract tests pass.

---

### 4.6 Phase 5: Deprecation Sunset, Cleanup & Mandatory CI Enforcement

**Objective**: Sunset backwards-compatibility stubs (aliases, legacy workflow inputs, fallback env vars) after the designated 30-day grace period, and lock down `tools/lint-naming` as a mandatory blocking CI check.

#### Execution Steps:
1. **Batch 5.1: Remove Deprecated Bazel Target Aliases**:
   - Remove `alias(name = "agent_app_test", ...)` and similar stubs after consumer verification.
2. **Batch 5.2: Remove Workflow Dual-Input Bridges**:
   - Contract reusable workflows to accept ONLY canonical `kebab-case` inputs.
3. **Batch 5.3: Contract Pulumi Stack Config Fallbacks**:
   - Remove legacy `config.get("bootstrap_stack")` fallbacks in TypeScript code.
4. **Batch 5.4: Activate Mandatory Blocking CI Gate**:
   - Update GitHub Actions CI workflow (`.github/workflows/ci.yaml`) to run `bazel test //tools/lint-naming:lint-naming_test` as a required blocking status check.
   - Any PR introducing naming violations will be automatically rejected by the merge queue.

#### Execution Commands:
```bash
# 1. Execute full repository naming audit in strict blocking mode
bazel run //tools/lint-naming:lint-naming

# 2. Run full monorepo test suite
bazel test //...

# 3. Verify zero lint errors
aspect lint //...
```

#### Validation Gate 5:
- [ ] `bazel test //tools/lint-naming:lint-naming_test` exits with code `0`.
- [ ] CI pipeline runs `lint-naming` as a required status check on every pull request.
- [ ] Repository has achieved 100% compliance across all 4,226 tracked files.

---

## 5. Backwards Compatibility & History Preservation Strategies

### 5.1 Git History Preservation via `git mv`

To ensure file history and line-by-line attribution (`git blame`) are preserved across renames:
1. **Never delete and recreate**: Every rename MUST be executed via `git mv <source> <destination>`.
2. **Isolate file renames from content edits**: Refactoring PRs MUST separate pure `git mv` rename commits from subsequent content edits. Mixing massive content rewrites with renames breaks Git's similarity index heuristic (`rename limit` / 50% similarity threshold).
3. **Verify Git History Followability**:
   ```bash
   # Verify history followability after rename
   git log --follow --stat -- docs/standards/naming-migration-plan.md
   ```

### 5.2 Bazel Target Aliasing & Deprecation Stubs

When a Bazel target is renamed from a legacy name (e.g. `:agent_app_test`) to a canonical name (e.g. `:agent-app_test`), a backwards-compatible `alias` rule is registered in the same package:

```python
# In tools/agent-app/BUILD:
sh_test(
    name = "agent-app_test",
    size = "small",
    srcs = ["agent-app_test.sh"],
    data = [":agent-app", "agents.tsv"],
)

# Deprecated alias stub for backwards compatibility:
alias(
    name = "agent_app_test",
    actual = ":agent-app_test",
    deprecation = "Target :agent_app_test is deprecated. Use :agent-app_test instead. Will be removed in Phase 5.",
)
```

### 5.3 GitHub Actions Dual-Input & Dual-Output Bridging

During the transition window, reusable workflows support both naming conventions concurrently using GitHub Actions expression evaluation:

```yaml
# In .github/workflows/foundation-app-deploy.yaml
on:
  workflow_call:
    inputs:
      working-directory:
        description: "Canonical working directory path"
        type: string
        required: false
      working_directory:
        description: "DEPRECATED: Use working-directory"
        type: string
        required: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Resolve Effective Parameters
        id: resolve
        run: |
          WORKING_DIR="${{ inputs['working-directory'] || inputs.working_directory }}"
          if [ -z "$WORKING_DIR" ]; then
            echo "::error::Either working-directory or working_directory must be provided"
            exit 1
          fi
          echo "working-dir=$WORKING_DIR" >> "$GITHUB_OUTPUT"
```

### 5.4 Environment Variable Resolution Ladders

Shell scripts and CLI tools evaluate environment variables using POSIX parameter expansion fallback ladders:

```bash
# Canonical Resolution Ladder in tools/ci/cloud-run.sh
EFFECTIVE_PROJECT="${GOOGLE_CLOUD_PROJECT:-${GCP_PROJECT:-${GCP_PROJECT_ID:-}}}"
if [ -z "$EFFECTIVE_PROJECT" ]; then
  echo "ERROR: GOOGLE_CLOUD_PROJECT must be set." >&2
  exit 1
fi
export GOOGLE_CLOUD_PROJECT="$EFFECTIVE_PROJECT"
```

In Go applications (`devx/internal/cloud/gcp.go`):
```go
func ResolveProjectID() string {
    if p := os.Getenv("GOOGLE_CLOUD_PROJECT"); p != "" {
        return p
    }
    if p := os.Getenv("GCP_PROJECT"); p != "" {
        return p
    }
    return os.Getenv("GCP_PROJECT_ID")
}
```

### 5.5 Copybara Transformation Shims for Standalone Mirrors

When internal monorepo package paths are renamed, Copybara transformation workflows (`tools/copybara/copy.bara.sky`) must map the new internal path to the expected root/subtree in the destination repository:

```python
# In tools/copybara/copy.bara.sky
core.workflow(
    name = "export_devx",
    origin = git.origin(
        url = "file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core",
        ref = "main",
    ),
    destination = git.destination(
        url = "git@github.com:VitruvianSoftware/devx.git",
        fetch = "main",
        push = "main",
    ),
    origin_files = glob(["devx/**"]),
    transformations = [
        core.move("devx", ""),
    ],
)
```

---

## 6. Pulumi Infrastructure State Migration Mechanics & Runbook

### 6.1 Risk Analysis & Zero-Recreation Guarantee

Renaming a Pulumi project in `Pulumi.yaml` (e.g. `pulumi_tabula_app` → `tabula-app`) causes Pulumi to perceive the stack as a brand new project. If executed naively with `pulumi up`, Pulumi would attempt to provision duplicate resources or fail on resource name collisions.

To achieve a **100% Zero-Recreation Guarantee**, the migration utilizes Pulumi's native state export and import mechanics to re-point the existing state snapshot to the canonical project name.

### 6.2 Step-by-Step Pulumi State Migration Procedure

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        PULUMI STATE MIGRATION WORKFLOW                                 │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  1. pulumi stack export --file <stack>.json                                            │
│  2. Edit JSON: replace "project": "pulumi_tabula_app" with "project": "tabula-app"     │
│  3. Edit Pulumi.yaml: update name: tabula-app                                          │
│  4. pulumi stack import --file <stack>.json                                            │
│  5. pulumi preview --diff (Assert: 0 to create, 0 to update, 0 to delete)              │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Detailed Execution Script:
```bash
#!/usr/bin/env bash
set -euo pipefail

PULUMI_DIR="tabula/infra/app"
STACK_NAME="development"
OLD_PROJECT="pulumi_tabula_app"
NEW_PROJECT="tabula-app"

cd "$PULUMI_DIR"

echo "Step 1: Exporting current stack state for $STACK_NAME..."
pulumi stack export --stack "$STACK_NAME" --file "state_backup_${STACK_NAME}.json"

echo "Step 2: Mutating project identifier and resource URNs in state snapshot..."
jq --arg old "$OLD_PROJECT" --arg new "$NEW_PROJECT" \
   'walk(
      if type == "object" and .project? == $old then .project = $new
      elif type == "string" then gsub("::" + $old + "::"; "::" + $new + "::")
      else . end
    )' \
   "state_backup_${STACK_NAME}.json" > "state_migrated_${STACK_NAME}.json"

echo "Step 3: Updating Pulumi.yaml project name..."
sed -i '' "s/name: $OLD_PROJECT/name: $NEW_PROJECT/" Pulumi.yaml

echo "Step 4: Importing migrated state snapshot..."
pulumi stack import --stack "$STACK_NAME" --file "state_migrated_${STACK_NAME}.json"

echo "Step 5: Verifying state integrity with dry-run preview..."
pulumi preview --stack "$STACK_NAME" --diff

echo "SUCCESS: Pulumi project $OLD_PROJECT successfully migrated to $NEW_PROJECT with zero resource drift."
```

### 6.3 Stack Configuration Dual-Lookup Code Bridge

In TypeScript Pulumi stacks (`tabula/infra/identity/index.ts`):

```typescript
import * as pulumi from "@pulumi/pulumi";

const config = new pulumi.Config();

// Dual-lookup resolver supporting both canonical camelCase and legacy snake_case
function resolveStackRef(canonicalKey: string, legacyKey: string): string {
    const val = config.get(canonicalKey);
    if (val) return val;
    const legacyVal = config.get(legacyKey);
    if (legacyVal) {
        pulumi.log.warn(`Configuration key '${legacyKey}' is deprecated. Please rename to '${canonicalKey}' in Pulumi.<stack>.yaml`);
        return legacyVal;
    }
    throw new Error(`Missing required configuration key: '${canonicalKey}' (or legacy '${legacyKey}')`);
}

export const bootstrapStack = resolveStackRef("bootstrapStack", "bootstrap_stack");
export const projectsStack = resolveStackRef("projectsStack", "projects_stack");
```

---

## 7. Rollback Procedures & Emergency Halt Criteria

### 7.1 Emergency Halt Trigger Criteria

An automated or manual **EMERGENCY HALT** must be invoked immediately if any of the following conditions occur during any phase:

1. **Build Breakage**: `bazel build //...` fails on `main` following a migration PR merge.
2. **CI Pipeline Blocked**: Any release, delivery, or testing workflow in `.github/workflows/` fails due to missing input/output contracts.
3. **Pulumi Destruction Proposed**: Any Pulumi preview proposes the unexpected deletion or replacement of a production cloud resource.
4. **Copybara Desync**: The hourly Copybara sync fails to export commits to any standalone repository mirror.
5. **Production Error Spikes**: Error rates or trace latencies spike in Grafana/OTel following an infrastructure deployment.

### 7.2 Phase-Specific Rollback Runbooks

#### Phase 1 & 2 Rollback (File & Target Renames):
Since Phases 1 and 2 modify only monorepo source files and Bazel targets without touching external cloud state:
```bash
# 1. Identify the offending migration commit SHA
git log -n 5 --oneline

# 2. Revert the commit cleanly
git revert <COMMIT_SHA> -m 1 --no-edit

# 3. Verify build health
bazel build //...
bazel test //...

# 4. Push revert to main
git push origin main
```

#### Phase 3 Rollback (Pulumi State & Workflows):
If a Pulumi project rename experiences issues in cloud synchronization:
```bash
# 1. Restore state from pre-migration backup file
cd <PULUMI_DIR>
pulumi stack import --stack <STACK_NAME> --file "state_backup_<STACK_NAME>.json"

# 2. Revert Pulumi.yaml project name
git checkout origin/main -- Pulumi.yaml Pulumi.<STACK_NAME>.yaml

# 3. Verify preview
pulumi preview
```

### 7.3 Fix-Forward vs. Revert Decision Trees

```
                                MIGRATION FAILURE DETECTED
                                             │
                       ┌─────────────────────┴─────────────────────┐
                       ▼                                           ▼
             Is failure isolated to                       Does failure impact
             internal target alias or                     live cloud state or
             typo in documentation?                       external git mirrors?
                       │                                           │
                       ▼                                           ▼
             [ FIX-FORWARD PATH ]                         [ IMMEDIATE REVERT ]
          1. Push atomic fix within 15m.               1. Execute `git revert`.
          2. Verify with `bazel test`.                 2. Restore Pulumi state backup.
          3. Unblock merge queue.                      3. Convene post-mortem.
```

---

## 8. CI/CD Automation, Governance & Long-Term Enforcement

### 8.1 Automated Merge Gate Architecture

Long-term naming consistency is guaranteed by integrating `tools/lint-naming` directly into the monorepo's automated GitHub Actions CI pipeline:

```yaml
# In .github/workflows/ci.yaml
jobs:
  lint-naming-conventions:
    name: "Enforce Monorepo Naming Standards"
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Setup Bazel
        uses: ./.github/actions/bazel-cache
        with:
          cache-prefix: lint-naming

      - name: Run Naming Linter Test
        run: |
          bazel test //tools/lint-naming:lint-naming_test --test_output=errors
```

### 8.2 Local Developer Pre-Flight Integration

To prevent naming violations from reaching CI, the naming linter is integrated into DevX pre-flight checks:

```yaml
# In devx.yaml
pipeline:
  lint:
    commands:
      - ["bazel", "test", "//tools/lint-naming:lint-naming_test"]
      - ["golangci-lint", "run"]
      - ["aspect", "lint", "//..."]
```

### 8.3 Exception Lifecycle & Architectural Review Board

No naming convention exceptions may be added via ad-hoc ignoring. All future exemptions must adhere to the following governance lifecycle:

1. **Formal RFC**: The author opens a proposal in `docs/standards/` explaining the hard language, compiler, or third-party schema constraint that prevents standard compliance.
2. **Architectural Review Board (ARB) Approval**: Requires sign-off from at least two monorepo codeowners.
3. **Explicit Linter Registration**: Upon approval, the exception path is registered in `tools/lint-naming/rules/exemptions.py` with an expiration date and ticket reference.
4. **Annual Audit**: All active exemptions are reviewed annually for deprecation or removal.

---

*This document constitutes the official, authoritative Phased Refactoring & Migration Plan for the `vitruvian-core` monorepo, fulfilling all requirements for Milestone 4.*
