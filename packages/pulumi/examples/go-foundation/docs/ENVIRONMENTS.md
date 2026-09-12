# Per-Environment Deployment Guide

This document provides environment-specific deployment instructions for the
Pulumi Go Foundation. The Go foundation mirrors the upstream Terraform
foundation's **directory-based environment separation**: every multi-environment
stage is a set of thin per-leaf Pulumi projects (`envs/<env>/` for stages 1–3,
`business_unit_1/<leaf>/` for stages 4–5), each calling the stage's shared
`modules/` package with that leaf's pinned environment identity.

## Architecture: Per-Leaf Pulumi Projects

```
0-bootstrap/                          → 1 project, 1 stack: production
1-org/envs/shared/                    → 1 leaf project, 1 stack: production
2-environments/envs/{development,nonproduction,production}/
                                      → 3 leaf projects, 1 production stack each
3-networks-*/envs/{shared,development,nonproduction,production}/
                                      → 4 leaf projects (shared = hub), 1 production stack each
4-projects/business_unit_1/{shared,development,nonproduction,production}/
                                      → 4 leaf projects (shared = infra-pipeline), 1 production stack each
5-app-infra/business_unit_1/{development,nonproduction,production}/
                                      → 3 leaf projects, 1 production stack each
```

Each leaf directory contains:

- `Pulumi.yaml` — the leaf's own Pulumi project (`foundation-<stage>-<leaf>`).
- `Pulumi.production.yaml(.example)` — the leaf's non-secret stack config.
- `main.go` (+ `config.go`) — thin root that pins the environment identity
  (e.g. `development`/`d`) and calls the shared `../../modules` package.
- `go.mod` — the leaf's own Go module.

All resource logic lives in the stage's shared `modules/` package, so the leaves
stay thin and identical in shape. Because the logic is module-shaped, the old
**one-project-multi-stack** model still works if you prefer it — point a single
project's `main.go` at the same modules and switch on `pulumi stack` — but the
reference layout (and the upstream mental model) is one leaf project per
environment with a single `production` stack.

## Environment Configuration: Development

### 3-networks (development leaf)

```bash
cd 3-networks-svpc/envs/development  # or 3-networks-hub-and-spoke/envs/development
pulumi stack init production
cp Pulumi.production.yaml.example Pulumi.production.yaml   # then edit values
pulumi config set project_id "prj-d-svpc"          # from Stage 1 output
pulumi config set parent_id "organizations/YOUR_ORG_ID"
pulumi up
```

The environment identity (`development`/`d`) is pinned in the leaf's `main.go`
— it is not a config value.

### 4-projects (development leaf)

```bash
cd 4-projects/business_unit_1/development
pulumi stack init production
cp Pulumi.production.yaml.example Pulumi.production.yaml   # then edit values
pulumi config set business_code "bu1"
pulumi config set billing_account "YOUR_BILLING_ACCOUNT_ID"
pulumi config set org_stack_name "YOUR_ORG/foundation-org-shared/production"
pulumi up
```

### 5-app-infra (development leaf)

```bash
cd 5-app-infra/business_unit_1/development
pulumi stack init production
cp Pulumi.production.yaml.example Pulumi.production.yaml   # then edit values
pulumi config set projects_stack_name "YOUR_ORG/foundation-projects-bu1-development/production"
pulumi up
```

## Environment Configuration: Non-Production

Identical to development, from the `nonproduction` leaf directory:

```bash
cd 3-networks-svpc/envs/nonproduction        # networks spoke
cd 4-projects/business_unit_1/nonproduction  # BU projects
cd 5-app-infra/business_unit_1/nonproduction # app infra
```

Each leaf gets `pulumi stack init production`, its own
`Pulumi.production.yaml`, and `pulumi up` — same commands, different leaf dir.

## Environment Configuration: Production and Shared

> **Note:** Deploy the networks **`envs/shared` leaf first** — it holds the hub
> (DNS hub / hub VPC / hierarchical firewall) that the environment spokes
> depend on. Likewise deploy `4-projects/business_unit_1/shared` (the BU
> infra-pipeline) before the 4-projects environment leaves.

```bash
# networks hub, then the production spoke
cd 3-networks-svpc/envs/shared        && pulumi stack init production && pulumi up
cd ../production                      && pulumi stack init production && pulumi up

# BU infra-pipeline, then the production projects leaf
cd 4-projects/business_unit_1/shared  && pulumi stack init production && pulumi up
cd ../production                      && pulumi stack init production && pulumi up

# production app infra
cd 5-app-infra/business_unit_1/production && pulumi stack init production && pulumi up
```

## Environment Inputs Summary

Each leaf's full configuration reference lives in its stage README. The
environment identity (`env`, `env_code`) is pinned in each leaf's `main.go`
rather than configured, so the config surface per leaf is:

### 3-networks (all environment leaves)

| Name         | Description                        | Type     | Default         | Required |
| ------------ | ---------------------------------- | -------- | --------------- | :------: |
| `project_id` | Shared VPC host project ID         | `string` | n/a             |   yes    |
| `parent_id`  | Parent scope for firewall policies | `string` | n/a             |   yes    |
| `region1`    | Primary region                     | `string` | `"us-central1"` |    no    |
| `region2`    | Secondary region                   | `string` | `"us-west1"`    |    no    |

### 4-projects (all business-unit leaves)

| Name              | Description                     | Type     | Default | Required |
| ----------------- | ------------------------------- | -------- | ------- | :------: |
| `business_code`   | Business unit code              | `string` | n/a     |   yes    |
| `billing_account` | Billing account ID              | `string` | n/a     |   yes    |
| `org_stack_name`  | Stack name of the 1-org leaf    | `string` | n/a     |   yes    |

### 5-app-infra (all business-unit leaves)

| Name                  | Description                          | Type     | Default         | Required |
| --------------------- | ------------------------------------ | -------- | --------------- | :------: |
| `projects_stack_name` | Stack name of the 4-projects leaf    | `string` | n/a             |   yes    |
| `region`              | Region for compute instances         | `string` | `"us-central1"` |    no    |

## Key Difference: Leaf Directory vs Stack

| Aspect           | Terraform                     | Pulumi TS                         | Pulumi Go                                        |
| ---------------- | ----------------------------- | --------------------------------- | ------------------------------------------------ |
| Env isolation    | `envs/development/` directory | `envs/development/` directory     | `envs/development/` leaf project                 |
| Config file      | `terraform.tfvars` per dir    | `Pulumi.development.yaml` per dir | `Pulumi.production.yaml` per leaf dir            |
| State isolation  | Backend prefix per dir        | Automatic per directory           | One `production` stack per leaf project          |
| Code duplication | Per-env `main.tf`             | Per-env `index.ts`                | Thin per-env `main.go` + **shared `modules/`**   |

The shared `modules/` package is what keeps the thin leaves honest: a leaf may
deliberately diverge (that flexibility is the point of per-leaf projects), but
by default every environment runs the same module code with a different pinned
identity.
