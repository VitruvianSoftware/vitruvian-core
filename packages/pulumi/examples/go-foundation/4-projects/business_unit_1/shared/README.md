# 4-projects / business_unit_1 / shared

The business unit's **shared** leaf, the Pulumi port of upstream
terraform-example-foundation
[`4-projects/business_unit_1/shared`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/4-projects/business_unit_1/shared):
the once-per-BU, environment-independent resources — the app-infra pipeline
project under the 1-org COMMON folder (`environment=common` / `env_code=c`),
deployed via [`modules/infra_pipelines`](../../modules/infra_pipelines). The
per-env business-unit project sets live in the sibling
`{development,nonproduction,production}` leaves.

Upstream's shared workspace deploys the pipeline via `modules/single_project` +
`modules/infra_pipelines` (Cloud Build). Our port calls
`modules/infra_pipelines` directly — under the GitHub-Actions-WIF deploy model
it owns the pipeline project itself; see the module doc for the
engine-difference note.

## File layout (upstream mapping)

| File | Upstream analogue | Contents |
|------|-------------------|----------|
| `main.go` | `example_infra_pipeline.tf` | Env pin (common/c), pipeline deploy, orchestration |
| `config.go` | `variables.tf` (+ `*.auto.tfvars`) | `SharedConfig`, config loader, label/budget helpers |
| `remote.go` | `remote.tf` | Cross-stage StackReference (org COMMON folder) |
| `outputs.go` | `outputs.tf` | Stack exports |
| `Pulumi.yaml`, `go.mod` | `backend.tf`, `versions.tf` | Engine adaptation: Pulumi project + Go module |
| `Pulumi.production.yaml.example` | `*.auto.example.tfvars` | Example stack configuration |

## Inputs

| Name | Description | Default | Required |
|------|-------------|---------|:--------:|
| `business_code` | The business code (ex. `bu1`) | n/a | yes |
| `billing_account` | The ID of the billing account to associate projects with | n/a | yes |
| `org_stack_name` | StackReference to the 1-org stack | n/a | yes |
| `project_prefix` | Name prefix to use for projects created | `prj` | no |
| `random_suffix` | Append a random suffix to project ids | `true` | no |
| `billing_code` | Label: chargeback code | `1234` | no |
| `primary_contact` | Label: primary email contact | `example@example.com` | no |
| `secondary_contact` | Label: secondary email contact | `example2@example.com` | no |
| `budget_amount` | Budget amount per project | `1000` | no |
| `budget_alert_percents` | Budget alert thresholds | `[1.2]` | no |
| `budget_spend_basis` | `CURRENT_SPEND` or `FORECASTED_SPEND` | `FORECASTED_SPEND` | no |
| `infra_pipeline_enabled` | Deploy the app-infra pipeline project | `true` | no |
| `api_propagation_seconds` | Post-API-enable propagation wait (0 disables) | `120` | no |
| `region` | Default region (exported) | `us-central1` | no |

## Outputs

| Name | Description |
|------|-------------|
| `infra_pipeline_project_id` | The BU's app-infra pipeline project id (upstream's `cloudbuild_project_id` analogue) |
| `default_region` | The default region |
