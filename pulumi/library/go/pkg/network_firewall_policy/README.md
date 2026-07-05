# network_firewall_policy

A Pulumi component for creating GCP Network Firewall Policies with rules and network association.

**Upstream Reference:** [terraform-google-modules/network/google//modules/network-firewall-policy](https://registry.terraform.io/modules/terraform-google-modules/network/google)

## Overview

Creates a network firewall policy with:
- Typed firewall rules (INGRESS/EGRESS) with configurable priority
- Automatic network association
- Secure tags and service account targeting
- Layer 4 protocol/port configuration with logging

## API Reference

### NetworkFirewallPolicyArgs

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `Project` | `pulumi.StringInput` | ✅ | GCP project ID |
| `Name` | `string` | ✅ | Policy name |
| `Description` | `string` | | Policy description |
| `Network` | `pulumi.StringInput` | ✅ | VPC self-link to associate |
| `Rules` | `[]FirewallRule` | | Firewall rules |

### FirewallRule

| Field | Type | Required | Description |
|:--|:--|:--|:--|
| `RuleName` | `string` | ✅ | Unique rule identifier |
| `Direction` | `string` | ✅ | `INGRESS` or `EGRESS` |
| `Action` | `string` | ✅ | `allow`, `deny`, or `goto_next` |
| `Priority` | `int` | ✅ | Rule priority (lower = higher precedence) |
| `Ranges` | `[]string` | | Source/destination CIDR ranges |
| `Layer4Configs` | `[]Layer4Config` | | Protocol/port configurations |
| `EnableLogging` | `bool` | | Enable firewall logging |
| `TargetSecureTags` | `[]SecureTag` | | Secure tag targets |
| `TargetServiceAccounts` | `[]string` | | Target service accounts |

### Layer4Config / SecureTag

| Field | Type | Description |
|:--|:--|:--|
| `IpProtocol` | `string` | Protocol (`tcp`, `udp`, `icmp`, `all`) |
| `Ports` | `[]string` | Port ranges (`["80", "443", "8000-9000"]`) |
| `Name` | `string` | Secure tag value (`tagValues/...`) |

## Usage

```go
policy, err := network_firewall_policy.NewNetworkFirewallPolicy(ctx, "fw-policy", &network_firewall_policy.NetworkFirewallPolicyArgs{
    Project: pulumi.String("my-project"),
    Name:    "vpc-firewall-policy",
    Network: vpc.SelfLink,
    Rules: []network_firewall_policy.FirewallRule{
        {
            RuleName:  "allow-iap",
            Direction: "INGRESS",
            Action:    "allow",
            Priority:  100,
            Ranges:    []string{"35.235.240.0/20"},
            Layer4Configs: []network_firewall_policy.Layer4Config{
                {IpProtocol: "tcp", Ports: []string{"22", "3389"}},
            },
        },
    },
})
```
