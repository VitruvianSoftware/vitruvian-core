# Cloud Asset Inventory Notification

Uses Google Cloud Asset Inventory to create a feed of IAM Policy change events, then processes them to detect when a role (from a preset list) is given to a member (service account, user or group). It then generates an SCC Finding with the member, role, resource where it was granted and the time that it was granted.

This is the Pulumi Go port of the upstream Terraform foundation's `1-org/modules/cai-monitoring` module. It delegates resource creation to the `pkg/cai_monitoring` library component; the Cloud Function source lives in [`function-source/`](function-source/), matching upstream.

The CAI monitoring pipeline works as follows:

1. A Cloud Asset Organization Feed watches for IAM policy changes
2. Changes are published to a Pub/Sub topic
3. A Cloud Function (v2) is triggered by the Pub/Sub messages
4. The function checks for IAM bindings with monitored roles
5. Violations are reported as SCC findings via the SCC Source

## Usage

```go
import "foundation-1-org/modules/cai_monitoring"

caiOutputs, err := cai_monitoring.New(ctx, "cai-monitoring", &cai_monitoring.Args{
    OrgID:         cfg.OrgID,
    DefaultRegion: cfg.DefaultRegion,
    SCCProjectID:  proj.SCCProjectID,
})
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| OrgID | GCP Organization ID. | `string` | yes |
| DefaultRegion | Default location to create resources where applicable (upstream `location`). | `string` | yes |
| SCCProjectID | The project ID where the resources will be created (the SCC notifications project). | `pulumi.StringOutput` | yes |

## Outputs

| Name | Description |
|------|-------------|
| ArtifactRegistryName | Artifact Registry repo that stores the Cloud Function image. |
| AssetFeedName | Organization Asset Feed name. |
| BucketName | Storage bucket where the function source code is. |
| TopicName | Pub/Sub topic for the Asset Feed. |

## Engine adaptations

- The `roles_to_monitor` list is fixed in-module (`caiRolesToMonitor`), matching the upstream default variable value.
- The Cloud Build service account (`cai-monitoring-builder`, upstream `build_service_account`) is created in `envs/shared/sa.go` and referenced here by its derived email.
