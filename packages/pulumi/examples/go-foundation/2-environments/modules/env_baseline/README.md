# env_baseline

Reusable per-environment baseline module — the Pulumi/Go port of upstream
[terraform-example-foundation `2-environments/modules/env_baseline`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/2-environments/modules/env_baseline).

For each environment it creates:

- the environment folder (`fldr-{environment}`) under the foundation parent, with
  the `environment_{env}` tag value from the 1-org stage bound to it
- `prj-{env_code}-kms` — the environment-level Cloud KMS project
- `prj-{env_code}-secrets` — the environment-level Secret Manager project
- an optional [Assured Workload](https://cloud.google.com/assured-workloads)

## File layout

The package mirrors upstream's file-per-concern layout:

| File | Upstream analog | Contents |
|------|-----------------|----------|
| `env_baseline.go` | `main.tf` (module wiring) | package doc + `Deploy` entrypoint orchestrating the per-concern files |
| `folders.go` | `folders.tf` | environment folder + environment tag binding |
| `kms.go` | `kms.tf` | environment KMS project |
| `secrets.go` | `secrets.tf` | environment Secrets project |
| `assured_workload.go` | `assured_workload.tf` | optional Assured Workload |
| `remote.go` | `remote.tf` | cross-stage state consumption (environment tag value from the 1-org `tags` output) |
| `config.go` | `variables.tf` | `Args` (module inputs) + budget defaults |
| `outputs.go` | `outputs.tf` | `Result` (module outputs) |

Engine adaptations (Pulumi instead of Terraform): provider pins live in the
module's `go.mod` instead of `versions.tf`, and upstream's
`terraform_remote_state` reads (`remote.tf`) arrive as module inputs — scalar
identifiers from stack config, the 1-org `tags` map as a StackReference output
wired by the env leaf.

## Inputs (`Args`)

| Name | Description | Default (applied by the leaf / helpers) |
|------|-------------|------------------------------------------|
| `Env` | The environment to prepare (upstream `env`, e.g. `development`) | n/a (required) |
| `EnvCode` | Short environment code (upstream `environment_code`, e.g. `d`) | n/a (required) |
| `Parent` | Parent of the environment folder — `organizations/<id>` or `folders/<id>` (upstream `remote.tf` `local.parent`) | n/a (required) |
| `OrgID` | Organization ID (used by the Assured Workload) | n/a (required) |
| `BillingAccount` | Billing account attached to the environment projects | n/a (required) |
| `ProjectPrefix` | Prefix for project IDs | `prj` |
| `FolderPrefix` | Prefix for folder display names | `fldr` |
| `RandomSuffix` | Append a random suffix to project IDs | `true` |
| `DefaultServiceAccount` | Default compute SA handling (`deprivilege`, `delete`, `disable`, `keep`) | `deprivilege` |
| `ProjectDeletionPolicy` | Deletion policy for the projects created | `PREVENT` |
| `FolderDeletionProtection` | Prevent destroying/recreating the environment folder | `true` |
| `ProjectBudget` | Per-project budget configuration (upstream `project_budget`); `SharedNetwork` retained for schema parity, no-op here | amount `1000`, alerts `[1.2]`, `FORECASTED_SPEND` |
| `ApiPropagationSeconds` | Cold-deploy wait for freshly-enabled project APIs before dependents use them | `120` (leaf default) |
| `AssuredWorkload` | Assured Workload configuration (upstream `assured_workload_configuration`) | disabled |
| `Tags` | 1-org `tags` output map (StackReference output); may be nil | nil (skips tag binding) |

## Outputs (`Result`)

| Name | Description |
|------|-------------|
| `FolderName` | Environment folder resource name (`folders/<id>`) |
| `FolderID` | Environment folder ID |
| `KMSProjectID` | Project for environment Cloud Key Management Service (KMS) |
| `KMSProjectNumber` | Project number for environment KMS |
| `SecretsProjectID` | Project for environment secrets |
| `AssuredWorkloadID` | Assured Workload ID (empty when disabled) |
| `AssuredWorkloadResources` | Resources associated with the Assured Workload |

## Usage

```go
import "foundation-2-environments/modules/env_baseline"

res, err := env_baseline.Deploy(ctx, &env_baseline.Args{
    Env:            "development",
    EnvCode:        "d",
    Parent:         "organizations/123456789012",
    OrgID:          "123456789012",
    BillingAccount: "XXXXXX-XXXXXX-XXXXXX",
    // ... remaining inputs from stack config (see envs/<env>/config.go)
})
```

The three env leaves (`../../envs/{development,nonproduction,production}`) are
the only callers; each pins its environment identity and passes stack config
through unchanged.
