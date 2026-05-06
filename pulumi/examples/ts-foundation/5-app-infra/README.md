# 5-app-infra

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to deploy sample application infrastructure in one of the business unit projects using the infra pipeline set up in [4-projects](../4-projects/README.md).

This stage deploys:

- A **Compute Engine instance** with an instance template
- A **Service account** with least-privilege roles

This demonstrates how applications are provisioned within the connected environments created by the preceding stages.

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.
1. [2-environments](../2-environments/README.md) executed successfully.
1. [3-networks](../3-networks-svpc/README.md) executed successfully.
1. [4-projects](../4-projects/README.md) executed successfully.

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Clone the repository you created to host the `5-app-infra` code at the same level of the `pulumi_ts-example-foundation` folder.

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-APP-INFRA-REPO>.git gcp-app-infra
   ```

1. Navigate into the repo. All subsequent steps assume you are running them from the `gcp-app-infra` directory.

   ```bash
   cd gcp-app-infra
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

1. Copy the app-infra stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/5-app-infra/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

1. Install dependencies.

   ```bash
   npm install
   ```

1. Initialize Pulumi stacks for each environment.

   ```bash
   for env in development nonproduction production; do
     pulumi stack init ${env}
     pulumi config set org_id "YOUR_ORG_ID"
     pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
     pulumi config set proj_stack_name "<PULUMI-ORG>/gcp-projects/${env}"
   done
   ```

1. (Optional) Override defaults:

   ```bash
   pulumi config set business_code "bu1"              # default: bu1
   pulumi config set instance_region "us-central1"     # default: us-central1
   pulumi config set machine_type "f1-micro"           # default: f1-micro
   ```

1. Commit and push.

   ```bash
   git add .
   git commit -m 'Initialize app-infra repo'
   git push --set-upstream origin plan
   ```

1. **Deploy development.** Open a pull request from `plan` to `development`, review, and merge.
1. **Promote to nonproduction.** Open a pull request from `development` to `nonproduction`, review, and merge.
1. **Promote to production.** Open a pull request from `nonproduction` to `production`, review, and merge.

### Running Pulumi Locally

1. Navigate to `5-app-infra`:

   ```bash
   cd pulumi_ts-example-foundation/5-app-infra
   ```

1. Install dependencies:

   ```bash
   npm install
   ```

1. Initialize stacks and set configuration as described above.

1. Deploy each environment:

   ```bash
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
| `proj_stack_name` | Stack reference to the 4-projects stack | `string` | n/a | yes |
| `business_code` | Short code for the business unit | `string` | `"bu1"` | no |
| `instance_region` | Region for the Compute Engine instance | `string` | `"us-central1"` | no |
| `machine_type` | Machine type for the instance | `string` | `"f1-micro"` | no |
| `project_deletion_policy` | Deletion policy for created projects | `string` | `"PREVENT"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `instance_name` | Name of the created Compute Engine instance |
| `instance_zone` | Zone where the instance is deployed |
| `service_account_email` | Service account email for the instance |

## File Structure

| File | Description |
|------|-------------|
| `business_unit_1/development/index.ts` | Development app infrastructure for BU1 |
| `business_unit_1/nonproduction/index.ts` | Non-production app infrastructure for BU1 |
| `business_unit_1/production/index.ts` | Production app infrastructure for BU1 |
