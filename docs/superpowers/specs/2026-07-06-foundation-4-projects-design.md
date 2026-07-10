# Design: Live foundation stage 4 (`gcp-projects`) — monorepo-native, co-tenant

**Date:** 2026-07-06
**Status:** Approved (design), pending implementation
**Worktree/branch:** `feat/foundation-gcp-projects`

## Context

We are porting Google's `terraform-example-foundation` to Pulumi/Go and running it live
under our own `vitruviansoftware.dev` GCP org, as a **co-tenant** under the
`fldr-foundation-1` umbrella folder (sibling `fldr-foundation-0` is off-limits). Stages 0–3
are already live and applied:

| Stage | Live stack | Notes |
|---|---|---|
| 0 · bootstrap | `infrastructure/pulumi/foundation/gcp-bootstrap` | seed/cicd, WIF |
| — · umbrella | `infrastructure/pulumi/foundation/org-folders` | `fldr-foundation-1` (`823326946563`) |
| 1 · org | `infrastructure/pulumi/foundation/gcp-org` | folder-scoped policies/sinks/IAM |
| 2 · environments | `infrastructure/pulumi/foundation/gcp-environments` | per-env folders + KMS/secrets |
| 3 · networks | `infrastructure/pulumi/foundation/gcp-networks` | Shared VPC host + spokes |

This spec covers **stage 4 (projects)** as a new live stack
`infrastructure/pulumi/foundation/gcp-projects/`. The reference is
`pulumi/examples/go-foundation/4-projects/` (Pulumi project `foundation-4-projects`).

### Why stage 4 is not redundant with `infrastructure/pulumi/apps/`

Every existing app stack (`apps/tabula`, `apps/oauth-user-inspector`,
`apps/oauth-user-inspector-deploy-identity`) **assumes a pre-existing GCP project** and only
creates resources *inside* it. Those target projects are **personal-account** projects
(`tabula-dev-0001`, `gen-lang-client-…` under `james.nguyen@gmail.com`) — not org-managed,
not under `fldr-foundation-1`. Nothing in the tree creates org-managed application projects or
performs Shared-VPC service-project attachment. Stage 4 fills exactly that gap.

**Seam between stage 4 and the app stacks:** stage 4 mints + wires an application project and
**exports its id**; a stage-5 / app stack later consumes that id as its `gcp:project` instead
of a hand-made personal project. Stage 4 does not deploy any app workload (that is stage 5).

## Decision: Hybrid — faithful code, one real BU, floating-only

Approved intent (of three options considered — faithful sample parity / real app onboarding /
hybrid): **Hybrid.** Port the full parametrized machinery faithfully, but the committed config
instantiates **business unit `bu1`** with **only the floating project type** enabled for now.
The Go code stays a faithful port; we simply choose what to instantiate.

- **First app** (oauth-user-inspector) is explicitly **out of scope** here — that wiring is
  stage 5. Stage 4 only produces the floating project and exports its id.
- **Floating-only** is deliberately chosen because a floating project is standalone (not
  attached to the Shared VPC), which eliminates the highest co-tenancy landmines
  (VPC-SC perimeter mutation, Shared-VPC host writes, peering CIDR overlap).

## Architecture

- **Stack:** `infrastructure/pulumi/foundation/gcp-projects/`, Pulumi project
  **`foundation-projects`**, `runtime: go`.
- **Sharding:** per-env stack trio (`development` / `nonproduction` / `production`), matching
  `gcp-environments` and `gcp-networks`. Each stack is one `(env × business_code)` cell;
  committed config sets `business_code: bu1`. Promotion order dev → nonprod → prod (dev
  auto-approves; nonprod/prod gated by GitHub Environment protection).

## Components (what a stack creates, bu1 / floating-only)

1. **BU folder** `fldr-{env}-bu1` — `organizations.NewFolder`, parented to the env folder
   (`env_folder` output from `gcp-environments`). Folder-scoped under `fldr-foundation-1`
   transitively; `folder_deletion_protection` default `true`.
2. **Floating project** `prj-{env}-bu1-floating` — created via the published
   `project_factory.NewProject` with `random_suffix` on. Includes its API enablement set, a
   `billing.Budget`, `DefaultServiceAccounts: "deprivilege"` (security hygiene), and the
   standard label set (`projectLabels`).
3. **Exports:** `bu_folder_id`, `floating_project_id`, `floating_project_number` (consumed by
   stage 5 / app stacks as `gcp:project`).

### Ported-but-OFF (toggles present in code, `false` in committed config)

Shared-VPC-attached project; peering project + its VPC/subnet/tags; confidential-space
project; VPC-SC perimeter attach; CMEK sample bucket; per-BU infra-pipeline project (our CI is
monorepo GitHub-Actions WIF, so a Cloud Build pipeline project is unneeded). The code keeps
these faithful and reachable behind config toggles; we do not instantiate them yet.
**CMEK is off** for the floating project in this first cut (can be enabled later).

## Data flow / cross-stage wiring (deliberately minimal)

Floating-only needs exactly **one** StackReference:

```
ipv1337/foundation-environments/{env}  →  env_folder   (BU-folder parent)
```

