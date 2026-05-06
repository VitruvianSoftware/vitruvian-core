# 3-networks-hub-and-spoke / production

This directory contains the Pulumi network configuration for the **production** environment using the Hub and Spoke architecture.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `env` | Environment name | `string` | `"production"` | yes |
| `hub_project_id` | Hub VPC host project ID | `string` | n/a | yes |
| `spoke_project_id` | Spoke VPC project ID | `string` | n/a | yes |
| `parent_id` | Parent scope for firewall policies | `string` | n/a | yes |
| `region1` | Primary region | `string` | `"us-central1"` | no |
| `region2` | Secondary region | `string` | `"us-west1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `hub_network_id` | Hub VPC network resource ID |
| `spoke_network_id` | Spoke VPC network resource ID |
