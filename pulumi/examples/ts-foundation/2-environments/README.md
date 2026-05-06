# 2-environments

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to set up development, nonproduction, and production environments within the Google Cloud organization that you've created. **This is where environment branches begin.**

For each environment, this stage creates:

- **`prj-{d,n,p}-kms`** — An environment-level [Cloud KMS](https://cloud.google.com/security-key-management) project for key management
- **`prj-{d,n,p}-secrets`** — An environment-level [Secret Manager](https://cloud.google.com/secret-manager) project for secret storage

This will create the following project structure under the environment folders created in Stage 1:

```
example-organization
└── fldr-development
    ├── prj-d-kms
    └── prj-d-secrets
└── fldr-nonproduction
    ├── prj-n-kms
    └── prj-n-secrets
└── fldr-production
    ├── prj-p-kms
    └── prj-p-secrets
```

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Clone the repository you created to host the `2-environments` code at the same level of the `pulumi_ts-example-foundation` folder.

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-ENVIRONMENTS-REPO>.git gcp-environments
   ```

1. Navigate into the repo. All subsequent steps assume you are running them from the `gcp-environments` directory.

   ```bash
   cd gcp-environments
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

1. Copy the environments stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/2-environments/* .
   mkdir -p .github/workflows
   cp ../pulumi_ts-example-foundation/build/pulumi-preview.yml .github/workflows/
   cp ../pulumi_ts-example-foundation/build/pulumi-up.yml .github/workflows/
   ```

1. Install dependencies.

   ```bash
   npm install
   ```

1. Initialize Pulumi stacks for **each environment**.

   ```bash
   # Development
   pulumi stack init development
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"

   # Nonproduction
   pulumi stack init nonproduction
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"

   # Production
   pulumi stack init production
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"
   ```

1. Commit and push.

   ```bash
   git add .
   git commit -m 'Initialize environments repo'
   git push --set-upstream origin plan
   ```

1. **Deploy development first.** Open a pull request from `plan` to `development`, review the GitHub Action output, and merge.
1. **Promote to nonproduction.** Open a pull request from `development` to `nonproduction`, review, and merge.
1. **Promote to production.** Open a pull request from `nonproduction` to `production`, review, and merge.

1. You can now move to the instructions in the network step. To use the [Shared VPC](https://cloud.google.com/architecture/security-foundations/networking#vpcsharedvpc-id7-1-shared-vpc-) network mode, go to [3-networks-svpc](../3-networks-svpc/README.md). To use the [Hub and Spoke](https://cloud.google.com/architecture/security-foundations/networking#hub-and-spoke) network mode, go to [3-networks-hub-and-spoke](../3-networks-hub-and-spoke/README.md).

1. Before moving to the next step, go back to the parent directory.

   ```bash
   cd ..
   ```

### Running Pulumi Locally

1. Navigate to `2-environments`:

   ```bash
   cd pulumi_ts-example-foundation/2-environments
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
| `org_stack_name` | Stack reference to the 1-org stack | `string` | n/a | yes |
| `project_prefix` | Name prefix for projects | `string` | `"prj"` | no |
| `folder_prefix` | Name prefix for folders | `string` | `"fldr"` | no |
| `default_region` | Default region for resources | `string` | `"us-central1"` | no |
| `project_deletion_policy` | Deletion policy for created projects | `string` | `"PREVENT"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `env_kms_project_id` | Environment KMS project ID |
| `env_secrets_project_id` | Environment Secrets project ID |
| `env_folder_id` | Environment folder ID |

## File Structure

| File | Description |
|------|-------------|
| `envs/development/index.ts` | Development environment deployment |
| `envs/nonproduction/index.ts` | Non-production environment deployment |
| `envs/production/index.ts` | Production environment deployment |
| `modules/env_baseline.ts` | Per-environment KMS + Secrets project creation with labels |
