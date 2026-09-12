# 2-environments

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **Go**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to set up development, nonproduction, and production environments within the Google Cloud organization that you've created. For each environment, this stage creates:

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

1. Each environment is its own thin leaf Pulumi project under `envs/`
   (mirroring upstream `2-environments/envs/<env>`); the environment identity
   is pinned in each leaf's `main.go`. Navigate to the environment's directory
   and initialize its stack — repeat these steps for `envs/development`,
   `envs/nonproduction`, and `envs/production` in promotion order:

   ```bash
   cd 2-environments/envs/development
   pulumi stack init production
   ```

1. Set the required configuration:

   ```bash
   pulumi config set org_id "YOUR_ORG_ID"
   pulumi config set billing_account "YOUR_BILLING_ACCOUNT_ID"
   pulumi config set org_stack_name "organization/vitruvian/foundation-org-shared/production"
   ```

1. (Optional) Override the project prefix:

   ```bash
   pulumi config set project_prefix "prj"  # default: prj
   ```

1. Preview and deploy:

   ```bash
   pulumi preview
   pulumi up
   ```

1. Commit and push to trigger the CI/CD pipeline:

   ```bash
   git add .
   git commit -m "Initialize environments stage"
   git push origin production
   ```

1. You can now move to the instructions in the network step. To use the [Shared VPC](https://cloud.google.com/architecture/security-foundations/networking#vpcsharedvpc-id7-1-shared-vpc-) network mode, go to [3-networks-svpc](../3-networks-svpc/README.md). To use the [Hub and Spoke](https://cloud.google.com/architecture/security-foundations/networking#hub-and-spoke) network mode, go to [3-networks-hub-and-spoke](../3-networks-hub-and-spoke/README.md).

### Running Pulumi Locally

1. Navigate to the environment leaf (e.g. `2-environments/envs/development`), initialize, and set configuration as described above.

1. Preview and deploy:

   ```bash
   pulumi preview
   pulumi up
   ```

## Configuration Reference

| Name                                 | Description                                          | Required | Default              |
| ------------------------------------ | ---------------------------------------------------- | :------: | -------------------- |
| `org_id`                             | GCP Organization ID                                  |    ✅    | —                    |
| `billing_account`                    | Billing account ID                                   |    ✅    | —                    |
| `org_stack_name`                     | Fully qualified Pulumi stack name of the 1-org stage |    ✅    | —                    |
| `project_prefix`                     | Project name prefix                                  |          | `"prj"`              |
| `folder_prefix`                      | Name prefix for folders                              |          | `"fldr"`             |
| `project_deletion_policy`            | Deletion policy for created projects                 |          | `"PREVENT"`          |
| `default_service_account`            | Default service account setting                      |          | `"deprivilege"`      |
| `folder_deletion_protection`         | Prevent Terraform from destroying folders            |          | `true`               |
| `random_suffix`                      | Append random suffix to project IDs                  |          | `true`               |
| `api_propagation_seconds`            | Cold-deploy wait for freshly-enabled project APIs    |          | `120`                |
| `project_budget`                     | Budget configuration for projects                    |          | `{}`                 |
| `assured_workload_enabled`           | Enable Assured Workload                              |          | `false`              |
| `assured_workload_location`          | Assured Workload location                            |          | `"us-central1"`      |
| `assured_workload_display_name`      | Assured Workload display name                        |          | `"FEDRAMP-MODERATE"` |
| `assured_workload_compliance_regime` | Assured Workload compliance regime                   |          | `"FEDRAMP_MODERATE"` |
| `assured_workload_resource_type`     | Assured Workload resource type                       |          | `"CONSUMER_FOLDER"`  |

## Outputs

Each environment leaf exports its own (un-prefixed) outputs, mirroring
upstream `2-environments/envs/<env>/outputs.tf`:

| Name                         | Description                                            |
| ---------------------------- | ------------------------------------------------------ |
| `env_folder`                 | Environment folder name                                |
| `env_kms_project_id`         | KMS project ID for the environment                     |
| `env_kms_project_number`     | KMS project number for the environment                 |
| `env_secrets_project_id`     | Secrets project ID for the environment                 |
| `assured_workload_id`        | Assured Workload ID (if configured)                    |
| `assured_workload_resources` | Assured Workload resources (if configured)             |

## File Structure

Mirrors upstream `terraform-example-foundation/2-environments`: three thin env
roots that pin their environment and call the shared `env_baseline` module.

| File                                    | Description                                                                             |
| --------------------------------------- | --------------------------------------------------------------------------------------- |
| `envs/development/main.go`              | Thin root pinning `development`/`d`; loads config and calls `modules/env_baseline`      |
| `envs/nonproduction/main.go`            | Thin root pinning `nonproduction`/`n`; loads config and calls `modules/env_baseline`    |
| `envs/production/main.go`               | Thin root pinning `production`/`p`; loads config and calls `modules/env_baseline`       |
| `modules/env_baseline/env_baseline.go`  | Shared logic: env folder, KMS + Secrets projects, budgets, optional Assured Workload    |
