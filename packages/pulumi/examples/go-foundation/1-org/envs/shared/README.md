# 1-org / envs / shared

The organization stage root (Pulumi Go project `foundation-1-org`), mirroring upstream `terraform-example-foundation/1-org/envs/shared`. Each concern lives in its own file matching the upstream `.tf` file names:

| File | Upstream counterpart | Concern |
|------|----------------------|---------|
| `cai_monitoring.go` | `cai_monitoring.tf` | CAI monitoring module call (SCC IAM-change findings) |
| `config.go` | `variables.tf` | Config struct + loader (tfvars → `Pulumi.<stack>.yaml`) |
| `essential_contacts.go` | `essential_contacts.tf` | Essential Contacts notifications |
| `folders.go` | `folders.tf` | Common + Network folders |
| `iam.go` | `iam.tf` | Governance-group and SA IAM bindings |
| `log_sinks.go` | `log_sinks.tf` | Centralized logging module call (org sinks) |
| `main.go` | (engine) | `func main()` wiring only |
| `org_policy.go` | `org_policy.tf` | Org policies + Access Context Manager policy |
| `outputs.go` | `outputs.tf` | All stack exports |
| `projects.go` | `projects.tf` | Org-level projects (audit, billing, SCC, KMS, secrets, interconnect, network) |
| `remote.go` | `remote.tf` | Bootstrap StackReference (remote state) |
| `sa.go` | `sa.tf` | `cai-monitoring-builder` service account |
| `scc_notification.go` | `scc_notification.tf` | SCC notification config |
| `tags.go` | `tags.tf` | Org-level tag keys/values + bindings |

Engine adaptations (kept, per the porting rules): backend/providers/versions live in `Pulumi.yaml`/`go.mod` instead of `backend.tf`/`providers.tf`/`versions.tf`; `terraform.example.tfvars` maps to `Pulumi.production.yaml.example`.

## Inputs

