# Go Source File Reference

This document provides a comprehensive reference for all Go source files across
the foundation stages. It is the Go foundation's equivalent of the per-module
READMEs in the TypeScript foundation.

## 0-bootstrap (5 files, ~1,214 lines)

| File                      | Lines | Description                                                                                                               |
| ------------------------- | ----: | ------------------------------------------------------------------------------------------------------------------------- |
| `main.go`                 |  ~250 | Orchestrates bootstrap: config loading, folder creation, project/IAM coordination, WIF setup, output exports              |
| `projects.go`             |  ~200 | Creates Seed project (KMS ring, crypto key, encrypted state bucket) and CI/CD project with labels and deletion protection |
| `iam.go`                  |  ~400 | 5 granular SAs, least-privilege IAM at org/parent/seed/cicd/billing scopes, SA self-impersonation, editor removal         |
| `build_github_actions.go` |  ~200 | WIF pool, OIDC provider, per-SA repo bindings for GitHub Actions                                                          |
| `groups.go`               |  ~160 | Required and optional Cloud Identity group creation                                                                       |

**Alternative CI/CD files (not compiled by default):**

| File                               | Description                                                 |
| ---------------------------------- | ----------------------------------------------------------- |
| `build_cloud_build.go.example`     | Cloud Build provisioning (CSR, Artifact Registry, triggers) |
| `build_gitlab.go.example`          | GitLab WIF OIDC provisioning                                |
| `build_local.go.example`           | Local (no-CI) apply path                                    |
| `build_terraform_cloud.go.example` | Pulumi Cloud agent equivalent of upstream Terraform Cloud   |
| `outputs_cb.go.example` etc.       | Per-builder output exports (`cb`, `github`, `gitlab`, `terraform_cloud`; `outputs_github.go` compiled by default) |

**Builder modules (`modules/`):** `cb-private-pool` (Cloud Build private worker
pool), `gitlab-oidc` (GitLab WIF pool/provider + SA bindings), `tfc-agent-gke`
(Pulumi Cloud agent on GKE, upstream tfc-agent-gke equivalent),
`parent-iam-member`, `parent-iam-remove-role`.

## 1-org (10+ files, ~1,870 lines)

The Pulumi project root is the `envs/shared/` leaf (upstream `1-org/envs/shared`
layout); reusable pieces live in the sibling `modules/` package.

| File                                | Lines | Description                                                                                |
| ----------------------------------- | ----: | ------------------------------------------------------------------------------------------ |
| `envs/shared/main.go`               |  ~180 | Config loading, orchestration, output exports (29 outputs)                                 |
| `envs/shared/folders.go`            |   ~80 | Common, network, and 3 environment folders                                                 |
| `envs/shared/projects.go`           |  ~250 | 8+ shared projects: logging, billing-export, SCC, KMS, secrets, DNS, interconnect, network |
| `envs/shared/policies.go`           |  ~300 | 14+ boolean + list organization policies via `pkg/policy`                                  |
| `envs/shared/scc.go`                |  ~100 | SCC notification with Pub/Sub topic and subscription                                       |
| `envs/shared/tags.go`               |   ~80 | Org-level environment classification tags                                                  |
| `envs/shared/iam.go`                |  ~150 | Org admin IAM, Essential Contacts permissions                                              |
| `envs/shared/essential_contacts.go` |   ~80 | Essential Contacts notification channels                                                   |

**Shared modules (`modules/`):**

| File                                      | Description                                                         |
| ----------------------------------------- | ------------------------------------------------------------------- |
| `modules/centralized_logging/`            | Org-level sinks to Storage, Pub/Sub, BigQuery; billing log sink     |
| `modules/cai_monitoring/`                 | Cloud Asset Inventory monitoring (Cloud Function v2, feeds, topics) |
| `modules/cai_monitoring/function-source/` | Node.js Cloud Function source for CAI monitoring                    |
| `modules/network/`                        | Shared network helpers for the org projects                         |

## 2-environments (4 files, ~950 lines)

| File                                   | Lines | Description                                                            |
| -------------------------------------- | ----: | ---------------------------------------------------------------------- |
| `envs/development/main.go`             |  ~210 | Thin env root pinning development/d; config + Stack Reference to Stage 1 |
| `envs/nonproduction/main.go`           |  ~210 | Thin env root pinning nonproduction/n; config + Stack Reference to Stage 1 |
| `envs/production/main.go`              |  ~210 | Thin env root pinning production/p; config + Stack Reference to Stage 1 |
| `modules/env_baseline/env_baseline.go` |  ~320 | Per-environment KMS + Secrets project creation with labels             |

## 3-networks-svpc (6 files, ~750 lines)

