# 3-networks-hub-and-spoke / envs / shared

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/envs/shared`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/envs/shared)
— the shared/hub root of the networks stage. It pins the shared identity
(`shared`/`c`) and deploys the central hub Shared VPC, the org/folder-level
hierarchical firewall policy, and (when enabled) the transitivity appliance.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | thin orchestration + pinned identity consts |
| `hierarchical_firewall.tf` | `hierarchical_firewall.go` | org/folder hierarchical firewall policy |
| `net-hubs.tf` | `net_hubs.go` | hub Shared VPC via `modules/shared_vpc` (hub mode) |
| `net-hubs-transitivity.tf` | `net_hubs_transitivity.go` | conditional transitivity appliance |
| `variables.tf` | `config.go` | stack config (engine adaptation: tfvars → `Pulumi.<stack>.yaml`) |
| `outputs.tf` | `outputs.go` | hub exports emitted by `modules/shared_vpc` hub mode (documented there) |
| `remote.tf` | `remote.go` | cross-stage reads live where consumed (documented there) |
| `backend.tf`, `providers.tf`, `versions.tf` | `Pulumi.yaml`, `go.mod` | engine adaptation |
| `interconnect.tf.example` | `interconnect.go.example` | rename-to-activate example |
| `partner_interconnect.tf.example` | `partner_interconnect.go.example` | rename-to-activate example |

Deploy order: `shared` → `development` → `nonproduction` → `production`
(serializes hub-side peering mutations; see the note in `main.go`).

## Interface
- `[config.go:VpcFlowLogsConfig]`
- `[config.go:NetSharedConfig]`

## Invariants
- [config.go:67]: `HubProjectID: conf.Require("hub_project_id"),`
- [config.go:70]: `ParentID:     conf.Require("parent_id"),`

## Side Effects
- [config.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [hierarchical_firewall.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [main.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [net_hubs.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [net_hubs_transitivity.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [outputs.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [remote.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/go-foundation/3-networks-hub-and-spoke/envs/shared/...`
