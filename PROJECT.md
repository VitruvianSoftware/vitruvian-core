# Project: Enterprise Monorepo Scalability Overhaul

## Architecture
- **Concurrency & Blast-Radius Isolation (R1)**:
  - Decoupled state backends (GCS per-app/per-env or Pulumi Org) with object-precondition locking, eliminating account-wide HTTP 409 conflict serialization and client-side retry loops.
  - Layered architectural boundary hierarchy (:platform_tools -> :infrastructure -> :shared_packages -> :applications) enforced via compile-time Bazel aspects and ESLint boundary rules.
  - Hierarchical per-directory `OWNERS` schema and compilation engine generating GitHub CODEOWNERS and review policies.
  - Speculative parallel merge queue lanes and per-unit deployment concurrency groups.
- **Smart Pipelines & Dynamic DAGs (R2)**:
  - Multi-tier presubmit pipeline: L0 (Local/IDE) -> L1 (Graph-scoped Presubmit) -> L2 (Merge Queue Verification) -> L3 (Async Soak & Postsubmit).
  - Sub-second package reverse-dependency change-detection engine (`tools/pipeline/plan`).
  - Declarative `pipeline_unit()` Starlark macros in `tools/pipeline/defs.bzl` compiled via `tools/pipeline/gen` into dynamic GitHub Actions workflow DAGs.
  - Persona-, operation-, and application-scoped trigger filtering with synthetic status gate aggregator (`gate/all-required-passed`).
- **Enterprise Identity, Secrets & Ephemeral Environments (R3)**:
  - Workload Identity Federation (WIF) with least-privilege IAM and CEL condition scoping per application and environment, deprecating static user pinning in `gcp-identities.tsv`.
  - Modernized secrets management using GCP Secret Manager with CEL prefix conditions, External Secrets Operator (ESO) in-cluster, and Pulumi ESC dynamic injection.
  - Automated PR ephemeral preview environments across Cloud Run/Kubernetes with instant Neon Postgres copy-on-write branches, wildcard DNS/ingress, Zero-Trust access gating, and dual-mode teardown (event-driven + hourly TTL Ghost Reaper).
- **E2E Validation & Adversarial Hardening (M4)**:
  - Comprehensive 4-tier opaque-box E2E test suite + Tier 5 adversarial coverage hardening validating zero lock contention, boundary integrity, sub-second targeting, zero redundant test runs, and preview lifecycle.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Decoupled Pulumi State Backends | Per-app/per-env GCS state buckets with atomic object-precondition locks | M1 | Survey R1 |
| 2 | Removal of 409 Retry Hack | Remove client-side exponential backoff loop in `tools/pulumi/pulumi-cmd.sh` | M1 | Survey R1 |
| 3 | Architectural Package Groups & Boundary Aspect | Formal tiers (:platform_tools, :infra, :shared_packages, :apps) & Bazel boundary aspect | M1 | Survey R1 |
| 4 | Fix Package Visibility Leaks | Update `backstage/BUILD`, `packages/design-system/BUILD` to private/restricted visibilities | M1 | Survey R1 |
| 5 | Hierarchical OWNERS Engine | Per-directory `OWNERS` schema, generator in `//tools/owners`, and conformance validation | M1 | Survey R1 |
| 6 | Speculative Parallel Merge Lanes & Deploy Concurrency | Parallel merge queue train lanes and per-unit deploy concurrency groups | M1 | Survey R1 |
| 7 | Sub-Second Change Detection Engine | Package-level rdeps query engine (`tools/pipeline/plan`) executing in < 1.5s | M2 | Survey R2 |
| 8 | Declarative `pipeline_unit()` Starlark Schema | Declarative pipeline unit schema in `tools/pipeline/defs.bzl` with tags and metadata | M2 | Survey R2 |
| 9 | Dynamic DAG Pipeline Generator | `tools/pipeline/gen` rendering dynamic GitHub Actions workflow matrices and DAGs | M2 | Survey R2 |
| 10 | Multi-Tier Presubmit Pipeline (L0-L3) | Formalized L0, L1, L2, L3 execution boundaries with remote execution optimization | M2 | Survey R2 |
| 11 | Persona/Operation/App Trigger Scoping | Granular trigger filtering and synthetic status gate aggregator (`gate/all-required-passed`) | M2 | Survey R2 |
| 12 | Workload Identity Federation Migration | Deprecate `gcp-identities.tsv` user pinning; implement role-based WIF pools | M3 | Survey R3 |
| 13 | Least-Privilege IAM with CEL Conditions | Resource-prefix scoped CEL IAM policies per application and environment | M3 | Survey R3 |
| 14 | Enterprise Secrets Architecture | GCP Secret Manager integration, ESO in-cluster sync, and Pulumi ESC OIDC injection | M3 | Survey R3 |
| 15 | Automated PR Ephemeral Previews | Cloud Run / K8s ephemeral preview engine with instant Neon copy-on-write branching | M3 | Survey R3 |
| 16 | Ephemeral Teardown & Ghost Reaper | Event-driven PR teardown action + hourly TTL Ghost Reaper cron (`tools/ci/preview-reaper.sh`) | M3 | Survey R3 |
| 17 | E2E Concurrency & Blast-Radius Suite | Tier 1-4 tests verifying concurrent IaC execution, boundary aspects, OWNERS checks | M4 | E2E Track |
| 18 | E2E Smart Pipelines & Trigger Suite | Tier 1-4 tests verifying sub-second targeting, zero redundant runs, DAG generator | M4 | E2E Track |
| 19 | E2E Identity & Ephemeral Lifecycle Suite | Tier 1-4 tests verifying WIF authentication, CEL policies, preview lifecycle & reaper | M4 | E2E Track |
| 20 | Adversarial Coverage Hardening (Tier 5) | White-box challenger gap analysis and adversarial stress testing | M4 | E2E Track |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1_Concurrency_Isolation | Decoupled Pulumi state, boundary aspects, visibility fixes, OWNERS engine, deploy concurrency | none | DONE |
| 2 | M2_Smart_Pipelines | Sub-second change detection, `pipeline_unit()` schema, DAG generator, multi-tier CI, gate aggregator | none | DONE |
| 3 | M3_Identity_Secrets_Previews | WIF migration, least-privilege CEL IAM, ESO/ESC secrets, PR ephemeral previews & ghost reaper | none | DONE |
| 4 | M4_E2E_Acceptance_Hardening | Comprehensive Tiers 1-4 E2E verification + Tier 5 adversarial coverage hardening | M1, M2, M3 | DONE |

