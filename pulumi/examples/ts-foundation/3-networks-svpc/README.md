# 3-networks-svpc

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to:

- Set up the global [DNS Hub](https://cloud.google.com/blog/products/networking/cloud-forwarding-peering-and-zones).
- Configure Shared VPCs with default DNS, NAT, Private Service networking, and baseline firewall rules for each environment.

This step makes use of the **Dual Shared VPC** architecture described in the **Networking** section of the [Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations/networking). To use the **Hub and Spoke** model instead, see [3-networks-hub-and-spoke](../3-networks-hub-and-spoke/README.md).

### What Gets Created

For each environment (`development`, `nonproduction`, `production`):

- **Shared VPC Host Project** designation on the network project created in Stage 1
- **VPC Network** with auto-create subnets disabled and default routes removed
- **Multi-region subnets** with GKE secondary ranges (pod + service CIDRs)
- **Private Google Access** enabled on all subnets with flow logging
- **Private Service Access** (PSA) for managed services like Cloud SQL and Memorystore
- **Hierarchical Firewall Policies** with baseline rules:
  - Allow [IAP TCP forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding) from `35.235.240.0/20`
  - Allow [load balancer health checks](https://cloud.google.com/load-balancing/docs/health-checks#firewall_rules) from `130.211.0.0/22` and `35.191.0.0/16`
  - Allow [Windows KMS activation](https://cloud.google.com/compute/docs/instances/windows/creating-managing-windows-instances#kms-server) to `35.190.247.13/32`
- **DNS Policy** with logging and [inbound query forwarding](https://cloud.google.com/dns/docs/overview#dns-server-policy-in) enabled
- **Cloud NAT** on all regions with error-only logging
- **Restricted Google APIs routing** via `199.36.153.4/30`
- **Default internet routes removed**

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

1. Copy the networks stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/3-networks-svpc/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

1. Install dependencies.

   ```bash
   npm install
   ```

1. Initialize Pulumi stacks for the shared environment and each per-environment stack.

   ```bash
   # Shared resources (DNS Hub, Interconnect, hierarchical firewall)
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

1. **Deploy the shared environment first** (manually, before environment branches):

   ```bash
   pulumi stack select shared
   pulumi up
   ```

   > **Important:** The shared environment (DNS Hub, hierarchical firewall) must be deployed before per-environment networks.

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

### Using Dedicated Interconnect

If you have provisioned Dedicated Interconnect prerequisites, extend the shared environment deployment to create VLAN attachments and BGP sessions. Refer to the [Dedicated Interconnect documentation](https://cloud.google.com/network-connectivity/docs/interconnect/how-to/dedicated/creating-vlan-attachments).

### Using HA VPN (Optional)

If you cannot use Dedicated or Partner Interconnect, you can use an HA Cloud VPN to access on-premises resources.

### Running Pulumi Locally

1. Navigate to `3-networks-svpc`:

   ```bash
   cd pulumi_ts-example-foundation/3-networks-svpc
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

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `org_id` | GCP Organization ID | `string` | n/a | yes |
| `billing_account` | Billing account ID | `string` | n/a | yes |
| `org_stack_name` | Stack reference to the 1-org stack | `string` | n/a | yes |
| `env_stack_name` | Stack reference to the 2-environments stack | `string` | n/a | yes |
| `default_region1` | Primary region for subnets | `string` | `"us-central1"` | no |
| `default_region2` | Secondary region for subnets | `string` | `"us-west1"` | no |
| `dns_enable_inbound_forwarding` | Enable DNS inbound forwarding | `boolean` | `true` | no |
| `dns_enable_logging` | Enable DNS query logging | `boolean` | `true` | no |
| `nat_enabled` | Enable Cloud NAT | `boolean` | `true` | no |
| `nat_num_addresses_region1` | Number of NAT IPs for region 1 | `number` | `2` | no |
| `nat_num_addresses_region2` | Number of NAT IPs for region 2 | `number` | `2` | no |
| `windows_activation_enabled` | Enable Windows KMS activation firewall rule | `boolean` | `false` | no |
| `enable_partner_interconnect` | Enable partner interconnect | `boolean` | `false` | no |
| `firewall_enable_logging` | Enable firewall logging | `boolean` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `network_name` | VPC network name |
| `network_self_link` | VPC network self-link |
| `subnets` | Subnet details (name, region, CIDR) |
| `dns_hub_project_id` | DNS hub project ID |

## File Structure

| File | Description |
|------|-------------|
| `envs/development/index.ts` | Development SVPC network deployment |
| `envs/nonproduction/index.ts` | Non-production SVPC network deployment |
| `envs/production/index.ts` | Production SVPC network deployment |
| `envs/shared/index.ts` | Shared resources (DNS Hub, hierarchical FW) |
| `modules/shared_vpc.ts` | Shared VPC module: VPC, subnets, firewall, DNS, NAT, PSA |
