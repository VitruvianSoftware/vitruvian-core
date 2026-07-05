# TypeScript Source File Reference

This document provides a comprehensive reference for all TypeScript source files
across the foundation stages. It is the TS foundation's equivalent of the Go
foundation's `SOURCE_FILES.md`.

## 0-bootstrap (5 files, ~771 lines)

| File | Description |
|------|-------------|
| `index.ts` | Main orchestration: config loading, folder creation, project/IAM coordination, output exports |
| `config.ts` | `BootstrapConfig` interface and `loadConfig()` — loads and validates all Pulumi config values with Terraform-parity defaults |
| `sa.ts` | 5 granular SAs with least-privilege IAM at org/parent/seed/cicd/billing scopes; `createIgnoreAlreadyExists` for pipeline resilience |
| `build_cb.ts` | CI/CD project creation with Cloud Build, Artifact Registry, and Source Repo configuration |
| `groups.ts` | Required and optional Cloud Identity group creation |

## 1-org (2 files, ~519 lines)

| File | Description |
|------|-------------|
| `index.ts` | Full org-level orchestration: folders, projects, org policies, logging sinks, SCC, tags, essential contacts, CAI monitoring |
| `config.ts` | `OrgConfig` interface and config loader with all org-level configuration |

## 2-environments (4 files, ~236 lines)

| File | Description |
|------|-------------|
| `envs/development/index.ts` | Development environment entry point — calls `deployEnvBaseline` |
| `envs/nonproduction/index.ts` | Non-production environment entry point |
| `envs/production/index.ts` | Production environment entry point |
| `modules/env_baseline.ts` | Shared module: creates environment folder, KMS project, and Secrets project via `ProjectFactory` |

## 3-networks-svpc (5 files, ~434 lines)

| File | Description |
|------|-------------|
| `envs/shared/index.ts` | Shared network resources (DNS hub, interconnect) |
| `envs/development/index.ts` | Development network entry point |
| `envs/nonproduction/index.ts` | Non-production network entry point |
| `envs/production/index.ts` | Production network entry point |
| `modules/shared_vpc.ts` | `SharedVpc` ComponentResource: VPC, subnets, firewall rules, DNS, NAT, Private Service Connect |

> **Note:** `3-networks-hub-and-spoke/` mirrors this structure with hub-and-spoke topology.

## 4-projects (5 files, ~389 lines)

| File | Description |
|------|-------------|
| `business_unit_1/shared/index.ts` | Shared BU1 projects (Secrets, Network) |
| `business_unit_1/development/index.ts` | Development BU1 projects |
| `business_unit_1/nonproduction/index.ts` | Non-production BU1 projects |
| `business_unit_1/production/index.ts` | Production BU1 projects |
| `modules/single_project.ts` | `deploySingleProject()` — creates a project with Shared VPC, VPC-SC, pipeline SA roles, and budget alerts |

## 5-app-infra (3 files, ~189 lines)

| File | Description |
|------|-------------|
| `business_unit_1/development/index.ts` | Development app infrastructure (Compute, IAM, networking) |
| `business_unit_1/nonproduction/index.ts` | Non-production app infrastructure |
| `business_unit_1/production/index.ts` | Production app infrastructure |

## Library Dependencies

The TS foundation imports the following packages from `@vitruviansoftware/pulumi-library`:

| Package | Used In |
|---------|---------|
| `pulumi-project-factory` | `2-environments`, `4-projects` |
| `pulumi-network` | `3-networks-*` |
| `pulumi-private-service-connect` | `3-networks-*` |
| `pulumi-parent-iam` | `0-bootstrap` |
| `pulumi-budget` | `4-projects` |
| `pulumi-google-group` | `0-bootstrap` |
| `pulumi-hierarchical-firewall-policy` | `3-networks-*` |
| `pulumi-dns-hub` | `3-networks-*` |
| `pulumi-kms` | `2-environments` |
| `pulumi-org-policy` | `1-org` |
| `pulumi-centralized-logging` | `1-org` |
| `pulumi-vpn-ha` | `3-networks-*` |
| `pulumi-network-peering` | `3-networks-*` |
| `pulumi-cb-private-pool` | `0-bootstrap` |
| `pulumi-instance-template` | `5-app-infra` |
| `pulumi-simple-bucket` | `0-bootstrap` |

## Test Files

| File | Tests | Description |
|------|------:|-------------|
| `test/0-bootstrap.config.test.ts` | 15 | Config defaults, parent resolution, groups config |
| `test/2-environments.config.test.ts` | 9 | Environment naming, env codes, interface contract |
| `test/3-networks.config.test.ts` | 7 | Region defaults, valid environments, SharedVpc config |
| `test/4-projects.config.test.ts` | 9 | Label generation, budget config, naming pattern |
| `test/5-app-infra.config.test.ts` | 7 | App config defaults, env codes, feature flags |
| **Total** | **47** | |
