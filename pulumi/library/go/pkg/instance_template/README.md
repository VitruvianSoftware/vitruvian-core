# instance_template

A Pulumi component for creating GCP Compute Instance Templates with optional shielded and confidential VM support.

**Upstream Reference:** [terraform-google-modules/vm/google//modules/instance_template](https://registry.terraform.io/modules/terraform-google-modules/vm/google)

## Overview

Creates a compute instance template with:
- Configurable machine type, disk type, and size
- Network and subnetwork binding
- Service account and IAM scopes
- Shielded VM configuration (Secure Boot, vTPM, Integrity Monitoring)
- Confidential VM support (AMD SEV)
- Custom labels, tags, and metadata

## API Reference

### InstanceTemplateArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `Project` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Region` | `string` | ✅ | GCP region |
| `SourceImage` | `string` | ✅ | Source image or family |
| `Network` | `pulumi.StringInput` | ✅ | VPC self-link |
| `Subnetwork` | `pulumi.StringInput` | ✅ | Subnet self-link |
| `MachineType` | `string` | | Machine type (default: `n1-standard-1`) |
| `DiskSizeGb` | `int` | | Boot disk size in GB (default: 20) |
| `DiskType` | `string` | | Disk type (default: `pd-standard`) |
| `ServiceAccountEmail` | `pulumi.StringInput` | | Service account email |
| `Tags` | `[]string` | | Network tags |
| `Labels` | `map[string]string` | | Resource labels |
| `Metadata` | `map[string]string` | | Instance metadata |
| `EnableShieldedVm` | `bool` | | Enable Shielded VM |
| `EnableConfidentialVm` | `bool` | | Enable Confidential VM |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Template` | `*compute.InstanceTemplate` | The created instance template |

## Usage

```go
tmpl, err := instance_template.NewInstanceTemplate(ctx, "web-tmpl", &instance_template.InstanceTemplateArgs{
    Project:          pulumi.String("my-project"),
    Region:           "us-central1",
    MachineType:      "n2-standard-2",
    SourceImage:      "projects/debian-cloud/global/images/family/debian-12",
    DiskSizeGb:       50,
    DiskType:         "pd-ssd",
    Network:          vpc.SelfLink,
    Subnetwork:       subnet.SelfLink,
    EnableShieldedVm: true,
    Tags:             []string{"allow-ssh", "allow-http"},
})
```
