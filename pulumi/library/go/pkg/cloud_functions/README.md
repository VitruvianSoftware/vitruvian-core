# cloud_functions

A Pulumi component for deploying Cloud Functions (2nd gen) with optional event triggers.

**Upstream Reference:** [terraform-google-modules/event-function/google](https://registry.terraform.io/modules/terraform-google-modules/event-function/google)

## Overview

Creates a Cloud Function v2 with:
- Source code from a GCS bucket
- Configurable runtime, entry point, and memory
- Optional Pub/Sub or Eventarc event triggers
- Custom labels, environment variables, and service account

## API Reference

### CloudFunctionArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Region` | `string` | ✅ | GCP region |
| `Name` | `string` | ✅ | Function name |
| `EntryPoint` | `string` | ✅ | Function entry point |
| `SourceBucket` | `pulumi.StringInput` | ✅ | GCS bucket containing source |
| `SourceObject` | `pulumi.StringInput` | ✅ | GCS object key for source |
| `Runtime` | `string` | | Runtime (default: `go121`) |
| `AvailableMemory` | `string` | | Memory allocation (default: `256M`) |
| `Timeout` | `int` | | Timeout in seconds (default: 60) |
| `EventTriggerType` | `string` | | Eventarc trigger type |
| `ServiceAccountEmail` | `pulumi.StringInput` | | Service account email |
| `Labels` | `map[string]string` | | Resource labels |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Function` | `*cloudfunctionsv2.Function` | The created Cloud Function |

## Usage

```go
fn, err := cloud_functions.NewCloudFunction(ctx, "processor", &cloud_functions.CloudFunctionArgs{
    ProjectID:        pulumi.String("my-project"),
    Region:           "us-central1",
    Name:             "event-processor",
    Runtime:          "python310",
    EntryPoint:       "handle_event",
    SourceBucket:     pulumi.String("my-source-bucket"),
    SourceObject:     pulumi.String("processor-v1.zip"),
    EventTriggerType: "google.cloud.pubsub.topic.v1.messagePublished",
    AvailableMemory:  "512M",
})
```
