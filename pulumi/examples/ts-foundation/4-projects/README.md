# 4-projects

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **TypeScript**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to set up the folder structure, projects, and infrastructure pipelines for applications that are connected as service projects to the Shared VPC created in the previous stage.

For each business unit and environment, this stage creates:

- A **business unit subfolder** under each environment folder (e.g., `fldr-development-bu1`)
- **Three project types** per business unit:
  - **SVPC-attached** (`prj-{env}-{bu}-sample-svpc`) — Connected as a service project to the Shared VPC host
  - **Floating** (`prj-{env}-{bu}-sample-floating`) — Standalone project not attached to any VPC
  - **Peering** (`prj-{env}-{bu}-sample-peering`) — Project with its own VPC peered to the Shared VPC host
- An **infrastructure pipeline project** (`prj-c-{bu}-infra-pipeline`) under the common folder

Running this code as-is should generate a structure as shown below:

```
example-organization/
└── fldr-development
    └── fldr-development-bu1
        ├── prj-d-bu1-sample-floating
        ├── prj-d-bu1-sample-svpc
        └── prj-d-bu1-sample-peering
└── fldr-nonproduction
    └── fldr-nonproduction-bu1
        ├── prj-n-bu1-sample-floating
        ├── prj-n-bu1-sample-svpc
        └── prj-n-bu1-sample-peering
└── fldr-production
    └── fldr-production-bu1
        ├── prj-p-bu1-sample-floating
        ├── prj-p-bu1-sample-svpc
        └── prj-p-bu1-sample-peering
└── fldr-common
    └── prj-c-bu1-infra-pipeline
```

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.
1. [2-environments](../2-environments/README.md) executed successfully.
1. [3-networks](../3-networks-svpc/README.md) executed successfully.

**Note:** As mentioned in the [0-bootstrap README](../0-bootstrap/README.md), make sure that you have requested at least 50 additional projects for the **projects step service account**, otherwise you may face a project quota exceeded error.

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Clone the repository you created to host the `4-projects` code at the same level of the `pulumi_ts-example-foundation` folder.

   ```bash
   git clone git@github.com:<GITHUB-OWNER>/<GITHUB-PROJECTS-REPO>.git gcp-projects
   ```

1. Navigate into the repo. All subsequent steps assume you are running them from the `gcp-projects` directory.

   ```bash
   cd gcp-projects
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

1. Copy the projects stage code and pipeline templates.

   ```bash
   cp -R ../pulumi_ts-example-foundation/4-projects/* .
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
   # Shared (infra pipeline project under common folder)
   pulumi stack init shared
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
   pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"
   pulumi config set net_stack_name "<PULUMI-ORG>/gcp-networks/production"

   # Per-environment stacks
   for env in development nonproduction production; do
     pulumi stack init ${env}
     pulumi config set org_id "YOUR_ORG_ID"
     pulumi config set billing_account "YOUR_BILLING_ACCOUNT"
     pulumi config set org_stack_name "<PULUMI-ORG>/gcp-org/production"
     pulumi config set net_stack_name "<PULUMI-ORG>/gcp-networks/${env}"
   done
   ```

1. **Deploy the shared environment first** (manually):

   ```bash
   pulumi stack select shared
   pulumi up
   ```

1. Commit and push.

   ```bash
   git add .
   git commit -m 'Initialize projects repo'
   git push --set-upstream origin plan
   ```

1. **Deploy development.** Open a pull request from `plan` to `development`, review, and merge.
1. **Promote to nonproduction.** Open a pull request from `development` to `nonproduction`, review, and merge.
1. **Promote to production.** Open a pull request from `nonproduction` to `production`, review, and merge.

1. Before moving to the next step, go back to the parent directory.

   ```bash
   cd ..
   ```

1. Proceed to the [5-app-infra](../5-app-infra/README.md) step.

### Adding Additional Business Units

To create a new business unit (e.g., `bu2`), copy the `business_unit_1` directory and update the business codes and subnet ranges.

> **Tip:** Each business unit can have its own configuration and deployment stacks.

### Running Pulumi Locally

1. Navigate to `4-projects`:

   ```bash
   cd pulumi_ts-example-foundation/4-projects
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
| `net_stack_name` | Stack reference to the 3-networks stack | `string` | n/a | yes |
| `project_prefix` | Name prefix for projects | `string` | `"prj"` | no |
| `folder_prefix` | Name prefix for folders | `string` | `"fldr"` | no |
| `business_code` | Short code for the business unit | `string` | `"bu1"` | no |
| `business_unit` | Full name of the business unit | `string` | `"business_unit_1"` | no |
| `project_deletion_policy` | Deletion policy for created projects | `string` | `"PREVENT"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `svpc_project_id` | SVPC-attached project ID |
| `floating_project_id` | Floating project ID |
| `peering_project_id` | Peering project ID |
| `infra_pipeline_project_id` | Infrastructure pipeline project ID |

## File Structure

| File | Description |
|------|-------------|
| `business_unit_1/development/index.ts` | Development projects for business unit 1 |
| `business_unit_1/nonproduction/index.ts` | Non-production projects for business unit 1 |
| `business_unit_1/production/index.ts` | Production projects for business unit 1 |
| `business_unit_1/shared/index.ts` | Shared projects for business unit 1 (infra pipeline) |
| `modules/single_project.ts` | Single project factory with APIs, billing, VPC attachment |