Config keys on this stack (upstream variable of the same name unless noted).

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| org\_id | The organization id. | `string` | n/a | yes |
| billing\_account | The ID of the billing account to associate projects with. | `string` | n/a | yes |
| bootstrap\_stack\_name | The 0-bootstrap stack to read cross-stage outputs from (engine adaptation of `remote_state_bucket`). | `string` | n/a | yes |
| project\_prefix | Name prefix to use for projects created. | `string` | `"prj"` | no |
| folder\_prefix | Name prefix to use for folders created. | `string` | `"fldr"` | no |
| default\_region | Default region for regional resources. | `string` | `"us-central1"` | no |
| parent\_folder | Deploy under a folder instead of the org root (co-tenant foundations). | `string` | `""` | no |
| group\_org\_admins / group\_billing\_admins / audit\_data\_users / billing\_data\_users | Required governance groups (from bootstrap or overridden locally). | `string` | `""` | no |
| gcp\_security\_reviewer / gcp\_network\_viewer / gcp\_scc\_admin / gcp\_global\_secrets\_admin / gcp\_kms\_admin / gcp\_audit\_viewer | Optional governance groups (upstream `gcp_groups`). | `string` | `""` | no |
| domains\_to\_allow | Comma-separated domains for the Domain Restricted Sharing org policy. | `string` (CSV) | `""` | no |
| essential\_contacts\_domains | Comma-separated domains allowed for Essential Contacts (upstream `essential_contacts_domains_to_allow`). | `string` (CSV) | `""` | no |
| essential\_contacts\_language | Essential Contacts preferred language (ISO 639-1). | `string` | `"en"` | no |
| scc\_notification\_name | Name of the Security Command Center Notification; must be unique in the organization. | `string` | `"scc-notify"` | no |
| scc\_notification\_filter | Filter used to create the SCC Notification. | `string` | `state = "ACTIVE"` | no |
| enable\_scc\_resources\_in\_pulumi | Create SCC resources (notification, CAI monitoring). SCC must be activated first (upstream `enable_scc_resources_in_terraform`). | `bool` | `false` | no |
| create\_access\_context\_manager\_policy | Whether to create the org-level Access Context Manager policy (upstream `create_access_context_manager_access_policy`). | `bool` | `false` | no |
| enforce\_allowed\_worker\_pools | Enforce the Cloud Build allowed-worker-pools org policy. | `bool` | `false` | no |
| allowed\_worker\_pool\_id | The private worker pool allowed when enforcement is on. | `string` | `""` | no |
| enable\_hub\_and\_spoke | Enable Hub-and-Spoke architecture (creates the net-hub project). | `bool` | `false` | no |
| networks\_sa\_email | Networks pipeline SA email for hub-and-spoke IAM. | `string` | `""` | no |
| enable\_kms\_key\_usage\_tracking | Enable KMS centralized key usage tracking system. | `bool` | `true` | no |
| random\_suffix | Adds a suffix of 4 random characters to project IDs. | `bool` | `true` | no |
| project\_deletion\_policy | The deletion policy for the projects created. | `string` | `"PREVENT"` | no |
| folder\_deletion\_protection | Prevent destroying or recreating the folders. | `bool` | `true` | no |
| default\_service\_account | Default SA handling on new projects (`deprivilege`/`keep`/`disable`/`delete`). | `string` | `"deprivilege"` | no |
| project\_budget | Per-project budget object (amounts, alert percents, Pub/Sub topics, spend basis). | `object` | `{}` | no |
| log\_export\_storage\_location | The location of the storage bucket used to export logs. | `string` | `default_region` | no |
| log\_export\_storage\_force\_destroy | Delete all bucket contents when destroying the log bucket. | `bool` | `false` | no |
| log\_export\_storage\_versioning | Toggles log-export bucket versioning. | `bool` | `false` | no |
| log\_export\_storage\_retention\_days / log\_export\_storage\_retention\_locked | Bucket retention policy (upstream `log_export_storage_retention_policy`). | `int` / `bool` | unset | no |
| enable\_billing\_account\_sink | Create billing-account-level log sinks. | `bool` | `true` | no |
| billing\_export\_dataset\_location | The location of the dataset for billing data export. | `string` | `default_region` | no |
| create\_unique\_tag\_key | Adds a random suffix to org-wide tag keys. | `bool` | `false` | no |
| bootstrap\_folder\_name | Bootstrap folder override when not read from the StackReference. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| access\_context\_manager\_policy\_id | Access Context Manager Policy ID (empty when not created by this stage). |
| billing\_sink\_names | The name of the sinks under billing account level. |
| cai\_monitoring\_artifact\_registry | CAI Monitoring Cloud Function Artifact Registry name. |
| cai\_monitoring\_asset\_feed | CAI Monitoring Cloud Function Organization Asset Feed name. |
| cai\_monitoring\_bucket | CAI Monitoring Cloud Function Source Bucket name. |
| cai\_monitoring\_topic | CAI Monitoring Cloud Function Pub/Sub Topic name. |
| common\_folder\_name / common\_folder\_id | The common folder. |
| common\_kms\_project\_id | The org Cloud Key Management Service (KMS) project ID. |
| domains\_to\_allow | The list of domains to allow users from in IAM. |
| interconnect\_project\_id / interconnect\_project\_number | The Dedicated Interconnect project. |
| logs\_export\_project\_linked\_dataset\_name | The Log Bucket linked BigQuery dataset for the project destination. |
| logs\_export\_project\_logbucket\_name | The Log Bucket created for the project destination. |
| logs\_export\_pubsub\_topic | The Pub/Sub topic for destination of log exports. |
| logs\_export\_storage\_bucket\_name | The storage bucket for destination of log exports. |
| net\_hub\_project\_id / net\_hub\_project\_number | The Network hub project (hub-and-spoke only). |
| network\_folder\_name / network\_folder\_id | The network folder. |
| {env}\_network\_project\_id / {env}\_network\_project\_number | Per-environment Shared-VPC host projects. |
| org\_audit\_logs\_project\_id | The org audit logs project ID. |
| org\_billing\_export\_project\_id | The org billing export project ID. |
| org\_id | The organization id. |
| org\_secrets\_project\_id | The org secrets project ID. |
| parent\_resource\_id / parent\_resource\_type | The parent resource id and type. |
| scc\_notification\_name | Name of the SCC Notification. |
| scc\_notifications\_project\_id | The SCC notifications project ID. |
| shared\_vpc\_projects | Shared VPC projects info grouped by environment. |
| tags | Tag values to be applied on next steps. |
