# Network Module

Creates one per-environment Shared-VPC host project under the Network folder. This is the Pulumi Go port of the upstream Terraform foundation's `1-org/modules/network` module (invoked per environment as `module "environment_network"` in `projects.tf`).

The project ID follows the upstream convention `{project_prefix}-{env_code}-svpc`, and the labels/APIs match the upstream shared-vpc-host network module. The 3-networks stage later attaches VPCs, subnets, and Shared-VPC service projects to these host projects.

## Usage

```go
import "foundation-1-org/modules/network"

netOutputs, err := network.New(ctx, "development-network", &network.Args{
    Env:            "development",
    EnvCode:        "d",
    ProjectPrefix:  cfg.ProjectPrefix,
    FolderID:       folders.Network.ID().ToStringOutput(),
    BillingAccount: cfg.BillingAccount,
})
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| Env | The environment name, e.g. `"development"`. | `string` | yes |
| EnvCode | The short environment code, e.g. `"d"`. | `string` | yes |
| ProjectPrefix | Name prefix to use for projects created (upstream `project_prefix`). | `string` | yes |
| FolderID | The Network folder ID the host project is created under. | `pulumi.StringOutput` | yes |
| BillingAccount | The ID of the billing account to associate the project with. | `string` | yes |
| RandomSuffix | Adds a suffix of 4 random characters to the project ID. | `bool` | no |
| ProjectDeletionPolicy | The deletion policy for the project created. | `string` | no |
| DefaultServiceAccount | Default service account handling: `deprivilege`, `keep`, `disable`, or `delete`. | `string` | no |
| Budget | Pre-resolved budget configuration for the project. | `*project.BudgetConfig` | no |

## Outputs

| Name | Description |
|------|-------------|
| ProjectID | The Shared-VPC host project ID. |
| ProjectNumber | The Shared-VPC host project number. |

> Upstream's module carries no README; this one documents the Pulumi port using the same Inputs/Outputs format as the sibling modules.
