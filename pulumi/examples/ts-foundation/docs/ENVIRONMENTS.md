# Per-Environment Deployment Guide

This document provides environment-specific deployment instructions for the
Pulumi TypeScript Foundation. The TS foundation uses **directory-based
environment separation** where each environment has its own `Pulumi.yaml`
and `index.ts` under an `envs/` subdirectory within each stage.

## Architecture: Directory-Based Environments

```
0-bootstrap/              → 1 stack:  bootstrap (shared)
1-org/                    → 1 stack:  org (shared)
2-environments/envs/
  ├── development/        → 1 stack:  development
  ├── nonproduction/      → 1 stack:  nonproduction
  └── production/         → 1 stack:  production
3-networks-svpc/envs/
  ├── shared/             → 1 stack:  shared
  ├── development/        → 1 stack:  development
  ├── nonproduction/      → 1 stack:  nonproduction
  └── production/         → 1 stack:  production
4-projects/business_unit_1/
  ├── shared/             → 1 stack:  shared
  ├── development/        → 1 stack:  development
  ├── nonproduction/      → 1 stack:  nonproduction
  └── production/         → 1 stack:  production
5-app-infra/business_unit_1/
  ├── development/        → 1 stack:  development
  ├── nonproduction/      → 1 stack:  nonproduction
  └── production/         → 1 stack:  production
```

**Total: 20 `Pulumi.yaml` files** — one per environment × stage combination.

## Key Difference from Go Foundation

The Go foundation uses **stack-based** environment separation (7 `Pulumi.yaml`
files, one per stage, with environment configured via `pulumi config set env`).
The TS foundation uses **directory-based** separation, where each environment
has its own physical directory containing a `Pulumi.yaml`, `index.ts`, and
`tsconfig.json`.

This means:
- **Go**: `cd 3-networks-svpc && pulumi stack select development && pulumi up`
- **TS**: `cd 3-networks-svpc/envs/development && pulumi up`

## Environment Configuration: Development

### 2-environments (development)

```bash
cd 2-environments/envs/development
pulumi config set org_id "YOUR_ORG_ID"
pulumi config set billing_account "AAAAAA-BBBBBB-CCCCCC"
pulumi config set parent "organizations/YOUR_ORG_ID"
pulumi up
```

### 3-networks (development)

```bash
cd 3-networks-svpc/envs/development
pulumi config set org_id "YOUR_ORG_ID"
pulumi config set project_id "prj-d-svpc"        # from Stage 2 output
pulumi config set parent "organizations/YOUR_ORG_ID"
pulumi up
```

### 4-projects (development)

```bash
cd 4-projects/business_unit_1/development
pulumi config set org_id "YOUR_ORG_ID"
pulumi config set billing_account "AAAAAA-BBBBBB-CCCCCC"
pulumi up
```

### 5-app-infra (development)

```bash
cd 5-app-infra/business_unit_1/development
pulumi config set org_id "YOUR_ORG_ID"
pulumi config set billing_account "AAAAAA-BBBBBB-CCCCCC"
pulumi up
```

## Environment Configuration: Non-Production & Production

Follow the same pattern as development, substituting the correct environment
directory:

```bash
# Non-production
cd 3-networks-svpc/envs/nonproduction && pulumi up

# Production
cd 3-networks-svpc/envs/production && pulumi up
```

## Deploying All Environments

To deploy all environments for a stage:

```bash
for env in shared development nonproduction production; do
  cd 3-networks-svpc/envs/$env
  pulumi up --yes
  cd ../../..
done
```
