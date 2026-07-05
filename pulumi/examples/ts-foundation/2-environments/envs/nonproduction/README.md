# 2-environments / nonproduction

This directory contains the Pulumi configuration for the **nonproduction** environment.

## Inputs

These values are read from `Pulumi.nonproduction.yaml` or set via `pulumi config set`:

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `org_id` | GCP Organization ID | `string` | n/a | yes |
| `billing_account` | Billing account ID | `string` | n/a | yes |
| `bootstrap_stack_name` | Fully qualified stack name of 0-bootstrap | `string` | n/a | yes |
| `project_prefix` | Name prefix for projects | `string` | `"prj"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `env_folder` | Environment folder ID |
| `env_kms_project_id` | KMS project ID for this environment |
| `env_secrets_project_id` | Secrets project ID for this environment |

## Deploying

```bash
cd 2-environments/envs/nonproduction
pulumi stack init nonproduction
pulumi config set org_id "YOUR_ORG_ID"
pulumi config set billing_account "YOUR_BILLING_ACCOUNT_ID"
pulumi config set bootstrap_stack_name "organization/vitruvian/0-bootstrap/production"
pulumi up
```
