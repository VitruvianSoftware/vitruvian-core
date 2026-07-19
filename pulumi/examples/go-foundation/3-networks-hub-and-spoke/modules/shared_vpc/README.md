# modules / shared_vpc

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/modules/shared_vpc`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/modules/shared_vpc)
— one Shared VPC host network (VPC, subnets, routes, peering, routers,
firewall, PSC, DNS, NAT, VPC-SC perimeter), branching on `Mode` ("hub" or
"spoke"). The module is a plain composition (NOT a ComponentResource) so
every child keeps its original stack-root URN.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | `New` + peering/routes/BGP-router helpers |
| `variables.tf` | `variables.go` | `Args` |
| `outputs.tf` | `outputs.go` | `Result` (+ hub stack exports emitted in `main.go` hub path) |
| `dns.tf` | `dns.go` | DNS policy, hub forwarding zone, spoke peering zone |
| `firewall.tf` | `firewall.go` | VPC-level network firewall policy |
| `nat.tf` | `nat.go` | conditional per-region NAT routers |
| `private_service_connect.tf` | `private_service_connect.go` | PSC endpoint |
| `service_control.tf` | `service_control.go` | VPC-SC perimeters (hub + spoke paths) |
| `versions.tf` | `../go.mod` | engine adaptation |

PSA-vs-peering serialization: the spoke peering `DependsOn` the spoke
`PSAConnection` (see `createPeering` in `main.go`) — a documented workaround
that mirrors upstream's peering/PSA mutual-exclusion with the opposite (but
equally deadlock-free) ordering.
