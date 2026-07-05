# 3-networks-svpc / production

This directory contains the Pulumi network configuration for the **production** environment using the Shared VPC architecture.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `env` | Environment name | `string` | `"production"` | yes |
| `project_id` | Shared VPC host project ID | `string` | n/a | yes |
| `parent_id` | Parent scope for firewall policies | `string` | n/a | yes |
| `region1` | Primary region | `string` | `"us-central1"` | no |
| `region2` | Secondary region | `string` | `"us-west1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `network_id` | VPC network resource ID |
| `network_name` | VPC network name |
| `network_self_link` | VPC network self link |
