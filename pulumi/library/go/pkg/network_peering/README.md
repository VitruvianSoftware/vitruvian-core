# network_peering

A Pulumi component for creating bidirectional VPC Network Peering between two GCP networks.

**Upstream Reference:** [terraform-google-modules/network/google//modules/network-peering](https://registry.terraform.io/modules/terraform-google-modules/network/google)

## Overview

Creates two reciprocal peering connections between a local and peer network, with configurable route exchange options and dual-stack support.

## API Reference

### NetworkPeeringArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `LocalNetwork` | `pulumi.StringInput` | ✅ | Self-link of the local VPC |
| `PeerNetwork` | `pulumi.StringInput` | ✅ | Self-link of the peer VPC |
| `ExportCustomRoutes` | `bool` | | Export custom routes to peer |
| `ImportCustomRoutes` | `bool` | | Import custom routes from peer |
| `ExportSubnetRoutesWithPublicIp` | `bool` | | Export subnet routes with public IPs |
| `ImportSubnetRoutesWithPublicIp` | `bool` | | Import subnet routes with public IPs |
| `StackType` | `string` | | Stack type (`IPV4_ONLY` or `IPV4_IPV6`) |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `LocalPeering` | `*compute.NetworkPeering` | Local → Peer peering connection |
| `PeerPeering` | `*compute.NetworkPeering` | Peer → Local peering connection |

## Usage

```go
peering, err := network_peering.NewNetworkPeering(ctx, "hub-spoke", &network_peering.NetworkPeeringArgs{
    LocalNetwork:       hubVpc.SelfLink,
    PeerNetwork:        spokeVpc.SelfLink,
    ExportCustomRoutes: true,
    ImportCustomRoutes: true,
})
```
