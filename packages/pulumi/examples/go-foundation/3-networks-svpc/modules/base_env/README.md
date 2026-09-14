# modules / base_env

Pulumi (Go) port of upstream terraform-example-foundation
[`3-networks-svpc/modules/base_env`](https://github.com/terraform-google-modules/terraform-example-foundation/tree/master/3-networks-svpc/modules/base_env)
— the per-environment orchestrator for the Shared VPC, firewall, PSC, DNS,
routes, BGP routers, NAT, and the VPC-SC perimeter.

Pulumi-port note: upstream `base_env` composes a separate `shared_vpc`
module; this port keeps the Shared VPC resource composition inline here (a
single per-environment orchestrator) — a documented structural divergence
that preserves the original flat port's resource logical names so the envs/
split stays a preview no-op. See `../shared_vpc/README.md`.

## File map (upstream → this port)

| Upstream | Here | Notes |
|---|---|---|
| `main.tf` | `main.go` | `New` — full per-environment composition |
| `variables.tf` | `variables.go` | `Args` |
| `outputs.tf` | `outputs.go` | `Result` |
| `remote.tf` | `remote.go` | 1-org StackReference (ACM policy id) |
| `versions.tf` | `../go.mod` | engine adaptation |
| `interconnect.tf.example` | `interconnect.go.example` | rename-to-activate example |
| `partner_interconnect.tf.example` | `partner_interconnect.go.example` | rename-to-activate example |
| `vpn.tf.example` | `vpn.go.example` | rename-to-activate example |
