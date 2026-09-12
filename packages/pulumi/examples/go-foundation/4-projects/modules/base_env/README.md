# modules / base_env

Per-environment project orchestrator, the Pulumi port of upstream
terraform-example-foundation
[`4-projects/modules/base_env`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/4-projects/modules/base_env).
Creates the business-unit project set (SVPC-attached, floating, peering) plus
their attached infrastructure (Shared-VPC attach, VPC-SC perimeter attach,
CMEK storage, peering network + firewall) and — via the separate exported
`DeployConfidentialSpaceProject` entrypoint — the Confidential Space project.

Every project is created through [`modules/single_project`](../single_project)
with unchanged logical names, so the resource graph (and every URN) is
identical to the pre-refactor inline code.

## File layout (upstream mapping)

| File | Upstream analogue | Contents |
|------|-------------------|----------|
| `base_env.go` | n/a (Go orchestration) | `New` — calls the per-concern deploy functions |
| `variables.go` | `variables.tf` | `Args` |
| `outputs.go` | `outputs.tf` | `BUProjects` |
| `example_shared_vpc_project.go` | `example_shared_vpc_project.tf` | SVPC-attached project + Shared-VPC/VPC-SC attach |
| `example_floating_project.go` | `example_floating_project.tf` | Floating project |
| `example_peering_project.go` | `example_peering_project.tf` | Peering project + VPC/subnet/DNS/peering/firewall |
| `example_storage_cmek.go` | `example_storage_cmek.tf` | KMS keyring/key + CMEK GCS bucket |
| `example_confidential_space_project.go` | `example_confidential_space_project.tf` | Confidential Space project + workload SA |
| — (shared `../go.mod`) | `versions.tf` | Engine adaptation |

Port divergences from the upstream file set (documented, per the port policy):

- `business_unit_folder.tf` has no analogue here — our port creates the BU
  folder in each `business_unit_1/{env}` leaf's `main.go`.
- `remote.tf` has no analogue here — the leaves resolve the cross-stage
  StackReferences in their `remote.go` and pass the outputs in via `Args`.

## Inputs (`Args`)

| Name | Description |
|------|-------------|
| `ProjectPrefix`, `EnvCode`, `BusinessCode` | Project id components (upstream `project_prefix` / `environment_code` / `business_code`) |
| `BillingAccount` | Billing account for every project |
| `RandomSuffix` | Append the project-factory random suffix to project ids |
| `SVPCProjectEnabled`, `FloatingProjectEnabled`, `PeeringProjectEnabled` | Project-type enablement toggles |
| `EnforceVpcSc` | Enforced (vs dry-run) VPC-SC perimeter attach |
| `CMEKEnabled` | Deploy CMEK keyring/key + encrypted GCS bucket |
| `PeeringEnabled` | Deploy the peering network infrastructure |
| `ApiPropagationSeconds` | Post-API-enable propagation wait forwarded to every project (0 disables) |
| `SubnetRegion`, `SubnetIPRange`, `PeeringIAPFWEnabled`, `FirewallEnableLogging`, `WindowsActivation`, `OptionalFWRulesEnabled` | Peering network configuration |
| `KeyringName`, `KMSLocation`, `KeyName`, `KeyRotationPeriod`, `GCSBucketPrefix`, `GCSLocation`, `GCSPlacementRegions` | CMEK configuration |
| `FolderID`, `NetworkProjectID`, `PerimeterName`, `KMSProjectID`, `ACMPolicyID` | Cross-stage StackReference outputs (resolved by the leaf) |
| `Labels`, `Budget` | Label builder closure + standard budget from the leaf's tested helpers |

## Outputs (`BUProjects`)

| Name | Description |
|------|-------------|
| `SVPCProjectID`, `SVPCProjectNumber` | SVPC-attached project |
| `FloatingProjectID` | Floating project |
| `PeeringProjectID`, `PeeringNetworkSelfLink`, `PeeringSubnetSelfLink`, `IAPFirewallTags` | Peering project + network |
| `CMEKBucket`, `CMEKKeyring`, `CMEKKeys` | CMEK storage (nil when disabled) |
| `ConfSpaceProjectID`, `ConfSpaceProjectNumber`, `ConfSpaceWorkloadSA` | Confidential Space project (nil unless deployed) |
| `SubnetsSelfLinks`, `VPCSCPerimeterName`, `PeeringComplete`, `AccessContextManagerPolicyID`, `RestrictedEnabledApis` | TF-parity outputs |
