# pkg/logging

Reusable Pulumi components for centralized log export infrastructure.

This package mirrors the upstream Terraform modules used by the Google Cloud Foundation:

| Pulumi Component | Upstream Terraform Module |
|---|---|
| `LogExport` | `terraform-google-modules/log-export/google` |
| `CentralizedLogging` | `modules/centralized-logging` (in-repo) |

## LogExport

Low-level component that creates a single log sink. Supports all four GCP sink types based on `ResourceType`:

- `"organization"` → `google_logging_organization_sink`
- `"folder"` → `google_logging_folder_sink`
- `"project"` → `google_logging_project_sink`
- `"billing_account"` → `google_logging_billing_account_sink`

### Usage

```go
sink, err := logging.NewLogExport(ctx, "my-sink", &logging.LogExportArgs{
    DestinationURI:   pulumi.String("storage.googleapis.com/my-bucket"),
    Filter:           pulumi.String("logName: /logs/cloudaudit"),
    LogSinkName:      pulumi.String("sk-audit-logs"),
    ParentResourceID: pulumi.String("123456789"),
    ResourceType:     "organization",
    IncludeChildren:  true,
})
// Use sink.WriterIdentity to grant IAM on the destination
```

## CentralizedLogging

High-level orchestrator that creates a complete centralized logging infrastructure with:

- **Destination resources**: Storage bucket, Pub/Sub topic, Logging project bucket with linked BigQuery dataset
- **Log sinks**: One per resource × destination combination (using `LogExport`)
- **Billing account sinks**: Optional, to all configured destinations
- **IAM grants**: Each sink writer identity gets appropriate roles on its destination
- **Internal project sink**: Captures the logging project's own logs (prevents blind spots)

### Usage

```go
cl, err := logging.NewCentralizedLogging(ctx, "logs-export", &logging.CentralizedLoggingArgs{
    Resources:                   map[string]string{"resource": orgID},
    ResourceType:                "organization", // or "folder"
    LoggingDestinationProjectID: auditProjectID,
    BillingAccount:              "AAAAAA-BBBBBB-CCCCCC",
    EnableBillingAccountSink:    true,
    StorageOptions: &logging.StorageOptions{
        LoggingSinkName:   "sk-c-logging-bkt",
        LoggingSinkFilter: logsFilter,
        Location:          "US",
        Versioning:        true,
    },
    PubSubOptions: &logging.PubSubOptions{
        LoggingSinkName:   "sk-c-logging-pub",
        LoggingSinkFilter: logsFilter,
        CreateSubscriber:  true,
    },
    ProjectOptions: &logging.ProjectOptions{
        LoggingSinkName:          "sk-c-logging-prj",
        LoggingSinkFilter:        logsFilter,
        LogBucketID:              "AggregatedLogs",
        Location:                 "us-central1",
        EnableAnalytics:          true,
        LinkedDatasetID:          "ds_c_prj_aggregated_logs_analytics",
        LinkedDatasetDescription: "BigQuery Dataset for log analytics",
    },
})
```
