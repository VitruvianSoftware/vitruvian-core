# Foundation Pulumi Port — Structural Faithfulness Assessment

**Date:** 2026-07-11 · **Reference:** `terraform-google-modules/terraform-example-foundation` (upstream)

## Why

The Pulumi port of Google's `terraform-example-foundation` reproduces the *behaviour* of each
stage but diverged badly from its *structure*. Upstream's readability comes from a consistent
pattern the port mostly dropped. James's call: teardown the (inactive) live foundation and
re-provision it with code that closely matches upstream, keeping `org-folders`/`fldr-foundation-1`.

## Upstream's structure (the target)

Every stage is **thin env roots + rich `modules/`**:

| upstream unit | what it is | size |
|---|---|---|
| `envs/<env>/` or `business_unit_N/<env>/` | **thin root**: `locals { environment }` + `module "x" { source = "../../modules/x" … }` + backend/remote/variables/outputs | ~40–275 lines |
| `envs/shared/` or `business_unit_N/shared/` | the **shared/singleton env** (DNS hub, infra_pipelines) | thin |
| `modules/<name>/` | the **reusable logic** | 100s–1000s of lines |

- `0-bootstrap`: single root + `modules/` (no envs — it bootstraps).
- `1-org`: `envs/shared` + `modules/{cai-monitoring, centralized-logging, network}`.
- `2-environments`: `envs/{development,nonproduction,production}` + `modules/env_baseline`.
- `3-networks-*`: `envs/{development,nonproduction,production,shared}` + `modules/{base_env, shared_vpc, hierarchical_firewall_policy, dedicated_interconnect, partner_interconnect, transitivity, vpn-ha}`.
- `4-projects`: `business_unit_1/{development,nonproduction,production,shared}` + `modules/{base_env, single_project, infra_pipelines}`.
- `5-app-infra`: `business_unit_1/{development,nonproduction,production}` + `modules/{env_base, confidential_space}`.

## Pulumi-idiomatic mapping of that structure

Terraform uses one **state per env directory**; Pulumi uses one **stack per env** inside one
project. So the faithful Pulumi port of a stage is:

```
gcp-<stage>/
├── main.go                       # THIN env-root: read env from stack config, call module(s)
├── modules/<name>/               # rich reusable logic, one dir per upstream module
├── Pulumi.development.yaml        # ┐ per-env stacks (== envs/<env>/)
├── Pulumi.nonproduction.yaml     # │
├── Pulumi.production.yaml        # ┘
└── Pulumi.shared.yaml            # == envs/shared or business_unit/shared (singletons)
```

`main.go` replaces the N per-env `envs/<env>/main.tf` roots — Pulumi dispatches by stack, so one
thin `main.go` reads `env` from config and calls the modules. Logic lives in `modules/`, matching
upstream's boundaries name-for-name.

## Current state vs target (gap per stage)

Legend: ✅ has module · ⚠️ partial/inline · ❌ monolith (logic inline in main.go + siblings)

| stage | upstream modules | our EXAMPLE | our LIVE | gap |
|---|---|---|---|---|
| **0-bootstrap** | cb-private-pool, gitlab-oidc, tfc-agent-gke, parent-iam-member, parent-iam-remove-role | ⚠️ only parent-iam-*; sa/groups/projects/build inline (main 341) | ⚠️ same, inline (1732 lines) | extract sa, groups, projects, cicd (WIF) into modules; drop N/A modules (gitlab/tfc/cb-pool) |
| **1-org** | cai-monitoring, centralized-logging, network | ✅ 3 modules **but** policies/iam/logging/scc/tags/folders/essential_contacts inline (main 478) | ✅ 3 modules, 2060 lines inline | extract org_policies, iam, scc, essential_contacts, tags, folders into modules; `envs/shared` stack |
| **2-environments** | env_baseline | ❌ none; env_baseline.go inline (main 231) | ❌ none (548 lines) | create `modules/env_baseline`; thin main; per-env stacks |
| **3-networks** | base_env, shared_vpc, hierarchical_firewall_policy, transitivity, interconnect×2, vpn-ha | ⚠️ svpc has 3 modules; hub-and-spoke has only .example (main 822) | ❌ none (1068 lines monolith) | biggest gap: extract shared_vpc, base_env, hierarchical_firewall_policy, transitivity into modules; `shared` stack for DNS hub |
| **4-projects** | base_env, single_project, infra_pipelines | ✅ base_env+single_project, has business_unit_1/; infra_pipelines + bu + cmek + peering + confidential inline (main 420) | ⚠️ base_env+single_project, business_unit.go inline (1529) | add `modules/infra_pipelines` (the app pipeline — absorbs apps/*-build + *-identity); business_unit + shared stack |
| **5-app-infra** | env_base, confidential_space | ⚠️ env_base+confidential+serverless_space, **flat main (133), no business_unit_1** | ❌ not created live | create live `gcp-app-infra`; add business_unit; serverless_space module (done) |

## Key structural corrections (beyond decomposition)

1. **The app-infra pipeline is stage 4, not stage 5.** Upstream `4-projects/modules/infra_pipelines`
   creates the per-app deploy SA + Artifact Registry + triggers. Our `apps/oauth-user-inspector-build`
   (#886) and `apps/oauth-user-inspector-deploy-identity` (#887) are that pipeline in the wrong place →
   they become `gcp-projects/modules/infra_pipelines`. `gcp-app-infra` (stage 5) is workload-only.
2. **Restore the env/business_unit layer** everywhere via per-env stacks (+ a `shared` stack for
   singletons: org, the networks DNS hub, the projects infra-pipeline).
3. **`main.go` must become thin** — read env, call modules. All current inline `.go` logic moves into
   `modules/` matching upstream names.

## Execution plan

1. **Teardown** live foundation, reverse-dep order (`gcp-projects → gcp-networks → gcp-environments →
   gcp-org → gcp-bootstrap`), **keep `org-folders`** (owns `fldr-foundation-1`). Foundation is
   inactive, so a clean teardown + fresh re-provision beats in-place URN migration.
2. **Refactor + redeploy bottom-up**, starting `gcp-bootstrap`, comparing each stage to upstream
   dir-for-dir, module-for-module. Refactor happens in the **example** (reference port) and the
   **live** tracks it (published pins + live config).
3. **Re-provision** each stage fresh under `fldr-foundation-1` as it's refactored.
4. **Stage 5** (`gcp-app-infra`) created faithfully last; finish the OSS app on it.

Per-stage detail lands in the stage's refactor PR; this doc is the map.
