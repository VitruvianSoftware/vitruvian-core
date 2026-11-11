# modules / base_env

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-hub-and-spoke/modules/base_env`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-hub-and-spoke/modules/base_env)
— the thin per-environment spoke orchestrator. It builds the spoke subnet
args (secondary ranges only on R1, matching upstream) and invokes the
`shared_vpc` module in "spoke" mode.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | `New` — subnet args + `shared_vpc` spoke call |
| `variables.tf` | `variables.go` | `Args` |
| `outputs.tf` | `outputs.go` | `Result` |
| `remote.tf` | `remote.go` | cross-stage reads happen at the leaf roots (documented there) |
| `versions.tf` | `../go.mod` | engine adaptation |
| `vpn.tf.example` | `vpn.go.example` | rename-to-activate HA-VPN example |

## Interface
- `[main.go:New]`
- `[outputs.go:Result]`
- `[variables.go:Args]`

## Invariants
- None

## Side Effects
- [main.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [outputs.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [remote.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`
- [variables.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/examples/go-foundation/3-networks-hub-and-spoke/modules/base_env/...`
