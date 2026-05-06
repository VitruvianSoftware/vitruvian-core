# log_export

A Pulumi component for creating GCP log sinks at organization, folder, project, or billing account level.

**Upstream Reference:** [terraform-google-modules/log-export/google](https://registry.terraform.io/modules/terraform-google-modules/log-export/google)

## Overview

Creates log sinks that export filtered logs to destinations like Cloud Storage, Pub/Sub, BigQuery, or Cloud Logging buckets. Supports all four GCP organizational levels.

## API Reference

### LogExportArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `DestinationURI` | `pulumi.StringInput` | ✅ | Destination URI for exported logs |
| `Filter` | `pulumi.StringInput` | | Log filter expression |
| `LogSinkName` | `pulumi.StringInput` | ✅ | Name for the log sink |
| `ParentResourceID` | `pulumi.StringInput` | ✅ | ID of the parent resource (org ID, folder ID, project ID, or billing account) |
| `ResourceType` | `string` | ✅ | `organization`, `folder`, `project`, or `billing_account` |
| `UniqueWriterIdentity` | `bool` | | Create a unique writer identity (project sinks) |
| `IncludeChildren` | `bool` | | Include child resources (org/folder sinks) |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `WriterIdentity` | `pulumi.StringOutput` | Service account for granting destination access |
| `Sink` | `pulumi.Resource` | The created log sink resource |

## Usage

```go
sink, err := log_export.NewLogExport(ctx, "audit-sink", &log_export.LogExportArgs{
    DestinationURI:   pulumi.String("storage.googleapis.com/audit-logs-bucket"),
    Filter:           pulumi.String("logName:\"activity\""),
    LogSinkName:      pulumi.String("org-audit-sink"),
    ParentResourceID: pulumi.String("123456789"),
    ResourceType:     "organization",
    IncludeChildren:  true,
})
```
