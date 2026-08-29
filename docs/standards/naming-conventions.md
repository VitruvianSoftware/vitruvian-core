# Monorepo Naming Conventions & Consistency Standard

> **Status:** Authoritative Standard for the `vitruvian-core` Monorepo  
> **Document Version:** 1.0.0  
> **Effective Date:** 2026-08-28  
> **Audience:** All engineers, architects, code contributors, automated tooling, and AI agents operating within `vitruvian-core`.

---

## 1. Purpose, Scope & Architectural Principles

### 1.1 Purpose
This standard establishes the single, authoritative, monorepo-wide naming convention specification for `vitruvian-core`. In a polyglot monorepo spanning Go, TypeScript/JavaScript, Python, Swift, Shell, Bazel Starlark, Kubernetes/ArgoCD, Pulumi Infrastructure as Code (IaC), and GitHub Actions, naming divergence causes cognitive friction, broken imports, schema drift, build cache misses, and pipeline failures.

This specification eliminates ambiguity by providing:
1. **Definitive casing rules** for every directory, file type, build target, configuration key, environment variable, CLI flag, and serialization interface.
2. **Explicit ecosystem boundaries** that clearly delineate hard language/tooling constraints (e.g., Go package syntax, Python import grammar, Kubernetes RFC 1123 DNS constraints) from internal conventions.
3. **An authoritative compound words and acronyms guide** across all casing paradigms.
4. **An explicit, technically justified exception catalog** preventing arbitrary exceptions.
5. **Concrete compliant vs. non-compliant examples** for every rule.
6. **Formal machine-enforceable regular expressions** serving as the direct contract for automated linting (`tools/lint-naming`) and CI verification.

### 1.2 Architectural Principles
- **Principle 1: Predictability Over Preference**: Every naming choice is governed by an explicit rule. Where multiple stylistic options exist, the monorepo standardizes on one canonical form.
- **Principle 2: Respect Hard Ecosystem Constraints**: Language compilers, runtimes, and upstream platform schemas take precedence within their isolated domain. Never force a naming style onto a language ecosystem where doing so breaks syntax or idioms (e.g., forcing hyphens into Go package directories or Python filenames).
- **Principle 3: Clean Boundary Translations**: When data or identifiers traverse language or architectural boundaries (e.g., Database `snake_case` → Wire JSON `camelCase` → Shell Env `SCREAMING_SNAKE_CASE`), translations must follow explicit mapping contracts.
- **Principle 4: Zero Ambient Drift**: Sibling files, directories, and build targets within the same architectural layer must adhere to the same naming convention without local divergence.
- **Principle 5: Every Fix Ships with the Check That Enforces It**: All rules defined herein are backed by automated linters in `tools/lint-naming` and verified in CI via `bazel test //tools/lint-naming:lint-naming_test`.

---

## 2. Global Casing Taxonomy & Master Authority Matrix

### 2.1 Casing Definitions

| Casing Style | Formal Regex Pattern | Character Set | Representative Example |
|---|---|---|---|
| **`kebab-case`** | `^[a-z0-9]+(-[a-z0-9]+)*$` | Lowercase alphanumeric, hyphen delimiter | `oauth-user-inspector`, `agent-app` |
| **`snake_case`** | `^[a-z0-9]+(_[a-z0-9]+)*$` | Lowercase alphanumeric, underscore delimiter | `cloud_build`, `net_hubs.go` |
| **`SCREAMING_SNAKE_CASE`** | `^[A-Z0-9]+(_[A-Z0-9]+)*$` | Uppercase alphanumeric, underscore delimiter | `GOOGLE_CLOUD_PROJECT`, `GH_TOKEN` |
| **`camelCase`** | `^[a-z][a-zA-Z0-9]*$` | Initial lowercase, upper camel hump, no delimiter | `runtimeServiceAccount`, `customDomain` |
| **`PascalCase`** | `^[A-Z][a-zA-Z0-9]*$` | Initial uppercase, upper camel hump, no delimiter | `NexusAgentCore.swift`, `EntityPage.tsx` |
| **`lower_single`** | `^[a-z0-9]+$` | Flat lowercase alphanumeric, no delimiter | `cmd`, `pkg`, `docs`, `main.go` |
| **`UPPERCASE`** | `^[A-Z0-9]+$` | Flat uppercase alphanumeric, no delimiter | `README.md`, `AGENTS.md`, `LICENSE` |
| **`Qualified Dot`** | `^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)+$` | Multi-part dot-separated qualifiers | `tabula-api.delivery.json`, `defs.bzl` |

---

### 2.2 Master Layer Authority Matrix

| Architectural Layer | Canonical Casing Standard | Permitted Secondary | Hard Constraint / Rationale |
|---|---|---|---|
| **Root & Package Directories** | `kebab-case` | `lower_single` | Monorepo standard; CLI path predictability |
| **Go Package Directories** | `lower_single` or `snake_case` | None | Go package declarations forbid `-` (`package foo_bar`) |
| **Python Package Directories** | `lower_single` or `snake_case` | None | Python import statement grammar forbids `-` (`import foo_bar`) |
| **Swift / Apple Directories** | `PascalCase` | `lower_single` | Xcode and Swift Package Manager convention |
| **Go Source Files (`.go`)** | `snake_case.go` | `lower_single.go` | Go idiomatic filename standard (`*_test.go`) |
| **Python Source Files (`.py`)** | `snake_case.py` | `lower_single.py` | Python module import syntax (`*_test.py`, `test_*.py`) |
| **TypeScript UI Components (`.tsx`)** | `PascalCase.tsx` | None | React JSX component identifier standard |
| **TypeScript Libs / Utilities (`.ts`)** | `kebab-case.ts` | `lower_single.ts` | Modern TypeScript monorepo standard |
| **TypeScript UI Tests (`.test.tsx`)** | `PascalCase.test.tsx`| None | Co-located React component unit test standard |
| **TypeScript Lib Tests (`.test.ts`)** | `kebab-case.test.ts` | `lower_single.test.ts` | Co-located library unit test standard |
| **Playwright E2E Tests (`.spec.ts`)** | `kebab-case.spec.ts` | `lower_single.spec.ts` | Playwright test discovery runner convention |
| **Swift Source Files (`.swift`)** | `PascalCase.swift` | `main.swift` entrypoint | Apple Swift standard module structure |
| **Shell Scripts (`.sh`)** | `kebab-case.sh` | `<name>_test.sh` | POSIX CLI executable convention |
| **Documentation Files (`.md`)** | `kebab-case.md` | `UPPERCASE.md` (`README`, `AGENTS`) | Web/markdown routing; root governance docs |
| **Dated RFCs / Plans (`.md`)** | `YYYY-MM-DD-<kebab-title>.md` | None | Chronological sorting and indexability |
| **Tabular Data Files (`.tsv`)** | `kebab-case.tsv` | None | Monorepo data file standard (`gcp-identities.tsv`) |
| **Image & Vector Assets (`.png`, `.svg`)** | `kebab-case.png`, `kebab-case.svg` | None | Web asset URL and content delivery standard |
| **Config Filenames (YAML)** | `kebab-case.yaml` | `PascalCase.yaml` (`Pulumi`, `Chart`) | Mandate `.yaml` over `.yml` repo-wide |
| **Reusable GitHub Workflows** | `_<kebab-name>.yaml` | None | Leading underscore signals reusable callable workflow |
| **GitHub Actions Job IDs** | `kebab-case` | `lower_single` | GitHub Actions workflow schema |
| **GitHub Actions Step IDs** | `kebab-case` | `lower_single` | Workflow run step reference standard |
| **Workflow / Action Inputs & Outputs** | `kebab-case` | None | Uniform contract between workflow caller and callee |
| **Environment Variables** | `SCREAMING_SNAKE_CASE` | None | POSIX environment variable standard |
| **Internal CLI Flags (DevX, Homelab, Tools)**| `kebab-case` (`--dry-run`)| Single-letter (`-d`)| GNU/POSIX long-option standard |
| **Bazel Native Flags** | `snake_case` (`--remote_cache`)| None | Bazel CLI option parser standard |
| **Bazel Package Paths** | `//<kebab-path>` | `//<snake_package>` (Go/Python) | Bazel workspace package convention |
| **Bazel Binaries / Apps (`sh_binary`, etc.)**| `kebab-case` | Single-word verbs (`:apply`, `:up`)| CLI binary invocation target standard |
| **Bazel Go Targets (`go_library`, `go_test`)**| `snake_case` | None | Gazelle rules_go standard generation |
| **Bazel Tool Tests (`sh_test`)** | `<binary-name>_test` | None | Tool binary-to-test pairing contract |
| **Bazel Starlark (`.bzl`) Rules & Macros** | `snake_case` | `_impl` private helpers | Bazel Starlark specification |
| **Bazel Starlark Rule Attributes** | `snake_case` | None | Starlark attribute naming standard |
| **Kubernetes Resource Names** | `kebab-case` | None | RFC 1123 DNS-1123 subdomain specification |
| **Kubernetes Namespaces** | `kebab-case` | `lower_single` | Kubernetes RFC 1123 label specification |
| **Kubernetes Spec Fields & Helm Values** | `camelCase` | None | Kubernetes OpenAPI spec convention |
| **Kubernetes Annotations & Labels** | `<domain>/<kebab-name>`| `lower_single` labels | Kubernetes metadata label/annotation standard |
| **Pulumi Project Names (`Pulumi.yaml`)** | `kebab-case` | None | Cloud project & stack identifier standard |
| **Pulumi Application Stack Keys** | `camelCase` | None | TypeScript IaC program property convention |
| **Database Tables & Columns (PostgreSQL)** | `snake_case` | None | SQL standard relational identifier convention |
| **API Wire Format (JSON / REST / OpenAPI)** | `camelCase` | None | Modern web & mobile JSON API standard |

