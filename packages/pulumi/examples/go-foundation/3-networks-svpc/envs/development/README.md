# 3-networks-svpc / envs / development

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-svpc/envs/development`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-svpc/envs/development)
— the development root of the networks stage. It pins the environment
identity (`development`/`d`) and calls the shared `modules/base_env`
orchestrator; all resource creation lives in `../../modules/base_env`. The
shared/global resources (hierarchical firewall) live in the sibling
`envs/shared` leaf.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | pinned identity consts + `base_env` call |
| `variables.tf` | `config.go` | stack config (engine adaptation: tfvars → `Pulumi.<stack>.yaml`) |
| `outputs.tf` | `outputs.go` | per-environment stack exports |
| `remote.tf` | `remote.go` | 1-org read happens in `modules/base_env` (documented there) |
| `backend.tf`, `providers.tf`, `versions.tf` | `Pulumi.yaml`, `go.mod` | engine adaptation |

## Interface
- `[config.go:VpcFlowLogsConfig]`
- `[config.go:NetConfig]`

## Invariants
- [config.go:70]: `ProjectID:    conf.Require("project_id"),`

## Side Effects
- [config.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [main.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [outputs.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [remote.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/go-foundation/3-networks-svpc/envs/development/...`
