# 5-app-infra / business_unit_1 / production

This directory contains the Pulumi application infrastructure for the **production** environment in **business_unit_1**.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `env` | Environment name | `string` | `"production"` | yes |
| `projects_stack_name` | Fully qualified stack name of 4-projects | `string` | n/a | yes |
| `region` | Region for compute instances | `string` | `"us-central1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `instance_name` | Name of the deployed compute instance |
| `instance_self_link` | Self-link of the deployed compute instance |
