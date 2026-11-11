# 4-projects / business_unit_1 / shared

This directory contains the Pulumi project configuration for the **shared** environment in **business_unit_1**.

## Inputs

| Name              | Description                         | Type     | Default    | Required |
| ----------------- | ----------------------------------- | -------- | ---------- | :------: |
| `env`             | Environment name                    | `string` | `"shared"` |   yes    |
| `business_code`   | Business unit code                  | `string` | `"bu1"`    |   yes    |
| `billing_account` | Billing account ID                  | `string` | n/a        |   yes    |
| `org_stack_name`  | Fully qualified stack name of 1-org | `string` | n/a        |   yes    |
| `project_prefix`  | Name prefix for projects            | `string` | `"prj"`    |    no    |

## Outputs

| Name                        | Description                        |
| --------------------------- | ---------------------------------- |
| `bu_folder_id`              | Business unit folder ID            |
| `svpc_project_id`           | SVPC-attached project ID           |
| `floating_project_id`       | Floating project ID                |
| `peering_project_id`        | Peering project ID                 |
| `infra_pipeline_project_id` | Infrastructure pipeline project ID |

## Interface
- Internal implementation components

## Invariants
- [index.ts:20]: `const orgId = config.require("org_id");`
- [index.ts:21]: `const billingAccount = config.require("billing_account");`
- [index.ts:28]: `folderId: config.require("common_folder_name"),`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/pulumi/examples/ts-foundation/4-projects/business_unit_1/shared/...`
