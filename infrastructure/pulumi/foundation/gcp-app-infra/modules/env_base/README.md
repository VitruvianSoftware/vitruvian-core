# env_base

Deploys the standard Compute Engine workload for an environment project: a
dedicated service account, an instance template, and a Compute Instance on the
shared-VPC subnet. Mirrors upstream
`terraform-example-foundation/5-app-infra/modules/env_base`.

> **Dormant catalog archetype.** No leaf calls `DeployEnvBase` in the live
> foundation yet — like `serverless_space`, `env_base` is part of the stage-5
> archetype catalog awaiting a consumer. It is an **upstream** module (upstream
> `5-app-infra` ships `env_base` and `confidential_space`), so having it here
> restores catalog parity with upstream. It is kept compiling and unit-tested
> (`main_test.go`, mock-driven) so it is ready to instantiate the moment an
> environment needs a Compute Engine base workload. A leaf would call it from
> its `main.go` exactly as the reference port's leaf does
> (`pulumi/examples/go-foundation/5-app-infra/business_unit_1/development`).

## Engine adaptations (Pulumi port)

- Upstream's `remote_state_bucket` / `terraform_remote_state` reads have no
  equivalent here: the calling env leaf resolves the 4-projects Stack
  References itself (see the leaf's `remote.go`) and passes resolved values in
  (`ProjectID`, `SubnetworkSelfLink`, ...).
- Upstream's `versions.tf` maps to the shared [`../go.mod`](../go.mod).
- Upstream's `terraform-google-modules/vm` wrappers map to the
  `pulumi-library` `pkg/instance_template` and `pkg/compute_instance`
  packages.

## File structure (upstream mapping)

| File           | Mirrors upstream | Purpose                                |
| -------------- | ---------------- | -------------------------------------- |
| `main.go`      | `main.tf`        | Resource logic (`DeployEnvBase`)       |
| `variables.go` | `variables.tf`   | Input surface (`EnvBaseArgs`)          |
| `outputs.go`   | `outputs.tf`     | Output surface (`EnvBaseResult`)       |

## Inputs (`EnvBaseArgs`)

| Name                 | Description                                                          | Required | Default          |
| -------------------- | -------------------------------------------------------------------- | :------: | ---------------- |
| `Env`                | The environment the workload belongs to                              |   yes    | n/a              |
| `BusinessUnit`       | The business unit code (e.g. `bu1`)                                  |   yes    | n/a              |
| `ProjectSuffix`      | Project-type suffix of the target project                            |   yes    | n/a              |
| `Hostname`           | Hostname prefix of the instances                                     |          | `"example-app"`  |
| `MachineType`        | Machine type to create                                               |          | `"f1-micro"`     |
| `NumInstances`       | Number of instances to create                                        |          | `1`              |
| `SourceImageFamily`  | Source image family                                                  |          | `"debian-12"`    |
| `SourceImageProject` | Project hosting the source image                                     |          | `"debian-cloud"` |
| `ProjectID`          | Target project (resolved from the 4-projects Stack Reference)        |   yes    | n/a              |
| `Region`             | Region to deploy into                                                |   yes    | n/a              |
| `SubnetworkSelfLink` | Shared-VPC subnet self link                                          |   yes    | n/a              |
| `IAPFirewallTags`    | IAP secure tags — `nil` for non-peering projects                     |          | `nil`            |

## Outputs (`EnvBaseResult`)

| Name               | Description                                     |
| ------------------ | ----------------------------------------------- |
| `InstanceSelfLink` | Self link of the compute instance               |
| `InstanceName`     | Name of the compute instance                    |
| `InstanceZone`     | Zone of the compute instance                    |
| `InstanceDetails`  | Map of details (name/zone/selfLink)             |