---

## 3. Directory Path Naming Standards

### 3.1 Directory Classification & Rules

```
                                DIRECTORY CASING TAXONOMY
┌────────────────────────┬───────────────────┬────────────────────────────────────────────────────────┐
│ Directory Type         │ Canonical Casing  │ Constraints & Examples                                 │
├────────────────────────┼───────────────────┼────────────────────────────────────────────────────────┤
│ Top-Level Root Dirs    │ kebab-case /      │ All root dirs must be lowercase.                       │
│                        │ lower_single      │ Compliant: mcp-slack, nexus-agent, devx, infrastructure│
│                        │                   │ Non-compliant: mcp_slack, NexusAgent                   │
├────────────────────────┼───────────────────┼────────────────────────────────────────────────────────┤
│ Package & Tool Dirs    │ kebab-case        │ All multi-word packages under tools/, packages/, etc.  │
│                        │                   │ Compliant: tools/agent-app, tools/ci-preflight         │
│                        │                   │ Non-compliant: tools/conflict_precheck, tools/gitops/appset_render │
├────────────────────────┼───────────────────┼────────────────────────────────────────────────────────┤
│ Go Library Packages    │ lower_single /    │ Directory MUST match declared Go package identifier.   │
│                        │ snake_case        │ Compliant: pulumi/library/go/pkg/cloud_build/          │
│                        │                   │ Non-compliant: pulumi/library/go/pkg/cloud-build/      │
├────────────────────────┼───────────────────┼────────────────────────────────────────────────────────┤
│ Python Packages        │ lower_single /    │ Directory MUST match importable Python package name.   │
│                        │ snake_case        │ Compliant: devx/scripts/, tools/lint_naming/           │
│                        │                   │ Non-compliant: tools/lint-naming/ (if imported as pkg) │
├────────────────────────┼───────────────────┼────────────────────────────────────────────────────────┤
│ Swift macOS Sources    │ PascalCase        │ Apple / SPM convention for source trees.               │
│                        │                   │ Compliant: nexus-agent/macos/Sources/NexusAgentCore/   │
│                        │                   │ Non-compliant: nexus-agent/macos/sources/nexus_agent/  │
├────────────────────────┼───────────────────┼────────────────────────────────────────────────────────┤
│ GitOps & K8s Trees     │ kebab-case        │ RFC 1123 compliant paths.                              │
│                        │                   │ Compliant: gitops/argocd/applications/sealed-secrets/  │
│                        │                   │ Non-compliant: gitops/argocd/applications/sealed_secrets/│
└────────────────────────┴───────────────────┴────────────────────────────────────────────────────────┘
```

### 3.2 Sibling Directory Consistency Rule
Within any single parent directory, all child directories of the same category MUST share identical casing conventions. Mixed casing among siblings is strictly prohibited.

#### Examples: Compliant vs. Non-Compliant Directory Paths

| Parent Directory | Compliant Sibling Structure | Non-Compliant Sibling Structure (VIOLATION) |
|---|---|---|
| `infrastructure/pulumi/platform/` | `dev-local/`<br>`repo-config/`<br>`zitadel-apps/` | `dev-local/`<br>`repo_config/` *(mixed snake in kebab parent)*<br>`zitadel-apps/` |
| `infrastructure/pulumi/foundation/gcp-networks/modules/` | `base_env/`<br>`dedicated_interconnect/`<br>`shared_vpc/`<br>`vpn_ha/` | `base_env/`<br>`dedicated_interconnect/`<br>`vpn-ha/` *(mixed kebab in Go module parent)*<br>`shared_vpc/` |
| `tools/` | `agent-app/`<br>`bazel-cache/`<br>`ci-preflight/`<br>`copybara/`<br>`gitops/` | `agent-app/`<br>`bazel-cache/`<br>`copybara/conflict_precheck/` *(nested snake_case package)* |

---

## 4. Source & Asset File Naming Standards

### 4.1 Go Ecosystem (`.go`)

- **Standard**: All Go source files MUST use `snake_case.go` or `lower_single.go`.
- **Test Files**: Go test files MUST append `_test.go` to the unit under test.
- **Prohibition**: Hyphens (`-`) are strictly forbidden in `.go` filenames.
- **Generated Code Exception**: Files generated by upstream SDKs (e.g. Pulumi Go SDK in `pkg/neon/sdk/neon/apiKey.go`) retain generated casing but must be quarantined within designated SDK directories.

```
Regex: ^[a-z0-9]+(_[a-z0-9]+)*(_test)?\.go$
```

