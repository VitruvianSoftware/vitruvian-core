# 3-networks-hub-and-spoke / envs / nonproduction

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/envs/nonproduction`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/envs/nonproduction)
— the nonproduction spoke root of the networks stage. It pins the environment
identity (`nonproduction`/`n`) and its spoke CIDR plan, then calls the shared
`modules/base_env` orchestrator; the hub network lives in the sibling
`envs/shared` leaf.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | pinned identity/CIDR consts + `base_env` call |
| `variables.tf` | `config.go` | stack config (engine adaptation: tfvars → `Pulumi.<stack>.yaml`) |
| `outputs.tf` | `outputs.go` | spoke stack exports (VPC-SC exports emitted in `modules/shared_vpc`) |
| `remote.tf` | `remote.go` | 1-org StackReference (hub host project) |
| `backend.tf`, `providers.tf`, `versions.tf` | `Pulumi.yaml`, `go.mod` | engine adaptation |

Deploy order: `shared` → `development` → `nonproduction` → `production`
(serializes hub-side peering mutations; see the note in `main.go`).
