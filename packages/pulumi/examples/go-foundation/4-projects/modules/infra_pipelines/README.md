# modules / infra_pipelines

The app-infra CI/CD home for a business unit, the Pulumi port of upstream
terraform-example-foundation
[`4-projects/modules/infra_pipelines`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/4-projects/modules/infra_pipelines),
created ONCE per BU from the [`business_unit_1/shared`](../../business_unit_1/shared)
leaf (upstream's `shared` workspace, `environment=common`).

Engine-difference note (documented Pulumi workaround, per the port policy):
upstream's module receives an existing `cloudbuild_project_id` and fills it
with Cloud Build triggers, CSRs, per-repo SAs, and state/log/artifact buckets.
Our foundation deploys application infrastructure from GitHub Actions via
Workload Identity Federation instead of Cloud Build, so this module owns the
pipeline PROJECT (Cloud Build/Artifact Registry/IAM APIs enabled, WIF-ready via
`iamcredentials`) and none of the Cloud Build machinery. The faithful Cloud
Build port is kept as the build-tagged `example_infra_pipelines.go`
(`go build -tags example`) in the go-foundation reference tree.

## File layout (upstream mapping)

| File | Upstream analogue | Contents |
|------|-------------------|----------|
| `main.go` | `main.tf` | `Deploy` |
| `variables.go` | `variables.tf` | `Args` (WIF-model subset) |
| `outputs.go` | `outputs.tf` | `Result` |
| `example_infra_pipelines.go` | `main.tf` (Cloud Build machinery) | Build-tagged faithful Cloud Build port (example tree only) |
| — (shared `../go.mod`) | `versions.tf` | Engine adaptation |

## Inputs (`Args`)

| Name | Description |
|------|-------------|
| `ProjectPrefix`, `BusinessCode` | Form the project id `{prefix}-c-{business_code}-infra-pipeline` |
| `BillingAccount` | Billing account |
| `RandomSuffix` | Append the project-factory random suffix |
| `CommonFolderID` | The 1-org COMMON folder (upstream `local.common_folder_name`) |
| `Labels` | COMMON-folder labels computed by the shared leaf |
| `Budget` | Budget configuration (upstream `project_budget`) |
| `ApiPropagationSeconds` | Post-API-enable propagation wait (0 disables) |

## Outputs (`Result`)

| Name | Description |
|------|-------------|
| `ProjectID` | The pipeline project id (upstream's `cloudbuild_project_id` analogue) |
