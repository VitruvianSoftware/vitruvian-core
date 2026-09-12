# 3-networks-hub-and-spoke

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **Go**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

This step configures the same network resources as [3-networks-svpc](../3-networks-svpc/README.md), but uses the [Hub and Spoke](https://cloud.google.com/architecture/security-foundations/networking#hub-and-spoke) reference network model instead of the Dual Shared VPC architecture.

### Architecture

In the Hub and Spoke model:

- A **Hub VPC** is created with central routing in the network hub project
- **Spoke VPCs** are created per environment with GKE secondary ranges
- **Bidirectional VPC peering** connects each spoke to the hub with custom route export/import
- The same baseline firewall, DNS, NAT, and routing configurations from the SVPC variant are applied

### What Gets Created

For each environment:

- **Hub VPC** with central routing
- **Spoke VPC** with GKE secondary ranges (pod + service CIDRs)
- **VPC Peering** between hub and spoke with custom route exchange
- **Hierarchical Firewall Policies** (IAP, health checks, Windows KMS)
- **DNS Policy** with logging and inbound forwarding
- **Cloud NAT** on all regions with error logging
- **Private Service Access** for managed services
- **Restricted Google APIs routing** (`199.36.153.4/30`)
- **Default internet routes removed**

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.
1. [2-environments](../2-environments/README.md) executed successfully.

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Each leaf is its own thin Pulumi project under `envs/` (mirroring upstream
   `3-networks-hub-and-spoke/envs/<env>`); the environment identity and spoke
   CIDR plan are pinned in each leaf's `main.go`. Deploy the **shared/hub**
   root first — the spokes peer into the hub VPC it creates:

   ```bash
   cd 3-networks-hub-and-spoke/envs/shared
   pulumi stack init production
   pulumi config set hub_project_id "prj-net-hub-svpc"   # from Stage 1 output
   pulumi config set parent_id "organizations/YOUR_ORG_ID"
   pulumi up
   ```

1. Deploy each spoke leaf (`envs/development`, `envs/nonproduction`,
   `envs/production`):

   ```bash
   cd ../development
   pulumi stack init production
   pulumi config set spoke_project_id "prj-d-svpc"       # from Stage 1 output
   pulumi config set org_stack_name "<org>/foundation-org-shared/production"
   pulumi preview
   pulumi up
   ```

1. Proceed to the [4-projects](../4-projects/README.md) step.

### Running Pulumi Locally

Same process as above — navigate, initialize, configure, and deploy.

### Known Issue: VPC Peering Rate Limit

When deploying the hub-and-spoke architecture, you may encounter a `CONCURRENT_OPERATIONS_QUOTA_EXCEEDED` error when adding network peering. This is a transient error; wait at least one minute and retry the deploy.

## Configuration Reference

The environment identity (`shared`/`c` and `development`/`nonproduction`/
`production` with their spoke CIDR plans) is pinned in each leaf's `main.go`,
not stack config.

| Name               | Leaf       | Description                        | Required | Default         |
| ------------------ | ---------- | ---------------------------------- | :------: | --------------- |
| `hub_project_id`   | shared     | Hub VPC host project ID            |    ✅    | —               |
| `parent_id`        | shared     | Parent scope for firewall policies |    ✅    | —               |
| `spoke_project_id` | env leaves | Spoke VPC project ID               |    ✅    | —               |
| `org_stack_name`   | env leaves | 1-org stack (hub project lookup)   |          | `"org"`         |
| `region1`          | all        | Primary region                     |          | `"us-central1"` |
| `region2`          | all        | Secondary region                   |          | `"us-west1"`    |

## Outputs

| Name                     | Description                                        |
| ------------------------ | -------------------------------------------------- |
| `hierarchical_fw`        | Hierarchical firewall policy ID                    |
| `hub_vpc_id`             | Hub VPC network resource ID                        |
| `spoke_vpc_id`           | Spoke VPC network resource ID                      |
| `service_perimeter_name` | VPC Service Controls perimeter name (when enabled) |

## File Structure

Mirrors upstream `terraform-example-foundation/3-networks-hub-and-spoke`: a
shared/hub root plus three thin spoke roots that pin their environment and call
the shared modules.

| File                                    | Description                                                                                      |
| --------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `envs/shared/main.go`                   | Thin shared root pinning `shared`/`c`: hub VPC, hierarchical firewall, DNS hub, transitivity      |
| `envs/development/main.go`              | Thin spoke root pinning `development`/`d` + spoke CIDRs; calls `modules/base_env`                 |
| `envs/nonproduction/main.go`            | Thin spoke root pinning `nonproduction`/`n` + spoke CIDRs; calls `modules/base_env`               |
| `envs/production/main.go`               | Thin spoke root pinning `production`/`p` + spoke CIDRs; calls `modules/base_env`                  |
| `modules/shared_vpc/`                   | Unified Shared VPC module (hub/spoke modes): VPC, subnets, peering, routes, firewall, PSC, DNS    |
| `modules/base_env/base_env.go`          | Per-env spoke orchestrator: builds spoke subnet args, invokes `shared_vpc` in spoke mode          |
| `modules/hierarchical_firewall_policy/` | Org/folder-level hierarchical firewall policy (used by `envs/shared`)                             |
| `modules/transitivity/`                 | Optional transitivity gateway appliance (hub)                                                     |
