# 2-environments/envs/development

Thin env root for the **development** environment — the Pulumi/Go port of upstream
[terraform-example-foundation `2-environments/envs/development`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/2-environments/envs/development).

## Purpose

This leaf pins the environment identity (`development`/`d`), reads the core
identifiers from stack config plus a StackReference to the 1-org stage (for tag
values), and calls the shared [`env_baseline`](../../modules/env_baseline/README.md)
module, which creates:

- `fldr-development` — the environment folder, with the `environment_development`
  tag value from 1-org bound to it
- `prj-d-kms` — the environment-level Cloud KMS project
- `prj-d-secrets` — the environment-level Secret Manager project
- an optional Assured Workload

The sibling leaves under `../` deploy the other environments; all resource
creation lives in the module.

## File layout

| File | Upstream analog | Contents |
|------|-----------------|----------|
| `main.go` | `main.tf` | pinned env identity + StackReference + `env_baseline.Deploy` call |
| `config.go` | `variables.tf` (+ `remote.tf` locals) | `EnvConfig` struct + `loadEnvConfig` (config keys, defaults, parent derivation) |
| `outputs.go` | `outputs.tf` | `exportOutputs` (stack exports) |
| `config_test.go` | — | config-loading unit test (Pulumi mocks) |
| `Pulumi.yaml` | `backend.tf` / `versions.tf` | Pulumi project file (engine adaptation; provider pins live in `go.mod`) |
| `Pulumi.production.yaml.example` | `terraform.tfvars` | example stack config (copy to `Pulumi.production.yaml`) |

## Inputs (stack config)

| Key | Description | Default | Required |
|-----|-------------|---------|:--------:|
| `org_id` | Organization ID | n/a | yes |
| `billing_account` | Billing account for the environment projects | n/a | yes |
| `org_stack_name` | Fully-qualified 1-org stack for the StackReference (tags) | n/a | yes |
| `parent_folder` | Parent folder ID; the org root is used when unset | org root | no |
| `project_prefix` | Prefix for project IDs | `"prj"` | no |
| `folder_prefix` | Prefix for folder display names | `"fldr"` | no |
| `random_suffix` | Append a random suffix to project IDs | `true` | no |
| `project_deletion_policy` | Deletion policy for the projects created | `"PREVENT"` | no |
| `folder_deletion_protection` | Prevent destroying/recreating the environment folder | `true` | no |
| `default_service_account` | Default compute SA handling | `"deprivilege"` | no |
| `api_propagation_seconds` | Cold-deploy wait for freshly-enabled project APIs before dependents (Budget, default-SA deprivilege) use them | `120` | no |
| `project_budget` | Per-project budget object (see module README) | upstream defaults (`1000`, `[1.2]`, `FORECASTED_SPEND`) | no |
| `assured_workload_enabled` | Create an Assured Workload | `false` | no |
| `assured_workload_location` | Assured Workload location | `"us-central1"` | no |
| `assured_workload_display_name` | Assured Workload display name | `"FEDRAMP-MODERATE"` | no |
| `assured_workload_compliance_regime` | Assured Workload compliance regime | `"FEDRAMP_MODERATE"` | no |
| `assured_workload_resource_type` | Assured Workload resource type | `"CONSUMER_FOLDER"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `env_folder` | Environment folder created under parent |
| `env_kms_project_id` | Project for environment Cloud Key Management Service (KMS) |
| `env_kms_project_number` | Project number for environment KMS |
| `env_secrets_project_id` | Project for environment related secrets |
| `assured_workload_id` | Assured Workload ID (only when enabled) |
| `assured_workload_resources` | Assured Workload resources (only when enabled) |

## Usage

1. Copy `Pulumi.production.yaml.example` to `Pulumi.production.yaml` and fill in
   your organization values (`org_id`, `billing_account`, `org_stack_name`).
2. Preview / deploy via the Bazel Pulumi wrapper:

```sh
bazel run //pulumi/examples/go-foundation/2-environments/envs/development:preview
bazel run //pulumi/examples/go-foundation/2-environments/envs/development:up
```

Deploy 0-bootstrap and 1-org first; this stage consumes the 1-org stack's
`tags` output via `org_stack_name`.
