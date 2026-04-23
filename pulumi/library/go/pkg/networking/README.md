# pkg/networking — VPC and Subnet Management

Creates VPC networks with subnets (including GKE secondary ranges, flow logs, and Private Google Access) and optional Private Service Access (PSA).

## Overview

The `Networking` component wraps:
- [`compute.Network`](https://www.pulumi.com/registry/packages/gcp/api-docs/compute/network/) — VPC network
- [`compute.Subnetwork`](https://www.pulumi.com/registry/packages/gcp/api-docs/compute/subnetwork/) — Subnets with secondary ranges
- [`compute.GlobalAddress`](https://www.pulumi.com/registry/packages/gcp/api-docs/compute/globaladdress/) + [`servicenetworking.Connection`](https://www.pulumi.com/registry/packages/gcp/api-docs/servicenetworking/connection/) — Private Service Access

### Security Defaults

- **Auto-create subnets** is always `false` — all subnets are explicitly defined
- **Default routes are removed** by default — forces explicit routing configuration
- **Private Google Access** is enabled on all subnets
- **Routing mode** defaults to `GLOBAL`

## API Reference

### `NetworkingArgs`

| Field | Type | Required | Default | Description |
|-------|------|:--------:|---------|-------------|
| `ProjectID` | `pulumi.StringInput` | ✅ | — | The GCP project ID |
| `VPCName` | `pulumi.StringInput` | ✅ | — | The VPC network name |
| `Subnets` | `[]SubnetArgs` | | `nil` | Subnet definitions (see below) |
| `EnablePSA` | `bool` | | `false` | Enable Private Service Access for managed services |
| `DeleteDefaultRoutesOnCreation` | `*bool` | | `true` | Remove default internet routes |
| `RoutingMode` | `string` | | `"GLOBAL"` | VPC routing mode (`GLOBAL` or `REGIONAL`) |

### `SubnetArgs`

| Field | Type | Required | Default | Description |
|-------|------|:--------:|---------|-------------|
| `Name` | `string` | ✅ | — | Subnet name |
| `Region` | `string` | ✅ | — | GCP region |
| `CIDR` | `string` | ✅ | — | Primary IP CIDR range |
| `SecondaryRanges` | `[]SecondaryRangeArgs` | | `nil` | GKE pod/service secondary ranges |
| `FlowLogs` | `bool` | | `false` | Enable VPC flow logs |

### `SecondaryRangeArgs`

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `RangeName` | `string` | ✅ | Name of the secondary range (e.g., `gke-pods`) |
| `CIDR` | `string` | ✅ | IP CIDR range for the secondary range |

### `Networking` (Output)

| Field | Type | Description |
|-------|------|-------------|
| `VPC` | `*compute.Network` | The underlying VPC network resource |
| `Subnets` | `map[string]*compute.Subnetwork` | Map of subnet name → subnet resource |

### Constructor

```go
func NewNetworking(ctx *pulumi.Context, name string, args *NetworkingArgs, opts ...pulumi.ResourceOption) (*Networking, error)
```

## Examples

### Simple VPC

```go
net, err := networking.NewNetworking(ctx, "main", &networking.NetworkingArgs{
    ProjectID: pulumi.String("my-project"),
    VPCName:   pulumi.String("vpc-main"),
    Subnets: []networking.SubnetArgs{
        {Name: "sb-us-central1", Region: "us-central1", CIDR: "10.0.0.0/24"},
    },
})
```

### VPC with GKE Ranges and Flow Logs

```go
net, err := networking.NewNetworking(ctx, "shared", &networking.NetworkingArgs{
    ProjectID: projectID,
    VPCName:   pulumi.String("vpc-shared-base"),
    EnablePSA: true,
    Subnets: []networking.SubnetArgs{
        {
            Name: "sb-dev-us-central1", Region: "us-central1",
            CIDR: "10.0.64.0/21", FlowLogs: true,
            SecondaryRanges: []networking.SecondaryRangeArgs{
                {RangeName: "gke-pods", CIDR: "100.64.64.0/21"},
                {RangeName: "gke-svcs", CIDR: "100.64.72.0/21"},
            },
        },
        {
            Name: "sb-dev-us-west1", Region: "us-west1",
            CIDR: "10.1.64.0/21", FlowLogs: true,
            SecondaryRanges: []networking.SecondaryRangeArgs{
                {RangeName: "gke-pods", CIDR: "100.65.64.0/21"},
                {RangeName: "gke-svcs", CIDR: "100.65.72.0/21"},
            },
        },
    },
})
```

### Accessing Subnet Outputs

```go
// Get a specific subnet by name
subnet := net.Subnets["sb-dev-us-central1"]
ctx.Export("subnet_self_link", subnet.SelfLink)
ctx.Export("vpc_id", net.VPC.ID())
```

## Resource Graph

```
pkg:index:Networking ("shared")
├── gcp:compute:Network ("shared-vpc")
│   ├── gcp:compute:Subnetwork ("shared-sb-dev-us-central1")
│   ├── gcp:compute:Subnetwork ("shared-sb-dev-us-west1")
│   ├── gcp:compute:GlobalAddress ("shared-psa-ip")
│   └── gcp:servicenetworking:Connection ("shared-psa-conn")
```
