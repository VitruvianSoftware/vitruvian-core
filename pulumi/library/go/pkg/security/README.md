# Security Components

Reusable Pulumi components for GCP security infrastructure, mirroring local modules from the upstream [Google Terraform Example Foundation](https://github.com/terraform-google-modules/terraform-example-foundation).

## Components

- **`CAIMonitoring`** (component): Mirrors `terraform-example-foundation/1-org/modules/cai-monitoring`. Deploys a Cloud Asset Inventory monitoring pipeline that watches for privileged IAM role grants across an organization and reports violations as Security Command Center findings.

## API Reference

### `CAIMonitoringArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `OrgID` | `pulumi.StringInput` | ✅ | GCP Organization ID to monitor |
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project where monitoring resources are created |
| `Location` | `string` | | GCP region (defaults to `us-central1`) |
| `BuildServiceAccount` | `pulumi.StringInput` | ✅ | Fully-qualified SA name for Cloud Build (`projects/<id>/serviceAccounts/<email>`) |
| `FunctionSourcePath` | `string` | ✅ | Local path to the Cloud Function source directory |
| `RolesToMonitor` | `[]string` | | IAM roles that trigger SCC findings (defaults to 5 high-privilege roles) |
| `EncryptionKey` | `string` | | KMS key resource name for CMEK encryption. Empty = no CMEK |
| `Labels` | `map[string]string` | | Labels applied to supporting resources |

### Default Monitored Roles

When `RolesToMonitor` is not specified, the component monitors:

| Role | Reason |
|------|--------|
| `roles/owner` | Full project control |
| `roles/editor` | Broad write access |
| `roles/resourcemanager.organizationAdmin` | Org-level admin |
| `roles/compute.networkAdmin` | Network infrastructure control |
| `roles/compute.orgFirewallPolicyAdmin` | Org firewall policy control |

### `CAIMonitoring` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `ArtifactRegistryName` | `pulumi.StringOutput` | Artifact Registry repository name |
| `BucketName` | `pulumi.StringOutput` | Cloud Storage bucket for function source |
| `AssetFeedName` | `pulumi.StringOutput` | Cloud Asset Organization Feed name |
| `TopicName` | `pulumi.StringOutput` | Pub/Sub topic name |
| `SCCSourceName` | `pulumi.StringOutput` | SCC v2 Organization Source name |

## Usage

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/security"

cai, err := security.NewCAIMonitoring(ctx, "cai-monitoring", &security.CAIMonitoringArgs{
    OrgID:               pulumi.String("123456789"),
    ProjectID:           sccProjectID,
    Location:            "us-central1",
    BuildServiceAccount: builderSAEmail,
    FunctionSourcePath:  "./cai-monitoring-function",
})
```

### With CMEK Encryption

```go
cai, err := security.NewCAIMonitoring(ctx, "cai-monitoring", &security.CAIMonitoringArgs{
    OrgID:               pulumi.String("123456789"),
    ProjectID:           sccProjectID,
    BuildServiceAccount: builderSAEmail,
    FunctionSourcePath:  "./cai-monitoring-function",
    EncryptionKey:       "projects/my-kms/locations/us/keyRings/ring/cryptoKeys/key",
})
```

### With Custom Roles

```go
cai, err := security.NewCAIMonitoring(ctx, "cai-monitoring", &security.CAIMonitoringArgs{
    OrgID:               pulumi.String("123456789"),
    ProjectID:           sccProjectID,
    BuildServiceAccount: builderSAEmail,
    FunctionSourcePath:  "./cai-monitoring-function",
    RolesToMonitor: []string{
        "roles/owner",
        "roles/editor",
        "roles/iam.serviceAccountTokenCreator",
    },
})
```

## Prerequisites

The Cloud Function source code directory must exist at the path specified by `FunctionSourcePath`. The upstream provides this at `1-org/modules/cai-monitoring/function-source/` and it should be copied to the consuming stage's directory (e.g., `1-org/cai-monitoring-function/`).

The `BuildServiceAccount` must have the following project-level roles:
- `roles/logging.logWriter`
- `roles/storage.objectViewer`
- `roles/artifactregistry.writer`

These are typically granted separately in the IAM configuration (see `iam.go` section 11 in the foundation).
