# cloud_dns

A Pulumi component for creating Cloud DNS managed zones with support for private, public, forwarding, peering, and reverse lookup zones.

**Upstream Reference:** [terraform-google-modules/cloud-dns/google](https://registry.terraform.io/modules/terraform-google-modules/cloud-dns/google)

## Overview

Creates DNS managed zones with:
- Private zones bound to a VPC network
- Public zones with optional DNSSEC
- Forwarding zones with configurable target nameservers
- Peering zones linked to target networks
- Reverse lookup zones
- Optional DNS record sets

## API Reference

### DnsZoneArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Name` | `string` | ✅ | Zone name |
| `Domain` | `string` | ✅ | DNS domain (must end with `.`) |
| `Type` | `string` | ✅ | Zone type: `private`, `public`, `forwarding`, `peering`, `reverse_lookup` |
| `Description` | `string` | | Zone description |
| `NetworkSelfLink` | `pulumi.StringInput` | | VPC self-link (required for private/forwarding/peering/reverse) |
| `TargetNameServerAddresses` | `[]string` | | Forwarding target IPs |
| `ForwardingPath` | `string` | | Forwarding path (`default` or `private`) |
| `TargetNetworkSelfLink` | `pulumi.StringInput` | | Peering target VPC |
| `EnableDnssec` | `bool` | | Enable DNSSEC (public zones) |
| `Labels` | `map[string]string` | | Resource labels |
| `Recordsets` | `[]RecordSet` | | DNS record sets to create |

### RecordSet

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `Name` | `string` | ✅ | Record name (relative to zone) |
| `Type` | `string` | ✅ | Record type (A, CNAME, MX, etc.) |
| `TTL` | `int` | | TTL in seconds (default 300) |
| `Records` | `[]string` | ✅ | Record data values |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Zone` | `*dns.ManagedZone` | The created managed zone |
| `RecordSets` | `[]*dns.RecordSet` | Created record sets |

## Usage

```go
zone, err := cloud_dns.NewDnsZone(ctx, "internal-dns", &cloud_dns.DnsZoneArgs{
    ProjectID:       pulumi.String("my-project"),
    Name:            "internal-zone",
    Domain:          "internal.example.com.",
    Type:            "private",
    NetworkSelfLink: vpc.SelfLink,
    Recordsets: []cloud_dns.RecordSet{
        {Name: "api", Type: "A", TTL: 300, Records: []string{"10.0.0.10"}},
    },
})
```