| File                                    | Lines | Description                                                                                                    |
| --------------------------------------- | ----: | --------------------------------------------------------------------------------------------------------------- |
| `envs/shared/main.go`                   |   ~85 | Thin shared root pinning shared; hierarchical firewall policy                                                   |
| `envs/development/main.go` (+config.go) |  ~340 | Thin env root pinning development/d; config + exports, calls `modules/base_env`                                 |
| `envs/nonproduction/main.go` (+config.go)| ~340 | Thin env root pinning nonproduction/n; config + exports, calls `modules/base_env`                               |
| `envs/production/main.go` (+config.go)  |  ~340 | Thin env root pinning production/p; config + exports, calls `modules/base_env`                                  |
| `modules/base_env/base_env.go`          |  ~360 | Per-env network stack: SVPC host, VPC, subnets with GKE ranges, PSA, DNS, NAT, VPC-SC, restricted APIs routing |
| `modules/hierarchical_firewall_policy/` |   ~50 | Org/folder-level hierarchical firewall policy (envs/shared)                                                     |

## 3-networks-hub-and-spoke (10+ files, ~1,600 lines)

| File                                     | Lines | Description                                                                                 |
| ---------------------------------------- | ----: | -------------------------------------------------------------------------------------------- |
| `envs/shared/main.go` (+config.go)       |  ~330 | Thin shared root pinning shared/c; hub VPC, hierarchical firewall, DNS hub, transitivity     |
| `envs/development/main.go` (+config.go)  |  ~320 | Thin env root pinning development/d + spoke CIDRs; calls `modules/base_env`, exports          |
| `envs/nonproduction/main.go` (+config.go)|  ~320 | Thin env root pinning nonproduction/n + spoke CIDRs; calls `modules/base_env`, exports        |
| `envs/production/main.go` (+config.go)   |  ~320 | Thin env root pinning production/p + spoke CIDRs; calls `modules/base_env`, exports           |
| `modules/{shared_vpc,base_env,hierarchical_firewall_policy,transitivity}` | ~800 | Shared VPC (hub/spoke modes), spoke orchestrator, hierarchical firewall, transitivity gateway |

## 4-projects (11+ files, ~2,400 lines)

| File                                     | Lines | Description                                                                                    |
| ---------------------------------------- | ----: | ---------------------------------------------------------------------------------------------- |
| `business_unit_1/shared/main.go`         |  ~250 | Thin shared leaf pinning common/c; BU infra-pipeline project via `modules/infra_pipelines`     |
| `business_unit_1/development/main.go`    |  ~470 | Thin env leaf pinning development/d; Stack References, BU folder, calls `modules/base_env`     |
| `business_unit_1/nonproduction/main.go`  |  ~470 | Thin env leaf pinning nonproduction/n; Stack References, BU folder, calls `modules/base_env`   |
| `business_unit_1/production/main.go`     |  ~470 | Thin env leaf pinning production/p; Stack References, BU folder, calls `modules/base_env`      |
| `modules/base_env/base_env.go`           |  ~330 | Per-env project set (SVPC, floating, peering), labels, budgets, VPC-SC, API-propagation gating |
| `modules/base_env/peering.go`            |  ~250 | Full peering network: VPC, subnet, DNS, bi-directional peering, firewall with IAP secure tags  |
| `modules/base_env/cmek.go`               |  ~150 | KMS keyring, crypto key, GCS SA IAM (API lookup), CMEK-encrypted GCS bucket                    |
| `modules/base_env/confidential_space.go` |  ~170 | Confidential Space project, workload SA, IAM, SVPC + VPC-SC attachment                         |
| `modules/single_project/`                |  ~120 | Single-project wrapper over the project factory (gated ApisReadyProjectID)                     |
| `modules/infra_pipelines/`               |  ~340 | App-infra pipeline project (WIF model) + Cloud Build reference behind the `example` build tag  |

## 5-app-infra (6 files, ~1,150 lines)

| File                                             | Lines | Description                                                                                    |
| ------------------------------------------------ | ----: | ---------------------------------------------------------------------------------------------- |
| `business_unit_1/development/main.go`            |  ~210 | Thin env leaf pinning development/d; 4-projects Stack References, calls shared modules         |
| `business_unit_1/nonproduction/main.go`          |  ~210 | Thin env leaf pinning nonproduction/n; same shape                                              |
| `business_unit_1/production/main.go`             |  ~210 | Thin env leaf pinning production/p; same shape                                                 |
| `modules/env_base/env_base.go`                   |  ~155 | Standard Compute Instances with Service Accounts and IAP tag bindings                          |
| `modules/confidential_space/confidential_space.go` | ~200 | Confidential Space VMs, Workload Identity Pool/Provider, attestation config                    |
| `modules/serverless_space/serverless_space.go`   |  ~170 | Cloud Run service + SA + secret wiring (serverless addition to the upstream module set)        |

## Total: 33+ Go files, ~7,300 lines

## Related

- [Pulumi Library](https://github.com/VitruvianSoftware/pulumi-library/go) — Shared component library (13 Go packages)
- [TypeScript Foundation](https://github.com/VitruvianSoftware/pulumi_ts-example-foundation) — TS equivalent with 21 modules
- [Upstream Terraform](https://github.com/terraform-google-modules/terraform-example-foundation) — Reference architecture
