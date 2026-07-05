# cloud_router

A Pulumi component for creating GCP Cloud Routers with optional BGP configuration and Cloud NAT.

**Upstream Reference:** [terraform-google-modules/cloud-router/google](https://registry.terraform.io/modules/terraform-google-modules/cloud-router/google)

## Overview

Creates a Cloud Router with:
- Configurable BGP ASN and keepalive interval
- Custom advertised groups and IP ranges
- Optional Cloud NAT with configurable external IP addresses

## API Reference

### CloudRouterArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Region` | `string` | ✅ | GCP region |
| `Network` | `pulumi.StringInput` | ✅ | Self-link of the VPC network |
| `BgpAsn` | `int` | ✅ | BGP Autonomous System Number |
| `Description` | `string` | | Router description |
| `AdvertisedGroups` | `[]string` | | BGP advertised groups (e.g., `ALL_SUBNETS`) |
| `AdvertisedIpRanges` | `[]AdvertisedIPRange` | | Custom IP ranges to advertise |
| `KeepaliveInterval` | `int` | | BGP keepalive interval in seconds |
| `EnableNat` | `bool` | | Enable Cloud NAT on this router |
| `NatNumAddresses` | `int` | | Number of external IPs for NAT |

### AdvertisedIPRange

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `Range` | `string` | ✅ | CIDR range to advertise |
| `Description` | `string` | | Description of the range |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Router` | `*compute.Router` | The created Cloud Router |
| `Addresses` | `[]*compute.Address` | External IPs for NAT (if enabled) |
| `NAT` | `*compute.RouterNat` | Cloud NAT (if enabled) |

## Usage

```go
router, err := cloud_router.NewCloudRouter(ctx, "my-router", &cloud_router.CloudRouterArgs{
    ProjectID: pulumi.String("my-project"),
    Region:    "us-central1",
    Network:   vpc.SelfLink,
    BgpAsn:    64514,
    AdvertisedGroups: []string{"ALL_SUBNETS"},
    AdvertisedIpRanges: []cloud_router.AdvertisedIPRange{
        {Range: "199.36.153.8/30", Description: "Google Private API"},
    },
    EnableNat:       true,
    NatNumAddresses: 2,
})
```
