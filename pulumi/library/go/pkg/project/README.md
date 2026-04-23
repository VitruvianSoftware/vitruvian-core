# pkg/project — Project Factory

Creates GCP projects with API enablement, billing association, and automatic default-VPC suppression.

## Overview

The `Project` component wraps [`organizations.Project`](https://www.pulumi.com/registry/packages/gcp/api-docs/organizations/project/) and a dynamic set of [`projects.Service`](https://www.pulumi.com/registry/packages/gcp/api-docs/projects/service/) resources. APIs to enable are specified as a plain `[]string` slice — not as Pulumi inputs — so that each API service is a first-class resource in the Pulumi state graph.

### Security Defaults

- **`AutoCreateNetwork`** defaults to `false`. The GCP default network comes with overly permissive firewall rules (`allow-internal`, `allow-ssh`, `allow-rdp`, `allow-icmp`). Suppressing it ensures all network configuration is explicit.
- **`DisableOnDestroy`** is `false` for API services, preventing orphaned APIs in destroyed projects.

## API Reference

### `ProjectArgs`

| Field | Type | Required | Default | Description |
|-------|------|:--------:|---------|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | — | The GCP project ID (must be globally unique) |
| `Name` | `pulumi.StringInput` | ✅ | — | The display name of the project |
| `FolderID` | `pulumi.StringInput` | ✅ | — | The folder ID to create the project under |
| `BillingAccount` | `pulumi.StringInput` | ✅ | — | The billing account to associate with the project |
| `ActivateApis` | `[]string` | | `nil` | List of APIs to enable (plain Go slice) |
| `AutoCreateNetwork` | `pulumi.BoolPtrInput` | | `false` | Whether to create the default network |
| `Labels` | `pulumi.StringMapInput` | | `nil` | Labels to apply to the project |
| `DeletionPolicy` | `pulumi.StringPtrInput` | | `nil` | Deletion policy (`DELETE`, `ABANDON`, `PREVENT`) |
| `RandomProjectID` | `bool` | | `false` | Append a 4-char random hex suffix to project ID |

### `Project` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `Project` | `*organizations.Project` | The underlying GCP project resource |
| `Services` | `[]*projects.Service` | The enabled API service resources |

### Constructor

```go
func NewProject(ctx *pulumi.Context, name string, args *ProjectArgs, opts ...pulumi.ResourceOption) (*Project, error)
```

## Examples

### Basic Project

```go
p, err := project.NewProject(ctx, "my-project", &project.ProjectArgs{
    ProjectID:      pulumi.String("prj-my-app"),
    Name:           pulumi.String("My Application"),
    FolderID:       pulumi.String("123456789"),
    BillingAccount: pulumi.String("XXXXXX-XXXXXX-XXXXXX"),
})
```

### Project with APIs

```go
p, err := project.NewProject(ctx, "data-project", &project.ProjectArgs{
    ProjectID:      pulumi.String("prj-data-platform"),
    Name:           pulumi.String("Data Platform"),
    FolderID:       envFolderID, // pulumi.StringOutput from another resource
    BillingAccount: pulumi.String("XXXXXX-XXXXXX-XXXXXX"),
    ActivateApis: []string{
        "bigquery.googleapis.com",
        "storage.googleapis.com",
        "cloudkms.googleapis.com",
    },
    Labels: pulumi.StringMap{
        "environment": pulumi.String("production"),
        "team":        pulumi.String("data-eng"),
    },
})
```

### Project with Random Suffix

When `RandomProjectID` is `true`, a 4-character hex suffix is appended to the
project ID (e.g., `prj-b-seed` → `prj-b-seed-a1b2`). The suffix is generated
once via a `random.RandomId` resource and persisted in Pulumi state. This
matches the upstream Terraform Example Foundation's `random_project_id`
behavior and prevents project ID collisions across multiple deployments.

```go
p, err := project.NewProject(ctx, "seed-project", &project.ProjectArgs{
    ProjectID:       pulumi.String("prj-b-seed"),
    Name:            pulumi.String("prj-b-seed"),
    FolderID:        folderID,
    BillingAccount:  pulumi.String("XXXXXX-XXXXXX-XXXXXX"),
    RandomProjectID: true,
    ActivateApis: []string{
        "cloudkms.googleapis.com",
        "compute.googleapis.com",
    },
})
// p.Project.ProjectId will be something like "prj-b-seed-f3c7"
```

### Referencing Project Outputs

```go
// Use the project ID as input to other resources
ctx.Export("project_id", p.Project.ProjectId)
ctx.Export("project_number", p.Project.Number)
```

## Resource Graph

```
pkg:index:Project ("data-project")
├── gcp:organizations:Project ("data-project")
├── gcp:projects:Service ("data-project-bigquery.googleapis.com")
├── gcp:projects:Service ("data-project-storage.googleapis.com")
└── gcp:projects:Service ("data-project-cloudkms.googleapis.com")
```

When `RandomProjectID` is `true`, a `random:index:RandomId` resource is added:

```
pkg:index:Project ("seed-project")
├── random:index:RandomId ("seed-project-suffix")
├── gcp:organizations:Project ("seed-project")
├── gcp:projects:Service ("seed-project-cloudkms.googleapis.com")
└── gcp:projects:Service ("seed-project-compute.googleapis.com")
```
