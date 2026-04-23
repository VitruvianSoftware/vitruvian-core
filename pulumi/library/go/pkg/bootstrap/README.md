# pkg/bootstrap — Foundation Bootstrap

Creates the seed infrastructure required by a GCP foundation, mirroring the functionality of the `terraform-google-modules/terraform-google-bootstrap` module.

## Overview

The `Bootstrap` component bundles the following resources to prepare a foundation environment:

- **Seed Project**: Created via `pkg/project`, with lien protection and default service account management.
- **KMS Key Ring & Crypto Key**: For state bucket encryption.
- **State Bucket**: GCS bucket with uniform bucket-level access, versioning, and KMS encryption.
- **Org Policy**: Allows cross-project service account usage on the seed project.
- **State Bucket IAM**: Grants `roles/storage.admin` to specified administrative groups or service accounts.

## API Reference

### `BootstrapArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `OrgID` | `string` | ✅ | The GCP organization ID |
| `BillingAccount` | `string` | ✅ | Billing account ID |
| `FolderID` | `pulumi.StringInput` | | Optional folder ID to place the seed project |
| `ProjectPrefix` | `string` | | Prefix for the seed project (e.g., `prj`) |
| `DefaultRegion` | `string` | | Region for KMS and GCS resources |
| `RandomSuffix` | `bool` | | Append a 4-char random hex suffix to the project ID and bucket name |
| `ActivateApis` | `[]string` | | APIs to enable on the seed project |
| `EncryptStateBucket` | `*bool` | | Enable encryption via KMS (defaults to true) |
| `StateBucketIAMMembers`| `[]pulumi.StringInput`| | IAM members granted `roles/storage.admin` on the bucket |

### `Bootstrap` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `SeedProject` | `*project.Project` | The underlying project component resource |
| `SeedProjectID` | `pulumi.StringOutput` | The seed project's GCP project ID |
| `StateBucketName`| `pulumi.StringOutput` | The name of the resulting GCS state bucket |
| `KMSKeyID` | `pulumi.StringOutput` | The fully qualified ID of the KMS crypto key |
| `KMSKeyRingID` | `pulumi.StringOutput` | The fully qualified ID of the KMS key ring |

## Examples

### Basic Bootstrap Execution

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/bootstrap"

seed, err := bootstrap.NewBootstrap(ctx, "foundation-seed", &bootstrap.BootstrapArgs{
    OrgID:          "1234567890",
    BillingAccount: "XXXXXX-XXXXXX-XXXXXX",
    ProjectPrefix:  "prj",
    DefaultRegion:  "us-central1",
    StateBucketIAMMembers: []pulumi.StringInput{
        pulumi.String("group:gcp-organization-admins@example.com"),
    },
})
```
