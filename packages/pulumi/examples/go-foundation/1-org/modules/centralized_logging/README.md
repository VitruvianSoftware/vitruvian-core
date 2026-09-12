# Centralized Logging Module

This module handles logging configuration enabling the organization (or a parent folder) to send logs to multiple destinations: a [GCS bucket](https://cloud.google.com/logging/docs/export/using_exported_logs#gcs-overview), [Pub/Sub](https://cloud.google.com/logging/docs/export/using_exported_logs#pubsub-overview), and a [Log Bucket](https://cloud.google.com/logging/docs/routing/overview#buckets) with [Log Analytics](https://cloud.google.com/logging/docs/log-analytics#analytics), plus optional billing-account sinks.

This is the Pulumi Go port of the upstream Terraform foundation's `1-org/modules/centralized-logging` module. It delegates resource creation to the `pkg/centralized_logging` library component, which handles:

- Dynamic org/folder sink routing based on `ParentType`
- Destination resource creation (storage, pubsub, log bucket)
- IAM grants for each sink writer identity
- Billing account sinks (when enabled)
- Internal project sink (prevents the audit project from being a blind spot)

## Usage

```go
import "foundation-1-org/modules/centralized_logging"

logOutputs, err := centralized_logging.New(ctx, "logs-export", &centralized_logging.Args{
    ParentID:               cfg.ParentID,
    ParentType:             cfg.ParentType,
    BillingAccount:         cfg.BillingAccount,
    DefaultRegion:          cfg.DefaultRegion,
    AuditProjectID:         proj.AuditLogsProjectID,
    BillingExportProjectID: proj.BillingExportProjectID,
})
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| ParentID | The org ID or folder ID whose logs are exported. | `string` | yes |
| ParentType | Resource type of the export parent: `"organization"` or `"folder"`. | `string` | yes |
| BillingAccount | Billing Account ID used for billing-account-level sinks. | `string` | yes |
| EnableBillingAccountSink | If true, log router sinks are created for the billing account. | `bool` | no |
| LogExportStorageLocation | The location of the storage bucket used to export logs. | `string` | yes |
| LogExportStorageForceDestroy | If true, delete all bucket contents when destroying the bucket. | `bool` | no |
| LogExportStorageVersioning | Toggles bucket versioning on the log export bucket. | `bool` | no |
| RetentionEnabled | Whether a retention policy is enabled on the bucket. | `bool` | no |
| RetentionLocked | Whether the bucket retention policy is locked. | `bool` | no |
| RetentionDays | The period of days for log retention. | `int` | no |
| DefaultRegion | Location for the project log bucket / linked dataset. | `string` | yes |
| BillingExportDatasetLocation | The location of the BigQuery dataset for billing data export. | `string` | yes |
| AuditProjectID | The audit-logs project that hosts the logging destinations. | `pulumi.StringOutput` | yes |
| BillingExportProjectID | The project that hosts the billing export BigQuery dataset. | `pulumi.StringOutput` | yes |
| BillingExportApisReady | Gates the billing dataset on the billing-export project's enabled APIs. | `pulumi.Resource` | no |

## Outputs

| Name | Description |
|------|-------------|
| StorageBucketName | The storage bucket for destination of log exports. |
| PubSubTopicName | The Pub/Sub topic for destination of log exports. |
| LogBucketName | The resource name for the Log Bucket created for the project destination. |
| LinkedDatasetName | The resource name of the Log Bucket linked BigQuery dataset. |
| BillingSinkNames | Map of log sink names with billing suffix. |
| LastResource | The last resource created; used for dependency ordering (policies wait for sinks). |