#### Examples: Go Filenames
| Compliant (DO) | Non-Compliant (DON'T) | Rationale |
|---|---|---|
| `net_hubs.go` | `net-hubs.go` | Hyphen violates Go filename standard |
| `net_hubs_transitivity.go` | `net-hubs-transitivity.go` | Hyphen violates Go filename standard |
| `agent_review_test.go` | `agent-review-test.go` | Hyphen violates Go test discovery |
| `cloud_run.go` | `cloudRun.go` | CamelCase in Go source filename |

---

### 4.2 Python Ecosystem (`.py`)

- **Standard**: All Python source files MUST use `snake_case.py` or `lower_single.py`.
- **Test Files**: Python test files MUST use `test_*.py` or `*_test.py`.
- **Prohibition**: Hyphens (`-`) are strictly forbidden in Python filenames because Python treats hyphens as subtraction operators in `import` statements (`import stream-hook` produces `SyntaxError: invalid syntax`).

```
Regex: ^[a-z0-9]+(_[a-z0-9]+)*(\.py)$
```

#### Examples: Python Filenames
| Compliant (DO) | Non-Compliant (DON'T) | Rationale |
|---|---|---|
| `stream_hook.py` | `stream-hook.py` | Hyphen prevents standard Python module import |
| `migrate_to_docker.py` | `migrate-to-docker.py` | Hyphen prevents module import |
| `patch_sa.py` | `patchSA.py` | CamelCase violates PEP 8 module standard |

---

### 4.3 TypeScript & JavaScript Ecosystem (`.ts`, `.tsx`, `.js`, `.mjs`, `.cjs`)

The TypeScript/JavaScript ecosystem applies distinct rules based on artifact role:

#### 1. React & UI Components (`.tsx`)
- **Standard**: **`PascalCase.tsx`** for all React components, page definitions, layout wrappers, and provider contexts.
- **Co-located Tests**: **`PascalCase.test.tsx`** matching the exact component name.

```
Regex (Component): ^[A-Z][a-zA-Z0-9]*\.tsx$
Regex (Test): ^[A-Z][a-zA-Z0-9]*\.test\.tsx$
```

#### 2. Libraries, Services, Utilities & Standalone Modules (`.ts`)
- **Standard**: **`kebab-case.ts`** or `lower_single.ts` for all services, API clients, helpers, utility modules, and middleware.
- **Co-located Unit Tests**: **`kebab-case.test.ts`** or `lower_single.test.ts`.
- **Playwright E2E Tests**: **`kebab-case.spec.ts`** located in `tests/` directories.
- **Backstage Component Exception**: Standalone Backstage plugin implementations in `backstage/packages/` may use `camelCase.ts` (`vitruvianTheme.ts`, `githubOrgSignIn.ts`) to conform with Spotify Backstage plugin framework conventions.

```
Regex (Library): ^[a-z0-9]+(-[a-z0-9]+)*\.ts$
Regex (Unit Test): ^[a-z0-9]+(-[a-z0-9]+)*\.test\.ts$
Regex (E2E Test): ^[a-z0-9]+(-[a-z0-9]+)*\.spec\.ts$
```

#### Examples: TypeScript / JavaScript Filenames
| Component / File Role | Compliant (DO) | Non-Compliant (DON'T) |
|---|---|---|
| React Component | `EntityPage.tsx` | `entity-page.tsx`, `entity_page.tsx` |
| React Component | `AccountSettings.tsx` | `accountSettings.tsx` |
| React Component Test | `EditableSpace.test.tsx` | `space-detail.test.tsx`, `relay_landing.test.tsx` |
| Library Service | `workspace-notes.ts` | `workspace_notes.ts`, `WorkspaceNotes.ts` |
| Sync Service Test | `cross-window-sync.test.ts` | `sections_notes.test.ts`, `CrossWindowSyncService.test.ts` |
| Security Utility | `security-headers.ts` | `securityHeaders.ts`, `security_headers.ts` |
| Playwright E2E Test | `sync-convergence.spec.ts` | `sync_convergence_spec.ts` |

---

### 4.4 Swift / Apple macOS Ecosystem (`.swift`)

- **Standard**: **`PascalCase.swift`** for all Swift types, protocols, views, models, and tests.
- **Entrypoint Exception**: `main.swift` is the standard Swift CLI/Application entrypoint.

```
Regex: ^([A-Z][a-zA-Z0-9]*|main)\.swift$
```

#### Examples: Swift Filenames
| Compliant (DO) | Non-Compliant (DON'T) | Rationale |
|---|---|---|
| `NexusAgentCore.swift` | `nexus-agent-core.swift` | Apple/Swift tooling standard |
| `AppDelegate.swift` | `app_delegate.swift` | Apple/Swift tooling standard |
| `main.swift` | `Main.swift` | Standard Swift entrypoint file |

---

### 4.5 Shell Scripts (`.sh`)

- **Standard**: Executable shell scripts MUST use **`kebab-case.sh`**.
- **Co-located Bazel Tests**: Shell test scripts paired with a script target MUST append **`_test.sh`** to the base kebab-case filename (e.g. `affected-targets_test.sh`).
- **Standalone Test Suites**: Standalone test scripts not paired with a binary MUST use **`kebab-case-test.sh`** or **`kebab-case_test.sh`**.

```
Regex (Binary Script): ^[a-z0-9]+(-[a-z0-9]+)*\.sh$
Regex (Test Script): ^[a-z0-9]+(-[a-z0-9]+)*_test\.sh$
```

#### Examples: Shell Script Filenames
| Role | Compliant (DO) | Non-Compliant (DON'T) | Rationale |
|---|---|---|---|
| Operational Tool | `argocd-secret.sh` | `argocd_secret.sh` | Standardize all `tools/` on kebab-case |
| Operational Tool | `create-app.sh` | `create_app.sh` | Standardize all `tools/` on kebab-case |
| Operational Tool | `pulumi-cmd.sh` | `pulumi_cmd.sh` | Standardize all `tools/` on kebab-case |
| Operational Tool | `resolve-identity.sh` | `resolve_identity.sh` | Standardize all `tools/` on kebab-case |
| Paired Test Script | `affected-targets_test.sh` | `affected_targets_test.sh` | Retains base script name `affected-targets.sh` |
| Paired Test Script | `publish-dev-latest_test.sh` | `publish_dev_latest_test.sh` | Retains base script name `publish-dev-latest.sh` |

---

### 4.6 Documentation (`.md`)

1. **Standard Governance Documents**: Root and module entrypoints MUST use **`UPPERCASE.md`**:
   - `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `SKILL.md`, `SECURITY.md`, `FEATURES.md`, `ROADMAP.md`, `PROJECT.md`, `DISPATCH.md`, `BRIEFING.md`.
2. **Topic Documentation**: General architectural guides, standards, and runbooks MUST use **`kebab-case.md`**:
   - `monorepo-architecture.md`, `naming-conventions.md`, `break-glass-deploy-runbook.md`.
3. **Chronological RFCs & Architecture Decisions**: Time-indexed documents MUST use **`YYYY-MM-DD-<kebab-title>.md`**:
   - `2026-08-25-traefik-to-envoy-gateway-migration.md`, `2026-06-08-native-linux-node.md`.
4. **Prohibition**: Snake_case documentation filenames (`product_analysis.md`, `gap_analysis.md`) and run-together filenames (`verifierreasoningfull.md`) are strictly forbidden.

#### Examples: Documentation Filenames
| Compliant (DO) | Non-Compliant (DON'T) |
|---|---|
| `docs/standards/naming-conventions.md` | `docs/standards/naming_conventions.md` |
| `docs/architecture/monorepo-overview.md` | `docs/architecture/MonorepoOverview.md` |
| `docs/archive/gap-analysis/gap-report.md` | `docs/archive/gap-analysis/GAPREPORT.md` |
| `docs/archive/gap-analysis/verifier-reasoning-full.md` | `docs/archive/gap-analysis/verifierreasoningfull.md` |
| `tabula/docs/product/gap-analysis.md` | `tabula/docs/product/gap_analysis.md` |

---

### 4.7 Asset & Data Files

- **Tabular Data (`.tsv`)**: MUST use **`kebab-case.tsv`** (`gcp-identities.tsv`, `version-pins.tsv`, `agents.tsv`).
- **Images & Vector Graphics (`.png`, `.svg`, `.webp`)**: MUST use **`kebab-case.<ext>`** (`hero-dark.png`, `devx-k8s-proof.png`, `cloud-run-diagram.svg`).
- **Database Schema & Migrations (`.sql`)**: Hand-authored SQL scripts use **`kebab-case.sql`** or `lower_single.sql`. Tool-generated Prisma migrations retain tool timestamp format (`YYYYMMDDHHMMSS_migration_name/migration.sql`).
- **Scaffolding Templates (`.tmpl`)**: MUST mirror the target file naming standard followed by `.tmpl` (e.g. `Pulumi.yaml.tmpl`, `cloud-run.sh.tmpl`, `service_account.go.tmpl`).

---

## 5. Configuration Files, Keys & Manifests Standards

### 5.1 Configuration Filenames

1. **Mandatory `.yaml` Extension**:
   - All YAML configuration files in the monorepo MUST use the **`.yaml`** extension.
   - The **`.yml`** extension is deprecated and prohibited for all first-party files.
   - *Upstream Exception*: External tool specifications mandating `.yml` (`action.yml` for composite GitHub Actions, `mkdocs.yml` for MkDocs) are exempt.
2. **Canonical Config Filename Stems**:
   - Human-authored repo configs: **`kebab-case`** (`pnpm-workspace.yaml`, `catalog-info.yaml`, `release-please-config.json`, `osv-scanner.toml`).
   - Reusable GitHub workflows: **`_<kebab-name>.yaml`** (`_deploy-cloud-run.yaml`, `_copybara-export.yaml`).
   - Upstream ecosystem files: **`PascalCase`** (`Pulumi.yaml`, `Chart.yaml`, `Cargo.toml`, `Gemfile`) or **`ALL_CAPS`** (`BUILD`, `MODULE.bazel`).

#### Examples: Config Filenames
| Compliant (DO) | Non-Compliant (DON'T) | Rationale |
|---|---|---|
| `.github/workflows/apps-release.yaml` | `.github/workflows/apps-release.yml` | Standardize all workflows on `.yaml` |
| `.github/workflows/tabula-release.yaml` | `.github/workflows/tabula-release.yml` | Standardize all workflows on `.yaml` |
| `gazelle-python.yaml` | `gazelle_python.yaml` | Standardize repo config on kebab-case |
| `maven-install.json` | `maven_install.json` | Standardize tool config on kebab-case |
| `tabula/extension/src/build-info.json` | `tabula/extension/src/build_info.json` | Standardize JSON manifests on kebab-case |

---

### 5.2 GitHub Actions Workflows & Actions

```yaml
# Authoritative GitHub Actions Casing Specification
name: "CI Pipeline"                         # Title Case

on:
  workflow_call:
    inputs:
      app-name:                             # MUST be kebab-case
        type: string
        required: true
      image-digest:                         # MUST be kebab-case
        type: string
        required: false
    outputs:
      affected-targets:                     # MUST be kebab-case
        value: ${{ jobs.build.outputs.affected-targets }}

jobs:
  build-and-test:                           # MUST be kebab-case
    runs-on: ubuntu-latest
    env:
      GOOGLE_CLOUD_PROJECT: vitruvian-prod  # MUST be SCREAMING_SNAKE_CASE
      GH_TOKEN: ${{ secrets.GH_TOKEN }}     # MUST be SCREAMING_SNAKE_CASE
    steps:
      - name: Checkout Repository           # Descriptive Title Case
        uses: actions/checkout@v4

      - name: Restore Bazel Cache
        id: bazel-cache                     # MUST be kebab-case
        uses: ./.github/actions/bazel-cache
        with:
          cache-prefix: ci-main             # MUST be kebab-case
```

#### GitHub Actions Syntax Rules Summary:
- **Job IDs (`jobs.<id>`)**: MUST be **`kebab-case`** (`build-and-test`, `deploy-cloud-run`, `lint-naming`).
- **Step IDs (`steps.<id>`)**: MUST be **`kebab-case`** (`bazel-cache`, `app-token`, `set-matrix`).
- **Step Names (`name:`)**: MUST be clear, human-readable Title Case description strings.
- **Environment Variables (`env.<KEY>`)**: MUST be **`SCREAMING_SNAKE_CASE`** (`GH_TOKEN`, `GOOGLE_CLOUD_PROJECT`).
- **Workflow Inputs (`inputs.<key>`)**: MUST be **`kebab-case`** (`app-name`, `working-directory`, `business-unit`, `image-digest`). Snake_case inputs are prohibited.
- **Workflow & Action Outputs (`outputs.<key>`)**: MUST be **`kebab-case`** (`affected-targets`, `access-token`, `exit-code`, `image-digest`). Snake_case outputs are prohibited.

---

### 5.3 Kubernetes, ArgoCD & GitOps Manifests

1. **Resource Names (`metadata.name`)**: MUST strictly follow **`kebab-case`** conforming to RFC 1123 DNS subdomain format:
   - Regex: `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
   - Underscores (`_`) are strictly forbidden by Kubernetes core validation schemas.
2. **Namespaces (`metadata.namespace`)**: MUST be **`kebab-case`** or `lower_single` (`argocd`, `cert-manager`, `kube-system`).
3. **Annotations**: MUST use domain-prefixed **`kebab-case`**:
   - `vitruvian.dev/release-model: continuous`
   - `vitruvian.dev/deploy-workflow: _deploy-cloud-run.yaml`
   - `argocd.argoproj.io/sync-wave: "5"`
   - `backstage.io/techdocs-ref: dir:.`
4. **Labels**: MUST use `lower_single` or domain-prefixed **`kebab-case`**:
   - `environment: production`
   - `app.kubernetes.io/name: tabula-api`
   - `app.kubernetes.io/part-of: vitruvian-core`
5. **Resource Specifications & Custom Helm Values**: MUST use **`camelCase`** matching Kubernetes OpenAPI schema specifications:
   - `serviceAccountName`, `imagePullPolicy`, `replicaCount`, `podAnnotations`, `securityContext`.

---

### 5.4 Pulumi Infrastructure Definitions

#### 1. Pulumi Project Names (`Pulumi.yaml` `name:` field)
All Pulumi projects across both foundation and application layers MUST use **`kebab-case`**. The legacy `pulumi_` snake_case prefix is deprecated and prohibited.

| Application / Layer | Canonical Pulumi Project Name | Prohibited Legacy Pattern |
|---|---|---|
| Tabula Application | `tabula-app` | `pulumi_tabula_app` |
| Tabula Web Frontend | `tabula-web` | `pulumi_tabula_web` |
| Tabula Database / Data | `tabula-data` | `pulumi_tabula_data` |
| Tabula Build Pipeline | `tabula-build` | `pulumi_tabula_build` |
| Tabula Deploy Identity | `tabula-deploy-identity` | `pulumi_tabula_deploy_identity` |
| OAuth User Inspector App | `oauth-user-inspector-app` | `pulumi_oauth_user_inspector` |
| Repository Config Platform | `repo-config` | `repo_config`, `vitruvian-core-repo-config` |
| Zitadel Applications | `zitadel-apps` | `pulumi_zitadel_apps` |
| Foundation Bootstrap | `foundation-bootstrap` | `foundation_bootstrap` |

#### 2. Stack Configuration Keys (`Pulumi.<stack>.yaml`)
Stack configurations format keys as `<namespace>:<property>`.
- **Application Stacks (TypeScript)**: MUST use **`camelCase`** for all custom properties:
  - `tabula-app:runtimeServiceAccount: sa-tabula@...`
  - `tabula-app:customDomain: tabula.vitruvian.dev`
  - `tabula-app:apiUrl: https://api.tabula.vitruvian.dev`
  - `tabula-app:bootstrapStack: ipv1337/foundation-bootstrap/production`
  - `tabula-app:projectsStack: ipv1337/foundation-projects-bu2-development/production`
- **Provider Namespaces**: Retain provider standard lowercase/snake (`gcp:project`, `gcp:region`).
- **In-File Casing Prohibition**: Mixing `snake_case` stack reference keys (`bootstrap_stack`) with `camelCase` keys (`domainVerificationAnchor`) within the same stack configuration is strictly prohibited.

---

### 5.5 Tool Configurations & Schemas

| Configuration File | Schema Authority | Key Casing Standard | Notes & Isolation |
|---|---|---|---|
| `tools/initializer/config.json` | Internal Vitruvian | **`snake_case`** | Internal tool schema: standardize all keys (`template_suffix`, `deploy_targets`, `applies_to`) |
| `devx.yaml` | Internal DevX CLI | **`snake_case`** | Internal tool schema: standardize all keys (`grafana_url`, `custom_actions`, `depends_on`) |
| `*.delivery.json` | Internal Delivery Engine | **`snake_case`** | Target metadata: `build_context`, `image_digest_output`, `workflow_inputs` |
| `renovate.json5` | Upstream Renovate | **`camelCase`** | Third-party schema enforced: `enabledManagers`, `packageRules` |
| `release-please-config.json` | Google Release Please | **`kebab-case`** | Third-party schema enforced: `release-type`, `bump-minor-pre-major` |
| `.github/dependabot.yml` | GitHub Dependabot | **`kebab-case`** | Third-party schema enforced: `package-ecosystem`, `open-pull-requests-limit` |
| `osv-scanner.toml` | Google OSV Scanner | **`PascalCase`** headers, **`camelCase`** keys | Third-party schema enforced: `[[IgnoredVulns]]`, `ignoreUntil` |
| `catalog-info.yaml` | Spotify Backstage | **`camelCase`** / `lower_single` | Backstage entity schema enforced: `apiVersion`, `metadata`, `spec` |

---

## 6. Bazel Build Graph Naming Standards

### 6.1 Bazel Package & Target Naming Matrix

```
                                BAZEL TARGET NAMING CONVENTIONS
┌──────────────────────┬──────────────────────┬────────────────────────────────────────────────────────┐
│ Rule Type            │ Target Naming Rule   │ Compliant Target Examples                              │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ go_library           │ snake_case           │ :devx_lib, :homelab_lib, :agent, :config               │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ go_binary            │ snake_case /         │ :devx, :homelab, :agent-app, :orchestrate              │
│                      │ kebab-case (tools)   │                                                        │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ go_test              │ snake_case (_test)   │ :agent_test, :config_test, :sync_test                  │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ sh_binary            │ kebab-case /         │ :agent-keys-pull, :cloud-run, :apply, :status, :tidy   │
│                      │ single-word verbs    │                                                        │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ sh_test              │ <binary-name>_test   │ :ci-preflight_test, :agent-app_test, :cloud-bootstrap_test│
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ ts_project           │ snake_case /         │ :lib, :tests_lib, :tools_lib, :mcp-slack               │
│                      │ kebab-case           │                                                        │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ js_binary            │ snake_case           │ :tabcli, :api_bin, :migrate_deploy_bin                 │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ jest_test            │ snake_case           │ :unit_tests, :jest_suite                               │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ swift_library        │ PascalCase           │ :NexusAgentCore, :NexusAgentLib                        │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ swift_test           │ PascalCase           │ :NexusAgentTests                                       │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ macos_application    │ PascalCase           │ :NexusAgent                                            │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ delivery             │ kebab-case           │ :oauth-user-inspector, :tabula-api                     │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ gitops_manifest      │ kebab-case           │ :opentelemetry-collector, :sealed-secrets              │
├──────────────────────┼──────────────────────┼────────────────────────────────────────────────────────┤
│ pulumi_project       │ Environment / Subdir │ :development, :production, :repo-config                │
└──────────────────────┴──────────────────────┴────────────────────────────────────────────────────────┘
```

---

### 6.2 The Shell Test (`sh_test`) Standardization Contract

To resolve the monorepo split between Group A (`:ci-preflight_test`) and Group B (`:agent_app_test`), the monorepo standardizes on the **`<binary-name>_test`** contract:
- The base binary or package name is preserved in its canonical form (typically `kebab-case` for tools).
- The standard Bazel test suffix `_test` is appended.

#### Canonical Tool Target Declarations:
```python
# In tools/agent-app/BUILD.bazel
sh_binary(
    name = "agent-app",
    srcs = ["agent-app.sh"],
)

sh_test(
    name = "agent-app_test",      # COMPLIANT: pairs directly with :agent-app
    srcs = ["agent-app_test.sh"],
    data = [":agent-app"],
)
```

| Tool Subsystem | Canonical Binary Target | Canonical Test Target | Prohibited Legacy Target |
|---|---|---|---|
| `//tools/agent-app` | `:agent-app` | `:agent-app_test` | `:agent_app_test` |
| `//tools/cloud-bootstrap` | `:cloud-bootstrap` | `:cloud-bootstrap_test` | `:cloud_bootstrap_test` |
| `//tools/gcp-token` | `:gcp-token` | `:gcp-token_test` | `:gcp_token_test` |
| `//tools/gcp-secrets` | `:seed`, `:status` | `:gcp-secrets_test` | `:gcp_secrets_test` |
| `//tools/saas-cli` | `:neon`, `:upstash` | `:saas-cli_test` | `:saas_cli_test` |
| `//tools/ci-preflight` | `:ci-preflight` | `:ci-preflight_test` | `:ci_preflight_test` |
| `//tools/pipeline-status` | `:pipeline-status` | `:pipeline-status_test` | `:pipeline_status_test` |

---

### 6.3 Starlark (`.bzl`) Rules, Macros & Attribute Names

1. **Rule & Macro Names**: MUST be **`snake_case`** (`cloud_run_deploy`, `gitops_manifest`, `pulumi_project`, `go_image`, `node_image`, `py3_image`).
2. **Private Helper Functions**: MUST be **`snake_case`** with a leading underscore (`_impl`, `_addlicense_launcher_impl`).
3. **Rule Attributes & Macro Parameters**: MUST be **`snake_case`** (`build_context`, `image_repository_path`, `pulumi_dir`, `smoke_path`, `env_prefix`).
4. **Intermediate Generated Subtargets**:
   - Layer / archive subtargets: append `snake_case` suffix (`<name>_layers`, `<name>_image`, `<name>_app_layer`).
   - Action / metadata subtargets: append dot-qualified suffix (`<name>.delivery`, `<name>.load`, `<name>.test`).

---

### 6.4 Bazel Command-Line Flags vs. Configuration Presets

- **Bazel Built-in Flags**: MUST be **`snake_case`** (`--remote_cache`, `--test_tag_filters`, `--workspace_status_command`, `--extra_toolchains`).
- **Bazel Config Preset Names (`--config=<name>`)**: MUST be **`kebab-case`** or `lower_single`:
  - `release`, `lint`, `e2e`, `race`, `ci`, `debug`, `remote`, `macos-app`, `remotecache-ci`.

---

## 7. Environment Variables & CLI Flags Standards

### 7.1 Environment Variables

All environment variables across Go, TypeScript, Python, Shell, Dockerfiles, and GitHub Actions MUST strictly use **`SCREAMING_SNAKE_CASE`**.

```
Regex: ^[A-Z0-9]+(_[A-Z0-9]+)*$
```

#### Canonical Monorepo Namespaces & Variable Standardization:

| Namespace / Category | Canonical Variable Name | Prohibited Aliases / Drift | Canonical Definition & Scope |
|---|---|---|---|
| **Google Cloud Project** | `GOOGLE_CLOUD_PROJECT` | `GCP_PROJECT`, `GCP_PROJECT_ID`, `GOOGLE_PROJECT`, `CLOUDSDK_CORE_PROJECT` | Canonical GCP Project ID standard across all apps, tools, and IaC |
| **Google Cloud Region** | `GOOGLE_CLOUD_REGION` | `GCP_REGION`, `CLOUDSDK_CORE_REGION` | Canonical GCP deployment region |
| **Google Cloud Access Token** | `GOOGLE_OAUTH_ACCESS_TOKEN` | `CLOUDSDK_AUTH_ACCESS_TOKEN` | Short-lived OAuth access token for Pulumi and GCP APIs |
| **GitHub Access Token** | `GH_TOKEN` / `GITHUB_TOKEN` | `GIT_TOKEN`, `GH_AUTH_TOKEN` | `GH_TOKEN` for CLI/Agent tools; `GITHUB_TOKEN` for Actions runners |
| **Cloudflare API Token** | `CLOUDFLARE_API_TOKEN` | `CF_API_TOKEN` | Canonical Cloudflare account API credential |
| **Cloudflare Tunnel Token** | `CF_TUNNEL_TOKEN` | `CLOUDFLARE_TUNNEL_TOKEN` | Argo tunnel credential token |
| **Bitwarden Vault** | `BW_SESSION`, `BW_PASSWORD` | `VAULT_SESSION` | Raw Bitwarden CLI vault credentials |
| **DevX Orchestrator** | `DEVX_CONFIG_DIR`, `DEVX_SYNC_SSH_KEY` | `DEVXCONFIG` | DevX orchestrator configuration overrides |
| **Vitruvian Platform** | `VITRUVIAN_PROFILE`, `VITRUVIAN_CLOUD_KEY` | `VITRUVIANKEY` | Monorepo platform profile settings |
| **Delivery Engine** | `DELIVERY_ORCHESTRATOR_ENABLED` | `DELIVERYORCHESTRATOR` | Monorepo continuous delivery engine switch |

#### Runtime-Injected Exceptions:
- `npm_package_version`: Injected by npm/pnpm into Node.js processes. Must be wrapped in application constant `APP_VERSION` and not propagated into shell environments.
- `__NEXT_*`: Internal runtime variables injected by Next.js engine.
- `K_SERVICE`, `K_REVISION`, `K_CONFIGURATION`: Cloud Run container runtime variables injected by Google Cloud.

---

### 7.2 CLI Flags & Options

All multi-word command-line flags and options across DevX CLI, Homelab CLI, repo tools, and shell wrappers MUST strictly use **`kebab-case`** with double-hyphen prefix.

```
Regex: ^--[a-z0-9]+(-[a-z0-9]+)*$
```

#### Examples: CLI Flags
| Subsystem | Compliant Flag (DO) | Non-Compliant Flag (DON'T) | Rationale |
|---|---|---|---|
| DevX Cobra CLI | `--dry-run`, `--skip-preflight`, `--ci-timeout`, `--basic-auth` | `--dry_run`, `--skipPreflight`, `--ciTimeout` | Long-option GNU/POSIX standard |
| Homelab CLI | `--auto-install`, `--config-file` | `--auto_install`, `--configFile` | Long-option GNU/POSIX standard |
| Cloud Run Wrapper | `--service`, `--env-prefix`, `--pulumi-dir`, `--smoke-path` | `--env_prefix`, `--pulumi_dir`, `--smokePath` | Tool wrapper flag consistency |
| Doctor Tool | `--data-file`, `--header-name`, `--no-ci` | `--data_file`, `--headerName` | Tool wrapper flag consistency |

---

## 8. Cross-Language Serialization & Interface Contracts

### 8.1 The Three-Tier Serialization Model

When data passes across database, application, wire, and environment layers, identifiers MUST be transformed according to this authoritative mapping model:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        THREE-TIER SERIALIZATION MAPPING MODEL                          │
├──────────────────────────┬─────────────────────────────┬───────────────────────────────┤
│ Architectural Layer      │ Canonical Casing Standard   │ Representative Identifiers    │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ 1. Database Persistence  │ snake_case                  │ users, password_hash,         │
│    (PostgreSQL / SQL)    │                             │ created_at, space_user_id     │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ 2. API Wire & Transport  │ camelCase                   │ userId, passwordHash,         │
│    (JSON / REST / TS DTO)│                             │ createdAt, spaceUserId        │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ 3. Environment & Config  │ SCREAMING_SNAKE_CASE        │ DATABASE_URL, JWT_SECRET,     │
│    (OS Process / Env)    │                             │ AUTH_POSTMESSAGE_ORIGIN       │
└──────────────────────────┴─────────────────────────────┴───────────────────────────────┘
```

---

### 8.2 Boundary Translation Implementations

#### 1. Prisma ORM (TypeScript ↔ PostgreSQL)
In `schema.prisma`, Prisma model fields MUST use `camelCase` mapped explicitly to `snake_case` database columns via `@map`:

```prisma
model User {
  id           String    @id @default(uuid())
  email        String    @unique
  passwordHash String    @map("password_hash")
  createdAt    DateTime  @default(now()) @map("created_at")
  updatedAt    DateTime  @updatedAt @map("updated_at")

  @@map("users")
}

model SpaceCollaborator {
  id        String   @id @default(uuid())
  spaceId   String   @map("space_id")
  userId    String   @map("user_id")
  createdAt DateTime @default(now()) @map("created_at")

  @@unique([spaceId, userId], name: "uq_space_user")
  @@map("space_collaborators")
}
```

#### 2. Go Structs (Go Runtime ↔ SQL Database ↔ JSON API)
Go models interfacing between relational storage and JSON APIs MUST provide explicit struct tags for both boundaries:

```go
type UserAccount struct {
    UserID       string    `db:"user_id"       json:"userId"`
    EmailAddress string    `db:"email_address" json:"emailAddress"`
    PasswordHash string    `db:"password_hash" json:"-"`
    CreatedAt    time.Time `db:"created_at"    json:"createdAt"`
}
```

#### 3. Python Pydantic Models (Python Runtime ↔ JSON API)
Python models interfacing with JSON APIs MUST use `snake_case` Python attributes aliased to `camelCase` wire fields:

```python
from pydantic import BaseModel, Field

class UserResponse(BaseModel):
    user_id: str = Field(alias="userId")
    email_address: str = Field(alias="emailAddress")
    created_at: str = Field(alias="createdAt")

    class Config:
        populate_by_name = True
```

---

## 9. Compound Words & Acronyms Standardization Guide

### 9.1 Compound Words Dictionary

In software naming, developers often inconsistently split or hyphenate compound English words. In `vitruvian-core`, compound words are standardized as either **closed compounds** (single unified word) or **hyphenated/delimited multi-words**.

| Term Category | Canonical Monorepo Word Form | Prohibited Split / Inconsistent Forms |
|---|---|---|
| Build & Tooling | `codebase` | `code-base`, `code_base` |
| Build & Tooling | `toolchain` | `tool-chain`, `tool_chain` |
| Build & Tooling | `filename` | `file-name`, `file_name` |
| Build & Tooling | `filepath` | `file-path`, `file_path` |
| Build & Tooling | `preflight` | `pre-flight`, `pre_flight` |
| Build & Tooling | `runbook` | `run-book`, `run_book` |
| Build & Tooling | `worktree` | `work-tree`, `work_tree` |
| Build & Tooling | `workspace` | `work-space`, `work_space` |
| Infrastructure | `namespace` | `name-space`, `name_space` |
| Infrastructure | `homelab` | `home-lab`, `home_lab` |
| Infrastructure | `devcontainer` | `dev-container`, `dev_container` |
| Platform & Web | `metadata` | `meta-data`, `meta_data` |
| Platform & Web | `allowlist` | `allow-list`, `whitelist` |
| Platform & Web | `denylist` | `deny-list`, `blacklist` |
| Platform & Web | `webhook` | `web-hook`, `web_hook` |
| Platform & Web | `postmessage` | `post-message`, `post_message` |

---

### 9.2 Standard Abbreviation Glossary

To prevent conflicting abbreviations across subpackages, the monorepo establishes standard short forms:

| Concept | Canonical Standard Abbreviation | Prohibited Conflicting Abbreviations |
|---|---|---|
| Configuration | `config` | `cfg`, `conf`, `cnfg` |
| Environment | `env` | `environ`, `environment` (in short names) |
| Directory | `dir` | `directory`, `folder` (in code identifiers) |
| Package | `pkg` | `pack`, `package` (in short names) |
| Command | `cmd` | `command`, `comm` |
| Temporary | `tmp` | `temp` (standardize on `tmp`) |
| Source | `src` | `source` (in path abbreviations) |
| Destination | `dst` | `dest`, `destination` |
| Repository | `repo` | `repository` (in short names) |
| Documentation | `docs` | `doc`, `document` |
| Message | `msg` | `message` (in short names) |
| Parameter | `param` | `parameter` (in short names) |
| Error | `err` | `error` (in short names) |
| Identifier | `id` | `ident`, `identifier` |
| Service Account | `sa` | `svc_acc`, `service_account` (in short names) |

---

### 9.3 Acronym Casing Rules Across Paradigms

Acronyms (e.g., API, HTTP, URL, GCP, OAUTH, JWT, DNS, WIF) are cased according to strict, paradigm-specific rules:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                          ACRONYM CASING RULES BY PARADIGM                              │
├──────────────────────────┬─────────────────────────────┬───────────────────────────────┤
│ Casing Paradigm          │ Acronym Rule                │ Examples                      │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ kebab-case               │ All lowercase               │ oauth-user-inspector,         │
│                          │                             │ gcp-bootstrap, api-gateway    │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ snake_case               │ All lowercase               │ oauth_user_inspector,         │
│                          │                             │ gcp_bootstrap, api_gateway    │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ SCREAMING_SNAKE_CASE     │ All uppercase               │ GOOGLE_CLOUD_PROJECT,         │
│                          │                             │ OAUTH_CLIENT_ID, API_URL      │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ camelCase (TS / JS)      │ Treat acronym as word       │ oauthUserId, apiUrl,          │
│                          │ (CamelHump style)           │ gcpProject, jwtSecret         │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ PascalCase (TS / Swift)  │ Treat acronym as word       │ OauthUserId, ApiUrl,          │
│                          │ (Initial cap only)          │ GcpProject, JwtSecret         │
├──────────────────────────┼─────────────────────────────┼───────────────────────────────┤
│ PascalCase (Go Exported) │ All uppercase (Go idiom)    │ OAuthUserID, APIURL,          │
│                          │                             │ GCPProject, JWTSecret         │
└──────────────────────────┴─────────────────────────────┴───────────────────────────────┘
```

---

### 9.4 Authoritative Monorepo Acronym Catalog

The following technical acronyms are recognized and MUST follow the rules in §9.3:

`API`, `APP`, `AWS`, `CLI`, `CNPG`, `CPU`, `CRD`, `DNS`, `DOM`, `EOF`, `GCP`, `GCS`, `GHA`, `GPU`, `GRPC`, `HA`, `HMAC`, `HTTP`, `HTTPS`, `IAC`, `IAM`, `ID`, `IP`, `JSON`, `JWKS`, `JWT`, `K8S`, `KMS`, `L10N`, `MCP`, `MIME`, `MTLS`, `NAT`, `NPM`, `OAUTH`, `OCI`, `OIDC`, `OSV`, `OTEL`, `PEM`, `POSIX`, `PR`, `PULL`, `RAM`, `RBAC`, `REST`, `RFC`, `RPC`, `SA`, `SAAS`, `SBOM`, `SDK`, `SHA`, `SMTP`, `SQL`, `SSH`, `SSL`, `SVPC`, `TCP`, `TLS`, `TSV`, `TTL`, `UDP`, `UI`, `UID`, `URI`, `URL`, `UUID`, `UX`, `VPC`, `VPN`, `WIF`, `XML`, `YAML`, `ZITADEL`.

---

## 10. Authoritative Exception Catalog & Technical Justifications

Every exception to the primary monorepo naming rules is cataloged below with its hard technical constraint, impacted files/patterns, and isolation boundary:

| Exception ID | Category | Impacted Files / Patterns | Hard Technical Constraint / Rationale | Isolation / Mitigation Boundary |
|---|---|---|---|---|
| **EXC-01** | Go Packages | `pulumi/library/go/pkg/*`, `infrastructure/pulumi/**/modules/*` | Go language grammar (`package <ident>`) strictly forbids `-` in package identifiers. | Isolated to Go package subdirectories. Directory name must exactly match declared Go package name. |
| **EXC-02** | Python Modules | All `.py` source files monorepo-wide | Python `import` statement grammar treats hyphens as subtraction operators (`import stream-hook` fails). | All Python modules MUST use `snake_case.py`. |
| **EXC-03** | React UI Components | `*.tsx` files across `tabula/`, `backstage/`, `packages/`, `oauth-user-inspector/` | React JSX compiler treats lowercase tags as HTML DOM nodes; components must be `PascalCase`. | Isolated to `.tsx` component definitions and co-located `.test.tsx` files. |
| **EXC-04** | Swift / Apple App | `nexus-agent/macos/**/*` | Xcode, Apple toolchains, and SPM mandate `PascalCase` module and file conventions. | Quarantined strictly within `nexus-agent/macos/`. |
| **EXC-05** | Kubernetes Metadata | All manifests in `gitops/` and app `deploy/` | Kubernetes API schema enforces RFC 1123 DNS subdomains (`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`). | Underscores strictly forbidden in all K8s metadata names and namespaces. |
| **EXC-06** | Prisma Migrations | `tabula/api/prisma/migrations/*` | Prisma engine auto-generates timestamped migration directories (`YYYYMMDDHHMMSS_name`). | Quarantined to Prisma migration directories; tool-generated artifacts are not manually renamed. |
| **EXC-07** | Upstream Config Schemas | `Pulumi.yaml`, `Chart.yaml`, `Cargo.toml`, `Gemfile`, `BUILD`, `MODULE.bazel` | Upstream CLI tools mandate specific, case-sensitive configuration filenames. | Explicitly registered as schema-mandated exceptions. |
| **EXC-08** | Tool-Imposed Config Extensions | `.github/actions/*/action.yml`, `mkdocs.yml` | GitHub Actions parser and MkDocs engine specifically require `.yml` extension. | Quarantined to composite action roots and MkDocs documentation roots. |
| **EXC-09** | Upstream Tool Config Schemas | `renovate.json5` (`camelCase`), `release-please-config.json` (`kebab-case`), `osv-scanner.toml` (`PascalCase`/`camelCase`) | Third-party validation schemas reject unaligned configuration field names. | Quarantined within each tool's dedicated configuration file. |
| **EXC-10** | Generated Pulumi SDK | `pulumi/library/go/pkg/neon/sdk/neon/*.go` | Pulumi Go code generator emits camelCase Go files (`apiKey.go`, `getProject.go`). | Quarantined to generated SDK subpackages. |
| **EXC-11** | Runtime-Injected Env Vars | `npm_package_version`, `__NEXT_*`, `K_SERVICE`, `K_REVISION`, `K_CONFIGURATION` | Runtime container / framework engines inject non-standard environment variables. | Quarantined; wrapped in standard application constants (e.g. `APP_VERSION`). |

---

## 11. Machine-Readable Validation Contract (For M3 & M5)

This section defines the exact regular expression rules, exclusion lists, and exit code specifications for automated enforcement tooling (`tools/lint-naming`) and CI test suites:

### 11.1 Regular Expression Validation Rules

```python
# Authoritative Validation Rules for tools/lint-naming
RULES = {
    # 1. Directory Names (Default)
    "RULE_DIR_KEBAB": {
        "pattern": r"^[a-z0-9]+(-[a-z0-9]+)*$",
        "applies_to": "directories",
        "description": "Directory names must be lowercase kebab-case or single-word.",
    },
    # 2. Go Package Directories Override
    "RULE_DIR_GO_PKG": {
        "pattern": r"^[a-z0-9]+(_[a-z0-9]+)*$",
        "applies_to": "directories_under_go_packages",
        "description": "Go package directories must be snake_case or single-word.",
    },
    # 3. Go Source Files
    "RULE_FILE_GO": {
        "pattern": r"^[a-z0-9]+(_[a-z0-9]+)*(_test)?\.go$",
        "applies_to": "*.go",
        "description": "Go source files must be snake_case.go or lower_single.go.",
    },
    # 4. Python Source Files
    "RULE_FILE_PY": {
        "pattern": r"^[a-z0-9]+(_[a-z0-9]+)*\.py$",
        "applies_to": "*.py",
        "description": "Python source files must be snake_case.py or lower_single.py.",
    },
    # 5. React TSX Components
    "RULE_FILE_TSX": {
        "pattern": r"^[A-Z][a-zA-Z0-9]*(\.test)?\.tsx$",
        "applies_to": "*.tsx",
        "description": "React TSX components and tests must be PascalCase.",
    },
    # 6. TypeScript Library Files
    "RULE_FILE_TS": {
        "pattern": r"^[a-z0-9]+(-[a-z0-9]+)*(\.(test|spec))?\.ts$",
        "applies_to": "*.ts",
        "description": "TypeScript libraries and tests must be kebab-case.ts.",
    },
    # 7. Shell Scripts
    "RULE_FILE_SH": {
        "pattern": r"^[a-z0-9]+(-[a-z0-9]+)*(_test)?\.sh$",
        "applies_to": "*.sh",
        "description": "Shell scripts must be kebab-case.sh with _test.sh for tests.",
    },
    # 8. Documentation Files
    "RULE_FILE_MD": {
        "pattern": r"^([A-Z0-9_-]+\.md|[a-z0-9]+(-[a-z0-9]+)*\.md|\d{4}-\d{2}-\d{2}-[a-z0-9-]+[a-z0-9]\.md)$",
        "applies_to": "*.md",
        "description": "Markdown docs must be UPPERCASE.md, kebab-case.md, or YYYY-MM-DD-title.md.",
    },
    # 9. YAML Configurations
    "RULE_FILE_YAML_EXT": {
        "pattern": r"^.*\.yaml$",
        "applies_to": "all_yaml_files",
        "description": "YAML configuration files must use .yaml extension (not .yml).",
    },
    # 10. Environment Variables
    "RULE_ENV_VAR": {
        "pattern": r"^[A-Z0-9]+(_[A-Z0-9]+)*$",
        "applies_to": "env_variable_identifiers",
        "description": "Environment variables must be SCREAMING_SNAKE_CASE.",
    },
    # 11. Internal CLI Flags
    "RULE_CLI_FLAG": {
        "pattern": r"^--[a-z0-9]+(-[a-z0-9]+)*$",
        "applies_to": "cli_flag_definitions",
        "description": "CLI flags must be kebab-case with double-hyphen prefix.",
    },
    # 12. Bazel sh_test Targets
    "RULE_BAZEL_SH_TEST": {
        "pattern": r"^[a-z0-9]+(-[a-z0-9]+)*_test$",
        "applies_to": "sh_test_target_names",
        "description": "Shell test targets must pair with binary as <binary-name>_test.",
    },
}
```

---

### 11.2 Ignore & Exemption Paths

The enforcement tool MUST ignore the following paths and generated trees:

```yaml
ignore_paths:
  - ".git/**"
  - ".agents/**"
  - "bazel-*/**"
  - "node_modules/**"
  - "dist/**"
  - "build/**"
  - "**/__tests__/**"                 # Framework specific test harness dirs
  - "tabula/api/prisma/migrations/**" # Prisma generated migration dirs
  - "pulumi/library/go/pkg/neon/sdk/**" # Upstream generated Pulumi Neon SDK
  - "backstage/packages/**"           # Backstage plugin upstream conventions
  - ".github/actions/**/action.yml"   # GHA required action manifest
  - "**/mkdocs.yml"                   # MkDocs required manifest
  - "nexus-agent/macos/**"            # Apple Swift / Xcode PascalCase tree
```

---

### 11.3 Diagnostics & Exit Code Specification

- **Exit Code 0**: Clean repository scan. Zero naming standard violations detected.
- **Exit Code 1+**: One or more naming standard violations detected.
- **Diagnostic Output Format**:
  ```
  <file_path>:<line_number>: [<RULE_ID>] <Description of violation> (Found: '<violating_identifier>', Expected: '<suggested_remediation>')
  ```

---

## 12. Verification & Governance

### 12.1 Automated CI Gate
Compliance with this specification is enforced automatically on every commit and pull request via:
```bash
bazel test //tools/lint-naming:lint-naming_test
```
Pull requests introducing naming violations will be rejected by the merge queue.

### 12.2 Proposing Changes to This Standard
Any proposed amendment to this standard requires:
1. An explicit architectural RFC in `docs/standards/`.
2. Demonstrated analysis showing impact across all monorepo language ecosystems.
3. Synchronous updates to `docs/standards/naming-conventions.md`, `tools/lint-naming/`, and all relevant test suites.
