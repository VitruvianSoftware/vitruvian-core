# private_service_connect

A Pulumi component for configuring Private Service Connect (PSC) endpoints with DNS zones for Google APIs.

**Upstream Reference:** [terraform-google-modules/network/google//modules/private-service-connect](https://registry.terraform.io/modules/terraform-google-modules/network/google)

## Overview

Creates a PSC endpoint with:
- Global address and forwarding rule targeting Google APIs
- Private DNS zones for `googleapis.com`, `gcr.io`, and `pkg.dev`
- CNAME and A records routing API traffic through the PSC endpoint
- Optional VPC-SC compatible configuration

## API Reference

### PrivateServiceConnectArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `ProjectID` | `pulumi.StringInput` | ✅ | GCP project ID |
| `NetworkSelfLink` | `pulumi.StringInput` | ✅ | VPC self-link |
| `IPAddress` | `string` | ✅ | Static IP for the PSC endpoint |
| `ForwardingRuleTarget` | `string` | ✅ | `all-apis` or `vpc-sc` |
| `DnsCode` | `string` | | Code for DNS zone naming |
| `PscGlobalAccess` | `bool` | | Enable global access for PSC |

### Outputs

| Field | Type | Description |
|:--|:--|:--|
| `Address` | `*compute.GlobalAddress` | The reserved global address |
| `ForwardingRule` | `*compute.GlobalForwardingRule` | The PSC forwarding rule |
| `DnsZones` | `[]*dns.ManagedZone` | Private DNS zones created |

## Usage

```go
psc, err := private_service_connect.NewPrivateServiceConnect(ctx, "psc-apis", &private_service_connect.PrivateServiceConnectArgs{
    ProjectID:            pulumi.String("my-project"),
    NetworkSelfLink:      vpc.SelfLink,
    IPAddress:            "10.255.255.254",
    ForwardingRuleTarget: "all-apis",
    DnsCode:              "hub",
    PscGlobalAccess:      true,
})
```
