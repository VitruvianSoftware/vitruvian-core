# modules / single_project

Wrapper around the project-factory library for single project creation, the
Pulumi port of upstream terraform-example-foundation
[`4-projects/modules/single_project`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/4-projects/modules/single_project):
the leaf building block that every BU project type (SVPC-attached, floating,
peering, confidential-space) is created from.

It is a PLAIN factory function (not a ComponentResource): `New` calls
`project.NewProject` with the caller-supplied logical name unchanged, so the
resulting resource URN is byte-identical to the pre-refactor inline call.

## File layout (upstream mapping)

| File | Upstream analogue | Contents |
|------|-------------------|----------|
| `main.go` | `main.tf` | `New` |
| `variables.go` | `variables.tf` | `Args` |
| `outputs.go` | `outputs.tf` | `Result` |
| — (shared `../go.mod`) | `versions.tf` | Engine adaptation |

## Inputs (`Args`)

| Name | Description |
|------|-------------|
| `ProjectID` | Project id; doubles as the display name (upstream `project_suffix` composition happens at the call site) |
| `FolderID` | Parent folder |
| `BillingAccount` | Billing account |
| `RandomProjectID` | Append the project-factory random suffix |
| `Labels` | Project labels (upstream `single_project` label block) |
| `Budget` | Budget configuration (upstream `project_budget`) |
| `ActivateApis` | APIs to enable (upstream `activate_apis`) |
| `DefaultServiceAccount` | Default compute SA posture (`disable`, matching upstream) |
| `ApiPropagationSeconds` | Post-API-enable propagation wait (0 disables) |

## Outputs (`Result`)

| Name | Description |
|------|-------------|
| `Project` | Raw project-factory handle (for attaches / CMEK / peering) |
| `ProjectID` | Project id (upstream `project_id`) |
| `ProjectNumber` | Project number (upstream `project_number`) |
| `ApisReadyProjectID` | Project id gated on the API-propagation wait (data dependency for library components) |
