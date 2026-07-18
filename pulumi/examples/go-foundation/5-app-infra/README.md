# 5-app-infra

This repo is part of a multi-part guide that shows how to configure and deploy
the example.com reference architecture described in
[Google Cloud security foundations guide](https://cloud.google.com/architecture/security-foundations), implemented using **Pulumi** and **Go**. See the [stage navigation table](../0-bootstrap/README.md) for an overview of all stages.

## Purpose

The purpose of this step is to deploy sample application infrastructure in one of the business unit projects using the infra pipeline set up in [4-projects](../4-projects/README.md).

The stage mirrors upstream's `business_unit_1/{development,nonproduction,production}` layout: each
environment is its own thin leaf Pulumi project (environment identity pinned in the leaf's `main.go`;
note 5-app-infra has **no** `shared` leaf, unlike 4-projects). All resource logic lives in the shared
`modules/` packages (`env_base`, `confidential_space`, `serverless_space`).

Each env leaf deploys:

- A **Base Compute Instance** in the SVPC-attached project (`prj-{env}-{bu}-sample-svpc`) using the shared VPC subnet (`modules/env_base`).
- An optional **Confidential Space VM** in the Confidential Space project (`prj-{env}-{bu}-conf-space`), utilizing a dedicated Workload Identity Pool and Provider for attestation, and running the `confidential-space` OS image (`modules/confidential_space`). The workload image is served from the BU's app-infra pipeline project (the 4-projects `business_unit_1/shared` leaf).
- An optional **Serverless (Cloud Run) workload** (`modules/serverless_space`) — our addition to the upstream module set, deployed only when a promoted image digest is configured.

This mirrors the upstream Terraform foundation's `env_base` and `confidential_space` modules, demonstrating how applications and hardware-secured workloads are provisioned within the connected environments.

## Prerequisites

1. [0-bootstrap](../0-bootstrap/README.md) executed successfully.
1. [1-org](../1-org/README.md) executed successfully.
1. [2-environments](../2-environments/README.md) executed successfully.
1. [3-networks](../3-networks-svpc/README.md) executed successfully.
1. [4-projects](../4-projects/README.md) executed successfully (including the `business_unit_1/shared` leaf).

### Troubleshooting

See [troubleshooting](../docs/TROUBLESHOOTING.md) if you run into issues during this step.

## Usage

### Deploying with GitHub Actions

1. Each environment is its own thin leaf Pulumi project under `business_unit_1/`
   (mirroring upstream `5-app-infra/business_unit_1/<env>`); the environment
   identity is pinned in each leaf's `main.go`. Navigate to a leaf and
   initialize its stack:

   ```bash
   cd 5-app-infra/business_unit_1/development
   pulumi stack init production
   ```

1. (Optional) Override the 4-projects stack references (defaults derive from
   the pinned environment and business code):

   ```bash
   pulumi config set projects_stack_name "organization/vitruvian/foundation-projects-bu1-development/production"
   pulumi config set projects_shared_stack_name "organization/vitruvian/foundation-projects-bu1-shared/production"
   ```

1. (Optional) Override the default region:

   ```bash
   pulumi config set region "us-central1"   # default: 4-projects default_region
   ```

1. (Optional) Enable Confidential Space deployment by providing an image digest:

   ```bash
   pulumi config set confidential_image_digest "sha256:exampledigest"
   ```

1. (Optional) Enable the serverless workload by providing a promoted Cloud Run image digest:

   ```bash
   pulumi config set serverless_image_digest "sha256:exampledigest"
   ```

1. Preview and deploy:

   ```bash
   pulumi preview
   pulumi up
   ```

1. **Repeat for each env leaf** (`business_unit_1/nonproduction`, `business_unit_1/production`).

### Running Pulumi Locally

Same process as above — navigate to each leaf, initialize, configure, and deploy.

## Configuration Reference

The environment identity (`development`, `nonproduction`, `production`) is pinned in each leaf's
`main.go`, not configured.

| Name                         | Description                                                                                 | Required | Default                                                            |
| ---------------------------- | ------------------------------------------------------------------------------------------- | :------: | ------------------------------------------------------------------ |
| `business_code`              | Business Unit code (e.g. `bu1`)                                                             |          | `"bu1"`                                                            |
| `projects_stack_name`        | Stack name of this environment's 4-projects `business_unit_1/<env>` leaf                    |          | `organization/vitruvian/foundation-projects-bu1-<env>/production`  |
| `projects_shared_stack_name` | Stack name of the BU's 4-projects `business_unit_1/shared` leaf                             |          | Derived from `projects_stack_name`                                 |
| `region`                     | Region for the Compute Instances                                                            |          | 4-projects `default_region`                                        |
| `confidential_image_digest`  | SHA256 digest of the Docker image to be used for running the workload in Confidential Space |          | —                                                                  |
| `serverless_image_digest`    | Promoted Cloud Run image digest enabling the serverless workload                            |          | — (workload skipped)                                               |

## Outputs

Each env leaf exports:

| Name                                | Description                                               |
| ----------------------------------- | --------------------------------------------------------- |
| `project_id`                        | Application project ID                                    |
| `region`                            | Deployment region                                         |
| `serverless_service_uri`            | Cloud Run service URI (when serverless workload enabled)  |

## File Structure

| File                                    | Description                                                                                                    |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `business_unit_1/development/main.go`   | Thin env leaf pinning `development`/`d`; 4-projects Stack References, calls the shared modules, exports results |
| `business_unit_1/nonproduction/main.go` | Thin env leaf pinning `nonproduction`/`n`; same shape                                                          |
| `business_unit_1/production/main.go`    | Thin env leaf pinning `production`/`p`; same shape                                                             |
| `modules/env_base/`                     | Standard Compute Instances with Service Accounts and IAP tag bindings                                          |
| `modules/confidential_space/`           | Confidential Space VMs and Workload Identity components for attestation                                        |
| `modules/serverless_space/`             | Cloud Run service + SA + secret wiring (our serverless addition to the upstream module set)                    |