## Interface Contracts
### Boundary Aspect (`tools/lint/boundaries.bzl`)
- Tags: `@layer:platform_tools`, `@layer:infra`, `@layer:shared_packages`, `@layer:apps`
- Invariant: A target in layer $L_i$ can only depend on targets in layer $L_j$ where $j \le i$. Targets in `:apps` cannot depend on other `:apps` targets.

### Pipeline Units (`tools/pipeline/defs.bzl`) ↔ Dynamic CI Generator (`tools/pipeline/gen`)
- Contract: Each `pipeline_unit` emits `<name>.pipeline.json` with schema `{schema: 1, name, package, test_targets, tier, runner, persona, concurrency_group}` tagged `pipeline`.
- CI Generator queries `attr(tags, "pipeline", //...)` and produces dynamic matrix and DAG in `.github/workflows/ci.yaml`.
- Gate Aggregator: `gate/all-required-passed` status context emitted on all PR and merge queue events.

### Identity & WIF ↔ Deploy Units (`tools/delivery/defs.bzl`)
- Principal Set format: `principalSet://iam.googleapis.com/projects/<PROJECT_NUM>/locations/global/workloadIdentityPools/<POOL>/attribute.environment/<APP>-<ENV>`
- Service Account naming: `sa-<app>-deploy-<env>@prj-<env>-<bu>-<app>-<hash>.iam.gserviceaccount.com`

### Ephemeral Preview Engine ↔ Ingress / State
- Preview Hostname: `pr-<pr_number>.<app>.preview.vitruviansoftware.dev`
- Neon Branch: `tabula-pr-<pr_number>`
- Teardown: `pull_request: [closed]` and `tools/ci/preview-reaper.sh` (TTL: 24h).

## Code Layout
- `tools/boundaries/` — Architectural package groups and boundary definitions
- `tools/lint/boundaries.bzl` — Bazel compile-time architectural boundary aspect
- `tools/owners/` — Hierarchical OWNERS schema, validation, and CODEOWNERS compiler
- `tools/pulumi/` — Pulumi runner wrapper and state backend configuration
- `tools/pipeline/` — Declarative `pipeline_unit()` definitions, generator, and sub-second change detection
- `infrastructure/pulumi/foundation/gcp-bootstrap/` — WIF pool configurations and IAM bindings
- `infrastructure/pulumi/foundation/gcp-projects/modules/app_deploy_identity/` — App deploy service accounts and CEL policies
- `tools/preview/` — Ephemeral preview provisioning, Neon branch automation, and Ghost Reaper
- `tools/ci/` — Gate reporter, preview reaper, and CI orchestration scripts
- `tests/e2e/` — Opaque-box E2E test suite and adversarial validation harness
