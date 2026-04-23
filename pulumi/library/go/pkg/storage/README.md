# pkg/storage — Cloud Storage

Provides foundational storage components, mirroring the functionality of the `terraform-google-modules/cloud-storage/google//modules/simple_bucket` module.

## Overview

The `SimpleBucket` component creates a Google Cloud Storage bucket with sane foundation defaults enforced out-of-the-box:

- Uniform Bucket-Level Access enabled by default
- Public Access Prevention strictly enforced
- Optional encryption via KMS keys
- Optional object versioning
- Key-value labels support
- Parameterized force-destroy safety rails

## API Reference

### `SimpleBucketArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `Name` | `pulumi.StringInput` | ✅ | Globally unique bucket name |
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Location` | `pulumi.StringInput` | ✅ | GCS location (region or multi-region) |
| `ForceDestroy` | `pulumi.BoolInput` | | Allow deletion of non-empty buckets |
| `Encryption` | `*storage.BucketEncryptionArgs` | | KMS encryption configuration |
| `Versioning` | `*bool` | | Enable object versioning |
| `Labels` | `pulumi.StringMapInput` | | Key-value labels for the bucket |

### `SimpleBucket` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `Bucket` | `*storage.Bucket` | The underlying GCS bucket resource |

## Examples

### Basic Bucket

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/storage"

bucket, err := storage.NewSimpleBucket(ctx, "projects-state", &storage.SimpleBucketArgs{
    Name:         pulumi.Sprintf("%s-gcp-projects-tfstate", seedProjectID),
    ProjectID:    seedProjectID,
    Location:     pulumi.String("us-central1"),
    ForceDestroy: pulumi.Bool(false),
    Encryption: &gcsStorage.BucketEncryptionArgs{
        DefaultKmsKeyName: kmsKeyID,
    },
})
```
