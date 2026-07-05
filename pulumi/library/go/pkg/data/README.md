# pkg/data — BigQuery Data Platform

Creates a BigQuery data platform with **raw** and **curated** datasets for data lake architectures.

## Overview

The `DataPlatform` component wraps two [`bigquery.Dataset`](https://www.pulumi.com/registry/packages/gcp/api-docs/bigquery/dataset/) resources:

- **Raw dataset** — Landing zone for raw, unprocessed data (e.g., event streams, API exports)
- **Curated dataset** — Transformed, validated data ready for analytics and reporting

Dataset IDs are parameterized to avoid collisions when deploying multiple `DataPlatform` instances in the same project.

## API Reference

### `DataPlatformArgs`

| Field | Type | Required | Default | Description |
|-------|------|:--------:|---------|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | — | The GCP project ID |
| `Location` | `pulumi.StringInput` | ✅ | — | BigQuery dataset location (e.g., `"US"`, `"EU"`, `"us-central1"`) |
| `RawDatasetID` | `string` | | `"raw_data"` | Dataset ID for the raw data landing zone |
| `CuratedDatasetID` | `string` | | `"curated_data"` | Dataset ID for the curated/transformed data |

### `DataPlatform` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `RawDataset` | `*bigquery.Dataset` | The raw data BigQuery dataset |
| `CuratedDataset` | `*bigquery.Dataset` | The curated data BigQuery dataset |

### Constructor

```go
func NewDataPlatform(ctx *pulumi.Context, name string, args *DataPlatformArgs, opts ...pulumi.ResourceOption) (*DataPlatform, error)
```

## Examples

### Basic Data Platform

```go
dp, err := data.NewDataPlatform(ctx, "analytics", &data.DataPlatformArgs{
    ProjectID: pulumi.String("prj-data"),
    Location:  pulumi.String("US"),
})
// Creates datasets: raw_data, curated_data
```

### Custom Dataset IDs

```go
dp, err := data.NewDataPlatform(ctx, "events", &data.DataPlatformArgs{
    ProjectID:        projectID,
    Location:         pulumi.String("us-central1"),
    RawDatasetID:     "raw_events",
    CuratedDatasetID: "curated_events",
})

ctx.Export("raw_dataset", dp.RawDataset.DatasetId)
ctx.Export("curated_dataset", dp.CuratedDataset.DatasetId)
```

### Multiple Data Platforms in One Project

```go
// Events pipeline
data.NewDataPlatform(ctx, "events", &data.DataPlatformArgs{
    ProjectID:        projectID,
    Location:         pulumi.String("US"),
    RawDatasetID:     "raw_events",
    CuratedDatasetID: "curated_events",
})

// Metrics pipeline
data.NewDataPlatform(ctx, "metrics", &data.DataPlatformArgs{
    ProjectID:        projectID,
    Location:         pulumi.String("US"),
    RawDatasetID:     "raw_metrics",
    CuratedDatasetID: "curated_metrics",
})
```

## Resource Graph

```
pkg:index:DataPlatform ("events")
├── gcp:bigquery:Dataset ("events-raw")
└── gcp:bigquery:Dataset ("events-curated")
```
