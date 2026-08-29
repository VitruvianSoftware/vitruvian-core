# Monorepo Naming & Structural Consistency Audit: `vitruvian-core`

**Document Status**: Official Repository Audit Deliverable (Milestone 1)  
**Date**: 2026-08-28  
**Scope**: Monorepo-wide filesystem, source files across 7 language ecosystems, Bazel build graph, environment variables, CLI flags, GitHub Actions workflows, Kubernetes manifests, Pulumi infrastructure definitions, and serialization schemas.  
**Auditors**: Multi-Agent Architectural Surveyors (Explorers 1, 2, and 3; Worker M1)

---

## Table of Contents

1. [Executive Summary & Scope Metrics](#1-executive-summary--scope-metrics)
2. [Category-by-Category Structural Analysis](#2-category-by-category-structural-analysis)
   - 2.1 [Directory Trees & Root Paths](#21-directory-trees--root-paths)
   - 2.2 [Source Files by Language Ecosystem](#22-source-files-by-language-ecosystem)
   - 2.3 [Shell Scripts & Automation Tooling](#23-shell-scripts--automation-tooling)
   - 2.4 [Documentation & Static Assets](#24-documentation--static-assets)
   - 2.5 [Bazel Packages, Build Targets & Starlark Rules](#25-bazel-packages-build-targets--starlark-rules)
   - 2.6 [Environment Variables & Configuration Namespaces](#26-environment-variables--configuration-namespaces)
   - 2.7 [CLI Flags & Option Conventions](#27-cli-flags--option-conventions)
   - 2.8 [GitHub Actions Workflows & Composite Actions](#28-github-actions-workflows--composite-actions)
   - 2.9 [Kubernetes Manifests, Helm Charts & GitOps](#29-kubernetes-manifests-helm-charts--gitops)
   - 2.10 [Pulumi Infrastructure Definitions & Stacks](#210-pulumi-infrastructure-definitions--stacks)
   - 2.11 [Tool Configurations, Schemas & Serialization Layers](#211-tool-configurations-schemas--serialization-layers)
3. [Ecosystem Technical Constraints vs. Unintentional Drift](#3-ecosystem-technical-constraints-vs-unintentional-drift)
   - 3.1 [Hard Language & Platform Constraints](#31-hard-language--platform-constraints)
   - 3.2 [Third-Party Tool-Mandated Schemas](#32-third-party-tool-mandated-schemas)
   - 3.3 [Constraint vs. Drift Authority Matrix](#33-constraint-vs-drift-authority-matrix)
4. [Inconsistency & Drift Inventory (Complete Catalog)](#4-inconsistency--drift-inventory-complete-catalog)
   - 4.1 [Source File Filename Anomalies](#41-source-file-filename-anomalies)
   - 4.2 [Directory & Bazel Package Path Inconsistencies](#42-directory--bazel-package-path-inconsistencies)
   - 4.3 [Bazel Target & `sh_test` Inconsistencies](#43-bazel-target--sh_test-inconsistencies)
   - 4.4 [Intra-Directory File Casing Clashes](#44-intra-directory-file-casing-clashes)
   - 4.5 [Pulumi Project & Stack Config Key Inconsistencies](#45-pulumi-project--stack-config-key-inconsistencies)
   - 4.6 [GitHub Actions Workflow Inputs, Outputs & Extensions](#46-github-actions-workflow-inputs-outputs--extensions)
   - 4.7 [Environment Variable Namespace Fragmentation](#47-environment-variable-namespace-fragmentation)
   - 4.8 [Internal Tool Schema & Config Inconsistencies](#48-internal-tool-schema--config-inconsistencies)
5. [Strategic Recommendations for Downstream Milestones](#5-strategic-recommendations-for-downstream-milestones)

---

## 1. Executive Summary & Scope Metrics

A comprehensive, automated, and forensic audit of the `vitruvian-core` repository was performed to evaluate the usage of hyphen (`-` / `kebab-case`), underscore (`_` / `snake_case`), camelCase, PascalCase, and SCREAMING_SNAKE_CASE across all architectural layers.

The audit examined all 4,226 tracked repository files, 840 unique directories, 293 Bazel packages, 546 build targets, 903 environment variables, 414 CLI flags, 54 GitHub Actions workflows, 169 Kubernetes/GitOps manifests, and 76 Pulumi infrastructure projects.

### 1.1 Monorepo Scope & Audit Metrics

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ VITRUVIAN-CORE MONOREPO AUDIT METRICS                                                   │
├──────────────────────────────────────────┬──────────────┬───────────────────────────────┤
│ Audited Category                         │ Total Count  │ Primary / Dominant Pattern    │
├──────────────────────────────────────────┼──────────────┼───────────────────────────────┤
│ Tracked Files                            │ 4,226 files  │ Language & file-type specific │
│ Unique Directories                       │ 840 dirs     │ lower_single (68%), kebab (20%)│
│ Root-Level Directories                   │ 22 roots     │ lower_single (19), kebab (3)  │
│ Bazel Packages                           │ 293 pkgs     │ kebab-case (43%), lower (40%) │
│ Bazel Build Targets                      │ 546 targets  │ Rule-dependent (snake/kebab)  │
│ Starlark (.bzl) Source Files             │ 11 files     │ snake_case (100% rules/attrs) │
│ Environment Variables                    │ 903 distinct │ SCREAMING_SNAKE_CASE (97%)    │
│ CLI Options & Flags                      │ 414 flags    │ kebab-case (tools), snake(bzl)│
│ Config, Schema, & Manifest Files         │ 1,481 files  │ kebab-case & tool-mandated    │
│ GitHub Actions Workflows                 │ 54 files     │ kebab-case jobs/steps (100%)  │
│ Kubernetes / GitOps Manifest Files       │ 169 files    │ DNS-1123 kebab-case (100%)    │
│ Pulumi Infrastructure Projects           │ 76 projects  │ Split: kebab-case vs snake    │
│ Supported Language Ecosystems            │ 7 ecosystems │ Go, TS/JS, Py, Swift, Shell,  │
│                                          │              │ Starlark, SQL/Prisma          │
└──────────────────────────────────────────┴──────────────┴───────────────────────────────┘
```

### 1.2 High-Level Summary of Findings

1. **Repository Baseline**: The overarching organizational standard for multi-word paths, applications, packages, tools, CLI commands, Kubernetes resources, and documentation is **`kebab-case`**.
2. **Hard Technical Constraints (Valid Divergence)**:
   - **Go Packages**: Go language grammar strictly forbids hyphens in package identifiers (`package cloud_dns`). Multi-word Go package directories must use `snake_case` or single-word naming.
   - **Python Modules**: Python import syntax (`import foo_bar`) strictly forbids hyphens. Python source files must use `snake_case`.
   - **Kubernetes / ArgoCD**: RFC 1123 DNS subdomain rules strictly forbid underscores in resource names and namespaces.
   - **React Components**: JSX parser requires initial capitalization to differentiate custom components from native HTML elements, mandating `PascalCase.tsx`.
   - **Swift / Apple macOS**: Xcode and Swift module conventions mandate `PascalCase` source files, directory structures, and application bundle identifiers.
   - **Database Persistence vs. API Wire Format**: PostgreSQL schema conventions mandate `snake_case` table and column identifiers, while TypeScript and OpenAPI wire formats standardize on `camelCase`.
3. **Unintentional Drift & High-Priority Remediation Targets**:
   - **Kebab-Case Go Files**: Four Go source files in Pulumi infrastructure trees use kebab-case (`net-hubs.go`, `net-hubs-transitivity.go`), violating Go filename idioms.
   - **Hyphenated Python Script**: `nexus-agent/hooks/stream-hook.py` uses a hyphen, causing a `SyntaxError` if imported as a module.
   - **`sh_test` Target Split**: 27 shell test targets are split arbitrarily between `<binary>_test` (preserving kebab-case binary name, e.g. `:ci-preflight_test`) and `<package_snake>_test` (e.g. `:agent_app_test`).
   - **Pulumi Project & Stack Drift**: Foundation Pulumi stacks use kebab-case (`foundation-bootstrap`), whereas Application Pulumi stacks use snake_case with a prefix (`pulumi_tabula_app`). Stack config files (`Pulumi.<env>.yaml`) mix `snake_case` and `camelCase` keys within the same file.
   - **Sibling Directory Drift**: `infrastructure/pulumi/platform/repo_config` (snake_case) sits directly beside `dev-local` and `zitadel-apps` (kebab-case).
   - **Tools Script Inconsistency**: Shell scripts under `tools/ci/` use kebab-case (`affected-targets.sh`), while `tools/gitops/`, `tools/pulumi/`, and `tools/copybara/` use snake_case (`argocd_secret.sh`, `pulumi_cmd.sh`, `check_version_maps.sh`).
   - **GitHub Actions Workflow Inputs & Outputs**: Reusable workflow inputs and outputs arbitrarily mix kebab-case (`app-name`, `image-digest`) with snake_case (`working_directory`, `business_unit`, `affected_charts`). Six root workflows still use `.yml` instead of `.yaml`.

---

## 2. Category-by-Category Structural Analysis

### 2.1 Directory Trees & Root Paths

The monorepo contains 22 root-level directories and 840 unique subdirectories.

#### Root-Level Directories (22 Roots)

| Directory | Casing Pattern | Direct Role / Subsystem |
|---|---|---|
| `.aspect/` | `lower_single` | Aspect Bazel and Gazelle plugin definitions |
| `.claude/` | `lower_single` | Claude Code configuration and helper scripts |
| `.devcontainer/` | `lower_single` | VS Code remote development container specification |
| `.github/` | `lower_single` | GitHub Actions CI/CD workflows, actions, and issue templates |
| `.vscode/` | `lower_single` | Workspace-level editor configurations |
| `architecture/` | `lower_single` | System architectural blueprints and diagrams |
| `backstage/` | `lower_single` | Spotify Backstage developer portal application & plugins |
| `devx/` | `lower_single` | DevX local development CLI and environment orchestrator |
| `docs/` | `lower_single` | Central monorepo documentation hub |
| `githooks/` | `lower_single` | Git pre-commit and pre-push hook automation |
| `gitops/` | `lower_single` | ArgoCD application definitions & Kubernetes manifests |
| `homelab/` | `lower_single` | Homelab infrastructure management Go CLI |
| `infrastructure/` | `lower_single` | Production Pulumi GCP infrastructure stacks |
| `mcp-slack/` | `kebab-case` | Model Context Protocol Slack server application |
| `nexus-agent/` | `kebab-case` | Native macOS menu-bar agent application |
| `oauth-user-inspector/` | `kebab-case` | OAuth inspection web app and API backend |
| `ops/` | `lower_single` | Operational scripts and maintenance tasks |
| `packages/` | `lower_single` | Shared UI libraries and frontend packages (`design-system`) |
| `pulumi/` | `lower_single` | Shared Pulumi Go/TS libraries and foundation blueprints |
| `requirements/` | `lower_single` | Python dependencies and lockfiles |
| `tabula/` | `lower_single` | Tabula Chrome extension, API backend, and web app |
| `tools/` | `lower_single` | Monorepo build, CI, release, security, and admin tooling |

**Root Rule**: Multi-word top-level applications strictly use **`kebab-case`** (`mcp-slack`, `nexus-agent`, `oauth-user-inspector`). Single-word domains use lowercase. No root directory uses `_` (snake_case).

#### Subdirectory Casing Distribution (840 Total Subdirectories)

- **`lower_single`** (572 dirs, 68.1%): `cmd`, `internal`, `pkg`, `src`, `components`, `lib`, `config`, `modules`.
- **`kebab-case`** (167 dirs, 19.9%): `gcp-bootstrap`, `ci-preflight`, `cloud-run`, `agent-app`, `gitops-validate`.
- **`snake_case`** (91 dirs, 10.8%): Concentrated in Go package directories (`pulumi/library/go/pkg/cloud_run/`, `infrastructure/pulumi/**/modules/shared_vpc/`) and Prisma migrations (`20260714205548_add_tab_notes/`).
- **`PascalCase`** (6 dirs, 0.7%): Swift/Apple directories (`nexus-agent/macos/Sources/NexusAgentCore/`).
- **`camelCase`** (2 dirs, 0.2%): `backstage/packages/backend/src/plugins/cloudRun/`.
- **Other / Spec** (2 dirs, 0.2%): `devx/.github/ISSUE_TEMPLATE/` (UPPER_SNAKE), `tabula/web/src/app/[relayId]/` (Next.js dynamic route).

---

### 2.2 Source Files by Language Ecosystem

#### Go Ecosystem (1,037 Files)
- **Primary Casing**: `lower_single.go` (779 files) and `snake_case.go` (222 files).
- **Test Suffix**: Co-located tests uniformly append `_test.go` (`client_test.go`, `config_test.go`).
- **Generated Files**: 32 files in `pulumi/library/go/pkg/neon/sdk/neon/` use `camelCase.go` (`apiKey.go`, `getProject.go`), emitted by the upstream Pulumi code generator.
- **Identified Violations**: 4 files in Pulumi trees use `kebab-case.go` filenames:
  - `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs.go`
  - `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs-transitivity.go`
  - `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs.go`
  - `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs-transitivity.go`

#### TypeScript & JavaScript Ecosystem (579 Files: 417 `.ts`, 162 `.tsx`)
- **React / UI Components (`.tsx`)**: Standard is **`PascalCase.tsx`** (135 files, e.g. `EntityPage.tsx`, `AccountSettings.tsx`, `EditableSpace.test.tsx`).
  - *Drift*: `tabula/web/__tests__/relay-landing.test.tsx` and `tabula/web/__tests__/space-detail.test.tsx` use kebab-case, while sibling tests in the same directory use PascalCase.
- **Services, Utilities & Libraries (`.ts`)**:
  - *Backstage*: Standardizes on **`camelCase.ts`** (`cloudRun.ts`, `githubOrgSignIn.ts`, `vitruvianTheme.ts`).
  - *OAuth Inspector Server*: Mixes **`camelCase.ts`** (`safeFetch.ts`, `securityHeaders.ts`) with **`kebab-case.ts`** (`oauth-error-guide.ts`).
  - *Tabula Extension Services*: Shows extreme intra-directory drift across 4 distinct styles in `tabula/extension/src/services/` (`CrossWindowSyncService.ts` [Pascal], `deviceId.ts` [camel], `sections_notes.test.ts` [snake], `workspace-notes.ts` [kebab]).
  - *Pulumi TS Packages*: `pulumi/library/ts/packages/cloud-dns/src/cloud-dns.ts` (kebab) vs `pulumi/examples/ts-foundation/modules/shared_vpc.ts` (snake).

#### Python Ecosystem (3 Files)
- **Standard**: **`snake_case.py`** (`devx/scripts/migrate_to_docker.py`, `pulumi/examples/go-foundation/patch_sa.py`).
- **Identified Violation**: `nexus-agent/hooks/stream-hook.py` uses kebab-case. Because Python modules cannot contain hyphens, `import stream-hook` fails with `SyntaxError: invalid syntax`.

#### Swift / macOS Ecosystem (11 Files)
- **Standard**: **`PascalCase.swift`** (`NexusAgentApp.swift`, `NexusAgentCore.swift`, `StatusBarController.swift`). Single entry point `main.swift` follows standard Apple compiler conventions.

#### Starlark & Bazel Rules (11 Files)
- **Standard**: **`snake_case.bzl`** (100% compliance across `defs.bzl`, `go_image.bzl`, `node_image.bzl`, `py3_image.bzl`, `linters.bzl`). All rule definitions, macros, and parameter names adhere to Starlark `snake_case` specifications.

---

### 2.3 Shell Scripts & Automation Tooling

The repository contains 153 `.sh` shell scripts exhibiting clear domain-level divergence:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ SHELL SCRIPT CASING CONVENTIONS BY SUBSYSTEM                                            │
├──────────────────────────┬──────────────┬──────────────────┬────────────────────────────┤
│ Subsystem / Directory    │ File Count   │ Casing Style     │ Representative Scripts     │
├──────────────────────────┼──────────────┼──────────────────┼────────────────────────────┤
│ tools/ci/, release/, etc.│ 55 scripts   │ kebab-case       │ affected-targets.sh,       │
│                          │              │                  │ delivery-drift.sh          │
├──────────────────────────┼──────────────┼──────────────────┼────────────────────────────┤
│ tools/gitops/            │ 12 scripts   │ snake_case       │ argocd_secret.sh,          │
│                          │              │                  │ gitops_cmd.sh              │
├──────────────────────────┼──────────────┼──────────────────┼────────────────────────────┤
│ tools/pulumi/            │ 8 scripts    │ snake_case       │ create_app.sh,             │
│                          │              │                  │ pulumi_cmd.sh              │
├──────────────────────────┼──────────────┼──────────────────┼────────────────────────────┤
│ tools/copybara/          │ 4 scripts    │ snake_case       │ check_version_maps.sh      │
├──────────────────────────┼──────────────┼──────────────────┼────────────────────────────┤
│ Bazel sh_test Co-located │ 33 scripts   │ Hybrid:          │ affected-targets_test.sh,  │
│                          │              │ <kebab>_test.sh  │ delivery-drift_test.sh     │
└──────────────────────────┴──────────────┴──────────────────┴────────────────────────────┘
```

**Notable Script Drift**:
- Root of `tools/`: `tools/workspace_status.sh` (snake_case) vs `tools/test-mcp-slack-e2e.sh` (kebab-case).
- Tabula extension: `tabula/extension/publish-dev-latest.sh` (kebab-case) vs its test `tabula/extension/publish_dev_latest_test.sh` (snake_case).

---

### 2.4 Documentation & Static Assets

#### Markdown Documents (694 Files)
- **Repository Governance Entrypoints (354 files)**: Strictly **`UPPERCASE.md`** (`README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `PROJECT.md`, `SECURITY.md`, `SKILL.md`).
- **Standard Technical Documentation (148 files)**: Strictly **`kebab-case.md`** (`docs/engineering/application-development-principles.md`, `docs/concepts/monorepo-architecture.md`, `docs/operations/break-glass-deploy-runbook.md`).
- **Implementation & Review Plans (77 files)**: Uses **`snake_case.md`** in `devx/docs/plans/` (`implementation_plan_idea_28.md`, `code_review_idea_44.md`) and `tabula/docs/product/` (`gap_analysis.md`, `verified_journeys.md`).
- **Archive Anomalies**: `docs/archive/gap-analysis/port-cft-pulumi/` mixes uppercase-kebab (`METHODOLOGY-BLINDSPOTS.md`, `REVERIFICATION-2026-07-24.md`) and run-together lowercase (`pulumiportgapanalysisworkflow.md`, `verifierreasoningfull.md`).

#### Static Assets & Images
- **Images (`.png`, `.webp`)**: Mixed conventions. `devx/docs/public/` mixes `hero-dark.png` (kebab) with `devx_k8s_proof.png` (snake).
- **Tabular Metadata (`.tsv`)**: Standardizes on **`kebab-case.tsv`** (`gcp-identities.tsv`, `version-pins.tsv`, `public-targets.tsv`, `agents.tsv`).

---

### 2.5 Bazel Packages, Build Targets & Starlark Rules

Across 299 `BUILD` / `BUILD.bazel` files containing 293 packages and 546 targets:

#### Bazel Package Path Drift
- Monorepo packages default to **`kebab-case`** (`//tools/agent-app`, `//tools/ci-preflight`, `//infrastructure/pulumi/platform/dev-local`).
- **Anomalous snake_case packages**:
  - `//tools/copybara/conflict_precheck` (under `tools/copybara`)
  - `//tools/gitops/appset_render` (under `tools/gitops`)
  - `//infrastructure/pulumi/platform/repo_config` (sits beside `dev-local` and `zitadel-apps`)
  - `//infrastructure/pulumi/foundation/gcp-app-infra/business_unit_1/development` (snake_case subpath under kebab-case foundation root)

#### Target Naming by Rule Type

| Rule Type | Target Count | Standard Naming Pattern | Observed Conventions & Violations |
|---|---|---|---|
| `go_library` | 110 | `snake_case` (`:devx_lib`, `:homelab_lib`, `:agent`) | Generated by Gazelle (`:pkg_lib` or directory name) |
| `go_binary` | 8 | `snake_case` / single-word (`:devx`, `:homelab`, `:gen`) | Gazelle binary rule |
| `go_test` | 74 | `snake_case` (`:agent_test`, `:config_test`, `:sync_test`) | Standard Go test naming |
| `sh_binary` | 80 | `kebab-case` (`:agent-keys-pull`, `:cloud-run`, `:apply`) | CLI command targets |
| `sh_test` | 27 | **SPLIT CONVENTION** | 8 use `<kebab>_test`, 11 use `<snake>_test` |
| `ts_project` | 9 | `snake_case` (`:lib`, `:tests_lib`, `:tools_lib`) | TypeScript compilation rules |
| `js_binary` | 7 | `snake_case` (`:tabcli`, `:api_bin`, `:migrate_deploy_bin`) | Node runtime binary targets |
| `swift_library` | 4 | `PascalCase` (`:NexusAgentCore`, `:NexusAgent_lib`) | Apple naming + mixed snake suffix |
| `swift_test` | 1 | `PascalCase_snake` (`:NexusAgent_tests`) | Apple test target |
| `macos_application` | 1 | `PascalCase` (`:NexusAgent`) | App bundle identifier |
| `pulumi_project` | 76 | Stack / Env name (`:development`, `:production`, `:repo_config`) | Pulumi stack entrypoint wrapper |
| `delivery` | 9 | `kebab-case` (`:oauth-user-inspector`, `:tabula-api`) | Delivery orchestrator registration |

#### The `sh_test` Target Naming Split
Bazel shell test targets exhibit an unresolved naming split:
- **Group A (Kebab-case base + `_test`)**: `:bazel-cache_test`, `:ci-preflight_test`, `:conformance-delivery_test`, `:cloud-run_test`, `:enable-dependency-graph_test`, `:osv-scan_test`, `:pipeline-status_test`, `:publish-local_test`.
- **Group B (Snake-case converted base + `_test`)**: `:agent_app_test`, `:cloud_bootstrap_test`, `:gcp_secrets_test`, `:gcp_token_test`, `:saas_cli_test`, `:pulumi_cmd_test`, `:resolve_identity_test`.

---

### 2.6 Environment Variables & Configuration Namespaces

The repository references **903 distinct environment variables**. 97% conform to `SCREAMING_SNAKE_CASE`.

#### Environment Variable Namespace Distribution

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ ENVIRONMENT VARIABLE NAMESPACES & PREFIXES                                              │
├────────────────────┬──────────────┬────────────────────────┬────────────────────────────┤
│ Namespace Prefix   │ Unique Vars  │ Reference Count        │ Representative Variables   │
├────────────────────┼──────────────┼────────────────────────┼────────────────────────────┤
│ UNPREFIXED         │ 206 vars     │ 1,839 refs             │ TOKEN, ROOT, PWD, DRY_RUN  │
│ FAKE / STUB / MOCK │ 58 vars      │ 105 refs               │ FAKE_GH_LOG, STUB_STATES   │
│ PULUMI             │ 18 vars      │ 74 refs                │ PULUMI_DIR, PULUMI_ESC_ORG │
│ DEVX               │ 18 vars      │ 28 refs                │ DEVX_SYNC_SSH_KEY, DEVX_ENV│
│ GITHUB / GH        │ 19 vars      │ 141 refs               │ GITHUB_TOKEN, GH_TOKEN     │
│ GCP / GOOGLE       │ 15 vars      │ 121 refs               │ GOOGLE_CLOUD_PROJECT,      │
│                    │              │                        │ GCP_PROJECT_ID, GOOGLE_OAUTH_ACCESS_TOKEN │
│ APP / REPO / ORG   │ 26 vars      │ 93 refs                │ APP_DIR, REPO_ROOT, ORG_ID │
│ VERCEL / NEXT      │ 12 vars      │ 64 refs                │ VERCEL_URL, NEXT_PUBLIC_*  │
│ NEXT Internals     │ 15 vars      │ 55 refs                │ __NEXT_BUNDLER, __NEXT_*   │
│ Cloud Run / K8s    │ 3 vars       │ 9 refs                 │ K_SERVICE, K_REVISION      │
│ Node / npm         │ 3 vars       │ 36 refs                │ NODE_ENV, npm_package_version│
└────────────────────┴──────────────┴────────────────────────┴────────────────────────────┘
```

#### Major Environment Variable Inconsistencies & Collisions

1. **GCP Project ID Fragmentation**:
   - `GOOGLE_CLOUD_PROJECT` (used by official GCP SDKs and `AGENTS.md`)
   - `GCP_PROJECT` (used in `tools/deploy/cloud-run.sh`)
   - `GCP_PROJECT_ID` (used in `tools/gcp-token/gcp-token.sh`)
   - `CLOUDSDK_CORE_PROJECT` (used by `gcloud` CLI)
2. **GCP Auth Access Token Collision**:
   - `GOOGLE_OAUTH_ACCESS_TOKEN` (used by Pulumi and Go GCP client libraries)
   - `CLOUDSDK_AUTH_ACCESS_TOKEN` (used by `gcloud` CLI wrappers)
3. **GitHub Authentication Token Drift**:
   - `GH_TOKEN` (used by GitHub CLI `gh` and `tools/agent-app`)
   - `GITHUB_TOKEN` (default token injected by GitHub Actions runners)
4. **Cloudflare Token Naming**:
   - `CLOUDFLARE_API_TOKEN` (unabbreviated, used in Go libraries)
   - `CF_API_TOKEN` / `CF_TUNNEL_TOKEN` (abbreviated, used in shell tools and K8s secrets)

---

### 2.7 CLI Flags & Option Conventions

Analysis of 414 CLI flags identified a clean binary divide based on tool execution context:

1. **Internal Tools & CLIs (100% `kebab-case`)**:
   - **DevX CLI (`devx/cmd/...`)**: Defines 60+ Cobra CLI flags; all multi-word flags use `kebab-case` (`--smtp-port`, `--ci-timeout`, `--skip-preflight`, `--ai-review`, `--db-only`, `--basic-auth`, `--keep-volume`, `--env-file`, `--non-interactive`).
   - **Homelab CLI (`homelab/cmd/...`)**: 100% `kebab-case` (`--dry-run`, `--auto-install`).
   - **Repo Shell Tools (`tools/**/*.sh`)**: 100% `kebab-case` (`--service`, `--env-prefix`, `--pulumi-dir`, `--smoke-path`, `--custom-smoke-script`, `--data-file`).
2. **Bazel Native Flags & Options (100% `snake_case`)**:
   - Bazel core options configured in `.bazelrc` and Starlark strictly use `snake_case` (`--remote_cache`, `--test_tag_filters`, `--workspace_status_command`, `--extra_toolchains`, `--bes_backend`, `--remote_download_outputs`).
3. **Bazel Config Preset Names (`--config=<name>`)**:
   - Mostly single-word (`release`, `lint`, `e2e`, `race`, `ci`, `debug`, `remote`), with two kebab-case presets: `macos-app` (`.bazelrc:72`) and `remotecache-ci` (`tools/remote.bazelrc:51`).

---

### 2.8 GitHub Actions Workflows & Composite Actions

Across **54 workflow files** and **10 composite actions**:

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ GITHUB ACTIONS CASING AUDIT SUMMARY                                                     │
├────────────────────────────┬──────────────┬─────────────────────────────────────────────┤
│ Syntax Element             │ Total Count  │ Casing Pattern & Observed Compliance        │
├────────────────────────────┼──────────────┼─────────────────────────────────────────────┤
│ Workflow Filename Stems    │ 54 files     │ kebab-case (45), _<kebab> (9 reusable)      │
│ Workflow Extensions        │ 54 files     │ 48 use .yaml, 6 use .yml (DRIFT)            │
│ Job IDs (`jobs.<id>`)      │ 108 jobs     │ 100% kebab-case (0 snake_case jobs)         │
│ Step IDs (`steps.id`)      │ 44 steps     │ 100% kebab-case                             │
│ Workflow Inputs (`inputs`) │ 38 inputs    │ 20 kebab-case (53%), 18 snake_case (47%)    │
│ Workflow Outputs           │ 22 outputs   │ 5 kebab-case (23%), 11 snake_case (50%)     │
│ Composite Action Inputs    │ 21 inputs    │ 100% kebab-case                             │
│ Composite Action Outputs   │ 14 outputs   │ 5 kebab-case, 2 snake_case, 7 single-word   │
│ Environment Variables      │ 126 env keys │ 100% SCREAMING_SNAKE_CASE                   │
└────────────────────────────┴──────────────┴─────────────────────────────────────────────┘
```

#### Detailed Workflow Inconsistencies

1. **Workflow Extension Drift**: 6 workflows use `.yml` while 48 use `.yaml`:
   - `.github/workflows/apps-release.yml`
   - `.github/workflows/dependabot-auto-merge.yml`
   - `.github/workflows/dependabot-bazel-reconcile.yml`
   - `.github/workflows/dependabot-lock-rebase.yml`
   - `.github/workflows/pulumi-library-release.yml`
   - `.github/workflows/tabula-release.yml`
2. **Workflow Inputs Casing Split**:
   - App delivery workflows use **`kebab-case`**: `app-name`, `bazel-image-target`, `dockerfile-dir`, `image-digest`, `service-name`, `pulumi-dir`, `env-prefix`, `smoke-url-path`.
   - Foundation & Copybara workflows use **`snake_case`**: `working_directory`, `business_unit`, `app_image_digests`, `allow_destructive`, `copybara_options`, `only_component`.
3. **Workflow Outputs Casing Split**:
   - Matrix/orchestration outputs use **`snake_case`**: `affected_charts`, `affected_oauth_user_inspector`, `affected_tabula_api`, `affected_zitadel_apps`, `release_created`.
   - Build outputs use **`kebab-case`**: `image-digest`, `web-image-digest`.
4. **Intra-Action Output Collision**:
   - `.github/actions/pulumi-run-captured/action.yml` exports both `exit_code` (snake_case) and `out-file` (kebab-case) from the same action.

---

### 2.9 Kubernetes Manifests, Helm Charts & GitOps

Across **169 Kubernetes and ArgoCD manifest files**:

1. **Resource Names (`metadata.name`)**: 100% compliance with RFC 1123 DNS subdomains (`kebab-case` / lowercase alphanumeric with hyphens, e.g. `alertmanager-ntfy-bridge`, `cnpg-cluster`, `opentelemetry-collector`). Underscores are strictly forbidden by Kubernetes API validation.
2. **Namespaces (`metadata.namespace`)**: 100% `kebab-case` (`argocd`, `cert-manager`, `kube-system`).
3. **Resource Spec Fields**: 100% `camelCase` as enforced by Kubernetes OpenAPI schemas (`serviceAccountName`, `imagePullPolicy`, `targetRevision`, `repoURL`).
4. **Custom Annotations**: 100% domain-prefixed `kebab-case` (`argocd.argoproj.io/sync-wave`, `backstage.io/techdocs-ref`, `vitruvian.dev/release-model`, `external-dns.alpha.kubernetes.io/cloudflare-proxied`).
5. **Helm Values (`values.yaml`)**: Standardizes on `camelCase` properties (`replicaCount`, `podAnnotations`, `securityContext`).

---

### 2.10 Pulumi Infrastructure Definitions & Stacks

Pulumi infrastructure definitions represent the single largest area of naming inconsistency in the repository.

#### Project Names (`Pulumi.yaml` `name:` field)
- **Foundation & Platform Stacks**: Use **`kebab-case`** (`foundation-bootstrap`, `foundation-projects-bu1-production`, `oauth-user-inspector-app`, `zitadel-apps`).
- **Application Stacks & GitHub Repo Config**: Use **`snake_case` with prefixes** (`pulumi_tabula_app`, `pulumi_tabula_web`, `pulumi_tabula_build`, `pulumi_tabula_data`, `pulumi_oauth_user_inspector`, `repo_config`).

#### Stack Configuration Property Keys (`Pulumi.<env>.yaml`)
Stack configurations store key-value pairs formatted as `<namespace>:<property>`. The monorepo exhibits severe drift across different domains:

```yaml
# Foundation Go Stacks use snake_case property keys:
foundation-bootstrap:billing_account: "012345-6789AB-CDEF01"
foundation-bootstrap:group_org_admins: "gcp-organization-admins@vitruvian.dev"
foundation-bootstrap:create_required_groups: "true"

# Application TypeScript Stacks use camelCase property keys:
tabula-app:runtimeServiceAccount: "tabula-sa@prj-d-bu2-tabula-app-1234.iam.gserviceaccount.com"
tabula-app:customDomain: "tabula.vitruvian.dev"
tabula-app:cloudflareZoneId: "0123456789abcdef"

# Sibling Build & Identity Stacks MIX snake_case and camelCase in the same file:
tabula-deploy-identity:bootstrap_stack: "ipv1337/foundation-bootstrap/production"           # snake_case
tabula-deploy-identity:projects_stack: "ipv1337/foundation-projects-bu2-development/production" # snake_case
tabula-deploy-identity:domainVerificationAnchor: true                                    # camelCase
tabula-deploy-identity:cloudflareTokenAccessorProjects: "prj-d-bu2-..."                   # camelCase
```

---

### 2.11 Tool Configurations, Schemas & Serialization Layers

#### Upstream Tool Configuration Schemas
- **Renovate (`renovate.json5`)**: Strict `camelCase` schema mandated by Renovate (`enabledManagers`, `packageRules`, `matchManagers`).
- **Release Please (`release-please-config.json`)**: Strict `kebab-case` schema mandated by Google Release Please (`release-type`, `bump-minor-pre-major`, `changelog-path`).
- **Dependabot (`.github/dependabot.yml`)**: Strict `kebab-case` schema mandated by GitHub (`package-ecosystem`, `open-pull-requests-limit`, `update-types`).
- **OSV Scanner (`osv-scanner.toml`)**: Strict `PascalCase` headers (`[[IgnoredVulns]]`) and `camelCase` keys (`ignoreUntil`) mandated by Google OSV.
- **Gitleaks (`.gitleaks.toml`)**: Strict `camelCase` keys (`useDefault`, `regexTarget`, `targetRules`).
- **Python Packaging (`pyproject.toml`)**: Strict PEP 518/621 `snake_case` / `lower_single` fields.

#### Internal Tool Schema Drift
- **Vitruvian Initializer (`tools/initializer/config.json`)**: Mixes `snake_case` top-level keys (`template_suffix`, `deploy_targets`), `camelCase` nested fields (`appliesTo`), and `kebab-case` preset identifiers (`go-minimal`).
- **Vitruvian DevX (`devx.yaml`)**: Mixes `snake_case` fields (`grafana_url`, `depends_on`), `camelCase` blocks (`customActions`), and `kebab-case` action names (`provision-local-dev-infrastructure`).

#### Database Persistence vs. API Wire Format Serialization
The Tabula system (`tabula/api/prisma/schema.prisma` and `tabula/api/openapi.yaml`) maintains a clean, deliberate dual-layer serialization boundary:
- **Database Persistence Layer (PostgreSQL via Prisma `@map`)**: Tables (`workspaces`, `space_collaborators`, `share_links`), columns (`password_hash`, `created_at`, `user_id`, `favicon_url`), and index constraints (`idx_workspaces_user`) strictly use **`snake_case`**.
- **TypeScript Runtime & OpenAPI Wire Format**: Model properties and API JSON request/response bodies strictly use **`camelCase`** (`passwordHash`, `createdAt`, `userId`, `faviconUrl`, `isPinned`, `perPage`).

---

## 3. Ecosystem Technical Constraints vs. Unintentional Drift

### 3.1 Hard Language & Platform Constraints

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ HARD TECHNICAL CONSTRAINTS VS. AVOIDABLE DRIFT                                          │
├──────────────────────────┬─────────────────────────────┬────────────────────────────────┤
│ Language / Platform      │ Hard Technical Constraint   │ Technical Justification        │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ Go Packages              │ Identifiers cannot use `-`  │ Go grammar defines identifiers │
│                          │ (`package cloud_dns` only)  │ as [a-zA-Z_][a-zA-Z0-9_]*. `-` │
│                          │                             │ is parsed as minus operator.   │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ Python Modules           │ Module files cannot use `-` │ `import foo-bar` triggers      │
│                          │ (`foo_bar.py` only)         │ SyntaxError in Python parser.  │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ Kubernetes Resources     │ Resource names cannot use `_`│ RFC 1123 DNS subdomain format  │
│                          │ (`[a-z0-9]([-a-z0-9]*[a-z0-9])?`) mandates lowercase + hyphen. │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ React / JSX              │ Component filenames & tags  │ JSX compiler distinguishes     │
│                          │ must use PascalCase         │ HTML elements from components  │
│                          │                             │ based on initial capital.      │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ Swift / Apple macOS      │ Module, class, and bundle   │ Apple toolchains, Xcode, and   │
│                          │ identifiers use PascalCase  │ Swift PM enforce PascalCase.   │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ Prisma Migrations        │ Migration dirs format is    │ Prisma engine expects timestamp│
│                          │ `YYYYMMDDHHMMSS_name`       │ lock matching lockfile.        │
├──────────────────────────┼─────────────────────────────┼────────────────────────────────┤
│ Starlark Rules (.bzl)    │ Rules, macros, attrs must   │ Bazel Starlark specification   │
│                          │ use snake_case              │ enforces Python-like syntax.   │
└──────────────────────────┴─────────────────────────────┴────────────────────────────────┘
```

### 3.2 Third-Party Tool-Mandated Schemas

- **Renovate**: Configuration requires `camelCase` properties. (Attempting to use kebab-case fails JSON schema validation).
- **Release Please**: Manifests and configs require `kebab-case` keys (`release-type`, `bump-minor-pre-major`).
- **Dependabot**: Schema requires `kebab-case` keys (`package-ecosystem`, `directory`, `schedule`).
- **OSV-Scanner**: TOML parser requires `PascalCase` headers (`[[IgnoredVulns]]`) and `camelCase` keys (`ignoreUntil`).
- **Gitleaks**: TOML configuration mandates `camelCase` keys (`useDefault`, `regexTarget`).

### 3.3 Constraint vs. Drift Authority Matrix

| Architectural Layer | Canonical Casing Standard | Permitted Ecosystem Exception | Prohibited Patterns (Unintentional Drift) |
|---|---|---|---|
| **Root & Package Directories** | `kebab-case` | `snake_case` (Go package dirs, Prisma migrations) | `snake_case` for general tools, apps, or platform dirs |
| **Go Source Files** | `snake_case.go` | `lower_single.go`, `camelCase.go` (Pulumi generated SDK) | `kebab-case.go` (`net-hubs.go`) |
| **Python Source Files** | `snake_case.py` | `lower_single.py` | `kebab-case.py` (`stream-hook.py`) |
| **React / UI Files** | `PascalCase.tsx` | None | `kebab-case.test.tsx` (`relay-landing.test.tsx`) |
| **TypeScript Services & Libs**| `kebab-case.ts` | `camelCase.ts` (Backstage plugins, utilities) | Mixed 4-way casing in a single directory |
| **Swift Source Files** | `PascalCase.swift`| `main.swift` | `snake_case.swift`, `kebab-case.swift` |
| **Shell Scripts** | `kebab-case.sh` | `<binary>_test.sh` (co-located test scripts) | `snake_case.sh` in `tools/gitops/`, `tools/pulumi/` |
| **Documentation** | `kebab-case.md` | `UPPERCASE.md` (`README.md`, `PROJECT.md`) | Arbitrary `snake_case.md` for new docs |
| **Bazel Binary / Tool Targets**| `kebab-case` | None | `snake_case` for operational tools (`:agent_app`) |
| **Bazel Go Targets** | `snake_case` | None (Gazelle standard) | `kebab-case` for Go libs (`:devx-lib`) |
| **Bazel Shell Test Targets** | `<binary-name>_test`| None | Arbitrary `<package_snake>_test` renaming |
| **Starlark Rules & Macros** | `snake_case` | None | `camelCase` or `kebab-case` rules/macros |
| **Environment Variables** | `SCREAMING_SNAKE` | Framework injected (`npm_package_version`, `__NEXT_*`, `K_SERVICE`) | `kebab-case`, duplicate synonyms (`GCP_PROJECT`) |
| **Internal CLI Flags** | `kebab-case` (`--dry-run`)| None | `snake_case` internal flags (`--dry_run`) |
| **Bazel Native Options** | `snake_case` (`--remote_cache`)| None (Bazel core standard) | `kebab-case` Bazel core flags |
| **GitHub Actions Jobs/Steps** | `kebab-case` | None | `snake_case` jobs or steps |
| **GitHub Actions Inputs/Outputs**| `kebab-case` | Reusable output mapping | `snake_case` inputs (`working_directory`, `business_unit`) |
| **Kubernetes Metadata** | `kebab-case` (DNS-1123) | None | Underscores anywhere in K8s metadata |
| **Kubernetes OpenAPI Specs** | `camelCase` | None (K8s OpenAPI standard) | `kebab-case` spec fields |
| **Pulumi Project Names** | `kebab-case` | None | `pulumi_` prefix, `snake_case` project names |
| **Pulumi Stack Keys** | Domain-consistent | Go Foundation: `snake_case`; TS App: `camelCase` | In-file mixing of `snake_case` and `camelCase` |

---

## 4. Inconsistency & Drift Inventory (Complete Catalog)

### 4.1 Source File Filename Anomalies

| Relative File Path | Current Filename | Expected Standard | Severity / Risk | Technical Impact |
|---|---|---|---|---|
| `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs.go` | `net-hubs.go` | `net_hubs.go` | Low / Safe | Violates standard Go filename idioms |
| `infrastructure/pulumi/foundation/gcp-networks/envs/shared/net-hubs-transitivity.go` | `net-hubs-transitivity.go` | `net_hubs_transitivity.go` | Low / Safe | Violates standard Go filename idioms |
| `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs.go` | `net-hubs.go` | `net_hubs.go` | Low / Safe | Violates standard Go filename idioms |
| `pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/net-hubs-transitivity.go` | `net-hubs-transitivity.go` | `net_hubs_transitivity.go` | Low / Safe | Violates standard Go filename idioms |
| `nexus-agent/hooks/stream-hook.py` | `stream-hook.py` | `stream_hook.py` | **High / Broken** | `import stream-hook` fails with SyntaxError |
| `tabula/web/__tests__/relay-landing.test.tsx` | `relay-landing.test.tsx` | `RelayLanding.test.tsx` | Low / Safe | Inconsistent with sibling React PascalCase tests |
| `tabula/web/__tests__/space-detail.test.tsx` | `space-detail.test.tsx` | `SpaceDetail.test.tsx` | Low / Safe | Inconsistent with sibling React PascalCase tests |

---

### 4.2 Directory & Bazel Package Path Inconsistencies

| Path | Current Casing | Sibling Directory Casing | Recommended Rename |
|---|---|---|---|
| `infrastructure/pulumi/platform/repo_config/` | `snake_case` | `dev-local`, `zitadel-apps` (`kebab-case`) | `infrastructure/pulumi/platform/repo-config/` |
| `tools/copybara/conflict_precheck/` | `snake_case` | `tools/agent-app/`, `tools/ci-preflight/` (`kebab-case`) | `tools/copybara/conflict-precheck/` |
| `tools/gitops/appset_render/` | `snake_case` | `tools/gitops/` (`kebab-case` siblings) | `tools/gitops/appset-render/` |
| `infrastructure/pulumi/foundation/gcp-networks/modules/vpn-ha/` | `kebab-case` | `base_env`, `shared_vpc` (`snake_case` Go pkgs) | `infrastructure/pulumi/foundation/gcp-networks/modules/vpn_ha/` |
| `pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/vpn-ha/` | `kebab-case` | `base_env`, `shared_vpc` (`snake_case` Go pkgs) | `.../modules/vpn_ha/` |
| `pulumi/examples/go-foundation/3-networks-svpc/modules/vpn-ha/` | `kebab-case` | `base_env`, `shared_vpc` (`snake_case` Go pkgs) | `.../modules/vpn_ha/` |
| `pulumi/examples/ts-foundation/1-org/modules/cai-monitoring/` | `kebab-case` | `modules/shared_vpc/`, `modules/base_env/` (`snake_case`) | Harmonize across TS examples |

---

### 4.3 Bazel Target & `sh_test` Inconsistencies

| Target Label | BUILD File Location | Associated Binary Target | Issue Description | Proposed Standard Target |
|---|---|---|---|---|
| `//tools/agent-app:agent_app_test` | `tools/agent-app/BUILD:25` | `//tools/agent-app:agent-app` | Snake-case conversion of kebab binary | `//tools/agent-app:agent-app_test` |
| `//tools/cloud-bootstrap:cloud_bootstrap_test` | `tools/cloud-bootstrap/BUILD:59` | `//tools/cloud-bootstrap:cloud-bootstrap` | Snake-case conversion of kebab binary | `//tools/cloud-bootstrap:cloud-bootstrap_test` |
| `//tools/gcp-token:gcp_token_test` | `tools/gcp-token/BUILD:43` | `//tools/gcp-token:gcp-token` | Snake-case conversion of kebab binary | `//tools/gcp-token:gcp-token_test` |
| `//tools/gcp-secrets:gcp_secrets_test` | `tools/gcp-secrets/BUILD:46` | `//tools/gcp-secrets:seed` | Snake-case conversion of kebab pkg | `//tools/gcp-secrets:gcp-secrets_test` |
| `//tools/saas-cli:saas_cli_test` | `tools/saas-cli/BUILD:55` | `//tools/saas-cli:neon` | Snake-case conversion of kebab pkg | `//tools/saas-cli:saas-cli_test` |
| `//nexus-agent/macos:NexusAgent_lib` | `nexus-agent/macos/BUILD:20` | - | Mixed PascalCase + snake suffix | `//nexus-agent/macos:NexusAgentLib` |
| `//nexus-agent/macos:NexusAgent_tests` | `nexus-agent/macos/BUILD:32` | - | Mixed PascalCase + snake suffix | `//nexus-agent/macos:NexusAgentTests` |
| `//nexus-agent/hooks:stream-hook` | `nexus-agent/hooks/BUILD:4` | `stream-hook.py` | `py_binary` kebab-case target | `//nexus-agent/hooks:stream_hook` |

---

### 4.4 Intra-Directory File Casing Clashes

| Directory | Files Exhibiting Inconsistency | Mixed Casing Types Observed | Recommended Action |
|---|---|---|---|
| Repository Root (`/`) | `catalog-info.yaml`, `pnpm-workspace.yaml`, `osv-scanner.toml` vs `gazelle_python.yaml`, `maven_install.json` | kebab-case vs snake_case | Standardize human configs on kebab; document generator exceptions |
| `.aspect/gazelle/` | `package-json-scripts.axl` (kebab) vs `go_image.axl`, `py3_image.axl` (snake) | kebab-case vs snake_case | Standardize Gazelle rules on snake_case |
| `tools/` | `test-mcp-slack-e2e.sh` (kebab) vs `workspace_status.sh` (snake) | kebab-case vs snake_case | Standardize scripts on kebab-case (`workspace-status.sh`) |
| `tabula/extension/` | `publish-dev-latest.sh` (kebab) vs `publish_dev_latest_test.sh` (snake) | kebab-case vs snake_case | Rename test script to `publish-dev-latest_test.sh` |
| `oauth-user-inspector/server/` | `oauth-error-guide.ts` (kebab) vs `apiEndpoints.server.ts`, `rateLimit.ts` (camel) | kebab-case vs camelCase | Standardize server services on camelCase or kebab-case |
| `tabula/extension/src/services/` | `CrossWindowSyncService.ts` (Pascal), `deviceId.ts` (camel), `sections_notes.test.ts` (snake), `workspace-notes.ts` (kebab) | Pascal vs camel vs snake vs kebab | Standardize TS service files on kebab-case |
| `tabula/web/lib/` | `safeHref.ts` (camel) vs `json-script.ts`, `runtime-config.ts` (kebab) | camelCase vs kebab-case | Standardize web library utilities on kebab-case |
| `tabula/docs/architecture/` | `workona_research.md` (snake) vs `conflict-resolution.md`, `sync-strategy.md` (kebab) | snake_case vs kebab-case | Rename docs to kebab-case (`workona-research.md`) |
| `tabula/docs/product/` | `gap_analysis.md`, `verified_journeys.md` (snake) vs `ui-design-language.md` (kebab) | snake_case vs kebab-case | Standardize product docs on kebab-case |
| `devx/docs/public/` | `hero-dark.png` (kebab) vs `devx_k8s_proof.png`, `devx_mock_proof.png` (snake) | kebab-case vs snake_case | Standardize docs images on kebab-case |

---

### 4.5 Pulumi Project & Stack Config Key Inconsistencies

#### Pulumi Project Name Drift (`Pulumi.yaml`)

| Project Path | Current Declared Name | Desired Standard Name | Migration Impact |
|---|---|---|---|
| `tabula/infra/app/Pulumi.yaml` | `pulumi_tabula_app` | `tabula-app` | Requires stack state migration / alias |
| `tabula/infra/build/Pulumi.yaml` | `pulumi_tabula_build` | `tabula-build` | Requires stack state migration / alias |
| `tabula/infra/data/Pulumi.yaml` | `pulumi_tabula_data` | `tabula-data` | Requires stack state migration / alias |
| `tabula/infra/identity/Pulumi.yaml` | `pulumi_tabula_deploy_identity` | `tabula-deploy-identity` | Requires stack state migration / alias |
| `tabula/infra/web/Pulumi.yaml` | `pulumi_tabula_web` | `tabula-web` | Requires stack state migration / alias |
| `infrastructure/pulumi/platform/repo_config/Pulumi.yaml` | `repo_config` | `repo-config` | Requires stack state migration / alias |
| `infrastructure/pulumi/platform/zitadel-apps/Pulumi.yaml` | `pulumi_zitadel_apps` | `zitadel-apps` | Requires stack state migration / alias |
| `oauth-user-inspector/infra/app/Pulumi.yaml` | `oauth-user-inspector-app` | `oauth-user-inspector-app` | Already compliant with kebab-case |
| `infrastructure/pulumi/foundation/gcp-bootstrap/Pulumi.yaml` | `foundation-bootstrap` | `foundation-bootstrap` | Already compliant with kebab-case |

#### Pulumi Stack Config In-File Property Drift (`Pulumi.<env>.yaml`)

| Stack Configuration File | Inconsistent Property Keys | Mixed Styles Observed | Recommended Resolution |
|---|---|---|---|
| `tabula/infra/identity/Pulumi.development.yaml` | `bootstrap_stack`, `projects_stack` vs `domainVerificationAnchor`, `cloudflareTokenAccessorProjects` | `snake_case` + `camelCase` | Standardize TS app stacks on `camelCase` (`bootstrapStack`, `projectsStack`) |
| `tabula/infra/identity/Pulumi.production.yaml` | `bootstrap_stack`, `projects_stack` vs `domainVerificationAnchor`, `cloudflareTokenAccessorProjects` | `snake_case` + `camelCase` | Standardize TS app stacks on `camelCase` (`bootstrapStack`, `projectsStack`) |
| `tabula/infra/build/Pulumi.production.yaml` | `bootstrap_stack` vs `operatorPrincipal` | `snake_case` + `camelCase` | Standardize TS app stacks on `camelCase` (`bootstrapStack`) |
| `tabula/infra/app/Pulumi.development.yaml` | `bootstrap_stack` vs `runtimeServiceAccount`, `customDomain`, `apiUrl` | `snake_case` + `camelCase` | Standardize TS app stacks on `camelCase` (`bootstrapStack`) |

---

### 4.6 GitHub Actions Workflow Inputs, Outputs & Extensions

#### Workflow File Extensions (`.yaml` vs `.yml`)

| File Path | Current Extension | Standard Extension |
|---|---|---|
| `.github/workflows/apps-release.yml` | `.yml` | `.yaml` |
| `.github/workflows/dependabot-auto-merge.yml` | `.yml` | `.yaml` |
| `.github/workflows/dependabot-bazel-reconcile.yml` | `.yml` | `.yaml` |
| `.github/workflows/dependabot-lock-rebase.yml` | `.yml` | `.yaml` |
| `.github/workflows/pulumi-library-release.yml` | `.yml` | `.yaml` |
| `.github/workflows/tabula-release.yml` | `.yml` | `.yaml` |

#### Workflow Inputs Casing Inconsistencies

| Workflow File | Current Input Key | Standard Input Key | Casing Type |
|---|---|---|---|
| `.github/workflows/_copybara-export.yaml` | `copybara_options` | `copybara-options` | snake_case → kebab-case |
| `.github/workflows/copybara-import-pr.yaml` | `only_component`, `poll_only` | `only-component`, `poll-only` | snake_case → kebab-case |
| `.github/workflows/foundation-app-deploy.yaml` | `working_directory`, `business_unit`, `app_image_digests` | `working-directory`, `business-unit`, `app-image-digests` | snake_case → kebab-case |
| `.github/workflows/foundation-proj-deploy.yaml`| `working_directory`, `business_unit`, `allow_destructive` | `working-directory`, `business-unit`, `allow-destructive` | snake_case → kebab-case |
| `.github/workflows/pulumi-stack-reset.yaml` | `pulumi_dir` | `pulumi-dir` | snake_case → kebab-case |

#### Workflow & Composite Action Outputs Casing Inconsistencies

| Workflow / Action File | Current Output Key | Standard Output Key | Context |
|---|---|---|---|
| `.github/workflows/delivery.yaml` | `affected_charts` | `affected-charts` | Orchestration matrix output |
| `.github/workflows/delivery.yaml` | `affected_tabula_api` | `affected-tabula-api` | Orchestration matrix output |
| `.github/workflows/delivery.yaml` | `affected_oauth_user_inspector` | `affected-oauth-user-inspector` | Orchestration matrix output |
| `.github/workflows/delivery.yaml` | `affected_zitadel_apps` | `affected-zitadel-apps` | Orchestration matrix output |
| `.github/workflows/_foundation-release-please.yaml` | `release_created` | `release-created` | Release output |
| `.github/actions/gcp-auth/action.yml` | `access_token` | `access-token` | Auth composite action |
| `.github/actions/pulumi-run-captured/action.yml` | `exit_code` | `exit-code` | Execution action (sits next to `out-file`) |

---

### 4.7 Environment Variable Namespace Fragmentation

| Inconsistency / Synonym Cluster | Variables in Active Use | Source Locations | Remediation Strategy |
|---|---|---|---|
| **GCP Project ID** | `GOOGLE_CLOUD_PROJECT`<br>`GCP_PROJECT`<br>`GCP_PROJECT_ID`<br>`CLOUDSDK_CORE_PROJECT` | `AGENTS.md:95`<br>`tools/deploy/cloud-run.sh:42`<br>`tools/gcp-token/gcp-token.sh:58`<br>`devx/internal/cloud/gcp.go:34` | Canonicalize on `GOOGLE_CLOUD_PROJECT` monorepo-wide. Deprecate `GCP_PROJECT`. Map to `CLOUDSDK_CORE_PROJECT` inside gcloud CLI wrappers. |
| **GCP Access Token** | `GOOGLE_OAUTH_ACCESS_TOKEN`<br>`CLOUDSDK_AUTH_ACCESS_TOKEN` | `AGENTS.md:94`<br>`tools/pulumi/pulumi_cmd.sh:80`<br>`devx/internal/cloud/gcp.go:77` | Canonicalize on `GOOGLE_OAUTH_ACCESS_TOKEN`. Mirror to `CLOUDSDK_AUTH_ACCESS_TOKEN` only in gcloud wrapper scripts. |
| **GitHub Access Token** | `GH_TOKEN`<br>`GITHUB_TOKEN` | `AGENTS.md:46`<br>`tools/agent-app/main.go:88`<br>`.github/workflows/ci.yaml:45` | Standardize on `GH_TOKEN` for developer/CLI auth; support `GITHUB_TOKEN` fallback for GitHub Actions runners. |
| **Cloudflare API Token** | `CLOUDFLARE_API_TOKEN`<br>`CF_API_TOKEN`<br>`CF_TUNNEL_TOKEN` | `devx/internal/cloudflare/dns.go:42`<br>`tools/sync-env-secrets/sync_env_secrets.sh:85`<br>`gitops/argocd/platform/cloudflared/secret.yaml:12` | Standardize external API auth on `CLOUDFLARE_API_TOKEN`. Reserve `CF_TUNNEL_TOKEN` specifically for ArgoCD tunnel secrets. |

---

### 4.8 Internal Tool Schema & Config Inconsistencies

| Tool Configuration File | Inconsistent Keys / Fields | Nature of Drift | Recommended Resolution |
|---|---|---|---|
| `tools/initializer/config.json` | `template_suffix`, `deploy_targets` (snake) vs `appliesTo` (camel) vs `go-minimal` (kebab) | Mixed top-level and nested casing within custom schema | Standardize JSON schema keys on `snake_case` (`applies_to`) |
| `devx.yaml` | `customActions` (camel) holding `provision-local-dev-infrastructure` (kebab) vs `grafana_url` (snake) | Mixed field naming in DevX orchestration definition | Standardize DevX schema on `snake_case` (`custom_actions`) |
| `tabula/extension/src/build_info.json` | `build_info.json` | Snake_case filename vs kebab-case config standard | Rename to `build-info.json` |
| `tabula/api/prisma/migrations/migration_lock.toml` | `migration_lock.toml` | Snake_case filename | Exempt (Prisma engine locked default) |
| Root `gazelle_python.yaml` | `gazelle_python.yaml` | Snake_case filename | Exempt (rules_python gazelle generator default) |
| Root `maven_install.json` | `maven_install.json` | Snake_case filename | Exempt (rules_jvm_external pin generator default) |

---

## 5. Strategic Recommendations for Downstream Milestones

### 5.1 Alignment with Milestone 2 (Global Naming Standard Specification)
- **Codify Universal Defaults**: Establish `kebab-case` as the global monorepo default for directory paths, tool binaries, CLI flags, GitHub workflows, Kubernetes resources, and documentation files.
- **Formalize Hard Technical Overrides**: Explicitly register Go package `snake_case`, Python module `snake_case`, React component `PascalCase`, Swift `PascalCase`, and PostgreSQL `snake_case` as hard platform exceptions with documented compiler/runtime rationale.
- **Define Compound Word & Acronym Rules**: Require strict lowercase in kebab-case (`cloud-dns`, not `cloud-DNS`; `gcp-org`, not `GCP-org`), strict lowercase in snake_case (`cloud_dns`, `gcp_org`), and camelCase/PascalCase rules (`cloudDns`, `CloudDns`, `OAuthUserInspector`).

### 5.2 Alignment with Milestone 3 (Automated Enforcement Tooling)
- **Implement Multi-Rule Linter Engine (`tools/lint-naming`)**:
  - Rule `DIR_KEBAB_CASE`: Verifies directory names conform to `^[a-z0-9]+(-[a-z0-9]+)*$` with registered exclusions for Go package directories and Prisma migrations.
  - Rule `GO_FILE_SNAKE_CASE`: Verifies Go files match `^[a-z0-9]+(_[a-z0-9]+)*(_test)?\.go$` (flags the 4 `net-hubs*.go` files).
  - Rule `PY_FILE_SNAKE_CASE`: Verifies Python files match `^[a-z0-9]+(_[a-z0-9]+)*\.py$` (flags `stream-hook.py`).
  - Rule `SH_TEST_TARGET_NAME`: Verifies Bazel shell test targets match `<binary-name>_test`.
  - Rule `WORKFLOW_INPUTS_KEBAB`: Verifies workflow inputs and outputs use `kebab-case`.
  - Rule `ENV_SCREAMING_SNAKE`: Verifies environment variables match `^[A-Z0-9]+(_[A-Z0-9]+)*$`.
- **Integrate with Bazel**: Provide `//tools/lint-naming:lint-naming` runnable target and `//tools/lint-naming:lint-naming_test` test target with standard non-zero exit codes.

### 5.3 Alignment with Milestone 4 (Phased Refactoring & Migration Plan)
- **Phase 1: Zero-Risk Non-Breaking Fixes**:
  - Rename 4 Go source files (`net-hubs.go` → `net_hubs.go`).
  - Rename `stream-hook.py` → `stream_hook.py` and update Bazel `py_binary` target.
  - Rename 6 workflow files `.yml` → `.yaml`.
  - Standardize 2 React test files to PascalCase.
- **Phase 2: Internal Tool & Target Harmonization**:
  - Standardize 27 `sh_test` targets to `<binary-name>_test`.
  - Rename `tools/gitops/appset_render` and `tools/copybara/conflict_precheck` directories.
  - Standardize shell scripts under `tools/` to `kebab-case.sh`.
- **Phase 3: CI/CD Workflow Contract Harmonization**:
  - Update workflow inputs and outputs to `kebab-case` with backwards-compatible alias bridging.
- **Phase 4: Pulumi Infrastructure Project & Stack Key Harmonization**:
  - Migrate `Pulumi.yaml` project names and `Pulumi.<env>.yaml` stack configuration keys using state export/import and alias scripts to prevent live cloud resource recreation.

---

*This document serves as the official, authoritative repository audit deliverable for Milestone 1 and provides the empirical foundation for the Global Naming Convention Specification (Milestone 2) and Automated Enforcement Tooling (Milestone 3).*
