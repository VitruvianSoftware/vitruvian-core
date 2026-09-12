# 4-projects / business_unit_1 / nonproduction

Thin business-unit leaf for the **nonproduction** environment, the Pulumi port of
upstream terraform-example-foundation
[`4-projects/business_unit_1/nonproduction`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/4-projects/business_unit_1/nonproduction).
The leaf pins the environment identity (`nonproduction` / `n`), creates the BU
folder under the environment folder, and calls
[`modules/base_env`](../../modules/base_env) for the per-env business-unit
project set. The BU's shared infra-pipeline project lives in the sibling
[`shared`](../shared) leaf.

## File layout (upstream mapping)

| File | Upstream analogue | Contents |
|------|-------------------|----------|
| `main.go` | `main.tf` | Env pin, BU folder, `base_env` call, orchestration |
| `config.go` | `variables.tf` (+ `*.auto.tfvars`) | `ProjectsConfig`, config loader, label/budget helpers |
| `remote.go` | `remote.tf` | Cross-stage StackReferences (environment, org, network) |
| `outputs.go` | `outputs.tf` | Stack exports |
| `Pulumi.yaml`, `go.mod` | `backend.tf`, `versions.tf` | Engine adaptation: Pulumi project + Go module |
| `Pulumi.production.yaml.example` | `*.auto.example.tfvars` | Example stack configuration |

## Inputs

| Name | Description | Default | Required |
|------|-------------|---------|:--------:|
| `business_code` | The business code (ex. `bu1`) | n/a | yes |
| `billing_account` | The ID of the billing account to associate projects with | n/a | yes |
| `org_stack_name` | StackReference to the 1-org stack | n/a | yes |
| `env_stack_name` | StackReference to this env's 2-environments leaf stack | n/a | yes |
| `network_stack_name` | StackReference to this env's 3-networks leaf stack | derived from `env_stack_name` by name substitution | no |
| `project_prefix` | Name prefix to use for projects created | `prj` | no |
| `folder_prefix` | Name prefix to use for folders created | `fldr` | no |
| `random_suffix` | Append a random suffix to project ids | `true` | no |
| `application_name` | Label: name of the sample application | `{business_code}-sample-application` | no |
| `billing_code` | Label: chargeback code | `1234` | no |
| `primary_contact` | Label: primary email contact | `example@example.com` | no |
| `secondary_contact` | Label: secondary email contact | `example2@example.com` | no |
| `budget_amount` | Budget amount per project | `1000` | no |
| `budget_alert_percents` | Budget alert thresholds | `[1.2]` | no |
| `budget_spend_basis` | `CURRENT_SPEND` or `FORECASTED_SPEND` | `FORECASTED_SPEND` | no |
| `svpc_project_enabled` | Deploy the SVPC-attached project | `true` | no |
| `floating_project_enabled` | Deploy the floating project | `true` | no |
| `peering_project_enabled` | Deploy the peering project | `true` | no |
| `api_propagation_seconds` | Post-API-enable propagation wait (0 disables) | `120` | no |
| `enforce_vpcsc` | Enforced (vs dry-run) VPC-SC perimeter attach | `true` | no |
| `peering_enabled` | Deploy the peering network infrastructure | `true` | no |
| `peering_iap_fw_rules_enabled` | Create IAP SSH/RDP firewall rules + secure tags | `true` | no |
| `subnet_region` | Region for the peered subnet | `us-central1` | no |
| `subnet_ip_range` | IP range for the peered subnet | `10.3.64.0/21` | no |
| `firewall_enable_logging` | Toggle firewall rule logging | `true` | no |
| `windows_activation_enabled` | Windows KMS activation egress rule | `false` | no |
| `optional_fw_rules_enabled` | Optional LB health-check rules | `false` | no |
| `confidential_space_enabled` | Deploy the Confidential Space project | `false` | no |
| `cmek_enabled` | Deploy CMEK keyring/key + encrypted GCS bucket | `true` | no |
| `location_kms` | Location for the KMS keyring | `subnet_region` | no |
| `location_gcs` | Location for the CMEK GCS bucket | `US` | no |
| `keyring_name` | KMS keyring name | `{business_code}-sample-keyring` | no |
| `key_name` | KMS crypto key name | `crypto-key-example` | no |
| `key_rotation_period` | KMS key rotation period | `7776000s` | no |
| `gcs_bucket_prefix` | Name prefix for the CMEK bucket | `bkt` | no |
| `gcs_placement_regions` | Dual-region custom placement (2 regions) | `[]` | no |
| `region` | Default region (exported) | `us-central1` | no |
| `region2` | Secondary region | `us-west1` | no |
| `folder_deletion_protection` | Prevent destroying/recreating the BU folder | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| `shared_vpc_project` | SVPC-attached project id |
| `shared_vpc_project_number` | SVPC-attached project number |
| `floating_project` | Floating project id |
| `peering_project` | Peering project id |
| `peering_network` | Peering VPC self link |
| `peering_subnetwork_self_link` | Peered subnet self link |
| `iap_firewall_tags` | Secure tags created for the IAP (SSH/RDP) firewall rules |
| `bucket` | CMEK-encrypted GCS bucket (when `cmek_enabled`) |
| `keyring` | KMS keyring name (when `cmek_enabled`) |
| `keys` | List of created crypto-key names |
| `confidential_space_project` | Confidential Space project id (when enabled) |
| `confidential_space_project_number` | Confidential Space project number (when enabled) |
| `confidential_space_workload_sa` | Confidential Space workload SA email (when enabled) |
| `default_region` | The default region |
| `subnets_self_links` | Subnet self links (see the TODO in `modules/base_env`) |
| `restricted_enabled_apis` | APIs activated on the SVPC-attached project |
| `vpc_service_control_perimeter_name` | VPC-SC perimeter name |
| `peering_complete` | Module-dependency marker for the peering network |
| `access_context_manager_policy_id` | Access Context Manager policy id |
