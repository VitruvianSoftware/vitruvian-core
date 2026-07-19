# confidential_space

Deploys the Confidential Space workload for an environment project: a Workload
Identity Pool, an OIDC attestation-verifier provider, the workload SA IAM
binding, and a Confidential VM running the `confidential-space` OS image with
the workload container referenced by digest. Mirrors upstream
`terraform-example-foundation/5-app-infra/modules/confidential_space`.

## Engine adaptations (Pulumi port)

- Upstream's `remote_state_bucket` / `terraform_remote_state` reads have no
  equivalent here: the calling env leaf resolves the 4-projects Stack
  References itself (see the leaf's `remote.go`) and passes resolved values in.
  In particular `CloudBuildProjectID` replaces upstream's
  `bootstrap_cloudbuild_project_id` read from the `business_unit_shared`
  workspace — our WIF port has no Cloud Build project chain, so the BU's
  app-infra pipeline project (4-projects `business_unit_1/shared`,
  `infra_pipeline_project_id` export) hosts the workload image registry
  (documented engine-difference workaround in the leaf's `remote.go`).
- `ProjectNumber` comes from the 4-projects stack export — not a runtime
  `LookupProject` call, which would break previews.
- Upstream's `time_sleep.wait_workload_pool_propagation` is preserved as a
  `pulumiverse/time` Sleep (60s) gating the IAM binding and template.
- Upstream's `versions.tf` maps to the shared [`../go.mod`](../go.mod).

## File structure (upstream mapping)

| File           | Mirrors upstream | Purpose                                       |
| -------------- | ---------------- | ---------------------------------------------- |
| `main.go`      | `main.tf`        | Resource logic (`DeployConfidentialSpace`)     |
| `variables.go` | `variables.tf`   | Input surface (`ConfidentialSpaceArgs`)        |
| `outputs.go`   | `outputs.tf`     | Output surface (`ConfidentialSpaceResult`)     |

## Inputs (`ConfidentialSpaceArgs`)

| Name                       | Description                                                              | Required | Default |
| -------------------------- | ------------------------------------------------------------------------ | :------: | ------- |
| `Env`                      | The environment the workload belongs to                                  |   yes    | n/a     |
| `BusinessUnit`             | The business unit code (e.g. `bu1`)                                      |   yes    | n/a     |
| `ProjectID`                | Target project (resolved from the 4-projects Stack Reference)            |   yes    | n/a     |
| `ProjectNumber`            | Target project number (from the 4-projects stack export)                 |   yes    | n/a     |
| `Region`                   | Region to deploy into                                                    |   yes    | n/a     |
| `SubnetworkSelfLink`       | Shared-VPC subnet self link                                              |   yes    | n/a     |
| `WorkloadSAEmail`          | Confidential Space workload service account email                        |   yes    | n/a     |
| `ConfidentialImageDigest`  | SHA256 digest of the attested workload container image                   |   yes    | n/a     |
| `ConfidentialMachineType`  | Confidential VM machine type (e.g. `n2d-standard-2`)                     |   yes    | n/a     |
| `ConfidentialInstanceType` | Confidential computing technology (e.g. `SEV`)                           |   yes    | n/a     |
| `CpuPlatform`              | Minimum CPU platform (e.g. `AMD Milan`)                                  |   yes    | n/a     |
| `CloudBuildProjectID`      | Project whose Artifact Registry hosts the workload image                 |   yes    | n/a     |

## Outputs (`ConfidentialSpaceResult`)

| Name                     | Description                                     |
| ------------------------ | ----------------------------------------------- |
| `InstanceSelfLink`       | Self link of the Confidential VM                |
| `InstanceName`           | Name of the Confidential VM                     |
| `InstanceZone`           | Zone of the Confidential VM                     |
| `WorkloadPoolID`         | Workload Identity Pool ID                       |
| `WorkloadPoolProviderID` | Workload Identity Pool Provider ID              |
