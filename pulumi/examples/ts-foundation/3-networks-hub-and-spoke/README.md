# 3-networks-hub-and-spoke

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is the same as [3-networks-svpc](../3-networks-svpc/README.md), but here the architecture is based on the Hub and Spoke network model instead of Dual Shared VPC.

This creates:
- **Hub VPC** with central routing
- **Spoke VPC** per environment with GKE secondary ranges
- **Bidirectional VPC peering** with custom route export/import
- Same firewall, DNS, NAT, and routing as the SVPC variant

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.
1. [2-environments](../2-environments/README.md) executed successfully.

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Clone the repository you created to host the `3-networks` code at the same level of the `pulumi_ts-example-foundation` folder.

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-NETWORKS-REPO>.git gcp-networks
   ```

1. Navigate into the repo. All subsequent steps assume you are running them from the `gcp-networks` directory.

   ```bash
   cd gcp-networks
   ```

1. Seed the repository with **all environment branches**.

   ```bash
   git commit --allow-empty -m 'repository seed'
   git push --set-upstream origin main

   git checkout -b production
   git push --set-upstream origin production

   git checkout -b nonproduction
   git push --set-upstream origin nonproduction

   git checkout -b development
   git push --set-upstream origin development
   ```

1. Create a working branch.

   ```bash
   git checkout -b plan
   ```

1. Copy the hub-and-spoke stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/3-networks-hub-and-spoke/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

1. Install dependencies.

   ```bash
   npm install
   ```

1. Initialize Pulumi stacks for shared and per-environment stacks.

   ```bash
   # Shared resources (DNS Hub, hierarchical firewall)
   pulumi stack init shared
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"
   pulumi config set env_stack_name "<PULUMI-ORG>/gcp-environments/production"

   # Per-environment stacks
   for env in development nonproduction production; do
     pulumi stack init ${env}
     pulumi config set org_id "YOUR_ORG_ID"
     pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
     pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"
     pulumi config set env_stack_name "<PULUMI-ORG>/gcp-environments/${env}"
   done
   ```

1. **Deploy the shared environment first** (manually):

   ```bash
   pulumi stack select shared
   pulumi up
   ```

   > **Important:** The shared environment must be deployed before per-environment networks.

1. Commit and push.

   ```bash
   git add .
   git commit -m 'Initialize networks repo'
   git push --set-upstream origin plan
   ```

1. **Deploy development.** Open a pull request from `plan` to `development`, review, and merge.
1. **Promote to nonproduction.** Open a pull request from `development` to `nonproduction`, review, and merge.
1. **Promote to production.** Open a pull request from `nonproduction` to `production`, review, and merge.

1. Before moving to the next step, go back to the parent directory.

   ```bash
   cd ..
   ```

1. Proceed to the [4-projects](../4-projects/README.md) step.

### Running Pulumi Locally

1. Navigate to `3-networks-hub-and-spoke`:

   ```bash
   cd pulumi_ts-example-foundation/3-networks-hub-and-spoke
   ```

1. Install dependencies:

   ```bash
   npm install
   ```

1. Initialize stacks and set configuration as described above.

1. Deploy shared first, then each environment:

   ```bash
   pulumi stack select shared
   pulumi up

   pulumi stack select development
   pulumi up

   pulumi stack select nonproduction
   pulumi up

   pulumi stack select production
   pulumi up
   ```

## Configuration Reference

Same as [3-networks-svpc](../3-networks-svpc/README.md#configuration-reference), with additional:

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `enable_hub_and_spoke_transitivity` | Enable transitivity between spokes via the hub | `boolean` | `false` | no |

## Outputs

Same as [3-networks-svpc](../3-networks-svpc/README.md#outputs), with additional:

| Name | Description |
|------|-------------|
| `hub_network_name` | Hub VPC network name |
| `hub_network_self_link` | Hub VPC network self-link |

## File Structure

| File | Description |
|------|-------------|
| `envs/development/index.ts` | Development hub-and-spoke network deployment |
| `envs/nonproduction/index.ts` | Non-production hub-and-spoke network deployment |
| `envs/production/index.ts` | Production hub-and-spoke network deployment |
| `envs/shared/index.ts` | Shared resources (DNS Hub, hierarchical FW) |
| `modules/shared_vpc.ts` | Hub-and-spoke VPC module with peering and route exchange |
