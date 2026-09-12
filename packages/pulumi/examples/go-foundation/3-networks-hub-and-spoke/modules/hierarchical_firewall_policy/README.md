# modules / hierarchical_firewall_policy

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/modules/hierarchical_firewall_policy`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/modules/hierarchical_firewall_policy)
— the org/folder-level hierarchical firewall policy and its folder
associations (hub only).

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | `New` — library `HierarchicalFirewallPolicy` component |
| `variables.tf` | `variables.go` | `Args` |
| `outputs.tf` | `outputs.go` | outputs encapsulated by the library component (documented there) |
| `versions.tf` | `../go.mod` | engine adaptation |
