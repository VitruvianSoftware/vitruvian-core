# modules / transitivity

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/modules/transitivity`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/modules/transitivity)
— the hub transitivity appliance (ILB + MIG) plus the health-check firewall.
Gated off by default (`enable_hub_and_spoke_transitivity=false`); the caller
only invokes `New` when enabled.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | `New` — library `TransitivityAppliance` + health-check firewall |
| `variables.tf` | `variables.go` | `Args` |
| `versions.tf` | `../go.mod` | engine adaptation |
| `assets/` | — | appliance startup logic lives in the library component |

## Interface
- `[main.go:New]`
- `[variables.go:Args]`

## Invariants
- None

## Side Effects
- [main.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [variables.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/transitivity/...`
