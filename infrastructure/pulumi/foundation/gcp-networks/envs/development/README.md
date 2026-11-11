# gcp-networks (3-networks-hub-and-spoke) / envs / development

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/envs/development`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/envs/development)
— the development spoke root of the networks stage. It pins the environment
identity (`development`/`d`) and its spoke CIDR plan, then calls the shared
`modules/base_env` orchestrator; the hub network lives in the sibling
`envs/shared` leaf.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | pinned identity/CIDR consts + `base_env` call |
| `variables.tf` | `config.go` | stack config (engine adaptation: tfvars → `Pulumi.<stack>.yaml`) |
| `outputs.tf` | `outputs.go` | spoke stack exports (VPC-SC exports emitted in `modules/shared_vpc`) |
| `remote.tf` | `remote.go` | 1-org StackReference (spoke + hub host projects) |
| `backend.tf`, `providers.tf`, `versions.tf` | `Pulumi.yaml`, `go.mod` | engine adaptation |

Deploy order: `shared` → `development` → `nonproduction` → `production`
(serializes hub-side peering mutations; see the note in `main.go`).

## Interface
- `[config.go:VpcFlowLogsConfig]`
- `[config.go:NetConfig]`

## Invariants
- [config.go:87]: `OrgID:        conf.Require("org_id"),`

## Side Effects
- [outputs.go:38]: `ctx.Export("network_name", net.VPC.Name)`
- [outputs.go:39]: `ctx.Export("network_self_link", net.VPC.SelfLink)`
- [outputs.go:41]: `// net.Subnets is a Go map, whose range order is randomized on every run.`

## Verification
- Run: `bazel test //infrastructure/pulumi/foundation/gcp-networks/envs/development/...`