The example's org + network StackReferences (Shared-VPC host, common folder, service-perimeter)
are **gated behind the feature toggles** — created only when an attached / peering / VPC-SC
feature is enabled. This is the one intentional divergence from the example (which wires all
three unconditionally): it keeps the minimal stack depending only on stage 2 and avoids
coupling to outputs we don't consume. Everything lands under `fldr-foundation-1` transitively
via `env_folder`, so **no `parent_folder` config key is needed** — same as the example.

Reference-name convention matches siblings: logical reference name is the upstream stage
(`"environment"`); the fully-qualified `ipv1337/foundation-environments/{env}` string lives in
the config key `environments_stack_name` (with a hardcoded default à la `gcp-networks`
`config.go:195`).

## Co-tenancy

With floating-only the surface is essentially collision-free:

- BU folder is folder-scoped (under the env folder → `fldr-foundation-1`).
- One project, id-namespaced by `{project_prefix}-{env_code}-{business_code}-floating` +
  `random_suffix`.
- All other resources (budget, default-SA deprivilege, labels) are project-scoped.
- **None** of the org-authoritative landmines (VPC-SC perimeter attach, Shared-VPC host
  writes, peering) are instantiated.

## Config surface (committed, non-secret identifiers)

Namespace `foundation-projects`. Per-env `Pulumi.{development,nonproduction,production}.yaml`:

- **Required:** `env`, `business_code` (`bu1`), `billing_account`, `environments_stack_name`
  (`ipv1337/foundation-environments/{env}`). (`env_code`, e.g. `d`/`n`/`p`, is *derived* from
  `env` in the loader, as in the example — not a separate key.)
- **Co-tenancy / identity (committed, defaulted):** `org_id`, `project_prefix` (`prj`),
  `folder_prefix` (`fldr`).
- **Feature toggles (all `false` except floating):** `floating_enabled: true`;
  `svpc_enabled`, `peering_enabled`, `confidential_space_enabled`, `enforce_vpcsc`,
  `cmek_enabled`, `infra_pipeline_enabled` → `false`.
- **Project-scoped knobs:** `random_suffix` (`true`), budget settings
  (`budget_amount`, `budget_alert_percents`, `budget_spend_basis`), label fields
  (`application_name`, `billing_code`, contacts), `folder_deletion_protection` (`true`).

Secrets, if any, come from env via the existing `EnvOrConfig` pattern — never committed.

## Testing

- **Unit:** `config_test.go` (`package main`) — mock provider + `PULUMI_CONFIG` env injection,
  call the `loadProjectsConfig` loader, assert defaults (business_code, env_code, floating-only
  toggle states, budget defaults, prefixes). Mirrors the sibling stacks' single-test pattern.
- **Build gate:** `GOWORK=off go build ./...`, `go test ./...`, `go vet ./...` green in the
  worktree.
- **Preview:** `bazel run //infrastructure/pulumi/foundation/gcp-projects:preview` for the
  `development` stack shows an **all-creates** plan (BU folder + 1 floating project + budget)
  under `fldr-foundation-1`, with **zero deletes/replaces** against existing resources.
- **Apply:** user-gated (dev first, then promote), same gating as env/networks.

## Monorepo integration checklist (matches the three live siblings exactly)

1. `BUILD`: `pulumi_project(name = "gcp-projects", dir = "infrastructure/pulumi/foundation/gcp-projects")`
   + the standard "PUBLISHED modules, no replace, Pulumi Cloud (ipv1337)" header comment.
2. `Pulumi.yaml`: `name: foundation-projects`, `runtime: go`, `pulumi:template: gcp-go`, MIT header.
3. Per-env config trio, committing the non-secret co-tenancy ids above.
4. `go.mod`: `module foundation-projects`, `go 1.26.2`, published `project_factory` pin
   `v1.0.3-0.20260708022723-33a1f2fcb936` (same as org/env), `pulumi-gcp/sdk/v9 v9.29.0`,
   `pulumi/sdk/v3 v3.250.0`, `testify v1.11.1`, **no `replace`**.
5. `infrastructure/gcp-identities.tsv`: add row
   `infrastructure/pulumi/foundation/gcp-projects   james@vitruviansoftware.dev   -   Foundation Phase 4 – Projects (bu1 floating; fldr-foundation-1)`.
6. `config_test.go` as above.
7. Export the created project id(s) for stage 5 / app consumption.

## Divergences from the example (explicit)

1. **Floating-only instantiation** — only the floating project type is enabled; other project
   types and the infra-pipeline project are toggled off (code retained, faithful).
2. **Gated StackReferences** — org/network references are created only when their features are
   enabled, so the minimal stack depends solely on stage 2.
3. **Published pins, no `replace`; Pulumi Cloud backend** — same dogfooding posture as the
   three live siblings (the example uses local `replace` directives and is template-oriented).

## Out of scope

- Stage 5 (`app-infra`) and wiring oauth-user-inspector (or any app) onto the floating project.
- Enabling shared-VPC / peering / confidential-space / VPC-SC / CMEK / infra-pipeline (future
  toggles).
- Retargeting the existing `apps/` stacks off their personal-account projects (a later, stage-5
  or migration concern).
